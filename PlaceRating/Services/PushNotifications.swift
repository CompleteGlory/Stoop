import Foundation
import Observation
import UIKit
import UserNotifications

/// What a Stoop push is about, from the `kind` and `userId` the server puts next to `aps`.
enum PushKind: String, Sendable {
    case friendRequest = "friend-request"
    case friendAccepted = "friend-accepted"
    case nearby
}

/// The Stoop part of a notification's payload, read once so it can cross to the main actor.
struct PushPayload: Equatable, Sendable {
    let kind: PushKind
    /// The other person: who asked, accepted, or is nearby.
    let userId: String?

    init(kind: PushKind, userId: String?) {
        self.kind = kind
        self.userId = userId
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo["kind"] as? String, let kind = PushKind(rawValue: raw) else { return nil }
        let id = (userInfo["userId"] as? String).flatMap(UUID.init(uuidString:))
        self.init(kind: kind, userId: id?.uuidString.lowercased())
    }

    /// Where tapping the notification takes you.
    var link: DeepLink {
        switch kind {
        case .friendRequest, .friendAccepted: .friends
        case .nearby: userId.map { .friend(id: $0) } ?? .friends
        }
    }
}

enum NotificationAccess: Equatable, Sendable {
    /// The person hasn't been asked yet.
    case unknown
    case denied
    case allowed
}

/// The system's notification permission. A protocol so tests can answer for the person.
protocol NotificationPermission: Sendable {
    func access() async -> NotificationAccess
    /// Shows the system prompt (only the first time); returns whether notifications are allowed.
    func request() async -> Bool
}

struct SystemNotificationPermission: NotificationPermission {
    func access() async -> NotificationAccess {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .unknown
        case .denied: .denied
        default: .allowed
        }
    }

    func request() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}

/// Keeps this phone's push token registered for the signed-in account.
@MainActor
protocol PushRegistering: AnyObject {
    var access: NotificationAccess { get }
    /// Reads the permission and, when allowed, asks iOS for the token (it arrives in `received`).
    func refresh() async
    /// Asks the person (the system prompt shows only once) and registers when they allow it.
    func requestAccess() async -> Bool
    /// Stops pushes to this phone for the account that is signing out.
    func unregister() async
    /// The account is gone on the server (deleted), which removed the token there too.
    func forget()
}

@MainActor
@Observable
final class PushRegistrar: PushRegistering {
    static let shared = PushRegistrar()

    private(set) var access: NotificationAccess = .unknown
    /// Set once the app has an API client; calls are only made while someone is signed in.
    @ObservationIgnored var api: (any NotificationsAPI)?
    @ObservationIgnored private let permission: any NotificationPermission
    @ObservationIgnored private let registerWithApple: @MainActor () -> Void
    @ObservationIgnored private let environment: PushEnvironment
    /// The token iOS gave this launch.
    @ObservationIgnored private(set) var token: String?
    /// Sent this launch (sent again each launch: the server may have dropped it).
    @ObservationIgnored private var uploaded: String?
    @ObservationIgnored private var isSignedIn = false
    /// The last token the server accepted, kept across launches so sign-out can remove it even when
    /// iOS hasn't handed over the token this time (notifications turned off since, say).
    @ObservationIgnored private let defaults: UserDefaults
    private static let registeredKey = "push.registeredToken"

    init(
        permission: any NotificationPermission = SystemNotificationPermission(),
        environment: PushEnvironment = .current,
        defaults: UserDefaults = .standard,
        registerWithApple: @escaping @MainActor () -> Void = { UIApplication.shared.registerForRemoteNotifications() }
    ) {
        self.permission = permission
        self.environment = environment
        self.defaults = defaults
        self.registerWithApple = registerWithApple
    }

    func refresh() async {
        isSignedIn = true
        access = await permission.access()
        if access == .allowed { registerWithApple() }
    }

    func requestAccess() async -> Bool {
        isSignedIn = true
        let allowed = await permission.request()
        access = allowed ? .allowed : await permission.access()
        if allowed { registerWithApple() }
        return allowed
    }

    /// From the app delegate. Sends the token to the API unless it already has it.
    func received(deviceToken: Data) async {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        token = hex
        await upload()
    }

    func unregister() async {
        isSignedIn = false
        uploaded = nil
        guard let registered = defaults.string(forKey: Self.registeredKey) else { return }
        defaults.removeObject(forKey: Self.registeredKey)
        try? await api?.unregisterDevice(token: registered)
    }

    func forget() {
        isSignedIn = false
        uploaded = nil
        defaults.removeObject(forKey: Self.registeredKey)
    }

    private func upload() async {
        guard isSignedIn, let token, uploaded != token, let api else { return }
        do {
            try await api.registerDevice(token: token, environment: environment)
            uploaded = token
            defaults.set(token, forKey: Self.registeredKey)
        } catch {
            // best effort: the next launch or foreground tries again
        }
    }
}

/// Notifications that were tapped or arrived while the app is open, for the views to act on.
@MainActor
@Observable
final class PushInbox {
    static let shared = PushInbox()

    /// Where a tapped notification wants to go; the app hands it to the session, which the map reads.
    var pendingLink: DeepLink?
    /// Goes up when a friend request or acceptance arrives with the app open, so the list reloads.
    private(set) var friendsRevision = 0

    func tapped(_ payload: PushPayload) {
        pendingLink = payload.link
        if payload.kind != .nearby { friendsRevision += 1 }
    }

    func arrived(_ payload: PushPayload) {
        if payload.kind != .nearby { friendsRevision += 1 }
    }
}

/// The texts the server names with `loc-key` (api-contract.md, "Push notifications"). iOS looks
/// them up in the string catalog itself; listing them here keeps them in it, and lets tests check them.
enum PushText {
    static let keys: [String] = [
        String(localized: "Friend request"),
        String(localized: "%@ wants to be friends"),
        String(localized: "New friend"),
        String(localized: "%@ accepted your friend request"),
        String(localized: "Friend nearby"),
        String(localized: "%@ is nearby"),
    ]
}
