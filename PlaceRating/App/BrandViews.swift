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

/// A person's DiceBear character in a cream circle, or a plain figure before they have one.
struct AvatarImage: View {
    let avatar: Avatar?
    var size: CGFloat = 44

    @Environment(\.avatarRenderer) private var injected
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Circle()
            .fill(Brand.foreground)
            .frame(width: size, height: size)
            .overlay {
                if let image, avatar != nil {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if avatar == nil {
                    Image(systemName: "person.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.24)
                        .foregroundStyle(Brand.background.opacity(0.3))
                }
            }
            .clipShape(.circle)
            .task(id: avatar) {
                guard let avatar else { return }
                let renderer = injected ?? DiceBearRenderer.shared
                // keep the previous picture until the new one is ready, so changes don't flicker
                if let rendered = try? await renderer.image(for: avatar, pixels: Int(size * displayScale)) {
                    image = rendered
                }
            }
            .accessibilityHidden(true)
    }
}

/// How a person appears on friends' maps: their avatar with a soft ring and a name pill.
struct MapMarker: View {
    let avatar: Avatar?
    let name: String
    var size: CGFloat = 52
    var showsRing = true

    var body: some View {
        VStack(spacing: 6) {
            AvatarImage(avatar: avatar, size: size)
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
