import SwiftUI

struct UsernameView: View {
    let session: SessionStore
    let user: SelfUser
    @State private var model: UsernameViewModel
    @FocusState private var fieldFocused: Bool

    init(session: SessionStore, user: SelfUser) {
        self.session = session
        self.user = user
        _model = State(initialValue: UsernameViewModel(session: session, user: user))
    }

    private var previewName: String {
        let name = UsernameRules.normalized(model.username)
        return name.isEmpty ? "…" : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pick your name")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Brand.foreground)
                Text("This is how friends see you on the map.")
                    .font(.callout)
                    .foregroundStyle(Brand.foreground.opacity(0.7))
            }

            MarkerPreview(avatar: user.avatar, name: previewName)

            usernameField

            statusChip
                .frame(height: 24)
                .animation(.snappy, value: model.status)

            Spacer()

            Button {
                Task { await model.submit() }
            } label: {
                if model.isSaving { ProgressView().tint(Brand.background) } else { Text("Continue") }
            }
            .buttonStyle(BrandButtonStyle())
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("continue")

            Button("Use a different Apple ID") {
                Task { await session.signOut() }
            }
            .font(.footnote)
            .foregroundStyle(Brand.foreground.opacity(0.7))
            .frame(maxWidth: .infinity)
        }
        .padding(24)
        .background(Brand.background)
        .onAppear { fieldFocused = true }
    }

    /// Usernames are Latin only, so the field reads left to right in every language.
    private var usernameField: some View {
        HStack(spacing: 2) {
            Text(verbatim: "@")
                .foregroundStyle(Brand.background.opacity(0.4))
            TextField(text: $model.username) {
                // a Latin example in every language: it shows the allowed format, and an
                // Arabic placeholder would run into the "@" in this left-to-right field
                Text(verbatim: "your.name").foregroundStyle(Brand.background.opacity(0.35))
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .submitLabel(.continue)
            .focused($fieldFocused)
            .onSubmit { Task { await model.submit() } }
            .onChange(of: model.username) { model.usernameChanged() }
            .accessibilityIdentifier("username")
        }
        .font(.title3.weight(.medium))
        .foregroundStyle(Brand.background)
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(Brand.foreground, in: .rect(cornerRadius: 14))
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder
    private var statusChip: some View {
        if let error = model.errorText {
            Chip(text: error, colors: Brand.negative)
        } else {
            switch model.status {
            case .idle, .unknown:
                EmptyView()
            case .checking:
                Chip(text: String(localized: "Checking…"), colors: (Brand.surface, Brand.foreground.opacity(0.75)))
            case .available:
                Chip(text: String(localized: "Available"), systemImage: "checkmark", colors: Brand.positive)
            case .taken:
                Chip(text: String(localized: "That username is taken."), colors: Brand.negative)
            case .reserved:
                Chip(text: String(localized: "That username isn't available."), colors: Brand.negative)
            case .invalid:
                Chip(text: String(localized: "Use 3 to 20 letters, digits, _ or ."), colors: Brand.negative)
            }
        }
    }
}

/// A small map tile showing the person's marker with the name they are typing.
private struct MarkerPreview: View {
    let avatar: Avatar
    let name: String

    var body: some View {
        ZStack {
            Brand.surface
            StreetPattern(color: Brand.street)
            MapMarker(avatar: avatar, name: name)
                .animation(.snappy, value: name)
        }
        .frame(height: 170)
        .clipShape(.rect(cornerRadius: 20))
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: name))
    }
}

private struct Chip: View {
    let text: String
    var systemImage: String?
    let colors: (fill: Color, text: Color)

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.caption.weight(.bold)) }
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(colors.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(colors.fill, in: .capsule)
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
    }
}
