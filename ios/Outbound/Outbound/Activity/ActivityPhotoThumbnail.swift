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
        Group {
            // Selected tiles reserve long press for native drag and drop.
            if isSelected || longPressAction == nil {
                thumbnail.onTapGesture(perform: action)
            } else {
                thumbnail.gesture(
                    LongPressGesture(minimumDuration: 0.35)
                        .exclusively(before: TapGesture())
                        .onEnded { gesture in
                            switch gesture {
                            case .first(true): longPressAction?()
                            case .second: action()
                            default: break
                            }
                        }
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomLeading) {
            content
                .frame(width: 116, height: 104)
                .clipped()
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

/// Shared saved-activity photo strip used by detail and editing surfaces.
struct ActivityPhotoCarousel<Content: View>: View {
    var horizontalPadding: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                content()
            }
            .padding(.horizontal, horizontalPadding)
        }
        .frame(height: 104)
    }
}
