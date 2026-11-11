import SwiftUI

/// The bottom sheet: browse (search and friends) or your profile.
struct MapSheet: View {
    let model: MapViewModel
    let session: SessionStore

    var body: some View {
        Group {
            switch model.sheet {
            case .browse: BrowseSheet(model: model)
            case .profile: ProfileSheet(model: model, session: session)
            }
        }
        .foregroundStyle(Brand.foreground)
        .animation(.snappy, value: model.sheet)
    }
}

private struct BrowseSheet: View {
    let model: MapViewModel
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Brand.foreground.opacity(0.5))
                TextField(text: $query) {
                    Text("Search places").foregroundStyle(Brand.foreground.opacity(0.45))
                }
                .disabled(true) // place search arrives with the API work (milestone 7)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Brand.surface, in: .rect(cornerRadius: 12))

            if model.visibleFriends.isEmpty {
                Label("Find friends", systemImage: "person.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.accent)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(model.visibleFriends) { friend in
                            Button { model.focus(on: friend) } label: {
                                VStack(spacing: 4) {
                                    AvatarImage(avatar: friend.person.avatar, size: 44)
                                        .opacity(friend.isDimmed ? 0.5 : 1)
                                    Text(verbatim: friend.person.name)
                                        .font(.caption2.weight(.medium))
                                        .lineLimit(1)
                                }
                                .frame(width: 56)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }
}

private struct ProfileSheet: View {
    let model: MapViewModel
    let session: SessionStore

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Button { model.showBrowse() } label: {
                        Label("Back", systemImage: "chevron.backward").font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                }

                AvatarImage(avatar: model.user.avatar, size: 96)
                    .overlay(Circle().stroke(Brand.accent, lineWidth: 3))
                VStack(spacing: 2) {
                    Text(verbatim: model.user.displayName.isEmpty ? (model.user.username ?? "") : model.user.displayName)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    if let username = model.user.username {
                        Text(verbatim: "@\(username)").foregroundStyle(Brand.foreground.opacity(0.6))
                    }
                }

                VStack(spacing: 0) {
                    Toggle(isOn: Binding(get: { model.ghost }, set: { _ in model.toggleGhost() })) {
                        Label("Ghost mode", systemImage: "eye.slash")
                    }
                    .tint(Brand.accent)
                    .padding(14)
                    Divider().overlay(Brand.foreground.opacity(0.1))
                    Button { session.editCharacter() } label: {
                        Label("Edit character", systemImage: "paintbrush")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .buttonStyle(.plain)
                }
                .background(Brand.surface, in: .rect(cornerRadius: 14))

                Text(model.ghost ? String(localized: "Ghost mode on") : String(localized: "Sharing with \(model.sharingCount) friends"))
                    .font(.footnote)
                    .foregroundStyle(Brand.foreground.opacity(0.6))

                Button("Sign out", role: .destructive) { Task { await session.signOut() } }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Brand.negative.text)
                    .padding(.top, 6)
            }
            .padding(20)
        }
    }
}
