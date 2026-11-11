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
