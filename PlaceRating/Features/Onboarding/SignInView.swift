import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @State private var model: SignInViewModel
    #if DEBUG
    @State private var devUsername = ""
    @State private var server = DebugServer.selected
    #endif

    init(session: SessionStore) {
        _model = State(initialValue: SignInViewModel(session: session))
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            StoopMark()
                .frame(width: 140)
            Text(verbatim: "Stoop")
                .font(.largeTitle.bold())
                .foregroundStyle(Brand.foreground)
            Text("Rate places with your friends")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Brand.foreground)
            Spacer()

            if let error = model.errorText {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Brand.accent)
                    .multilineTextAlignment(.center)
            }

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
                request.nonce = model.prepareNonce()
            } onCompletion: { result in
                Task { await model.complete(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .disabled(model.isBusy)

            #if DEBUG
            debugControls
            #endif
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background)
    }

    #if DEBUG
    /// Developer tools, compiled out of Release builds, so they aren't translated.
    private var debugControls: some View {
        VStack(spacing: 8) {
            Picker(selection: $server) {
                ForEach(DebugServer.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
            } label: {
                Text(verbatim: "Server")
            }
            .pickerStyle(.segmented)
            .onChange(of: server) { DebugServer.selected = server }

            if server == .local {
                HStack {
                    TextField(text: $devUsername) { Text(verbatim: "dev username") }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("devUsername")
                    Button {
                        Task { await model.devSignIn(username: devUsername) }
                    } label: {
                        Text(verbatim: "Dev sign in")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("devSignIn")
                }
            }
        }
    }
    #endif
}
