import SwiftUI

/// A selected place: average, your stars (saved on tap) and comment (saved when you finish),
/// then friends' ratings first and everyone else's after.
struct PlaceSheet: View {
    let model: PlaceViewModel
    let close: () -> Void
    @FocusState private var commentFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                SafetyNotice(safety: model.safety)
                if model.isLoading && model.place == nil {
                    ProgressView().tint(Brand.foreground).frame(maxWidth: .infinity)
                } else if model.place == nil, let error = model.errorText {
                    retry(error) { Task { await model.load() } }
                } else {
                    yourRating
                    PlacePhotosSection(model: model.photos)
                    ratingsList
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await model.load() }
        .onChange(of: commentFocused) { _, focused in
            if !focused { Task { await model.commentEditingEnded() } }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: model.place?.name ?? "")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                if let category = PlaceCategory.name(for: model.place?.category) {
                    Text(verbatim: category).foregroundStyle(Brand.foreground.opacity(0.6))
                }
                if let place = model.place {
                    AverageLine(place: place).padding(.top, 2)
                }
            }
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

    private var yourRating: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your rating").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.foreground.opacity(0.7))
            StarPicker(stars: model.stars) { model.setStars($0) }
            // a vertical field grows with the text, but Return should finish (and save), not add a line
            TextField(text: Binding(
                get: { model.comment },
                set: { text in
                    if text.contains("\n") {
                        model.comment = text.replacingOccurrences(of: "\n", with: "")
                        commentFocused = false
                    } else {
                        model.comment = text
                    }
                }
            ), axis: .vertical) {
                Text("Add a comment (optional)").foregroundStyle(Brand.foreground.opacity(0.4))
            }
            .lineLimit(1...4)
            .focused($commentFocused)
            .submitLabel(.done)
            .onSubmit { commentFocused = false }
            .disabled(model.stars == 0)
            .padding(12)
            .background(Brand.surface, in: .rect(cornerRadius: 12))
            HStack {
                if model.isSaving {
                    ProgressView().tint(Brand.foreground).controlSize(.small)
                    Text("Saving…").font(.footnote)
                } else if model.saveFailed {
                    Text(model.errorText ?? "").font(.footnote).foregroundStyle(Brand.negative.text)
                    Button("Try again") { Task { await model.save() } }
                        .font(.footnote.weight(.bold)).foregroundStyle(Brand.accent)
                }
                Spacer()
                if model.stars > 0 && !model.isSaving {
                    Button("Remove my rating") { Task { await model.removeRating() } }
                        .font(.footnote).foregroundStyle(Brand.foreground.opacity(0.6))
                }
            }
            .frame(minHeight: 20)
        }
    }

    @ViewBuilder
    private var ratingsList: some View {
        if !model.friendRatings.isEmpty {
            Section(title: tr("Friends")) {
                ForEach(model.friendRatings) { RatingRow(rating: $0, safety: model.safety) }
            }
        }
        if !model.otherRatings.isEmpty {
            Section(title: tr("Everyone")) {
                ForEach(model.otherRatings) { RatingRow(rating: $0, safety: model.safety) }
                if model.hasMoreRatings {
                    Button("Show more") { Task { await model.loadMoreRatings() } }
                        .font(.footnote.weight(.semibold)).foregroundStyle(Brand.accent)
                }
            }
        }
        if model.friendRatings.isEmpty && model.otherRatings.isEmpty && !model.isLoading {
            Text("No ratings yet. Be the first.").foregroundStyle(Brand.foreground.opacity(0.6))
        }
    }

    private func retry(_ message: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Text(message).foregroundStyle(Brand.foreground.opacity(0.75)).multilineTextAlignment(.center)
            Button("Try again", action: action).buttonStyle(BrandButtonStyle())
        }
        .frame(maxWidth: .infinity)
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

/// "★ 4.5 · 12 ratings", or a note when nobody rated it yet.
struct AverageLine: View {
    let place: Place

    var body: some View {
        if place.ratingCount == 0 {
            Text("No ratings yet").font(.subheadline).foregroundStyle(Brand.foreground.opacity(0.6))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "star.fill").foregroundStyle(Brand.accent)
                Text(place.avgRating, format: .number.precision(.fractionLength(1)))
                    .font(.headline)
                Text("\(place.ratingCount) ratings")
                    .font(.subheadline).foregroundStyle(Brand.foreground.opacity(0.6))
            }
        }
    }
}

/// Five stars; tapping one sets the rating. Stars always fill left to right, also in Arabic.
struct StarPicker: View {
    let stars: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { value in
                Button { onChange(value) } label: {
                    Image(systemName: value <= stars ? "star.fill" : "star")
                        .font(.system(size: 32))
                        .foregroundStyle(value <= stars ? Brand.accent : Brand.foreground.opacity(0.35))
                        .scaleEffect(value == stars ? 1.1 : 1)
                        .animation(.snappy(duration: 0.15), value: stars)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(value) stars"))
                .accessibilityAddTraits(value == stars ? .isSelected : [])
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

private struct RatingRow: View {
    let rating: PlaceRating
    let safety: SafetyViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarImage(avatar: rating.user.avatar, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(verbatim: rating.user.name).font(.subheadline.weight(.semibold))
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { value in
                            Image(systemName: value <= rating.stars ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundStyle(value <= rating.stars ? Brand.accent : Brand.foreground.opacity(0.3))
                        }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    SafetyMenu(
                        safety: safety, user: rating.user,
                        content: .init(target: .rating, id: rating.id, title: tr("Report rating"))
                    )
                    .padding(.trailing, -8)
                }
                if let comment = rating.comment, !comment.isEmpty {
                    Text(verbatim: comment).font(.callout).foregroundStyle(Brand.foreground.opacity(0.85))
                }
                Text(rating.updatedAt, format: .relative(presentation: .named))
                    .font(.caption).foregroundStyle(Brand.foreground.opacity(0.5))
            }
        }
        .padding(12)
        .background(Brand.surface, in: .rect(cornerRadius: 14))
    }
}
