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
    /// Places, ratings and friends; the real client provides both.
    let places: any PlacesAPI
    let friends: any FriendsAPI

    init(api: any APIClientProtocol, places: (any PlacesAPI)? = nil, friends: (any FriendsAPI)? = nil) {
        self.friends = friends ?? (api as? any FriendsAPI) ?? UnavailableFriendsAPI()
        self.api = api
        self.places = places ?? (api as? any PlacesAPI) ?? UnavailablePlacesAPI()
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

    /// Opens the character screen for someone who already has a character.
    func editCharacter() {
        if case .ready(let user) = phase { phase = .needsCharacter(user) }
    }

    /// Leaves the character screen without saving, back to the map.
    func cancelCharacterEdit() {
        if case .needsCharacter(let user) = phase, user.avatar != nil { phase = .ready(user) }
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
