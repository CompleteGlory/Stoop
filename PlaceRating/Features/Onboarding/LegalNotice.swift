import SwiftUI

/// "By continuing you accept the Terms of Use and the Privacy Policy", with both as links to the
/// pages the API serves. Shown where someone signs in or creates an account.
struct LegalNotice: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        // the links use a private scheme so the translated text doesn't have to contain real addresses
        Text("By continuing you accept the [Terms of Use](stoop://terms) and the [Privacy Policy](stoop://privacy).")
            .font(.caption2)
            .foregroundStyle(Brand.foreground.opacity(0.55))
            .tint(Brand.accent)
            .multilineTextAlignment(.center)
            .environment(\.openURL, OpenURLAction { url in
                switch url.host() {
                case "terms": openURL(AppConfig.current.termsURL)
                case "privacy": openURL(AppConfig.current.privacyURL)
                default: return .discarded
                }
                return .handled
            })
    }
}
