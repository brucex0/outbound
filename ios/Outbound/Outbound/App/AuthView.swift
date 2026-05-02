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
                        Text("Sign in with Google, email, or phone number.")
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

                        if authStore.isFirebaseConfigured {
                            HStack {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.25))
                                    .frame(height: 1)
                                Text("or")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.25))
                                    .frame(height: 1)
                            }

                            Button {
                                Task { await authStore.signInWithGoogle() }
                            } label: {
                                Label("Continue with Google", systemImage: "globe")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                            .disabled(authStore.isBusy)
                        }

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
            if mode == .createAccount {
                return "Google sign-in creates the account automatically on first use. Email and phone accounts still use the password flow below."
            }

            if mode == .signIn {
                return "Google sign-in uses Firebase's hosted OAuth flow. Phone logins still use the same password system as email accounts, without SMS verification."
            }
        }

        if mode == .signIn {
            return "Without Firebase, password accounts are stored only on this device in local secure storage."
        }

        return "Creating an account right now stores the login only on this device, so it will not sync to other phones."
    }

    private var authBackendMessage: String {
        if authStore.isFirebaseConfigured {
            return "Firebase is configured, so this build uses cloud-backed accounts and Google sign-in."
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
