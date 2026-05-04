import SwiftUI

struct AuthView: View {
    @EnvironmentObject var authStore: AuthStore

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
                        Text("Sign in with Apple or Google.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Button {
                            Task { await authStore.signInWithApple() }
                        } label: {
                            Label("Continue with Apple", systemImage: "apple.logo")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.black)
                        .disabled(!authStore.isAppleSignInAvailable || authStore.isBusy)

                        Button {
                            Task { await authStore.signInWithGoogle() }
                        } label: {
                            Label("Continue with Google", systemImage: "globe")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .disabled(!authStore.isFirebaseConfigured || authStore.isBusy)

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

    private var helperText: String {
        if authStore.isFirebaseConfigured {
            if let pendingLink = authStore.pendingFederatedLink {
                return "\(pendingLink.providerName) matches an existing account for \(pendingLink.email). Continue with the provider already on that account and Outbound will connect both methods."
            }

            if !authStore.isAppleSignInAvailable {
                return "Google sign-in is available. Apple sign-in needs a provisioning profile with the Sign in with Apple capability."
            }

            return "Apple and Google accounts are linked only after you prove the existing sign-in method."
        }

        return "This build needs GoogleService-Info.plist before Firebase sign-in can work."
    }

    private var authBackendMessage: String {
        if authStore.isFirebaseConfigured {
            return "Firebase is configured, so this build uses cloud-backed provider accounts."
        }

        return "Firebase is not configured in this checkout yet. Place GoogleService-Info.plist under ios/Outbound/Outbound to enable real sign-in."
    }
}
