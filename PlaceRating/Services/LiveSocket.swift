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
}

/// The live location connection. The real `/live` WebSocket arrives in milestone 8;
/// until then `MockLiveSocket` plays friends walking around.
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
        case .ghost, .disconnected:
            break
        }
    }

    mutating func prune(now: Date) {
        fixes = fixes.filter { now.timeIntervalSince($0.value.receivedAt) < Self.removeAfter }
    }

    func isDimmed(_ userId: String, now: Date) -> Bool {
        guard let fix = fixes[userId] else { return false }
        return now.timeIntervalSince(fix.receivedAt) >= Self.dimAfter
    }
}

/// A person the app can show: friends come from `GET /friends` later; the mock invents them.
struct Person: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let avatar: Avatar?
}

/// Fake friends who stroll around near you, one of whom goes quiet now and then so the
/// dim-and-remove rules can be seen. Used until the real socket lands in milestone 8.
@MainActor
final class MockLiveSocket: LiveSocketProtocol {
    static let people: [Person] = [
        Person(id: "mock-nia", name: "nia", avatar: .sampleNia),
        Person(id: "mock-omar", name: "omar", avatar: .sampleOmar),
        Person(id: "mock-sara", name: "sara", avatar: .sampleSara),
        Person(id: "mock-yusuf", name: "yusuf", avatar: Avatar(style: "personas", options: [
            "hair": "fade", "hairColor": "362c47", "skinColor": "b16a5b", "eyes": "happy", "mouth": "smile",
            "body": "rounded", "clothingColor": "6dbb58", "facialHair": "none", "nose": "smallRound",
        ])),
    ]

    private var continuation: AsyncStream<LiveEvent>.Continuation?
    private var walker: Task<Void, Never>?
    private var center = CLLocationCoordinate2D(latitude: 30.0444, longitude: 31.2357)
    private var hasRealCenter = false
    private var positions: [String: CLLocationCoordinate2D] = [:]
    private let tick: Duration

    init(tick: Duration = .seconds(2)) {
        self.tick = tick
    }

    func connect() -> AsyncStream<LiveEvent> {
        disconnect()
        let (stream, continuation) = AsyncStream<LiveEvent>.makeStream()
        self.continuation = continuation
        placeFriends()
        continuation.yield(.hello(ghost: false, friends: Self.people.map { fix(for: $0.id) }))
        walker = Task { [weak self] in await self?.walk() }
        return stream
    }

    func disconnect() {
        walker?.cancel()
        walker = nil
        continuation?.finish()
        continuation = nil
    }

    func send(_ location: CLLocation) {
        guard !hasRealCenter else { return }
        // the first real fix: move the friends from the default spot to around you
        hasRealCenter = true
        center = location.coordinate
        placeFriends()
        for person in Self.people { continuation?.yield(.loc(fix(for: person.id))) }
    }

    func setGhost(_ on: Bool) {
        continuation?.yield(.ghost(on))
    }

    private func placeFriends() {
        for (index, person) in Self.people.enumerated() {
            let angle = Double(index) / Double(Self.people.count) * 2 * .pi
            positions[person.id] = offset(center, north: cos(angle) * 220, east: sin(angle) * 220)
        }
    }

    private func walk() async {
        var step = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: tick)
            guard !Task.isCancelled else { return }
            step += 1
            for person in Self.people {
                // yusuf goes quiet for about 70 s out of every 100 s, so he dims and then disappears
                if person.id == "mock-yusuf", step % 50 >= 15 { continue }
                if let here = positions[person.id] {
                    positions[person.id] = offset(here, north: .random(in: -14...14), east: .random(in: -14...14))
                }
                continuation?.yield(.loc(fix(for: person.id)))
            }
        }
    }

    private func fix(for id: String) -> FriendFix {
        let here = positions[id] ?? center
        return FriendFix(userId: id, latitude: here.latitude, longitude: here.longitude, heading: nil, receivedAt: Date())
    }

    private func offset(_ from: CLLocationCoordinate2D, north: Double, east: Double) -> CLLocationCoordinate2D {
        let metersPerDegree = 111_320.0
        return CLLocationCoordinate2D(
            latitude: from.latitude + north / metersPerDegree,
            longitude: from.longitude + east / (metersPerDegree * cos(from.latitude * .pi / 180))
        )
    }
}
