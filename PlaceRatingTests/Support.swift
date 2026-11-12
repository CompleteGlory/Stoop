import Foundation
import UIKit
@testable import PlaceRating

let sampleAvatar = Avatar(style: "avataaars", options: ["top": "shortFlat", "hairColor": "111111"])

func makeUser(username: String? = "alice", displayName: String = "Alice", avatar: Avatar? = sampleAvatar) -> SelfUser {
    SelfUser(
        id: "11111111-1111-1111-1111-111111111111",
        username: username,
        displayName: displayName,
        avatar: avatar,
        ghostMode: false,
        createdAt: Date(timeIntervalSince1970: 0)
    )
}

func makeAuth(access: String, refresh: String, expiresIn: Int = 900, user: SelfUser = makeUser()) -> AuthResponse {
    AuthResponse(
        accessToken: access,
        refreshToken: refresh,
        expiresIn: expiresIn,
        needsOnboarding: user.username == nil,
        user: user
    )
}

final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: StoredTokens?
    var loadError: Error?

    init(_ tokens: StoredTokens? = nil) { value = tokens }

    var tokens: StoredTokens? { lock.withLock { value } }

    func load() throws -> StoredTokens? {
        if let loadError { throw loadError }
        return tokens
    }
    func save(_ tokens: StoredTokens) throws { lock.withLock { value = tokens } }
    func clear() throws { lock.withLock { value = nil } }
}

actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

@MainActor
final class FakeAPI: APIClientProtocol, @unchecked Sendable {
    var restoreResult: Result<Bool, Error> = .success(false)
    var meResult: Result<SelfUser, Error> = .success(makeUser())
    var availabilityResult: Result<UsernameAvailability, Error> = .success(.init(available: true, reason: nil))
    var updateResult: Result<SelfUser, Error> = .success(makeUser())
    var avatarResult: Result<SelfUser, Error> = .success(makeUser())
    var savedAvatars: [Avatar] = []
    var checked: [String] = []
    var updates: [(username: String, displayName: String?)] = []
    var signedOut = false

    func restoreSession() async throws -> Bool { try restoreResult.get() }
    func signInWithApple(identityToken: String, nonce: String, fullName: String?) async throws -> AuthResponse {
        makeAuth(access: "a", refresh: "r", user: makeUser(username: nil, displayName: ""))
    }
    func devSignIn(username: String) async throws -> AuthResponse { makeAuth(access: "a", refresh: "r") }

    var googleTokens: [String] = []
    var emailCalls: [String] = []
    /// Answers for the email routes, keyed by route name; missing means success.
    var emailErrors: [String: Error] = [:]
    var emailUser = makeUser(username: nil, displayName: "")

    func signInWithGoogle(idToken: String) async throws -> AuthResponse {
        googleTokens.append(idToken)
        return makeAuth(access: "a", refresh: "r", user: makeUser(username: nil, displayName: "G"))
    }
    private func email(_ route: String) throws {
        emailCalls.append(route)
        if let error = emailErrors[route] { throw error }
    }
    var signUpUsernames: [String?] = []
    func emailSignUp(email: String, password: String, username: String?) async throws {
        signUpUsernames.append(username)
        try self.email("signup")
    }
    func emailVerify(email: String, code: String) async throws -> AuthResponse {
        try self.email("verify")
        return makeAuth(access: "a", refresh: "r", user: emailUser)
    }
    func emailResend(email: String) async throws { try self.email("resend") }
    func emailSignIn(email: String, password: String) async throws -> AuthResponse {
        try self.email("signin")
        return makeAuth(access: "a", refresh: "r", user: emailUser)
    }
    func passwordForgot(email: String) async throws { try self.email("forgot") }
    func passwordReset(email: String, code: String, newPassword: String) async throws -> AuthResponse {
        try self.email("reset")
        return makeAuth(access: "a", refresh: "r", user: emailUser)
    }
    func me() async throws -> SelfUser { try meResult.get() }
    func updateProfile(username: String, displayName: String?) async throws -> SelfUser {
        updates.append((username, displayName))
        return try updateResult.get()
    }
    func updateAvatar(_ avatar: Avatar) async throws -> SelfUser {
        savedAvatars.append(avatar)
        return try avatarResult.get()
    }
    func usernameAvailability(_ username: String) async throws -> UsernameAvailability {
        checked.append(username)
        return try availabilityResult.get()
    }
    var publicChecked: [String] = []
    func publicUsernameAvailability(_ username: String) async throws -> UsernameAvailability {
        publicChecked.append(username)
        return try availabilityResult.get()
    }
    var deleteResult: Result<Void, Error> = .success(())
    var deleted = false
    func deleteAccount() async throws {
        try deleteResult.get()
        deleted = true
    }
    func signOut() async { signedOut = true }
}

/// Two styles with a couple of options, enough to drive the character screen without a web view.
@MainActor
final class FakeRenderer: AvatarRendering {
    var calls: [String] = []

    func styles() async throws -> [CharacterStyle] {
        [
            CharacterStyle(id: "avataaars", title: "Avataaars", creator: "Pablo Stanley", license: "Free", sortedByGender: true),
            CharacterStyle(id: "lorelei", title: "Lorelei", creator: "Lisa Wischofsky", license: "CC0 1.0", sortedByGender: false),
        ]
    }

    func groups(style: String, gender: CharacterGender) async throws -> [OptionGroup] {
        calls.append("groups \(style) \(gender.rawValue)")
        let hair = gender == .male ? ["shortFlat", "none"] : ["bob", "bun"]
        var groups = [OptionGroup(name: "top", kind: .choice, values: hair, page: "top"),
                      OptionGroup(name: "hairColor", kind: .color, values: ["111111", "a55728"], page: "top")]
        if gender == .male {
            groups.append(OptionGroup(name: "facialHair", kind: .choice, values: ["none", "beardLight"], page: "facialHair"))
        }
        if style == "avataaars" {
            groups.append(OptionGroup(name: "clothing", kind: .choice, values: ["hoodie", "overall"], page: "clothing"))
        }
        return groups
    }

    func normalise(_ avatar: Avatar, gender: CharacterGender) async throws -> Avatar {
        var options: [String: String] = [:]
        for group in try await groups(style: avatar.style, gender: gender) {
            let current = avatar.options[group.name]
            options[group.name] = current.flatMap { group.values.contains($0) ? $0 : nil } ?? group.values[0]
        }
        return Avatar(style: avatar.style, options: options)
    }

    func random(style: String, gender: CharacterGender) async throws -> Avatar {
        calls.append("random \(style)")
        return try await normalise(Avatar(style: style, options: [:]), gender: gender)
    }

    func image(for avatar: Avatar, pixels: Int) async throws -> UIImage { UIImage() }
}
