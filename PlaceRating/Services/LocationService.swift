import CoreLocation

enum LocationAccess: Equatable, Sendable {
    /// The person hasn't been asked yet.
    case unknown
    case denied
    case allowed
}

/// Where the person is, while the app is in the foreground. No background location.
@MainActor
protocol LocationServiceProtocol: AnyObject {
    var access: LocationAccess { get }
    var onAccessChange: ((LocationAccess) -> Void)? { get set }
    func requestAccess()
    /// Positions until the stream is cancelled.
    func updates() -> AsyncStream<CLLocation>
}

@MainActor
final class LiveLocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var access: LocationAccess = .unknown
    var onAccessChange: ((LocationAccess) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        access = Self.access(for: manager.authorizationStatus)
    }

    func requestAccess() {
        manager.requestWhenInUseAuthorization()
    }

    func updates() -> AsyncStream<CLLocation> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location { continuation.yield(location) }
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.access = Self.access(for: status)
            self.onAccessChange?(self.access)
        }
    }

    private static func access(for status: CLAuthorizationStatus) -> LocationAccess {
        switch status {
        case .notDetermined: .unknown
        case .authorizedWhenInUse, .authorizedAlways: .allowed
        default: .denied
        }
    }
}

/// When to send a position to friends (live-protocol.md): at most every 3 s, only after moving
/// 10 m, but at least every 15 s so the server's 60 s expiry never lapses while standing still.
struct SendThrottle {
    static let minInterval: TimeInterval = 3
    static let minDistance: CLLocationDistance = 10
    static let heartbeat: TimeInterval = 15
    static let worstAccuracy: CLLocationAccuracy = 100

    private(set) var last: (location: CLLocation, at: Date)?

    func shouldSend(_ location: CLLocation, now: Date) -> Bool {
        let accuracy = location.horizontalAccuracy
        guard accuracy >= 0, accuracy <= Self.worstAccuracy else { return false }
        guard let last else { return true }
        let elapsed = now.timeIntervalSince(last.at)
        if elapsed < Self.minInterval { return false }
        if elapsed >= Self.heartbeat { return true }
        return location.distance(from: last.location) >= Self.minDistance
    }

    mutating func didSend(_ location: CLLocation, at now: Date) {
        last = (location, now)
    }
}
