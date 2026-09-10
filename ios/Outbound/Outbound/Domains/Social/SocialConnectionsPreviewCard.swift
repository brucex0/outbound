import SwiftUI

struct SocialConnectionsPreviewCard: View {
    let connections: [SocialConnectionDTO]
    let isLoading: Bool
    let entrySource: String
    let onOpenAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
            HStack {
                Text(String(localized: "social.connections.title", defaultValue: "Connections"))
                    .socialSectionLabel()
                Spacer()
                Button(String(localized: "social.connections.all", defaultValue: "All"), action: onOpenAll)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OutboundPalette.companion)
            }

            OutboundCard {
                if isLoading {
                    loadingContent
                } else if connections.isEmpty {
                    Button(action: onOpenAll) {
                        Label(
                            String(localized: "social.connections.find", defaultValue: "Find people"),
                            systemImage: "person.badge.plus"
                        )
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: OutboundSpacing.standard) {
                            ForEach(connections.prefix(8)) { connection in
                                SocialProfileLink(
                                    person: connection.person,
                                    connection: connection,
                                    entrySource: entrySource
                                ) {
                                    VStack(spacing: 6) {
                                        ZStack(alignment: .bottomTrailing) {
                                            SocialAvatar(
                                                name: connection.person.displayName,
                                                avatarURL: connection.person.avatarUrl
                                            )
                                            if connection.isInActiveWorkout == true {
                                                Circle()
                                                    .fill(.green)
                                                    .frame(width: 12, height: 12)
                                                    .overlay {
                                                        Circle().stroke(OutboundPalette.surface, lineWidth: 2)
                                                    }
                                            }
                                        }
                                        Text(connection.firstName)
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .frame(width: 58)
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityValue(
                                        connection.isInActiveWorkout == true
                                            ? String(localized: "social.connections.workout_in_progress", defaultValue: "Workout in progress")
                                            : ""
                                    )
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private var loadingContent: some View {
        HStack(spacing: OutboundSpacing.standard) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(spacing: 6) {
                    Circle()
                        .fill(OutboundPalette.companion.opacity(0.12))
                        .frame(width: 40, height: 40)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 48, height: 12)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
