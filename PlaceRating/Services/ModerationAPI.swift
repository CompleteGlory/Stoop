import Foundation

enum ReportTarget: String, Codable, Sendable {
    case user, rating, photo
}

enum ReportReason: String, Codable, Sendable, CaseIterable {
    case spam, abuse, inappropriate, impersonation, other
}

/// Reports and blocks (api-contract.md, "Friends and blocks" and "Reports").
protocol ModerationAPI: Sendable {
    func report(_ target: ReportTarget, id: String, reason: ReportReason) async throws
    func blocks() async throws -> [PublicUser]
    /// Also removes any friendship or request between you.
    func block(userId: String) async throws
    func unblock(userId: String) async throws
}

extension APIClient: ModerationAPI {
    func report(_ target: ReportTarget, id: String, reason: ReportReason) async throws {
        let body = ReportBody(targetType: target, targetId: id, reason: reason)
        let _: ReportResponse = try await authorized { try http.request("POST", "reports", body: body, token: $0) }
    }

    func blocks() async throws -> [PublicUser] {
        let page: BlocksPage = try await authorized { try http.request("GET", "blocks", token: $0) }
        return page.items
    }

    func block(userId: String) async throws {
        try await authorizedNoContent { try http.request("POST", "blocks", body: BlockBody(userId: userId), token: $0) }
    }

    func unblock(userId: String) async throws {
        try await authorizedNoContent { try http.request("DELETE", "blocks/\(userId)", token: $0) }
    }
}

private struct ReportBody: Encodable {
    let targetType: ReportTarget
    let targetId: String
    let reason: ReportReason
}

private struct ReportResponse: Decodable { let id: String }
private struct BlocksPage: Decodable { let items: [PublicUser] }
private struct BlockBody: Encodable { let userId: String }

/// Stands in when no moderation API was given (previews, tests that don't need it).
struct UnavailableModerationAPI: ModerationAPI {
    private struct Unavailable: Error {}
    func report(_ target: ReportTarget, id: String, reason: ReportReason) async throws { throw Unavailable() }
    func blocks() async throws -> [PublicUser] { [] }
    func block(userId: String) async throws { throw Unavailable() }
    func unblock(userId: String) async throws { throw Unavailable() }
}
