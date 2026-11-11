import SwiftUI

/// The email sheet: sign in, create an account, enter a code, or reset the password.
struct EmailAuthView: View {
    @State private var model: EmailAuthViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Field?

    private enum Field { case email, password, code, newPassword }

    init(session: SessionStore) {
        _model = State(initialValue: EmailAuthViewModel(session: session))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                    if let info = model.infoText {
                        Text(info).font(.callout).foregroundStyle(Brand.foreground.opacity(0.75))
                    }
                    fields
                    if let error = model.errorText {
                        Text(error).font(.footnote).foregroundStyle(Brand.negative.text)
                    }
                    Button {
                        Task { await model.submit() }
                    } label: {
                        if model.isBusy { ProgressView().tint(Brand.background) } else { Text(actionTitle) }
                    }
                    .buttonStyle(BrandButtonStyle())
                    .disabled(!model.canSubmit)
                    .accessibilityIdentifier("emailSubmit")
                    links
                }
                .padding(24)
            }
            .foregroundStyle(Brand.foreground)
            .background(Brand.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Brand.foreground)
                }
            }
            .onAppear { focused = .email }
            .onChange(of: model.step) { _, step in
                // put the keyboard where the next thing to type is
                focused = switch step {
                case .verify, .reset: .code
                case .signIn, .signUp, .forgot: .email
                }
            }
            .animation(.snappy, value: model.step)
        }
    }

    private var title: String {
        switch model.step {
        case .signIn: String(localized: "Sign in with email")
        case .signUp: String(localized: "Create your account")
        case .verify: String(localized: "Confirm your email")
        case .forgot: String(localized: "Forgot your password?")
        case .reset: String(localized: "Choose a new password")
        }
    }

    private var actionTitle: String {
        switch model.step {
        case .signIn: String(localized: "Sign in")
        case .signUp: String(localized: "Create account")
        case .verify: String(localized: "Confirm")
        case .forgot: String(localized: "Send code")
        case .reset: String(localized: "Save password")
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch model.step {
        case .signIn, .signUp:
            BrandField(placeholder: String(localized: "Email")) {
                TextField("", text: $model.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .focused($focused, equals: .email)
                    .accessibilityIdentifier("email")
            }
            BrandField(placeholder: String(localized: "Password")) {
                SecureField("", text: $model.password)
                    .textContentType(model.step == .signUp ? .newPassword : .password)
                    .focused($focused, equals: .password)
                    .accessibilityIdentifier("password")
            }
            if model.step == .signUp {
                Text("At least 8 characters.").font(.footnote).foregroundStyle(Brand.foreground.opacity(0.6))
            }
        case .verify:
            codeField
        case .forgot:
            BrandField(placeholder: String(localized: "Email")) {
                TextField("", text: $model.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .focused($focused, equals: .email)
            }
        case .reset:
            codeField
            BrandField(placeholder: String(localized: "New password")) {
                SecureField("", text: $model.newPassword)
                    .textContentType(.newPassword)
                    .focused($focused, equals: .newPassword)
            }
        }
    }

    private var codeField: some View {
        BrandField(placeholder: String(localized: "6-digit code")) {
            TextField("", text: Binding(
                get: { model.code },
                set: { model.code = String($0.filter(\.isNumber).prefix(6)) }
            ))
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .font(.title2.monospacedDigit())
            .focused($focused, equals: .code)
            .accessibilityIdentifier("code")
        }
    }

    @ViewBuilder
    private var links: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.step {
            case .signIn:
                LinkButton(title: String(localized: "Forgot password?")) { model.go(to: .forgot) }
                LinkButton(title: String(localized: "New here? Create an account")) { model.go(to: .signUp) }
            case .signUp:
                LinkButton(title: String(localized: "Have an account? Sign in")) { model.go(to: .signIn) }
            case .verify, .reset:
                LinkButton(title: String(localized: "Send a new code")) { Task { await model.resend() } }
                LinkButton(title: String(localized: "Back to sign in")) { model.go(to: .signIn) }
            case .forgot:
                LinkButton(title: String(localized: "Back to sign in")) { model.go(to: .signIn) }
            }
        }
        .padding(.top, 4)
    }
}

/// A cream input on navy. Emails, passwords and codes read left to right in every language.
private struct BrandField<Field: View>: View {
    let placeholder: String
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(placeholder).font(.footnote.weight(.semibold)).foregroundStyle(Brand.foreground.opacity(0.7))
            field
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Brand.background)
                .tint(Brand.background)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Brand.foreground, in: .rect(cornerRadius: 12))
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}

private struct LinkButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.callout.weight(.semibold))
            .foregroundStyle(Brand.accent)
    }
}
