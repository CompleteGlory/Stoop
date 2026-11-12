import SwiftUI

/// The "…" menu on someone else's rating, photo or profile row: report the content, report the
/// person, or block them. Never shown for your own content.
struct SafetyMenu: View {
    struct Content {
        let target: ReportTarget
        let id: String
        let title: String
    }

    let safety: SafetyViewModel
    let user: PublicUser
    var content: Content?
    var tint: Color = Brand.foreground
    /// Friends only: adds "Remove friend" at the top of the menu.
    var onRemove: (() -> Void)?

    @State private var reporting: (target: ReportTarget, id: String)?
    @State private var confirmingBlock = false

    var body: some View {
        Menu {
            if let onRemove {
                Button(tr("Remove friend"), systemImage: "person.badge.minus", action: onRemove)
            }
            if let content {
                Button(content.title, systemImage: "flag") { reporting = (content.target, content.id) }
            }
            Button(tr("Report user"), systemImage: "exclamationmark.bubble") { reporting = (.user, user.id) }
            Button(tr("Block user"), systemImage: "hand.raised", role: .destructive) { confirmingBlock = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.footnote.weight(.bold))
                .foregroundStyle(tint.opacity(0.7))
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .accessibilityLabel(Text("More"))
        .confirmationDialog(
            Text("Why are you reporting this?"),
            isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }),
            titleVisibility: .visible
        ) {
            ForEach(ReportReason.allCases, id: \.self) { reason in
                Button(reason.title) {
                    guard let reporting else { return }
                    Task { await safety.report(reporting.target, id: reporting.id, reason: reason) }
                }
            }
        }
        .confirmationDialog(Text("Block \(user.name)?"), isPresented: $confirmingBlock, titleVisibility: .visible) {
            Button(tr("Block user"), role: .destructive) { Task { await safety.block(user) } }
        } message: {
            Text("You won't see each other anywhere in Stoop. You can unblock them from your profile.")
        }
    }
}

/// A confirmation or an error from the last report or block, under a sheet's header.
struct SafetyNotice: View {
    let safety: SafetyViewModel

    var body: some View {
        if let error = safety.errorText {
            Text(error).font(.footnote).foregroundStyle(Brand.negative.text)
        } else if let notice = safety.noticeText {
            Label(notice, systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Brand.positive.text)
                .transition(.opacity)
        }
    }
}

extension ReportReason {
    var title: String {
        switch self {
        case .spam: tr("Spam")
        case .abuse: tr("Abuse or harassment")
        case .inappropriate: tr("Inappropriate")
        case .impersonation: tr("Impersonation")
        case .other: tr("Something else")
        }
    }
}

/// People you blocked, with a way to unblock them. Reached from the profile sheet.
struct BlockedSheet: View {
    let safety: SafetyViewModel
    let back: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button(action: back) {
                        Label("Back", systemImage: "chevron.backward").font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                }
                Text("Blocked people").font(.system(.title2, design: .rounded, weight: .bold))
                SafetyNotice(safety: safety)
                if safety.isLoading && safety.blocked.isEmpty {
                    ProgressView().tint(Brand.foreground).frame(maxWidth: .infinity)
                } else if safety.blocked.isEmpty {
                    Text("You haven't blocked anyone.").font(.callout).foregroundStyle(Brand.foreground.opacity(0.6))
                }
                ForEach(safety.blocked) { user in
                    HStack(spacing: 12) {
                        AvatarImage(avatar: user.avatar, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: user.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if let username = user.username, username != user.name {
                                Text(verbatim: "@\(username)").font(.footnote).foregroundStyle(Brand.foreground.opacity(0.6))
                            }
                        }
                        Spacer(minLength: 8)
                        Button { Task { await safety.unblock(user) } } label: {
                            Text("Unblock")
                                .font(.footnote.weight(.bold))
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .background(Brand.foreground.opacity(0.12), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Brand.surface, in: .rect(cornerRadius: 14))
                }
            }
            .padding(20)
        }
        .task { await safety.loadBlocked() }
    }
}
