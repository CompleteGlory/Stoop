import MapKit
import SwiftUI

/// The app's one screen. Everything else will be a sheet or an overlay on this map.
struct MapScreen: View {
    let session: SessionStore

    var body: some View {
        Map()
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button("Sign out") { Task { await session.signOut() } }
                    .buttonStyle(.borderedProminent)
                    .padding()
                    .accessibilityIdentifier("signOut")
            }
    }
}
