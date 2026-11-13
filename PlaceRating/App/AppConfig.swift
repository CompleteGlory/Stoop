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

    /// The development server on a Mac. `host` is `localhost` for the simulator; a real phone needs
    /// the Mac's name on the network, such as `Magds-MacBook-Pro.local`.
    static func local(host: String = "localhost") -> AppConfig {
        AppConfig(
            apiBaseURL: URL(string: "http://\(host):3000")!,
            liveURL: URL(string: "ws://\(host):3000/live")!
        )
    }

    static let production = AppConfig(
        apiBaseURL: URL(string: "https://place-rating-api-production.up.railway.app")!,
        liveURL: URL(string: "wss://place-rating-api-production.up.railway.app/live")!
    )

    static var current: AppConfig {
        #if DEBUG
        DebugServer.selected == .production ? production : local(host: DebugServer.localHost)
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

    private static let hostKey = "debug.localHost"

    /// The Mac that runs the local server. Set it for a real phone with the launch argument
    /// `-debug.localHost <name>.local`; the simulator's default, `localhost`, is the Mac itself.
    static var localHost: String {
        let host = UserDefaults.standard.string(forKey: hostKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return host.isEmpty ? "localhost" : host
    }

    /// Launch arguments (`-debug.server local -debug.localHost …`) only last for that launch. Keep
    /// them, so the next launch (from a tapped notification, say) talks to the same server.
    static func rememberLaunchArguments(
        _ arguments: [String: Any] = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain),
        defaults: UserDefaults = .standard
    ) {
        for name in [key, hostKey] {
            if let value = arguments[name] as? String { defaults.set(value, forKey: name) }
        }
    }

    static var selected: DebugServer {
        get { UserDefaults.standard.string(forKey: key).flatMap(Self.init) ?? .local }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}
#endif
