import Nuke
import SwiftUI

@main
struct PlaceRatingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session: SessionStore
    @State private var settings = AppSettings()
    private let inbox = PushInbox.shared

    init() {
        #if DEBUG
        DebugServer.rememberLaunchArguments()
        #endif
        // place photos never change once uploaded, so keep the downloaded files on disk too
        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
        let http = HTTPClient(baseURL: { AppConfig.current.apiBaseURL }, transport: URLSession.shared)
        let api = APIClient(http: http, store: KeychainTokenStore())
        let session = SessionStore(api: api)
        // pushes and background positions use the same signed-in client as everything else
        PushRegistrar.shared.api = api
        NearbyReporter.shared.api = api
        session.push = PushRegistrar.shared
        session.nearby = NearbyReporter.shared
        _session = State(initialValue: session)
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
                .environment(settings)
                .applying(settings)
                .onOpenURL { url in
                    // shared place links (universal or stoop://) first, then Google Sign-In's callback
                    if !session.handle(url) { GoogleSignInService.handle(url) }
                }
                // a tapped notification goes where shared links go: the map opens it once it can
                .onChange(of: inbox.pendingLink, initial: true) { _, link in
                    guard let link else { return }
                    inbox.pendingLink = nil
                    session.pendingLink = link
                }
        }
    }
}
