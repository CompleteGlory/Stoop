import SwiftUI

struct UsernameView: View {
    let session: SessionStore
    @State private var model: UsernameViewModel

    init(session: SessionStore, user: SelfUser) {
        self.session = session
        _model = State(initialValue: UsernameViewModel(session: session, user: user))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a username")
                .font(.largeTitle.bold())
            Text("Friends find you by this name.")
                .foregroundStyle(.secondary)

            TextField("Username", text: $model.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("username")
                .onChange(of: model.username) { model.usernameChanged() }

            // a fixed-height slot, so the button doesn't jump as messages come and go
            ZStack(alignment: .leading) {
                Color.clear
                statusLine
            }
            .font(.footnote)
            .frame(height: 20)

            Button {
                Task { await model.submit() }
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("continue")

            Spacer()

            Button("Sign out", role: .destructive) {
                Task { await session.signOut() }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let error = model.errorText {
            Text(error).foregroundStyle(.red)
        } else {
            switch model.status {
            case .idle, .unknown: EmptyView()
            case .checking: Text("Checking…").foregroundStyle(.secondary)
            case .available: Label("Available", systemImage: "checkmark.circle").foregroundStyle(.green)
            case .taken: Text("That username is taken.").foregroundStyle(.red)
            case .reserved: Text("That username isn't available.").foregroundStyle(.red)
            case .invalid: Text("Use 3 to 20 letters, digits, _ or .").foregroundStyle(.red)
            }
        }
    }
}
