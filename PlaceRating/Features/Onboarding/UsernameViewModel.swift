import Foundation
import Observation

enum UsernameRules {
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Mirrors the server's `^[a-z0-9_.]{3,20}$`.
    static func isValid(_ username: String) -> Bool {
        username.wholeMatch(of: /[a-z0-9_.]{3,20}/) != nil
    }
}

@MainActor
@Observable
final class UsernameViewModel {
    typealias Status = UsernameChecker.Status

    var username = ""
    private(set) var isSaving = false
    private(set) var errorText: String?

    private let session: SessionStore
    private let user: SelfUser
    private let checker: UsernameChecker

    init(session: SessionStore, user: SelfUser, debounce: Duration = .milliseconds(400)) {
        self.session = session
        self.user = user
        checker = UsernameChecker(debounce: debounce, onSessionExpired: { session.sessionExpired() }) {
            try await session.api.usernameAvailability($0)
        }
    }

    var status: Status { checker.status }

    var canSubmit: Bool {
        !isSaving && checker.isAcceptable
    }

    /// Call on every edit. Only the latest text is ever checked.
    func usernameChanged() {
        errorText = nil
        checker.textChanged(username)
    }

    /// Waits for the current check. Used by tests.
    func waitForCheck() async {
        await checker.waitForCheck()
    }

    func submit() async {
        guard canSubmit else { return }
        isSaving = true
        defer { isSaving = false }
        let chosen = UsernameRules.normalized(username)
        // Apple may give no name, and friends' markers show the display name
        let blankName = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        do {
            let updated = try await session.api.updateProfile(
                username: chosen,
                displayName: blankName ? chosen : nil
            )
            session.usernameChosen(updated)
        } catch AuthError.sessionExpired {
            session.sessionExpired()
        } catch let error as APIError where error.code == "username_taken" {
            checker.status = .taken
        } catch let error as APIError where error.code == "username_reserved" {
            checker.status = .reserved
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }
}
