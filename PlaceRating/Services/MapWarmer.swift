import CoreLocation
import MapKit

/// Asks MapKit for the map around a spot ahead of time (at a few zoom levels), so its tiles are
/// already cached when the map shows that area. Best effort: failures are ignored.
enum MapWarmer {
    /// Street, neighbourhood and district views.
    static let spans: [CLLocationDistance] = [900, 3_000, 10_000]

    @MainActor
    static func warmTiles(around coordinate: CLLocationCoordinate2D) {
        for meters in spans {
            Task { await snapshot(around: coordinate, meters: meters) }
        }
    }

    private static func snapshot(around coordinate: CLLocationCoordinate2D, meters: CLLocationDistance) async {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: meters, longitudinalMeters: meters)
        options.size = CGSize(width: 390, height: 844)
        options.pointOfInterestFilter = .includingAll
        _ = try? await MKMapSnapshotter(options: options).start()
    }

    /// The phone's last known position, if location is already allowed (never asks).
    @MainActor
    static var lastKnownLocation: CLLocationCoordinate2D? {
        let manager = CLLocationManager()
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return manager.location?.coordinate
        default: return nil
        }
    }
}
