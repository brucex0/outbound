import SwiftUI

struct AuthView: View {
    @EnvironmentObject var authStore: AuthStore
    @State private var identifier = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var mode: Mode = .signIn

    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case createAccount = "Create Account"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 24)

                    VStack(spacing: 12) {
                        Image(systemName: "figure.run.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.orange)
                        Text("Outbound")
                            .font(.largeTitle.bold())
                        Text("Sign in with email or phone number and a password.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email or Phone")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("name@example.com or +1 415 555 1212", text: $identifier)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .textContentType(.username)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            SecureField("At least 6 characters", text: $password)
                                .textContentType(mode == .signIn ? .password : .newPassword)
                                .textFieldStyle(.roundedBorder)
                        }

                        if mode == .createAccount {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Confirm Password")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                SecureField("Repeat password", text: $confirmPassword)
                                    .textContentType(.newPassword)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        Button(actionTitle) {
                            Task { await submit() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(
                            authStore.isBusy ||
                            identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            password.isEmpty
                        )

                        Text(helperText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))

                    VStack(spacing: 12) {
                        Text(authBackendMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if !authStore.isFirebaseConfigured {
                            Button("Continue Without Account") { authStore.startLocalSession() }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                        }
                    }

                    if authStore.isBusy {
                        ProgressView()
                            .tint(.orange)
                    }

                    if let error = authStore.authError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Spacer(minLength: 24)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var actionTitle: String {
        mode == .signIn ? "Sign In" : "Create Account"
    }

    private var helperText: String {
        if authStore.isFirebaseConfigured {
            if mode == .signIn {
                return "Phone logins use the same password system as email accounts, without SMS verification."
            }

            return "Creating an account with a phone number stores it behind the same Firebase email/password provider, so users can sign in later with that same phone number and password."
        }

        if mode == .signIn {
            return "Without Firebase, password accounts are stored only on this device in local secure storage."
        }

        return "Creating an account right now stores the login only on this device, so it will not sync to other phones."
    }

    private var authBackendMessage: String {
        if authStore.isFirebaseConfigured {
            return "Firebase is configured, so this build uses cloud-backed accounts."
        }

        return "Firebase is missing on this build, so accounts created here are stored only on this device."
    }

    private func submit() async {
        if mode == .signIn {
            await authStore.signIn(identifier: identifier, password: password)
        } else {
            await authStore.createAccount(
                identifier: identifier,
                password: password,
                confirmPassword: confirmPassword
            )
        }
    }
}
