import CoreLocation
import MapKit
import Observation

/// A place found by searching Apple Maps.
struct PlaceSearchResult: Equatable, Sendable, Identifiable {
    let id: String
    /// Apple's stable id for the place, when it has one.
    let appleId: String?
    let name: String
    /// An `MKPointOfInterestCategory` code; the app translates it for display.
    let category: String?
    let address: String?
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

protocol PlaceSearching: Sendable {
    /// Points of interest matching `query`, nearest to `region` first.
    func search(_ query: String, near region: MKCoordinateRegion?) async throws -> [PlaceSearchResult]
}

struct MapKitPlaceSearch: PlaceSearching {
    func search(_ query: String, near region: MKCoordinateRegion?) async throws -> [PlaceSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        if let region { request.region = region }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(15).compactMap { item in
            guard let name = item.name, !name.isEmpty else { return nil }
            let coordinate = item.placemark.coordinate
            let address = [item.placemark.thoroughfare, item.placemark.locality]
                .compactMap { $0 }
                .joined(separator: ", ")
            return PlaceSearchResult(
                id: item.identifier?.rawValue ?? "\(name)@\(coordinate.latitude),\(coordinate.longitude)",
                appleId: item.identifier?.rawValue,
                name: name,
                category: item.pointOfInterestCategory?.rawValue,
                address: address.isEmpty ? nil : address,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
    }
}

/// The search field in the bottom sheet: searches after a short pause in typing.
@MainActor
@Observable
final class PlaceSearchViewModel {
    static let minLength = 2

    var query = "" {
        didSet { if query != oldValue { queryChanged() } }
    }
    private(set) var results: [PlaceSearchResult] = []
    private(set) var isSearching = false
    private(set) var errorText: String?
    /// The search finished and found nothing (as opposed to not having searched yet).
    private(set) var foundNothing = false

    private let searcher: any PlaceSearching
    private var region: () -> MKCoordinateRegion?
    private let debounce: Duration
    private var task: Task<Void, Never>?

    init(
        searcher: any PlaceSearching,
        region: @escaping () -> MKCoordinateRegion? = { nil },
        debounce: Duration = .milliseconds(400)
    ) {
        self.searcher = searcher
        self.region = region
        self.debounce = debounce
    }

    /// The map's visible area, so results near it come first. Set once the map model exists.
    func setRegionProvider(_ provider: @escaping () -> MKCoordinateRegion?) {
        region = provider
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Something is typed: show search results instead of the friends row.
    var isActive: Bool { !trimmed.isEmpty }

    /// Typed, but too short to search yet.
    var needsMoreLetters: Bool { isActive && trimmed.count < Self.minLength }

    func clear() {
        query = ""
    }

    /// Waits for a pending search. Used by tests.
    func waitForSearch() async {
        await task?.value
    }

    private func queryChanged() {
        task?.cancel()
        errorText = nil
        foundNothing = false
        guard trimmed.count >= Self.minLength else {
            results = []
            isSearching = false
            return
        }
        let term = trimmed
        isSearching = true
        task = Task { [searcher, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            do {
                let found = try await searcher.search(term, near: region())
                guard !Task.isCancelled else { return }
                results = found
                foundNothing = found.isEmpty
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                errorText = String(localized: "The search didn't work. Try again.")
            }
            isSearching = false
        }
    }
}
