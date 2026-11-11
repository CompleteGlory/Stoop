import Foundation
import Observation

/// Checks a username while it is typed: rules first, then the server after a short pause.
/// Shared by the username step and the email sign-up screen.
@MainActor
@Observable
final class UsernameChecker {
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

    var status: Status = .idle

    private let lookup: (String) async throws -> UsernameAvailability
    private let debounce: Duration
    private let onSessionExpired: () -> Void
    private var check: Task<Void, Never>?

    init(
        debounce: Duration = .milliseconds(400),
        onSessionExpired: @escaping () -> Void = {},
        lookup: @escaping (String) async throws -> UsernameAvailability
    ) {
        self.debounce = debounce
        self.onSessionExpired = onSessionExpired
        self.lookup = lookup
    }

    /// Good enough to submit: available, or the check couldn't run.
    var isAcceptable: Bool { status == .available || status == .unknown }

    /// Call on every edit. Only the latest text is ever checked.
    func textChanged(_ text: String) {
        check?.cancel()
        let candidate = UsernameRules.normalized(text)
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

    private func runCheck(of candidate: String) async {
        do {
            try await Task.sleep(for: debounce)
            let result = try await lookup(candidate)
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
            onSessionExpired()
        } catch {
            guard !Task.isCancelled else { return }
            status = .unknown
        }
    }
}
