import CoreLocation
import Foundation
import Testing
@testable import PlaceRating

private let day = Date(timeIntervalSince1970: 1_800_000_000)

private func user(_ id: String, _ username: String? = nil) -> PublicUser {
    PublicUser(id: id, username: username ?? id, displayName: username ?? id, avatar: nil)
}

final class FakeModerationAPI: ModerationAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    var blockedList: [PublicUser] = []
    var failure: Error?

    var calls: [String] { lock.withLock { _calls } }
    private func log(_ call: String) throws {
        lock.withLock { _calls.append(call) }
        if let failure { throw failure }
    }

    func report(_ target: ReportTarget, id: String, reason: ReportReason) async throws {
        try log("report \(target.rawValue) \(id) \(reason.rawValue)")
    }
    func blocks() async throws -> [PublicUser] {
        try log("blocks")
        return blockedList
    }
    func block(userId: String) async throws { try log("block \(userId)") }
    func unblock(userId: String) async throws { try log("unblock \(userId)") }
}

@MainActor
struct SafetyViewModelTests {
    @Test func reportsAUserARatingOrAPhotoAndConfirmsBriefly() async throws {
        let api = FakeModerationAPI()
        let safety = SafetyViewModel(api: api, noticeDuration: .milliseconds(30))

        await safety.report(.rating, id: "r1", reason: .spam)
        await safety.report(.user, id: "u1", reason: .abuse)
        await safety.report(.photo, id: "ph1", reason: .inappropriate)

        #expect(api.calls == ["report rating r1 spam", "report user u1 abuse", "report photo ph1 inappropriate"])
        #expect(safety.noticeText != nil)
        try await Task.sleep(for: .milliseconds(120))
        #expect(safety.noticeText == nil)
    }

    @Test func blockingHidesThemAndTellsTheRestOfTheApp() async {
        let api = FakeModerationAPI()
        let safety = SafetyViewModel(api: api)
        var blockedIds: [String] = []
        safety.onBlocked = { blockedIds.append($0) }

        await safety.block(user("pest"))
        await safety.block(user("pest")) // already blocked: nothing more to do

        #expect(api.calls == ["block pest"])
        #expect(safety.isBlocked("pest"))
        #expect(safety.blockedIds == ["pest"])
        #expect(blockedIds == ["pest"])
        #expect(safety.noticeText != nil)
    }

    @Test func unblockingBringsThemBack() async {
        let api = FakeModerationAPI()
        api.blockedList = [user("a"), user("b")]
        let safety = SafetyViewModel(api: api)
        await safety.loadBlocked()
        #expect(safety.blocked.map(\.id) == ["a", "b"])

        await safety.unblock(user("a"))
        #expect(api.calls.last == "unblock a")
        #expect(safety.blocked.map(\.id) == ["b"])
    }

    @Test func aFailedBlockOrReportShowsAnErrorAndChangesNothing() async {
        let api = FakeModerationAPI()
        api.failure = URLError(.notConnectedToInternet)
        let safety = SafetyViewModel(api: api)
        var blockedIds: [String] = []
        safety.onBlocked = { blockedIds.append($0) }

        await safety.block(user("pest"))
        #expect(safety.errorText != nil)
        #expect(!safety.isBlocked("pest"))
        #expect(blockedIds.isEmpty)

        await safety.report(.user, id: "pest", reason: .spam)
        #expect(safety.errorText != nil)
        #expect(safety.noticeText == nil)
    }
}

@MainActor
struct BlockingInTheAppTests {
    @Test func ratingsFromBlockedPeopleDisappearFromThePlaceSheet() async {
        let places = FakePlacesAPI()
        places.ratingPages = [nil: RatingPage(items: [
            PlaceRating(id: "1", stars: 1, comment: "rude", createdAt: day, updatedAt: day, user: user("pest")),
            PlaceRating(id: "2", stars: 5, comment: nil, createdAt: day, updatedAt: day, user: user("friend")),
        ], nextCursor: nil)]
        places.friendsList = FriendsList(friends: [FriendshipEntry(id: "f", user: user("friend"), since: day)], incoming: [], outgoing: [])
        let safety = SafetyViewModel(api: FakeModerationAPI())
        let model = PlaceViewModel(placeId: "p1", api: places, myId: "me", safety: safety)
        await model.load()
        #expect(model.otherRatings.map(\.id) == ["1"])
        #expect(model.friendRatings.map(\.id) == ["2"])

        await safety.block(user("pest"))
        #expect(model.otherRatings.isEmpty)
        #expect(model.friendRatings.map(\.id) == ["2"])
    }

    @Test func blockingAFriendRemovesThemFromTheMapAndTheList() async {
        let friends = FakeFriendsAPI()
        let nia = user("a", "nia")
        friends.list = FriendsList(friends: [FriendshipEntry(id: "f1", user: nia, since: day)], incoming: [], outgoing: [])
        let model = MapViewModel(
            user: makeUser(), location: FakeLocation(access: .allowed), socket: FakeLiveSocket(),
            friendsAPI: friends, moderationAPI: FakeModerationAPI()
        )
        await model.loadFriends()
        model.handle(.loc(FriendFix(userId: "a", latitude: 30, longitude: 31, heading: nil, receivedAt: Date())))
        #expect(model.visibleFriends.count == 1)

        friends.list = FriendsList(friends: [], incoming: [], outgoing: []) // the server drops the friendship too
        await model.safety.block(nia)

        #expect(model.visibleFriends.isEmpty)
        #expect(model.friendsList.friends.isEmpty)
    }

    @Test func theBlockedListIsReachableFromTheProfile() {
        let model = MapViewModel(user: makeUser(), location: FakeLocation(access: .allowed), socket: FakeLiveSocket())
        model.showBlocked()
        #expect(model.sheet == .blocked)
        model.showProfile()
        #expect(model.sheet == .profile)
    }
}
