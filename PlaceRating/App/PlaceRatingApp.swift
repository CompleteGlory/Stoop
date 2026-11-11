import SwiftUI

@main
struct PlaceRatingApp: App {
    @State private var session: SessionStore

    init() {
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
