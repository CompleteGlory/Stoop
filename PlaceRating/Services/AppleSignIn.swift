import AuthenticationServices
import CryptoKit
import Foundation

/// What the app needs from a completed Sign in with Apple, free of Apple's types.
struct AppleCredential: Equatable, Sendable {
    let identityToken: String
    let fullName: String?
    /// One-time code the server swaps for an Apple refresh token, so deleting the account can revoke the sign-in.
    let authorizationCode: String?

    /// Nil when Apple's result has no usable identity token.
    init?(_ authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken,
              let token = String(data: data, encoding: .utf8) else { return nil }
        identityToken = token
        fullName = credential.fullName.flatMap(Self.format)
        authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
    }

    init(identityToken: String, fullName: String?, authorizationCode: String? = nil) {
        self.identityToken = identityToken
        self.fullName = fullName
        self.authorizationCode = authorizationCode
    }

    private static func format(_ name: PersonNameComponents) -> String? {
        let text = PersonNameComponentsFormatter().string(from: name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(60))
    }
}

enum Nonce {
    /// A random raw nonce. The server receives this; Apple receives its hash.
    static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
    }

    static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
