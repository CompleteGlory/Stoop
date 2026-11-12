import SwiftUI

/// Settings: who you are, how the app looks and speaks, sharing and privacy, storage, help and the
/// account. The map's own look is not here; it is picked on the map.
struct SettingsSheet: View {
    let model: MapViewModel
    let session: SessionStore
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    @State private var vm: SettingsViewModel
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    init(model: MapViewModel, session: SessionStore) {
        self.model = model
        self.session = session
        _vm = State(initialValue: SettingsViewModel(user: model.user, session: session))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Button { model.showBrowse() } label: {
                        Label("Back", systemImage: "chevron.backward").font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                }
                header
                appearanceGroup
                characterGroup
                sharingGroup
                storageGroup
                helpGroup
                accountGroup
                Text("Stoop \(SettingsViewModel.versionText)")
                    .font(.footnote)
                    .foregroundStyle(Brand.foreground.opacity(0.45))
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .alert(Text("Your name"), isPresented: $editingName) {
            TextField(text: $nameDraft) { Text("Display name") }
            Button("Save") { Task { await vm.saveDisplayName(nameDraft) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Friends see this name on the map.")
        }
        .confirmationDialog(Text("Delete your account?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete my account", role: .destructive) { deleteAccount() }
        } message: {
            Text("This permanently deletes your ratings, comments, photos, friendships and account. It can't be undone.")
        }
    }

    // MARK: groups

    private var header: some View {
        VStack(spacing: 8) {
            AvatarImage(avatar: model.user.avatar, size: 88)
                .overlay(Circle().stroke(Brand.accent, lineWidth: 3))
            Button {
                nameDraft = vm.displayName
                editingName = true
            } label: {
                HStack(spacing: 6) {
                    Text(verbatim: vm.displayName).font(.system(.title2, design: .rounded, weight: .bold))
                    Image(systemName: "pencil").font(.footnote.weight(.bold)).foregroundStyle(Brand.accent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Changes your display name"))
            if let username = model.user.username {
                Text(verbatim: "@\(username)").foregroundStyle(Brand.foreground.opacity(0.6))
            }
            if vm.isSavingName { ProgressView().tint(Brand.foreground).controlSize(.small) }
            if let error = vm.nameError {
                Text(error).font(.footnote).foregroundStyle(Brand.negative.text)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var appearanceGroup: some View {
        Group_(title: "Appearance") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledPicker(title: "Theme", selection: Bindable(settings).appearance, options: AppAppearance.allCases) { $0.title }
                LabeledPicker(title: "Language", selection: Bindable(settings).language, options: AppLanguage.allCases) { $0.title }
            }
            .padding(14)
        }
    }

    private var characterGroup: some View {
        Group_(title: "Character") {
            Button { session.editCharacter() } label: {
                Row(title: "Edit character", systemImage: "paintbrush")
            }
            .buttonStyle(.plain)
        }
    }

    private var sharingGroup: some View {
        Group_(title: "Sharing and privacy") {
            Toggle(isOn: Binding(get: { model.ghost }, set: { _ in model.toggleGhost() })) {
                Label("Ghost mode", systemImage: "eye.slash")
            }
            .tint(Brand.accent)
            .padding(14)
            Divider().overlay(Brand.foreground.opacity(0.1))
            Text(model.ghost ? tr("Ghost mode on") : tr("Sharing with \(model.sharingCount) friends"))
                .font(.footnote)
                .foregroundStyle(Brand.foreground.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider().overlay(Brand.foreground.opacity(0.1))
            locationRow
            Divider().overlay(Brand.foreground.opacity(0.1))
            Button { model.showBlocked() } label: {
                Row(title: "Blocked people", systemImage: "hand.raised")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var locationRow: some View {
        switch model.access {
        case .allowed:
            Row(title: "Location", systemImage: "location", detail: tr("On while Stoop is open"), showsChevron: false)
        case .denied:
            Button { openURL(URL(string: UIApplication.openSettingsURLString)!) } label: {
                Row(title: "Location", systemImage: "location.slash", detail: tr("Off. Open Settings to turn it on."))
            }
            .buttonStyle(.plain)
        case .unknown:
            Button { model.allowLocation() } label: {
                Row(title: "Location", systemImage: "location", detail: tr("Not set up yet"))
            }
            .buttonStyle(.plain)
        }
    }

    private var storageGroup: some View {
        Group_(title: "Storage") {
            Button { Task { await vm.clearImageCache() } } label: {
                Row(
                    title: "Clear cached images", systemImage: "trash",
                    detail: vm.cacheCleared ? tr("Cleared") : nil, showsChevron: false
                )
            }
            .buttonStyle(.plain)
            .disabled(vm.isClearingCache)
        }
    }

    private var helpGroup: some View {
        Group_(title: "Help and legal") {
            LinkRow(title: tr("Contact support"), systemImage: "envelope", url: URL(string: "mailto:\(AppConfig.supportEmail)")!)
            Divider().overlay(Brand.foreground.opacity(0.1))
            LinkRow(title: tr("Terms of Use"), systemImage: "doc.text", url: AppConfig.current.termsURL)
            Divider().overlay(Brand.foreground.opacity(0.1))
            LinkRow(title: tr("Privacy Policy"), systemImage: "lock.shield", url: AppConfig.current.privacyURL)
        }
    }

    private var accountGroup: some View {
        VStack(spacing: 14) {
            Button("Sign out", role: .destructive) { Task { await session.signOut() } }
                .font(.callout.weight(.semibold))
                .foregroundStyle(Brand.negative.text)
            Button("Delete account", role: .destructive) { confirmingDelete = true }
                .font(.footnote)
                .foregroundStyle(Brand.negative.text.opacity(0.8))
                .disabled(isDeleting)
            if isDeleting { ProgressView().tint(Brand.foreground) }
            if let deleteError {
                Text(deleteError).font(.footnote).foregroundStyle(Brand.negative.text).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func deleteAccount() {
        Task {
            isDeleting = true
            deleteError = nil
            do {
                try await session.deleteAccount()
            } catch {
                deleteError = ErrorText.text(for: error)
            }
            isDeleting = false
        }
    }
}

// MARK: building blocks

/// A titled card of rows.
private struct Group_<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Brand.foreground.opacity(0.6))
                .padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .background(Brand.surface, in: .rect(cornerRadius: 14))
        }
    }
}

private struct Row: View {
    let title: LocalizedStringKey
    let systemImage: String
    var detail: String?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 8)
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(Brand.foreground.opacity(0.6)).multilineTextAlignment(.trailing)
            }
            if showsChevron {
                Image(systemName: "chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(Brand.foreground.opacity(0.4))
            }
        }
        .padding(14)
        .contentShape(.rect)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LinkRow: View {
    let title: String
    let systemImage: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(Brand.foreground.opacity(0.4))
            }
            .padding(14)
            .contentShape(.rect)
        }
        .foregroundStyle(Brand.foreground)
    }
}

/// A title above a segmented control.
private struct LabeledPicker<Option: Hashable & Identifiable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Picker(selection: $selection) {
                ForEach(options) { option in Text(label(option)).tag(option) }
            } label: {
                Text(title)
            }
            .pickerStyle(.segmented)
        }
    }
}
