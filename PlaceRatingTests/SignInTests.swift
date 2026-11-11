import Foundation
import Testing
@testable import PlaceRating

@MainActor
final class FakeGoogle: GoogleSignInProviding {
    var isConfigured = true
    var result: Result<String?, Error> = .success("google-id-token")
    func signIn() async throws -> String? { try result.get() }
}

@MainActor
struct GoogleSignInTests {
    @Test func sendsTheIdTokenAndSignsIn() async {
        let api = FakeAPI()
        let store = SessionStore(api: api)
        let model = SignInViewModel(session: store, google: FakeGoogle())
        await model.signInWithGoogle()
        #expect(api.googleTokens == ["google-id-token"])
        #expect(store.phase == .needsUsername(makeUser(username: nil, displayName: "G")))
    }

    @Test func cancellingDoesNothing() async {
        let api = FakeAPI()
        let google = FakeGoogle()
        google.result = .success(nil)
        let model = SignInViewModel(session: SessionStore(api: api), google: google)
        await model.signInWithGoogle()
        #expect(api.googleTokens.isEmpty)
        #expect(model.errorText == nil)
    }
}

@MainActor
struct EmailAuthViewModelTests {
    private func make() -> (EmailAuthViewModel, FakeAPI, SessionStore) {
        let api = FakeAPI()
        let store = SessionStore(api: api)
        return (EmailAuthViewModel(session: store), api, store)
    }

    @Test func signUpAsksForTheCodeThenSignsIn() async {
        let (model, api, store) = make()
        model.go(to: .signUp)
        model.email = " Nia@Example.com "
        model.password = "short"
        #expect(!model.canSubmit)
        model.password = "long enough"
        await model.submit()
        #expect(model.step == .verify)
        #expect(model.infoText?.contains("nia@example.com") == true)

        model.code = "12345"
        #expect(!model.canSubmit)
        model.code = "123456"
        await model.submit()
        #expect(api.emailCalls == ["signup", "verify"])
        #expect(store.phase == .needsUsername(api.emailUser))
    }

    @Test func anUnconfirmedAccountGetsANewCode() async {
        let (model, api, _) = make()
        api.emailErrors["signin"] = APIError(status: 403, code: "email_not_verified", message: "")
        model.email = "nia@example.com"
        model.password = "long enough"
        await model.submit()
        #expect(api.emailCalls == ["signin", "resend"])
        #expect(model.step == .verify)
    }

    @Test func wrongPasswordShowsAnError() async {
        let (model, api, store) = make()
        api.emailErrors["signin"] = APIError(status: 401, code: "invalid_credentials", message: "")
        model.email = "nia@example.com"
        model.password = "nope nope"
        await model.submit()
        #expect(model.errorText != nil)
        #expect(model.step == .signIn)
        #expect(store.phase == .launching)
    }

    @Test func forgotThenResetSignsIn() async {
        let (model, api, store) = make()
        model.go(to: .forgot)
        model.email = "nia@example.com"
        await model.submit()
        #expect(model.step == .reset)
        model.code = "654321"
        model.newPassword = "a new password"
        await model.submit()
        #expect(api.emailCalls == ["forgot", "reset"])
        #expect(store.phase == .needsUsername(api.emailUser))
    }

    @Test func checksTheEmailShape() {
        #expect(EmailAuthViewModel.isEmail("a@b.co"))
        #expect(!EmailAuthViewModel.isEmail("a@b"))
        #expect(!EmailAuthViewModel.isEmail("not an email"))
    }
}
