import SwiftUI

struct SocialProfileLink<Label: View>: View {
    private let person: TogetherPersonDTO
    private let username: String?
    private let entrySource: String
    private let label: Label

    init(
        person: TogetherPersonDTO,
        username: String? = nil,
        entrySource: String,
        @ViewBuilder label: () -> Label
    ) {
        self.person = person
        self.username = username
        self.entrySource = entrySource
        self.label = label()
    }

    init(
        person: SocialPersonDTO,
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
            entrySource: entrySource,
            label: label
        )
    }

    var body: some View {
        NavigationLink {
            SocialProfileDestination(
                person: person,
                username: username,
                entrySource: entrySource
            )
        } label: {
            label
        }
        .buttonStyle(.plain)
    }
}

private struct SocialProfileDestination: View {
    @Environment(\.analyticsManager) private var analyticsManager

    let person: TogetherPersonDTO
    let username: String?
    let entrySource: String
    @State private var hasTrackedOpen = false

    var body: some View {
        SocialPersonProfileView(person: person, username: username)
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
}
