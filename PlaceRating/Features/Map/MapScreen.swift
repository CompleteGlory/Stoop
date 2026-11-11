import MapKit
import SwiftUI

/// The app's one screen: the map, your character, your friends, and a bottom sheet for everything else.
struct MapScreen: View {
    let session: SessionStore
    @State private var model: MapViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(session: SessionStore, user: SelfUser) {
        self.session = session
        _model = State(initialValue: MapViewModel(
            user: user,
            location: LiveLocationService(),
            socket: MockLiveSocket(),
            people: MockLiveSocket.people
        ))
    }

    var body: some View {
        Map(position: $model.camera) {
            if let me = model.me {
                Annotation("", coordinate: me, anchor: .center) {
                    SelfMarker(avatar: model.user.avatar, isGhost: model.ghost)
                }
                .annotationTitles(.hidden)
            }
            ForEach(model.visibleFriends) { friend in
                Annotation(friend.person.name, coordinate: friend.coordinate, anchor: .bottom) {
                    MapMarker(avatar: friend.person.avatar, name: friend.person.name, size: 42, showsRing: !friend.isDimmed)
                        .opacity(friend.isDimmed ? 0.45 : 1)
                        .animation(.easeInOut(duration: 0.6), value: friend.coordinate.latitude)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .all))
        .mapControlVisibility(.hidden)
        .safeAreaInset(edge: .top) { topBar }
        .overlay { if model.showsLocationPrompt { LocationPrompt(model: model) } }
        .sheet(isPresented: .constant(true)) {
            MapSheet(model: model, session: session)
                .presentationDetents([MapViewModel.smallDetent, .medium, .large], selection: $model.detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationBackground(Brand.background)
                .presentationCornerRadius(28)
                .interactiveDismissDisabled()
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.start() } else { model.stop() }
        }
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                Button { model.showProfile() } label: {
                    AvatarImage(avatar: model.user.avatar, size: 46)
                        .overlay(Circle().stroke(Brand.foreground, lineWidth: 3))
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                }
                .accessibilityLabel(Text("Profile"))

                Spacer()
                SharingPill(count: model.sharingCount, isGhost: model.ghost)
                Spacer()

                VStack(spacing: 10) {
                    RoundButton(systemImage: model.ghost ? "eye.slash.fill" : "eye.fill",
                                label: String(localized: "Ghost mode"), isOn: model.ghost) { model.toggleGhost() }
                    RoundButton(systemImage: "location.fill", label: String(localized: "Recenter")) { model.recenter() }
                }
            }
            if model.access == .denied {
                LocationDeniedBanner { openURL(URL(string: UIApplication.openSettingsURLString)!) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

/// Your own character with a soft pulse, instead of the system's blue dot.
private struct SelfMarker: View {
    let avatar: Avatar?
    let isGhost: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Brand.accent.opacity(0.35))
                .frame(width: 56, height: 56)
                .scaleEffect(pulse ? 1.7 : 1)
                .opacity(pulse || isGhost ? 0 : 1)
            AvatarImage(avatar: avatar, size: 48)
                .overlay(Circle().stroke(Brand.accent, lineWidth: 3))
                .opacity(isGhost ? 0.5 : 1)
            if isGhost {
                Image(systemName: "eye.slash.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Brand.foreground)
                    .padding(5)
                    .background(Brand.background, in: .circle)
                    .offset(x: 18, y: 18)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityLabel(Text("You"))
    }
}

/// Always says whether you are visible, so sharing is never invisible.
private struct SharingPill: View {
    let count: Int
    let isGhost: Bool

    var body: some View {
        Label {
            Text(isGhost ? String(localized: "Ghost mode on") : String(localized: "Sharing with \(count) friends"))
        } icon: {
            Image(systemName: isGhost ? "eye.slash.fill" : "dot.radiowaves.left.and.right")
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(isGhost ? Brand.background : Brand.foreground)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isGhost ? Brand.accent : Brand.background.opacity(0.92), in: .capsule)
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .animation(.snappy, value: isGhost)
    }
}

private struct RoundButton: View {
    let systemImage: String
    let label: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(isOn ? Brand.background : Brand.foreground)
                .background(isOn ? Brand.accent : Brand.background.opacity(0.92), in: .circle)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .accessibilityLabel(Text(label))
    }
}

private struct LocationDeniedBanner: View {
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.slash.fill")
            Text("Turn on location to share with friends")
                .font(.footnote.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Settings", action: openSettings)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Brand.accent)
        }
        .foregroundStyle(Brand.foreground)
        .padding(12)
        .background(Brand.background.opacity(0.95), in: .rect(cornerRadius: 14))
    }
}

/// The app's own explanation, shown before the system's location prompt.
private struct LocationPrompt: View {
    let model: MapViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Brand.accent)
                Text("Show friends where you are?")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Your location is shown to friends you accept, while the app is open.")
                    .font(.callout)
                    .foregroundStyle(Brand.foreground.opacity(0.75))
                    .multilineTextAlignment(.center)
                Button("Turn on location") { model.allowLocation() }
                    .buttonStyle(BrandButtonStyle())
                Button("Not now") { model.dismissLocationPrompt() }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Brand.foreground.opacity(0.75))
            }
            .foregroundStyle(Brand.foreground)
            .padding(24)
            .background(Brand.background, in: .rect(cornerRadius: 24))
            .padding(28)
        }
    }
}
