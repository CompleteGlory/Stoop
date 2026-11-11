import Foundation

/// Owns the tokens and refreshes them.
///
/// Refresh tokens rotate, so two refreshes must never run at once. Being an actor isn't
/// enough for that: other callers can enter while one is suspended at an `await`. They
/// share the stored `inFlight` task instead.
actor AuthSession {
    typealias Refresh = @Sendable (String) async throws -> AuthResponse

    /// Refresh this long before the access token actually expires.
    static let expiryMargin: TimeInterval = 60

    private let store: any TokenStore
    private let refresh: Refresh
    private let now: @Sendable () -> Date
    private var tokens: StoredTokens?
    private var inFlight: Task<StoredTokens, Error>?

    init(
        store: any TokenStore,
        now: @escaping @Sendable () -> Date = { Date() },
        refresh: @escaping Refresh
    ) {
        self.store = store
        self.now = now
        self.refresh = refresh
    }

    /// Loads saved tokens. Returns whether there is a session to resume.
    func restore() throws -> Bool {
        tokens = try store.load()
        return tokens != nil
    }

    func establish(_ response: AuthResponse) throws {
        let new = stored(from: response)
        try store.save(new)
        tokens = new
    }

    var currentRefreshToken: String? { tokens?.refreshToken }

    func validAccessToken() async throws -> String {
        guard let tokens else { throw AuthError.sessionExpired }
        if tokens.accessExpiry.timeIntervalSince(now()) > Self.expiryMargin {
            return tokens.accessToken
        }
        return try await refreshShared().accessToken
    }

    /// A token for retrying after the server rejected `rejected` with a 401.
    func tokenReplacing(_ rejected: String) async throws -> String {
        guard let tokens else { throw AuthError.sessionExpired }
        if tokens.accessToken != rejected { return tokens.accessToken }
        return try await refreshShared().accessToken
    }

    func clear() throws {
        tokens = nil
        inFlight = nil
        try store.clear()
    }

    private func refreshShared() async throws -> StoredTokens {
        if let inFlight { return try await inFlight.value }
        guard let current = tokens else { throw AuthError.sessionExpired }
        let task = Task { try await self.performRefresh(using: current.refreshToken) }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    private func performRefresh(using refreshToken: String) async throws -> StoredTokens {
        let response: AuthResponse
        do {
            response = try await refresh(refreshToken)
        } catch let error as APIError where error.status == 401 {
            tokens = nil
            try? store.clear()
            throw AuthError.sessionExpired
        }
        // signed out while the request was running: don't bring the session back
        guard tokens?.refreshToken == refreshToken else { throw AuthError.sessionExpired }
        let new = stored(from: response)
        try store.save(new)
        tokens = new
        return new
    }

    private func stored(from response: AuthResponse) -> StoredTokens {
        StoredTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            accessExpiry: now().addingTimeInterval(TimeInterval(response.expiresIn))
        )
    }
}
