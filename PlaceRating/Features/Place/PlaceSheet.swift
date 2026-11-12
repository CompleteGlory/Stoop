import SwiftUI

/// A place: who it is, how it's rated (average, star breakdown, friends' average), your own rating
/// (stars save on tap, the comment when you finish), photos, then reviews with friends first.
struct PlaceSheet: View {
    let model: PlaceViewModel
    let close: () -> Void
    @FocusState private var commentFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                SafetyNotice(safety: model.safety)
                if model.place == nil, !model.isLoading, let error = model.errorText {
                    retry(error) { Task { await model.load() } }
                } else {
                    summaryCard
                    yourRatingCard
                    if let photos = model.photos { PlacePhotosSection(model: photos) }
                    reviews
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

    // MARK: header

    private var header: some View {
        let symbol = PlaceCategory.symbol(for: model.category)
        return HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(symbol.color.gradient)
                Image(systemName: symbol.name).font(.title2.weight(.semibold)).foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)
            .shadow(color: symbol.color.opacity(0.35), radius: 8, y: 4)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: model.name.isEmpty ? " " : model.name)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .lineLimit(2)
                    .redacted(reason: model.name.isEmpty ? .placeholder : [])
                if let category = PlaceCategory.name(for: model.category) {
                    Text(verbatim: category).font(.subheadline).foregroundStyle(Brand.foreground.opacity(0.6))
                }
            }
            Spacer(minLength: 8)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .frame(width: 32, height: 32)
                    .background(Brand.surface, in: .circle)
            }
            .accessibilityLabel(Text("Close"))
        }
    }

    // MARK: summary

    private var summaryCard: some View {
        Card {
            if let place = model.place, place.ratingCount > 0 {
                HStack(alignment: .center, spacing: 18) {
                    VStack(spacing: 4) {
                        Text(place.avgRating, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        StarRow(value: place.avgRating, size: 13)
                        Text("\(place.ratingCount) ratings")
                            .font(.caption).foregroundStyle(Brand.foreground.opacity(0.6))
                    }
                    .frame(minWidth: 92)
                    StarBreakdown(counts: model.starCounts)
                }
                if let friends = model.friendsAverage {
                    Divider().overlay(Brand.foreground.opacity(0.1))
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill").foregroundStyle(Brand.accent)
                        Text("Friends' average").font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(Brand.accent)
                        Text(friends, format: .number.precision(.fractionLength(1))).font(.subheadline.weight(.bold))
                    }
                }
                if model.starCountsArePartial {
                    Text("The bars show the latest ratings.").font(.caption2).foregroundStyle(Brand.foreground.opacity(0.5))
                }
            } else if model.isLoading {
                HStack(spacing: 10) {
                    ProgressView().tint(Brand.foreground)
                    Text("Loading ratings…").font(.subheadline).foregroundStyle(Brand.foreground.opacity(0.7))
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "star.bubble").font(.title).foregroundStyle(Brand.accent)
                    Text("No ratings yet. Be the first.").font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: your rating

    private var yourRatingCard: some View {
        Card {
            HStack {
                Text("Your rating").font(.subheadline.weight(.semibold))
                Spacer()
                saveStatus
            }
            StarPicker(stars: model.stars) { model.setStars($0) }
                .frame(maxWidth: .infinity)
                .disabled(model.placeId == nil)
            Text(PlaceCategory.feeling(for: model.stars))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(model.stars > 0 ? Brand.accent : Brand.foreground.opacity(0.55))
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)
                .animation(.snappy, value: model.stars)

            VStack(alignment: .trailing, spacing: 4) {
                // a vertical field grows with the text, but Return should finish (and save), not add a line
                TextField(text: Binding(
                    get: { model.comment },
                    set: { text in
                        if text.contains("\n") {
                            model.comment = text.replacingOccurrences(of: "\n", with: "")
                            commentFocused = false
                        } else {
                            model.comment = String(text.prefix(PlaceViewModel.maxComment))
                        }
                    }
                ), axis: .vertical) {
                    Text(model.stars == 0 ? "Rate it first, then add a comment" : "What stood out? (optional)")
                        .foregroundStyle(Brand.foreground.opacity(0.4))
                }
                .lineLimit(1...5)
                .focused($commentFocused)
                .submitLabel(.done)
                .onSubmit { commentFocused = false }
                .disabled(model.stars == 0)
                .padding(12)
                .background(Brand.background.opacity(0.6), in: .rect(cornerRadius: 12))
                if commentFocused || !model.comment.isEmpty {
                    Text(verbatim: "\(model.comment.count)/\(PlaceViewModel.maxComment)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Brand.foreground.opacity(0.45))
                }
            }

            if model.stars > 0 && !model.isSaving {
                Button("Remove my rating", role: .destructive) { Task { await model.removeRating() } }
                    .font(.footnote)
                    .foregroundStyle(Brand.foreground.opacity(0.55))
            }
        }
        .sensoryFeedback(.selection, trigger: model.stars)
    }

    @ViewBuilder
    private var saveStatus: some View {
        if model.isSaving {
            HStack(spacing: 6) {
                ProgressView().tint(Brand.foreground).controlSize(.mini)
                Text("Saving…").font(.caption)
            }
        } else if model.saveFailed {
            Button { Task { await model.save() } } label: {
                Label("Try again", systemImage: "arrow.clockwise").font(.caption.weight(.bold))
            }
            .foregroundStyle(Brand.negative.text)
        } else if model.savedRecently {
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Brand.positive.text)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    // MARK: reviews

    @ViewBuilder
    private var reviews: some View {
        if !model.friendRatings.isEmpty || !model.otherRatings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Reviews").font(.headline)
                ForEach(model.friendRatings) { RatingRow(rating: $0, isFriend: true, safety: model.safety) }
                ForEach(model.otherRatings) { RatingRow(rating: $0, isFriend: false, safety: model.safety) }
                if model.hasMoreRatings {
                    Button { Task { await model.loadMoreRatings() } } label: {
                        Text("Show more").font(.footnote.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .foregroundStyle(Brand.accent)
                }
            }
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

// MARK: building blocks

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.surface, in: .rect(cornerRadius: 18))
    }
}

/// Five small stars filled to a fractional value (4.3 fills four and a third).
struct StarRow: View {
    let value: Double
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                let fill = min(max(value - Double(index - 1), 0), 1)
                ZStack(alignment: .leading) {
                    Image(systemName: "star.fill").foregroundStyle(Brand.foreground.opacity(0.2))
                    Image(systemName: "star.fill").foregroundStyle(Brand.accent)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: size * fill)
                        }
                }
                .font(.system(size: size))
                .frame(width: size, height: size)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel(Text(value, format: .number.precision(.fractionLength(1))))
    }
}

/// Bars for 5 down to 1 star, as a share of the ratings counted.
private struct StarBreakdown: View {
    let counts: [Int]

    var body: some View {
        let total = max(counts.reduce(0, +), 1)
        VStack(spacing: 5) {
            ForEach((1...5).reversed(), id: \.self) { stars in
                HStack(spacing: 6) {
                    Text(stars, format: .number).font(.caption2.monospacedDigit().weight(.semibold))
                        .frame(width: 10)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Brand.foreground.opacity(0.12))
                            Capsule().fill(Brand.accent)
                                .frame(width: geo.size.width * CGFloat(counts[stars - 1]) / CGFloat(total))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .animation(.snappy, value: counts)
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
                Text(place.avgRating, format: .number.precision(.fractionLength(1))).font(.headline)
                Text("\(place.ratingCount) ratings").font(.subheadline).foregroundStyle(Brand.foreground.opacity(0.6))
            }
        }
    }
}

/// Five big stars; tapping one sets the rating. They fill left to right in every language.
struct StarPicker: View {
    let stars: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach(1...5, id: \.self) { value in
                Button { onChange(value) } label: {
                    Image(systemName: value <= stars ? "star.fill" : "star")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(value <= stars ? Brand.accent : Brand.foreground.opacity(0.3))
                        .scaleEffect(value == stars ? 1.15 : 1)
                        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: stars)
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
    let isFriend: Bool
    let safety: SafetyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AvatarImage(avatar: rating.user.avatar, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: rating.user.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if isFriend {
                            Text("Friend")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Brand.ink)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Brand.accent, in: .capsule)
                        }
                    }
                    HStack(spacing: 6) {
                        StarRow(value: Double(rating.stars), size: 11)
                        Text(rating.updatedAt, format: .relative(presentation: .named))
                            .font(.caption).foregroundStyle(Brand.foreground.opacity(0.5))
                    }
                }
                Spacer(minLength: 4)
                SafetyMenu(
                    safety: safety, user: rating.user,
                    content: .init(target: .rating, id: rating.id, title: tr("Report rating"))
                )
            }
            if let comment = rating.comment, !comment.isEmpty {
                Text(verbatim: comment).font(.callout).foregroundStyle(Brand.foreground.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Brand.surface, in: .rect(cornerRadius: 16))
    }
}
