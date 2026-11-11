import SwiftUI

/// The Stoop logo: three front steps with a star above them, drawn in a 100-unit square.
struct StoopMark: View {
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 100, y: size.height / 100)
            for step in [
                CGRect(x: 20, y: 70, width: 60, height: 12),
                CGRect(x: 36, y: 56, width: 44, height: 14),
                CGRect(x: 52, y: 42, width: 28, height: 14),
            ] {
                context.fill(Path(roundedRect: step, cornerRadius: 2), with: .color(Brand.foreground))
            }
            context.fill(Self.star, with: .color(Brand.accent))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private static let star = Path { path in
        path.addLines([
            CGPoint(x: 36, y: 19), CGPoint(x: 39.2, y: 27.6), CGPoint(x: 48.4, y: 28),
            CGPoint(x: 41.2, y: 33.7), CGPoint(x: 43.6, y: 42.5), CGPoint(x: 36, y: 37.5),
            CGPoint(x: 28.4, y: 42.5), CGPoint(x: 30.8, y: 33.7), CGPoint(x: 23.6, y: 28),
            CGPoint(x: 32.8, y: 27.6),
        ])
        path.closeSubpath()
    }
}
