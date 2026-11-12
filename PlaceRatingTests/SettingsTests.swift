import Foundation
import SwiftUI
import Testing
@testable import PlaceRating

/// A throwaway place to remember settings, so tests never touch the real ones.
private func freshDefaults() -> UserDefaults {
    let name = "settings-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
struct AppSettingsTests {
    @Test func startsWithTheSystemChoicesAndTheClassicMap() {
        let settings = AppSettings(defaults: freshDefaults(), localizer: Localizer())
        #expect(settings.appearance == .system)
        #expect(settings.language == .system)
        #expect(settings.mapTheme == .classic)
        #expect(settings.appearance.colorScheme == nil)
        #expect(settings.language.layoutDirection == nil)
    }

    @Test func remembersChoicesBetweenLaunches() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults, localizer: Localizer())
        first.appearance = .dark
        first.language = .arabic
        first.mapTheme = .terrain

        let second = AppSettings(defaults: defaults, localizer: Localizer())
        #expect(second.appearance == .dark)
        #expect(second.language == .arabic)
        #expect(second.mapTheme == .terrain)
    }

    @Test func arabicFlipsTheLayoutAndEnglishDoesNot() {
        #expect(AppLanguage.arabic.layoutDirection == .rightToLeft)
        #expect(AppLanguage.english.layoutDirection == .leftToRight)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
    }

    @Test func switchingTheLanguageTellsTheLocalizer() {
        let localizer = Localizer()
        let settings = AppSettings(defaults: freshDefaults(), localizer: localizer)
        settings.language = .arabic
        #expect(localizer.language == .arabic)
        #expect(settings.locale.identifier == "ar")
    }

    @Test func ignoresUnknownSavedValues() {
        let defaults = freshDefaults()
        defaults.set("neon", forKey: "settings.appearance")
        defaults.set("klingon", forKey: "settings.language")
        defaults.set("rainbow", forKey: "settings.mapTheme")
        let settings = AppSettings(defaults: defaults, localizer: Localizer())
        #expect(settings.appearance == .system)
        #expect(settings.language == .system)
        #expect(settings.mapTheme == .classic)
    }
}

struct LocalizerTests {
    @Test func writesStringsInTheChosenLanguage() {
        #expect(Localizer(language: .english).string("Continue") == "Continue")
        #expect(Localizer(language: .arabic).string("Continue") == "متابعة")
    }

    @Test func fillsInNumbersAndPluralsInArabic() {
        let arabic = Localizer(language: .arabic)
        #expect(arabic.string("Sharing with \(1) friends") == "مشاركة مع صديق واحد")
        #expect(arabic.string("Sharing with \(3) friends") == "مشاركة مع 3 أصدقاء")
        #expect(Localizer(language: .english).string("Sharing with \(1) friends") == "Sharing with 1 friend")
    }
}

struct MapThemeTests {
    @Test func everyThemeHasANameAnIconAndASwatch() {
        for theme in MapTheme.allCases {
            #expect(!theme.title.isEmpty)
            #expect(!theme.systemImage.isEmpty)
            #expect(theme.swatch.count == 2)
        }
        #expect(MapTheme.allCases.count == 9)
    }

    @Test func onlyNightForcesADarkMap() {
        #expect(MapTheme.night.colorScheme == .dark)
        #expect(MapTheme.allCases.filter { $0 != .night }.allSatisfy { $0.colorScheme == nil })
    }
}

@MainActor
struct SettingsViewModelTests {
    private func make(user: SelfUser = makeUser(), clearing: @escaping () async -> Void = {}) -> (SettingsViewModel, FakeAPI, SessionStore) {
        let api = FakeAPI()
        let session = SessionStore(api: api)
        return (SettingsViewModel(user: user, session: session, clearCaches: clearing), api, session)
    }

    @Test func savesANewDisplayName() async {
        let (model, api, session) = make()
        api.updateResult = .success(makeUser(displayName: "Alice B"))

        await model.saveDisplayName("  Alice B ")

        #expect(api.updates.map(\.displayName) == ["Alice B"])
        #expect(api.updates.map(\.username) == ["alice"])
        #expect(model.displayName == "Alice B")
        #expect(model.nameError == nil)
        #expect(session.phase == .ready(makeUser(displayName: "Alice B")))
    }

    @Test func refusesEmptyAndTooLongNamesWithoutAskingTheServer() async {
        let (model, api, _) = make()
        await model.saveDisplayName("   ")
        #expect(model.nameError != nil)
        await model.saveDisplayName(String(repeating: "a", count: 41))
        #expect(model.nameError != nil)
        #expect(api.updates.isEmpty)
    }

    @Test func doesNothingWhenTheNameDidNotChange() async {
        let (model, api, _) = make()
        await model.saveDisplayName("Alice")
        #expect(api.updates.isEmpty)
        #expect(model.nameError == nil)
    }

    @Test func showsTheServersAnswerWhenSavingFails() async {
        let (model, api, _) = make()
        api.updateResult = .failure(URLError(.notConnectedToInternet))
        await model.saveDisplayName("New name")
        #expect(model.nameError != nil)
        #expect(model.displayName == "Alice")
    }

    @Test func fallsBackToTheUsernameWhenThereIsNoDisplayName() {
        let (model, _, _) = make(user: makeUser(username: "alice", displayName: ""))
        #expect(model.displayName == "alice")
    }

    @Test func clearsCachedImages() async {
        var cleared = 0
        let (model, _, _) = make(clearing: { cleared += 1 })
        await model.clearImageCache()
        #expect(cleared == 1)
        #expect(model.cacheCleared)
        #expect(!model.isClearingCache)
    }
}
