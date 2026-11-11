import GoogleSignIn
import UIKit

/// Signs in with Google and hands back the ID token the server checks.
@MainActor
protocol GoogleSignInProviding: AnyObject {
    /// False until a client id from Google Cloud is set in the GOOGLE_CLIENT_ID build setting.
    var isConfigured: Bool { get }
    /// The Google ID token, or nil when the person cancelled.
    func signIn() async throws -> String?
}

enum GoogleSignInError: Error {
    case noWindow
    case noToken
}

@MainActor
final class GoogleSignInService: GoogleSignInProviding {
    var isConfigured: Bool {
        let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
        return id.hasSuffix(".apps.googleusercontent.com")
    }

    func signIn() async throws -> String? {
        guard let presenter = Self.topViewController() else { throw GoogleSignInError.noWindow }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let token = result.user.idToken?.tokenString else { throw GoogleSignInError.noToken }
            return token
        } catch let error as NSError where error.domain == kGIDSignInErrorDomain && error.code == GIDSignInError.canceled.rawValue {
            return nil
        }
    }

    /// Google's sign-in comes back to the app through this URL.
    static func handle(_ url: URL) {
        GIDSignIn.sharedInstance.handle(url)
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
