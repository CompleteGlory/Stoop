import CoreLocation
import MapKit
import Foundation
import Testing
@testable import PlaceRating

private func result(_ name: String, appleId: String? = "I1") -> PlaceSearchResult {
    PlaceSearchResult(id: appleId ?? name, appleId: appleId, name: name, category: "MKPOICategoryCafe",
                      address: "Tahrir St, Cairo", latitude: 30.05, longitude: 31.24)
}

final class FakeSearcher: PlaceSearching, @unchecked Sendable {
    private let lock = NSLock()
    private var _queries: [String] = []
    private var _regions: [MKCoordinateRegion?] = []
    var results: [PlaceSearchResult] = []
    var failure: Error?

    var queries: [String] { lock.withLock { _queries } }
    var regions: [MKCoordinateRegion?] { lock.withLock { _regions } }

    func search(_ query: String, near region: MKCoordinateRegion?) async throws -> [PlaceSearchResult] {
        lock.withLock {
            _queries.append(query)
            _regions.append(region)
        }
        if let failure { throw failure }
        return results
    }
}

@MainActor
struct PlaceSearchViewModelTests {
    private func make(_ searcher: FakeSearcher) -> PlaceSearchViewModel {
        PlaceSearchViewModel(searcher: searcher, debounce: .milliseconds(10))
    }

    @Test func typingSearchesOnceAfterAPause() async {
        let searcher = FakeSearcher()
        searcher.results = [result("Stoop Café")]
        let model = make(searcher)

        model.query = "ca"
        model.query = "caf"
        model.query = " cafe "
        #expect(model.isSearching)
        await model.waitForSearch()

        #expect(searcher.queries == ["cafe"])
        #expect(model.results.map(\.name) == ["Stoop Café"])
        #expect(!model.isSearching)
        #expect(!model.foundNothing)
    }

    @Test func waitsForTwoLettersBeforeSearching() async {
        let searcher = FakeSearcher()
        let model = make(searcher)

        model.query = "c"
        await model.waitForSearch()
        #expect(searcher.queries.isEmpty)
        #expect(model.isActive)
        #expect(model.needsMoreLetters)

        model.query = "  "
        #expect(!model.isActive)
    }

    @Test func clearingEmptiesTheResults() async {
        let searcher = FakeSearcher()
        searcher.results = [result("A")]
        let model = make(searcher)
        model.query = "cafe"
        await model.waitForSearch()
        #expect(!model.results.isEmpty)

        model.clear()
        #expect(model.results.isEmpty)
        #expect(!model.isActive)
        #expect(!model.isSearching)
    }

    @Test func sayssoWhenNothingMatchesOrTheSearchFails() async {
        let searcher = FakeSearcher()
        let model = make(searcher)
        model.query = "zzzz"
        await model.waitForSearch()
        #expect(model.foundNothing)
        #expect(model.errorText == nil)

        searcher.failure = URLError(.notConnectedToInternet)
        model.query = "zzzzz"
        await model.waitForSearch()
        #expect(model.errorText != nil)
        #expect(!model.foundNothing)
        #expect(model.results.isEmpty)
    }
}

@MainActor
struct MapSearchTests {
    private func make(_ searcher: FakeSearcher, places: FakePlacesAPI = FakePlacesAPI()) -> MapViewModel {
        MapViewModel(user: makeUser(), location: FakeLocation(access: .allowed), socket: FakeLiveSocket(),
                     places: places, searcher: searcher, searchDebounce: .milliseconds(10))
    }

    @Test func searchesNearWhatTheMapShows() async {
        let searcher = FakeSearcher()
        let model = make(searcher)
        model.search.query = "cafe"
        await model.search.waitForSearch()
        #expect(searcher.regions.last! == nil) // the map hasn't settled yet

        model.cameraSettled(center: CLLocationCoordinate2D(latitude: 30, longitude: 31), latitudeDelta: 0.02, longitudeDelta: 0.01)
        model.search.query = "bakery"
        await model.search.waitForSearch()
        let region = searcher.regions.last!
        #expect(region?.center.latitude == 30)
        #expect(region?.span.longitudeDelta == 0.01)
    }

    @Test func tappingAResultOpensItsPlaceSheetAndClearsTheSearch() async {
        let searcher = FakeSearcher()
        searcher.results = [result("Stoop Café")]
        let places = FakePlacesAPI()
        let model = make(searcher, places: places)
        model.search.query = "stoop"
        await model.search.waitForSearch()

        await model.openSearchResult(model.search.results[0])
        #expect(model.sheet == .place)
        #expect(model.placeModel?.name == "Stoop Café")
        await model.placeModel?.load()

        #expect(places.calls.first == "resolve I1 Stoop Café")
        #expect(model.placeModel?.placeId == "p1")
        #expect(model.detent == .medium)
        #expect(!model.search.isActive)
        #expect(model.search.results.isEmpty)
    }
}
