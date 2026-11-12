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

    private(set) var phase: Phase = .launching {
        didSet { warmUp() }
    }
    let api: any APIClientProtocol
    /// Places, ratings and friends; the real client provides both.
    let places: any PlacesAPI
    let friends: any FriendsAPI
    let photos: any PhotosAPI
    let liveAuth: any LiveAuth
    let moderation: any ModerationAPI
    /// Rated places by hexagon, shared with the map so what loads during sign-in is already there.
    let placesCache: PlacesChunkCache
    private var warmedTiles = false
    private var preloadedPlaces = false

    init(api: any APIClientProtocol, places: (any PlacesAPI)? = nil, friends: (any FriendsAPI)? = nil) {
        self.friends = friends ?? (api as? any FriendsAPI) ?? UnavailableFriendsAPI()
        self.photos = (api as? any PhotosAPI) ?? UnavailablePhotosAPI()
        self.liveAuth = (api as? any LiveAuth) ?? UnavailableLiveAuth()
        self.moderation = (api as? any ModerationAPI) ?? UnavailableModerationAPI()
        self.api = api
        let placesAPI = places ?? (api as? any PlacesAPI) ?? UnavailablePlacesAPI()
        self.places = placesAPI
        placesCache = PlacesChunkCache(api: placesAPI)
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

    /// Deletes the account on the server; only when that worked does the app return to sign-in.
    func deleteAccount() async throws {
        try await api.deleteAccount()
        phase = .signedOut
    }

    /// While someone signs in or sets up, load the map around them in the background (only if
    /// location is already allowed): tiles straight away, rated places once the account has a
    /// username (the API needs one).
    private func warmUp() {
        guard let spot = MapWarmer.lastKnownLocation else { return }
        if !warmedTiles {
            warmedTiles = true
            MapWarmer.warmTiles(around: spot)
        }
        switch phase {
        case .needsCharacter, .ready:
            guard !preloadedPlaces else { return }
            preloadedPlaces = true
            Task { [placesCache] in await placesCache.preload(around: spot, radius: 3) }
        case .signedOut:
            preloadedPlaces = false
            placesCache.removeAll()
        default:
            break
        }
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
