import Foundation
import Observation

/// Which part of the app the person is allowed to see. The root view switches on `phase`.
@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable {
        case launching
        case signedOut
        case needsUsername(SelfUser)
        case needsCharacter(SelfUser)
        case ready(SelfUser)
        /// A saved session exists but couldn't be checked, for example when offline.
        case unavailable
    }

    private(set) var phase: Phase = .launching
    let api: any APIClientProtocol

    init(api: any APIClientProtocol) {
        self.api = api
    }

    func start() async {
        phase = .launching
        do {
            guard try await api.restoreSession() else {
                phase = .signedOut
                return
            }
            enter(try await api.me())
        } catch AuthError.sessionExpired {
            phase = .signedOut
        } catch {
            phase = .unavailable
        }
    }

    func signedIn(_ response: AuthResponse) {
        enter(response.user)
    }

    func usernameChosen(_ user: SelfUser) {
        enter(user)
    }

    func characterChosen(_ user: SelfUser) {
        enter(user)
    }

    func sessionExpired() {
        phase = .signedOut
    }

    func signOut() async {
        await api.signOut()
        phase = .signedOut
    }

    private func enter(_ user: SelfUser) {
        if user.username == nil {
            phase = .needsUsername(user)
        } else if user.avatar == nil {
            phase = .needsCharacter(user)
        } else {
            phase = .ready(user)
        }
    }
}
