import AuthenticationServices
import Foundation
import Observation

@MainActor
@Observable
final class SignInViewModel {
    private(set) var isBusy = false
    private(set) var errorText: String?

    private let session: SessionStore
    private var rawNonce = ""

    init(session: SessionStore) {
        self.session = session
    }

    /// Returns the hashed nonce to hand to Apple, and remembers the raw one for the server.
    func prepareNonce() -> String {
        rawNonce = Nonce.make()
        return Nonce.sha256Hex(rawNonce)
    }

    func complete(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = AppleCredential(authorization) else {
                errorText = String(localized: "Sign in failed. Try again.")
                return
            }
            await signIn(with: credential)
        case .failure(let error as ASAuthorizationError) where error.code == .canceled:
            errorText = nil
        case .failure:
            errorText = String(localized: "Sign in failed. Try again.")
        }
    }

    func signIn(with credential: AppleCredential) async {
        await run {
            try await self.session.api.signInWithApple(
                identityToken: credential.identityToken,
                nonce: self.rawNonce,
                fullName: credential.fullName
            )
        }
    }

    #if DEBUG
    func devSignIn(username: String) async {
        await run { try await self.session.api.devSignIn(username: username) }
    }
    #endif

    private func run(_ call: @escaping () async throws -> AuthResponse) async {
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            session.signedIn(try await call())
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }
}
