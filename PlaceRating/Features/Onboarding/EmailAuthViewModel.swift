import Foundation
import Observation

/// Email and password sign-in: create an account, confirm it with a 6-digit code, sign in,
/// and reset a forgotten password with a code.
@MainActor
@Observable
final class EmailAuthViewModel {
    enum Step: Equatable {
        case signIn
        case signUp
        /// Enter the code that confirms a new account.
        case verify
        case forgot
        /// Enter the reset code and a new password.
        case reset
    }

    var step: Step = .signIn
    var email = ""
    var password = ""
    var code = ""
    var newPassword = ""
    private(set) var isBusy = false
    private(set) var errorText: String?
    private(set) var infoText: String?

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
    }

    private var normalizedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    static func isEmail(_ text: String) -> Bool {
        text.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
    }

    var canSubmit: Bool {
        guard !isBusy else { return false }
        switch step {
        case .signIn: return Self.isEmail(normalizedEmail) && !password.isEmpty
        case .signUp: return Self.isEmail(normalizedEmail) && password.count >= 8
        case .verify: return code.count == 6
        case .forgot: return Self.isEmail(normalizedEmail)
        case .reset: return code.count == 6 && newPassword.count >= 8
        }
    }

    func go(to newStep: Step) {
        step = newStep
        errorText = nil
        infoText = nil
        code = ""
    }

    func submit() async {
        guard canSubmit else { return }
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        let api = session.api
        let email = normalizedEmail
        do {
            switch step {
            case .signIn:
                session.signedIn(try await api.emailSignIn(email: email, password: password))
            case .signUp:
                try await api.emailSignUp(email: email, password: password)
                go(to: .verify)
                infoText = String(localized: "We sent a 6-digit code to \(email).")
            case .verify:
                session.signedIn(try await api.emailVerify(email: email, code: code))
            case .forgot:
                try await api.passwordForgot(email: email)
                go(to: .reset)
                infoText = String(localized: "If \(email) has an account, we sent it a 6-digit code.")
            case .reset:
                session.signedIn(try await api.passwordReset(email: email, code: code, newPassword: newPassword))
            }
        } catch let error as APIError where error.code == "email_not_verified" {
            // the account is waiting for its code: send a fresh one and ask for it
            try? await api.emailResend(email: email)
            go(to: .verify)
            infoText = ErrorText.text(for: error)
        } catch let error as APIError where error.code == "validation_failed" {
            errorText = String(localized: "Check the email and password. Passwords need at least 8 characters.")
            _ = error
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }

    func resend() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            switch step {
            case .verify: try await session.api.emailResend(email: normalizedEmail)
            case .reset: try await session.api.passwordForgot(email: normalizedEmail)
            default: return
            }
            errorText = nil
            infoText = String(localized: "We sent a new code.")
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }
}
