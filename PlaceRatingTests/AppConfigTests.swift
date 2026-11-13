import Foundation
import Testing
@testable import PlaceRating

struct AppConfigTests {
    @Test func productionUsesEncryptedTransport() {
        #expect(AppConfig.production.apiBaseURL.scheme == "https")
        #expect(AppConfig.production.liveURL.scheme == "wss")
    }

    @Test func liveSocketIsAtLivePath() {
        #expect(AppConfig.local().liveURL.path() == "/live")
        #expect(AppConfig.production.liveURL.path() == "/live")
    }

    @Test func theLocalServerCanBeAnotherMachineForARealPhone() {
        #expect(AppConfig.local().apiBaseURL.absoluteString == "http://localhost:3000")
        let mac = AppConfig.local(host: "Some-Mac.local")
        #expect(mac.apiBaseURL.absoluteString == "http://Some-Mac.local:3000")
        #expect(mac.liveURL.absoluteString == "ws://Some-Mac.local:3000/live")
    }

    #if DEBUG
    @Test func launchArgumentsForTheServerAreRemembered() {
        let name = "config-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        DebugServer.rememberLaunchArguments(["debug.server": "local", "debug.localHost": "Some-Mac.local", "other": "x"], defaults: defaults)
        let saved = defaults.persistentDomain(forName: name)
        #expect(saved?["debug.server"] as? String == "local")
        #expect(saved?["debug.localHost"] as? String == "Some-Mac.local")
        #expect(saved?["other"] == nil)
    }
    #endif
}
