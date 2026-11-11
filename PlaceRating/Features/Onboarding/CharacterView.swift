import SwiftUI

/// Make a DiceBear character: pick a style, then every part, with a live preview of the map marker.
struct CharacterView: View {
    let user: SelfUser
    @State private var model: CharacterViewModel

    init(session: SessionStore, user: SelfUser, renderer: (any AvatarRendering)? = nil) {
        self.user = user
        _model = State(initialValue: CharacterViewModel(
            session: session,
            renderer: renderer ?? DiceBearRenderer.shared,
            existing: user.avatar
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            stepTabs
            page
            footer
        }
        .background(Brand.background)
        .task { await model.load() }
        .animation(.snappy(duration: 0.2), value: model.step)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("Make your character")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Brand.foreground)
            ZStack {
                Brand.surface
                StreetPattern(color: Brand.street)
                if model.isLoading {
                    ProgressView().tint(Brand.foreground)
                } else {
                    MapMarker(avatar: model.avatar, name: user.username ?? "", size: 96)
                }
            }
            .frame(height: 160)
            .clipShape(.rect(cornerRadius: 20))
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// One tab per page, scrolled so the current one is visible; people can jump to any part.
    private var stepTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(model.steps, id: \.self) { step in
                        Button {
                            model.go(to: step)
                        } label: {
                            Text(Self.title(of: step))
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 34)
                                .foregroundStyle(model.step == step ? Brand.background : Brand.foreground.opacity(0.75))
                                .background(model.step == step ? Brand.foreground : Brand.surface, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .id(step)
                        .accessibilityAddTraits(model.step == step ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .padding(.vertical, 12)
            .onChange(of: model.step) { withAnimation { proxy.scrollTo(model.step, anchor: .center) } }
        }
    }

    /// Only the current page is built, so only its thumbnails are drawn.
    @ViewBuilder
    private var page: some View {
        ScrollView {
            if model.step == CharacterViewModel.stylePage {
                stylePage
            } else {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(model.groupsOnStep) { group in
                        OptionRow(group: group, model: model)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .scrollIndicators(.hidden)
        .id(model.step)
        .transition(.opacity)
    }

    private var stylePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(selection: Binding(
                get: { model.gender },
                set: { value in Task { await model.selectGender(value) } }
            )) {
                Text("Male").tag(CharacterGender.male)
                Text("Female").tag(CharacterGender.female)
            } label: {
                Text("Hairstyles")
            }
            .pickerStyle(.segmented)
            .colorScheme(.dark)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 14) {
                ForEach(model.styles) { style in
                    Button {
                        Task { await model.selectStyle(style.id) }
                    } label: {
                        VStack(spacing: 6) {
                            AvatarImage(avatar: model.styleSamples[style.id], size: 72)
                                .overlay(SelectionRing(isOn: model.avatar?.style == style.id))
                            Text(verbatim: style.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Brand.foreground.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: style.title))
                    .accessibilityAddTraits(model.avatar?.style == style.id ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let error = model.errorText {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Brand.negative.text)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                if model.step != model.steps.first {
                    SquareButton(systemImage: "chevron.backward", label: String(localized: "Back")) { model.back() }
                }
                SquareButton(systemImage: "dice", label: String(localized: "Surprise me")) {
                    Task { await model.randomize() }
                }
                .accessibilityIdentifier("randomize")

                if model.isLastStep {
                    Button {
                        Task { await model.save() }
                    } label: {
                        if model.isSaving { ProgressView().tint(Brand.background) } else { Text("Continue") }
                    }
                    .buttonStyle(BrandButtonStyle())
                    .disabled(model.avatar == nil || model.isLoading)
                    .accessibilityIdentifier("continue")
                } else {
                    Button("Next") { model.next() }
                        .buttonStyle(BrandButtonStyle())
                        .disabled(model.avatar == nil || model.isLoading)
                        .accessibilityIdentifier("next")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Brand.background)
    }

    static func title(of step: String) -> String {
        step == CharacterViewModel.stylePage ? String(localized: "Style") : OptionNames.title(for: step)
    }
}

private struct SquareButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 52, height: 52)
                .background(Brand.surface, in: .rect(cornerRadius: 14))
                .foregroundStyle(Brand.foreground)
        }
        .accessibilityLabel(Text(label))
    }
}

/// One part of the character: thumbnails of the character wearing each choice, or color swatches.
private struct OptionRow: View {
    let group: OptionGroup
    let model: CharacterViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: OptionNames.title(for: group.name))
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(group.values, id: \.self) { value in
                        Button {
                            model.set(group.name, to: value)
                        } label: {
                            label(for: value)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: "\(OptionNames.title(for: group.name)) \(value)"))
                        .accessibilityAddTraits(model.isSelected(group.name, value) ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 3)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func label(for value: String) -> some View {
        let isOn = model.isSelected(group.name, value)
        switch group.kind {
        case .color:
            Circle()
                .fill(Color(hexString: value))
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(Brand.foreground.opacity(0.25), lineWidth: 1))
                .overlay(SelectionRing(isOn: isOn, inset: -4))
        case .choice:
            AvatarImage(avatar: model.preview(group.name, value), size: 60)
                .overlay {
                    if value == "none" {
                        Image(systemName: "nosign").font(.caption.weight(.bold)).foregroundStyle(Brand.background.opacity(0.5))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(4)
                    }
                }
                .overlay(SelectionRing(isOn: isOn))
        }
    }
}

private struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Brand.foreground.opacity(0.75))
            .padding(.horizontal, 20)
    }
}

private struct SelectionRing: View {
    let isOn: Bool
    var inset: CGFloat = -3

    var body: some View {
        Circle()
            .inset(by: inset)
            .stroke(Brand.accent, lineWidth: isOn ? 3 : 0)
            .animation(.snappy(duration: 0.15), value: isOn)
    }
}

/// Readable, translated names for DiceBear's option groups.
enum OptionNames {
    static func title(for name: String) -> String {
        switch name {
        case "top", "hair", "head": String(localized: "Hair")
        case "hairColor": String(localized: "Hair color")
        case "skinColor", "baseColor": String(localized: "Skin")
        case "eyes": String(localized: "Eyes")
        case "eyesColor": String(localized: "Eye color")
        case "eyebrows", "brows": String(localized: "Eyebrows")
        case "eyebrowsColor": String(localized: "Eyebrow color")
        case "mouth", "lips", "face": String(localized: "Mouth")
        case "nose": String(localized: "Nose")
        case "facialHair", "beard": String(localized: "Facial hair")
        case "facialHairColor": String(localized: "Facial hair color")
        case "clothing", "clothes", "body", "shirt": String(localized: "Outfit")
        case "clothesColor", "clothingColor", "shirtColor": String(localized: "Outfit color")
        case "accessories": String(localized: "Accessories")
        case "accessoriesColor": String(localized: "Accessory color")
        case "glasses": String(localized: "Glasses")
        case "glassesColor": String(localized: "Glasses color")
        case "earrings", "ears": String(localized: "Earrings")
        case "earringsColor", "earringColor": String(localized: "Earring color")
        case "features", "freckles": String(localized: "Details")
        case "hatColor": String(localized: "Hat color")
        default:
            name.replacing(/([a-z])([A-Z0-9])/) { "\($0.output.1) \($0.output.2)" }.capitalized
        }
    }
}

extension Color {
    /// A 6-digit hex string such as "2c1b18".
    init(hexString: String) {
        self.init(hex: UInt32(hexString, radix: 16) ?? 0)
    }
}
