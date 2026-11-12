import CoreLocation
import Foundation

/// Rated places, kept hexagon by hexagon. Showing an area uses what is cached straight away;
/// whatever is missing or older than five minutes comes back in one request for all of it.
/// Preloading fills the hexagons around you before you look at them.
@MainActor
final class PlacesChunkCache {
    private struct Chunk {
        var places: [Place]
        var fetchedAt: Date
    }

    static let freshFor: TimeInterval = 300

    private let api: any PlacesAPI
    private let now: () -> Date
    private var chunks: [HexCell: Chunk] = [:]
    private var loading: Set<HexCell> = []
    /// Called after new places arrive, so the map can redraw its pins.
    var onUpdate: () -> Void = {}

    init(api: any PlacesAPI, now: @escaping () -> Date = { Date() }) {
        self.api = api
        self.now = now
    }

    /// Whatever is cached for these hexagons, fresh or not: shown at once, refreshed after.
    func places(in cells: [HexCell]) -> [Place] {
        cells.flatMap { chunks[$0]?.places ?? [] }
    }

    func isFresh(_ cell: HexCell) -> Bool {
        guard let chunk = chunks[cell] else { return false }
        return now().timeIntervalSince(chunk.fetchedAt) < Self.freshFor
    }

    /// Fetches the hexagons that are missing or stale, in a single request. Returns whether it asked.
    @discardableResult
    func load(_ cells: [HexCell]) async -> Bool {
        let wanted = cells.filter { !isFresh($0) && !loading.contains($0) }
        guard !wanted.isEmpty, let box = HexGrid.box(around: wanted) else { return false }
        loading.formUnion(wanted)
        defer { loading.subtract(wanted) }
        guard let found = try? await api.places(in: box) else { return true }
        let byCell = Dictionary(grouping: found) { HexGrid.cell(for: $0.coordinate) }
        let fetchedAt = now()
        for cell in wanted {
            chunks[cell] = Chunk(places: byCell[cell] ?? [], fetchedAt: fetchedAt)
        }
        onUpdate()
        return true
    }

    /// Loads the hexagons around a spot (`radius` 2 is 19 hexagons, about 7 km across).
    func preload(around coordinate: CLLocationCoordinate2D, radius: Int) async {
        await load(HexGrid.disk(around: HexGrid.cell(for: coordinate), radius: radius))
    }

    /// Keeps the cache in step with a rating made in the sheet.
    func update(_ place: Place) {
        let cell = HexGrid.cell(for: place.coordinate)
        guard var chunk = chunks[cell] else { return }
        chunk.places.removeAll { $0.id == place.id }
        chunk.places.append(place)
        chunks[cell] = chunk
        onUpdate()
    }

    func removeAll() {
        chunks.removeAll()
    }
}
