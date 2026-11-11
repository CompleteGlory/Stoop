import CoreLocation
import Foundation
import Testing
@testable import PlaceRating

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func hello(ghost: Bool = false, friends: String = "[]") -> String {
    #"{"t":"hello","d":{"userId":"me","ghost":\#(ghost),"friends":\#(friends),"serverTime":1800000000000}}"#
}

private let friendJSON = #"{"userId":"u1","lat":30.5,"lng":31.25,"accuracy":10,"heading":90,"ts":1800000000000}"#

struct LiveFrameTests {
    @Test func readsHelloWithFriends() throws {
        let event = try #require(LiveFrame.decode(hello(friends: "[\(friendJSON)]"), receivedAt: t0))
        guard case .hello(let ghost, let friends) = event else { Issue.record("not a hello"); return }
        #expect(!ghost)
        #expect(friends.count == 1)
        #expect(friends[0].userId == "u1")
        #expect(friends[0].latitude == 30.5)
        #expect(friends[0].longitude == 31.25)
        #expect(friends[0].heading == 90)
        #expect(friends[0].receivedAt == t0)
    }

    @Test func readsLocGoneAndGhost() {
        #expect(LiveFrame.decode(#"{"t":"loc","d":\#(friendJSON)}"#, receivedAt: t0)
            == .loc(FriendFix(userId: "u1", latitude: 30.5, longitude: 31.25, heading: 90, receivedAt: t0)))
        #expect(LiveFrame.decode(#"{"t":"gone","d":{"userId":"u1"}}"#, receivedAt: t0) == .gone(userId: "u1"))
        #expect(LiveFrame.decode(#"{"t":"ghost","d":{"on":true}}"#, receivedAt: t0) == .ghost(true))
    }

    @Test func unknownHeadingsBecomeNil() {
        let minusOne = #"{"t":"loc","d":{"userId":"u","lat":1,"lng":2,"accuracy":5,"heading":-1,"ts":1}}"#
        let missing = #"{"t":"loc","d":{"userId":"u","lat":1,"lng":2,"accuracy":5,"heading":null,"ts":1}}"#
        for text in [minusOne, missing] {
            guard case .loc(let fix)? = LiveFrame.decode(text, receivedAt: t0) else { Issue.record("not a loc"); return }
            #expect(fix.heading == nil)
        }
    }

    @Test func ignoresErrorsUnknownTypesAndGarbage() {
        #expect(LiveFrame.decode(#"{"t":"error","d":{"code":"invalid_loc","message":"x"}}"#, receivedAt: t0) == nil)
        #expect(LiveFrame.decode(#"{"t":"mystery","d":{}}"#, receivedAt: t0) == nil)
        #expect(LiveFrame.decode(#"{"t":"loc"}"#, receivedAt: t0) == nil)
        #expect(LiveFrame.decode("not json", receivedAt: t0) == nil)
    }

    @Test func writesLocAndGhostFrames() throws {
        let position = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 30.5, longitude: 31.25), altitude: 0,
            horizontalAccuracy: 12, verticalAccuracy: 0, course: 270, speed: 1, timestamp: t0
        )
        let loc = try #require(JSONSerialization.jsonObject(with: Data(LiveFrame.location(position, now: t0).utf8)) as? [String: Any])
        #expect(loc["t"] as? String == "loc")
        let d = try #require(loc["d"] as? [String: Any])
        #expect(d["lat"] as? Double == 30.5)
        #expect(d["lng"] as? Double == 31.25)
        #expect(d["accuracy"] as? Double == 12)
        #expect(d["heading"] as? Double == 270)
        #expect(d["ts"] as? Int == 1_800_000_000_000)

        let still = CLLocation(coordinate: position.coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 0,
                               course: -1, speed: -1, timestamp: t0)
        let still2 = try #require(JSONSerialization.jsonObject(with: Data(LiveFrame.location(still, now: t0).utf8)) as? [String: Any])
        #expect((still2["d"] as? [String: Any])?["heading"] as? Double == -1)

        #expect(LiveFrame.ghost(true) == #"{"d":{"on":true},"t":"ghost"}"#)
    }
}

struct LiveBackoffTests {
    @Test func doublesFrom1SecondUpTo30WithJitter() {
        let seconds = (0..<8).map { LiveSocketClient.backoff(attempt: $0, jitter: 1) }
        #expect(seconds == [1, 2, 4, 8, 16, 30, 30, 30].map { Duration.milliseconds($0 * 1000) })
        #expect(LiveSocketClient.backoff(attempt: 2, jitter: 0.8) == .milliseconds(3200))
        #expect(LiveSocketClient.backoff(attempt: 2, jitter: 1.2) == .milliseconds(4800))
    }
}

// MARK: fakes

/// A scripted connection: plays its steps in order, then waits until it is closed.
final class FakeConnection: LiveConnection, @unchecked Sendable {
    enum Step {
        case frame(String)
        case end(closeCode: Int?, status: Int? = nil)
    }

    private let lock = NSLock()
    private var steps: [Step]
    private var _sent: [String] = []
    private var _closed = false
    private var _closeCode: Int?
    private var _status: Int?
    let request: URLRequest

    init(_ steps: [Step], request: URLRequest = URLRequest(url: URL(string: "ws://test/live")!)) {
        self.steps = steps
        self.request = request
    }

    var sent: [String] { lock.withLock { _sent } }
    var closed: Bool { lock.withLock { _closed } }
    var closeCode: Int? { lock.withLock { _closeCode } }
    var handshakeStatus: Int? { lock.withLock { _status } }

    func send(_ text: String) async throws { lock.withLock { _sent.append(text) } }
    func close() { lock.withLock { _closed = true } }

    func receive() async throws -> String {
        let step: Step? = lock.withLock { steps.isEmpty ? nil : steps.removeFirst() }
        switch step {
        case .frame(let text)?:
            return text
        case .end(let code, let status)?:
            lock.withLock { _closeCode = code; _status = status }
            throw URLError(.networkConnectionLost)
        case nil:
            try await Task.sleep(for: .seconds(3600)) // stays open until the test cancels us
            throw CancellationError()
        }
    }
}

final class FakeConnector: LiveConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [[FakeConnection.Step]]
    private var _opened: [FakeConnection] = []

    init(_ connections: [[FakeConnection.Step]]) { queue = connections }

    var opened: [FakeConnection] { lock.withLock { _opened } }

    func open(_ request: URLRequest) -> any LiveConnection {
        lock.withLock {
            let connection = FakeConnection(queue.isEmpty ? [] : queue.removeFirst(), request: request)
            _opened.append(connection)
            return connection
        }
    }
}

final class FakeLiveAuth: LiveAuth, @unchecked Sendable {
    private let lock = NSLock()
    private var _rejected: [String?] = []
    private var count = 0
    var failWith: Error?

    var rejected: [String?] { lock.withLock { _rejected } }

    func liveAccessToken(replacing rejected: String?) async throws -> String {
        try lock.withLock {
            _rejected.append(rejected)
            if let failWith { throw failWith }
            count += 1
            return "token-\(count)"
        }
    }
}

final class Pauses: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Duration] = []
    var values: [Duration] { lock.withLock { _values } }
    func record(_ value: Duration) { lock.withLock { _values.append(value) } }
}

@MainActor
private func makeClient(
    _ connector: FakeConnector, auth: FakeLiveAuth = FakeLiveAuth(), pauses: Pauses = Pauses()
) -> LiveSocketClient {
    LiveSocketClient(
        url: { URL(string: "ws://test/live")! }, auth: auth, connector: connector,
        pause: { pauses.record($0) }, jitter: { 1 }, now: { t0 }
    )
}

/// The next `count` events, or fewer if the stream ends first.
@MainActor
private func events(_ stream: AsyncStream<LiveEvent>, _ count: Int) async -> [LiveEvent] {
    var result: [LiveEvent] = []
    var iterator = stream.makeAsyncIterator()
    while result.count < count, let event = await iterator.next() { result.append(event) }
    return result
}

private func position(_ lat: Double = 30) -> CLLocation {
    CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: 31), altitude: 0,
               horizontalAccuracy: 10, verticalAccuracy: 0, timestamp: t0)
}

@MainActor
struct LiveSocketClientTests {
    @Test func connectsWithTheTokenAndPassesEventsOn() async throws {
        let connector = FakeConnector([[.frame(hello(friends: "[\(friendJSON)]")), .frame(#"{"t":"gone","d":{"userId":"u1"}}"#)]])
        let client = makeClient(connector)
        let received = await events(client.connect(), 2)
        client.disconnect()

        guard case .hello(_, let friends)? = received.first else { Issue.record("no hello"); return }
        #expect(friends.map(\.userId) == ["u1"])
        #expect(received.last == .gone(userId: "u1"))
        let request = try #require(connector.opened.first?.request)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(connector.opened.first?.closed == true)
    }

    @Test func reconnectsWithGrowingBackoffAndResetsAfterHello() async {
        let connector = FakeConnector([
            [.end(closeCode: nil)], // never got in
            [.end(closeCode: 1006)], // never got in again
            [.frame(hello()), .end(closeCode: 1011)], // worked, then dropped
            [.frame(hello())],
        ])
        let pauses = Pauses()
        let client = makeClient(connector, pauses: pauses)
        let received = await events(client.connect(), 5)
        client.disconnect()

        let names = received.map { event -> String in
            switch event {
            case .hello: "hello"
            case .disconnected: "disconnected"
            default: "other"
            }
        }
        #expect(names == ["disconnected", "disconnected", "hello", "disconnected", "hello"])
        #expect(pauses.values == [.seconds(1), .seconds(2), .seconds(1)])
        #expect(connector.opened.count == 4)
    }

    @Test func refreshesARefusedTokenOnceThenSignsOut() async {
        let connector = FakeConnector([[.end(closeCode: nil, status: 401)], [.end(closeCode: nil, status: 401)]])
        let auth = FakeLiveAuth()
        let client = makeClient(connector, auth: auth)
        let received = await events(client.connect(), 10) // the stream ends by itself
        client.disconnect()

        #expect(received == [.disconnected, .disconnected, .unauthorized])
        #expect(auth.rejected == [nil, "token-1"])
        #expect(connector.opened.count == 2)
    }

    @Test func aRefusedTokenThatRefreshesFineJustReconnects() async {
        let connector = FakeConnector([[.end(closeCode: 4401)], [.frame(hello())]])
        let client = makeClient(connector)
        let received = await events(client.connect(), 2)
        client.disconnect()

        #expect(received.first == .disconnected)
        if case .hello? = received.last {} else { Issue.record("expected a hello after refreshing") }
    }

    @Test func signsOutWhenTheAccountWasDeletedOrTheSessionIsGone() async {
        let deleted = makeClient(FakeConnector([[.end(closeCode: 4403)]]))
        #expect(await events(deleted.connect(), 10) == [.disconnected, .unauthorized])

        let auth = FakeLiveAuth()
        auth.failWith = AuthError.sessionExpired
        let gone = makeClient(FakeConnector([]), auth: auth)
        #expect(await events(gone.connect(), 10) == [.unauthorized])
    }

    @Test func staysPausedWhenAnotherDeviceTakesOver() async {
        let connector = FakeConnector([[.frame(hello()), .end(closeCode: 4409)], [.frame(hello())]])
        let pauses = Pauses()
        let client = makeClient(connector, pauses: pauses)
        let received = await events(client.connect(), 10)

        #expect(received.suffix(2) == [.disconnected, .replaced])
        #expect(connector.opened.count == 1) // no reconnect: two devices would fight forever
        #expect(pauses.values.isEmpty)
    }

    @Test func staysAwayForALongTimeAfterFlooding() async {
        let connector = FakeConnector([[.end(closeCode: 4429)], [.frame(hello())]])
        let pauses = Pauses()
        let client = makeClient(connector, pauses: pauses)
        _ = await events(client.connect(), 2)
        client.disconnect()
        #expect(pauses.values.first == LiveSocketClient.floodPause)
    }

    @Test func doesNotLoopWhenTheUsernameIsMissing() async {
        let connector = FakeConnector([[.end(closeCode: nil, status: 403)]])
        let client = makeClient(connector)
        #expect(await events(client.connect(), 10) == [.disconnected])
        #expect(connector.opened.count == 1)
    }

    @Test func sendsPositionsOnlyOnceConnectedAndInOrder() async throws {
        let connector = FakeConnector([[.frame(hello())]])
        let client = makeClient(connector)
        client.send(position()) // nothing is open yet

        let stream = client.connect()
        client.send(position()) // connecting, no hello yet: dropped
        _ = await events(stream, 1)
        client.send(position(30))
        client.send(position(31))
        try await Task.sleep(for: .milliseconds(100))
        client.disconnect()

        let frames = try #require(connector.opened.first).sent
        #expect(frames.count == 2)
        #expect(frames.allSatisfy { $0.contains(#""t":"loc""#) })
    }

    @Test func sendsAGhostChoiceMadeOfflineAfterTheHello() async throws {
        let connector = FakeConnector([[.frame(hello(ghost: false))]])
        let client = makeClient(connector)
        client.setGhost(true) // offline: remembered

        let received = await events(client.connect(), 1)
        try await Task.sleep(for: .milliseconds(100))
        client.disconnect()

        #expect(received == [.hello(ghost: true, friends: [])]) // the app sees what the person chose
        #expect(try #require(connector.opened.first).sent == [LiveFrame.ghost(true)])
    }

    @Test func sendsGhostFramesWhileConnected() async throws {
        let connector = FakeConnector([[.frame(hello())]])
        let client = makeClient(connector)
        _ = await events(client.connect(), 1)
        client.setGhost(true)
        try await Task.sleep(for: .milliseconds(100))
        client.disconnect()
        #expect(try #require(connector.opened.first).sent == [LiveFrame.ghost(true)])
    }
}
