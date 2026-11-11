import Foundation

enum PhotoKind: String, Codable, Sendable, CaseIterable {
    case place
    case menu
}

/// A photo someone added to a place. `url` and `thumbnailUrl` are public and never change.
struct PlacePhoto: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let kind: PhotoKind
    let url: URL
    let thumbnailUrl: URL
    let width: Int
    let height: Int
    let createdAt: Date
    let user: PublicUser
}

struct PhotoPage: Codable, Equatable, Sendable {
    let items: [PlacePhoto]
    let nextCursor: String?
}

enum ReportReason: String, Codable, Sendable, CaseIterable {
    case spam, abuse, inappropriate, impersonation, other
}

/// Place and menu photos (api-contract.md, "Place photos"), plus reporting one.
protocol PhotosAPI: Sendable {
    func photos(placeId: String, kind: PhotoKind?, cursor: String?) async throws -> PhotoPage
    /// Uploads a JPEG in the three steps the API asks for: get a signed address, send the bytes
    /// there, then tell the API so it checks and re-encodes the photo.
    func addPhoto(placeId: String, kind: PhotoKind, jpeg: Data) async throws -> PlacePhoto
    func deletePhoto(placeId: String, photoId: String) async throws
    func reportPhoto(_ photoId: String, reason: ReportReason) async throws
}

extension APIClient: PhotosAPI {
    func photos(placeId: String, kind: PhotoKind?, cursor: String?) async throws -> PhotoPage {
        var query = [URLQueryItem(name: "limit", value: "30")]
        if let kind { query.append(URLQueryItem(name: "kind", value: kind.rawValue)) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let items = query
        return try await authorized { try http.request("GET", "places/\(placeId)/photos", query: items, token: $0) }
    }

    func addPhoto(placeId: String, kind: PhotoKind, jpeg: Data) async throws -> PlacePhoto {
        let ticket: UploadTicket = try await authorized {
            try http.request("POST", "places/\(placeId)/photos/upload-url",
                             body: UploadRequest(contentType: "image/jpeg", contentLength: jpeg.count), token: $0)
        }
        // straight to the bucket: no token, and exactly the signed headers and byte count
        var put = URLRequest(url: ticket.uploadUrl)
        put.httpMethod = ticket.method
        for (name, value) in ticket.headers { put.setValue(value, forHTTPHeaderField: name) }
        put.httpBody = jpeg
        let (_, response) = try await http.transport.send(put)
        guard (200..<300).contains(response.statusCode) else {
            throw APIError(status: response.statusCode, code: "upload_failed", message: "")
        }
        return try await authorized {
            try http.request("POST", "places/\(placeId)/photos", body: AddPhotoBody(kind: kind, key: ticket.key), token: $0)
        }
    }

    func deletePhoto(placeId: String, photoId: String) async throws {
        try await authorizedNoContent { try http.request("DELETE", "places/\(placeId)/photos/\(photoId)", token: $0) }
    }

    func reportPhoto(_ photoId: String, reason: ReportReason) async throws {
        let _: ReportResponse = try await authorized {
            try http.request("POST", "reports", body: ReportBody(targetType: "photo", targetId: photoId, reason: reason), token: $0)
        }
    }
}

private struct UploadRequest: Encodable {
    let contentType: String
    let contentLength: Int
}

private struct UploadTicket: Decodable {
    let key: String
    let uploadUrl: URL
    let method: String
    let headers: [String: String]
}

private struct AddPhotoBody: Encodable {
    let kind: PhotoKind
    let key: String
}

private struct ReportBody: Encodable {
    let targetType: String
    let targetId: String
    let reason: ReportReason
}

private struct ReportResponse: Decodable { let id: String }

/// Stands in when no photos API was given (previews, tests that don't need it).
struct UnavailablePhotosAPI: PhotosAPI {
    private struct Unavailable: Error {}
    func photos(placeId: String, kind: PhotoKind?, cursor: String?) async throws -> PhotoPage { PhotoPage(items: [], nextCursor: nil) }
    func addPhoto(placeId: String, kind: PhotoKind, jpeg: Data) async throws -> PlacePhoto { throw Unavailable() }
    func deletePhoto(placeId: String, photoId: String) async throws { throw Unavailable() }
    func reportPhoto(_ photoId: String, reason: ReportReason) async throws { throw Unavailable() }
}
