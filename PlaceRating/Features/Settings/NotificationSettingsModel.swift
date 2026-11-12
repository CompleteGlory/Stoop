import Foundation
import Observation

/// The Notifications part of Settings: the system permission, and the "nearby friends" switch,
/// which needs notifications, the server's `nearbyAlerts` and background location together.
@MainActor
@Observable
final class NotificationSettingsModel {
    private(set) var isSaving = false
    private(set) var error: String?

    private let session: SessionStore
    private let api: any NotificationsAPI
    private let push: any PushRegistering
    private let nearby: any NearbyReporting

    init(session: SessionStore, push: any PushRegistering, nearby: any NearbyReporting, api: (any NotificationsAPI)? = nil) {
        self.session = session
        self.api = api ?? session.notifications
        self.push = push
        self.nearby = nearby
    }

    var notifications: NotificationAccess { push.access }
    var nearbyOn: Bool { nearby.isEnabled }
    var location: BackgroundLocationAccess { nearby.locationAccess }
    /// On, but iOS only lets Stoop see moves while it is open.
    var needsAlwaysLocation: Bool { nearbyOn && location != .always }

    func appeared() async {
        await push.refresh()
    }

    func allowNotifications() async {
        _ = await push.requestAccess()
    }

    func setNearby(_ on: Bool) async {
        guard on != nearbyOn, !isSaving else { return }
        error = nil
        if on, push.access != .allowed {
            guard await push.requestAccess() else {
                error = tr("Allow notifications for Stoop in Settings to get nearby alerts.")
                return
            }
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let user = try await api.setNearbyAlerts(on)
            session.usernameChosen(user)
            if user.nearbyAlerts ?? on {
                nearby.start()
                if location != .always { nearby.requestAlwaysAccess() }
            } else {
                nearby.stop()
            }
        } catch AuthError.sessionExpired {
            session.sessionExpired()
        } catch {
            self.error = ErrorText.text(for: error)
        }
    }

    func askForAlwaysLocation() {
        nearby.requestAlwaysAccess()
    }
}
