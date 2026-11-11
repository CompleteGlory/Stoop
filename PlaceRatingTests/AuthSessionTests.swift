import Foundation
import Testing
@testable import PlaceRating

struct AuthSessionTests {
    private let expired = StoredTokens(accessToken: "old", refreshToken: "r0", accessExpiry: .distantPast)
    private let valid = StoredTokens(accessToken: "good", refreshToken: "r0", accessExpiry: .distantFuture)

    @Test func usesTheCurrentTokenWithoutRefreshing() async throws {
        let calls = Counter()
        let session = AuthSession(store: MemoryTokenStore(valid)) { _ in
            await calls.increment()
            return makeAuth(access: "new", refresh: "r1")
        }
        _ = try await session.restore()
        #expect(try await session.validAccessToken() == "good")
        #expect(await calls.value == 0)
    }

    @Test func concurrentCallersShareOneRefresh() async throws {
        let calls = Counter()
        let session = AuthSession(store: MemoryTokenStore(expired)) { _ in
            await calls.increment()
            try await Task.sleep(for: .milliseconds(50))
            return makeAuth(access: "new", refresh: "r1")
        }
        _ = try await session.restore()

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 { group.addTask { try await session.validAccessToken() } }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }

        #expect(tokens == Array(repeating: "new", count: 10))
        #expect(await calls.value == 1)
    }

    @Test func savesTheRotatedTokenBeforeReturning() async throws {
        let store = MemoryTokenStore(expired)
        let session = AuthSession(store: store) { _ in makeAuth(access: "new", refresh: "r1") }
        _ = try await session.restore()
        _ = try await session.validAccessToken()
        #expect(store.tokens?.refreshToken == "r1")
    }

    @Test func aRejectedRefreshEndsTheSession() async throws {
        let store = MemoryTokenStore(expired)
        let session = AuthSession(store: store) { _ in
            throw APIError(status: 401, code: "unauthorized", message: "")
        }
        _ = try await session.restore()
        await #expect(throws: AuthError.sessionExpired) { try await session.validAccessToken() }
        #expect(store.tokens == nil)
    }

    @Test func aNetworkFailureKeepsTheSession() async throws {
        let store = MemoryTokenStore(expired)
        let session = AuthSession(store: store) { _ in throw URLError(.notConnectedToInternet) }
        _ = try await session.restore()
        await #expect(throws: URLError.self) { try await session.validAccessToken() }
        #expect(store.tokens?.refreshToken == "r0")
    }

    @Test func aRetryAfterRejectionReusesANewerToken() async throws {
        let calls = Counter()
        let session = AuthSession(store: MemoryTokenStore(valid)) { _ in
            await calls.increment()
            return makeAuth(access: "new", refresh: "r1")
        }
        _ = try await session.restore()
        #expect(try await session.tokenReplacing("older") == "good")
        #expect(await calls.value == 0)
    }
}
