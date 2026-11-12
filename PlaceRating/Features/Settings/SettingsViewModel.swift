import Foundation
import Nuke
import Observation

/// What the settings sheet does beyond switches: renaming yourself and clearing cached images.
@MainActor
@Observable
final class SettingsViewModel {
    static let maxDisplayName = 40

    private(set) var displayName: String
    private(set) var isSavingName = false
    private(set) var nameError: String?
    private(set) var isClearingCache = false
    private(set) var cacheCleared = false

    private let user: SelfUser
    private let session: SessionStore
    private let clearCaches: () async -> Void

    init(user: SelfUser, session: SessionStore, clearCaches: @escaping () async -> Void = SettingsViewModel.clearImageCaches) {
        self.user = user
        self.session = session
        self.clearCaches = clearCaches
        displayName = user.displayName.isEmpty ? (user.username ?? "") : user.displayName
    }

    /// Friends see this name on the map. 1 to 40 characters.
    func saveDisplayName(_ text: String) async {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= Self.maxDisplayName else {
            nameError = tr("Use 1 to 40 characters.")
            return
        }
        guard name != displayName else { return }
        isSavingName = true
        nameError = nil
        defer { isSavingName = false }
        do {
            let updated = try await session.api.updateProfile(username: user.username ?? "", displayName: name)
            displayName = updated.displayName
            session.usernameChosen(updated)
        } catch AuthError.sessionExpired {
            session.sessionExpired()
        } catch {
            nameError = ErrorText.text(for: error)
        }
    }

    func clearImageCache() async {
        isClearingCache = true
        cacheCleared = false
        await clearCaches()
        isClearingCache = false
        cacheCleared = true
    }

    /// Downloaded place photos and drawn avatars; they come back from the server when needed.
    static func clearImageCaches() async {
        ImagePipeline.shared.cache.removeAll()
        await AvatarDiskCache.shared.removeAll()
    }

    /// "1.0 (12)" from the app's Info.plist.
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
