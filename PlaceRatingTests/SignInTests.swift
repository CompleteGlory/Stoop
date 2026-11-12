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
struct AppleSignInTests {
    @Test func passesTheAuthorizationCodeOn() async {
        let api = FakeAPI()
        let model = SignInViewModel(session: SessionStore(api: api), google: FakeGoogle())
        await model.signIn(with: AppleCredential(identityToken: "id", fullName: nil, authorizationCode: "code-1"))
        await model.signIn(with: AppleCredential(identityToken: "id", fullName: nil))
        #expect(api.appleCodes == ["code-1", nil])
    }
}

@MainActor
struct EmailAuthViewModelTests {
    private func make() -> (EmailAuthViewModel, FakeAPI, SessionStore) {
        let api = FakeAPI()
        let store = SessionStore(api: api)
        return (EmailAuthViewModel(session: store, usernameDebounce: .zero), api, store)
    }

    @Test func signUpAsksForTheCodeThenSignsIn() async {
        let (model, api, store) = make()
        model.go(to: .signUp)
        model.email = " Nia@Example.com "
        model.username = " Nia.R "
        await model.usernameCheck.waitForCheck()
        model.password = "short"
        model.confirmPassword = "short"
        #expect(!model.canSubmit)
        model.password = "long enough"
        #expect(!model.canSubmit) // the second password no longer matches
        #expect(model.passwordsMismatch)
        model.confirmPassword = "long enough"
        #expect(model.canSubmit)
        await model.submit()
        #expect(api.publicChecked == ["nia.r"])
        #expect(api.signUpUsernames == ["nia.r"])
        #expect(model.step == .verify)
        #expect(model.infoText?.contains("nia@example.com") == true)

        model.code = "12345"
        #expect(!model.canSubmit)
        model.code = "123456"
        await model.submit()
        #expect(api.emailCalls == ["signup", "verify"])
        #expect(store.phase == .needsUsername(api.emailUser))
    }

    @Test func signUpNeedsAFreeUsername() async {
        let (model, api, _) = make()
        model.go(to: .signUp)
        model.email = "a@b.co"
        model.password = "long enough"
        model.confirmPassword = "long enough"
        #expect(!model.canSubmit) // no username yet

        model.username = "a b"
        #expect(model.usernameCheck.status == .invalid)
        #expect(!model.canSubmit)

        api.availabilityResult = .success(.init(available: false, reason: .taken))
        model.username = "dana"
        await model.usernameCheck.waitForCheck()
        #expect(model.usernameCheck.status == .taken)
        #expect(!model.canSubmit)
    }

    @Test func aNameTakenJustBeforeSigningUpIsShownOnTheField() async {
        let (model, api, _) = make()
        model.go(to: .signUp)
        model.email = "a@b.co"
        model.username = "dana"
        await model.usernameCheck.waitForCheck()
        model.password = "long enough"
        model.confirmPassword = "long enough"
        api.emailErrors["signup"] = APIError(status: 409, code: "username_taken", message: "")

        await model.submit()

        #expect(model.step == .signUp)
        #expect(model.usernameCheck.status == .taken)
        #expect(model.errorText == nil)
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

struct PasswordStrengthTests {
    @Test func gradesPasswords() {
        #expect(PasswordStrength("") == .empty)
        #expect(PasswordStrength("abc1") == .tooShort)
        #expect(PasswordStrength("password1") == .weak) // common
        #expect(PasswordStrength("aaaaaaaaaa") == .weak) // too few different characters
        #expect(PasswordStrength("lemontree") == .weak)
        #expect(PasswordStrength("lemontree7") == .weak)
        #expect(PasswordStrength("lemontree77x") == .fair)
        #expect(PasswordStrength("Lemontree77x") == .good)
        #expect(PasswordStrength("Lemon-tree-77-river") == .strong)
    }

    @Test func fillsMoreOfTheBarAsItGetsStronger() {
        let order: [PasswordStrength] = [.empty, .tooShort, .weak, .fair, .good, .strong]
        #expect(order == order.sorted())
        #expect(order.map(\.filledSegments) == [0, 1, 1, 2, 3, 4])
    }
}
