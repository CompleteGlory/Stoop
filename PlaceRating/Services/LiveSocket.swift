import CoreLocation
import Foundation

/// A friend's last known position, stamped with when this phone received it.
struct FriendFix: Equatable, Sendable {
    let userId: String
    var latitude: Double
    var longitude: Double
    var heading: Double?
    var receivedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// What the `/live` socket tells the app (live-protocol.md).
enum LiveEvent: Equatable, Sendable {
    /// First frame after every connect: a snapshot that replaces what the app knew.
    case hello(ghost: Bool, friends: [FriendFix])
    case loc(FriendFix)
    case gone(userId: String)
    case ghost(Bool)
    case disconnected
    /// Another device (or an older socket of ours) took over the connection. Sharing is paused
    /// here until the app returns to the foreground.
    case replaced
    /// The server no longer accepts this session: sign out.
    case unauthorized
}

/// The live location connection: `LiveSocketClient` is the real `/live` WebSocket.
@MainActor
protocol LiveSocketProtocol: AnyObject {
    func connect() -> AsyncStream<LiveEvent>
    func disconnect()
    func send(_ location: CLLocation)
    func setGhost(_ on: Bool)
}

/// Friends' positions and staleness rules: `hello` replaces, `loc` upserts, `gone` removes.
/// A friend dims after 30 s without an update and disappears after 60 s, so a dropped
/// connection never leaves a frozen marker on the map.
struct FriendsState: Equatable {
    static let dimAfter: TimeInterval = 30
    static let removeAfter: TimeInterval = 60

    private(set) var fixes: [String: FriendFix] = [:]

    mutating func apply(_ event: LiveEvent) {
        switch event {
        case .hello(_, let friends):
            fixes = Dictionary(friends.map { ($0.userId, $0) }, uniquingKeysWith: { _, newer in newer })
        case .loc(let fix):
            fixes[fix.userId] = fix
        case .gone(let userId):
            fixes[userId] = nil
        case .ghost, .disconnected, .replaced, .unauthorized:
            break
        }
    }

    /// Drops friends not heard from for a minute. Returns whether anyone was dropped.
    @discardableResult
    mutating func prune(now: Date) -> Bool {
        let kept = fixes.filter { now.timeIntervalSince($0.value.receivedAt) < Self.removeAfter }
        guard kept.count != fixes.count else { return false }
        fixes = kept
        return true
    }

    /// The friends who should look dimmed right now.
    func dimmedIds(now: Date) -> Set<String> {
        Set(fixes.keys.filter { isDimmed($0, now: now) })
    }

    func isDimmed(_ userId: String, now: Date) -> Bool {
        guard let fix = fixes[userId] else { return false }
        return now.timeIntervalSince(fix.receivedAt) >= Self.dimAfter
    }
}

/// A friend as the map draws them: friends come from `GET /friends`, positions from the socket.
struct Person: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let avatar: Avatar?
}
