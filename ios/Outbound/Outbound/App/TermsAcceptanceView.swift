import SwiftUI

struct TermsAcceptanceView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var authStore: AuthStore
    @State private var confirmsAccountDeletion = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(OutboundPalette.companion)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("terms.acceptance.title")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.center)

                    Text("terms.acceptance.body")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 0) {
                    legalRow(.terms, title: String(localized: "legal.terms.title"), systemImage: "doc.text")
                    Divider().padding(.leading, 44)
                    legalRow(.privacy, title: String(localized: "legal.privacy.title"), systemImage: "hand.raised")
                }
                .padding(.horizontal, 16)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(spacing: 12) {
                    Button {
                        acceptTerms()
                    } label: {
                        Group {
                            if authStore.isBusy {
                                ProgressView().tint(.white)
                            } else {
                                Text("terms.acceptance.accept")
                            }
                        }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(authStore.isBusy)

                    if let error = authStore.authError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button("Sign out") { authStore.signOut() }
                        .disabled(authStore.isBusy)

                    Button(String(localized: "account.delete.title"), role: .destructive) {
                        confirmsAccountDeletion = true
                    }
                    .font(.footnote)
                    .disabled(authStore.isBusy)
                }

                Text("terms.acceptance.footer")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.vertical, 42)
            .frame(maxWidth: .infinity)
        }
        .background(OutboundPalette.background.ignoresSafeArea())
        .task {
            await analyticsManager?.track(.init(.termsAcceptancePresented, properties: [
                .termsVersion: .integer(authStore.currentTermsVersion),
            ]))
        }
        .confirmationDialog(
            "Permanently delete your account?",
            isPresented: $confirmsAccountDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete Account and Data", role: .destructive) {
                Task { await authStore.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your Plainstride account, synced activities, plans, profile, social data, and locally stored Plainstride data. This cannot be undone.")
        }
    }

    private func legalRow(_ document: PlainstrideLegalDocument, title: String, systemImage: String) -> some View {
        Button {
            Task {
                await analyticsManager?.track(.init(.legalDocumentOpened, properties: [
                    .documentType: .string(document.rawValue),
                    .entrySource: .string("terms_gate"),
                ]))
            }
            openURL(document.url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 22)
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func acceptTerms() {
        let version = authStore.currentTermsVersion
        Task {
            let accepted = await authStore.acceptCurrentTerms()
            await analyticsManager?.track(.init(.termsAcceptanceCompleted, properties: [
                .termsVersion: .integer(version),
                .result: .string(accepted ? "success" : "failure"),
            ]))
        }
    }
}
