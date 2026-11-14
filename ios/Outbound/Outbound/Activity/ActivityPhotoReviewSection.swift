import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

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

    private var photoDragType: UTType {
        UTType(exportedAs: "ai.plainstride.activity-photo", conformingTo: .data)
    }

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
                        Image(systemName: "checkmark")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "common.done", defaultValue: "Done"))
                    .accessibilityIdentifier("\(identifierPrefix)CancelPhotoSelectionButton")
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
                        preferredItemEncoding: .current,
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
                text: String(localized: "tooltip.photos", defaultValue: "Touch and hold a photo to select it; drag to reorder"),
                arrowEdge: .bottom
            )

            if photos.isEmpty {
                Text(String(localized: "summary.photos.empty", defaultValue: "No photo added"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            thumbnail(photo, index)
                                // Keep one stable drag source on every tile. Installing it only
                                // after a selection long press loses the gesture that is in flight.
                                .onDrag {
                                    selectedPhotoIDs.insert(photo.id)
                                    let provider = NSItemProvider()
                                    let data = Data(photo.id.uuidString.utf8)
                                    provider.registerDataRepresentation(
                                        forTypeIdentifier: photoDragType.identifier,
                                        visibility: .ownProcess
                                    ) { completion in
                                        completion(data, nil)
                                        return nil
                                    }
                                    return provider
                                }
                                .onDrop(of: [photoDragType], isTargeted: nil) { providers in
                                    acceptPhotoDrop(providers, destinationID: photo.id)
                                }
                                .accessibilityAction(named: String(localized: "summary.photos.select", defaultValue: "Select or deselect photo")) {
                                    if selectedPhotoIDs.contains(photo.id) {
                                        selectedPhotoIDs.remove(photo.id)
                                    } else {
                                        selectedPhotoIDs.insert(photo.id)
                                    }
                                }
                                .accessibilityAction(named: String(localized: "summary.photos.move_earlier", defaultValue: "Move photo earlier")) {
                                    guard index > 0 else { return }
                                    _ = onMove(photo.id, photos[index - 1].id)
                                }
                                .accessibilityAction(named: String(localized: "summary.photos.move_later", defaultValue: "Move photo later")) {
                                    guard index + 1 < photos.count else { return }
                                    _ = onMove(photo.id, photos[index + 1].id)
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
        .accessibilityElement(children: .contain)
    }

    /// Use the same explicit representation at both ends of the native drag.
    /// Decode the actual payload rather than relying on selection or stale drag state.
    private func acceptPhotoDrop(_ providers: [NSItemProvider], destinationID: UUID) -> Bool {
        guard providers.count == 1, let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(photoDragType.identifier) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: photoDragType.identifier) { data, error in
            if let error {
                let failure = error as NSError
                if failure.domain == NSCocoaErrorDomain && failure.code == NSUserCancelledError { return }
                ActivityDiagnosticLog.error(.persistence, "Activity photo drop failed: operation=load_payload domain=\(failure.domain) code=\(failure.code)")
                return
            }
            guard let data,
                  let identifier = String(data: data, encoding: .utf8),
                  let sourceID = UUID(uuidString: identifier) else {
                ActivityDiagnosticLog.error(.persistence, "Activity photo drop failed: unavailable or invalid local drag payload")
                return
            }
            Task { @MainActor in
                // The draft may have changed while the provider was loading.
                // Each caller validates both UUIDs against its current array.
                _ = onMove(sourceID, destinationID)
            }
        }
        return true
    }

}
