import Foundation
import Testing
@testable import PlaceRating

private let friendId = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"

/// Answers the notification permission prompt for the person.
private final class FakePermission: NotificationPermission, @unchecked Sendable {
    var current: NotificationAccess
    var answer: Bool
    private(set) var asked = 0

    init(_ current: NotificationAccess = .unknown, answer: Bool = true) {
        self.current = current
        self.answer = answer
    }

    func access() async -> NotificationAccess { current }
    func request() async -> Bool {
        asked += 1
        current = answer ? .allowed : .denied
        return answer
    }
}

@MainActor
private final class FakeNotificationsAPI: NotificationsAPI, @unchecked Sendable {
    var registered: [(token: String, environment: PushEnvironment)] = []
    var unregistered: [String] = []
    var nearbyCalls: [Bool] = []
    var nearbyResult: Result<Void, Error> = .success(())

    nonisolated func registerDevice(token: String, environment: PushEnvironment) async throws {
        await MainActor.run { registered.append((token, environment)) }
    }
    nonisolated func unregisterDevice(token: String) async throws {
        await MainActor.run { unregistered.append(token) }
    }
    nonisolated func setNearbyAlerts(_ on: Bool) async throws -> SelfUser {
        try await MainActor.run {
            nearbyCalls.append(on)
            try nearbyResult.get()
            var user = makeUser()
            user.nearbyAlerts = on
            return user
        }
    }
    nonisolated func reportPosition(latitude: Double, longitude: Double, accuracy: Double) async throws {}
}

@MainActor
private final class FakeReporter: NearbyReporting {
    var isEnabled = false
    var locationAccess: BackgroundLocationAccess = .whileUsing
    private(set) var askedForAlways = 0

    func start() { isEnabled = true }
    func stop() { isEnabled = false }
    func requestAlwaysAccess() { askedForAlways += 1 }
}

@MainActor
private final class FakePush: PushRegistering {
    var access: NotificationAccess = .allowed
    var answer = true
    private(set) var refreshed = 0
    private(set) var requested = 0
    private(set) var unregistered = 0
    private(set) var forgotten = 0

    func refresh() async { refreshed += 1 }
    func requestAccess() async -> Bool {
        requested += 1
        access = answer ? .allowed : .denied
        return answer
    }
    func unregister() async { unregistered += 1 }
    func forget() { forgotten += 1 }
}

/// Counts calls from main-actor closures.
@MainActor
private final class Calls {
    var count = 0
}

private func freshDefaults() -> UserDefaults {
    let name = "push-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

struct PushPayloadTests {
    @Test func friendPushesOpenTheFriendsList() {
        let request = PushPayload(userInfo: ["kind": "friend-request", "userId": friendId, "aps": [:]])
        #expect(request == PushPayload(kind: .friendRequest, userId: friendId.lowercased()))
        #expect(request?.link == .friends)
        #expect(PushPayload(userInfo: ["kind": "friend-accepted", "userId": friendId])?.link == .friends)
    }

    @Test func nearbyOpensThatFriendAndFallsBackToTheList() {
        #expect(PushPayload(userInfo: ["kind": "nearby", "userId": friendId])?.link == .friend(id: friendId.lowercased()))
        #expect(PushPayload(userInfo: ["kind": "nearby", "userId": "not-an-id"])?.link == .friends)
    }

    @Test func ignoresOtherNotifications() {
        #expect(PushPayload(userInfo: ["aps": ["alert": "hi"]]) == nil)
        #expect(PushPayload(userInfo: ["kind": "something-new"]) == nil)
    }
}

@MainActor
struct PushInboxTests {
    @Test func tappingAFriendPushOpensTheListAndReloadsIt() {
        let inbox = PushInbox()
        inbox.tapped(PushPayload(kind: .friendRequest, userId: nil))
        #expect(inbox.pendingLink == .friends)
        #expect(inbox.friendsRevision == 1)
        inbox.arrived(PushPayload(kind: .nearby, userId: friendId))
        #expect(inbox.friendsRevision == 1)
        inbox.arrived(PushPayload(kind: .friendAccepted, userId: friendId))
        #expect(inbox.friendsRevision == 2)
    }
}

@MainActor
struct PushRegistrarTests {
    private func registrar(_ permission: FakePermission, api: FakeNotificationsAPI, defaults: UserDefaults = freshDefaults(), registered: @escaping @MainActor () -> Void = {}) -> PushRegistrar {
        let registrar = PushRegistrar(permission: permission, environment: .sandbox, defaults: defaults, registerWithApple: registered)
        registrar.api = api
        return registrar
    }

    @Test func registersWithAppleOnlyWhenAllowedAndSendsTheTokenOnce() async {
        let api = FakeNotificationsAPI()
        let apple = Calls()
        let denied = registrar(FakePermission(.denied), api: api) { apple.count += 1 }
        await denied.refresh()
        #expect(apple.count == 0)
        #expect(denied.access == .denied)

        let allowed = registrar(FakePermission(.allowed), api: api) { apple.count += 1 }
        await allowed.refresh()
        #expect(apple.count == 1)
        await allowed.received(deviceToken: Data([0x0a, 0xff, 0x00]))
        await allowed.received(deviceToken: Data([0x0a, 0xff, 0x00]))
        #expect(api.registered.map(\.token) == ["0aff00"])
        #expect(api.registered.first?.environment == .sandbox)
    }

    @Test func asksOnceAndRegistersWhenThePersonAgrees() async {
        let permission = FakePermission(.unknown, answer: true)
        let apple = Calls()
        let registrar = registrar(permission, api: FakeNotificationsAPI()) { apple.count += 1 }
        #expect(await registrar.requestAccess())
        #expect(permission.asked == 1)
        #expect(registrar.access == .allowed)
        #expect(apple.count == 1)
    }

    @Test func sendsNothingWhileSignedOut() async {
        let api = FakeNotificationsAPI()
        let registrar = registrar(FakePermission(.allowed), api: api)
        await registrar.received(deviceToken: Data([1, 2]))
        #expect(api.registered.isEmpty)
    }

    @Test func signingOutRemovesTheTokenTheServerHas_evenFromAnEarlierLaunch() async {
        let defaults = freshDefaults()
        let api = FakeNotificationsAPI()
        let first = registrar(FakePermission(.allowed), api: api, defaults: defaults)
        await first.refresh()
        await first.received(deviceToken: Data([0xab]))

        // a later launch where iOS hasn't handed the token over (notifications turned off since)
        let later = registrar(FakePermission(.denied), api: api, defaults: defaults)
        await later.refresh()
        await later.unregister()
        #expect(api.unregistered == ["ab"])
        await later.unregister()
        #expect(api.unregistered == ["ab"])
    }

    @Test func forgettingAfterDeletionCallsNothing() async {
        let defaults = freshDefaults()
        let api = FakeNotificationsAPI()
        let registrar = registrar(FakePermission(.allowed), api: api, defaults: defaults)
        await registrar.refresh()
        await registrar.received(deviceToken: Data([0xcd]))
        registrar.forget()
        await registrar.unregister()
        #expect(api.unregistered.isEmpty)
    }
}

@MainActor
struct NearbySettingsTests {
    private func model(push: FakePush = FakePush(), reporter: FakeReporter = FakeReporter(), api: FakeNotificationsAPI = FakeNotificationsAPI()) -> NotificationSettingsModel {
        let session = SessionStore(api: FakeAPI())
        return NotificationSettingsModel(session: session, push: push, nearby: reporter, api: api)
    }

    @Test func turningOnSavesStartsReportingAndAsksForAlways() async {
        let reporter = FakeReporter()
        let api = FakeNotificationsAPI()
        let settings = model(reporter: reporter, api: api)
        await settings.setNearby(true)
        #expect(api.nearbyCalls == [true])
        #expect(reporter.isEnabled)
        #expect(reporter.askedForAlways == 1)
        #expect(settings.needsAlwaysLocation)
        #expect(settings.error == nil)

        reporter.locationAccess = .always
        #expect(!settings.needsAlwaysLocation)

        await settings.setNearby(false)
        #expect(api.nearbyCalls == [true, false])
        #expect(!reporter.isEnabled)
    }

    @Test func needsNotificationsFirst() async {
        let push = FakePush()
        push.access = .unknown
        push.answer = false
        let reporter = FakeReporter()
        let api = FakeNotificationsAPI()
        let settings = model(push: push, reporter: reporter, api: api)
        await settings.setNearby(true)
        #expect(push.requested == 1)
        #expect(api.nearbyCalls.isEmpty)
        #expect(!reporter.isEnabled)
        #expect(settings.error != nil)
    }

    @Test func staysOffWhenTheServerRefuses() async {
        let reporter = FakeReporter()
        let api = FakeNotificationsAPI()
        api.nearbyResult = .failure(APIError(status: 500, code: "internal_error", message: ""))
        let settings = model(reporter: reporter, api: api)
        await settings.setNearby(true)
        #expect(!reporter.isEnabled)
        #expect(settings.error != nil)
    }
}

@MainActor
struct SessionNotificationTests {
    @Test func theMapMatchesTheReporterToTheAccountAndRegisters() async {
        let api = FakeAPI()
        var user = makeUser()
        user.nearbyAlerts = true
        api.restoreResult = .success(true)
        api.meResult = .success(user)
        let session = SessionStore(api: api)
        let push = FakePush()
        let reporter = FakeReporter()
        session.push = push
        session.nearby = reporter
        await session.start()

        await session.mapAppeared()
        #expect(reporter.isEnabled)
        #expect(push.refreshed == 1)
    }

    @Test func signingOutStopsPushesAndReports() async {
        let session = SessionStore(api: FakeAPI())
        let push = FakePush()
        let reporter = FakeReporter()
        reporter.isEnabled = true
        session.push = push
        session.nearby = reporter
        await session.signOut()
        #expect(push.unregistered == 1)
        #expect(!reporter.isEnabled)
    }

    @Test func asksForNotificationsOnlyOnce() async {
        let session = SessionStore(api: FakeAPI())
        let push = FakePush()
        push.access = .unknown
        session.push = push
        await session.askForNotificationsOnce()
        await session.askForNotificationsOnce()
        #expect(push.requested == 1)
    }
}

@MainActor
struct NotificationLinkTests {
    private func map() -> MapViewModel {
        MapViewModel(user: makeUser(), location: FakeLocation(access: .allowed), socket: FakeLiveSocket(),
                     onSessionExpired: {}, friendsAPI: FakeFriendsAPI())
    }

    @Test func friendPushesOpenTheFriendsSheet() {
        let model = map()
        model.openShared(.friends)
        #expect(model.sheet == .friends)
    }

    @Test func aNearbyFriendWhoIsNotSharingOpensTheList() {
        let model = map()
        model.openShared(.friend(id: friendId.lowercased()))
        #expect(model.sheet == .friends)
    }
}

/// The server sends these as `loc-key`; iOS finds the words here, so they must stay in the catalog.
struct PushTextTests {
    @Test func everyServerKeyHasAnArabicTranslation() throws {
        let path = try #require(Bundle.main.path(forResource: "ar", ofType: "lproj"))
        let arabic = try #require(Bundle(path: path))
        for key in ["Friend request", "%@ wants to be friends", "New friend", "%@ accepted your friend request",
                    "Friend nearby", "%@ is nearby"] {
            let text = arabic.localizedString(forKey: key, value: "missing", table: nil)
            #expect(text != "missing" && text != key, "no Arabic for \(key)")
        }
        #expect(PushText.keys.count == 6)
    }
}

@MainActor
struct LanguageForNotificationsTests {
    @Test func theInAppLanguageAlsoWordsNotifications() {
        let name = "lang-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults, localizer: Localizer())
        settings.language = .arabic
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["ar"])
        settings.language = .system
        #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] == nil)
    }
}
