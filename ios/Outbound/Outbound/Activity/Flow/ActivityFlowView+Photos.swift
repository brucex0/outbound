import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

extension ActivityFlowView {
    var preActivityPhotoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let photo = model.preActivityPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 10) {
                    Button {
                        model.track(.init(.photoCaptureAttempted, properties: [.sourceType: .string("pre_activity_camera")]))
                        model.setup.isPreActivityCameraPresented = true
                    } label: {
                        Label(String(localized: "record.photo.retake", defaultValue: "Retake"), systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }

                    Button(role: .destructive) {
                        model.track(.init(.photoRemoved, properties: [.sourceType: .string("pre_activity")]))
                        model.removePreActivityPhoto()
                    } label: {
                        Label(String(localized: "record.photo.remove", defaultValue: "Remove"), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
            } else {
                HStack(spacing: 12) {
                    Button {
                        model.track(.init(.photoCaptureAttempted, properties: [.sourceType: .string("pre_activity_camera")]))
                        model.setup.isPreActivityCameraPresented = true
                    } label: {
                        Label(model.setup.preActivityPhotoActionTitle, systemImage: "camera.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    PhotosPicker(selection: binding(\.setup.selectedPreActivityPhotoItem), matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(String(localized: "record.photo.choose", defaultValue: "Choose a photo"))
                }

                Text(String(localized: "record.photo.optional_detail", defaultValue: "Optional — add a photo before you start."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: model.startSetupCardCornerRadius, style: .continuous))
    }

    var preActivityPhotoPreview: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let photo = model.preActivityPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Label(
                        String(localized: "record.photo.added", defaultValue: "Photo added"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.green)

                    HStack(spacing: 12) {
                        Button {
                            model.setup.isPreActivityPhotoPreviewPresented = false
                            model.track(.init(.photoCaptureAttempted, properties: [.sourceType: .string("pre_activity_camera")]))
                            DispatchQueue.main.async { model.setup.isPreActivityCameraPresented = true }
                        } label: {
                            Label(String(localized: "record.photo.retake", defaultValue: "Retake"), systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        Button(role: .destructive) {
                            model.track(.init(.photoRemoved, properties: [.sourceType: .string("pre_activity")]))
                            model.removePreActivityPhoto()
                            model.setup.isPreActivityPhotoPreviewPresented = false
                        } label: {
                            Label(String(localized: "record.photo.remove", defaultValue: "Remove"), systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)
            .navigationTitle(String(localized: "record.photo.preview", defaultValue: "Activity photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done", defaultValue: "Done")) {
                        model.setup.isPreActivityPhotoPreviewPresented = false
                    }
                }
            }
        }
    }
}
