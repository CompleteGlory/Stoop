import CoreLocation
import MapKit

/// One hexagon of a worldwide grid. Rated places are cached and preloaded hexagon by hexagon,
/// so moving the map shows what is already known at once and only asks for what is missing.
struct HexCell: Hashable, Sendable {
    let q: Int
    let r: Int
}

/// Pointy-top hexagons in axial coordinates, laid over Web Mercator so the grid is the same
/// everywhere. A hexagon is about 1.5 km across around Cairo.
enum HexGrid {
    /// Corner-to-centre distance, in Web Mercator metres.
    static let size = 1_000.0
    private static let earthRadius = 6_378_137.0
    private static let root3 = 3.0.squareRoot()

    static func cell(for coordinate: CLLocationCoordinate2D) -> HexCell {
        let (x, y) = project(coordinate)
        let q = (root3 / 3 * x - y / 3) / size
        let r = (2.0 / 3 * y) / size
        return round(q: q, r: r)
    }

    static func center(of cell: HexCell) -> CLLocationCoordinate2D {
        let x = size * root3 * (Double(cell.q) + Double(cell.r) / 2)
        let y = size * 1.5 * Double(cell.r)
        return unproject(x: x, y: y)
    }

    static func corners(of cell: HexCell) -> [CLLocationCoordinate2D] {
        let cx = size * root3 * (Double(cell.q) + Double(cell.r) / 2)
        let cy = size * 1.5 * Double(cell.r)
        return (0..<6).map { i in
            let angle = (60.0 * Double(i) - 30) * .pi / 180
            return unproject(x: cx + size * cos(angle), y: cy + size * sin(angle))
        }
    }

    /// The hexagons within `radius` steps of `cell`, the cell itself included (1, 7, 19, 37…).
    static func disk(around cell: HexCell, radius: Int) -> [HexCell] {
        var cells: [HexCell] = []
        for dq in -radius...radius {
            for dr in max(-radius, -dq - radius)...min(radius, -dq + radius) {
                cells.append(HexCell(q: cell.q + dq, r: cell.r + dr))
            }
        }
        return cells
    }

    /// The hexagons that touch a map region, or nil when there would be more than `limit`
    /// (zoomed out too far to be worth caching in chunks).
    static func cells(covering region: MKCoordinateRegion, limit: Int = 400) -> [HexCell]? {
        let lat = region.span.latitudeDelta / 2, lng = region.span.longitudeDelta / 2
        let (x0, y0) = project(CLLocationCoordinate2D(latitude: max(-85, region.center.latitude - lat), longitude: region.center.longitude - lng))
        let (x1, y1) = project(CLLocationCoordinate2D(latitude: min(85, region.center.latitude + lat), longitude: region.center.longitude + lng))
        let rMin = Int(floor(y0 / (1.5 * size))) - 1, rMax = Int(ceil(y1 / (1.5 * size))) + 1
        let rows = rMax - rMin + 1
        let columns = Int(ceil((x1 - x0) / (root3 * size))) + 3
        guard rows > 0, columns > 0, rows * columns <= limit * 2 else { return nil }
        var cells: [HexCell] = []
        for r in rMin...rMax {
            let qMin = Int(floor(x0 / (root3 * size) - Double(r) / 2)) - 1
            let qMax = Int(ceil(x1 / (root3 * size) - Double(r) / 2)) + 1
            for q in qMin...qMax {
                let cx = size * root3 * (Double(q) + Double(r) / 2), cy = size * 1.5 * Double(r)
                // keep cells whose hexagon can overlap the region
                if cx >= x0 - size, cx <= x1 + size, cy >= y0 - size, cy <= y1 + size {
                    cells.append(HexCell(q: q, r: r))
                }
            }
        }
        return cells.count <= limit ? cells : nil
    }

    /// One box that holds every given hexagon, or nil if it would be too big for the API (5°).
    static func box(around cells: some Collection<HexCell>) -> BoundingBox? {
        let points = cells.flatMap(corners(of:))
        guard let minLat = points.map(\.latitude).min(), let maxLat = points.map(\.latitude).max(),
              let minLng = points.map(\.longitude).min(), let maxLng = points.map(\.longitude).max(),
              maxLat - minLat <= BoundingBox.maxSpan, maxLng - minLng <= BoundingBox.maxSpan,
              minLng >= -180, maxLng <= 180 else { return nil }
        return BoundingBox(minLongitude: minLng, minLatitude: minLat, maxLongitude: maxLng, maxLatitude: maxLat)
    }

    // MARK: math

    private static func project(_ c: CLLocationCoordinate2D) -> (Double, Double) {
        let lat = min(85, max(-85, c.latitude)) * .pi / 180
        return (earthRadius * c.longitude * .pi / 180, earthRadius * log(tan(.pi / 4 + lat / 2)))
    }

    private static func unproject(x: Double, y: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (2 * atan(exp(y / earthRadius)) - .pi / 2) * 180 / .pi,
            longitude: x / earthRadius * 180 / .pi
        )
    }

    /// Rounds fractional axial coordinates to the hexagon that contains them.
    private static func round(q: Double, r: Double) -> HexCell {
        let s = -q - r
        var rq = q.rounded(), rr = r.rounded()
        let rs = s.rounded()
        let dq = abs(rq - q), dr = abs(rr - r), ds = abs(rs - s)
        if dq > dr && dq > ds { rq = -rr - rs } else if dr > ds { rr = -rq - rs }
        return HexCell(q: Int(rq), r: Int(rr))
    }
}
