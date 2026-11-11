import Nuke
import SwiftUI

@main
struct PlaceRatingApp: App {
    @State private var session: SessionStore

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
                .onOpenURL { GoogleSignInService.handle($0) }
        }
    }
}
