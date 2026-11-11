import SwiftUI

/// Shows exactly one part of the app, decided by the session. Like a router redirect,
/// except a screen can't be reached in the wrong state because it isn't built at all.
struct RootView: View {
    let session: SessionStore

    var body: some View {
        Group {
            switch session.phase {
            case .launching:
                ProgressView()
                    .tint(Brand.foreground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Brand.background)
            case .signedOut:
                SignInView(session: session)
            case .needsUsername(let user):
                UsernameView(session: session, user: user)
            case .needsCharacter(let user):
                CharacterView(session: session, user: user)
            case .ready(let user):
                MapScreen(session: session, user: user)
                    .id(user.id)
            case .unavailable:
                UnavailableView(session: session)
            }
        }
        .task { await session.start() }
    }
}

private struct UnavailableView: View {
    let session: SessionStore

    var body: some View {
        ContentUnavailableView {
            Label("We couldn't reach the server.", systemImage: "wifi.slash")
        } actions: {
            Button("Try again") { Task { await session.start() } }
                .buttonStyle(BrandButtonStyle())
                .frame(maxWidth: 220)
        }
        .foregroundStyle(Brand.foreground)
        .background(Brand.background)
    }
}
