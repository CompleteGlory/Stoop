import SwiftUI

/// A faint street map, drawn in relative coordinates so it fits any size.
struct StreetPattern: View {
    var color: Color = Brand.surface

    var body: some View {
        Canvas { context, size in
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: x * size.width, y: y * size.height)
            }
            let avenues: [[CGPoint]] = [
                [point(-0.05, 0.16), point(1.05, 0.08)],
                [point(-0.05, 0.62), point(1.05, 0.72)],
                [point(0.25, -0.05), point(0.38, 1.05)],
                [point(0.73, -0.05), point(0.63, 1.05)],
            ]
            let streets: [[CGPoint]] = [
                [point(-0.05, 0.4), point(1.05, 0.42)],
                [point(0.08, -0.05), point(0.14, 1.05)],
                [point(0.9, -0.05), point(0.86, 1.05)],
                [point(-0.05, 0.9), point(1.05, 0.86)],
            ]
            for line in avenues {
                context.stroke(Path { $0.addLines(line) }, with: .color(color), lineWidth: 9)
            }
            for line in streets {
                context.stroke(Path { $0.addLines(line) }, with: .color(color), lineWidth: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The emoji drawn for each preset avatar until real artwork exists.
enum AvatarPreset {
    static let emoji: [String: String] = [
        "fox": "🦊", "panda": "🐼", "koala": "🐨", "owl": "🦉", "frog": "🐸", "tiger": "🐯",
        "whale": "🐳", "penguin": "🐧", "cat": "🐱", "dog": "🐶", "rabbit": "🐰", "bear": "🐻",
        "lion": "🦁", "octopus": "🐙", "turtle": "🐢", "dolphin": "🐬", "giraffe": "🦒",
        "monkey": "🐵", "hedgehog": "🦔", "sloth": "🦥", "unicorn": "🦄", "robot": "🤖",
        "alien": "👽", "ghost": "👻",
    ]
}

/// A person's avatar in a cream circle: the preset's emoji, or their uploaded photo.
struct AvatarBadge: View {
    let avatar: Avatar
    var size: CGFloat = 44

    var body: some View {
        Circle()
            .fill(Brand.foreground)
            .frame(width: size, height: size)
            .overlay {
                switch avatar.kind {
                case .preset:
                    Text(verbatim: AvatarPreset.emoji[avatar.value] ?? "🦊")
                        .font(.system(size: size * 0.55))
                case .upload:
                    AsyncImage(url: avatar.url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                    .clipShape(.circle)
                }
            }
            .accessibilityHidden(true)
    }
}

/// How a person appears on friends' maps: their avatar with a soft ring and a name pill.
struct MapMarker: View {
    let avatar: Avatar
    let name: String
    var size: CGFloat = 52
    var showsRing = true

    var body: some View {
        VStack(spacing: 6) {
            AvatarBadge(avatar: avatar, size: size)
                .padding(5)
                .overlay {
                    if showsRing {
                        Circle().stroke(Brand.accent.opacity(0.7), lineWidth: 2)
                    }
                }
            Text(verbatim: name)
                .font(.caption.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(Brand.background)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Brand.foreground, in: .capsule)
        }
    }
}
