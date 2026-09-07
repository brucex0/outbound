import SwiftUI
import UIKit

struct AccountTransferView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @State private var intent: IdentityLinkIntentResponse?
    @State private var isLoading = false
    @State private var alertMessage: String?
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                Text(String(localized: "account_transfer.explanation", table: "AccountTransfer"))
                    .foregroundStyle(.secondary)
            }

            if let intent {
                Section(String(localized: "account_transfer.code_header", table: "AccountTransfer")) {
                    Text(intent.code)
                        .font(.title2.monospaced().weight(.semibold))
                        .textSelection(.enabled)
                        .accessibilityLabel(intent.code.replacingOccurrences(of: "-", with: " "))
                    Text(String(localized: "account_transfer.expiry", table: "AccountTransfer"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        UIPasteboard.general.string = intent.code
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        Label(String(localized: "account_transfer.copy", table: "AccountTransfer"), systemImage: "doc.on.doc")
                    }
                    ShareLink(item: intent.url) {
                        Label(String(localized: "account_transfer.share", table: "AccountTransfer"), systemImage: "square.and.arrow.up")
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        Task { await analyticsManager?.track(.init(.accountTransferShared, properties: [.sourceType: .string("link")])) }
                    })
                }
            }

            Section {
                Button {
                    Task { await createIntent() }
                } label: {
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(String(localized: intent == nil ? "account_transfer.create" : "account_transfer.replace", table: "AccountTransfer"))
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isLoading)
            } footer: {
                Text(String(localized: "account_transfer.security_note", table: "AccountTransfer"))
            }
        }
        .navigationTitle(String(localized: "account_transfer.title", table: "AccountTransfer"))
        .overlay(alignment: .bottom) {
            if copied {
                Text(String(localized: "account_transfer.copied", table: "AccountTransfer"))
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: copied)
        .alert(String(localized: "account_transfer.error_title", table: "AccountTransfer"), isPresented: Binding(
            get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } }
        )) {
            Button(String(localized: "account_transfer.ok", table: "AccountTransfer"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func createIntent() async {
        isLoading = true
        defer { isLoading = false }
        do {
            intent = try await APIClient.shared.createIdentityLinkIntent()
            await analyticsManager?.track(.init(.accountTransferIntentCreated, properties: [.result: .string("success")]))
        } catch {
            alertMessage = String(localized: "account_transfer.error_message", table: "AccountTransfer")
            await analyticsManager?.track(.init(.accountTransferIntentCreated, properties: [
                .result: .string("failure"), .errorCategory: .string("request_failed")
            ]))
        }
    }
}
