import Foundation
import Testing
@testable import PlaceRating

private let day = Date(timeIntervalSince1970: 1_800_000_000)

private func person(_ id: String, _ username: String) -> PublicUser {
    PublicUser(id: id, username: username, displayName: "", avatar: nil)
}

private func entry(_ id: String, _ user: PublicUser) -> FriendshipEntry {
    FriendshipEntry(id: id, user: user, since: day)
}

/// Keeps a small friend graph in memory and behaves like the server does.
final class FakeFriendsAPI: FriendsAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    var list = FriendsList(friends: [], incoming: [], outgoing: [])
    var people: [UserSearchResult] = []
    var failNext: Error?

    var calls: [String] { lock.withLock { _calls } }
    private func log(_ call: String) throws {
        lock.withLock { _calls.append(call) }
        if let error = failNext {
            failNext = nil
            throw error
        }
    }

    func friends() async throws -> FriendsList {
        try log("friends")
        return list
    }

    func searchUsers(_ query: String) async throws -> [UserSearchResult] {
        try log("search \(query)")
        return people.filter { $0.user.username?.hasPrefix(query) == true }
    }

    func sendFriendRequest(to userId: String) async throws -> RequestOutcome {
        try log("send \(userId)")
        if let theirs = list.incoming.first(where: { $0.user.id == userId }) {
            list = FriendsList(friends: list.friends + [theirs], incoming: list.incoming.filter { $0.user.id != userId },
                               outgoing: list.outgoing)
            return .accepted
        }
        let user = people.first { $0.id == userId }?.user ?? person(userId, userId)
        list = FriendsList(friends: list.friends, incoming: list.incoming, outgoing: list.outgoing + [entry("f-\(userId)", user)])
        return .pending
    }

    func acceptFriendRequest(_ friendshipId: String) async throws {
        try log("accept \(friendshipId)")
        guard let theirs = list.incoming.first(where: { $0.id == friendshipId }) else { return }
        list = FriendsList(friends: list.friends + [theirs], incoming: list.incoming.filter { $0.id != friendshipId },
                           outgoing: list.outgoing)
    }

    func removeFriend(_ userId: String) async throws {
        try log("remove \(userId)")
        list = FriendsList(friends: list.friends.filter { $0.user.id != userId },
                           incoming: list.incoming.filter { $0.user.id != userId },
                           outgoing: list.outgoing.filter { $0.user.id != userId })
    }
}

struct FriendsDecodingTests {
    @Test func searchResultReadsThePersonAndStatusSideBySide() throws {
        let json = #"{"items":[{"id":"u2","username":"sara","displayName":"Sara","avatar":null,"friendStatus":"request_received"}]}"#
        struct Page: Decodable { let items: [UserSearchResult] }
        let page = try JSONDecoder.api.decode(Page.self, from: Data(json.utf8))
        #expect(page.items[0].user.username == "sara")
        #expect(page.items[0].friendStatus == .requestReceived)
    }
}

@MainActor
struct FriendsViewModelTests {
    @Test func searchTermFollowsTheUsernameRules() {
        #expect(FriendsViewModel.searchTerm(" @Sara ") == "sara")
        #expect(FriendsViewModel.searchTerm("sa") == nil)
        #expect(FriendsViewModel.searchTerm("sara smith") == nil)
        #expect(FriendsViewModel.searchTerm("سارة") == nil)
        #expect(FriendsViewModel.searchTerm("o.k_99") == "o.k_99")
    }

    @Test func typingSearchesOnceAfterAPause() async {
        let api = FakeFriendsAPI()
        api.people = [UserSearchResult(user: person("s", "sara"), friendStatus: .none)]
        let model = FriendsViewModel(api: api, debounce: .milliseconds(20))

        model.query = "sa"
        model.query = "sar"
        model.query = "sara"
        await model.waitForSearch()

        #expect(api.calls == ["search sara"])
        #expect(model.results.map(\.user.username) == ["sara"])
        #expect(!model.isSearching)

        model.query = "x"
        #expect(model.results.isEmpty)
    }

    @Test func addingSomeoneMarksThemRequestedAndListsTheRequest() async {
        let api = FakeFriendsAPI()
        let sara = person("s", "sara")
        api.people = [UserSearchResult(user: sara, friendStatus: .none)]
        var published: [FriendsList] = []
        let model = FriendsViewModel(api: api, debounce: .zero) { published.append($0) }
        model.query = "sara"
        await model.waitForSearch()

        await model.send(to: sara)

        #expect(model.results.first?.friendStatus == .requestSent)
        #expect(model.outgoing.map(\.user.id) == ["s"])
        #expect(published.last?.outgoing.count == 1)
        #expect(model.busy.isEmpty)
    }

    @Test func addingSomeoneWhoAskedYouMakesYouFriends() async {
        let api = FakeFriendsAPI()
        let omar = person("o", "omar")
        api.list = FriendsList(friends: [], incoming: [entry("f1", omar)], outgoing: [])
        api.people = [UserSearchResult(user: omar, friendStatus: .requestReceived)]
        let model = FriendsViewModel(api: api, debounce: .zero)
        model.query = "omar"
        await model.waitForSearch()

        await model.send(to: omar)

        #expect(model.results.first?.friendStatus == .friends)
        #expect(model.friends.map(\.user.id) == ["o"])
        #expect(model.incoming.isEmpty)
    }

    @Test func acceptingAndDecliningRequests() async {
        let api = FakeFriendsAPI()
        let omar = person("o", "omar"), nia = person("n", "nia")
        api.list = FriendsList(friends: [], incoming: [entry("f1", omar), entry("f2", nia)], outgoing: [])
        let model = FriendsViewModel(api: api)
        await model.load()

        await model.accept(model.incoming[0])
        await model.remove(nia)

        #expect(api.calls.contains("accept f1"))
        #expect(api.calls.contains("remove n"))
        #expect(model.friends.map(\.user.id) == ["o"])
        #expect(model.incoming.isEmpty)
    }

    @Test func aFailedChangeShowsAnErrorAndKeepsTheLists() async {
        let api = FakeFriendsAPI()
        let omar = person("o", "omar")
        api.list = FriendsList(friends: [entry("f1", omar)], incoming: [], outgoing: [])
        let model = FriendsViewModel(api: api)
        await model.load()
        api.failNext = URLError(.notConnectedToInternet)

        await model.remove(omar)

        #expect(model.errorText != nil)
        #expect(model.friends.count == 1)
        #expect(model.busy.isEmpty)
    }
}

@MainActor
struct MapFriendsTests {
    @Test func loadsFriendsAndKeepsThemInStepWithTheSheet() async {
        let api = FakeFriendsAPI()
        let sara = person("s", "sara")
        api.list = FriendsList(friends: [], incoming: [entry("f1", sara)], outgoing: [])
        let model = MapViewModel(user: makeUser(), location: FakeLocation(access: .allowed), socket: FakeLiveSocket(),
                                 people: [], friendsAPI: api)

        await model.loadFriends()
        #expect(model.friendsList.incoming.count == 1)

        model.showFriends()
        #expect(model.sheet == .friends)
        await model.friendsModel?.accept(entry("f1", sara))
        #expect(model.friendsList.friends.map(\.user.id) == ["s"])
        #expect(model.friendsList.incoming.isEmpty)

        model.showBrowse()
        #expect(model.friendsModel == nil)
    }
}
