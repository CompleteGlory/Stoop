import CoreLocation
import Foundation
import Testing
@testable import PlaceRating

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func fix(_ id: String, at time: Date = t0, lat: Double = 30.0) -> FriendFix {
    FriendFix(userId: id, latitude: lat, longitude: 31.0, heading: nil, receivedAt: time)
}

private func place(_ lat: Double, _ lng: Double, accuracy: Double = 10) -> CLLocation {
    CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), altitude: 0,
               horizontalAccuracy: accuracy, verticalAccuracy: 0, timestamp: t0)
}

struct FriendsStateTests {
    @Test func helloReplacesLocUpsertsGoneRemoves() {
        var state = FriendsState()
        state.apply(.hello(ghost: false, friends: [fix("a"), fix("b")]))
        state.apply(.loc(fix("c")))
        state.apply(.loc(fix("a", lat: 31)))
        state.apply(.gone(userId: "b"))
        #expect(Set(state.fixes.keys) == ["a", "c"])
        #expect(state.fixes["a"]?.latitude == 31)

        state.apply(.hello(ghost: false, friends: [fix("d")]))
        #expect(Array(state.fixes.keys) == ["d"])
    }

    @Test func dimsAfter30SecondsAndRemovesAfter60() {
        var state = FriendsState()
        state.apply(.loc(fix("a")))
        #expect(!state.isDimmed("a", now: t0.addingTimeInterval(29)))
        #expect(state.isDimmed("a", now: t0.addingTimeInterval(30)))
        state.prune(now: t0.addingTimeInterval(59))
        #expect(state.fixes["a"] != nil)
        state.prune(now: t0.addingTimeInterval(60))
        #expect(state.fixes["a"] == nil)
    }
}

struct SendThrottleTests {
    @Test func sendsTheFirstAccurateFix() {
        #expect(SendThrottle().shouldSend(place(30, 31), now: t0))
        #expect(!SendThrottle().shouldSend(place(30, 31, accuracy: 150), now: t0))
        #expect(!SendThrottle().shouldSend(place(30, 31, accuracy: -1), now: t0))
    }

    @Test func waits3SecondsAnd10MetersButBeatsEvery15() {
        var throttle = SendThrottle()
        throttle.didSend(place(30, 31), at: t0)
        let farAway = place(30.001, 31) // about 111 m north
        #expect(!throttle.shouldSend(farAway, now: t0.addingTimeInterval(2)))
        #expect(throttle.shouldSend(farAway, now: t0.addingTimeInterval(3)))
        let sameSpot = place(30.00003, 31) // about 3 m
        #expect(!throttle.shouldSend(sameSpot, now: t0.addingTimeInterval(10)))
        #expect(throttle.shouldSend(sameSpot, now: t0.addingTimeInterval(15)))
    }
}

@MainActor
final class FakeLocation: LocationServiceProtocol {
    var access: LocationAccess
    var onAccessChange: ((LocationAccess) -> Void)?
    var requested = false
    let stream: AsyncStream<CLLocation>
    let continuation: AsyncStream<CLLocation>.Continuation

    init(access: LocationAccess) {
        self.access = access
        (stream, continuation) = AsyncStream<CLLocation>.makeStream()
    }

    func requestAccess() { requested = true }
    func updates() -> AsyncStream<CLLocation> { stream }
}

@MainActor
final class FakeLiveSocket: LiveSocketProtocol {
    var connects = 0
    var disconnects = 0
    var sent: [CLLocation] = []
    var ghostFrames: [Bool] = []

    func connect() -> AsyncStream<LiveEvent> {
        connects += 1
        return AsyncStream { _ in }
    }
    func disconnect() { disconnects += 1 }
    func send(_ location: CLLocation) { sent.append(location) }
    func setGhost(_ on: Bool) { ghostFrames.append(on) }
}

@MainActor
struct MapViewModelTests {
    private let nia = Person(id: "a", name: "nia", avatar: nil)

    private func make(access: LocationAccess = .allowed, now: @escaping () -> Date = { t0 })
        -> (MapViewModel, FakeLocation, FakeLiveSocket) {
        let location = FakeLocation(access: access)
        let socket = FakeLiveSocket()
        let model = MapViewModel(user: makeUser(), location: location, socket: socket, people: [nia], clock: now)
        return (model, location, socket)
    }

    @Test func asksBeforeTheSystemPrompt() {
        let (model, location, _) = make(access: .unknown)
        model.start()
        #expect(model.showsLocationPrompt)
        model.allowLocation()
        #expect(!model.showsLocationPrompt)
        #expect(location.requested)
        model.stop()
    }

    @Test func showsKnownFriendsAndCountsThem() {
        let (model, _, _) = make()
        model.handle(.hello(ghost: false, friends: [fix("a"), fix("stranger")]))
        #expect(model.isConnected)
        #expect(model.visibleFriends.map(\.person.name) == ["nia"])
        #expect(model.sharingCount == 2)
    }

    @Test func dimsAndDropsQuietFriendsOnTheTicker() {
        var clock = t0
        let (model, _, _) = make(now: { clock })
        model.handle(.loc(fix("a")))
        clock = t0.addingTimeInterval(31)
        model.tick()
        #expect(model.visibleFriends.first?.isDimmed == true)
        clock = t0.addingTimeInterval(61)
        model.tick()
        #expect(model.visibleFriends.isEmpty)
    }

    @Test func ghostModeStopsSendingAndTellsTheServer() {
        let (model, _, socket) = make()
        model.received(place(30, 31))
        #expect(socket.sent.count == 1)
        model.toggleGhost()
        #expect(socket.ghostFrames == [true])
        #expect(model.sharingCount == 0)
        model.received(place(30.01, 31))
        #expect(socket.sent.count == 1)
        model.handle(.ghost(false))
        #expect(!model.ghost)
    }

    @Test func throttlesWhatItSends() {
        let (model, _, socket) = make()
        model.received(place(30, 31))
        model.received(place(30.01, 31))
        #expect(socket.sent.count == 1)
        #expect(model.me?.latitude == 30.01)
    }

    @Test func stoppingDisconnectsAndStartingReconnects() {
        let (model, _, socket) = make()
        model.start()
        model.start()
        #expect(socket.connects == 1)
        model.stop()
        #expect(socket.disconnects == 1)
        #expect(!model.isConnected)
        model.start()
        #expect(socket.connects == 2)
        model.stop()
    }

    @Test func profileOpensAtMediumHeight() {
        let (model, _, _) = make()
        model.showProfile()
        #expect(model.sheet == .profile)
        #expect(model.detent == .medium)
        model.showBrowse()
        #expect(model.sheet == .browse)
    }
}
