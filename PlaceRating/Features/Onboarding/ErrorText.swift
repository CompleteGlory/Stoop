import Foundation

/// Translated text for an error. Switches on the server's stable `code`, never its `message`.
enum ErrorText {
    static func text(for error: Error) -> String {
        switch error {
        case is URLError:
            tr("We couldn't reach the server.")
        case AuthError.sessionExpired:
            tr("Your session has expired. Sign in again.")
        case let error as APIError:
            text(forCode: error.code)
        default:
            tr("Something went wrong. Try again.")
        }
    }

    private static func text(forCode code: String) -> String {
        switch code {
        case "username_taken": tr("That username is taken.")
        case "username_reserved": tr("That username isn't available.")
        case "validation_failed": tr("Use 3 to 20 letters, digits, _ or .")
        case "invalid_credentials": tr("Wrong email or password.")
        case "invalid_code": tr("That code is wrong or has expired.")
        case "email_not_verified": tr("Confirm your email first. We sent you a new code.")
        case "invalid_avatar": tr("That character couldn't be saved. Try another look.")
        case "rate_limited": tr("Too many attempts. Try again later.")
        case "unauthorized": tr("Sign in failed. Try again.")
        case "invalid_image": tr("That photo couldn't be used. Try another one.")
        case "image_too_large": tr("That photo is too big. Try a smaller one.")
        case "upload_failed": tr("The upload didn't finish. Try again.")
        case "already_friends": tr("You're already friends.")
        case "not_found": tr("We couldn't find that. It may have been removed.")
        default: tr("Something went wrong. Try again.")
        }
    }
}
