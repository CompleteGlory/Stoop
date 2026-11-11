import CoreLocation
import Foundation

/// Another person as the API shows them.
struct PublicUser: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let username: String?
    let displayName: String
    let avatar: Avatar?

    /// What to call them: the display name, else the username.
    var name: String {
        displayName.isEmpty ? (username ?? "") : displayName
    }
}

struct Place: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let appleId: String?
    let name: String
    /// A stable category code (`MKPOICategoryCafe`); the app translates it for display.
    let category: String?
    let latitude: Double
    let longitude: Double
    /// 0 when nobody rated it yet, otherwise rounded to 2 decimals.
    let avgRating: Double
    let ratingCount: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct MyRating: Codable, Equatable, Sendable {
    let id: String
    let stars: Int
    let comment: String?
    let updatedAt: Date
}

/// `GET /places/:id`: the place plus your own rating.
struct PlaceDetail: Codable, Equatable, Sendable {
    let place: Place
    let myRating: MyRating?

    init(place: Place, myRating: MyRating?) {
        self.place = place
        self.myRating = myRating
    }

    // the API returns the place's fields and `myRating` side by side
    init(from decoder: Decoder) throws {
        place = try Place(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        myRating = try container.decodeIfPresent(MyRating.self, forKey: .myRating)
    }

    func encode(to encoder: Encoder) throws {
        try place.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(myRating, forKey: .myRating)
    }

    private enum CodingKeys: String, CodingKey { case myRating }
}

struct PlaceRating: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let stars: Int
    let comment: String?
    let createdAt: Date
    let updatedAt: Date
    let user: PublicUser
}

struct RatingPage: Codable, Equatable, Sendable {
    let items: [PlaceRating]
    let nextCursor: String?
}

/// `PUT /places/:id/rating`: your rating and the place with its new average.
struct RatingResult: Codable, Equatable, Sendable {
    struct Rating: Codable, Equatable, Sendable {
        let id: String
        let stars: Int
        let comment: String?
        let updatedAt: Date
    }

    let rating: Rating
    let place: Place
}

struct FriendshipEntry: Codable, Equatable, Sendable, Identifiable {
    /// The friendship id, used to accept an incoming request.
    let id: String
    let user: PublicUser
    let since: Date
}

struct FriendsList: Codable, Equatable, Sendable {
    let friends: [FriendshipEntry]
    let incoming: [FriendshipEntry]
    let outgoing: [FriendshipEntry]
}

/// A map area in degrees. The API refuses boxes wider than 5° either way.
struct BoundingBox: Equatable, Sendable {
    static let maxSpan = 5.0

    let minLongitude: Double
    let minLatitude: Double
    let maxLongitude: Double
    let maxLatitude: Double

    init(minLongitude: Double, minLatitude: Double, maxLongitude: Double, maxLatitude: Double) {
        self.minLongitude = minLongitude
        self.minLatitude = minLatitude
        self.maxLongitude = maxLongitude
        self.maxLatitude = maxLatitude
    }

    /// The box around a visible map region, or nil when it is too big to ask for
    /// (zoomed far out, or crossing the 180° meridian).
    init?(center: CLLocationCoordinate2D, latitudeDelta: Double, longitudeDelta: Double) {
        let minLng = center.longitude - longitudeDelta / 2
        let maxLng = center.longitude + longitudeDelta / 2
        let minLat = max(-90, center.latitude - latitudeDelta / 2)
        let maxLat = min(90, center.latitude + latitudeDelta / 2)
        guard longitudeDelta > 0, latitudeDelta > 0,
              longitudeDelta <= Self.maxSpan, latitudeDelta <= Self.maxSpan,
              minLng >= -180, maxLng <= 180 else { return nil }
        self.init(minLongitude: minLng, minLatitude: minLat, maxLongitude: maxLng, maxLatitude: maxLat)
    }

    var queryValue: String {
        [minLongitude, minLatitude, maxLongitude, maxLatitude]
            .map { String(format: "%.6f", $0) }
            .joined(separator: ",")
    }
}
