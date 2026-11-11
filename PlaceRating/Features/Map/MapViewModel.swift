import CoreLocation
import MapKit
import Observation
import SwiftUI

/// The one screen's state: your position, friends' positions, ghost mode and the bottom sheet.
/// Views only read it and call its methods.
@MainActor
@Observable
final class MapViewModel {
    enum Sheet: Equatable {
        case browse
        case profile
        case place(String)
        case friends
    }

    struct VisibleFriend: Identifiable, Equatable {
        let person: Person
        let coordinate: CLLocationCoordinate2D
        let isDimmed: Bool
        var id: String { person.id }

        static func == (a: Self, b: Self) -> Bool {
            a.person == b.person && a.isDimmed == b.isDimmed
                && a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude
        }
    }

    static let smallDetent = PresentationDetent.height(150)

    var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    var sheet: Sheet = .browse
    var detent: PresentationDetent = MapViewModel.smallDetent
    var showsLocationPrompt = false
    private(set) var me: CLLocationCoordinate2D?
    private(set) var friends = FriendsState()
    private(set) var ghost: Bool
    private(set) var access: LocationAccess
    private(set) var isConnected = false
    private(set) var now: Date
    /// Rated places in the visible area (the API also returns unrated ones; those get no pin).
    private(set) var places: [Place] = []
    /// A point of interest the person tapped on the map.
    var selectedFeature: MapFeature?
    private(set) var placeModel: PlaceViewModel?
    private(set) var isResolvingPlace = false
    private(set) var placeErrorText: String?
    /// Your accepted friends and requests, from the API (positions come from the live socket).
    private(set) var friendsList = FriendsList(friends: [], incoming: [], outgoing: [])
    private(set) var friendsModel: FriendsViewModel?

    let user: SelfUser
    private let location: any LocationServiceProtocol
    private let socket: any LiveSocketProtocol
    private let people: [String: Person]
    private let clock: () -> Date
    private let placesAPI: any PlacesAPI
    private let friendsAPI: any FriendsAPI
    private let placesDebounce: Duration
    private var placesTask: Task<Void, Never>?
    private var throttle = SendThrottle()
    private var tasks: [Task<Void, Never>] = []

    init(
        user: SelfUser,
        location: any LocationServiceProtocol,
        socket: any LiveSocketProtocol,
        people: [Person],
        places: any PlacesAPI = UnavailablePlacesAPI(),
        friendsAPI: any FriendsAPI = UnavailableFriendsAPI(),
        placesDebounce: Duration = .milliseconds(400),
        clock: @escaping () -> Date = { Date() }
    ) {
        self.placesAPI = places
        self.friendsAPI = friendsAPI
        self.placesDebounce = placesDebounce
        self.user = user
        self.location = location
        self.socket = socket
        self.people = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.clock = clock
        ghost = user.ghostMode
        access = location.access
        now = clock()
        location.onAccessChange = { [weak self] access in self?.accessChanged(access) }
    }

    var visibleFriends: [VisibleFriend] {
        friends.fixes.values
            .compactMap { fix in
                people[fix.userId].map {
                    VisibleFriend(person: $0, coordinate: fix.coordinate, isDimmed: friends.isDimmed(fix.userId, now: now))
                }
            }
            .sorted { $0.person.name < $1.person.name }
    }

    /// Friends who can see you right now (none while you are a ghost).
    var sharingCount: Int { ghost ? 0 : friends.fixes.count }

    /// Starts location, the live connection and the staleness ticker. Called when the screen
    /// appears and whenever the app comes back to the foreground.
    func start() {
        guard tasks.isEmpty else { return }
        if access == .unknown { showsLocationPrompt = true }
        if access == .allowed { startLocation() }
        tasks.append(Task { [weak self] in await self?.loadFriends() })
        let events = socket.connect()
        tasks.append(Task { [weak self] in
            for await event in events { self?.handle(event) }
        })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        })
    }

    /// Sharing only happens while the app is open: stop everything when it leaves the foreground.
    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        socket.disconnect()
        isConnected = false
    }

    func allowLocation() {
        showsLocationPrompt = false
        location.requestAccess()
    }

    func dismissLocationPrompt() {
        showsLocationPrompt = false
    }

    func toggleGhost() {
        ghost.toggle()
        socket.setGhost(ghost)
    }

    func recenter() {
        withAnimation { camera = .userLocation(fallback: .automatic) }
    }

    func focus(on friend: VisibleFriend) {
        withAnimation {
            camera = .region(MKCoordinateRegion(center: friend.coordinate, latitudinalMeters: 600, longitudinalMeters: 600))
        }
        detent = Self.smallDetent
    }

    func showProfile() {
        sheet = .profile
        detent = .medium
    }

    func showBrowse() {
        sheet = .browse
        placeModel = nil
        friendsModel = nil
        selectedFeature = nil
    }

    // MARK: friends

    func showFriends() {
        friendsModel = FriendsViewModel(api: friendsAPI) { [weak self] list in self?.friendsList = list }
        sheet = .friends
        detent = .large
    }

    func loadFriends() async {
        if let list = try? await friendsAPI.friends() { friendsList = list }
    }

    /// Where a friend is right now, if they are sharing.
    func liveFriend(_ userId: String) -> VisibleFriend? {
        visibleFriends.first { $0.id == userId }
    }

    // MARK: places

    /// Called when the camera settles: after a short pause, loads the rated places in view.
    func cameraSettled(center: CLLocationCoordinate2D, latitudeDelta: Double, longitudeDelta: Double) {
        placesTask?.cancel()
        guard let box = BoundingBox(center: center, latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta) else {
            return // zoomed out too far to ask; keep what is shown
        }
        placesTask = Task { [placesAPI, placesDebounce] in
            try? await Task.sleep(for: placesDebounce)
            guard !Task.isCancelled, let found = try? await placesAPI.places(in: box) else { return }
            self.places = found.filter { $0.ratingCount > 0 }
        }
    }

    /// Waits for a pending places request. Used by tests.
    func waitForPlaces() async {
        await placesTask?.value
    }

    /// A point of interest was tapped on the map: ask Apple Maps for its details, then resolve it.
    func select(_ feature: MapFeature) async {
        guard feature.kind == .pointOfInterest else {
            selectedFeature = nil
            return
        }
        let item = try? await MKMapItemRequest(feature: feature).mapItem
        let name = item?.name ?? feature.title ?? ""
        guard !name.isEmpty else { return }
        await resolve(
            appleId: item?.identifier?.rawValue,
            name: name,
            category: (item?.pointOfInterestCategory ?? feature.pointOfInterestCategory)?.rawValue,
            coordinate: feature.coordinate
        )
    }

    /// Finds or creates the place for a point of interest, then opens it.
    func resolve(appleId: String?, name: String, category: String?, coordinate: CLLocationCoordinate2D) async {
        isResolvingPlace = true
        placeErrorText = nil
        defer { isResolvingPlace = false }
        do {
            let place = try await placesAPI.resolvePlace(
                appleId: appleId, name: name, category: category,
                latitude: coordinate.latitude, longitude: coordinate.longitude
            )
            open(place)
        } catch {
            placeErrorText = ErrorText.text(for: error)
        }
    }

    func open(_ place: Place) {
        placeModel = PlaceViewModel(placeId: place.id, api: placesAPI, myId: user.id) { [weak self] updated in
            self?.placeChanged(updated)
        }
        sheet = .place(place.id)
        detent = .medium
    }

    /// Keeps the pins in step with ratings made in the sheet.
    func placeChanged(_ place: Place) {
        places.removeAll { $0.id == place.id }
        if place.ratingCount > 0 { places.append(place) }
    }

    // MARK: events

    func handle(_ event: LiveEvent) {
        switch event {
        case .hello(let isGhost, _):
            ghost = isGhost
            isConnected = true
        case .ghost(let on):
            ghost = on
        case .disconnected:
            isConnected = false
        case .loc, .gone:
            break
        }
        friends.apply(event)
    }

    func tick() {
        now = clock()
        friends.prune(now: now)
    }

    func received(_ position: CLLocation) {
        me = position.coordinate
        let at = clock()
        guard !ghost, throttle.shouldSend(position, now: at) else { return }
        throttle.didSend(position, at: at)
        socket.send(position)
    }

    private func startLocation() {
        let updates = location.updates()
        tasks.append(Task { [weak self] in
            for await position in updates { self?.received(position) }
        })
    }

    private func accessChanged(_ newAccess: LocationAccess) {
        let wasAllowed = access == .allowed
        access = newAccess
        if newAccess == .allowed, !wasAllowed, !tasks.isEmpty { startLocation() }
    }
}
