import Testing
@testable import PlaceRating

struct AppConfigTests {
    @Test func productionUsesEncryptedTransport() {
        #expect(AppConfig.production.apiBaseURL.scheme == "https")
        #expect(AppConfig.production.liveURL.scheme == "wss")
    }

    @Test func liveSocketIsAtLivePath() {
        #expect(AppConfig.local.liveURL.path() == "/live")
        #expect(AppConfig.production.liveURL.path() == "/live")
    }
}
