import CoreLocation
import Observation
import UIKit

/// What location permission allows for nearby alerts. They need "Always": with "While Using" iOS
/// only reports moves while Stoop is open.
enum BackgroundLocationAccess: Equatable, Sendable {
    case unknown
    case denied
    case whileUsing
    case always
}

/// Reports a coarse position after the phone moves about 500 m, even with Stoop closed, for
/// "a friend is nearby" alerts (iOS significant-location changes). A protocol so tests can stand in.
@MainActor
protocol NearbyReporting: AnyObject {
    var isEnabled: Bool { get }
    var locationAccess: BackgroundLocationAccess { get }
    func start()
    func stop()
    /// Asks for "Always" (iOS shows its prompt at most once; after that only Settings can change it).
    func requestAlwaysAccess()
}

@MainActor
@Observable
final class NearbyReporter: NSObject, NearbyReporting, CLLocationManagerDelegate {
    static let shared = NearbyReporter()

    /// Remembered between launches, because iOS relaunches the app in the background for a move and
    /// monitoring has to be switched on again then.
    private(set) var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }
    private(set) var locationAccess: BackgroundLocationAccess = .unknown
    @ObservationIgnored var api: (any NotificationsAPI)?
    /// Called when the server says the alerts are off (switched off on another phone, say).
    @ObservationIgnored var onTurnedOffElsewhere: (() -> Void)?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let defaults: UserDefaults
    private static let enabledKey = "nearby.enabled"
    /// The server ignores fixes coarser than this.
    static let worstAccuracy: CLLocationAccuracy = 1000

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        super.init()
        manager.delegate = self
        locationAccess = Self.access(for: manager.authorizationStatus)
    }

    /// At launch, including the background relaunches iOS does for a significant move.
    func resumeIfEnabled() {
        if isEnabled { manager.startMonitoringSignificantLocationChanges() }
    }

    func start() {
        isEnabled = true
        manager.startMonitoringSignificantLocationChanges()
    }

    func stop() {
        isEnabled = false
        manager.stopMonitoringSignificantLocationChanges()
    }

    func requestAlwaysAccess() {
        manager.requestAlwaysAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.locationAccess = Self.access(for: status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let fix = (location.coordinate.latitude, location.coordinate.longitude, location.horizontalAccuracy)
        Task { @MainActor in await self.report(latitude: fix.0, longitude: fix.1, accuracy: fix.2) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func report(latitude: Double, longitude: Double, accuracy: Double) async {
        guard isEnabled, let api, accuracy >= 0, accuracy <= Self.worstAccuracy else { return }
        // iOS gives a background launch only a few seconds; ask for a little more to finish the request
        let task = UIApplication.shared.beginBackgroundTask(withName: "nearby-position")
        defer { if task != .invalid { UIApplication.shared.endBackgroundTask(task) } }
        do {
            try await api.reportPosition(latitude: latitude, longitude: longitude, accuracy: accuracy)
        } catch let error as APIError where error.code == "nearby_alerts_off" {
            stop()
            onTurnedOffElsewhere?()
        } catch AuthError.sessionExpired {
            stop()
        } catch {
            // offline or busy: the next move reports again
        }
    }

    private static func access(for status: CLAuthorizationStatus) -> BackgroundLocationAccess {
        switch status {
        case .notDetermined: .unknown
        case .authorizedAlways: .always
        case .authorizedWhenInUse: .whileUsing
        default: .denied
        }
    }
}
