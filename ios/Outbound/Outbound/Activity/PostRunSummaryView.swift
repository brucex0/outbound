import MapKit
import PhotosUI
import SwiftUI
import UIKit

struct PostRunSummaryView: View {
    @EnvironmentObject var measurementPreferences: MeasurementPreferences
    @EnvironmentObject var personalizationStore: PersonalizationStore
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var tooltipCoordinator: TooltipCoordinator
    @Environment(\.analyticsManager) private var analyticsManager
    let summary: ActivitySummary
    let activityType: ActivityType
    let weightKilograms: Double?
    let photos: [(UIImage, PhotoMetadata)]
    let reflection: FinishReflection
    let recognitionPreviews: [RecognitionPreview]
    let guidanceReport: LiveGuidanceSessionReport
    let workoutID: String
    let onGuidanceFeedback: (LiveGuidanceFeedback) -> Void
    let onDiscardPrompted: () -> Void
    let onSave: ([(UIImage, PhotoMetadata)], FinishReflection) async -> Bool
    let onDiscard: () -> Void
    @State private var draftPhotos: [PostRunPhoto]
    @State private var selectedPhotoIDs: Set<UUID> = []
    @State private var previewedPhotoID: UUID?
    @State private var isCameraPresented = false
    @State private var importedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedEffort: RunEffort?
    @State private var continuationCapacity: ContinuationCapacity?
    @State private var selectedGuidanceFeedback: LiveGuidanceFeedback?
    @State private var isSubmitting = false
    @State private var didTrackSaveIneligible = false
    @State private var isWeightInputPresented = false
    @State private var isDiscardConfirmationPresented = false

    init(
        summary: ActivitySummary,
        activityType: ActivityType = .running,
        weightKilograms: Double? = nil,
        photos: [(UIImage, PhotoMetadata)],
        reflection: FinishReflection,
        recognitionPreviews: [RecognitionPreview],
        guidanceReport: LiveGuidanceSessionReport = .empty,
        workoutID: String = "freestyle-run",
        onGuidanceFeedback: @escaping (LiveGuidanceFeedback) -> Void = { _ in },
        onDiscardPrompted: @escaping () -> Void = {},
        onSave: @escaping ([(UIImage, PhotoMetadata)], FinishReflection) async -> Bool,
        onDiscard: @escaping () -> Void
    ) {
        self.summary = summary
        self.activityType = activityType
        self.weightKilograms = weightKilograms
        self.photos = photos
        self.reflection = reflection
        self.recognitionPreviews = recognitionPreviews
        self.guidanceReport = guidanceReport
        self.workoutID = workoutID
        self.onGuidanceFeedback = onGuidanceFeedback
        self.onDiscardPrompted = onDiscardPrompted
        self.onSave = onSave
        self.onDiscard = onDiscard
        _draftPhotos = State(initialValue: photos.map(PostRunPhoto.init))
    }

    private var saveEligibility: ActivitySaveEligibility {
        ActivitySaveEligibility.evaluate(
            durationSecs: summary.durationSecs,
            distanceM: summary.distanceM
        )
    }

    private var isSaveEligible: Bool {
        saveEligibility == .eligible
    }

    private var saveButtonTitle: String {
        isSaveEligible
            ? String(localized: "common.save", defaultValue: "Save")
            : String(localized: "summary.action.too_short", defaultValue: "Too short to save")
    }

    private var saveButtonAccessibilityLabel: String {
        isSaveEligible
            ? String(localized: "summary.action.save", defaultValue: "Save activity")
            : String(localized: "summary.action.too_short", defaultValue: "Too short to save")
    }

    private var ineligibleExplanation: String {
        String(localized: "summary.save.ineligible.explanation", defaultValue: "Record at least 5 minutes or 500 meters to save this activity.")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                mediaPager
                reflectionSection
                if isSaveEligible {
                    feedbackSection
                    if guidanceReport.spokenCueCount > 0 {
                        guidanceFeedbackSection
                    }
                }
                photoReviewSection
                if let primaryRecognition = recognitionPreviews.first {
                    recognitionSection(primaryRecognition)
                }
                statsSection
                if !isSaveEligible {
                    saveEligibilitySection
                }
                motivationSection
            }
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $isWeightInputPresented) {
            CalorieWeightInputView()
                .environmentObject(measurementPreferences)
                .environmentObject(onboardingStore)
        }
        .onAppear {
            guard !isSaveEligible, !didTrackSaveIneligible else { return }
            didTrackSaveIneligible = true
            Task {
                await analyticsManager?.track(.init(.activitySaveIneligibleShown, properties: [
                    .activityType: .string(activityType.rawValue),
                    .durationBucket: .string(ProductAnalyticsBucket.duration(seconds: summary.durationSecs)),
                    .distanceBucket: .string(ProductAnalyticsBucket.distance(meters: summary.distanceM))
                ]))
            }
        }
        .overlay(alignment: .top) {
            HStack {
                closeButton
                Spacer()
                saveButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .fullScreenCover(isPresented: photoViewerPresented) {
            PostRunPhotoViewer(
                photos: draftPhotos,
                initialPhotoID: previewedPhotoID
            )
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            PostRunCameraView { image in
                draftPhotos.append(PostRunPhoto(image: image, metadata: finishPhotoMetadata))
                Task {
                    await analyticsManager?.track(.init(.photoCaptured, properties: [
                        .sourceType: .string("finish_review"),
                        .locationAttached: .boolean(finishPhotoMetadata.coordinate != nil),
                    ]))
                }
            }
        }
        .onChange(of: importedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(from: items) }
        }
        .alert(
            String(localized: "summary.discard.confirmation.title", defaultValue: "Discard unsaved activity?"),
            isPresented: $isDiscardConfirmationPresented
        ) {
            Button(String(localized: "summary.action.discard", defaultValue: "Discard activity"), role: .destructive) {
                onDiscard()
            }
            Button(
                String(localized: "summary.discard.confirmation.keep_editing", defaultValue: "Keep editing"),
                role: .cancel
            ) {}
        } message: {
            Text(String(
                localized: "summary.discard.confirmation.message",
                defaultValue: "This activity hasn’t been saved. If you close now, it will be permanently discarded."
            ))
        }
    }

    private var closeButton: some View {
        Button {
            guard !isSubmitting else { return }
            if isSaveEligible {
                onDiscardPrompted()
                isDiscardConfirmationPresented = true
            } else {
                onDiscard()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .disabled(isSubmitting)
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(.ultraThinMaterial, in: Circle())
        .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        .accessibilityLabel(String(localized: "common.close", defaultValue: "Close"))
        .accessibilityIdentifier("ClosePostRunSummaryButton")
    }

    private var mediaPager: some View {
        TabView {
            if summary.trackPoints.count > 1 {
                routeMap
                    .tag("route")
            }
            ForEach(draftPhotos) { photo in
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .tag(photo.id.uuidString)
            }
            if summary.trackPoints.count <= 1 && draftPhotos.isEmpty {
                LinearGradient(
                    colors: [.orange.opacity(0.8), .red.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .tag("placeholder")
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
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
                    label: String(localized: "summary.stats.distance", defaultValue: "Distance"),
                    value: measurementPreferences.unitSystem.distanceValueString(meters: summary.distanceM),
                    unit: measurementPreferences.unitSystem.distanceUnit
                )
                Divider().frame(height: 48)
                SummaryStatColumn(
                    label: String(localized: "summary.stats.time", defaultValue: "Time"),
                    value: summary.durationSecs.formatted(),
                    unit: ""
                )
                if let pace = summary.avgPace {
                    Divider().frame(height: 48)
                    SummaryStatColumn(label: String(localized: "summary.stats.avg_pace", defaultValue: "Avg Pace"), value: pace.paceString(for: measurementPreferences.unitSystem), unit: "")
                }
            }

            Divider().padding(.vertical, 12)

            HStack(spacing: 0) {
                SummaryStatColumn(
                    label: String(localized: "summary.stats.elev_gain", defaultValue: "Elev Gain"),
                    value: measurementPreferences.unitSystem.elevationValueString(meters: summary.elevationGainM),
                    unit: measurementPreferences.unitSystem.elevationUnit
                )
                if activityType == .walking, let walkingStepCount = summary.walkingStepCount {
                    Divider().frame(height: 48)
                    SummaryStatColumn(
                        label: String(localized: "activity.metric.steps", defaultValue: "Steps"),
                        value: walkingStepCount.formatted(),
                        unit: ""
                    )
                }
                Divider().frame(height: 48)
                if calorieEstimate.unavailableReason == .missingWeight {
                    Button {
                        isWeightInputPresented = true
                        Task {
                            await analyticsManager?.track(.init(.preferenceChanged, properties: [
                                .changeType: .string("calorie_weight_prompt"),
                                .selectionType: .string("post_run_summary_opened"),
                            ]))
                        }
                    } label: {
                        SummaryStatColumn(
                            label: String(localized: "activity.metric.calories", defaultValue: "Calories"),
                            value: "—",
                            unit: ""
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(String(
                        localized: "activity.calories.add_weight.hint",
                        defaultValue: "Add your weight to calculate calories"
                    ))
                } else {
                    SummaryStatColumn(
                        label: String(localized: "activity.metric.calories", defaultValue: "Calories"),
                        value: calorieEstimate.kilocalories.map { kilocalories in
                            WorkoutCalorieEstimator.calorieValue(kilocalories)
                        } ?? "—",
                        unit: ""
                    )
                }
                if let averageHeartRate = summary.healthMetrics?.averageHeartRateBPM {
                    Divider().frame(height: 48)
                    SummaryStatColumn(label: String(localized: "summary.stats.avg_hr", defaultValue: "Avg HR"), value: "\(averageHeartRate)", unit: "bpm")
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

    private var calorieEstimate: WorkoutCalorieEstimate {
        WorkoutCalorieEstimator.estimate(
            for: summary,
            activityType: activityType,
            weightKilograms: onboardingStore.latestWeightKilograms ?? weightKilograms
        )
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

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "summary.feedback.header", defaultValue: "How did that feel?"))
                .font(.headline)
            HStack {
                effortButton(.easy, title: String(localized: "summary.feedback.easy", defaultValue: "Easy"))
                effortButton(.aboutRight, title: String(localized: "summary.feedback.about_right", defaultValue: "About right"))
                effortButton(.tooHard, title: String(localized: "summary.feedback.too_hard", defaultValue: "Too hard"))
            }
            if selectedEffort == .easy {
                Text(String(localized: "summary.feedback.capacity.header", defaultValue: "Could you comfortably have continued?"))
                    .font(.subheadline.weight(.semibold))
                HStack {
                    capacityButton(.none, title: String(localized: "summary.feedback.capacity.no", defaultValue: "No"))
                    capacityButton(.tenMinutes, title: String(localized: "summary.feedback.capacity.10min", defaultValue: "10 min"))
                    capacityButton(.muchLonger, title: String(localized: "summary.feedback.capacity.much_longer", defaultValue: "Much longer"))
                }
            }
            Text(String(localized: "summary.feedback.note", defaultValue: "Optional. Plainstride asks after workouts where your answer can improve the plan."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var guidanceFeedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "guide.feedback.section.title", defaultValue: "How was live guidance?"))
                .font(.headline)

            Text(guidanceSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(LiveGuidanceFeedback.allCases) { feedback in
                    Button(feedback.displayName) {
                        selectedGuidanceFeedback = feedback
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedGuidanceFeedback == feedback ? .orange : .secondary)
                }
            }

            Text(String(localized: "guide.feedback.privacy", defaultValue: "Feedback improves cue timing and frequency. Coaching text is not included in analytics."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var guidanceSummary: String {
        let format = String(
            localized: "guide.feedback.summary.format",
            defaultValue: "%1$d cues · %2$d helped"
        )
        return String(
            format: format,
            locale: .autoupdatingCurrent,
            guidanceReport.spokenCueCount,
            guidanceReport.helpfulCueCount
        )
    }

    private func effortButton(_ effort: RunEffort, title: String) -> some View {
        Button(title) {
            selectedEffort = effort
            if effort != .easy { continuationCapacity = nil }
        }
            .buttonStyle(.bordered)
            .tint(selectedEffort == effort ? .orange : .secondary)
            .frame(maxWidth: .infinity)
    }

    private func capacityButton(_ capacity: ContinuationCapacity, title: String) -> some View {
        Button(title) { continuationCapacity = capacity }
            .buttonStyle(.bordered)
            .tint(continuationCapacity == capacity ? .orange : .secondary)
            .frame(maxWidth: .infinity)
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
            ForEach(Array(summary.trackSegments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment.map(\.coordinate))
                    .stroke(.orange, lineWidth: 4)
            }
            ForEach(draftPhotos) { photo in
                if let coordinate = photo.metadata.coordinate {
                    Annotation(
                        String(localized: "activity.map.photo", defaultValue: "Activity photo"),
                        coordinate: coordinate
                    ) {
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 42, height: 42)
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .stroke(.white, lineWidth: 1.5)
                            }
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(true)
    }

    private var finishPhotoMetadata: PhotoMetadata {
        PhotoMetadata(
            takenAt: Date(),
            paceAtShot: summary.avgPace,
            hrAtShot: summary.healthMetrics?.averageHeartRateBPM,
            distAtShot: summary.distanceM,
            coordinate: summary.trackPoints.last?.coordinate,
            captureContext: .paused
        )
    }

    private var photoReviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(String(localized: "summary.photos.title", defaultValue: "Photos"))
                    .font(.headline)

                Spacer()

                if !selectedPhotoIDs.isEmpty {
                    Button {
                        removeSelectedPhotos()
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .accessibilityLabel(String(localized: "summary.photos.delete_selected", defaultValue: "Delete selected photos"))
                    .accessibilityIdentifier("DeleteSelectedFinishPhotosButton")

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
                        Task {
                            await analyticsManager?.track(.init(.photoCaptureAttempted, properties: [
                                .sourceType: .string("finish_review"),
                            ]))
                        }
                        isCameraPresented = true
                    } label: {
                        Image(systemName: "camera.fill")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(String(localized: "summary.photos.take", defaultValue: "Take Photo"))
                    .accessibilityIdentifier("TakeFinishPhotoButton")

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
                    .accessibilityIdentifier("ImportFinishPhotoButton")
                }
            }
            .coordinatedTooltip(
                .photoManagement,
                isEligible: draftPhotos.count >= 2 && selectedPhotoIDs.isEmpty,
                text: String(localized: "tooltip.photos", defaultValue: "Press and hold to select, delete, or reorder photos"),
                arrowEdge: .bottom
            )

            if draftPhotos.isEmpty {
                Text(String(localized: "summary.photos.empty", defaultValue: "No photo added"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(draftPhotos.enumerated()), id: \.element.id) { index, photo in
                            if selectedPhotoIDs.contains(photo.id) {
                                finishPhotoThumbnail(photo, index: index)
                                    .draggable(photo.id.uuidString)
                                    .dropDestination(for: String.self) { identifiers, _ in
                                        guard let identifier = identifiers.first,
                                              let sourceID = UUID(uuidString: identifier)
                                        else { return false }
                                        return movePhoto(sourceID, to: photo.id)
                                    }
                            } else {
                                finishPhotoThumbnail(photo, index: index)
                                    .dropDestination(for: String.self) { identifiers, _ in
                                        guard let identifier = identifiers.first,
                                              let sourceID = UUID(uuidString: identifier)
                                        else { return false }
                                        return movePhoto(sourceID, to: photo.id)
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
        .accessibilityIdentifier("PostRunPhotoReviewSection")
    }

    private var photoViewerPresented: Binding<Bool> {
        Binding(
            get: { previewedPhotoID != nil },
            set: { if !$0 { previewedPhotoID = nil } }
        )
    }

    private func finishPhotoThumbnail(_ photo: PostRunPhoto, index: Int) -> some View {
        ActivityPhotoThumbnail(
            caption: finishPhotoCaption(photo, index: index),
            isSelected: selectedPhotoIDs.contains(photo.id),
            action: { handlePhotoTap(photo) },
            longPressAction: { togglePhotoSelection(photo.id) }
        ) {
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFill()
        }
        .accessibilityLabel(finishPhotoCaption(photo, index: index))
        .accessibilityHint(String(localized: "summary.photos.long_press_hint", defaultValue: "Long press to select, then drag to reorder"))
    }

    private func handlePhotoTap(_ photo: PostRunPhoto) {
        if selectedPhotoIDs.isEmpty {
            previewedPhotoID = photo.id
            Task {
                await analyticsManager?.track(.init(.photoPreviewed, properties: [
                    .sourceType: .string("finish_review"),
                ]))
            }
        } else {
            togglePhotoSelection(photo.id)
        }
    }

    private func togglePhotoSelection(_ photoID: UUID) {
        tooltipCoordinator.dismiss(.photoManagement, outcome: "used")
        if selectedPhotoIDs.contains(photoID) {
            selectedPhotoIDs.remove(photoID)
        } else {
            selectedPhotoIDs.insert(photoID)
        }
    }

    private func removeSelectedPhotos() {
        let removedCount = selectedPhotoIDs.count
        draftPhotos.removeAll { selectedPhotoIDs.contains($0.id) }
        selectedPhotoIDs.removeAll()
        guard removedCount > 0 else { return }
        Task {
            await analyticsManager?.track(.init(.photoRemoved, properties: [
                .sourceType: .string("finish_review"),
            ]))
        }
    }

    private func movePhoto(_ sourceID: UUID, to destinationID: UUID) -> Bool {
        guard sourceID != destinationID,
              let sourceIndex = draftPhotos.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = draftPhotos.firstIndex(where: { $0.id == destinationID })
        else { return false }

        let photo = draftPhotos.remove(at: sourceIndex)
        draftPhotos.insert(photo, at: min(destinationIndex, draftPhotos.count))
        Task {
            await analyticsManager?.track(.init(.photoReordered, properties: [
                .sourceType: .string("finish_review"),
            ]))
        }
        return true
    }

    private func finishPhotoCaption(_ photo: PostRunPhoto, index: Int) -> String {
        if photo.metadata.captureContext == .preActivity {
            return String(localized: "activity.photos.start", defaultValue: "Start")
        }
        if index == draftPhotos.count - 1 || photo.metadata.captureContext == .paused {
            return String(localized: "activity.photos.finish", defaultValue: "Finish")
        }
        return measurementPreferences.unitSystem.distanceString(meters: photo.metadata.distAtShot, fractionDigits: 1)
    }

    private func importPhotos(from items: [PhotosPickerItem]) async {
        await analyticsManager?.track(.init(.photoCaptureAttempted, properties: [
            .sourceType: .string("finish_photo_library"),
        ]))

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { continue }

            let metadata = PhotoMetadata(
                takenAt: Date(),
                paceAtShot: summary.avgPace,
                hrAtShot: summary.healthMetrics?.averageHeartRateBPM,
                distAtShot: summary.distanceM,
                coordinate: nil,
                captureContext: .paused
            )
            draftPhotos.append(PostRunPhoto(image: image, metadata: metadata))
            await analyticsManager?.track(.init(.photoCaptured, properties: [
                .sourceType: .string("finish_photo_library"),
                .locationAttached: .boolean(false),
            ]))
        }

        importedPhotoItems = []
    }

    private var saveEligibilitySection: some View {
        Text(ineligibleExplanation)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .accessibilityIdentifier("PostRunSaveEligibilityExplanation")
    }

    private var saveButton: some View {
        Button {
            guard !isSubmitting, isSaveEligible else { return }
            isSubmitting = true
            if let selectedEffort {
                Task {
                    await personalizationStore.submitFeedback(
                        effort: selectedEffort,
                        continuationCapacity: continuationCapacity,
                        workoutID: workoutID,
                        activityID: nil
                    )
                }
            }
            if let selectedGuidanceFeedback {
                onGuidanceFeedback(selectedGuidanceFeedback)
            }
            Task {
                let didSave = await onSave(draftPhotos.map { ($0.image, $0.metadata) }, reflection)
                if !didSave {
                    isSubmitting = false
                }
            }
        } label: {
            ZStack {
                Text(saveButtonTitle)
                    .font(.subheadline.weight(.bold))
                    .opacity(isSubmitting ? 0 : 1)

                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(minWidth: 44)
            .padding(.horizontal, 12)
            .frame(height: 44)
        }
        .disabled(isSubmitting || !isSaveEligible)
        .buttonStyle(.plain)
        .foregroundStyle(isSaveEligible ? .white : .secondary)
        .background(isSaveEligible ? Color.orange : Color(.tertiarySystemFill), in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        .accessibilityLabel(saveButtonAccessibilityLabel)
        .accessibilityIdentifier("SavePostRunSummaryButton")
    }
}

struct PostRunPhoto: Identifiable {
    let id: UUID
    let image: UIImage
    let metadata: PhotoMetadata

    init(id: UUID = UUID(), image: UIImage, metadata: PhotoMetadata) {
        self.id = id
        self.image = image
        self.metadata = metadata
    }

    init(_ photo: (UIImage, PhotoMetadata)) {
        self.init(image: photo.0, metadata: photo.1)
    }
}

struct PostRunPhotoViewer: View {
    let photos: [PostRunPhoto]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoID: UUID

    init(photos: [PostRunPhoto], initialPhotoID: UUID?) {
        self.photos = photos
        _selectedPhotoID = State(initialValue: initialPhotoID ?? photos.first?.id ?? UUID())
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedPhotoID) {
                ForEach(photos) { photo in
                    Image(uiImage: photo.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(photo.id)
                        .accessibilityLabel(String(localized: "summary.photos.preview", defaultValue: "Activity photo"))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "common.close", defaultValue: "Close"))
            .padding(.top, 12)
            .padding(.trailing, 16)
        }
    }
}

struct PostRunCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraController()
    @State private var isCapturing = false
    let onCapture: (UIImage) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreviewLayer(session: camera.session).ignoresSafeArea()

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title3.bold())
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                    Button { camera.flipCamera() } label: {
                        Image(systemName: "camera.rotate.fill")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .foregroundStyle(.white)
                .padding()

                Spacer()

                Button {
                    guard !isCapturing else { return }
                    isCapturing = true
                    camera.capturePhoto { image in
                        DispatchQueue.main.async {
                            isCapturing = false
                            guard let image else { return }
                            onCapture(image)
                            dismiss()
                        }
                    }
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 72, height: 72)
                        .overlay(Circle().stroke(.white.opacity(0.65), lineWidth: 5).padding(-7))
                }
                .disabled(isCapturing)
                .accessibilityLabel(String(localized: "summary.photos.capture", defaultValue: "Take photo"))
                .padding(.bottom, 32)
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
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
            onSave: { selectedPhotos, _ in
                savedPhotoCount = selectedPhotos.count
                return true
            },
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
