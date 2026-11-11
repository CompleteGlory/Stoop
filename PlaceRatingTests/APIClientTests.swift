import Foundation
import Testing
@testable import PlaceRating

private let userJSON = """
{"id":"u1","username":null,"displayName":"","avatar":{"kind":"preset","value":"fox","url":null},\
"ghostMode":false,"createdAt":"2026-11-11T06:54:12.345Z"}
"""

/// Answers by path, and records what was asked.
private final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [URLRequest] = []
    private let answer: @Sendable (URLRequest, Int) -> (Int, String)

    init(answer: @escaping @Sendable (URLRequest, Int) -> (Int, String)) { self.answer = answer }

    var requests: [URLRequest] { lock.withLock { log } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let count = lock.withLock { log.append(request); return log.count }
        let (status, body) = answer(request, count)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

private func client(_ transport: StubTransport, store: MemoryTokenStore) -> APIClient {
    APIClient(http: HTTPClient(baseURL: { URL(string: "http://test")! }, transport: transport), store: store)
}

struct APIClientTests {
    private let session = StoredTokens(accessToken: "a0", refreshToken: "r0", accessExpiry: .distantFuture)

    @Test func decodesDatesWithMilliseconds() throws {
        let user = try JSONDecoder.api.decode(SelfUser.self, from: Data(userJSON.utf8))
        #expect(user.username == nil)
        #expect(user.createdAt.timeIntervalSince1970 == 1_794_380_052.345)
    }

    @Test func refreshesOnceAndRetriesAfterA401() async throws {
        let auth = #"{"accessToken":"a1","refreshToken":"r1","expiresIn":900,"needsOnboarding":true,"user":\#(userJSON)}"#
        let transport = StubTransport { request, count in
            if request.url!.path() == "/auth/refresh" { return (200, auth) }
            return count == 1
                ? (401, #"{"error":{"code":"unauthorized","message":"no"}}"#)
                : (200, userJSON)
        }
        let api = client(transport, store: MemoryTokenStore(session))
        _ = try await api.restoreSession()

        _ = try await api.me()

        #expect(transport.requests.map { $0.url!.path() } == ["/me", "/auth/refresh", "/me"])
        #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer a1")
    }

    @Test func turnsTheErrorEnvelopeIntoAnAPIError() async throws {
        let transport = StubTransport { _, _ in (409, #"{"error":{"code":"username_taken","message":"x"}}"#) }
        let api = client(transport, store: MemoryTokenStore(session))
        _ = try await api.restoreSession()
        await #expect(throws: APIError(status: 409, code: "username_taken", message: "x")) {
            try await api.updateProfile(username: "alice", displayName: nil)
        }
    }

    @Test func omitsAMissingDisplayName() async throws {
        let transport = StubTransport { _, _ in (200, userJSON) }
        let api = client(transport, store: MemoryTokenStore(session))
        _ = try await api.restoreSession()
        _ = try await api.updateProfile(username: "alice", displayName: nil)
        let body = try #require(transport.requests.first?.httpBody)
        #expect(String(decoding: body, as: UTF8.self) == #"{"username":"alice"}"#)
    }

    @Test func signOutClearsTokensEvenIfTheServerFails() async throws {
        let store = MemoryTokenStore(session)
        let api = client(StubTransport { _, _ in (500, "") }, store: store)
        _ = try await api.restoreSession()
        await api.signOut()
        #expect(store.tokens == nil)
    }
}
