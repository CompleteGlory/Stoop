import SwiftUI

/// The email sheet: sign in, create an account, enter a code, or reset the password.
struct EmailAuthView: View {
    @State private var model: EmailAuthViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Field?

    private enum Field { case email, username, password, confirmPassword, code, newPassword }

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
        case .signIn:
            emailField
            BrandField(placeholder: String(localized: "Password")) {
                SecureField("", text: $model.password)
                    .textContentType(.password)
                    .focused($focused, equals: .password)
                    .accessibilityIdentifier("password")
            }
        case .signUp:
            emailField
                .submitLabel(.next)
                .onSubmit { focused = .username }
            VStack(alignment: .leading, spacing: 8) {
                BrandField(placeholder: String(localized: "Username")) {
                    HStack(spacing: 2) {
                        Text(verbatim: "@").foregroundStyle(Brand.background.opacity(0.5))
                        TextField("", text: $model.username)
                            .textContentType(.username)
                            .focused($focused, equals: .username)
                            .submitLabel(.next)
                            .onSubmit { focused = .password }
                            .accessibilityIdentifier("username")
                    }
                }
                UsernameStatusLine(status: model.usernameCheck.status)
                    .animation(.snappy, value: model.usernameCheck.status)
            }
            VStack(alignment: .leading, spacing: 8) {
                BrandField(placeholder: String(localized: "Password")) {
                    SecureField("", text: $model.password)
                        .textContentType(.newPassword)
                        .focused($focused, equals: .password)
                        .submitLabel(.next)
                        .onSubmit { focused = .confirmPassword }
                        .accessibilityIdentifier("password")
                }
                StrengthBar(strength: model.passwordStrength)
            }
            VStack(alignment: .leading, spacing: 8) {
                BrandField(placeholder: String(localized: "Confirm password")) {
                    SecureField("", text: $model.confirmPassword)
                        .textContentType(.newPassword)
                        .focused($focused, equals: .confirmPassword)
                        .submitLabel(.go)
                        .onSubmit { Task { await model.submit() } }
                        .accessibilityIdentifier("confirmPassword")
                }
                if model.passwordsMismatch {
                    Label("Passwords don't match.", systemImage: "xmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Brand.negative.text)
                } else if !model.confirmPassword.isEmpty {
                    Label("Passwords match.", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Brand.positive.text)
                }
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

    private var emailField: some View {
        BrandField(placeholder: String(localized: "Email")) {
            TextField("", text: $model.email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .focused($focused, equals: .email)
                .accessibilityIdentifier("email")
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

/// Four segments that fill and change colour as the password gets harder to guess.
private struct StrengthBar: View {
    let strength: PasswordStrength

    private var color: Color {
        switch strength {
        case .empty: Brand.foreground.opacity(0.2)
        case .tooShort, .weak: Brand.negative.text
        case .fair: Brand.accent
        case .good, .strong: Brand.positive.text
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index < strength.filledSegments ? color : Brand.foreground.opacity(0.15))
                        .frame(height: 6)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .animation(.snappy, value: strength)
            if strength != .empty {
                HStack(spacing: 6) {
                    Text(strength.label).font(.footnote.weight(.semibold)).foregroundStyle(color)
                    if let hint = strength.hint {
                        Text(hint).font(.footnote).foregroundStyle(Brand.foreground.opacity(0.6))
                    }
                }
            } else {
                Text("At least 8 characters.").font(.footnote).foregroundStyle(Brand.foreground.opacity(0.6))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Password strength: \(strength.label)"))
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
