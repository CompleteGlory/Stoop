import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @State private var model: SignInViewModel
    #if DEBUG
    @State private var devUsername = ""
    @State private var server = DebugServer.selected
    #endif

    init(session: SessionStore) {
        _model = State(initialValue: SignInViewModel(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            FriendsOnAMap()
                .frame(maxHeight: .infinity)

            VStack(spacing: 10) {
                StoopMark()
                    .frame(width: 92, height: 92)
                Text(verbatim: "Stoop")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.foreground)
                Text("Your friends, your places, one map")
                    .font(.callout)
                    .foregroundStyle(Brand.foreground.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 32)

            VStack(spacing: 14) {
                if let error = model.errorText {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Brand.negative.text)
                        .multilineTextAlignment(.center)
                }

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                    request.nonce = model.prepareNonce()
                } onCompletion: { result in
                    Task { await model.complete(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 52)
                .clipShape(.rect(cornerRadius: 14))
                .disabled(model.isBusy)

                Text("By continuing you accept the Terms and Privacy Policy.")
                    .font(.caption2)
                    .foregroundStyle(Brand.foreground.opacity(0.55))
                    .multilineTextAlignment(.center)

                #if DEBUG
                debugControls
                #endif
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(Brand.background)
    }

    #if DEBUG
    /// Developer tools, compiled out of Release builds, so they aren't translated.
    private var debugControls: some View {
        VStack(spacing: 8) {
            Picker(selection: $server) {
                ForEach(DebugServer.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
            } label: {
                Text(verbatim: "Server")
            }
            .pickerStyle(.segmented)
            .colorScheme(.dark)
            .onChange(of: server) { DebugServer.selected = server }

            if server == .local {
                HStack {
                    TextField(text: $devUsername) {
                        Text(verbatim: "dev username").foregroundStyle(Brand.foreground.opacity(0.4))
                    }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(Brand.surface, in: .rect(cornerRadius: 10))
                        .foregroundStyle(Brand.foreground)
                        .accessibilityIdentifier("devUsername")
                    Button {
                        Task { await model.devSignIn(username: devUsername) }
                    } label: {
                        Text(verbatim: "Dev sign in").font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.accent)
                    .accessibilityIdentifier("devSignIn")
                }
            }
        }
        .padding(.top, 4)
    }
    #endif
}

/// The decorative top half: a street map with a few friends on it, fading into the background.
private struct FriendsOnAMap: View {
    private struct Friend {
        let preset: String
        let name: String
        let x: Double
        let y: Double
        let rating: String?
        let isActive: Bool
    }

    private let friends = [
        Friend(preset: "panda", name: "nia", x: 0.24, y: 0.36, rating: "4.5", isActive: true),
        Friend(preset: "owl", name: "omar", x: 0.76, y: 0.2, rating: nil, isActive: false),
        Friend(preset: "fox", name: "sara", x: 0.68, y: 0.62, rating: nil, isActive: true),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                StreetPattern()
                ForEach(friends, id: \.name) { friend in
                    VStack(spacing: 6) {
                        MapMarker(
                            avatar: Avatar(kind: .preset, value: friend.preset, url: nil),
                            name: friend.name,
                            size: 40,
                            showsRing: friend.isActive
                        )
                        if let rating = friend.rating {
                            Label {
                                Text(verbatim: rating)
                            } icon: {
                                Image(systemName: "star.fill")
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Brand.background)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Brand.accent, in: .capsule)
                        }
                    }
                    .opacity(friend.isActive ? 1 : 0.5)
                    .position(x: proxy.size.width * friend.x, y: proxy.size.height * friend.y)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .mask {
            LinearGradient(
                stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityHidden(true)
    }
}
