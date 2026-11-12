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
    private func make(
        access: LocationAccess = .allowed,
        now: @escaping () -> Date = { t0 },
        onSessionExpired: @escaping () -> Void = {}
    ) -> (MapViewModel, FakeLocation, FakeLiveSocket) {
        let location = FakeLocation(access: access)
        let socket = FakeLiveSocket()
        let friends = FakeFriendsAPI()
        let nia = PublicUser(id: "a", username: "nia", displayName: "nia", avatar: nil)
        friends.list = FriendsList(friends: [FriendshipEntry(id: "f1", user: nia, since: t0)], incoming: [], outgoing: [])
        let model = MapViewModel(
            user: makeUser(), location: location, socket: socket, onSessionExpired: onSessionExpired,
            friendsAPI: friends, clock: now
        )
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

    @Test func showsKnownFriendsAndCountsThem() async {
        let (model, _, _) = make()
        await model.loadFriends()
        model.handle(.hello(ghost: false, friends: [fix("a"), fix("stranger")]))
        #expect(model.isConnected)
        #expect(model.visibleFriends.map(\.person.name) == ["nia"])
        #expect(model.sharingCount == 2)
    }

    @Test func dimsAndDropsQuietFriendsOnTheTicker() async {
        var clock = t0
        let (model, _, _) = make(now: { clock })
        await model.loadFriends()
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

    @Test func aNewConnectionTellsFriendsWhereYouAreRightAway() {
        let (model, _, socket) = make()
        model.received(place(30, 31))
        #expect(socket.sent.count == 1)
        model.handle(.hello(ghost: false, friends: []))
        #expect(socket.sent.count == 2) // the throttle starts over with every connection
    }

    @Test func repeatsTheLastPositionEvery15SecondsWhileStandingStill() {
        var clock = t0
        let (model, _, socket) = make(now: { clock })
        model.received(place(30, 31))
        model.handle(.hello(ghost: false, friends: []))
        #expect(socket.sent.count == 2)

        clock = t0.addingTimeInterval(10)
        model.tick()
        #expect(socket.sent.count == 2)
        clock = t0.addingTimeInterval(16)
        model.tick()
        #expect(socket.sent.count == 3)
    }

    @Test func staysQuietWhileOfflineAsAGhostOrBeforeAnyFix() {
        var clock = t0
        let (model, _, socket) = make(now: { clock })
        clock = t0.addingTimeInterval(20)
        model.tick() // no position yet
        model.received(place(30, 31))
        model.handle(.hello(ghost: false, friends: []))
        let before = socket.sent.count
        model.handle(.disconnected)
        clock = t0.addingTimeInterval(60)
        model.tick() // offline: nothing to send to
        #expect(socket.sent.count == before)
    }

    @Test func showsOfflineAndDimsFriendsUntilTheNextHello() async {
        let (model, _, _) = make()
        await model.loadFriends()
        model.handle(.hello(ghost: false, friends: [fix("a")]))
        #expect(!model.connectionLost)
        #expect(model.visibleFriends.first?.isDimmed == false)

        model.handle(.disconnected)
        #expect(model.connectionLost)
        #expect(!model.isConnected)
        #expect(model.visibleFriends.first?.isDimmed == true)

        model.handle(.hello(ghost: false, friends: [fix("a")]))
        #expect(!model.connectionLost)
        #expect(model.visibleFriends.first?.isDimmed == false)
    }

    @Test func pausesWhenAnotherDeviceTakesOverUntilTheAppReturns() {
        let (model, _, socket) = make()
        model.start()
        model.handle(.replaced)
        #expect(model.isPaused)
        #expect(!model.isConnected)
        model.stop()
        model.start()
        #expect(!model.isPaused)
        #expect(socket.connects == 2)
        model.stop()
    }

    @Test func signsOutWhenTheServerRefusesTheSession() {
        var expired = 0
        let (model, _, _) = make(onSessionExpired: { expired += 1 })
        model.handle(.unauthorized)
        #expect(expired == 1)
    }

    @Test func asksForFriendsAgainWhenSomeoneUnknownShowsUpOnce() async {
        let (model, _, _) = make()
        model.handle(.loc(fix("newcomer")))
        model.handle(.loc(fix("newcomer")))
        // the refresh runs in its own task: give it time instead of a single yield
        for _ in 0..<200 where model.friendsList.friends.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(model.friendsList.friends.map(\.user.id) == ["a"])
    }

    @Test func goingBackShrinksTheSheetSoTheMapCanBeTappedAgain() {
        let (model, _, _) = make()
        model.showSettings()
        #expect(model.detent == .large)
        model.showBrowse()
        #expect(model.detent == MapViewModel.smallDetent)
        model.showFriends()
        model.showBrowse()
        #expect(model.detent == MapViewModel.smallDetent)
    }

    @Test func settingsOpenAtFullHeight() {
        let (model, _, _) = make()
        model.showSettings()
        #expect(model.sheet == .settings)
        #expect(model.detent == .large)
        model.showBrowse()
        #expect(model.sheet == .browse)
    }
}
