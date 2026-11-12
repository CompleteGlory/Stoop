import Foundation

/// Links that open Stoop on something. A shared place is `https://<api>/p/<placeId>` (a universal
/// link, so WhatsApp and Instagram make it tappable, and a web page for people without the app),
/// or `stoop://place/<placeId>`, which that web page's Open in Stoop button uses.
enum DeepLink: Equatable, Sendable {
    case place(id: String)
    /// The friends list, from a friend request notification. Never parsed from a URL.
    case friends
    /// A friend's marker (or the friends list when they aren't sharing), from a "nearby" notification.
    case friend(id: String)

    static let scheme = "stoop"

    /// Nil for any other link, such as Google Sign-In's callback.
    init?(url: URL, apiBaseURL: URL = AppConfig.current.apiBaseURL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        let id: String?
        switch url.scheme?.lowercased() {
        case Self.scheme:
            id = url.host() == "place" ? parts.first : nil
        case "https", "http":
            let hosts = [apiBaseURL.host(), AppConfig.production.apiBaseURL.host()].compactMap { $0?.lowercased() }
            guard let host = url.host()?.lowercased(), hosts.contains(host) else { return nil }
            id = parts.count == 2 && parts[0] == "p" ? parts[1] : nil
        default:
            id = nil
        }
        guard let id, let uuid = UUID(uuidString: id) else { return nil }
        self = .place(id: uuid.uuidString.lowercased())
    }
}

/// Where a place can be sent: its Stoop link and Google Maps.
enum PlaceLinks {
    static func share(_ place: Place, apiBaseURL: URL = AppConfig.current.apiBaseURL) -> URL {
        apiBaseURL.appending(path: "p/\(place.id)")
    }

    /// Opens the Google Maps app when it is installed (Google handles this link), the website otherwise.
    static func googleMaps(_ place: Place) -> URL {
        var components = URLComponents(string: "https://www.google.com/maps/search/")!
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: "\(place.latitude),\(place.longitude)"),
        ]
        return components.url!
    }
}
