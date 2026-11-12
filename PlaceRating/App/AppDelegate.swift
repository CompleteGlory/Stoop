import UIKit
import UserNotifications

/// The UIKit hooks SwiftUI has no modifier for: the push token, notifications arriving or being
/// tapped, and background launches for a significant move (nearby alerts).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // after a background relaunch for a move, monitoring must be switched on again to get it
        MainActor.assumeIsolated { NearbyReporter.shared.resumeIfEnabled() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in await PushRegistrar.shared.received(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // the simulator without a push setup, or no network: nothing to do, the next launch tries again
    }

    /// With the app open, still show the banner (a friend nearby is worth seeing) and refresh the friends list.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if let payload = PushPayload(userInfo: notification.request.content.userInfo) {
            await MainActor.run { PushInbox.shared.arrived(payload) }
        }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let payload = PushPayload(userInfo: response.notification.request.content.userInfo) {
            await MainActor.run { PushInbox.shared.tapped(payload) }
        }
    }
}
