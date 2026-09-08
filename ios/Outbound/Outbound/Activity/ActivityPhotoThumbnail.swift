import SwiftUI

struct ActivityPhotoThumbnail<Content: View>: View {
    let caption: String
    let isSelected: Bool
    let action: () -> Void
    let content: Content

    init(
        caption: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.caption = caption
        self.isSelected = isSelected
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                content
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                Text(caption)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(8)
            }
            .frame(width: 116, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ActivityPhotoCaptureTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.orange.gradient, in: Circle())
                    .shadow(color: .orange.opacity(0.28), radius: 7, y: 3)

                Text(String(localized: "summary.photos.take", defaultValue: "Take Photo"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 116, height: 104)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.separator).opacity(0.45), lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("TakeFinishPhotoButton")
    }
}
