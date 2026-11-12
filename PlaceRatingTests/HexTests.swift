import CoreLocation
import MapKit
import Foundation
import Testing
@testable import PlaceRating

private let cairo = CLLocationCoordinate2D(latitude: 30.0444, longitude: 31.2357)

private func ratedPlace(_ id: String, at coordinate: CLLocationCoordinate2D, stars: Double = 4) -> Place {
    Place(id: id, appleId: nil, name: id, category: nil, latitude: coordinate.latitude,
          longitude: coordinate.longitude, avgRating: stars, ratingCount: 1)
}

struct HexGridTests {
    @Test func aPointBelongsToTheHexagonCentredNearIt() {
        let cell = HexGrid.cell(for: cairo)
        let center = HexGrid.center(of: cell)
        let distance = CLLocation(latitude: center.latitude, longitude: center.longitude)
            .distance(from: CLLocation(latitude: cairo.latitude, longitude: cairo.longitude))
        #expect(distance < 900) // inside one hexagon (about 1.5 km across here)
        #expect(HexGrid.cell(for: center) == cell)
    }

    @Test func everyCornerSurroundsTheCentre() {
        let corners = HexGrid.corners(of: HexGrid.cell(for: cairo))
        #expect(corners.count == 6)
        let center = HexGrid.center(of: HexGrid.cell(for: cairo))
        #expect(corners.map(\.latitude).min()! < center.latitude)
        #expect(corners.map(\.latitude).max()! > center.latitude)
    }

    @Test func disksGrowInRings() {
        let cell = HexCell(q: 0, r: 0)
        #expect(HexGrid.disk(around: cell, radius: 0) == [cell])
        #expect(HexGrid.disk(around: cell, radius: 1).count == 7)
        #expect(HexGrid.disk(around: cell, radius: 2).count == 19)
        #expect(Set(HexGrid.disk(around: cell, radius: 3)).count == 37)
    }

    @Test func coversAStreetViewButNotACountry() throws {
        let street = MKCoordinateRegion(center: cairo, latitudinalMeters: 1500, longitudinalMeters: 1500)
        let cells = try #require(HexGrid.cells(covering: street))
        #expect(cells.contains(HexGrid.cell(for: cairo)))
        #expect(cells.count < 40)

        let country = MKCoordinateRegion(center: cairo, span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8))
        #expect(HexGrid.cells(covering: country) == nil)
    }

    @Test func boxesHoldTheirHexagons() throws {
        let cells = HexGrid.disk(around: HexGrid.cell(for: cairo), radius: 2)
        let box = try #require(HexGrid.box(around: cells))
        for cell in cells {
            let c = HexGrid.center(of: cell)
            #expect(c.latitude >= box.minLatitude && c.latitude <= box.maxLatitude)
            #expect(c.longitude >= box.minLongitude && c.longitude <= box.maxLongitude)
        }
    }
}

@MainActor
struct PlacesChunkCacheTests {
    @Test func loadsMissingHexagonsInOneRequestThenServesThemFromMemory() async {
        let api = FakePlacesAPI()
        api.nearby = [ratedPlace("here", at: cairo)]
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let cache = PlacesChunkCache(api: api, now: { clock })
        let cells = HexGrid.disk(around: HexGrid.cell(for: cairo), radius: 1)

        #expect(await cache.load(cells))
        #expect(api.calls.filter { $0.hasPrefix("places") }.count == 1)
        #expect(cache.places(in: cells).map(\.id) == ["here"])

        // fresh: no second request
        #expect(await !cache.load(cells))
        #expect(api.calls.filter { $0.hasPrefix("places") }.count == 1)

        // five minutes later the chunks are stale and come back again
        clock = clock.addingTimeInterval(PlacesChunkCache.freshFor + 1)
        #expect(await cache.load(cells))
        #expect(api.calls.filter { $0.hasPrefix("places") }.count == 2)
    }

    @Test func onlyAsksForTheHexagonsItDoesNotHave() async {
        let api = FakePlacesAPI()
        let cache = PlacesChunkCache(api: api)
        let home = HexGrid.cell(for: cairo)
        await cache.load([home])
        await cache.load(HexGrid.disk(around: home, radius: 1))
        #expect(api.calls.filter { $0.hasPrefix("places") }.count == 2)
        #expect(cache.isFresh(home))
        #expect(HexGrid.disk(around: home, radius: 1).allSatisfy { cache.isFresh($0) })
    }

    @Test func aNewRatingUpdatesItsHexagon() async {
        let api = FakePlacesAPI()
        api.nearby = [ratedPlace("here", at: cairo, stars: 3)]
        let cache = PlacesChunkCache(api: api)
        var updates = 0
        cache.onUpdate = { updates += 1 }
        let home = HexGrid.cell(for: cairo)
        await cache.load([home])

        cache.update(ratedPlace("here", at: cairo, stars: 5))
        #expect(cache.places(in: [home]).map(\.avgRating) == [5])
        #expect(updates == 2)
    }

    @Test func preloadingFillsTheRingAroundYou() async {
        let cache = PlacesChunkCache(api: FakePlacesAPI())
        await cache.preload(around: cairo, radius: 2)
        #expect(HexGrid.disk(around: HexGrid.cell(for: cairo), radius: 2).allSatisfy { cache.isFresh($0) })
    }
}

@MainActor
struct PlaceSheetNumbersTests {
    @Test func countsStarsAndAveragesFriends() async {
        let api = FakePlacesAPI()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let friend = PublicUser(id: "f", username: "f", displayName: "F", avatar: nil)
        let stranger = PublicUser(id: "s", username: "s", displayName: "S", avatar: nil)
        api.detail = PlaceDetail(place: makePlace(avg: 4, count: 3), myRating: MyRating(id: "m", stars: 5, comment: nil, updatedAt: day))
        api.ratingPages = [nil: RatingPage(items: [
            PlaceRating(id: "1", stars: 4, comment: nil, createdAt: day, updatedAt: day, user: friend),
            PlaceRating(id: "2", stars: 2, comment: nil, createdAt: day, updatedAt: day, user: stranger),
        ], nextCursor: nil)]
        api.friendsList = FriendsList(friends: [FriendshipEntry(id: "x", user: friend, since: day)], incoming: [], outgoing: [])
        let model = PlaceViewModel(placeId: "p1", api: api, myId: "me")
        await model.load()

        #expect(model.starCounts == [0, 1, 0, 1, 1])
        #expect(model.friendsAverage == 4)
        #expect(!model.starCountsArePartial)
    }

    @Test func showsSavedForAMomentAfterSaving() async {
        let model = PlaceViewModel(placeId: "p1", api: FakePlacesAPI(), myId: "me", debounce: .zero)
        await model.load()
        model.setStars(4)
        await model.waitForSave()
        #expect(model.savedRecently)
    }

    @Test func everyStarCountHasWords() {
        #expect(Set((0...5).map(PlaceCategory.feeling(for:))).count == 6)
        #expect(PlaceCategory.symbol(for: "MKPOICategoryCafe").name == "cup.and.saucer.fill")
        #expect(PlaceCategory.symbol(for: nil).name == "mappin")
    }
}
