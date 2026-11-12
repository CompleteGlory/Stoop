import Foundation
import Testing
@testable import PlaceRating

@MainActor
struct SessionStoreTests {
    @Test func noSavedSessionMeansSignedOut() async {
        let store = SessionStore(api: FakeAPI())
        await store.start()
        #expect(store.phase == .signedOut)
    }

    @Test func anAccountWithoutAUsernameMustChooseOne() async {
        let api = FakeAPI()
        api.restoreResult = .success(true)
        let user = makeUser(username: nil)
        api.meResult = .success(user)
        let store = SessionStore(api: api)
        await store.start()
        #expect(store.phase == .needsUsername(user))
    }

    @Test func anAccountWithoutACharacterMustMakeOne() async {
        let api = FakeAPI()
        api.restoreResult = .success(true)
        let user = makeUser(avatar: nil)
        api.meResult = .success(user)
        let store = SessionStore(api: api)
        await store.start()
        #expect(store.phase == .needsCharacter(user))
    }

    @Test func anAccountWithAUsernameGoesToTheMap() async {
        let api = FakeAPI()
        api.restoreResult = .success(true)
        let store = SessionStore(api: api)
        await store.start()
        #expect(store.phase == .ready(makeUser()))
    }

    @Test func beingOfflineDoesNotSignYouOut() async {
        let api = FakeAPI()
        api.restoreResult = .success(true)
        api.meResult = .failure(URLError(.notConnectedToInternet))
        let store = SessionStore(api: api)
        await store.start()
        #expect(store.phase == .unavailable)
    }

    @Test func anUnreadableKeychainDoesNotSignYouOut() async {
        let api = FakeAPI()
        api.restoreResult = .failure(KeychainError(status: -25308))
        let store = SessionStore(api: api)
        await store.start()
        #expect(store.phase == .unavailable)
    }

    @Test func anExpiredSessionSignsOut() async {
        let api = FakeAPI()
        api.restoreResult = .success(true)
        api.meResult = .failure(AuthError.sessionExpired)
        let store = SessionStore(api: api)
        await store.start()
        #expect(store.phase == .signedOut)
    }
}

@MainActor
struct UsernameViewModelTests {
    private func make(_ api: FakeAPI, displayName: String = "Nia") -> (UsernameViewModel, SessionStore) {
        let store = SessionStore(api: api)
        let user = makeUser(username: nil, displayName: displayName)
        return (UsernameViewModel(session: store, user: user, debounce: .zero), store)
    }

    private func enter(_ text: String, in model: UsernameViewModel) async {
        model.username = text
        model.usernameChanged()
        await model.waitForCheck()
    }

    @Test func badFormatsNeverReachTheServer() async {
        let api = FakeAPI()
        let (model, _) = make(api)
        await enter("a b!", in: model)
        #expect(model.status == .invalid)
        #expect(api.checked.isEmpty)
    }

    @Test func checksTheNormalizedName() async {
        let api = FakeAPI()
        let (model, _) = make(api)
        await enter("  Nia.K ", in: model)
        #expect(api.checked == ["nia.k"])
        #expect(model.status == .available)
        #expect(model.canSubmit)
    }

    @Test func aTakenNameCannotBeSubmitted() async {
        let api = FakeAPI()
        api.availabilityResult = .success(.init(available: false, reason: .taken))
        let (model, _) = make(api)
        await enter("alice", in: model)
        #expect(model.status == .taken)
        #expect(!model.canSubmit)
    }

    @Test func onlyTheLatestTextIsChecked() async {
        let api = FakeAPI()
        let store = SessionStore(api: api)
        let model = UsernameViewModel(session: store, user: makeUser(username: nil), debounce: .milliseconds(30))
        model.username = "first"
        model.usernameChanged()
        await enter("second", in: model)
        #expect(api.checked == ["second"])
    }

    @Test func aFailedCheckStillAllowsSaving() async {
        let api = FakeAPI()
        api.availabilityResult = .failure(URLError(.timedOut))
        let (model, _) = make(api)
        await enter("alice", in: model)
        #expect(model.status == .unknown)
        #expect(model.canSubmit)
    }

    @Test func savingMovesOnToTheMap() async {
        let api = FakeAPI()
        let (model, store) = make(api)
        await enter("nia", in: model)
        await model.submit()
        #expect(store.phase == .ready(makeUser()))
        #expect(api.updates.first?.displayName == nil)
    }

    @Test func aBlankNameFallsBackToTheUsername() async {
        let api = FakeAPI()
        let (model, _) = make(api, displayName: "  ")
        await enter("nia", in: model)
        await model.submit()
        #expect(api.updates.first?.displayName == "nia")
    }

    @Test func losingTheRaceShowsTaken() async {
        let api = FakeAPI()
        api.updateResult = .failure(APIError(status: 409, code: "username_taken", message: ""))
        let (model, store) = make(api)
        await enter("nia", in: model)
        await model.submit()
        #expect(model.status == .taken)
        #expect(store.phase == .launching)
    }
}

struct NonceTests {
    @Test func hashesToLowercaseHex() {
        #expect(Nonce.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func isRandom() {
        #expect(Nonce.make() != Nonce.make())
    }
}

@MainActor
struct CharacterViewModelTests {
    private func make(gender: CharacterGender = .male, existing: Avatar? = nil) -> (CharacterViewModel, FakeAPI, SessionStore) {
        let api = FakeAPI()
        let store = SessionStore(api: api)
        let model = CharacterViewModel(session: store, renderer: FakeRenderer(), existing: existing, gender: gender)
        return (model, api, store)
    }

    @Test func startsWithACharacterInTheFirstStyle() async {
        let (model, _, _) = make()
        await model.load()
        #expect(model.avatar?.style == "avataaars")
        #expect(model.groups.map(\.name) == ["top", "hairColor", "facialHair", "clothing"])
        #expect(model.styleSamples.keys.sorted() == ["avataaars", "lorelei"])
        #expect(!model.isLoading)
    }

    @Test func keepsAnExistingCharacter() async {
        let existing = Avatar(style: "avataaars", options: [
            "top": "none", "hairColor": "a55728", "facialHair": "beardLight", "clothing": "overall",
        ])
        let (model, _, _) = make(existing: existing)
        await model.load()
        #expect(model.avatar == existing)
    }

    @Test func switchingToFemaleDropsFacialHairAndInvalidHair() async {
        let (model, _, _) = make()
        await model.load()
        model.set("facialHair", to: "beardLight")
        await model.selectGender(.female)
        #expect(model.gender == .female)
        #expect(model.avatar?.options["facialHair"] == nil)
        #expect(model.avatar?.options["top"] == "bob")
        #expect(!model.groups.contains { $0.name == "facialHair" })
    }

    @Test func choosingAnOptionUpdatesThePreview() async {
        let (model, _, _) = make()
        await model.load()
        model.set("hairColor", to: "a55728")
        #expect(model.isSelected("hairColor", "a55728"))
        #expect(model.preview("top", "none")?.options["hairColor"] == "a55728")
    }

    @Test func switchingStyleStartsAFreshCharacter() async {
        let (model, _, _) = make()
        await model.load()
        await model.selectStyle("lorelei")
        #expect(model.avatar?.style == "lorelei")
    }

    @Test func savingMovesOnToTheMap() async {
        let (model, api, store) = make()
        await model.load()
        await model.save()
        #expect(api.savedAvatars.count == 1)
        #expect(store.phase == .ready(makeUser()))
    }

    @Test func everyPartGetsAPageWithItsColors() async {
        let (model, _, _) = make()
        await model.load()
        #expect(model.steps == ["style", "top", "facialHair", "clothing"])
        #expect(model.groupsOnStep.isEmpty)
        model.next()
        #expect(model.step == "top")
        #expect(model.groupsOnStep.map(\.name) == ["top", "hairColor"])
        model.go(to: "clothing")
        #expect(model.isLastStep)
        model.next()
        #expect(model.step == "clothing")
        model.back()
        #expect(model.step == "facialHair")
        model.go(to: "nose")
        #expect(model.step == "facialHair")
    }

    @Test func aPageThatDisappearsReturnsToStyle() async {
        let (model, _, _) = make()
        await model.load()
        model.go(to: "facialHair")
        await model.selectGender(.female)
        #expect(model.step == "style")
        #expect(model.steps == ["style", "top", "clothing"])
    }

    @Test func aRejectedCharacterShowsAnError() async {
        let (model, api, store) = make()
        api.avatarResult = .failure(APIError(status: 400, code: "invalid_avatar", message: ""))
        await model.load()
        await model.save()
        #expect(model.errorText != nil)
        #expect(store.phase == .launching)
    }
}

@MainActor
struct AccountDeletionTests {
    private func signedIn() -> (SessionStore, FakeAPI) {
        let api = FakeAPI()
        let store = SessionStore(api: api)
        store.usernameChosen(makeUser())
        return (store, api)
    }

    @Test func deletingTheAccountReturnsToSignIn() async throws {
        let (store, api) = signedIn()
        #expect(store.phase == .ready(makeUser()))

        try await store.deleteAccount()

        #expect(api.deleted)
        #expect(store.phase == .signedOut)
    }

    @Test func aFailedDeletionKeepsYouSignedInAndSaysWhy() async {
        let (store, api) = signedIn()
        api.deleteResult = .failure(URLError(.notConnectedToInternet))

        await #expect(throws: URLError.self) { try await store.deleteAccount() }

        #expect(!api.deleted)
        #expect(store.phase == .ready(makeUser()))
    }
}

struct LegalLinksTests {
    @Test func theLegalPagesLiveNextToTheAPI() {
        let production = AppConfig.production
        #expect(production.termsURL.absoluteString == "https://place-rating-api-production.up.railway.app/terms")
        #expect(production.privacyURL.absoluteString == "https://place-rating-api-production.up.railway.app/privacy")
        #expect(AppConfig.local.termsURL.absoluteString == "http://localhost:3000/terms")
        #expect(AppConfig.supportEmail.contains("@"))
    }
}
