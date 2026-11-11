import Foundation
import Observation

@MainActor
@Observable
final class CharacterViewModel {
    private(set) var styles: [CharacterStyle] = []
    /// One example character per style, for the style picker.
    private(set) var styleSamples: [String: Avatar] = [:]
    private(set) var groups: [OptionGroup] = []
    private(set) var avatar: Avatar?
    private(set) var gender: CharacterGender
    private(set) var isLoading = true
    private(set) var isSaving = false
    private(set) var errorText: String?
    /// `CharacterViewModel.stylePage`, or the name of the part whose page is showing.
    private(set) var step: String = CharacterViewModel.stylePage

    static let stylePage = "style"

    private let session: SessionStore
    private let renderer: any AvatarRendering

    init(
        session: SessionStore,
        renderer: any AvatarRendering,
        existing: Avatar? = nil,
        gender: CharacterGender = Bool.random() ? .male : .female
    ) {
        self.session = session
        self.renderer = renderer
        self.avatar = existing
        self.gender = gender
    }

    var currentStyle: CharacterStyle? {
        styles.first { $0.id == avatar?.style }
    }

    /// The options shown on the current page. Only these get thumbnails, which keeps each tap cheap.
    var groupsOnStep: [OptionGroup] {
        groups.filter { $0.page == step }
    }

    /// The style page, then one page per part the current style has, in order.
    var steps: [String] {
        var pages = [Self.stylePage]
        for group in groups where !pages.contains(group.page) { pages.append(group.page) }
        return pages
    }

    var isLastStep: Bool { step == steps.last }

    func go(to newStep: String) {
        guard steps.contains(newStep) else { return }
        step = newStep
    }

    func next() {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return }
        step = steps[index + 1]
    }

    func back() {
        guard let index = steps.firstIndex(of: step), index > 0 else { return }
        step = steps[index - 1]
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            styles = try await renderer.styles()
            guard let first = styles.first else { return }
            if let avatar {
                self.avatar = try await renderer.normalise(avatar, gender: gender)
            } else {
                avatar = try await renderer.random(style: first.id, gender: gender)
            }
            groups = try await renderer.groups(style: avatar?.style ?? first.id, gender: gender)
            await loadSamples()
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }

    func selectStyle(_ id: String) async {
        guard id != avatar?.style else { return }
        defer { if !steps.contains(step) { step = Self.stylePage } }
        await apply { [gender] renderer in
            let avatar = try await renderer.random(style: id, gender: gender)
            return (avatar, try await renderer.groups(style: id, gender: gender))
        }
    }

    func selectGender(_ newValue: CharacterGender) async {
        guard newValue != gender, let current = avatar else { return }
        defer { if !steps.contains(step) { step = Self.stylePage } }
        gender = newValue
        await apply { renderer in
            let avatar = try await renderer.normalise(current, gender: newValue)
            return (avatar, try await renderer.groups(style: current.style, gender: newValue))
        }
        await loadSamples()
    }

    func randomize() async {
        guard let style = avatar?.style else { return }
        await apply { [gender] renderer in
            (try await renderer.random(style: style, gender: gender), try await renderer.groups(style: style, gender: gender))
        }
    }

    func set(_ group: String, to value: String) {
        avatar?.options[group] = value
    }

    func isSelected(_ group: String, _ value: String) -> Bool {
        avatar?.options[group] == value
    }

    /// The current character with one option changed, for the option thumbnails.
    func preview(_ group: String, _ value: String) -> Avatar? {
        guard var copy = avatar else { return nil }
        copy.options[group] = value
        return copy
    }

    func save() async {
        guard let avatar, !isSaving else { return }
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        do {
            session.characterChosen(try await session.api.updateAvatar(avatar))
        } catch AuthError.sessionExpired {
            session.sessionExpired()
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }

    private func apply(_ change: (any AvatarRendering) async throws -> (Avatar, [OptionGroup])) async {
        do {
            let (newAvatar, newGroups) = try await change(renderer)
            avatar = newAvatar
            groups = newGroups
            errorText = nil
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }

    private func loadSamples() async {
        for style in styles {
            if let sample = try? await renderer.random(style: style.id, gender: gender) {
                styleSamples[style.id] = sample
            }
        }
    }
}
