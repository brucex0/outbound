import SwiftUI

struct SocialProfileLink<Label: View>: View {
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
        NavigationLink {
            SocialProfileDestination(
                person: person,
                username: username,
                connection: connection,
                entrySource: entrySource
            )
        } label: {
            label
        }
        .buttonStyle(.plain)
    }
}

private struct SocialProfileDestination: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analyticsManager) private var analyticsManager

    let person: TogetherPersonDTO
    let username: String?
    let connection: SocialConnectionDTO?
    let entrySource: String
    @State private var hasTrackedOpen = false
    @State private var showsRemoveConfirmation = false
    @State private var isRemovingConnection = false

    var body: some View {
        SocialPersonProfileView(person: person, username: username)
            .toolbar {
                if connection?.status == "accepted" {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Remove connection", role: .destructive) {
                                showsRemoveConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("Profile actions")
                    }
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
        .alert("Remove connection?", isPresented: $showsRemoveConfirmation) {
            Button("Remove", role: .destructive) {
                Task { await removeConnection() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove \(person.displayName) from your connections?")
        }
    }

    private func removeConnection() async {
        guard let connection, !isRemovingConnection else { return }
        isRemovingConnection = true
        defer { isRemovingConnection = false }
        if await socialStore.removeConnection(connection) {
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
    @State private var showsRemoveConfirmation = false

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
                if relationship?.status == "accepted" {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Remove connection", role: .destructive) {
                                showsRemoveConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("Profile actions")
                    }
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
            .alert("Remove connection?", isPresented: $showsRemoveConfirmation) {
                Button("Remove", role: .destructive) {
                    removeConnection()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to remove \(person.displayName) from your connections?")
            }
    }

    @ViewBuilder
    private var relationshipAction: some View {
        switch (relationship?.status, relationship?.direction) {
        case ("accepted", _):
            Text("Connected")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        case ("pending", "outgoing"):
            Text("Sent")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        case ("pending", "incoming"):
            Button("Accept") { acceptConnection() }
                .buttonStyle(.borderedProminent)
                .disabled(isMutating)
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
