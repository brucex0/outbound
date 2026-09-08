import SwiftUI

struct ActivityPhotoThumbnail<Content: View>: View {
    let caption: String
    let isSelected: Bool
    let action: () -> Void
    let longPressAction: (() -> Void)?
    let content: Content

    init(
        caption: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        longPressAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.caption = caption
        self.isSelected = isSelected
        self.action = action
        self.longPressAction = longPressAction
        self.content = content()
    }

    var body: some View {
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
        .onTapGesture(perform: action)
        .onLongPressGesture(minimumDuration: 0.35) {
            longPressAction?()
        }
        .accessibilityAddTraits(.isButton)
    }
}

struct ActivityPhotoCaptureTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActivityPhotoActionTile(
                title: String(localized: "summary.photos.take", defaultValue: "Take Photo"),
                systemImage: "camera.fill"
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("TakeFinishPhotoButton")
    }
}

struct ActivityPhotoActionTile: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.orange.gradient, in: Circle())
                .shadow(color: .orange.opacity(0.28), radius: 7, y: 3)

            Text(title)
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
}
