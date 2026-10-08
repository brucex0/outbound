import SwiftUI

struct SocialProfileLink<Label: View>: View {
    @EnvironmentObject private var appNavigationStore: AppNavigationStore
    private let person: TogetherPersonDTO
    private let username: String?
    private let connection: SocialConnectionDTO?
    private let entrySource: String
    private let label: Label

    init(
        person: TogetherPersonDTO,
        username: String? = nil,
        connection: SocialConnectionDTO? = nil,
        entrySource: String,
        @ViewBuilder label: () -> Label
    ) {
        self.person = person
        self.username = username
        self.connection = connection
        self.entrySource = entrySource
        self.label = label()
    }

    init(
        person: SocialPersonDTO,
        connection: SocialConnectionDTO? = nil,
        entrySource: String,
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            person: TogetherPersonDTO(
                id: person.id,
                displayName: person.displayName,
                avatarUrl: person.avatarUrl
            ),
            username: person.username,
            connection: connection,
            entrySource: entrySource,
            label: label
        )
    }

    var body: some View {
        Button {
            appNavigationStore.openSharedDestination(.runnerProfile(
                person,
                username: username,
                connection: connection,
                entrySource: entrySource
            ))
        } label: {
            label
        }
        .buttonStyle(.plain)
    }
}

struct SocialProfileDestination: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analyticsManager) private var analyticsManager

    let person: TogetherPersonDTO
    let username: String?
    let connection: SocialConnectionDTO?
    private var resolvedConnection: SocialConnectionDTO? {
        socialStore.connections.first { $0.person.id == person.id } ?? connection
    }
    let entrySource: String
    @State private var hasTrackedOpen = false
    @State private var isRemovingConnection = false

    var body: some View {
        SocialPersonProfileView(person: person, username: username)
            .safeAreaInset(edge: .bottom) {
                if resolvedConnection?.status == "pending", resolvedConnection?.direction == "incoming" {
                    HStack(spacing: OutboundSpacing.compact) {
                        Button("Decline", role: .destructive) {
                            Task { await removeConnection() }
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .disabled(isRemovingConnection)

                        Button("Accept") {
                            Task { await acceptConnection() }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(isRemovingConnection)
                    }
                    .padding(.horizontal, OutboundSpacing.screen)
                    .padding(.vertical, OutboundSpacing.compact)
                    .background(.bar)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let connection = resolvedConnection, ["accepted", "connected"].contains(connection.status) {
                    ConnectedProfileActions(personID: person.id, connection: connection) { dismiss() }
                }
            }
        .onAppear {
            guard !hasTrackedOpen else { return }
            hasTrackedOpen = true
            Task {
                await analyticsManager?.track(.init(.socialProfileOpened, properties: [
                    .entrySource: .string(entrySource),
                ]))
            }
        }
    }

    private func removeConnection() async {
        guard let connection = resolvedConnection, !isRemovingConnection else { return }
        isRemovingConnection = true
        defer { isRemovingConnection = false }
        if await socialStore.removeConnection(connection) {
            dismiss()
        }
    }

    private func acceptConnection() async {
        guard let connection = resolvedConnection, !isRemovingConnection else { return }
        isRemovingConnection = true
        defer { isRemovingConnection = false }
        if await socialStore.acceptConnection(connection) {
            dismiss()
        }
    }
}

struct ConnectionLinkProfileDestination: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @Environment(\.analyticsManager) private var analyticsManager
    @Environment(\.dismiss) private var dismiss

    let preview: ConnectionLinkProfilePreview
    @State private var relationship: SocialRelationshipDTO?
    @State private var isMutating = false
    @State private var toastMessage: String?
    @State private var toastIsError = false

    init(preview: ConnectionLinkProfilePreview) {
        self.preview = preview
        _relationship = State(initialValue: preview.person.relationship)
    }

    private var person: TogetherPersonDTO {
        TogetherPersonDTO(
            id: preview.person.id,
            displayName: preview.person.displayName,
            avatarUrl: preview.person.avatarUrl
        )
    }

    private var connection: SocialConnectionDTO? {
        guard let relationship else { return nil }
        return SocialConnectionDTO(
            id: relationship.id,
            status: relationship.status,
            direction: relationship.direction,
            person: SocialPersonDTO(
                id: preview.person.id,
                username: preview.person.username,
                displayName: preview.person.displayName,
                avatarUrl: preview.person.avatarUrl
            )
        )
    }

    var body: some View {
        SocialPersonProfileView(person: person, username: preview.person.username)
            .safeAreaInset(edge: .bottom) {
                if !preview.isSelf {
                    relationshipAction
                        .padding(.horizontal, OutboundSpacing.screen)
                        .padding(.vertical, OutboundSpacing.compact)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay(alignment: .top) {
                if let toastMessage {
                    Label(
                        toastMessage,
                        systemImage: toastIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
                    )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(toastIsError ? Color.red : Color.green)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                        .padding(.top, 8)
                }
            }
            .task {
                await analyticsManager?.track(.init(.socialProfileOpened, properties: [
                    .entrySource: .string("connection_qr_code"),
                ]))
            }
            .task(id: toastMessage) {
                guard toastMessage != nil else { return }
                try? await Task.sleep(for: .seconds(2.2))
                guard !Task.isCancelled else { return }
                toastMessage = nil
            }
    }

    @ViewBuilder
    private var relationshipAction: some View {
        switch (relationship?.status, relationship?.direction) {
        case ("accepted", _), ("connected", _):
            if let connection {
                ConnectedProfileActions(personID: person.id, connection: connection) { relationship = nil }
            }
        case ("pending", "outgoing"):
            Text("Sent")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        case ("pending", "incoming"):
            HStack(spacing: OutboundSpacing.compact) {
                Button("Decline", role: .destructive) { removeConnection() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .disabled(isMutating)
                Button("Accept") { acceptConnection() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(isMutating)
            }
        default:
            Button("Connect") { requestConnection() }
                .buttonStyle(.borderedProminent)
                .disabled(isMutating)
        }
    }

    private func requestConnection() {
        guard !isMutating else { return }
        isMutating = true
        Task {
            let response = await socialStore.requestConnection(linkCode: preview.code)
            isMutating = false
            if let response {
                relationship = response.relationship
                toastIsError = false
                toastMessage = String(localized: "Connection request sent")
            } else {
                toastIsError = true
                toastMessage = String(localized: "Could not send the connection request. Try again.")
            }
            await analyticsManager?.track(.init(.connectionQRCodeRequestResult, properties: [
                .result: .string(response.map { analyticsResult($0.result) } ?? "failure"),
            ]))
        }
    }

    private func removeConnection() {
        guard !isMutating, let connection else { return }
        isMutating = true
        Task {
            let succeeded = await socialStore.removeConnection(connection)
            isMutating = false
            if succeeded {
                relationship = nil
            }
        }
    }

    private func acceptConnection() {
        guard !isMutating, let connection else { return }
        isMutating = true
        Task {
            let succeeded = await socialStore.acceptConnection(connection)
            isMutating = false
            if succeeded {
                relationship = SocialRelationshipDTO(id: connection.id, status: "accepted", direction: "incoming")
            }
        }
    }

    private func analyticsResult(_ result: String) -> String {
        switch result {
        case "requested", "already_pending", "incoming_pending", "already_connected", "self": result
        default: "unknown"
        }
    }
}

/// Shared by ordinary and QR profiles so connection safety actions stay visible.
private struct ConnectedProfileActions: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @Environment(\.analyticsManager) private var analyticsManager
    let personID: String
    let connection: SocialConnectionDTO
    let onDisconnected: () -> Void
    @State private var confirmsDisconnect = false
    @State private var showsReportReasons = false
    @State private var isProcessing = false
    @State private var toast: String?

    var body: some View {
        HStack {
            Button(String(localized: "social.profile.disconnect", defaultValue: "Disconnect"), role: .destructive) {
                confirmsDisconnect = true
            }
            .buttonStyle(.bordered)
            Spacer()
            Button(String(localized: "social.profile.report", defaultValue: "Report"), role: .destructive) {
                showsReportReasons = true
            }
            .buttonStyle(.bordered)
        }
        .disabled(isProcessing)
        .padding(.horizontal, OutboundSpacing.screen)
        .padding(.vertical, OutboundSpacing.compact)
        .background(.bar)
        .alert("Remove connection?", isPresented: $confirmsDisconnect) {
            Button(String(localized: "social.profile.disconnect", defaultValue: "Disconnect"), role: .destructive) {
                isProcessing = true
                Task {
                    let success = await socialStore.removeConnection(connection)
                    await analyticsManager?.track(.init(.socialConnectionRemoved, properties: [.result: .string(success ? "success" : "failure")]))
                    isProcessing = false
                    if success { onDisconnected() }
                    else { toast = String(localized: "social.profile.action.failed", defaultValue: "Could not complete the action. Try again.") }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove \(connection.person.displayName) from your connections?")
        }
        .confirmationDialog(String(localized: "social.profile.report.reason", defaultValue: "Why are you reporting this person?"), isPresented: $showsReportReasons, titleVisibility: .visible) {
            ForEach(SocialPostReportReason.allCases) { reason in
                Button(reason.localizedLabel, role: .destructive) {
                    isProcessing = true
                    Task {
                        let success = await socialStore.reportPerson(id: personID, reason: reason.rawValue)
                        await analyticsManager?.track(.init(.socialContentReported, properties: [.result: .string(success ? "success" : "failure")]))
                        isProcessing = false
                        toast = success
                            ? String(localized: "social.profile.report.sent", defaultValue: "Report submitted")
                            : String(localized: "social.profile.action.failed", defaultValue: "Could not complete the action. Try again.")
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(String(localized: "social.report.confirmation", defaultValue: "Select a reason to confirm your private report."))
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast).font(.subheadline).padding(12).background(.regularMaterial, in: Capsule()).offset(y: -55)
            }
        }
        .task(id: toast) {
            guard toast != nil else { return }
            do { try await Task.sleep(for: .seconds(2.5)) } catch { return }
            toast = nil
        }
    }
}
