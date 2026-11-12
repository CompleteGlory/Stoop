import CoreLocation
import Foundation
import Testing
@testable import PlaceRating

private let me = "11111111-1111-1111-1111-111111111111"
private let day = Date(timeIntervalSince1970: 1_800_000_000)

func makePlace(id: String = "p1", avg: Double = 0, count: Int = 0) -> Place {
    Place(id: id, appleId: "I1", name: "Stoop Café", category: "MKPOICategoryCafe",
          latitude: 30.05, longitude: 31.24, avgRating: avg, ratingCount: count)
}

private func person(_ id: String, _ name: String) -> PublicUser {
    PublicUser(id: id, username: name.lowercased(), displayName: name, avatar: nil)
}

private func rating(_ id: String, by user: PublicUser, stars: Int = 4) -> PlaceRating {
    PlaceRating(id: id, stars: stars, comment: nil, createdAt: day, updatedAt: day, user: user)
}

/// Records calls and answers from what each test sets.
final class FakePlacesAPI: PlacesAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _rateBodies: [(Int, String?)] = []
    var detail = PlaceDetail(place: makePlace(), myRating: nil)
    var ratingPages: [String?: RatingPage] = [nil: RatingPage(items: [], nextCursor: nil)]
    var friendsList = FriendsList(friends: [], incoming: [], outgoing: [])
    var nearby: [Place] = []
    var failRate = false

    var calls: [String] { lock.withLock { _calls } }
    var rateBodies: [(Int, String?)] { lock.withLock { _rateBodies } }
    private func log(_ call: String) { lock.withLock { _calls.append(call) } }

    func places(in box: BoundingBox) async throws -> [Place] {
        log("places \(box.queryValue)")
        return nearby
    }

    func resolvePlace(appleId: String?, name: String, category: String?, latitude: Double, longitude: Double) async throws -> Place {
        log("resolve \(appleId ?? "-") \(name)")
        return detail.place
    }

    func place(id: String) async throws -> PlaceDetail {
        log("place \(id)")
        return detail
    }

    func rate(placeId: String, stars: Int, comment: String?) async throws -> RatingResult {
        log("rate \(stars)")
        lock.withLock { _rateBodies.append((stars, comment)) }
        if failRate { throw URLError(.notConnectedToInternet) }
        let place = Place(id: placeId, appleId: nil, name: "Stoop Café", category: nil,
                          latitude: 30.05, longitude: 31.24, avgRating: Double(stars), ratingCount: 1)
        return RatingResult(rating: .init(id: "r", stars: stars, comment: comment, updatedAt: day), place: place)
    }

    func deleteRating(placeId: String) async throws {
        log("delete")
        detail = PlaceDetail(place: makePlace(), myRating: nil)
    }

    func ratings(placeId: String, cursor: String?) async throws -> RatingPage {
        log("ratings \(cursor ?? "-")")
        return ratingPages[cursor] ?? RatingPage(items: [], nextCursor: nil)
    }

    func friends() async throws -> FriendsList {
        log("friends")
        return friendsList
    }
}

struct BoundingBoxTests {
    @Test func spansTheVisibleRegion() throws {
        let box = try #require(BoundingBox(center: .init(latitude: 30, longitude: 31), latitudeDelta: 0.2, longitudeDelta: 0.4))
        #expect(box.queryValue == "30.800000,29.900000,31.200000,30.100000")
    }

    @Test func refusesTooWideOrAcrossTheDateLine() {
        #expect(BoundingBox(center: .init(latitude: 30, longitude: 31), latitudeDelta: 2, longitudeDelta: 6) == nil)
        #expect(BoundingBox(center: .init(latitude: 0, longitude: 179.5), latitudeDelta: 1, longitudeDelta: 2) == nil)
    }
}

struct PlaceModelDecodingTests {
    @Test func placeDetailReadsThePlaceAndMyRatingSideBySide() throws {
        let json = """
        {"id":"p1","appleId":null,"name":"Koshary","category":"MKPOICategoryRestaurant","latitude":30,"longitude":31,
        "avgRating":4.5,"ratingCount":2,"createdAt":"2026-11-11T06:54:12.345Z",
        "myRating":{"id":"r1","stars":5,"comment":"Great","updatedAt":"2026-11-11T06:54:12.345Z"}}
        """
        let detail = try JSONDecoder.api.decode(PlaceDetail.self, from: Data(json.utf8))
        #expect(detail.place.name == "Koshary")
        #expect(detail.place.avgRating == 4.5)
        #expect(detail.myRating?.stars == 5)
    }

    @Test func categoryNamesAreReadable() {
        #expect(PlaceCategory.name(for: "MKPOICategoryCafe") == "Café")
        #expect(PlaceCategory.name(for: "MKPOICategoryGasStation") == "Gas Station")
        #expect(PlaceCategory.name(for: nil) == nil)
    }
}

@MainActor
struct PlaceViewModelTests {
    @Test func loadsWithFriendsFirstAndLeavesMyOwnRatingOut() async {
        let api = FakePlacesAPI()
        let sara = person("s", "Sara"), omar = person("o", "Omar"), mine = person(me, "Alice")
        api.detail = PlaceDetail(place: makePlace(avg: 4, count: 3),
                                 myRating: MyRating(id: "m", stars: 3, comment: "ok", updatedAt: day))
        api.ratingPages = [nil: RatingPage(items: [rating("1", by: omar), rating("2", by: mine), rating("3", by: sara)],
                                           nextCursor: "c2")]
        api.friendsList = FriendsList(friends: [FriendshipEntry(id: "f", user: sara, since: day)], incoming: [], outgoing: [])
        let model = PlaceViewModel(placeId: "p1", api: api, myId: me)

        await model.load()

        #expect(model.stars == 3)
        #expect(model.comment == "ok")
        #expect(model.friendRatings.map(\.user.name) == ["Sara"])
        #expect(model.otherRatings.map(\.user.name) == ["Omar"])
        #expect(model.hasMoreRatings)
    }

    @Test func quickStarTapsBecomeOneSaveAndUpdateThePin() async {
        let api = FakePlacesAPI()
        var changed: [Place] = []
        let model = PlaceViewModel(placeId: "p1", api: api, myId: me, debounce: .milliseconds(20)) { changed.append($0) }
        await model.load()

        model.setStars(2)
        model.setStars(5)
        await model.waitForSave()

        #expect(api.calls.filter { $0.hasPrefix("rate") } == ["rate 5"])
        #expect(model.place?.avgRating == 5)
        #expect(changed.map(\.ratingCount) == [1])
    }

    @Test func commentSavesOnFocusLossOnlyWhenChanged() async {
        let api = FakePlacesAPI()
        api.detail = PlaceDetail(place: makePlace(avg: 4, count: 1),
                                 myRating: MyRating(id: "m", stars: 4, comment: "nice", updatedAt: day))
        let model = PlaceViewModel(placeId: "p1", api: api, myId: me)
        await model.load()

        model.comment = "nice  "
        await model.commentEditingEnded()
        #expect(api.rateBodies.isEmpty)

        model.comment = "  "
        await model.commentEditingEnded()
        #expect(api.rateBodies.count == 1)
        #expect(api.rateBodies[0].0 == 4)
        #expect(api.rateBodies[0].1 == nil) // an empty field clears the comment
    }

    @Test func aFailedSaveOffersARetry() async {
        let api = FakePlacesAPI()
        api.failRate = true
        let model = PlaceViewModel(placeId: "p1", api: api, myId: me, debounce: .zero)
        await model.load()

        model.setStars(4)
        await model.waitForSave()

        #expect(model.saveFailed)
        #expect(model.errorText != nil)
        #expect(model.stars == 4)
    }

    @Test func removingTheRatingClearsItAndRefreshes() async {
        let api = FakePlacesAPI()
        api.detail = PlaceDetail(place: makePlace(avg: 4, count: 1),
                                 myRating: MyRating(id: "m", stars: 4, comment: nil, updatedAt: day))
        var changed: [Place] = []
        let model = PlaceViewModel(placeId: "p1", api: api, myId: me) { changed.append($0) }
        await model.load()

        await model.removeRating()

        #expect(model.stars == 0)
        #expect(api.calls.contains("delete"))
        #expect(changed.last?.ratingCount == 0)
    }

    @Test func loadsMoreRatings() async {
        let api = FakePlacesAPI()
        api.ratingPages = [nil: RatingPage(items: [rating("1", by: person("a", "A"))], nextCursor: "c2"),
                           "c2": RatingPage(items: [rating("2", by: person("b", "B"))], nextCursor: nil)]
        let model = PlaceViewModel(placeId: "p1", api: api, myId: me)
        await model.load()

        await model.loadMoreRatings()

        #expect(model.otherRatings.map(\.id) == ["1", "2"])
        #expect(!model.hasMoreRatings)
    }
}

@MainActor
struct MapPlacesTests {
    private func makeModel(_ api: FakePlacesAPI) -> MapViewModel {
        MapViewModel(user: makeUser(), location: FakeLocation(access: .allowed), socket: FakeLiveSocket(),
                     places: api, placesDebounce: .milliseconds(10))
    }

    @Test func pinsOnlyRatedPlacesAfterTheCameraSettles() async {
        let api = FakePlacesAPI()
        api.nearby = [makePlace(id: "rated", avg: 4, count: 2), makePlace(id: "unrated")]
        let model = makeModel(api)

        // the places sit at 30.05, 31.24
        model.cameraSettled(center: .init(latitude: 30.04, longitude: 31.24), latitudeDelta: 0.03, longitudeDelta: 0.03)
        model.cameraSettled(center: .init(latitude: 30.05, longitude: 31.24), latitudeDelta: 0.03, longitudeDelta: 0.03)
        await model.waitForPlaces()

        #expect(model.places.map(\.id) == ["rated"])
        #expect(api.calls.filter { $0.hasPrefix("places") }.count == 1) // the first was replaced
    }

    @Test func showsCachedPinsAtOnceWhenTheCameraComesBack() async {
        let api = FakePlacesAPI()
        api.nearby = [makePlace(id: "rated", avg: 4, count: 2)]
        let model = makeModel(api)
        model.cameraSettled(center: .init(latitude: 30.05, longitude: 31.24), latitudeDelta: 0.02, longitudeDelta: 0.02)
        await model.waitForPlaces()

        // look away, then back: the pin is there before any new request
        model.cameraSettled(center: .init(latitude: 31.5, longitude: 32.5), latitudeDelta: 0.02, longitudeDelta: 0.02)
        model.cameraSettled(center: .init(latitude: 30.05, longitude: 31.24), latitudeDelta: 0.02, longitudeDelta: 0.02)
        #expect(model.places.map(\.id) == ["rated"])
        await model.waitForPlaces()
        #expect(api.calls.filter { $0.hasPrefix("places") }.count == 1) // still fresh: not asked again
    }

    @Test func zoomedFarOutKeepsThePinsWithoutAsking() async {
        let api = FakePlacesAPI()
        let model = makeModel(api)

        model.cameraSettled(center: .init(latitude: 30, longitude: 31), latitudeDelta: 20, longitudeDelta: 20)
        await model.waitForPlaces()

        #expect(api.calls.isEmpty)
    }

    @Test func aTappedPlaceOpensAtOnceAndResolvesInTheSheet() async {
        let api = FakePlacesAPI()
        let model = makeModel(api)

        model.openPreview(PlacePreview(name: "Stoop Café", category: "MKPOICategoryCafe")) {
            try await api.resolvePlace(appleId: "I1", name: "Stoop Café", category: "MKPOICategoryCafe",
                                       latitude: 30.05, longitude: 31.24)
        }

        // the sheet is up before the server has answered
        #expect(model.sheet == .place)
        #expect(model.placeModel?.placeId == nil)
        #expect(model.placeModel?.name == "Stoop Café")
        #expect(api.calls.isEmpty)

        await model.placeModel?.load()
        #expect(api.calls.first == "resolve I1 Stoop Café")
        #expect(model.placeModel?.placeId == "p1")
        #expect(model.placeModel?.photos != nil)

        model.showBrowse()
        #expect(model.placeModel == nil)
    }

    @Test func aFailedResolveOffersARetryInTheSheet() async {
        let model = makeModel(FakePlacesAPI())
        var attempts = 0
        model.openPreview(PlacePreview(name: "Nowhere", category: nil)) {
            attempts += 1
            throw URLError(.notConnectedToInternet)
        }
        await model.placeModel?.load()
        #expect(model.placeModel?.errorText != nil)
        #expect(model.placeModel?.name == "Nowhere")
        await model.placeModel?.load()
        #expect(attempts == 2)
    }

    @Test func ratingInTheSheetAddsAndRemovesThePin() {
        let model = makeModel(FakePlacesAPI())

        model.placeChanged(makePlace(avg: 5, count: 1))
        #expect(model.places.map(\.avgRating) == [5])
        model.placeChanged(makePlace())
        #expect(model.places.isEmpty)
    }
}
