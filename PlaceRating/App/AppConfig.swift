import Foundation

/// Server addresses. Release builds always use production.
struct AppConfig: Sendable {
    let apiBaseURL: URL
    let liveURL: URL

    /// Where people can reach us (also on the terms and privacy pages, and in App Store Connect).
    static let supportEmail = "magddevf@gmail.com"

    /// The Terms of Use and Privacy Policy pages, served by the API.
    var termsURL: URL { apiBaseURL.appending(path: "terms") }
    var privacyURL: URL { apiBaseURL.appending(path: "privacy") }

    static let local = AppConfig(
        apiBaseURL: URL(string: "http://localhost:3000")!,
        liveURL: URL(string: "ws://localhost:3000/live")!
    )

    static let production = AppConfig(
        apiBaseURL: URL(string: "https://place-rating-api-production.up.railway.app")!,
        liveURL: URL(string: "wss://place-rating-api-production.up.railway.app/live")!
    )

    static var current: AppConfig {
        #if DEBUG
        DebugServer.selected == .production ? production : local
        #else
        production
        #endif
    }
}

#if DEBUG
/// The server a Debug build talks to, chosen on the sign-in screen.
enum DebugServer: String, CaseIterable, Sendable {
    case local
    case production

    private static let key = "debug.server"

    static var selected: DebugServer {
        get { UserDefaults.standard.string(forKey: key).flatMap(Self.init) ?? .local }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}
#endif
