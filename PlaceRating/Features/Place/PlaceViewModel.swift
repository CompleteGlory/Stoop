import Foundation
import Observation

/// One place's sheet: its average, your stars and comment, and everyone's ratings with friends first.
@MainActor
@Observable
final class PlaceViewModel {
    let placeId: String
    private(set) var place: Place?
    private(set) var stars = 0
    var comment = ""
    private(set) var friendRatings: [PlaceRating] = []
    private(set) var otherRatings: [PlaceRating] = []
    private(set) var hasMoreRatings = false
    private(set) var isLoading = true
    private(set) var isSaving = false
    private(set) var errorText: String?
    /// The last save failed: show a retry instead of queueing it (offline never queues writes).
    private(set) var saveFailed = false
    let photos: PlacePhotosViewModel

    private let api: any PlacesAPI
    private let myId: String
    private let debounce: Duration
    private let onPlaceChanged: (Place) -> Void
    private var savedComment = ""
    private var savedStars = 0
    private var friendIds: Set<String> = []
    private var cursor: String?
    private var pendingSave: Task<Void, Never>?

    static let maxComment = 280

    init(
        placeId: String,
        api: any PlacesAPI,
        myId: String,
        photosAPI: any PhotosAPI = UnavailablePhotosAPI(),
        debounce: Duration = .milliseconds(600),
        onPlaceChanged: @escaping (Place) -> Void = { _ in }
    ) {
        photos = PlacePhotosViewModel(placeId: placeId, api: photosAPI, myId: myId)
        self.placeId = placeId
        self.api = api
        self.myId = myId
        self.debounce = debounce
        self.onPlaceChanged = onPlaceChanged
    }

    func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
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
        guard let cursor else { return }
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
        guard stars > 0 else { return }
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
        } catch {
            saveFailed = true
            errorText = ErrorText.text(for: error)
        }
    }

    func removeRating() async {
        pendingSave?.cancel()
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
            friendRatings = friends
            otherRatings = rest
        } else {
            friendRatings += friends
            otherRatings += rest
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
        case "MKPOICategoryCafe": return String(localized: "Café")
        case "MKPOICategoryRestaurant": return String(localized: "Restaurant")
        case "MKPOICategoryBakery": return String(localized: "Bakery")
        case "MKPOICategoryBrewery", "MKPOICategoryWinery", "MKPOICategoryNightlife": return String(localized: "Bar")
        case "MKPOICategoryFoodMarket", "MKPOICategoryStore": return String(localized: "Shop")
        case "MKPOICategoryMuseum": return String(localized: "Museum")
        case "MKPOICategoryPark", "MKPOICategoryNationalPark": return String(localized: "Park")
        case "MKPOICategoryBeach": return String(localized: "Beach")
        case "MKPOICategoryHotel": return String(localized: "Hotel")
        case "MKPOICategoryMovieTheater", "MKPOICategoryTheater": return String(localized: "Theater")
        case "MKPOICategoryFitnessCenter": return String(localized: "Gym")
        case "MKPOICategoryLibrary": return String(localized: "Library")
        case "MKPOICategoryPharmacy": return String(localized: "Pharmacy")
        case "MKPOICategoryHospital": return String(localized: "Hospital")
        case "MKPOICategoryUniversity", "MKPOICategorySchool": return String(localized: "School")
        case "MKPOICategoryAmusementPark", "MKPOICategoryZoo", "MKPOICategoryAquarium": return String(localized: "Attraction")
        case "MKPOICategoryLandmark": return String(localized: "Landmark")
        default:
            // anything else: "MKPOICategoryGasStation" → "Gas Station"
            let bare = code.replacingOccurrences(of: "MKPOICategory", with: "")
            return bare.replacing(/([a-z])([A-Z])/) { "\($0.output.1) \($0.output.2)" }
        }
    }
}
