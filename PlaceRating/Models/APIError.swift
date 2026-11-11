import Foundation

/// An error answered by the server. Switch on `code`; `message` is for debugging only.
struct APIError: Error, Equatable, Sendable {
    let status: Int
    let code: String
    let message: String
}

enum AuthError: Error, Equatable, Sendable {
    /// The session is gone for good and the person has to sign in again.
    case sessionExpired
}

struct APIErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
    }

    let error: Body
}
