import Foundation
import Observation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }

    /// nil follows the phone's setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: String {
        switch self {
        case .system: tr("System")
        case .light: tr("Light")
        case .dark: tr("Dark")
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case arabic = "ar"
    var id: String { rawValue }

    /// Each language is named in itself, so you can find yours whatever the app is showing.
    var title: String {
        switch self {
        case .system: tr("System")
        case .english: "English"
        case .arabic: "العربية"
        }
    }

    /// nil follows the phone's language.
    var localeIdentifier: String? { self == .system ? nil : rawValue }

    var layoutDirection: LayoutDirection? {
        switch self {
        case .system: nil
        case .english: .leftToRight
        case .arabic: .rightToLeft
        }
    }
}

/// What the person chose in settings, remembered between launches. The root view applies the
/// language, layout direction and appearance, so every screen follows without a restart.
@MainActor
@Observable
final class AppSettings {
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            localizer.language = language
        }
    }

    /// The map's look, picked on the map itself rather than in settings.
    var mapTheme: MapTheme {
        didSet { defaults.set(mapTheme.rawValue, forKey: Keys.mapTheme) }
    }

    private let defaults: UserDefaults
    private let localizer: Localizer

    private enum Keys {
        static let appearance = "settings.appearance"
        static let language = "settings.language"
        static let mapTheme = "settings.mapTheme"
    }

    init(defaults: UserDefaults = .standard, localizer: Localizer = .shared) {
        self.defaults = defaults
        self.localizer = localizer
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppAppearance.init) ?? .system
        let language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init) ?? .system
        self.language = language
        mapTheme = defaults.string(forKey: Keys.mapTheme).flatMap(MapTheme.init) ?? .classic
        localizer.language = language
    }

    var locale: Locale {
        language.localeIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }
}

/// Applies the settings to everything below it.
struct SettingsApplied: ViewModifier {
    let settings: AppSettings

    func body(content: Content) -> some View {
        content
            .environment(\.locale, settings.locale)
            .environment(\.layoutDirection, settings.language.layoutDirection ?? defaultDirection)
            .preferredColorScheme(settings.appearance.colorScheme)
    }

    /// With "System", keep whatever direction the phone's language gives.
    @Environment(\.layoutDirection) private var defaultDirection
}

extension View {
    func applying(_ settings: AppSettings) -> some View { modifier(SettingsApplied(settings: settings)) }
}

/// The language strings written in code come from, so `tr(...)` follows the in-app choice.
/// Text("...") in views gets its language from the locale in the environment instead.
final class Localizer: @unchecked Sendable {
    static let shared = Localizer()

    private let lock = NSLock()
    private var current: AppLanguage

    init(language: AppLanguage = .system) {
        current = language
    }

    var language: AppLanguage {
        get { lock.withLock { current } }
        set {
            lock.withLock { current = newValue }
            LanguageChange.shared.revision += 1
        }
    }

    /// The folder of translations for the chosen language, or the app's own bundle for "System".
    var bundle: Bundle {
        guard let code = language.localeIdentifier,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    var locale: Locale {
        language.localeIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }

    /// A string written in code, in this localizer's language.
    func string(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: bundle, locale: locale)
    }
}

/// Views that call `tr` read this counter, so SwiftUI redraws them when the language changes.
@Observable
final class LanguageChange: @unchecked Sendable {
    static let shared = LanguageChange()
    var revision = 0
}

/// A string written in code, in the app's chosen language (`String(localized:)` would follow
/// only the phone's language).
func tr(_ value: String.LocalizationValue) -> String {
    _ = LanguageChange.shared.revision
    return Localizer.shared.string(value)
}
