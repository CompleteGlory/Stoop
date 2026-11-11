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
        case "invalid_credentials": String(localized: "Wrong email or password.")
        case "invalid_code": String(localized: "That code is wrong or has expired.")
        case "email_not_verified": String(localized: "Confirm your email first. We sent you a new code.")
        case "invalid_avatar": String(localized: "That character couldn't be saved. Try another look.")
        case "rate_limited": String(localized: "Too many attempts. Try again later.")
        case "unauthorized": String(localized: "Sign in failed. Try again.")
        case "invalid_image": String(localized: "That photo couldn't be used. Try another one.")
        case "image_too_large": String(localized: "That photo is too big. Try a smaller one.")
        case "upload_failed": String(localized: "The upload didn't finish. Try again.")
        case "already_friends": String(localized: "You're already friends.")
        case "not_found": String(localized: "We couldn't find that. It may have been removed.")
        default: String(localized: "Something went wrong. Try again.")
        }
    }
}
