import MapKit
import SwiftUI

/// How the map looks, picked on the map itself. MapKit can't recolour its tiles freely, so each
/// theme combines what it does offer: the map type, a muted or dark rendering, 3D terrain, and
/// which kinds of places are shown.
enum MapTheme: String, CaseIterable, Identifiable, Sendable {
    case classic, muted, night, satellite, hybrid, terrain, food, nature, minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: tr("Classic")
        case .muted: tr("Soft")
        case .night: tr("Night")
        case .satellite: tr("Satellite")
        case .hybrid: tr("Hybrid")
        case .terrain: tr("Terrain")
        case .food: tr("Food")
        case .nature: tr("Nature")
        case .minimal: tr("Minimal")
        }
    }

    var systemImage: String {
        switch self {
        case .classic: "map"
        case .muted: "cloud.fog"
        case .night: "moon.stars"
        case .satellite: "globe.europe.africa"
        case .hybrid: "square.stack.3d.up"
        case .terrain: "mountain.2"
        case .food: "fork.knife"
        case .nature: "leaf"
        case .minimal: "circle.dotted"
        }
    }

    /// Two colours for the picker's swatch: roughly the theme's land and water or ground.
    var swatch: [Color] {
        switch self {
        case .classic: [Color(hex: 0xF2EFE9), Color(hex: 0xA6D4F2)]
        case .muted: [Color(hex: 0xEDEBE6), Color(hex: 0xCBD8E0)]
        case .night: [Color(hex: 0x1E2A44), Color(hex: 0x0F1B33)]
        case .satellite: [Color(hex: 0x4F6B3C), Color(hex: 0x1F4E79)]
        case .hybrid: [Color(hex: 0x6B7F52), Color(hex: 0x2B5C8A)]
        case .terrain: [Color(hex: 0xC9B98A), Color(hex: 0x7FA37A)]
        case .food: [Color(hex: 0xF7E3C4), Color(hex: 0xF4B740)]
        case .nature: [Color(hex: 0xCFE8C4), Color(hex: 0x7FBF8F)]
        case .minimal: [Color(hex: 0xF5F5F3), Color(hex: 0xE3E3DF)]
        }
    }

    /// The map's own light or dark appearance, whatever the app is set to. nil follows the app.
    var colorScheme: ColorScheme? {
        self == .night ? .dark : nil
    }

    var style: MapStyle {
        switch self {
        case .classic:
            .standard(elevation: .flat, emphasis: .automatic, pointsOfInterest: .all)
        case .muted:
            .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .all)
        case .night:
            .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .all)
        case .satellite:
            .imagery(elevation: .flat)
        case .hybrid:
            .hybrid(elevation: .flat, pointsOfInterest: .all)
        case .terrain:
            .standard(elevation: .realistic, emphasis: .automatic, pointsOfInterest: .all)
        case .food:
            .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .including([
                .restaurant, .cafe, .bakery, .brewery, .winery, .nightlife, .foodMarket,
            ]))
        case .nature:
            .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .including([
                .park, .nationalPark, .beach, .campground, .zoo, .aquarium, .marina,
            ]))
        case .minimal:
            .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)
        }
    }
}

/// The small chooser behind the map's layers button.
struct MapThemePicker: View {
    @Binding var selection: MapTheme
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Map style").font(.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(MapTheme.allCases) { theme in
                    Button {
                        selection = theme
                        dismiss()
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                LinearGradient(colors: theme.swatch, startPoint: .topLeading, endPoint: .bottomTrailing)
                                Image(systemName: theme.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(theme == .night || theme == .satellite || theme == .hybrid ? Color.white : Brand.ink)
                            }
                            .frame(height: 54)
                            .clipShape(.rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selection == theme ? Brand.accent : .clear, lineWidth: 3)
                            }
                            Text(theme.title)
                                .font(.caption.weight(selection == theme ? .bold : .medium))
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == theme ? .isSelected : [])
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .foregroundStyle(Brand.foreground)
        .background(Brand.background)
    }
}
