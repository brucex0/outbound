import SwiftUI

struct CompanionNotificationPreview: View {
    let item: NotificationCenterPresentationItem
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.presentation.tier == .cheersAndMilestones ? "heart.fill" : "envelope.fill")
                        .foregroundStyle(OutboundPalette.companion)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedGroupNotificationMessage(item.primary))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(3)
                        if item.additionalCount > 0 {
                            Text(String(
                                format: String(localized: "safety.inbox.additional_count", defaultValue: "%d more"),
                                locale: .autoupdatingCurrent,
                                item.additionalCount
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.primary)
                .padding(.leading, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("fox.companion.preview")
            .accessibilityHint(String(localized: "fox.companion.open_notification", defaultValue: "Opens this notification in Notification Center"))

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "fox.companion.dismiss_preview", defaultValue: "Dismiss notification preview"))
            .accessibilityIdentifier("fox.companion.dismiss")
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }
}
