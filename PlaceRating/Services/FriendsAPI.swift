import Foundation

/// How a search result relates to you.
enum FriendStatus: String, Codable, Sendable {
    case none
    case friends
    case requestSent = "request_sent"
    case requestReceived = "request_received"
}

/// `GET /users/search`: a person plus how they relate to you.
struct UserSearchResult: Decodable, Equatable, Sendable, Identifiable {
    let user: PublicUser
    var friendStatus: FriendStatus
    var id: String { user.id }

    init(user: PublicUser, friendStatus: FriendStatus) {
        self.user = user
        self.friendStatus = friendStatus
    }

    // the API returns the person's fields and `friendStatus` side by side
    init(from decoder: Decoder) throws {
        user = try PublicUser(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        friendStatus = (try? container.decode(FriendStatus.self, forKey: .friendStatus)) ?? .none
    }

    private enum CodingKeys: String, CodingKey { case friendStatus }
}

/// `POST /friends/requests`: `accepted` when they had already asked you.
enum RequestOutcome: String, Decodable, Sendable {
    case pending
    case accepted
}

/// Friends and requests (api-contract.md, "Friends and blocks").
protocol FriendsAPI: Sendable {
    func friends() async throws -> FriendsList
    func searchUsers(_ query: String) async throws -> [UserSearchResult]
    func sendFriendRequest(to userId: String) async throws -> RequestOutcome
    /// `friendshipId` is the `id` of an entry in `incoming`.
    func acceptFriendRequest(_ friendshipId: String) async throws
    /// Removes a friend, cancels a request you sent, or declines one you received.
    func removeFriend(_ userId: String) async throws
}

extension APIClient: FriendsAPI {
    func searchUsers(_ query: String) async throws -> [UserSearchResult] {
        let items = [URLQueryItem(name: "q", value: query)]
        let page: SearchPage = try await authorized { try http.request("GET", "users/search", query: items, token: $0) }
        return page.items
    }

    func sendFriendRequest(to userId: String) async throws -> RequestOutcome {
        let response: RequestResponse = try await authorized {
            try http.request("POST", "friends/requests", body: ["userId": userId], token: $0)
        }
        return response.status
    }

    func acceptFriendRequest(_ friendshipId: String) async throws {
        try await authorizedNoContent { try http.request("POST", "friends/requests/\(friendshipId)/accept", token: $0) }
    }

    func removeFriend(_ userId: String) async throws {
        try await authorizedNoContent { try http.request("DELETE", "friends/\(userId)", token: $0) }
    }
}

private struct SearchPage: Decodable { let items: [UserSearchResult] }
private struct RequestResponse: Decodable { let status: RequestOutcome }

/// Stands in when no friends API was given (previews, tests that don't need it).
struct UnavailableFriendsAPI: FriendsAPI {
    private struct Unavailable: Error {}
    func friends() async throws -> FriendsList { FriendsList(friends: [], incoming: [], outgoing: []) }
    func searchUsers(_ query: String) async throws -> [UserSearchResult] { [] }
    func sendFriendRequest(to userId: String) async throws -> RequestOutcome { throw Unavailable() }
    func acceptFriendRequest(_ friendshipId: String) async throws { throw Unavailable() }
    func removeFriend(_ userId: String) async throws { throw Unavailable() }
}
