import SwiftUI

/// The app's identity in one place, so changing it never touches a screen.
/// Dark is the Night garden look (navy with cream); light swaps them. `ink` and `paper` never change:
/// they are for text on gold, text in input fields, and everything that sits on the map.
enum Brand {
    static let background = adaptive(dark: 0x12233F, light: 0xF7F3E8)
    static let foreground = adaptive(dark: 0xF7F3E8, light: 0x12233F)
    /// Gold. A little deeper in light mode so it still reads on cream.
    static let accent = adaptive(dark: 0xF4B740, light: 0xBF8200)
    /// Raised surfaces and the street lines of the map pattern.
    static let surface = adaptive(dark: 0x1C3157, light: 0xEBE4D0)
    static let street = adaptive(dark: 0x26406B, light: 0xDCD4BC)
    /// Input fields: cream on navy, white on cream.
    static let field = adaptive(dark: 0xF7F3E8, light: 0xFFFFFF)

    /// Always navy: text on gold and in input fields.
    static let ink = Color(hex: 0x12233F)
    /// Always cream: avatar backdrops and map labels.
    static let paper = Color(hex: 0xF7F3E8)

    static let positive = (
        fill: adaptive(dark: 0x1F4D3A, light: 0xD3EDE0),
        text: adaptive(dark: 0x9FE1CB, light: 0x1B5B43)
    )
    static let negative = (
        fill: adaptive(dark: 0x5A2330, light: 0xF8DCE2),
        text: adaptive(dark: 0xF7A8B8, light: 0x9A2640)
    )

    /// The sheet background for a known appearance. The bottom sheet's background is handed to
    /// UIKit once, so it gets a plain colour that changes when the appearance does.
    static func background(for scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? 0x12233F : 0xF7F3E8)
    }

    private static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat(hex >> 16 & 0xFF) / 255,
                green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double(hex >> 16 & 0xFF) / 255,
            green: Double(hex >> 8 & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The gold primary button.
struct BrandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .fontDesign(.rounded)
            .foregroundStyle(isEnabled ? Brand.ink : Brand.foreground.opacity(0.4))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isEnabled ? Brand.accent : Brand.surface, in: .rect(cornerRadius: 14))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
