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
            case .place:
                if let place = model.placeModel {
                    PlaceSheet(model: place) { model.showBrowse() }
                        .id(place.placeId)
                }
            case .friends:
                if let friends = model.friendsModel {
                    FriendsSheet(model: friends, safety: model.safety) { model.showBrowse() }
                }
            case .blocked:
                BlockedSheet(safety: model.safety) { model.showProfile() }
            }
        }
        .foregroundStyle(Brand.foreground)
        .animation(.snappy, value: model.sheet)
    }
}

private struct BrowseSheet: View {
    let model: MapViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Brand.foreground.opacity(0.5))
                TextField(text: Binding(get: { model.search.query }, set: { model.search.query = $0 })) {
                    Text("Search places").foregroundStyle(Brand.foreground.opacity(0.45))
                }
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                if model.search.isSearching {
                    ProgressView().tint(Brand.foreground).controlSize(.small)
                } else if model.search.isActive {
                    Button { model.search.clear() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.foreground.opacity(0.5))
                    }
                    .accessibilityLabel(Text("Clear"))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Brand.surface, in: .rect(cornerRadius: 12))

            if model.search.isActive {
                SearchResults(model: model)
            }

            if model.isResolvingPlace {
                HStack(spacing: 8) {
                    ProgressView().tint(Brand.foreground).controlSize(.small)
                    Text("Opening place…").font(.footnote)
                }
            } else if let error = model.placeErrorText {
                Text(error).font(.footnote).foregroundStyle(Brand.negative.text)
            }

            if !model.search.isActive {
                HStack {
                    Text("Friends").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.foreground.opacity(0.7))
                    Spacer()
                    Button { model.showFriends() } label: {
                        HStack(spacing: 6) {
                            Label("Find friends", systemImage: "person.badge.plus")
                            if !model.friendsList.incoming.isEmpty {
                                Text(model.friendsList.incoming.count, format: .number)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Brand.background)
                                    .padding(.horizontal, 6)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(Brand.accent, in: .capsule)
                                    .accessibilityLabel(Text("\(model.friendsList.incoming.count) requests"))
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.accent)
                    }
                }

                if !model.friendsList.friends.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 14) {
                            ForEach(model.friendsList.friends) { entry in
                                let live = model.liveFriend(entry.user.id)
                                Button {
                                    if let live { model.focus(on: live) } else { model.showFriends() }
                                } label: {
                                    VStack(spacing: 4) {
                                        AvatarImage(avatar: entry.user.avatar, size: 44)
                                            .opacity(live == nil || live?.isDimmed == true ? 0.5 : 1)
                                        Text(verbatim: entry.user.name)
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
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .onChange(of: searchFocused) { _, focused in
            // room for the keyboard and the results
            if focused { model.detent = .large }
        }
        .onChange(of: model.sheet) { _, _ in searchFocused = false }
    }
}

/// Places found by the search field. Tapping one flies there and opens it.
private struct SearchResults: View {
    let model: MapViewModel

    var body: some View {
        let search = model.search
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if search.needsMoreLetters {
                    Hint(text: String(localized: "Keep typing to search."))
                } else if let error = search.errorText {
                    Text(error).font(.footnote).foregroundStyle(Brand.negative.text)
                } else if search.foundNothing {
                    Hint(text: String(localized: "No places found."))
                }
                ForEach(search.results) { result in
                    Button {
                        Task { await model.openSearchResult(result) }
                    } label: {
                        ResultRow(result: result)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct Hint: View {
    let text: String

    var body: some View {
        Text(text).font(.callout).foregroundStyle(Brand.foreground.opacity(0.6))
    }
}

private struct ResultRow: View {
    let result: PlaceSearchResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(Brand.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: result.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                let detail = [PlaceCategory.name(for: result.category), result.address].compactMap { $0 }.joined(separator: " · ")
                if !detail.isEmpty {
                    Text(verbatim: detail).font(.footnote).foregroundStyle(Brand.foreground.opacity(0.6)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: .rect(cornerRadius: 14))
        .contentShape(.rect)
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
                    Divider().overlay(Brand.foreground.opacity(0.1))
                    Button { model.showBlocked() } label: {
                        Label("Blocked people", systemImage: "hand.raised")
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
