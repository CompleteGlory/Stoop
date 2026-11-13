import SwiftUI

/// The email sheet: sign in, create an account, enter a code, or reset the password.
struct EmailAuthView: View {
    @State private var model: EmailAuthViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Field?

    enum Field: Hashable { case email, username, password, confirmPassword, code, newPassword }

    init(session: SessionStore) {
        _model = State(initialValue: EmailAuthViewModel(session: session))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if model.step == .signIn || model.step == .signUp { modeSwitch }
                    header
                    VStack(alignment: .leading, spacing: 16) { fields }
                    if let error = model.errorText { ErrorBanner(text: error) }
                    Button {
                        Task { await model.submit() }
                    } label: {
                        if model.isBusy { ProgressView().tint(Brand.ink) } else { Text(actionTitle) }
                    }
                    .buttonStyle(BrandButtonStyle())
                    .disabled(!model.canSubmit)
                    .accessibilityIdentifier("emailSubmit")
                    if model.step == .signUp { LegalNotice().frame(maxWidth: .infinity) }
                    links
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
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
            .animation(.snappy, value: model.errorText)
        }
    }

    // MARK: top

    /// Sign in or create an account, side by side, so neither hides behind a link at the bottom.
    private var modeSwitch: some View {
        HStack(spacing: 4) {
            modeButton(tr("Sign in"), step: .signIn)
            modeButton(tr("Create account"), step: .signUp)
        }
        .padding(4)
        .background(Brand.surface, in: .capsule)
    }

    private func modeButton(_ title: String, step: EmailAuthViewModel.Step) -> some View {
        let selected = model.step == step
        return Button {
            if !selected { model.go(to: step) }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .foregroundStyle(selected ? Brand.ink : Brand.foreground.opacity(0.7))
                .background(selected ? Brand.accent : .clear, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: headerIcon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Brand.ink)
                .frame(width: 48, height: 48)
                .background(Brand.accent, in: .rect(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.infoText ?? subtitle)
                    .font(.callout)
                    .foregroundStyle(Brand.foreground.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var headerIcon: String {
        switch model.step {
        case .signIn: "person.crop.circle"
        case .signUp: "person.crop.circle.badge.plus"
        case .verify: "envelope.badge"
        case .forgot: "key"
        case .reset: "lock.rotation"
        }
    }

    private var title: String {
        switch model.step {
        case .signIn: tr("Sign in with email")
        case .signUp: tr("Create your account")
        case .verify: tr("Confirm your email")
        case .forgot: tr("Forgot your password?")
        case .reset: tr("Choose a new password")
        }
    }

    private var subtitle: String {
        switch model.step {
        case .signIn: tr("Welcome back. Use the email and password you signed up with.")
        case .signUp: tr("Pick a username friends can find you by.")
        case .verify: tr("Enter the 6-digit code we emailed you.")
        case .forgot: tr("We'll email you a code to choose a new password.")
        case .reset: tr("Enter the code from the email and your new password.")
        }
    }

    private var actionTitle: String {
        switch model.step {
        case .signIn: tr("Sign in")
        case .signUp: tr("Create account")
        case .verify: tr("Confirm")
        case .forgot: tr("Send code")
        case .reset: tr("Save password")
        }
    }

    private var usernameIsWrong: Bool {
        [.invalid, .taken, .reserved].contains(model.usernameCheck.status)
    }

    // MARK: fields

    @ViewBuilder
    private var fields: some View {
        switch model.step {
        case .signIn:
            emailField
                .submitLabel(.next)
                .onSubmit { focused = .password }
            VStack(alignment: .trailing, spacing: 10) {
                PasswordInput(label: tr("Password"), text: $model.password, field: .password, focused: $focused,
                              contentType: .password, identifier: "password")
                    .submitLabel(.go)
                    .onSubmit { Task { await model.submit() } }
                LinkButton(title: tr("Forgot password?")) { model.go(to: .forgot) }
                    .font(.footnote.weight(.semibold))
            }
        case .signUp:
            emailField
                .submitLabel(.next)
                .onSubmit { focused = .username }
            VStack(alignment: .leading, spacing: 8) {
                AuthField(label: tr("Username"), icon: "at", isFocused: focused == .username, isInvalid: usernameIsWrong) {
                    TextField("", text: $model.username, prompt: Text(verbatim: "yourname").foregroundStyle(Brand.ink.opacity(0.35)))
                        .textContentType(.username)
                        .focused($focused, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                        .accessibilityIdentifier("username")
                }
                UsernameStatusLine(status: model.usernameCheck.status)
                    .animation(.snappy, value: model.usernameCheck.status)
            }
            VStack(alignment: .leading, spacing: 8) {
                PasswordInput(label: tr("Password"), text: $model.password, field: .password, focused: $focused,
                              contentType: .newPassword, identifier: "password")
                    .submitLabel(.next)
                    .onSubmit { focused = .confirmPassword }
                StrengthBar(strength: model.passwordStrength)
            }
            VStack(alignment: .leading, spacing: 8) {
                PasswordInput(label: tr("Confirm password"), text: $model.confirmPassword, field: .confirmPassword,
                              focused: $focused, contentType: .newPassword, identifier: "confirmPassword",
                              isInvalid: model.passwordsMismatch)
                    .submitLabel(.go)
                    .onSubmit { Task { await model.submit() } }
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
            emailField
                .submitLabel(.send)
                .onSubmit { Task { await model.submit() } }
        case .reset:
            codeField
            VStack(alignment: .leading, spacing: 8) {
                PasswordInput(label: tr("New password"), text: $model.newPassword, field: .newPassword,
                              focused: $focused, contentType: .newPassword, identifier: "newPassword")
                    .submitLabel(.go)
                    .onSubmit { Task { await model.submit() } }
                StrengthBar(strength: PasswordStrength(model.newPassword))
            }
        }
    }

    private var emailField: some View {
        AuthField(label: tr("Email"), icon: "envelope", isFocused: focused == .email) {
            TextField("", text: $model.email, prompt: Text(verbatim: "you@example.com").foregroundStyle(Brand.ink.opacity(0.35)))
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .focused($focused, equals: .email)
                .accessibilityIdentifier("email")
        }
    }

    private var codeField: some View {
        AuthField(label: tr("6-digit code"), icon: "number", isFocused: focused == .code) {
            TextField("", text: Binding(
                get: { model.code },
                set: { model.code = String($0.filter(\.isNumber).prefix(6)) }
            ), prompt: Text(verbatim: "000000").foregroundStyle(Brand.ink.opacity(0.25)))
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .font(.title3.monospacedDigit().weight(.semibold))
            .tracking(6)
            .focused($focused, equals: .code)
            .accessibilityIdentifier("code")
        }
    }

    @ViewBuilder
    private var links: some View {
        switch model.step {
        case .signIn, .signUp:
            EmptyView()
        case .verify, .reset:
            HStack {
                LinkButton(title: tr("Send a new code")) { Task { await model.resend() } }
                Spacer()
                LinkButton(title: tr("Back to sign in")) { model.go(to: .signIn) }
            }
        case .forgot:
            LinkButton(title: tr("Back to sign in")) { model.go(to: .signIn) }
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: building blocks

/// A labelled input with an icon. The border turns gold while typing and red when the value is wrong.
/// Emails, passwords and codes read left to right in every language.
struct AuthField<Input: View, Accessory: View>: View {
    let label: String
    let icon: String
    let isFocused: Bool
    let isInvalid: Bool
    let input: Input
    let accessory: Accessory

    init(label: String, icon: String, isFocused: Bool = false, isInvalid: Bool = false,
         @ViewBuilder input: () -> Input, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.label = label
        self.icon = icon
        self.isFocused = isFocused
        self.isInvalid = isInvalid
        self.input = input()
        self.accessory = accessory()
    }

    private var borderColor: Color {
        if isInvalid { return Brand.negative.text }
        return isFocused ? Brand.accent : Brand.ink.opacity(0.08)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Brand.foreground.opacity(0.75))
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isFocused ? Brand.accent : Brand.ink.opacity(0.45))
                    .frame(width: 22)
                    .accessibilityHidden(true)
                input
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(Brand.ink)
                    .tint(Brand.ink)
                accessory
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(Brand.field, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(borderColor, lineWidth: isFocused || isInvalid ? 2 : 1)
            }
            .environment(\.layoutDirection, .leftToRight)
            .animation(.snappy(duration: 0.2), value: isFocused)
        }
    }
}

/// A password input with an eye button that shows or hides what was typed.
struct PasswordInput: View {
    let label: String
    @Binding var text: String
    let field: EmailAuthView.Field
    let focused: FocusState<EmailAuthView.Field?>.Binding
    let contentType: UITextContentType
    let identifier: String
    let isInvalid: Bool
    @State private var isVisible = false

    init(label: String, text: Binding<String>, field: EmailAuthView.Field, focused: FocusState<EmailAuthView.Field?>.Binding,
         contentType: UITextContentType, identifier: String, isInvalid: Bool = false) {
        self.label = label
        _text = text
        self.field = field
        self.focused = focused
        self.contentType = contentType
        self.identifier = identifier
        self.isInvalid = isInvalid
    }

    var body: some View {
        AuthField(label: label, icon: "lock", isFocused: focused.wrappedValue == field, isInvalid: isInvalid) {
            Group {
                if isVisible {
                    TextField("", text: $text)
                } else {
                    SecureField("", text: $text)
                }
            }
            .textContentType(contentType)
            .focused(focused, equals: field)
            .accessibilityIdentifier(identifier)
        } accessory: {
            Button {
                let wasTyping = focused.wrappedValue == field
                isVisible.toggle()
                // swapping the field drops the keyboard; keep typing where the person was
                if wasTyping { focused.wrappedValue = field }
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Brand.ink.opacity(0.55))
                    .frame(width: 36, height: 36)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isVisible ? tr("Hide password") : tr("Show password")))
            .accessibilityIdentifier("\(identifier)Visibility")
        }
    }
}

/// What went wrong, in a tinted box with an icon so it can't be missed.
private struct ErrorBanner: View {
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Brand.negative.text)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.negative.fill, in: .rect(cornerRadius: 12))
        .transition(.opacity.combined(with: .move(edge: .top)))
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
