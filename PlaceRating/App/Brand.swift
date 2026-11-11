import SwiftUI

/// The app's identity in one place, so changing it never touches a screen.
enum Brand {
    static let background = Color(hex: 0x12233F)
    static let foreground = Color(hex: 0xF7F3E8)
    static let accent = Color(hex: 0xF4B740)
    /// Raised surfaces and the street lines of the map pattern.
    static let surface = Color(hex: 0x1C3157)
    static let street = Color(hex: 0x26406B)

    static let positive = (fill: Color(hex: 0x1F4D3A), text: Color(hex: 0x9FE1CB))
    static let negative = (fill: Color(hex: 0x5A2330), text: Color(hex: 0xF7A8B8))
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
            .foregroundStyle(isEnabled ? Brand.background : Brand.foreground.opacity(0.4))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isEnabled ? Brand.accent : Brand.surface, in: .rect(cornerRadius: 14))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
