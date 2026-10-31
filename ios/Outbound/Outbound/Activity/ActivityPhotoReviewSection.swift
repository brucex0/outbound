import PhotosUI
import SwiftUI

/// Save and edit share the same photo management layout and drag gestures.
/// Callers retain image loading, draft ownership, preview, persistence and analytics.
struct ActivityPhotoReviewSection<Photo: Identifiable, Thumbnail: View>: View where Photo.ID == UUID {
    let photos: [Photo]
    @Binding var selectedPhotoIDs: Set<UUID>
    @Binding var importedPhotoItems: [PhotosPickerItem]
    let identifierPrefix: String
    let onCapture: () -> Void
    let onRemove: () -> Void
    let onMove: (UUID, UUID) -> Bool
    @ViewBuilder let thumbnail: (Photo, Int) -> Thumbnail

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(String(localized: "summary.photos.title", defaultValue: "Photos"))
                    .font(.headline)

                Spacer()

                if !selectedPhotoIDs.isEmpty {
                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .accessibilityLabel(String(localized: "summary.photos.delete_selected", defaultValue: "Delete selected photos"))
                    .accessibilityIdentifier(identifierPrefix == "Finish" ? "DeleteSelectedFinishPhotosButton" : "\(identifierPrefix)DeleteSelectedPhotosButton")

                    Button {
                        selectedPhotoIDs.removeAll()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "common.cancel", defaultValue: "Cancel"))
                } else {
                    Button {
                        onCapture()
                    } label: {
                        Image(systemName: "camera.fill")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(String(localized: "summary.photos.take", defaultValue: "Take Photo"))
                    .accessibilityIdentifier(identifierPrefix == "Finish" ? "TakeFinishPhotoButton" : "\(identifierPrefix)TakePhotoButton")

                    PhotosPicker(
                        selection: $importedPhotoItems,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(String(localized: "summary.photos.import", defaultValue: "Import Photo"))
                    .accessibilityIdentifier(identifierPrefix == "Finish" ? "ImportFinishPhotoButton" : "\(identifierPrefix)ImportPhotoButton")
                }
            }
            .coordinatedTooltip(
                .photoManagement,
                isEligible: photos.count >= 2 && selectedPhotoIDs.isEmpty,
                text: String(localized: "tooltip.photos", defaultValue: "Press and hold to select, delete, or reorder photos"),
                arrowEdge: .bottom
            )

            if photos.isEmpty {
                Text(String(localized: "summary.photos.empty", defaultValue: "No photo added"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            if selectedPhotoIDs.contains(photo.id) {
                                thumbnail(photo, index)
                                    .draggable(photo.id.uuidString)
                                    .dropDestination(for: String.self) { identifiers, _ in
                                        guard let identifier = identifiers.first,
                                              let sourceID = UUID(uuidString: identifier)
                                        else { return false }
                                        return onMove(sourceID, photo.id)
                                    }
                            } else {
                                thumbnail(photo, index)
                                    .dropDestination(for: String.self) { identifiers, _ in
                                        guard let identifier = identifiers.first,
                                              let sourceID = UUID(uuidString: identifier)
                                        else { return false }
                                        return onMove(sourceID, photo.id)
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(height: 104)
                .padding(.horizontal, -20)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .accessibilityIdentifier(identifierPrefix == "Finish" ? "PostRunPhotoReviewSection" : "\(identifierPrefix)PhotoReviewSection")
    }

}
