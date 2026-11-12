import Foundation
import SwiftUI
import Observation

/// What the sheet can show before our server knows the place: Apple Maps already gave us these.
struct PlacePreview: Equatable, Sendable {
    let name: String
    let category: String?
}

/// One place's sheet: its average, your stars and comment, and everyone's ratings with friends first.
/// It can open before the place is resolved on the server: it shows the preview at once and
/// resolves while you look at it.
@MainActor
@Observable
final class PlaceViewModel {
    /// nil until the place is resolved on the server.
    private(set) var placeId: String?
    let preview: PlacePreview?
    private(set) var place: Place?
    private(set) var stars = 0
    var comment = ""
    private var loadedFriendRatings: [PlaceRating] = []
    private var loadedOtherRatings: [PlaceRating] = []
    /// Friends' ratings and everyone else's, without anything from people you blocked.
    var friendRatings: [PlaceRating] { loadedFriendRatings.filter { !safety.isBlocked($0.user.id) } }
    var otherRatings: [PlaceRating] { loadedOtherRatings.filter { !safety.isBlocked($0.user.id) } }
    private(set) var hasMoreRatings = false
    private(set) var isLoading = true
    private(set) var isSaving = false
    private(set) var errorText: String?
    /// The last save failed: show a retry instead of queueing it (offline never queues writes).
    private(set) var saveFailed = false
    /// Photos need the place's id, so they appear once it is known.
    private(set) var photos: PlacePhotosViewModel?
    let safety: SafetyViewModel

    /// Shown for a moment after a save goes through.
    private(set) var savedRecently = false

    var name: String { place?.name ?? preview?.name ?? "" }

    /// How many of the loaded ratings gave 1, 2, 3, 4 and 5 stars (your own included).
    var starCounts: [Int] {
        var counts = Array(repeating: 0, count: 5)
        for rating in friendRatings + otherRatings where (1...5).contains(rating.stars) { counts[rating.stars - 1] += 1 }
        if (1...5).contains(savedStars) { counts[savedStars - 1] += 1 }
        return counts
    }

    /// The breakdown only covers the ratings loaded so far.
    var starCountsArePartial: Bool { hasMoreRatings }

    /// The average of your friends' ratings here, if any of them rated it.
    var friendsAverage: Double? {
        let stars = friendRatings.map(\.stars)
        guard !stars.isEmpty else { return nil }
        return Double(stars.reduce(0, +)) / Double(stars.count)
    }
    var category: String? { place?.category ?? preview?.category }

    private let api: any PlacesAPI
    private let photosAPI: any PhotosAPI
    private let resolver: (() async throws -> Place)?
    private let myId: String
    private let debounce: Duration
    private let onPlaceChanged: (Place) -> Void
    private var savedComment = ""
    private var savedStars = 0
    private var friendIds: Set<String> = []
    private var cursor: String?
    private var pendingSave: Task<Void, Never>?
    private var savedFlash: Task<Void, Never>?

    static let maxComment = 280

    init(
        placeId: String,
        api: any PlacesAPI,
        myId: String,
        photosAPI: any PhotosAPI = UnavailablePhotosAPI(),
        safety: SafetyViewModel = SafetyViewModel(api: UnavailableModerationAPI()),
        debounce: Duration = .milliseconds(600),
        onPlaceChanged: @escaping (Place) -> Void = { _ in }
    ) {
        self.safety = safety
        self.placeId = placeId
        preview = nil
        resolver = nil
        self.api = api
        self.photosAPI = photosAPI
        self.myId = myId
        self.debounce = debounce
        self.onPlaceChanged = onPlaceChanged
        photos = PlacePhotosViewModel(placeId: placeId, api: photosAPI, myId: myId, safety: safety)
    }

    /// Opens at once with what Apple Maps knows; `resolve` finds or creates the place on the server.
    init(
        preview: PlacePreview,
        resolve: @escaping () async throws -> Place,
        api: any PlacesAPI,
        myId: String,
        photosAPI: any PhotosAPI = UnavailablePhotosAPI(),
        safety: SafetyViewModel = SafetyViewModel(api: UnavailableModerationAPI()),
        debounce: Duration = .milliseconds(600),
        onPlaceChanged: @escaping (Place) -> Void = { _ in }
    ) {
        self.safety = safety
        placeId = nil
        self.preview = preview
        resolver = resolve
        self.api = api
        self.photosAPI = photosAPI
        self.myId = myId
        self.debounce = debounce
        self.onPlaceChanged = onPlaceChanged
    }

    func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            if placeId == nil, let resolver {
                let resolved = try await resolver()
                placeId = resolved.id
                place = resolved
                photos = PlacePhotosViewModel(placeId: resolved.id, api: photosAPI, myId: myId, safety: safety)
            }
            guard let placeId else { return }
            async let detail = api.place(id: placeId)
            async let page = api.ratings(placeId: placeId, cursor: nil)
            async let friends = api.friends()
            let (d, p) = try await (detail, page)
            place = d.place
            stars = d.myRating?.stars ?? 0
            comment = d.myRating?.comment ?? ""
            savedStars = stars
            savedComment = comment
            friendIds = Set(((try? await friends)?.friends ?? []).map(\.user.id))
            ratingsLoaded(p, replacing: true)
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }

    func loadMoreRatings() async {
        guard let cursor, let placeId else { return }
        if let page = try? await api.ratings(placeId: placeId, cursor: cursor) {
            ratingsLoaded(page, replacing: false)
        }
    }

    /// Tapping a star saves it; a few quick taps become one save.
    func setStars(_ value: Int) {
        guard (1...5).contains(value) else { return }
        stars = value
        pendingSave?.cancel()
        pendingSave = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self.save()
        }
    }

    /// The comment saves when its field loses focus.
    func commentEditingEnded() async {
        let trimmed = String(comment.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxComment))
        comment = trimmed
        guard stars > 0, trimmed != savedComment else { return }
        await save()
    }

    /// Waits for a star save that is still pending. Used by tests.
    func waitForSave() async {
        await pendingSave?.value
    }

    func save() async {
        guard stars > 0, let placeId else { return }
        isSaving = true
        saveFailed = false
        errorText = nil
        defer { isSaving = false }
        let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let result = try await api.rate(placeId: placeId, stars: stars, comment: text.isEmpty ? nil : text)
            savedStars = result.rating.stars
            savedComment = result.rating.comment ?? ""
            place = result.place
            onPlaceChanged(result.place)
            savedRecently = true
            savedFlash?.cancel()
            savedFlash = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                savedRecently = false
            }
        } catch {
            saveFailed = true
            errorText = ErrorText.text(for: error)
        }
    }

    func removeRating() async {
        pendingSave?.cancel()
        guard let placeId else { return }
        do {
            try await api.deleteRating(placeId: placeId)
            stars = 0
            comment = ""
            savedStars = 0
            savedComment = ""
            let refreshed = try await api.place(id: placeId)
            place = refreshed.place
            onPlaceChanged(refreshed.place)
        } catch {
            errorText = ErrorText.text(for: error)
        }
    }

    private func ratingsLoaded(_ page: RatingPage, replacing: Bool) {
        // your own rating is the star control, not a row in the list
        let others = page.items.filter { $0.user.id != myId }
        let friends = others.filter { friendIds.contains($0.user.id) }
        let rest = others.filter { !friendIds.contains($0.user.id) }
        if replacing {
            loadedFriendRatings = friends
            loadedOtherRatings = rest
        } else {
            loadedFriendRatings += friends
            loadedOtherRatings += rest
        }
        cursor = page.nextCursor
        hasMoreRatings = page.nextCursor != nil
    }
}

/// Readable, translated names for the category codes Apple Maps gives places (`MKPOICategoryCafe`).
enum PlaceCategory {
    static func name(for code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        switch code {
        case "MKPOICategoryCafe": return tr("Café")
        case "MKPOICategoryRestaurant": return tr("Restaurant")
        case "MKPOICategoryBakery": return tr("Bakery")
        case "MKPOICategoryBrewery", "MKPOICategoryWinery", "MKPOICategoryNightlife": return tr("Bar")
        case "MKPOICategoryFoodMarket", "MKPOICategoryStore": return tr("Shop")
        case "MKPOICategoryMuseum": return tr("Museum")
        case "MKPOICategoryPark", "MKPOICategoryNationalPark": return tr("Park")
        case "MKPOICategoryBeach": return tr("Beach")
        case "MKPOICategoryHotel": return tr("Hotel")
        case "MKPOICategoryMovieTheater", "MKPOICategoryTheater": return tr("Theater")
        case "MKPOICategoryFitnessCenter": return tr("Gym")
        case "MKPOICategoryLibrary": return tr("Library")
        case "MKPOICategoryPharmacy": return tr("Pharmacy")
        case "MKPOICategoryHospital": return tr("Hospital")
        case "MKPOICategoryUniversity", "MKPOICategorySchool": return tr("School")
        case "MKPOICategoryAmusementPark", "MKPOICategoryZoo", "MKPOICategoryAquarium": return tr("Attraction")
        case "MKPOICategoryLandmark": return tr("Landmark")
        default:
            // anything else: "MKPOICategoryGasStation" → "Gas Station"
            let bare = code.replacingOccurrences(of: "MKPOICategory", with: "")
            return bare.replacing(/([a-z])([A-Z])/) { "\($0.output.1) \($0.output.2)" }
        }
    }
}

extension PlaceCategory {
    /// An SF Symbol and a colour for the place sheet's header.
    static func symbol(for code: String?) -> (name: String, color: Color) {
        switch code ?? "" {
        case "MKPOICategoryCafe": ("cup.and.saucer.fill", Color(hex: 0xC27C2C))
        case "MKPOICategoryRestaurant", "MKPOICategoryFoodMarket": ("fork.knife", Color(hex: 0xE0702E))
        case "MKPOICategoryBakery": ("birthday.cake.fill", Color(hex: 0xD9905A))
        case "MKPOICategoryBrewery", "MKPOICategoryWinery", "MKPOICategoryNightlife": ("wineglass.fill", Color(hex: 0x9B4D8F))
        case "MKPOICategoryStore": ("bag.fill", Color(hex: 0xE3A72F))
        case "MKPOICategoryMuseum", "MKPOICategoryLandmark": ("building.columns.fill", Color(hex: 0xC2557A))
        case "MKPOICategoryPark", "MKPOICategoryNationalPark": ("tree.fill", Color(hex: 0x3E9B5A))
        case "MKPOICategoryBeach", "MKPOICategoryMarina": ("beach.umbrella.fill", Color(hex: 0x2E9CC9))
        case "MKPOICategoryHotel": ("bed.double.fill", Color(hex: 0x7A5BD0))
        case "MKPOICategoryMovieTheater", "MKPOICategoryTheater": ("theatermasks.fill", Color(hex: 0xD04F8C))
        case "MKPOICategoryFitnessCenter": ("dumbbell.fill", Color(hex: 0x3F7FD6))
        case "MKPOICategoryLibrary", "MKPOICategoryUniversity", "MKPOICategorySchool": ("books.vertical.fill", Color(hex: 0x6B6FD0))
        case "MKPOICategoryPharmacy", "MKPOICategoryHospital": ("cross.case.fill", Color(hex: 0xD9465C))
        case "MKPOICategoryAmusementPark", "MKPOICategoryZoo", "MKPOICategoryAquarium": ("sparkles", Color(hex: 0xE09A2B))
        default: ("mappin", Color(hex: 0xBF8200))
        }
    }

    /// Words for each star, under the picker.
    static func feeling(for stars: Int) -> String {
        switch stars {
        case 1: tr("Not for me")
        case 2: tr("Could be better")
        case 3: tr("Good")
        case 4: tr("Great")
        case 5: tr("Loved it")
        default: tr("Tap a star to rate")
        }
    }
}
