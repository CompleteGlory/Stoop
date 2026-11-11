import Foundation
@testable import PlaceRating

func makeUser(username: String? = "alice", displayName: String = "Alice") -> SelfUser {
    SelfUser(
        id: "11111111-1111-1111-1111-111111111111",
        username: username,
        displayName: displayName,
        avatar: Avatar(kind: .preset, value: "fox", url: nil),
        ghostMode: false,
        createdAt: Date(timeIntervalSince1970: 0)
    )
}

func makeAuth(access: String, refresh: String, expiresIn: Int = 900, user: SelfUser = makeUser()) -> AuthResponse {
    AuthResponse(
        accessToken: access,
        refreshToken: refresh,
        expiresIn: expiresIn,
        needsOnboarding: user.username == nil,
        user: user
    )
}

final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: StoredTokens?
    var loadError: Error?

    init(_ tokens: StoredTokens? = nil) { value = tokens }

    var tokens: StoredTokens? { lock.withLock { value } }

    func load() throws -> StoredTokens? {
        if let loadError { throw loadError }
        return tokens
    }
    func save(_ tokens: StoredTokens) throws { lock.withLock { value = tokens } }
    func clear() throws { lock.withLock { value = nil } }
}

actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

@MainActor
final class FakeAPI: APIClientProtocol, @unchecked Sendable {
    var restoreResult: Result<Bool, Error> = .success(false)
    var meResult: Result<SelfUser, Error> = .success(makeUser())
    var availabilityResult: Result<UsernameAvailability, Error> = .success(.init(available: true, reason: nil))
    var updateResult: Result<SelfUser, Error> = .success(makeUser())
    var checked: [String] = []
    var updates: [(username: String, displayName: String?)] = []
    var signedOut = false

    func restoreSession() async throws -> Bool { try restoreResult.get() }
    func signInWithApple(identityToken: String, nonce: String, fullName: String?) async throws -> AuthResponse {
        makeAuth(access: "a", refresh: "r", user: makeUser(username: nil, displayName: ""))
    }
    func devSignIn(username: String) async throws -> AuthResponse { makeAuth(access: "a", refresh: "r") }
    func me() async throws -> SelfUser { try meResult.get() }
    func updateProfile(username: String, displayName: String?) async throws -> SelfUser {
        updates.append((username, displayName))
        return try updateResult.get()
    }
    func usernameAvailability(_ username: String) async throws -> UsernameAvailability {
        checked.append(username)
        return try availabilityResult.get()
    }
    func signOut() async { signedOut = true }
}
