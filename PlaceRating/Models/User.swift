import Foundation

/// A DiceBear character: the style and the chosen option for each part. The app draws it.
struct Avatar: Codable, Hashable, Sendable {
    var style: String
    var options: [String: String]
}

struct SelfUser: Codable, Equatable, Sendable {
    let id: String
    /// Nil until onboarding is finished.
    let username: String?
    let displayName: String
    /// Nil until the person has made a character.
    let avatar: Avatar?
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
