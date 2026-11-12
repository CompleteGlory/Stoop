import SwiftUI

/// Find people by username, answer requests and manage friends. Lives in the map's bottom sheet.
struct FriendsSheet: View {
    let model: FriendsViewModel
    let safety: SafetyViewModel
    let close: () -> Void
    @State private var removing: PublicUser?
    @FocusState private var searchFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                SafetyNotice(safety: safety)
                searchField
                if let error = model.errorText {
                    Text(error).font(.footnote).foregroundStyle(Brand.negative.text)
                }
                if model.isSearchActive {
                    searchResults
                } else if model.isLoading {
                    ProgressView().tint(Brand.foreground).frame(maxWidth: .infinity)
                } else {
                    lists
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await model.load() }
        .confirmationDialog(
            Text("Remove \(removing?.name ?? "") from your friends?"),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove friend", role: .destructive) {
                if let user = removing { Task { await model.remove(user) } }
            }
        } message: {
            Text("You'll stop seeing each other on the map.")
        }
    }

    private var header: some View {
        HStack {
            Text("Friends").font(.system(.title2, design: .rounded, weight: .bold))
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .frame(width: 32, height: 32)
                    .background(Brand.surface, in: .circle)
            }
            .accessibilityLabel(Text("Close"))
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Brand.foreground.opacity(0.5))
            TextField(text: Binding(get: { model.query }, set: { model.query = $0 })) {
                Text("Search by username").foregroundStyle(Brand.foreground.opacity(0.45))
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($searchFocused)
            .submitLabel(.search)
            if model.isSearching {
                ProgressView().tint(Brand.foreground).controlSize(.small)
            } else if model.isSearchActive {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.foreground.opacity(0.5))
                }
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Brand.surface, in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var searchResults: some View {
        if FriendsViewModel.searchTerm(model.query) == nil {
            Hint(text: tr("Type at least 3 letters of a username."))
        } else if model.results.isEmpty && !model.isSearching {
            Hint(text: tr("No one with that username."))
        } else {
            VStack(spacing: 10) {
                ForEach(model.results) { result in
                    PersonRow(user: result.user) {
                        HStack(spacing: 2) {
                            resultAction(result)
                            SafetyMenu(safety: safety, user: result.user)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resultAction(_ result: UserSearchResult) -> some View {
        let isBusy = model.busy.contains(result.id)
        switch result.friendStatus {
        case .none:
            PillButton(title: tr("Add"), style: .primary, isBusy: isBusy) {
                Task { await model.send(to: result.user) }
            }
        case .requestReceived:
            PillButton(title: tr("Accept"), style: .primary, isBusy: isBusy) {
                Task { await model.send(to: result.user) } // sending back accepts theirs
            }
        case .requestSent:
            PillButton(title: tr("Requested"), style: .quiet, isBusy: isBusy) {
                Task { await model.remove(result.user) }
            }
            .accessibilityHint(Text("Cancels the request"))
        case .friends:
            Label("Friends", systemImage: "checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Brand.positive.text)
        }
    }

    @ViewBuilder
    private var lists: some View {
        if !model.incoming.isEmpty {
            Section(title: tr("Requests")) {
                ForEach(model.incoming) { entry in
                    PersonRow(user: entry.user) {
                        HStack(spacing: 8) {
                            PillButton(title: tr("Decline"), style: .quiet,
                                       isBusy: model.busy.contains(entry.user.id)) {
                                Task { await model.remove(entry.user) }
                            }
                            PillButton(title: tr("Accept"), style: .primary,
                                       isBusy: model.busy.contains(entry.user.id)) {
                                Task { await model.accept(entry) }
                            }
                            SafetyMenu(safety: safety, user: entry.user)
                        }
                    }
                }
            }
        }
        Section(title: tr("Your friends")) {
            if model.friends.isEmpty {
                Hint(text: tr("Search for a username to add your first friend."))
            }
            ForEach(model.friends) { entry in
                PersonRow(user: entry.user) {
                    SafetyMenu(safety: safety, user: entry.user, onRemove: { removing = entry.user })
                }
            }
        }
        if !model.outgoing.isEmpty {
            Section(title: tr("Sent")) {
                ForEach(model.outgoing) { entry in
                    PersonRow(user: entry.user) {
                        PillButton(title: tr("Cancel"), style: .quiet,
                                   isBusy: model.busy.contains(entry.user.id)) {
                            Task { await model.remove(entry.user) }
                        }
                    }
                }
            }
        }
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.foreground.opacity(0.7))
            content
        }
    }
}

private struct Hint: View {
    let text: String

    var body: some View {
        Text(text).font(.callout).foregroundStyle(Brand.foreground.opacity(0.6))
    }
}

/// Avatar, name and @username, with an action on the trailing side.
private struct PersonRow<Action: View>: View {
    let user: PublicUser
    @ViewBuilder let action: Action

    var body: some View {
        HStack(spacing: 12) {
            AvatarImage(avatar: user.avatar, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: user.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let username = user.username, username != user.name {
                    Text(verbatim: "@\(username)").font(.footnote).foregroundStyle(Brand.foreground.opacity(0.6))
                }
            }
            Spacer(minLength: 8)
            action
        }
        .padding(10)
        .background(Brand.surface, in: .rect(cornerRadius: 14))
    }
}

private struct PillButton: View {
    enum Style { case primary, quiet }
    let title: String
    let style: Style
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isBusy ? 0 : 1)
                if isBusy { ProgressView().controlSize(.small).tint(style == .primary ? Brand.ink : Brand.foreground) }
            }
            .font(.footnote.weight(.bold))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .foregroundStyle(style == .primary ? Brand.ink : Brand.foreground)
            .background(style == .primary ? Brand.accent : Brand.foreground.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}
