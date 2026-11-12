import Foundation
import Testing
@testable import PlaceRating

struct DeepLinkTests {
    private let id = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"
    private let local = URL(string: "http://localhost:3000")!

    @Test func readsSharedPlaceLinks() {
        let expected = DeepLink.place(id: id.lowercased())
        #expect(DeepLink(url: URL(string: "https://place-rating-api-production.up.railway.app/p/\(id)")!, apiBaseURL: local) == expected)
        #expect(DeepLink(url: URL(string: "http://localhost:3000/p/\(id.lowercased())")!, apiBaseURL: local) == expected)
        #expect(DeepLink(url: URL(string: "stoop://place/\(id)")!, apiBaseURL: local) == expected)
    }

    @Test func ignoresEverythingElse() {
        for link in [
            "https://evil.example/p/\(id)",
            "https://place-rating-api-production.up.railway.app/privacy",
            "https://place-rating-api-production.up.railway.app/p/not-an-id",
            "https://place-rating-api-production.up.railway.app/p/\(id)/extra",
            "stoop://friend/\(id)",
            "com.googleusercontent.apps.123:/oauth2redirect?code=x",
        ] {
            #expect(DeepLink(url: URL(string: link)!, apiBaseURL: local) == nil, "\(link)")
        }
    }

    @Test func buildsTheShareAndGoogleMapsLinks() {
        let place = makePlace(id: id.lowercased())
        let share = PlaceLinks.share(place, apiBaseURL: URL(string: "https://api.example.com")!)
        #expect(share.absoluteString == "https://api.example.com/p/\(id.lowercased())")
        #expect(DeepLink(url: share, apiBaseURL: URL(string: "https://api.example.com")!) == .place(id: id.lowercased()))
        #expect(PlaceLinks.googleMaps(place).absoluteString == "https://www.google.com/maps/search/?api=1&query=30.05,31.24")
    }
}

@MainActor
struct SharedLinkSessionTests {
    @Test func keepsStoopLinksForTheMapAndLeavesOthers() {
        let store = SessionStore(api: FakeAPI())
        #expect(!store.handle(URL(string: "com.googleusercontent.apps.123:/oauth2redirect")!))
        #expect(store.pendingLink == nil)
        #expect(store.handle(URL(string: "stoop://place/3F2504E0-4F89-41D3-9A0C-0305E82C3301")!))
        #expect(store.pendingLink == .place(id: "3f2504e0-4f89-41d3-9a0c-0305e82c3301"))
    }
}

@MainActor
struct OpenSharedPlaceTests {
    @Test func opensTheSheetAtOnceAndFliesThereWhenLoaded() async throws {
        let places = FakePlacesAPI()
        let model = MapViewModel(
            user: makeUser(), location: FakeLocation(access: .allowed), socket: FakeLiveSocket(), onSessionExpired: {},
            places: places, friendsAPI: FakeFriendsAPI()
        )
        model.openShared(.place(id: "p1"))
        #expect(model.sheet == .place)
        let sheet = try #require(model.placeModel)
        #expect(sheet.placeId == "p1")

        await sheet.load()
        #expect(model.camera.region?.center.latitude == 30.05)
    }
}
