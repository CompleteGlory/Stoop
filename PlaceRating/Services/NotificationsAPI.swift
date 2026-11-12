import Foundation

/// Which Apple push service a device token belongs to: builds run from Xcode get sandbox tokens,
/// TestFlight and App Store builds production ones.
enum PushEnvironment: String, Encodable, Sendable {
    case sandbox
    case production

    static var current: PushEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }
}

/// Push devices, the nearby-alerts switch and background positions (api-contract.md, "Push notifications").
protocol NotificationsAPI: Sendable {
    func registerDevice(token: String, environment: PushEnvironment) async throws
    func unregisterDevice(token: String) async throws
    func setNearbyAlerts(_ on: Bool) async throws -> SelfUser
    /// Only for the nearby check; the server answers 409 `nearby_alerts_off` when the switch is off.
    func reportPosition(latitude: Double, longitude: Double, accuracy: Double) async throws
}

extension APIClient: NotificationsAPI {
    func registerDevice(token: String, environment: PushEnvironment) async throws {
        try await authorizedNoContent {
            try http.request("PUT", "me/devices/\(token)", body: ["environment": environment.rawValue], token: $0)
        }
    }

    func unregisterDevice(token: String) async throws {
        try await authorizedNoContent { try http.request("DELETE", "me/devices/\(token)", token: $0) }
    }

    func setNearbyAlerts(_ on: Bool) async throws -> SelfUser {
        try await authorized { try http.request("PATCH", "me", body: ["nearbyAlerts": on], token: $0) }
    }

    func reportPosition(latitude: Double, longitude: Double, accuracy: Double) async throws {
        let body = PositionBody(lat: latitude, lng: longitude, accuracy: accuracy)
        try await authorizedNoContent { try http.request("POST", "me/position", body: body, token: $0) }
    }
}

private struct PositionBody: Encodable {
    let lat: Double
    let lng: Double
    let accuracy: Double
}

/// Stands in when no notifications API was given (previews, tests that don't need it).
struct UnavailableNotificationsAPI: NotificationsAPI {
    private struct Unavailable: Error {}
    func registerDevice(token: String, environment: PushEnvironment) async throws {}
    func unregisterDevice(token: String) async throws {}
    func setNearbyAlerts(_ on: Bool) async throws -> SelfUser { throw Unavailable() }
    func reportPosition(latitude: Double, longitude: Double, accuracy: Double) async throws {}
}
