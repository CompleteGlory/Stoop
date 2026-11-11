import Foundation
import Observation

/// The friends sheet: find people by username, answer requests, manage your friends.
@MainActor
@Observable
final class FriendsViewModel {
    private(set) var friends: [FriendshipEntry] = []
    private(set) var incoming: [FriendshipEntry] = []
    private(set) var outgoing: [FriendshipEntry] = []
    private(set) var results: [UserSearchResult] = []
    private(set) var isLoading = true
    private(set) var isSearching = false
    private(set) var errorText: String?
    /// People with a request or removal in flight, so their buttons can't be pressed twice.
    private(set) var busy: Set<String> = []
    var query = "" {
        didSet { if query != oldValue { queryChanged() } }
    }

    private let api: any FriendsAPI
    private let debounce: Duration
    private let onChange: (FriendsList) -> Void
    private var searchTask: Task<Void, Never>?

    init(api: any FriendsAPI, debounce: Duration = .milliseconds(350), onChange: @escaping (FriendsList) -> Void = { _ in }) {
        self.api = api
        self.debounce = debounce
        self.onChange = onChange
    }

    /// The query the API will accept: 3–20 of a–z, 0–9, `_` and `.`, or nil.
    static func searchTerm(_ text: String) -> String? {
        let term = text.trimmingCharacters(in: .whitespaces).lowercased()
            .trimmingPrefix("@")
        guard (3...20).contains(term.count),
              term.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "." })
        else { return nil }
        return String(term)
    }

    var isSearchActive: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    func load() async {
        errorText = nil
        do {
            apply(try await api.friends())
        } catch {
            errorText = ErrorText.text(for: error)
        }
        isLoading = false
    }

    /// Waits for a pending search. Used by tests.
    func waitForSearch() async {
        await searchTask?.value
    }

    func send(to user: PublicUser) async {
        await act(on: user.id) {
            let outcome = try await self.api.sendFriendRequest(to: user.id)
            self.setStatus(user.id, outcome == .accepted ? .friends : .requestSent)
        }
    }

    func accept(_ entry: FriendshipEntry) async {
        await act(on: entry.user.id) {
            try await self.api.acceptFriendRequest(entry.id)
            self.setStatus(entry.user.id, .friends)
        }
    }

    /// Declining, cancelling and unfriending are the same call.
    func remove(_ user: PublicUser) async {
        await act(on: user.id) {
            try await self.api.removeFriend(user.id)
            self.setStatus(user.id, .none)
        }
    }

    // MARK: private

    private func queryChanged() {
        searchTask?.cancel()
        errorText = nil
        guard let term = Self.searchTerm(query) else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [api, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            do {
                let found = try await api.searchUsers(term)
                guard !Task.isCancelled else { return }
                self.results = found
            } catch {
                guard !Task.isCancelled else { return }
                self.errorText = ErrorText.text(for: error)
            }
            self.isSearching = false
        }
    }

    /// Runs one change, then reloads the lists so every section agrees with the server.
    private func act(on userId: String, _ change: @escaping () async throws -> Void) async {
        guard !busy.contains(userId) else { return }
        busy.insert(userId)
        errorText = nil
        defer { busy.remove(userId) }
        do {
            try await change()
            apply(try await api.friends())
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }

    private func setStatus(_ userId: String, _ status: FriendStatus) {
        if let index = results.firstIndex(where: { $0.id == userId }) {
            results[index].friendStatus = status
        }
    }

    private func apply(_ list: FriendsList) {
        friends = list.friends
        incoming = list.incoming
        outgoing = list.outgoing
        onChange(list)
    }
}
