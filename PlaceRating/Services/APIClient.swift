import Foundation

protocol APIClientProtocol: Sendable {
    /// Returns whether a saved session exists.
    func restoreSession() async throws -> Bool
    func signInWithApple(identityToken: String, nonce: String, fullName: String?) async throws -> AuthResponse
    func devSignIn(username: String) async throws -> AuthResponse
    func me() async throws -> SelfUser
    func updateProfile(username: String, displayName: String?) async throws -> SelfUser
    func usernameAvailability(_ username: String) async throws -> UsernameAvailability
    func signOut() async
}

struct APIClient: APIClientProtocol {
    private let http: HTTPClient
    private let session: AuthSession

    init(http: HTTPClient, store: any TokenStore) {
        self.http = http
        session = AuthSession(store: store) { refreshToken in
            let request = try http.request("POST", "auth/refresh", body: RefreshBody(refreshToken: refreshToken))
            return try JSONDecoder.api.decode(AuthResponse.self, from: await http.data(for: request))
        }
    }

    func restoreSession() async throws -> Bool {
        try await session.restore()
    }

    func signInWithApple(identityToken: String, nonce: String, fullName: String?) async throws -> AuthResponse {
        let body = AppleBody(identityToken: identityToken, nonce: nonce, fullName: fullName)
        return try await signIn(http.request("POST", "auth/apple", body: body))
    }

    func devSignIn(username: String) async throws -> AuthResponse {
        try await signIn(http.request("POST", "auth/dev", body: DevBody(username: username)))
    }

    func me() async throws -> SelfUser {
        try await authorized { try http.request("GET", "me", token: $0) }
    }

    func updateProfile(username: String, displayName: String?) async throws -> SelfUser {
        let body = ProfileBody(username: username, displayName: displayName)
        return try await authorized { try http.request("PATCH", "me", body: body, token: $0) }
    }

    func usernameAvailability(_ username: String) async throws -> UsernameAvailability {
        let query = [URLQueryItem(name: "username", value: username)]
        return try await authorized { try http.request("GET", "users/availability", query: query, token: $0) }
    }

    /// Always ends the local session, even if the server can't be reached.
    func signOut() async {
        if let refreshToken = await session.currentRefreshToken,
           let request = try? http.request("POST", "auth/logout", body: RefreshBody(refreshToken: refreshToken)) {
            _ = try? await http.data(for: request)
        }
        try? await session.clear()
    }

    private func signIn(_ request: URLRequest) async throws -> AuthResponse {
        let response = try JSONDecoder.api.decode(AuthResponse.self, from: await http.data(for: request))
        try await session.establish(response)
        return response
    }

    /// Sends with a valid token; on a 401, refreshes once and retries once.
    private func authorized<T: Decodable>(_ make: @Sendable (String) throws -> URLRequest) async throws -> T {
        let token = try await session.validAccessToken()
        do {
            return try JSONDecoder.api.decode(T.self, from: await http.data(for: make(token)))
        } catch let error as APIError where error.status == 401 {
            let fresh = try await session.tokenReplacing(token)
            do {
                return try JSONDecoder.api.decode(T.self, from: await http.data(for: make(fresh)))
            } catch let error as APIError where error.status == 401 {
                try? await session.clear()
                throw AuthError.sessionExpired
            }
        }
    }
}

private struct RefreshBody: Encodable { let refreshToken: String }
private struct DevBody: Encodable { let username: String }
private struct AppleBody: Encodable {
    let identityToken: String
    let nonce: String
    let fullName: String?
}
private struct ProfileBody: Encodable {
    let username: String
    let displayName: String?
}
