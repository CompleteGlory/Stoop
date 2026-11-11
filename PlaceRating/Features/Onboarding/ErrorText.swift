import Foundation

/// Translated text for an error. Switches on the server's stable `code`, never its `message`.
enum ErrorText {
    static func text(for error: Error) -> String {
        switch error {
        case is URLError:
            String(localized: "We couldn't reach the server.")
        case AuthError.sessionExpired:
            String(localized: "Your session has expired. Sign in again.")
        case let error as APIError:
            text(forCode: error.code)
        default:
            String(localized: "Something went wrong. Try again.")
        }
    }

    private static func text(forCode code: String) -> String {
        switch code {
        case "username_taken": String(localized: "That username is taken.")
        case "username_reserved": String(localized: "That username isn't available.")
        case "validation_failed": String(localized: "Use 3 to 20 letters, digits, _ or .")
        case "rate_limited": String(localized: "Too many attempts. Try again later.")
        case "unauthorized": String(localized: "Sign in failed. Try again.")
        default: String(localized: "Something went wrong. Try again.")
        }
    }
}
