import Foundation

/// Places, ratings and friends (api-contract.md). Separate from sign-in so each can be faked alone.
protocol PlacesAPI: Sendable {
    func places(in box: BoundingBox) async throws -> [Place]
    /// Finds or creates the place for a point of interest the person tapped.
    func resolvePlace(appleId: String?, name: String, category: String?, latitude: Double, longitude: Double) async throws -> Place
    func place(id: String) async throws -> PlaceDetail
    /// Create-or-replace; repeating the same body changes nothing, so retries are safe.
    func rate(placeId: String, stars: Int, comment: String?) async throws -> RatingResult
    func deleteRating(placeId: String) async throws
    func ratings(placeId: String, cursor: String?) async throws -> RatingPage
    func friends() async throws -> FriendsList
}

extension APIClient: PlacesAPI {
    func places(in box: BoundingBox) async throws -> [Place] {
        let query = [URLQueryItem(name: "bbox", value: box.queryValue)]
        let page: Items<Place> = try await authorized { try http.request("GET", "places", query: query, token: $0) }
        return page.items
    }

    func resolvePlace(appleId: String?, name: String, category: String?, latitude: Double, longitude: Double) async throws -> Place {
        let body = ResolveBody(
            appleId: appleId,
            name: String(name.prefix(120)),
            category: category.map { String($0.prefix(60)) },
            latitude: latitude,
            longitude: longitude
        )
        return try await authorized { try http.request("POST", "places/resolve", body: body, token: $0) }
    }

    func place(id: String) async throws -> PlaceDetail {
        try await authorized { try http.request("GET", "places/\(id)", token: $0) }
    }

    func rate(placeId: String, stars: Int, comment: String?) async throws -> RatingResult {
        let body = RatingBody(stars: stars, comment: comment)
        return try await authorized { try http.request("PUT", "places/\(placeId)/rating", body: body, token: $0) }
    }

    func deleteRating(placeId: String) async throws {
        try await authorizedNoContent { try http.request("DELETE", "places/\(placeId)/rating", token: $0) }
    }

    func ratings(placeId: String, cursor: String?) async throws -> RatingPage {
        var query = [URLQueryItem(name: "limit", value: "50")]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let items = query
        return try await authorized { try http.request("GET", "places/\(placeId)/ratings", query: items, token: $0) }
    }

    func friends() async throws -> FriendsList {
        try await authorized { try http.request("GET", "friends", token: $0) }
    }
}

private struct Items<T: Decodable>: Decodable { let items: [T] }

private struct ResolveBody: Encodable {
    let appleId: String?
    let name: String
    let category: String?
    let latitude: Double
    let longitude: Double
}

/// `comment` is always sent, as null when empty, so saving stars never wipes a comment by accident
/// and clearing the field really clears it.
private struct RatingBody: Encodable {
    let stars: Int
    let comment: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stars, forKey: .stars)
        try container.encode(comment, forKey: .comment)
    }

    private enum CodingKeys: String, CodingKey { case stars, comment }
}

/// Stands in when no places API was given (previews, tests that don't need it).
struct UnavailablePlacesAPI: PlacesAPI {
    private struct Unavailable: Error {}
    func places(in box: BoundingBox) async throws -> [Place] { [] }
    func resolvePlace(appleId: String?, name: String, category: String?, latitude: Double, longitude: Double) async throws -> Place { throw Unavailable() }
    func place(id: String) async throws -> PlaceDetail { throw Unavailable() }
    func rate(placeId: String, stars: Int, comment: String?) async throws -> RatingResult { throw Unavailable() }
    func deleteRating(placeId: String) async throws { throw Unavailable() }
    func ratings(placeId: String, cursor: String?) async throws -> RatingPage { throw Unavailable() }
    func friends() async throws -> FriendsList { throw Unavailable() }
}
