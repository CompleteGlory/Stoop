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
    enum Status: Equatable {
        case idle
        case invalid
        case checking
        case available
        case taken
        case reserved
        /// The check itself failed. Saving is still allowed; the server has the final word.
        case unknown
    }

    var username = ""
    private(set) var status: Status = .idle
    private(set) var isSaving = false
    private(set) var errorText: String?

    private let session: SessionStore
    private let user: SelfUser
    private let debounce: Duration
    private var check: Task<Void, Never>?

    init(session: SessionStore, user: SelfUser, debounce: Duration = .milliseconds(400)) {
        self.session = session
        self.user = user
        self.debounce = debounce
    }

    var canSubmit: Bool {
        !isSaving && (status == .available || status == .unknown)
    }

    /// Call on every edit. Only the latest text is ever checked.
    func usernameChanged() {
        check?.cancel()
        errorText = nil
        let candidate = UsernameRules.normalized(username)
        guard !candidate.isEmpty else {
            status = .idle
            return
        }
        guard UsernameRules.isValid(candidate) else {
            status = .invalid
            return
        }
        status = .checking
        check = Task { await runCheck(of: candidate) }
    }

    /// Waits for the current check. Used by tests.
    func waitForCheck() async {
        await check?.value
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
            status = .taken
        } catch let error as APIError where error.code == "username_reserved" {
            status = .reserved
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }

    private func runCheck(of candidate: String) async {
        do {
            try await Task.sleep(for: debounce)
            let result = try await session.api.usernameAvailability(candidate)
            guard !Task.isCancelled else { return }
            status = switch (result.available, result.reason) {
            case (true, _): .available
            case (_, .taken): .taken
            case (_, .reserved): .reserved
            default: .invalid
            }
        } catch is CancellationError {
            return
        } catch AuthError.sessionExpired {
            session.sessionExpired()
        } catch {
            guard !Task.isCancelled else { return }
            status = .unknown
        }
    }
}
