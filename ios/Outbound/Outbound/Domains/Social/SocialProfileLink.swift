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
