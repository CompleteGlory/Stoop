import Foundation

struct Avatar: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case preset
        case upload
    }

    let kind: Kind
    let value: String
    /// Nil for presets, which the app draws itself.
    let url: URL?
}

struct SelfUser: Codable, Equatable, Sendable {
    let id: String
    /// Nil until onboarding is finished.
    let username: String?
    let displayName: String
    let avatar: Avatar
    let ghostMode: Bool
    let createdAt: Date
}

struct AuthResponse: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    /// Seconds until `accessToken` expires.
    let expiresIn: Int
    let needsOnboarding: Bool
    let user: SelfUser
}

struct UsernameAvailability: Codable, Equatable, Sendable {
    enum Reason: String, Codable, Sendable {
        case taken
        case reserved
        case invalid
    }

    let available: Bool
    let reason: Reason?
}
