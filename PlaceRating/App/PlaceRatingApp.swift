import Nuke
import SwiftUI

@main
struct PlaceRatingApp: App {
    @State private var session: SessionStore
    @State private var settings = AppSettings()

    init() {
        // place photos never change once uploaded, so keep the downloaded files on disk too
        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
        let http = HTTPClient(baseURL: { AppConfig.current.apiBaseURL }, transport: URLSession.shared)
        let api = APIClient(http: http, store: KeychainTokenStore())
        _session = State(initialValue: SessionStore(api: api))
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
        }
    }
}
