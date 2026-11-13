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
        case settings
        case place
        case friends
        case blocked
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

    static let smallDetent = PresentationDetent.height(160)

    var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    var sheet: Sheet = .browse
    var detent: PresentationDetent = MapViewModel.smallDetent
    var showsLocationPrompt = false
    private(set) var me: CLLocationCoordinate2D?
    private(set) var friends = FriendsState()
    private(set) var ghost: Bool
    private(set) var access: LocationAccess
    private(set) var isConnected = false
    /// The connection dropped after having worked: show the offline banner and dim markers.
    private(set) var connectionLost = false
    /// Another device took over the connection; sharing from here resumes on the next foreground.
    private(set) var isPaused = false
    /// The search field in the bottom sheet.
    let search: PlaceSearchViewModel
    /// Reports and blocks, shared by every screen that shows other people's content.
    let safety: SafetyViewModel
    private(set) var visibleRegion: MKCoordinateRegion?
    /// The clock as of the last tick. Not observed: the map only redraws when what it shows changes.
    @ObservationIgnored private var now: Date
    /// Friends not heard from for 30 s; updated only when the set changes.
    private(set) var dimmedFriendIds: Set<String> = []
    /// Rated places in the visible area (the API also returns unrated ones; those get no pin).
    private(set) var places: [Place] = []
    /// A point of interest the person tapped on the map.
    /// What is selected on the map: one of Apple's points of interest (iOS 18 `MapSelection`).
    var mapSelection: MapSelection<String>?
    private(set) var placeModel: PlaceViewModel?
    /// Your accepted friends and requests, from the API (positions come from the live socket).
    private(set) var friendsList = FriendsList(friends: [], incoming: [], outgoing: [])
    private(set) var friendsModel: FriendsViewModel?

    let user: SelfUser
    private let location: any LocationServiceProtocol
    private let socket: any LiveSocketProtocol
    private let onSessionExpired: () -> Void
    private var lastLocation: CLLocation?
    private var isRefreshingFriends = false
    private var askedAboutFriends: Set<String> = []
    private let clock: () -> Date
    private let placesAPI: any PlacesAPI
    private let friendsAPI: any FriendsAPI
    private let photosAPI: any PhotosAPI
    private let placesDebounce: Duration
    private let placesCache: PlacesChunkCache
    private var visibleCells: [HexCell] = []
    /// Where you have been standing still, and since when; preloading happens once per spot.
    private var restingSpot: (location: CLLocation, since: Date, preloaded: Bool)?
    private var placesTask: Task<Void, Never>?
    private var throttle = SendThrottle()
    private var tasks: [Task<Void, Never>] = []

    init(
        user: SelfUser,
        location: any LocationServiceProtocol,
        socket: any LiveSocketProtocol,
        onSessionExpired: @escaping () -> Void = {},
        places: any PlacesAPI = UnavailablePlacesAPI(),
        placesCache: PlacesChunkCache? = nil,
        friendsAPI: any FriendsAPI = UnavailableFriendsAPI(),
        photosAPI: any PhotosAPI = UnavailablePhotosAPI(),
        moderationAPI: any ModerationAPI = UnavailableModerationAPI(),
        searcher: any PlaceSearching = MapKitPlaceSearch(),
        searchDebounce: Duration = .milliseconds(400),
        placesDebounce: Duration = .milliseconds(400),
        clock: @escaping () -> Date = { Date() }
    ) {
        self.placesAPI = places
        self.friendsAPI = friendsAPI
        self.photosAPI = photosAPI
        self.placesDebounce = placesDebounce
        self.placesCache = placesCache ?? PlacesChunkCache(api: places)
        self.user = user
        self.location = location
        self.socket = socket
        self.onSessionExpired = onSessionExpired
        search = PlaceSearchViewModel(searcher: searcher, debounce: searchDebounce)
        safety = SafetyViewModel(api: moderationAPI)
        self.clock = clock
        ghost = user.ghostMode
        access = location.access
        now = clock()
        location.onAccessChange = { [weak self] access in self?.accessChanged(access) }
        search.setRegionProvider { [weak self] in self?.visibleRegion }
        safety.onBlocked = { [weak self] userId in self?.personBlocked(userId) }
        self.placesCache.onUpdate = { [weak self] in self?.refreshPins() }
    }

    var visibleFriends: [VisibleFriend] {
        let people = Dictionary(
            friendsList.friends.map { ($0.user.id, Person(id: $0.user.id, name: $0.user.name, avatar: $0.user.avatar)) },
            uniquingKeysWith: { first, _ in first }
        )
        return friends.fixes.values
            .compactMap { fix in
                people[fix.userId].map {
                    VisibleFriend(
                        person: $0, coordinate: fix.coordinate,
                        isDimmed: connectionLost || dimmedFriendIds.contains(fix.userId)
                    )
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
        // back in the foreground: requests may have been sent or cancelled while away
        tasks.append(Task { [weak self] in await self?.friendsChanged() })
        let events = socket.connect()
        isPaused = false
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

    func showSettings() {
        sheet = .settings
        detent = .large
    }

    func showBlocked() {
        sheet = .blocked
        detent = .large
    }

    /// The server also drops a blocked person from the friend graph and the live socket;
    /// do the same here without waiting for it.
    private func personBlocked(_ userId: String) {
        friends.apply(.gone(userId: userId))
        friendsList = FriendsList(
            friends: friendsList.friends.filter { $0.user.id != userId },
            incoming: friendsList.incoming.filter { $0.user.id != userId },
            outgoing: friendsList.outgoing.filter { $0.user.id != userId }
        )
        Task { await loadFriends() }
    }

    func showBrowse() {
        sheet = .browse
        // back to the small sheet, so the map (and your avatar) can be tapped again
        detent = Self.smallDetent
        placeModel = nil
        friendsModel = nil
        mapSelection = nil
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

    /// Friends or requests changed (a push, a `friends` frame, back from the background): reload the
    /// list, and the open friends sheet with it, search results included.
    func friendsChanged() async {
        if let friendsModel { await friendsModel.refresh() } else { await loadFriends() }
    }

    /// Where a friend is right now, if they are sharing.
    func liveFriend(_ userId: String) -> VisibleFriend? {
        visibleFriends.first { $0.id == userId }
    }

    // MARK: places

    /// Called when the camera settles. Pins for the hexagons in view come from the cache at once;
    /// after a short pause, whatever is missing or stale is fetched in one request.
    func cameraSettled(center: CLLocationCoordinate2D, latitudeDelta: Double, longitudeDelta: Double) {
        let region = MKCoordinateRegion(
            center: center, span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
        visibleRegion = region
        placesTask?.cancel()
        guard let cells = HexGrid.cells(covering: region) else {
            return // zoomed out too far to ask; keep what is shown
        }
        visibleCells = cells
        refreshPins()
        placesTask = Task { [placesCache, placesDebounce] in
            try? await Task.sleep(for: placesDebounce)
            guard !Task.isCancelled else { return }
            await placesCache.load(cells)
        }
    }

    /// Waits for a pending places request. Used by tests.
    func waitForPlaces() async {
        await placesTask?.value
    }

    /// The pins: rated places in the hexagons on screen.
    private func refreshPins() {
        var seen = Set<String>()
        places = placesCache.places(in: visibleCells).filter { $0.ratingCount > 0 && seen.insert($0.id).inserted }
    }

    /// A point of interest was tapped on the map: its sheet opens at once with what the map
    /// knows, and the details (Apple's lookup, then our server) fill in while it is open.
    func select(_ feature: MapFeature) async {
        guard feature.kind == .pointOfInterest else {
            mapSelection = nil
            return
        }
        let preview = PlacePreview(name: feature.title ?? "", category: feature.pointOfInterestCategory?.rawValue)
        let coordinate = feature.coordinate
        openPreview(preview) { [placesAPI] in
            let item = try? await MKMapItemRequest(feature: feature).mapItem
            return try await placesAPI.resolvePlace(
                appleId: item?.identifier?.rawValue,
                name: item?.name ?? preview.name,
                category: (item?.pointOfInterestCategory ?? feature.pointOfInterestCategory)?.rawValue,
                latitude: coordinate.latitude, longitude: coordinate.longitude
            )
        }
    }

    /// A search result was tapped: fly there and open its place sheet.
    func openSearchResult(_ result: PlaceSearchResult) async {
        search.clear()
        withAnimation {
            camera = .region(MKCoordinateRegion(center: result.coordinate, latitudinalMeters: 500, longitudinalMeters: 500))
        }
        openPreview(PlacePreview(name: result.name, category: result.category)) { [placesAPI] in
            try await placesAPI.resolvePlace(
                appleId: result.appleId, name: result.name, category: result.category,
                latitude: result.latitude, longitude: result.longitude
            )
        }
    }

    /// Opens the sheet for a place the server may not know yet.
    func openPreview(_ preview: PlacePreview, resolve: @escaping () async throws -> Place) {
        placeModel = PlaceViewModel(
            preview: preview, resolve: resolve, api: placesAPI, myId: user.id, photosAPI: photosAPI, safety: safety
        ) { [weak self] updated in
            self?.placeChanged(updated)
        }
        sheet = .place
        detent = .medium
    }

    func open(_ place: Place) { open(placeId: place.id) }

    /// A shared link or a tapped notification. A place opens its sheet at once and the map flies
    /// there once it is known; a friend is shown on the map when they are sharing, otherwise the
    /// friends list opens.
    func openShared(_ link: DeepLink) {
        let id: String
        switch link {
        case .friends:
            showFriends()
            return
        case .friend(let friendId):
            if let friend = liveFriend(friendId) {
                showBrowse()
                focus(on: friend)
            } else {
                showFriends()
            }
            return
        case .place(let placeId):
            id = placeId
        }
        search.clear()
        open(placeId: id)
        placeModel?.onFirstLoad = { [weak self] place in
            withAnimation {
                self?.camera = .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 600, longitudinalMeters: 600))
            }
        }
    }

    private func open(placeId: String) {
        placeModel = PlaceViewModel(placeId: placeId, api: placesAPI, myId: user.id, photosAPI: photosAPI, safety: safety) { [weak self] updated in
            self?.placeChanged(updated)
        }
        sheet = .place
        detent = .medium
    }

    /// Keeps the pins in step with ratings made in the sheet.
    func placeChanged(_ place: Place) {
        placesCache.update(place)
        places.removeAll { $0.id == place.id }
        if place.ratingCount > 0 { places.append(place) }
    }

    // MARK: events

    func handle(_ event: LiveEvent) {
        switch event {
        case .hello(let isGhost, let known):
            ghost = isGhost
            isConnected = true
            connectionLost = false
            isPaused = false
            refreshFriendsIfUnknown(known.map(\.userId))
            // a new connection starts clean: tell friends where you are right away
            throttle = SendThrottle()
            if let lastLocation { sendIfDue(lastLocation) }
        case .loc(let fix):
            refreshFriendsIfUnknown([fix.userId])
        case .ghost(let on):
            ghost = on
        case .friendsChanged:
            Task { await friendsChanged() }
        case .disconnected:
            isConnected = false
            connectionLost = true
        case .replaced:
            isConnected = false
            isPaused = true
        case .unauthorized:
            isConnected = false
            onSessionExpired()
        case .gone:
            break
        }
        friends.apply(event)
        refreshDimmed()
    }

    private func refreshDimmed() {
        let dimmed = friends.dimmedIds(now: now)
        if dimmed != dimmedFriendIds { dimmedFriendIds = dimmed }
    }

    func tick() {
        now = clock()
        // work on a copy: writing the observed state every second would redraw the whole map
        var pruned = friends
        if pruned.prune(now: now) { friends = pruned }
        refreshDimmed()
        preloadIfResting()
        // standing still: the server forgets you after 60 s, so repeat the last position every 15 s
        if isConnected, let lastLocation { sendIfDue(lastLocation) }
    }

    func received(_ position: CLLocation) {
        let first = lastLocation == nil
        me = position.coordinate
        lastLocation = position
        sendIfDue(position)
        noteMovement(position, first: first)
    }

    // MARK: preloading

    /// Standing still this long preloads the wider area around you.
    static let restBeforePreload: TimeInterval = 20
    static let restingRadius: CLLocationDistance = 40

    private func noteMovement(_ position: CLLocation, first: Bool) {
        if first {
            // the first fix: fill the hexagons around you right away
            Task { [placesCache] in await placesCache.preload(around: position.coordinate, radius: 2) }
        }
        if let spot = restingSpot, position.distance(from: spot.location) < Self.restingRadius { return }
        restingSpot = (position, clock(), false)
    }

    /// Called every second by the ticker: after you have stood still for a while, preload a
    /// wider ring of hexagons and warm the map's tiles around you.
    private func preloadIfResting() {
        guard let spot = restingSpot, !spot.preloaded,
              clock().timeIntervalSince(spot.since) >= Self.restBeforePreload else { return }
        restingSpot?.preloaded = true
        let coordinate = spot.location.coordinate
        Task { [placesCache] in await placesCache.preload(around: coordinate, radius: 4) }
        MapWarmer.warmTiles(around: coordinate)
    }

    private func sendIfDue(_ position: CLLocation) {
        let at = clock()
        guard !ghost, throttle.shouldSend(position, now: at) else { return }
        throttle.didSend(position, at: at)
        socket.send(position)
    }

    /// Someone you just became friends with can show up on the socket before the friends list knows them.
    private func refreshFriendsIfUnknown(_ ids: [String]) {
        let known = Set(friendsList.friends.map(\.user.id))
        let unknown = Set(ids).subtracting(known).subtracting(askedAboutFriends)
        guard !isRefreshingFriends, !unknown.isEmpty else { return }
        askedAboutFriends.formUnion(unknown) // ask once per person, not on every position
        isRefreshingFriends = true
        Task {
            await loadFriends()
            isRefreshingFriends = false
        }
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
