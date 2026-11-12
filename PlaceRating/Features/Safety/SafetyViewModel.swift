import Foundation
import Observation

/// Reporting and blocking, shared by every screen that shows other people's content.
/// Blocked people vanish from ratings, photos and friends right away; the server hides them too.
@MainActor
@Observable
final class SafetyViewModel {
    private(set) var blocked: [PublicUser] = []
    private(set) var isLoading = false
    /// A short confirmation ("Thanks. We'll take a look."), cleared after a few seconds.
    private(set) var noticeText: String?
    private(set) var errorText: String?
    /// Called after someone is blocked, so the friends list and the map can drop them.
    var onBlocked: (String) -> Void = { _ in }

    private let api: any ModerationAPI
    private let noticeDuration: Duration
    private var noticeTask: Task<Void, Never>?

    init(api: any ModerationAPI, noticeDuration: Duration = .seconds(4)) {
        self.api = api
        self.noticeDuration = noticeDuration
    }

    var blockedIds: Set<String> { Set(blocked.map(\.id)) }

    func isBlocked(_ userId: String) -> Bool { blocked.contains { $0.id == userId } }

    func loadBlocked() async {
        isLoading = true
        defer { isLoading = false }
        do {
            blocked = try await api.blocks()
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }

    func report(_ target: ReportTarget, id: String, reason: ReportReason) async {
        errorText = nil
        do {
            try await api.report(target, id: id, reason: reason)
            showNotice(String(localized: "Thanks. We'll take a look."))
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }

    func block(_ user: PublicUser) async {
        guard !isBlocked(user.id) else { return }
        errorText = nil
        do {
            try await api.block(userId: user.id)
            blocked.insert(user, at: 0)
            showNotice(String(localized: "Blocked \(user.name)."))
            onBlocked(user.id)
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }

    func unblock(_ user: PublicUser) async {
        errorText = nil
        do {
            try await api.unblock(userId: user.id)
            blocked.removeAll { $0.id == user.id }
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }

    private func showNotice(_ text: String) {
        noticeText = text
        noticeTask?.cancel()
        noticeTask = Task { [noticeDuration] in
            try? await Task.sleep(for: noticeDuration)
            guard !Task.isCancelled else { return }
            noticeText = nil
        }
    }
}
