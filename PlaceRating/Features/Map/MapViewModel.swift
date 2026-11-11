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

    let user: SelfUser
    private let location: any LocationServiceProtocol
    private let socket: any LiveSocketProtocol
    private let people: [String: Person]
    private let clock: () -> Date
    private var throttle = SendThrottle()
    private var tasks: [Task<Void, Never>] = []

    init(
        user: SelfUser,
        location: any LocationServiceProtocol,
        socket: any LiveSocketProtocol,
        people: [Person],
        clock: @escaping () -> Date = { Date() }
    ) {
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
