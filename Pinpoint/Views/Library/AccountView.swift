import Auth
import SwiftUI

struct AccountView: View {
    @Environment(SwingLibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @FocusState private var focusedField: AuthField?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if library.isSignedIn {
                        signedIn
                    } else if !PinpointSupabase.isConfigured {
                        unconfigured
                    } else if mode == .checkEmail {
                        checkEmail
                    } else {
                        signedOut
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PinpointTheme.background)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if !library.isSignedIn {
                    focusedField = .email
                }
            }
            .onChange(of: mode) { _, _ in
                errorMessage = nil
                infoMessage = nil
                password = ""
                confirmPassword = ""
                showPassword = false
            }
        }
    }

    private var navigationTitle: String {
        if library.isSignedIn { return "Cloud account" }
        switch mode {
        case .resetPassword: return "Reset password"
        case .checkEmail: return "Confirm email"
        case .signIn, .signUp:
            return library.needsAuth ? "Sign in to continue" : "Cloud account"
        }
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(PinpointTheme.accent.opacity(0.2))
                        .frame(width: 52, height: 52)
                    Text(accountInitial)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(PinpointTheme.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(library.accountEmail ?? "Signed in")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                    Text("Synced with this iPhone")
                        .font(.subheadline)
                        .foregroundStyle(PinpointTheme.secondaryText)
                }
            }

            Text("Swings you upload are stored in the cloud and show up on any device using this account.")
                .foregroundStyle(PinpointTheme.secondaryText)

            Button {
                Task { await library.signOut() }
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var unconfigured: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(
                icon: "cloud",
                title: "Cloud sync isn't set up",
                subtitle: "Add your project URL and anon key to SupabaseConfig.plist, then rebuild."
            )
        }
    }

    private var checkEmail: some View {
        VStack(alignment: .leading, spacing: 20) {
            header(
                icon: "envelope.badge",
                title: "Check your email",
                subtitle: "We sent a confirmation link to \(trimmedEmail). Open it, then come back here to sign in."
            )

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { mode = .signIn }
            } label: {
                Text("Back to sign in")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Use a different email") {
                withAnimation(.easeInOut(duration: 0.18)) { mode = .signUp }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PinpointTheme.accent)
            .frame(maxWidth: .infinity)
        }
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 20) {
            header(icon: mode.icon, title: mode.title, subtitle: modeSubtitle)

            if mode != .resetPassword {
                modePicker
            }

            VStack(spacing: 12) {
                AuthFieldView(
                    icon: "envelope",
                    title: "Email",
                    text: $email,
                    field: .email,
                    focusedField: $focusedField,
                    contentType: .username,
                    keyboard: .emailAddress,
                    submitLabel: mode == .resetPassword ? .send : .next,
                    onSubmit: advanceFromEmail
                )

                if mode != .resetPassword {
                    AuthFieldView(
                        icon: "lock",
                        title: "Password",
                        text: $password,
                        field: .password,
                        focusedField: $focusedField,
                        isSecure: !showPassword,
                        contentType: mode == .signUp ? .newPassword : .password,
                        submitLabel: mode == .signUp ? .next : .go,
                        trailing: {
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(PinpointTheme.secondaryText)
                            }
                            .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                        },
                        onSubmit: advanceFromPassword
                    )
                }

                if mode == .signUp {
                    AuthFieldView(
                        icon: "lock.fill",
                        title: "Confirm password",
                        text: $confirmPassword,
                        field: .confirmPassword,
                        focusedField: $focusedField,
                        isSecure: !showPassword,
                        contentType: .newPassword,
                        submitLabel: .go,
                        onSubmit: { Task { await submit() } }
                    )
                }
            }

            if let hint = fieldHint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(PinpointTheme.secondaryText)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let infoMessage {
                Text(infoMessage)
                    .font(.subheadline)
                    .foregroundStyle(PinpointTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isWorking ? mode.workingTitle : mode.actionTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.45)

            secondaryActions
        }
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach([AuthMode.signIn, AuthMode.signUp], id: \.self) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { mode = item }
                } label: {
                    Text(item.pickerTitle)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            mode == item ? PinpointTheme.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var secondaryActions: some View {
        VStack(spacing: 12) {
            switch mode {
            case .signIn:
                Button("Forgot password?") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        mode = .resetPassword
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PinpointTheme.accent)
            case .resetPassword:
                Button("Back to sign in") {
                    withAnimation(.easeInOut(duration: 0.18)) { mode = .signIn }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PinpointTheme.accent)
            case .signUp, .checkEmail:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func header(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(PinpointTheme.accent)
                .frame(width: 44, height: 44)
                .background(PinpointTheme.accent.opacity(0.16), in: Circle())

            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(PinpointTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeSubtitle: String {
        if library.needsAuth, mode == .signIn {
            return "Sign in to upload this swing and keep it in the cloud."
        }
        return mode.subtitle
    }

    private var accountInitial: String {
        let source = library.accountEmail?.first.map(String.init) ?? "P"
        return source.uppercased()
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isEmailValid: Bool {
        let parts = trimmedEmail.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        return parts[1].contains(".") && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".")
    }

    private var canSubmit: Bool {
        guard !isWorking, isEmailValid else { return false }
        switch mode {
        case .signIn:
            return password.count >= 6
        case .signUp:
            return password.count >= 6 && password == confirmPassword
        case .resetPassword:
            return true
        case .checkEmail:
            return false
        }
    }

    private var fieldHint: String? {
        switch mode {
        case .signUp where !password.isEmpty && password.count < 6:
            return "Use at least 6 characters."
        case .signUp where !confirmPassword.isEmpty && password != confirmPassword:
            return "Passwords don't match."
        case .signUp:
            return "Use at least 6 characters."
        default:
            return nil
        }
    }

    private func advanceFromEmail() {
        if mode == .resetPassword {
            Task { await submit() }
        } else {
            focusedField = .password
        }
    }

    private func advanceFromPassword() {
        if mode == .signUp {
            focusedField = .confirmPassword
        } else {
            Task { await submit() }
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        defer { isWorking = false }

        do {
            switch mode {
            case .signIn:
                try await library.signIn(email: trimmedEmail, password: password)
                dismiss()
            case .signUp:
                let signedIn = try await library.signUp(email: trimmedEmail, password: password)
                if signedIn {
                    dismiss()
                } else {
                    mode = .checkEmail
                }
            case .resetPassword:
                try await library.sendPasswordReset(email: trimmedEmail)
                infoMessage = "If an account exists for \(trimmedEmail), you'll get a reset link shortly."
            case .checkEmail:
                break
            }
        } catch {
            errorMessage = AuthUserMessage.from(error)
        }
    }
}

private enum AuthMode: Hashable {
    case signIn
    case signUp
    case resetPassword
    case checkEmail

    var pickerTitle: String {
        switch self {
        case .signIn: return "Sign in"
        case .signUp: return "Create account"
        default: return ""
        }
    }

    var title: String {
        switch self {
        case .signIn: return "Welcome back"
        case .signUp: return "Create an account"
        case .resetPassword: return "Forgot your password?"
        case .checkEmail: return "Check your email"
        }
    }

    var subtitle: String {
        switch self {
        case .signIn:
            return "Sign in to upload swings and open them on any iPhone."
        case .signUp:
            return "Save swings in the cloud so you can review them later on another device."
        case .resetPassword:
            return "Enter the email for your account. We'll send a link to choose a new password."
        case .checkEmail:
            return "Open the confirmation link we sent, then come back here to sign in."
        }
    }

    var icon: String {
        switch self {
        case .signIn: return "cloud"
        case .signUp: return "person.badge.plus"
        case .resetPassword: return "key"
        case .checkEmail: return "envelope.badge"
        }
    }

    var actionTitle: String {
        switch self {
        case .signIn: return "Sign in"
        case .signUp: return "Create account"
        case .resetPassword: return "Send reset link"
        case .checkEmail: return "Back to sign in"
        }
    }

    var workingTitle: String {
        switch self {
        case .signIn: return "Signing in…"
        case .signUp: return "Creating account…"
        case .resetPassword: return "Sending…"
        case .checkEmail: return "Working…"
        }
    }
}

private enum AuthField: Hashable {
    case email
    case password
    case confirmPassword
}

private struct AuthFieldView<Trailing: View>: View {
    let icon: String
    let title: String
    @Binding var text: String
    let field: AuthField
    var focusedField: FocusState<AuthField?>.Binding
    var isSecure = false
    var contentType: UITextContentType
    var keyboard: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .next
    @ViewBuilder var trailing: () -> Trailing
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(PinpointTheme.secondaryText)
                .frame(width: 18)

            Group {
                if isSecure {
                    SecureField(title, text: $text, prompt: prompt)
                } else {
                    TextField(title, text: $text, prompt: prompt)
                }
            }
            .textContentType(contentType)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(submitLabel)
            .focused(focusedField, equals: field)
            .onSubmit(onSubmit)
            .foregroundStyle(.white)
            .tint(PinpointTheme.accent)

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(focusedField.wrappedValue == field ? PinpointTheme.accent.opacity(0.7) : PinpointTheme.hairline, lineWidth: 1)
        }
    }

    private var prompt: Text {
        Text(title).foregroundStyle(.white.opacity(0.35))
    }
}

extension AuthFieldView where Trailing == EmptyView {
    init(
        icon: String,
        title: String,
        text: Binding<String>,
        field: AuthField,
        focusedField: FocusState<AuthField?>.Binding,
        isSecure: Bool = false,
        contentType: UITextContentType,
        keyboard: UIKeyboardType = .default,
        submitLabel: SubmitLabel = .next,
        onSubmit: @escaping () -> Void
    ) {
        self.init(
            icon: icon,
            title: title,
            text: text,
            field: field,
            focusedField: focusedField,
            isSecure: isSecure,
            contentType: contentType,
            keyboard: keyboard,
            submitLabel: submitLabel,
            trailing: { EmptyView() },
            onSubmit: onSubmit
        )
    }
}

private enum AuthUserMessage {
    static func from(_ error: Error) -> String {
        if let auth = error as? AuthError {
            switch auth.errorCode {
            case .invalidCredentials:
                return "Wrong email or password."
            case .emailExists, .userAlreadyExists:
                return "An account with that email already exists. Sign in instead."
            case .emailNotConfirmed:
                return "Confirm your email first. Check your inbox for a link from Pinpoint."
            case .weakPassword:
                return "Choose a stronger password with at least 6 characters."
            case .overRequestRateLimit, .overEmailSendRateLimit:
                return "Too many attempts. Wait a minute and try again."
            case .userBanned:
                return "This account is disabled."
            case .signupDisabled:
                return "New accounts are turned off right now."
            case .userNotFound:
                return "No account found for that email."
            default:
                break
            }
        }

        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("invalid login credentials") {
            return "Wrong email or password."
        }
        if text.localizedCaseInsensitiveContains("already registered")
            || text.localizedCaseInsensitiveContains("already exists") {
            return "An account with that email already exists. Sign in instead."
        }
        if text.localizedCaseInsensitiveContains("email not confirmed") {
            return "Confirm your email first. Check your inbox for a link from Pinpoint."
        }
        return text
    }
}
