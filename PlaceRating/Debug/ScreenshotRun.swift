#if DEBUG
import Foundation
import MapKit
import SwiftUI

/// Launch arguments for taking App Store screenshots without tapping through the app. Debug builds
/// only; Release builds don't contain this file's code. For example:
///
///     xcrun simctl launch <device> com.magdzaky.PlaceRating \
///       -ScreenshotSignIn karim -ScreenshotPlace <placeId> -ScreenshotDetent large -settings.language ar
///
/// `-settings.language` is the app's own language setting (`en` or `ar`), read through UserDefaults.
@MainActor
enum ScreenshotRun {
    private static var defaults: UserDefaults { .standard }

    /// Signs in through the local API's dev sign-in as this username.
    static var signInAs: String? { defaults.string(forKey: "ScreenshotSignIn") }

    /// Opens a place (`-ScreenshotPlace <id>`) or a sheet (`-ScreenshotSheet friends|settings`)
    /// once the map has had a moment to load, at `-ScreenshotDetent medium|large`.
    /// `-ScreenshotCenter 30.0486,31.2400 -ScreenshotSpan 700` also frames the map on that spot, that many metres across.
    static func openSheet(on model: MapViewModel) async {
        let place = defaults.string(forKey: "ScreenshotPlace")
        let sheet = defaults.string(forKey: "ScreenshotSheet")
        let center = defaults.string(forKey: "ScreenshotCenter")?.split(separator: ",").compactMap { Double($0) }
        guard place != nil || sheet != nil || center != nil else { return }
        try? await Task.sleep(for: .seconds(2))
        if let center, center.count == 2 {
            let span = defaults.double(forKey: "ScreenshotSpan")
            model.camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: center[0], longitude: center[1]),
                latitudinalMeters: span > 0 ? span : 700, longitudinalMeters: span > 0 ? span : 700
            ))
        }
        if let place { model.openShared(.place(id: place)) }
        switch sheet {
        case "friends": model.showFriends()
        case "settings": model.showSettings()
        default: break
        }
        switch defaults.string(forKey: "ScreenshotDetent") {
        case "large": model.detent = .large
        case "medium": model.detent = .medium
        default: break
        }
    }
}
#endif
