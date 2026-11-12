import MapKit
import SwiftUI

/// The app's one screen: the map, your character, your friends, and a bottom sheet for everything else.
struct MapScreen: View {
    let session: SessionStore
    @State private var model: MapViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsThemes = false
    @Environment(\.openURL) private var openURL

    init(session: SessionStore, user: SelfUser) {
        self.session = session
        _model = State(initialValue: MapViewModel(
            user: user,
            location: LiveLocationService(),
            socket: LiveSocketClient(url: { AppConfig.current.liveURL }, auth: session.liveAuth),
            onSessionExpired: { session.sessionExpired() },
            places: session.places,
            placesCache: session.placesCache,
            friendsAPI: session.friends,
            photosAPI: session.photos,
            moderationAPI: session.moderation
        ))
    }

    var body: some View {
        Map(position: $model.camera, selection: $model.mapSelection) {
            ForEach(model.places) { place in
                Annotation(place.name, coordinate: place.coordinate, anchor: .bottom) {
                    PlacePin(place: place) { model.open(place) }
                }
                .annotationTitles(.hidden)
            }
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
        .mapStyle(settings.mapTheme.style)
        .environment(\.colorScheme, settings.mapTheme.colorScheme ?? colorScheme)
        .mapControlVisibility(.hidden)
        .onMapCameraChange(frequency: .onEnd) { context in
            let region = context.region
            model.cameraSettled(center: region.center, latitudeDelta: region.span.latitudeDelta,
                                longitudeDelta: region.span.longitudeDelta)
        }
        .onChange(of: model.mapSelection) { _, selection in
            if let feature = selection?.feature { Task { await model.select(feature) } }
        }
        .safeAreaInset(edge: .top) { topBar }
        .overlay { if model.showsLocationPrompt { LocationPrompt(model: model) } }
        .sheet(isPresented: .constant(true)) {
            MapSheet(model: model, session: session)
                // the sheet is its own window layer: give it the chosen appearance directly, so a
                // theme change repaints it at once instead of the next time it opens
                .preferredColorScheme(settings.appearance.colorScheme)
                .presentationDetents([MapViewModel.smallDetent, .medium, .large], selection: $model.detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationBackground(Brand.background(for: settings.appearance.colorScheme ?? colorScheme))
                .presentationCornerRadius(28)
                .interactiveDismissDisabled()
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        #if DEBUG
        .task { await ScreenshotRun.openSheet(on: model) }
        #endif
        .onChange(of: session.pendingLink, initial: true) { _, link in
            guard let link else { return }
            session.pendingLink = nil
            model.openShared(link)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.start() } else { model.stop() }
        }
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                Button { model.showSettings() } label: {
                    AvatarImage(avatar: model.user.avatar, size: 46)
                        .overlay(Circle().stroke(Brand.foreground, lineWidth: 3))
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                }
                .accessibilityLabel(Text("Settings"))

                Spacer()
                SharingPill(count: model.sharingCount, isGhost: model.ghost)
                Spacer()

                VStack(spacing: 10) {
                    RoundButton(systemImage: model.ghost ? "eye.slash.fill" : "eye.fill",
                                label: tr("Ghost mode"), isOn: model.ghost) { model.toggleGhost() }
                    RoundButton(systemImage: "location.fill", label: tr("Recenter")) { model.recenter() }
                    RoundButton(systemImage: "square.2.layers.3d", label: tr("Map style"), isOn: showsThemes) { showsThemes = true }
                        .popover(isPresented: $showsThemes) {
                            MapThemePicker(selection: Bindable(settings).mapTheme)
                                .presentationCompactAdaptation(.popover)
                        }
                }
            }
            if model.isPaused {
                StatusBanner(systemImage: "pause.circle.fill", text: tr("Sharing is paused: Stoop is open on another device."))
            } else if model.connectionLost {
                StatusBanner(systemImage: "wifi.slash", text: tr("You're offline. Reconnecting…"))
            }
            if model.access == .denied {
                LocationDeniedBanner { openURL(URL(string: UIApplication.openSettingsURLString)!) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

/// A rated place: a navy tag with a gold star and its average.
private struct PlacePin: View {
    let place: Place
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").foregroundStyle(Brand.accent)
                    Text(place.avgRating, format: .number.precision(.fractionLength(1)))
                        .foregroundStyle(Brand.paper)
                }
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Brand.ink, in: .capsule)
                .overlay(Capsule().stroke(Brand.accent.opacity(0.8), lineWidth: 1.5))
                Image(systemName: "triangle.fill")
                    .font(.system(size: 7))
                    .rotationEffect(.degrees(180))
                    .foregroundStyle(Brand.ink)
                    .offset(y: -2)
            }
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .environment(\.layoutDirection, .leftToRight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: place.name))
    }
}

/// Your own character with a soft pulse, instead of the system's blue dot.
private struct SelfMarker: View {
    let avatar: Avatar?
    let isGhost: Bool

    var body: some View {
        // a still halo: a pulse that animated forever made the map redraw on every frame
        ZStack {
            Circle()
                .fill(Brand.accent.opacity(isGhost ? 0 : 0.28))
                .frame(width: 72, height: 72)
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
        .accessibilityLabel(Text("You"))
    }
}

/// Always says whether you are visible, so sharing is never invisible.
private struct SharingPill: View {
    let count: Int
    let isGhost: Bool

    var body: some View {
        Label {
            Text(isGhost ? tr("Ghost mode on") : tr("Sharing with \(count) friends"))
        } icon: {
            Image(systemName: isGhost ? "eye.slash.fill" : "dot.radiowaves.left.and.right")
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(isGhost ? Brand.ink : Brand.foreground)
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
                .foregroundStyle(isOn ? Brand.ink : Brand.foreground)
                .background(isOn ? Brand.accent : Brand.background.opacity(0.92), in: .circle)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .accessibilityLabel(Text(label))
    }
}

/// A one-line notice under the top bar (offline, sharing paused).
private struct StatusBanner: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Brand.foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Brand.background.opacity(0.95), in: .rect(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            .transition(.opacity)
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
