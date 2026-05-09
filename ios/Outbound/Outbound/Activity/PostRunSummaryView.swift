import MapKit
import SwiftUI
import UIKit

struct PostRunSummaryView: View {
    @EnvironmentObject var measurementPreferences: MeasurementPreferences
    let summary: ActivitySummary
    let photos: [(UIImage, PhotoMetadata)]
    let reflection: FinishReflection
    let recognitionPreviews: [RecognitionPreview]
    let onSave: ([(UIImage, PhotoMetadata)], FinishReflection) -> Void
    let onDiscard: () -> Void
    @State private var selectedPhotoIndices: Set<Int>
    @State private var isPhotoSelectionPresented = false

    init(
        summary: ActivitySummary,
        photos: [(UIImage, PhotoMetadata)],
        reflection: FinishReflection,
        recognitionPreviews: [RecognitionPreview],
        onSave: @escaping ([(UIImage, PhotoMetadata)], FinishReflection) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.summary = summary
        self.photos = photos
        self.reflection = reflection
        self.recognitionPreviews = recognitionPreviews
        self.onSave = onSave
        self.onDiscard = onDiscard
        _selectedPhotoIndices = State(initialValue: Set(photos.indices))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    heroImage
                    reflectionSection
                    if !photos.isEmpty { photoReviewSection }
                    if let primaryRecognition = recognitionPreviews.first {
                        recognitionSection(primaryRecognition)
                    }
                    statsSection
                    if summary.trackPoints.count > 1 { routeMap }
                    motivationSection
                }
                .padding(.bottom, 100)
            }
            .ignoresSafeArea(edges: .top)
            
            actionButtons
        }
        .sheet(isPresented: $isPhotoSelectionPresented) {
            PhotoSelectionView(
                photos: photos,
                selectedPhotoIndices: $selectedPhotoIndices
            )
        }
    }

    private var heroImage: some View {
        Group {
            if let selectedPhoto = selectedPhotos.first {
                Image(uiImage: selectedPhoto.0)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [.orange.opacity(0.8), .red.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .frame(height: 280)
        .clipped()
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 120)
        }
    }

    private var statsSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SummaryStatColumn(
                    label: "Distance",
                    value: measurementPreferences.unitSystem.distanceValueString(meters: summary.distanceM),
                    unit: measurementPreferences.unitSystem.distanceUnit
                )
                Divider().frame(height: 48)
                SummaryStatColumn(
                    label: "Time",
                    value: summary.durationSecs.formatted(),
                    unit: ""
                )
                if let pace = summary.avgPace {
                    Divider().frame(height: 48)
                    SummaryStatColumn(label: "Avg Pace", value: pace.paceString(for: measurementPreferences.unitSystem), unit: "")
                }
            }

            Divider().padding(.vertical, 12)

            HStack(spacing: 0) {
                SummaryStatColumn(
                    label: "Elev Gain",
                    value: measurementPreferences.unitSystem.elevationValueString(meters: summary.elevationGainM),
                    unit: measurementPreferences.unitSystem.elevationUnit
                )
                if let averageHeartRate = summary.healthMetrics?.averageHeartRateBPM {
                    Divider().frame(height: 48)
                    SummaryStatColumn(label: "Avg HR", value: "\(averageHeartRate)", unit: "bpm")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(reflection.title)
                .font(.title2.bold())
            Text(reflection.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let progressNote = reflection.progressNote {
                Text(progressNote)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(reflection.highlight)
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private func recognitionSection(_ preview: RecognitionPreview) -> some View {
        RecognitionHeroBadge(preview: preview, secondaryCount: recognitionPreviews.count - 1)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var motivationSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            Text(reflection.highlight)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var routeMapPosition: MapCameraPosition {
        let coords = summary.trackPoints.map(\.coordinate)
        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.6, 0.005),
            longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.6, 0.005)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    private var routeMap: some View {
        Map(position: .constant(routeMapPosition)) {
            MapPolyline(coordinates: summary.trackPoints.map(\.coordinate))
                .stroke(.orange, lineWidth: 4)
        }
        .frame(height: 200)
        .disabled(true)
    }

    private var selectedPhotos: [(UIImage, PhotoMetadata)] {
        photos.indices
            .filter { selectedPhotoIndices.contains($0) }
            .map { photos[$0] }
    }

    private var photoSelectionSummary: String {
        switch selectedPhotos.count {
        case 0:
            return "None selected"
        case photos.count:
            return "\(photos.count) selected"
        default:
            return "\(selectedPhotos.count) of \(photos.count) selected"
        }
    }

    private var photoReviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Photos")
                        .font(.headline)
                    Text(photoSelectionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isPhotoSelectionPresented = true
                } label: {
                    Label("Manage", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .accessibilityIdentifier("ManagePhotosButton")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos.indices, id: \.self) { index in
                        PostRunPhotoThumbnail(
                            image: photos[index].0,
                            isSelected: selectedPhotoIndices.contains(index)
                        )
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .accessibilityIdentifier("PostRunPhotoReviewSection")
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button(role: .destructive, action: onDiscard) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
            .background(Color(.tertiarySystemBackground))
            .clipShape(Circle())

            Button {
                onSave(selectedPhotos, reflection)
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderless)
            .frame(width: 64, height: 64)
            .background(Color.orange)
            .clipShape(Circle())
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

private struct PostRunPhotoThumbnail: View {
    let image: UIImage
    let isSelected: Bool

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 68, height: 68)
            .clipped()
            .opacity(isSelected ? 1 : 0.35)
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? .orange : .white)
                    .padding(5)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PhotoSelectionView: View {
    let photos: [(UIImage, PhotoMetadata)]
    @Binding var selectedPhotoIndices: Set<Int>
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(photos.indices, id: \.self) { index in
                        Button {
                            togglePhoto(at: index)
                        } label: {
                            PhotoSelectionTile(
                                image: photos[index].0,
                                isSelected: selectedPhotoIndices.contains(index)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Photo \(index + 1)")
                        .accessibilityValue(selectedPhotoIndices.contains(index) ? "Selected" : "Not selected")
                    }
                }
                .padding(16)
            }
            .navigationTitle("Choose Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(allPhotosSelected ? "Clear" : "Select All") {
                        if allPhotosSelected {
                            selectedPhotoIndices.removeAll()
                        } else {
                            selectedPhotoIndices = Set(photos.indices)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(selectionCountText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.bar)
            }
        }
    }

    private var allPhotosSelected: Bool {
        selectedPhotoIndices.count == photos.count
    }

    private var selectionCountText: String {
        "\(selectedPhotoIndices.count) of \(photos.count) selected"
    }

    private func togglePhoto(at index: Int) {
        if selectedPhotoIndices.contains(index) {
            selectedPhotoIndices.remove(index)
        } else {
            selectedPhotoIndices.insert(index)
        }
    }
}

private struct PhotoSelectionTile: View {
    let image: UIImage
    let isSelected: Bool

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .overlay {
                if !isSelected {
                    Color.black.opacity(0.38)
                }
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? .orange : .white)
                    .padding(7)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
    }
}

#if DEBUG
struct DebugPostRunSummaryHarness: View {
    @State private var savedPhotoCount: Int?

    var body: some View {
        PostRunSummaryView(
            summary: Self.summary,
            photos: Self.photos,
            reflection: FinishReflection(
                title: "Good finish",
                body: "You got the session done and kept the finish simple.",
                highlight: "Photos are ready to review.",
                progressNote: nil
            ),
            recognitionPreviews: [],
            onSave: { selectedPhotos, _ in savedPhotoCount = selectedPhotos.count },
            onDiscard: {}
        )
        .overlay(alignment: .topTrailing) {
            if let savedPhotoCount {
                Text("Saved \(savedPhotoCount)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 16)
                    .padding(.trailing, 16)
            }
        }
    }

    private static var summary: ActivitySummary {
        let start = Date().addingTimeInterval(-28 * 60)
        let route = [
            CLLocation(latitude: 37.7793, longitude: -122.4192),
            CLLocation(latitude: 37.7819, longitude: -122.4147),
            CLLocation(latitude: 37.7857, longitude: -122.4104)
        ]
        return ActivitySummary(
            startedAt: start,
            endedAt: Date(),
            durationSecs: 28 * 60,
            distanceM: 4820,
            avgPace: 348,
            elevationGainM: 34,
            trackPoints: route
        )
    }

    private static var photos: [(UIImage, PhotoMetadata)] {
        [photo(index: 1), photo(index: 2), photo(index: 3)]
    }

    private static func photo(index: Int) -> (UIImage, PhotoMetadata) {
        let offset = Double(index)
        let coordinate = CLLocationCoordinate2D(
            latitude: 37.7793 + offset * 0.002,
            longitude: -122.4192 + offset * 0.002
        )
        let metadata = PhotoMetadata(
            takenAt: Date().addingTimeInterval(offset * -180),
            paceAtShot: 348,
            hrAtShot: 142 + index,
            distAtShot: offset * 1100,
            coordinate: coordinate,
            captureContext: .active
        )
        return (debugPhoto(index: index), metadata)
    }

    private static func debugPhoto(index: Int) -> UIImage {
        let size = CGSize(width: 900, height: 1200)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let colors: [(UIColor, UIColor)] = [
                (.systemOrange, .systemBlue),
                (.systemGreen, .systemIndigo),
                (.systemPink, .systemTeal)
            ]
            let pair = colors[(index - 1) % colors.count]

            pair.0.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            pair.1.setFill()
            context.fill(CGRect(x: 0, y: size.height * 0.56, width: size.width, height: size.height * 0.44))

            UIColor.white.withAlphaComponent(0.95).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 104, y: 120, width: 210, height: 210))

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 78, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            "Run Photo\n\(index)".draw(
                in: CGRect(x: 84, y: 430, width: size.width - 168, height: 230),
                withAttributes: attributes
            )
        }
    }
}

#Preview {
    DebugPostRunSummaryHarness()
        .environmentObject(MeasurementPreferences())
}

#endif

private struct SummaryStatColumn: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title.bold().monospacedDigit())
                if !unit.isEmpty {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
