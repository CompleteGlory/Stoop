import Foundation

protocol APIClientProtocol: Sendable {
    /// Returns whether a saved session exists.
    func restoreSession() async throws -> Bool
    func signInWithApple(identityToken: String, nonce: String, fullName: String?) async throws -> AuthResponse
    func devSignIn(username: String) async throws -> AuthResponse
    func signInWithGoogle(idToken: String) async throws -> AuthResponse
    /// Emails a 6-digit code; the account exists only once the code is entered.
    /// `username`, when given, goes to the account once the code is entered (if it is still free).
    func emailSignUp(email: String, password: String, username: String?) async throws
    func emailVerify(email: String, code: String) async throws -> AuthResponse
    func emailResend(email: String) async throws
    func emailSignIn(email: String, password: String) async throws -> AuthResponse
    func passwordForgot(email: String) async throws
    func passwordReset(email: String, code: String, newPassword: String) async throws -> AuthResponse
    func me() async throws -> SelfUser
    func updateProfile(username: String, displayName: String?) async throws -> SelfUser
    func updateAvatar(_ avatar: Avatar) async throws -> SelfUser
    func usernameAvailability(_ username: String) async throws -> UsernameAvailability
    /// The same check signed out, for the email sign-up screen.
    func publicUsernameAvailability(_ username: String) async throws -> UsernameAvailability
    func signOut() async
}

struct APIClient: APIClientProtocol {
    let http: HTTPClient
    let session: AuthSession

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

    func signInWithGoogle(idToken: String) async throws -> AuthResponse {
        try await signIn(http.request("POST", "auth/google", body: ["idToken": idToken]))
    }

    func emailSignUp(email: String, password: String, username: String?) async throws {
        let body = SignUpBody(email: email, password: password, username: username)
        _ = try await http.data(for: http.request("POST", "auth/email/signup", body: body))
    }

    func emailVerify(email: String, code: String) async throws -> AuthResponse {
        try await signIn(http.request("POST", "auth/email/verify", body: ["email": email, "code": code]))
    }

    func emailResend(email: String) async throws {
        _ = try await http.data(for: http.request("POST", "auth/email/resend", body: ["email": email]))
    }

    func emailSignIn(email: String, password: String) async throws -> AuthResponse {
        try await signIn(http.request("POST", "auth/email/signin", body: ["email": email, "password": password]))
    }

    func passwordForgot(email: String) async throws {
        _ = try await http.data(for: http.request("POST", "auth/password/forgot", body: ["email": email]))
    }

    func passwordReset(email: String, code: String, newPassword: String) async throws -> AuthResponse {
        let body = ["email": email, "code": code, "newPassword": newPassword]
        return try await signIn(http.request("POST", "auth/password/reset", body: body))
    }

    func me() async throws -> SelfUser {
        try await authorized { try http.request("GET", "me", token: $0) }
    }

    func updateProfile(username: String, displayName: String?) async throws -> SelfUser {
        let body = ProfileBody(username: username, displayName: displayName)
        return try await authorized { try http.request("PATCH", "me", body: body, token: $0) }
    }

    func updateAvatar(_ avatar: Avatar) async throws -> SelfUser {
        let body = AvatarBody(avatar: avatar)
        return try await authorized { try http.request("PATCH", "me", body: body, token: $0) }
    }

    func usernameAvailability(_ username: String) async throws -> UsernameAvailability {
        let query = [URLQueryItem(name: "username", value: username)]
        return try await authorized { try http.request("GET", "users/availability", query: query, token: $0) }
    }

    func publicUsernameAvailability(_ username: String) async throws -> UsernameAvailability {
        let query = [URLQueryItem(name: "username", value: username)]
        let data = try await http.data(for: http.request("GET", "users/availability", query: query))
        return try JSONDecoder.api.decode(UsernameAvailability.self, from: data)
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
    func authorized<T: Decodable>(_ make: @Sendable (String) throws -> URLRequest) async throws -> T {
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

extension APIClient {
    /// Like `authorized`, for answers without a body (204).
    func authorizedNoContent(_ make: @Sendable (String) throws -> URLRequest) async throws {
        let token = try await session.validAccessToken()
        do {
            _ = try await http.data(for: make(token))
        } catch let error as APIError where error.status == 401 {
            let fresh = try await session.tokenReplacing(token)
            do {
                _ = try await http.data(for: make(fresh))
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
private struct AvatarBody: Encodable { let avatar: Avatar }
private struct ProfileBody: Encodable {
    let username: String
    let displayName: String?
}

private struct SignUpBody: Encodable {
    let email: String
    let password: String
    let username: String?
}
