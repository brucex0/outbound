import Charts
import MapKit
import SwiftUI
import UIKit

// MARK: - Main View

struct ActivityDetailView: View {
    let activity: SavedActivity
    private let usesStoredActivity: Bool
    private let showsShareControl: Bool
    private let showsEditControl: Bool
    private let showsPrivateDetails: Bool
    private let supplementalContent: AnyView?
    private let bottomContent: AnyView?
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var measurementPreferences: MeasurementPreferences
    @EnvironmentObject var gearStore: GearStore
    @State private var shareURL: URL?
    @State private var shareImage: UIImage?
    @State private var shareError: ShareRouteError?
    @State private var isPreparingShareCard = false
    @State private var showSplits = false
    @State private var showElevationProfile = false
    @State private var isEditPresented = false
    @State private var sheetDetent: ActivityDetailSheetDetent = .split
    @State private var sheetDragHeight: CGFloat?
    @State private var showsCollapsedSheetContent = false
    @State private var selectedPhotoPage = 0
    @State private var lightboxPhotoIndex: Int?

    init(
        activity: SavedActivity,
        usesStoredActivity: Bool = true,
        showsShareControl: Bool = true,
        showsEditControl: Bool = true,
        showsPrivateDetails: Bool = true,
        supplementalContent: AnyView? = nil,
        bottomContent: AnyView? = nil
    ) {
        self.activity = activity
        self.usesStoredActivity = usesStoredActivity
        self.showsShareControl = showsShareControl
        self.showsEditControl = showsEditControl
        self.showsPrivateDetails = showsPrivateDetails
        self.supplementalContent = supplementalContent
        self.bottomContent = bottomContent
    }

    private var currentActivity: SavedActivity {
        guard usesStoredActivity else { return activity }
        return activityStore.activity(id: activity.id) ?? activity
    }

    private var unitSystem: MeasurementUnitSystem { measurementPreferences.unitSystem }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        currentActivity.routeCoordinates
    }

    // MARK: Computed values

    private var primaryStat: String {
        unitSystem.distanceString(meters: currentActivity.distanceM)
    }

    private var activityStats: [DetailActivityStat] {
        [
            DetailActivityStat(label: "Distance", value: primaryStat),
            DetailActivityStat(
                label: String(localized: "activity.metric.avg_pace", defaultValue: "Avg Pace"),
                value: currentActivity.avgPace?.paceString(for: unitSystem) ?? "—"
            ),
            DetailActivityStat(label: String(localized: "activity.metric.moving_time", defaultValue: "Moving Time"), value: currentActivity.durationSecs.formatted()),
            DetailActivityStat(
                label: String(localized: "activity.metric.elevation_gain", defaultValue: "Elev Gain"),
                value: currentActivity.elevationGainM.map { unitSystem.elevationString(meters: $0) } ?? "—"
            ),
        ]
    }

    private var splits: [ActivitySplit] {
        computeSplits(from: currentActivity.routePoints, unitSystem: unitSystem)
    }

    private var paceSegments: [(startIndex: Int, endIndex: Int, pace: Double)] {
        computePaceSegments(from: currentActivity.routePoints)
    }

    private var elevationProfilePoints: [ActivityElevationProfilePoint] {
        computeElevationProfilePoints(from: currentActivity.routePoints)
    }

    // MARK: Body

    var body: some View {
        GeometryReader { proxy in
            let sheetHeight = sheetDetent.height(in: proxy)
            let interactiveSheetHeight = sheetDragHeight ?? sheetHeight

            ZStack(alignment: .bottom) {
                backgroundMedia(bottomInset: interactiveSheetHeight)

                activitySheet(height: interactiveSheetHeight, proxy: proxy)
                    .simultaneousGesture(sheetDragGesture(in: proxy))
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .navigationTitle(currentActivity.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if showsShareControl {
                    Button {
                        shareActivityCard()
                    } label: {
                        if isPreparingShareCard {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(isPreparingShareCard)
                    .accessibilityLabel(isPreparingShareCard
                                        ? String(localized: "activity.share.preparing", defaultValue: "Preparing activity to share")
                                        : String(localized: "activity.share", defaultValue: "Share activity"))
                }

                if showsEditControl {
                    Button {
                        isEditPresented = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel(String(localized: "activity.edit", defaultValue: "Edit activity"))
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: isShareSheetPresented) {
            if let shareImage {
                ShareSheet(activityItems: [shareImage])
            } else if let shareURL {
                ShareSheet(activityItems: [shareURL])
            }
        }
        .alert(item: $shareError) { error in
            Alert(title: Text(String(localized: "activity.share_route.unable", defaultValue: "Unable to Share Route")), message: Text(error.message))
        }
        .sheet(isPresented: $isEditPresented) {
            EditActivityView(activity: currentActivity)
                .environmentObject(activityStore)
                .environmentObject(gearStore)
        }
        .fullScreenCover(isPresented: lightboxIsPresented) {
            ActivityPhotoLightbox(
                photos: currentActivity.photos,
                selectedIndex: $selectedPhotoPage,
                imageURL: activityStore.imageURL(for:),
                onClose: { lightboxPhotoIndex = nil }
            )
        }
        .onChange(of: currentActivity.photos.count) { _, count in
            if count == 0 {
                selectedPhotoPage = 0
            } else if selectedPhotoPage >= count {
                selectedPhotoPage = max(0, count - 1)
            }
        }
    }

    private func backgroundMedia(bottomInset: CGFloat) -> some View {
        ActivityRouteMapView(
            routeCoordinates: routeCoordinates,
            paceSegments: paceSegments,
            photos: currentActivity.photos,
            bottomInset: bottomInset,
            isRouteProminent: sheetDetent != .expanded,
            selectedPhotoID: selectedPhotoID
        )
        .ignoresSafeArea()
    }

    // MARK: - Sheet

    private func activitySheet(height: CGFloat, proxy: GeometryProxy) -> some View {
        let isExpandedHeight = height >= ActivityDetailSheetDetent.expanded.height(in: proxy) - 1
        let isShowingCollapsedSummary = showsCollapsedSheetContent && sheetDetent == .collapsed && sheetDragHeight == nil
        let topRadius: CGFloat = isExpandedHeight ? 0 : 22

        return VStack(spacing: 0) {
            sheetGrabber
                .padding(.top, 8)
                .padding(.bottom, sheetDetent == .collapsed ? 2 : 6)

            ZStack(alignment: .top) {
                collapsedSummary
                    .opacity(isShowingCollapsedSummary ? 1 : 0)
                    .allowsHitTesting(isShowingCollapsedSummary)

                ScrollView(showsIndicators: sheetDetent == .expanded) {
                    VStack(spacing: 0) {
                        if let supplementalContent { supplementalContent }
                        statsHeroSection
                        if currentActivity.activityEventID != nil { sharedActivitySection }
                        if showsPrivateDetails, showsMetadataSection { metadataSection }
                        elevationProfileSection
                        if !splits.isEmpty { splitsSection }
                        if showsPrivateDetails { guideHeroCard(currentActivity.reflection) }
                        if let bottomContent { bottomContent }
                    }
                    .padding(.bottom, proxy.safeAreaInsets.bottom + 24)
                }
                .scrollDisabled(sheetDetent != .expanded)
                .opacity(isShowingCollapsedSummary ? 0 : 1)
                .allowsHitTesting(!isShowingCollapsedSummary)
            }
            .animation(.easeInOut(duration: 0.16), value: isShowingCollapsedSummary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background(Color(.systemBackground))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: topRadius, topTrailingRadius: topRadius))
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: -6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var sharedActivitySection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.2.fill")
                .foregroundStyle(OutboundPalette.companion)
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "activity.shared.title", defaultValue: "Shared activity")).font(.headline)
                Text(String(localized: "activity.shared.detail", defaultValue: "This is your personal recording from an activity event. Shared participant results remain in Social."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var sheetGrabber: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 42, height: 5)
            .onTapGesture {
                showsCollapsedSheetContent = false
                sheetDetent = sheetDetent == .expanded ? .split : .expanded
            }
    }

    private var collapsedSummary: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryStat)
                    .font(.title3.bold().monospacedDigit())
                Text(currentActivity.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            ForEach(activityStats.prefix(2)) { stat in
                VStack(alignment: .trailing, spacing: 2) {
                    Text(stat.value)
                        .font(.subheadline.bold().monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(stat.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            showsCollapsedSheetContent = false
            sheetDetent = .split
        }
    }

    private func sheetDragGesture(in proxy: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                if showsCollapsedSheetContent {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showsCollapsedSheetContent = false
                    }
                }

                let currentHeight = sheetDetent.height(in: proxy)
                let proposedHeight = currentHeight - value.translation.height
                let clampedHeight = min(
                    max(proposedHeight, sheetDetent.minimumHeight(in: proxy)),
                    sheetDetent.maximumHeight(in: proxy)
                )
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    sheetDragHeight = clampedHeight
                }
            }
            .onEnded { value in
                let projectedHeight = sheetDetent.height(in: proxy) - value.predictedEndTranslation.height
                let target = ActivityDetailSheetDetent.snapTarget(
                    from: sheetDetent,
                    translation: value.translation.height,
                    projectedHeight: projectedHeight,
                    in: proxy
                )
                let targetHeight = target.height(in: proxy)
                withAnimation(.snappy(duration: 0.28)) {
                    sheetDragHeight = targetHeight
                } completion: {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        sheetDetent = target
                        sheetDragHeight = nil
                    }
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showsCollapsedSheetContent = target == .collapsed
                    }
                }
            }
    }

    // MARK: - Elevation Profile

    @ViewBuilder
    private var elevationProfileSection: some View {
        if elevationProfilePoints.count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.snappy) { showElevationProfile.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Text(String(localized: "activity.elevation.section", defaultValue: "Elevation"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let elevationGainM = currentActivity.elevationGainM {
                            Text(unitSystem.elevationString(meters: elevationGainM))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showElevationProfile ? 180 : 0))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showElevationProfile {
                    elevationChart
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .transition(.opacity)
                }
            }
            .background(Color(.systemBackground))
        }
    }

    private var elevationChart: some View {
        let yDomain = elevationChartDomain(points: elevationProfilePoints, unitSystem: unitSystem)
        let xDomain = elevationChartDistanceDomain(points: elevationProfilePoints, unitSystem: unitSystem)

        return Chart(elevationProfilePoints) { point in
            AreaMark(
                x: .value("Distance", unitSystem.distanceValue(meters: point.distanceMeters)),
                yStart: .value("Baseline", yDomain.lowerBound),
                yEnd: .value("Elevation", unitSystem.elevationValue(meters: point.altitudeMeters))
            )
            .foregroundStyle(Color.orange.opacity(0.14))

            LineMark(
                x: .value("Distance", unitSystem.distanceValue(meters: point.distanceMeters)),
                y: .value("Elevation", unitSystem.elevationValue(meters: point.altitudeMeters))
            )
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round))
            .foregroundStyle(Color.orange)
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: [xDomain.lowerBound, xDomain.upperBound]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color(.separator).opacity(0.35))
                AxisValueLabel {
                    if let distance = value.as(Double.self) {
                        Text(distance, format: .number.precision(.fractionLength(0...1)))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .chartOverlay(alignment: .topTrailing) { _ in
            Text("\(Int(yDomain.upperBound.rounded())) \(unitSystem.elevationUnit)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
    }

    // MARK: - Stats Hero

    private var statsHeroSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(currentActivity.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .lineLimit(2)

            if !currentActivity.photos.isEmpty {
                activityPhotoStrip
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20),
                ],
                alignment: .leading,
                spacing: 18
            ) {
                ForEach(Array(activityStats.prefix(4))) { stat in
                    DetailStatCell(label: stat.label, value: stat.value)
                }
            }
            .padding(.horizontal, 28)
        }
        .padding(.top, 22)
        .padding(.bottom, 24)
        .background(Color(.systemBackground))
    }

    private var selectedPhotoID: UUID? {
        currentActivity.photos.indices.contains(selectedPhotoPage)
            ? currentActivity.photos[selectedPhotoPage].id
            : nil
    }

    private var lightboxIsPresented: Binding<Bool> {
        Binding(
            get: { lightboxPhotoIndex != nil },
            set: { if !$0 { lightboxPhotoIndex = nil } }
        )
    }

    private var activityPhotoStrip: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(currentActivity.photos.enumerated()), id: \.element.id) { index, photo in
                        Button {
                            if selectedPhotoPage == index {
                                lightboxPhotoIndex = index
                            } else {
                                withAnimation(.snappy) { selectedPhotoPage = index }
                            }
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                if let url = activityStore.imageURL(for: photo) {
                                    LocalImageView(url: url) { Color(.secondarySystemBackground) }
                                }
                                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                                Text(photoCaption(photo, index: index, compact: true))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(8)
                            }
                            .frame(width: 116, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(photo.id == selectedPhotoID ? Color.orange : Color.clear, lineWidth: 3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(photo.id)
                        .accessibilityLabel(photoCaption(photo, index: index, compact: false))
                        .accessibilityHint(photo.id == selectedPhotoID
                            ? String(localized: "activity.photos.open", defaultValue: "Open photo full screen")
                            : String(localized: "activity.photos.locate", defaultValue: "Show this photo on the map"))
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 104)
            .onChange(of: selectedPhotoPage) { _, index in
                guard currentActivity.photos.indices.contains(index) else { return }
                withAnimation(.snappy) { reader.scrollTo(currentActivity.photos[index].id, anchor: .center) }
            }
        }
    }

    private func photoCaption(_ photo: SavedPhoto, index: Int, compact: Bool) -> String {
        if index == 0 { return String(localized: "activity.photos.start", defaultValue: "Start") }
        if index == currentActivity.photos.count - 1 { return String(localized: "activity.photos.finish", defaultValue: "Finish") }
        let distance = unitSystem.distanceString(meters: photo.distAtShot, fractionDigits: 1)
        return compact ? distance : String(localized: "Photo at \(distance)")
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if currentActivity.source.kind != .outbound {
                ActivityMetadataRow(
                    icon: sourceIcon,
                    title: sourceTitle,
                    detail: currentActivity.source.deviceName ?? sourceDetail
                )
            }

            if let gear = currentActivity.gear {
                ActivityMetadataRow(icon: "shoeprints.fill", title: String(localized: "activity.meta.shoes", defaultValue: "Shoes"), detail: gear.shoeName)
            }

            if currentActivity.indoor?.isIndoor == true {
                ActivityMetadataRow(icon: "figure.run.treadmill", title: String(localized: "activity.meta.treadmill", defaultValue: "Treadmill"), detail: String(localized: "activity.meta.indoor_run", defaultValue: "Indoor run"))
            }

            if let cadence = currentActivity.cadence,
               cadence.averageStepsPerMinute != nil || cadence.maxStepsPerMinute != nil {
                ActivityMetadataRow(
                    icon: "metronome.fill",
                    title: String(localized: "activity.meta.cadence.title", defaultValue: "Cadence"),
                    detail: [
                        cadence.averageStepsPerMinute.map { String(localized: "Avg \($0) spm") },
                        cadence.maxStepsPerMinute.map { String(localized: "Max \($0) spm") }
                    ].compactMap { $0 }.joined(separator: " • ")
                )
            }

            if let zones = currentActivity.heartRateZones {
                HeartRateZonesMiniView(summary: zones)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
    }

    private var showsMetadataSection: Bool {
        currentActivity.source.kind != .outbound
            || currentActivity.gear != nil
            || currentActivity.indoor?.isIndoor == true
            || currentActivity.cadence?.averageStepsPerMinute != nil
            || currentActivity.cadence?.maxStepsPerMinute != nil
            || currentActivity.heartRateZones != nil
    }

    private var sourceTitle: String {
        if currentActivity.manualEdits != nil { return String(localized: "activity.source.edited", defaultValue: "Edited activity") }
        return currentActivity.source.displayName
    }

    private var sourceDetail: String {
        if let edits = currentActivity.manualEdits {
            return edits.editedFields.joined(separator: ", ")
        }
        switch currentActivity.source.kind {
        case .outbound: return String(localized: "activity.source.outbound", defaultValue: "Recorded in Plainstride")
        case .appleHealth: return String(localized: "activity.source.apple_health", defaultValue: "Imported from Apple Health")
        case .garminViaHealth: return String(localized: "activity.source.garmin_via_health", defaultValue: "Garmin via Apple Health")
        case .manual: return String(localized: "activity.source.manual", defaultValue: "Manual entry")
        case .importedFile: return String(localized: "activity.source.imported_file", defaultValue: "Imported file")
        }
    }

    private var sourceIcon: String {
        if currentActivity.manualEdits != nil { return "pencil" }
        switch currentActivity.source.kind {
        case .outbound: return "iphone"
        case .appleHealth, .garminViaHealth: return "heart.text.square.fill"
        case .manual: return "square.and.pencil"
        case .importedFile: return "doc.badge.arrow.up"
        }
    }

    // MARK: - Splits

    private var splitsSection: some View {
        let fastestPace = splits.map(\.pace).filter { $0 > 0 }.min() ?? 0
        let slowestPace = splits.map(\.pace).filter { $0 > 0 }.max() ?? fastestPace
        let showElevation = splits.contains { $0.elevationChangeM != nil }

        return VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { showSplits.toggle() }
            } label: {
                HStack {
                    Text(String(localized: "activity.splits.title", defaultValue: "Splits"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(splits.count) \(unitSystem.distanceUnit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showSplits ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showSplits {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text(unitSystem.distanceUnit.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .leading)
                        Text(String(localized: "activity.splits.pace", defaultValue: "Pace"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .leading)
                        Spacer()
                        if showElevation {
                            Text(String(localized: "activity.splits.elev", defaultValue: "Elev"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                    ForEach(splits) { split in
                        SplitRow(
                            split: split,
                            unitSystem: unitSystem,
                            paceFraction: splitPaceFraction(
                                pace: split.pace,
                                fastestPace: fastestPace,
                                slowestPace: slowestPace
                            ),
                            showElevation: showElevation
                        )
                    }
                }
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Guide Hero Card

    private func guideHeroCard(_ reflection: FinishReflection?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(reflection?.title ?? String(localized: "activity.guide.reflection_title", defaultValue: "A moment to reflect"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "activity.guide.companion", defaultValue: "Your companion"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(reflection?.body ?? String(localized: "activity.guide.reflection_body", defaultValue: "You showed up and added another honest effort to your story. Notice what felt strong and carry that into the next one."))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !currentActivity.guideNudge.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(currentActivity.guideNudge)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Share Sheet

    private var isShareSheetPresented: Binding<Bool> {
        Binding(
            get: { shareImage != nil || shareURL != nil },
            set: { isPresented in
                if !isPresented {
                    shareImage = nil
                    shareURL = nil
                }
            }
        )
    }

    private func shareActivityCard() {
        isPreparingShareCard = true
        Task { @MainActor in
            defer { isPreparingShareCard = false }
            do {
                let referralURL = (try? await APIClient.shared.createReferralLink())?.url
                    ?? PlainstrideLinks.appInvitation
                let cardImage = try await ActivityShareCardRenderer.renderCard(
                    activity: currentActivity,
                    unitSystem: unitSystem,
                    referralURL: referralURL
                )
                shareImage = cardImage
            } catch {
                shareError = ShareRouteError(message: error.localizedDescription)
            }
        }
    }

    private func shareRoute(_ format: RouteExportFormat) {
        Task {
            do {
                shareURL = try await activityStore.exportRoute(for: currentActivity, format: format)
            } catch {
                shareError = ShareRouteError(message: error.localizedDescription)
            }
        }
    }
}
// MARK: - Sheet Detents

private enum ActivityDetailSheetDetent: CaseIterable {
    case collapsed
    case split
    case expanded

    func height(in proxy: GeometryProxy) -> CGFloat {
        let availableHeight = proxy.size.height
        switch self {
        case .collapsed:
            return min(132 + proxy.safeAreaInsets.bottom, availableHeight * 0.28)
        case .split:
            return min(max(340, availableHeight * 0.48), availableHeight * 0.62)
        case .expanded:
            return maximumHeight(in: proxy)
        }
    }

    func minimumHeight(in proxy: GeometryProxy) -> CGFloat {
        Self.collapsed.height(in: proxy)
    }

    func maximumHeight(in proxy: GeometryProxy) -> CGFloat {
        proxy.size.height + proxy.safeAreaInsets.bottom
    }

    static func nearest(to height: CGFloat, in proxy: GeometryProxy) -> ActivityDetailSheetDetent {
        allCases.min {
            abs($0.height(in: proxy) - height) < abs($1.height(in: proxy) - height)
        } ?? .split
    }

    static func snapTarget(
        from current: ActivityDetailSheetDetent,
        translation: CGFloat,
        projectedHeight: CGFloat,
        in proxy: GeometryProxy
    ) -> ActivityDetailSheetDetent {
        if translation < -56 {
            switch current {
            case .collapsed:
                return .split
            case .split, .expanded:
                return .expanded
            }
        }

        if translation > 56 {
            switch current {
            case .collapsed:
                return .collapsed
            case .split:
                return .collapsed
            case .expanded:
                return .split
            }
        }

        return nearest(to: projectedHeight, in: proxy)
    }
}

// MARK: - Photo Lightbox

private struct ActivityPhotoLightbox: View {
    let photos: [SavedPhoto]
    @Binding var selectedIndex: Int
    let imageURL: (SavedPhoto) -> URL?
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    if let url = imageURL(photo) {
                        LocalImageView(url: url) { Color.black }
                            .scaledToFit()
                            .padding(.vertical, 72)
                            .tag(index)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                HStack {
                    Text(String(localized: "Photo \(selectedIndex + 1) of \(photos.count)"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel(String(localized: "activity.photos.close", defaultValue: "Close photo"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                if photos.indices.contains(selectedIndex) {
                    let photo = photos[selectedIndex]
                    Text(lightboxCaption(photo, index: selectedIndex))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
        }
        .statusBarHidden()
    }

    private func lightboxCaption(_ photo: SavedPhoto, index: Int) -> String {
        if index == 0 { return String(localized: "activity.photos.trailhead_start", defaultValue: "Trailhead start") }
        if index == photos.count - 1 { return String(localized: "activity.photos.finish_line", defaultValue: "Finish line") }
        return String(localized: "Activity moment \(index + 1)")
    }
}

// MARK: - Route Map

private struct ActivityRouteMapView: View {
    let routeCoordinates: [CLLocationCoordinate2D]
    let paceSegments: [(startIndex: Int, endIndex: Int, pace: Double)]
    let photos: [SavedPhoto]
    let bottomInset: CGFloat
    let isRouteProminent: Bool
    var selectedPhotoID: UUID? = nil

    var body: some View {
        Group {
            if routeCoordinates.count > 1 {
                ActivityRouteMapRepresentable(
                    routeCoordinates: routeCoordinates,
                    paceSegments: paceSegments,
                    photos: photos,
                    bottomInset: bottomInset,
                    isRouteProminent: isRouteProminent,
                    selectedPhotoID: selectedPhotoID
                )
            } else {
                Color(.systemGroupedBackground)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "map")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text(String(localized: "activity.map.no_route", defaultValue: "No route data"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
    }
}

private struct ActivityRouteMapRepresentable: UIViewRepresentable {
    let routeCoordinates: [CLLocationCoordinate2D]
    let paceSegments: [(startIndex: Int, endIndex: Int, pace: Double)]
    let photos: [SavedPhoto]
    let bottomInset: CGFloat
    let isRouteProminent: Bool
    let selectedPhotoID: UUID?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.isPitchEnabled = false
        mapView.backgroundColor = .secondarySystemBackground
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.routeCoordinates = routeCoordinates
        context.coordinator.paceSegments = paceSegments
        context.coordinator.photos = photos
        context.coordinator.bottomInset = bottomInset
        context.coordinator.isRouteProminent = isRouteProminent
        context.coordinator.selectedPhotoID = selectedPhotoID
        context.coordinator.refresh(mapView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var routeCoordinates: [CLLocationCoordinate2D] = []
        var paceSegments: [(startIndex: Int, endIndex: Int, pace: Double)] = []
        var photos: [SavedPhoto] = []
        var bottomInset: CGFloat = 0
        var isRouteProminent = true
        var selectedPhotoID: UUID?

        private var previousRouteSignature: String?
        private var previousPhotoSignature: String?
        private var previousBottomInset: CGFloat?
        private var previousProminence: Bool?
        private var previousMapSize: CGSize?
        private var hasSetInitialRegion = false
        private var previousSelectedPhotoID: UUID?

        func refresh(_ mapView: MKMapView) {
            let routeSignature = "\(routeCoordinates.count)-\(routeCoordinates.first?.latitude ?? 0)-\(routeCoordinates.last?.longitude ?? 0)-\(isRouteProminent)"
            if routeSignature != previousRouteSignature {
                mapView.removeOverlays(mapView.overlays)
                addRouteOverlays(to: mapView)
                previousRouteSignature = routeSignature
            }

            let photoSignature = photos.map(\.id).map(\.uuidString).joined(separator: ",")
            if photoSignature != previousPhotoSignature {
                mapView.removeAnnotations(mapView.annotations)
                mapView.addAnnotations(photos.compactMap(ActivityRoutePhotoAnnotation.init(photo:)))
                previousPhotoSignature = photoSignature
            }

            if selectedPhotoID != previousSelectedPhotoID {
                updateSelectedPhoto(in: mapView)
                previousSelectedPhotoID = selectedPhotoID
            }

            let insetChanged = abs((previousBottomInset ?? -1) - bottomInset) > 6
            let prominenceChanged = previousProminence != isRouteProminent
            let sizeChanged = previousMapSize != mapView.bounds.size
            if mapView.bounds.width > 10,
               mapView.bounds.height > 10,
               insetChanged || prominenceChanged || sizeChanged || !hasSetInitialRegion {
                fitRoute(in: mapView, animated: hasSetInitialRegion)
                previousBottomInset = bottomInset
                previousProminence = isRouteProminent
                previousMapSize = mapView.bounds.size
                hasSetInitialRegion = true
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? ActivityRoutePolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = polyline.strokeColor
            renderer.lineWidth = polyline.lineWidth
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let photoAnnotation = annotation as? ActivityRoutePhotoAnnotation else { return nil }
            let identifier = "activity-photo"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            if let markerView = view as? MKMarkerAnnotationView {
                markerView.glyphImage = UIImage(systemName: "camera.fill")
                markerView.markerTintColor = .systemOrange
                markerView.glyphTintColor = .white
                markerView.displayPriority = .required
                markerView.transform = photoAnnotation.photoID == selectedPhotoID
                    ? CGAffineTransform(scaleX: 1.22, y: 1.22)
                    : .identity
            }
            return view
        }

        private func updateSelectedPhoto(in mapView: MKMapView) {
            for annotation in mapView.annotations {
                guard let photoAnnotation = annotation as? ActivityRoutePhotoAnnotation,
                      let view = mapView.view(for: annotation) else { continue }
                UIView.animate(withDuration: 0.22) {
                    view.transform = photoAnnotation.photoID == self.selectedPhotoID
                        ? CGAffineTransform(scaleX: 1.22, y: 1.22)
                        : .identity
                }
            }
            guard let selectedPhotoID,
                  let annotation = mapView.annotations.compactMap({ $0 as? ActivityRoutePhotoAnnotation })
                    .first(where: { $0.photoID == selectedPhotoID }) else { return }
            mapView.setCenter(annotation.coordinate, animated: true)
            mapView.selectAnnotation(annotation, animated: true)
        }

        private func addRouteOverlays(to mapView: MKMapView) {
            guard routeCoordinates.count > 1 else { return }

            let shadow = ActivityRoutePolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
            shadow.strokeColor = UIColor.black.withAlphaComponent(0.18)
            shadow.lineWidth = isRouteProminent ? 8 : 6
            mapView.addOverlay(shadow, level: .aboveRoads)

            if paceSegments.isEmpty {
                let route = ActivityRoutePolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
                route.strokeColor = .systemOrange
                route.lineWidth = isRouteProminent ? 5 : 4
                mapView.addOverlay(route, level: .aboveRoads)
                return
            }

            for segment in paceSegments {
                guard segment.startIndex < routeCoordinates.count,
                      segment.endIndex < routeCoordinates.count,
                      segment.endIndex > segment.startIndex else { continue }
                let coordinates = Array(routeCoordinates[segment.startIndex...segment.endIndex])
                let route = ActivityRoutePolyline(coordinates: coordinates, count: coordinates.count)
                route.strokeColor = paceUIColor(segment.pace)
                route.lineWidth = isRouteProminent ? 5 : 4
                mapView.addOverlay(route, level: .aboveRoads)
            }
        }

        private func fitRoute(in mapView: MKMapView, animated: Bool) {
            guard routeCoordinates.count > 1 else { return }
            guard mapView.bounds.width > 10, mapView.bounds.height > 10 else { return }

            var mapRect = MKMapRect.null
            for coordinate in routeCoordinates {
                let point = MKMapPoint(coordinate)
                let pointRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
                mapRect = mapRect.union(pointRect)
            }

            if mapRect.width < 250 {
                mapRect = mapRect.insetBy(dx: -250, dy: 0)
            }
            if mapRect.height < 250 {
                mapRect = mapRect.insetBy(dx: 0, dy: -250)
            }

            let mapHeight = max(mapView.bounds.height, 1)
            let clampedBottom = min(bottomInset + 28, mapHeight * (isRouteProminent ? 0.72 : 0.42))
            let topInset = isRouteProminent ? CGFloat(84) : CGFloat(52)
            let padding = UIEdgeInsets(top: topInset, left: 28, bottom: clampedBottom, right: 28)
            mapView.setVisibleMapRect(mapRect, edgePadding: padding, animated: animated)
        }
    }
}

private final class ActivityRoutePolyline: MKPolyline {
    var strokeColor: UIColor = .systemOrange
    var lineWidth: CGFloat = 5
}

private final class ActivityRoutePhotoAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let photoID: UUID

    nonisolated init?(photo: SavedPhoto) {
        guard let photoCoordinate = photo.coordinate else { return nil }
        photoID = photo.id
        coordinate = CLLocationCoordinate2D(
            latitude: photoCoordinate.latitude,
            longitude: photoCoordinate.longitude
        )
        super.init()
    }
}

// MARK: - Split Model

private struct ActivitySplit: Identifiable {
    let number: Int
    let timeSeconds: Int
    let pace: Double
    let distanceMeters: Double
    let elevationChangeM: Double?
    let heartRateBPM: Int?
    var id: Int { number }
}

private struct ActivityElevationProfilePoint: Identifiable {
    let id: Int
    let distanceMeters: Double
    let altitudeMeters: Double
}

// MARK: - Split Row

private struct SplitRow: View {
    let split: ActivitySplit
    let unitSystem: MeasurementUnitSystem
    let paceFraction: Double
    let showElevation: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(split.number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)

            Text(split.pace.paceString(for: unitSystem))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
                .frame(width: 54, alignment: .leading)

            GeometryReader { proxy in
                let barWidth = max(18, proxy.size.width * paceFraction)
                Capsule()
                    .fill(Color.blue)
                    .frame(width: barWidth, height: 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 18)

            if showElevation {
                Text(split.elevationChangeM.map { signedElevationString(meters: $0, unitSystem: unitSystem) } ?? "--")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }
}

// MARK: - Helper Types

private struct ShareRouteError: Identifiable {
    let id = UUID()
    let message: String
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct DetailActivityStat: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

private struct DetailStatCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActivityMetadataRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail.isEmpty ? "--" : detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
    }
}

private struct HeartRateZonesMiniView: View {
    let summary: ActivityHeartRateZoneSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Heart-rate zones", systemImage: "heart.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("Max \(summary.estimatedMaxHeartRate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 3) {
                ForEach(summary.zones) { zone in
                    Capsule()
                        .fill(zone.seconds > 0 ? Color.orange : Color(.tertiarySystemFill))
                        .frame(maxWidth: .infinity)
                        .frame(height: 8)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct EditActivityView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var gearStore: GearStore

    let activity: SavedActivity
    @State private var title: String
    @State private var startedAt: Date
    @State private var distanceText: String
    @State private var durationMinutesText: String
    @State private var shoeID: UUID?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isPhotoManagerPresented = false

    init(activity: SavedActivity) {
        self.activity = activity
        _title = State(initialValue: activity.title)
        _startedAt = State(initialValue: activity.startedAt)
        _distanceText = State(initialValue: String(format: "%.2f", activity.distanceM / 1000))
        _durationMinutesText = State(initialValue: String(format: "%.0f", Double(activity.durationSecs) / 60))
        _shoeID = State(initialValue: activity.gear?.shoeID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    TextField("Title", text: $title)
                    DatePicker("Date", selection: $startedAt)
                    TextField("Distance in km", text: $distanceText)
                        .keyboardType(.decimalPad)
                    TextField("Duration in minutes", text: $durationMinutesText)
                        .keyboardType(.numberPad)
                }

                Section("Gear") {
                    Picker("Shoes", selection: $shoeID) {
                        Text("None").tag(UUID?.none)
                        ForEach(gearStore.activeShoes) { shoe in
                            Text(shoe.displayName).tag(Optional(shoe.id))
                        }
                    }
                }

                Section(String(localized: "activity.photos.title", defaultValue: "Photos")) {
                    Button {
                        isPhotoManagerPresented = true
                    } label: {
                        Label(
                            String(localized: "summary.photos.manage", defaultValue: "Manage Photos"),
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }
                }
            }
            .navigationTitle("Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                        .disabled(isSaving || !hasChanges)
                        .fontWeight(.semibold)
                }
            }
        }
        .alert("Couldn’t save activity", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Try again.")
        }
        .sheet(isPresented: $isPhotoManagerPresented) {
            SavedActivityPhotoManager(activity: activity)
                .environmentObject(activityStore)
        }
    }

    private var hasChanges: Bool {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let distanceM = (Double(distanceText) ?? activity.distanceM / 1000) * 1000
        let durationSecs = max(1, Int((Double(durationMinutesText) ?? Double(activity.durationSecs) / 60) * 60))

        return (!cleanedTitle.isEmpty && cleanedTitle != activity.title)
            || startedAt != activity.startedAt
            || abs(distanceM - activity.distanceM) > 0.5
            || durationSecs != activity.durationSecs
            || shoeID != activity.gear?.shoeID
    }

    private func save() async {
        guard !isSaving, hasChanges else { return }
        isSaving = true
        defer { isSaving = false }
        let distanceM = (Double(distanceText) ?? activity.distanceM / 1000) * 1000
        let durationSecs = max(1, Int((Double(durationMinutesText) ?? Double(activity.durationSecs) / 60) * 60))
        let selectedShoe = shoeID.flatMap { id in gearStore.shoes.first { $0.id == id } }
        do {
            try await activityStore.updateActivity(
                activity,
                title: title,
                startedAt: startedAt,
                distanceM: distanceM,
                durationSecs: durationSecs,
                gear: gearStore.attachment(for: selectedShoe)
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct SavedActivityPhotoManager: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var activityStore: ActivityStore
    let activity: SavedActivity
    @State private var keptPhotos: [SavedPhoto]
    @State private var newPhotos: [PostRunPhoto] = []
    @State private var isCameraPresented = false
    @State private var isSaving = false
    @State private var saveError: String?

    init(activity: SavedActivity) {
        self.activity = activity
        _keptPhotos = State(initialValue: activity.photos)
    }

    private var photoMetadata: PhotoMetadata {
        PhotoMetadata(
            takenAt: Date(),
            paceAtShot: activity.avgPace,
            hrAtShot: activity.healthMetrics?.averageHeartRateBPM,
            distAtShot: activity.distanceM,
            coordinate: activity.routeCoordinates.last,
            captureContext: .paused
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { isCameraPresented = true } label: {
                        Label(String(localized: "summary.photos.take", defaultValue: "Take Photo"), systemImage: "camera.fill")
                    }
                }

                if !keptPhotos.isEmpty || !newPhotos.isEmpty {
                    Section(String(localized: "summary.photos.reorder", defaultValue: "Photos — drag to reorder")) {
                        ForEach(keptPhotos) { photo in
                            HStack(spacing: 12) {
                                if let url = activityStore.imageURL(for: photo) {
                                    LocalImageView(url: url) { Color(.systemGroupedBackground) }
                                        .frame(width: 72, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Text(photo.takenAt, style: .time).foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { keptPhotos.remove(atOffsets: $0) }
                        .onMove { keptPhotos.move(fromOffsets: $0, toOffset: $1) }

                        ForEach(newPhotos) { photo in
                            HStack(spacing: 12) {
                                Image(uiImage: photo.image)
                                    .resizable().scaledToFill()
                                    .frame(width: 72, height: 56).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(photo.metadata.takenAt, style: .time).foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { newPhotos.remove(atOffsets: $0) }
                        .onMove { newPhotos.move(fromOffsets: $0, toOffset: $1) }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(String(localized: "summary.photos.manage.title", defaultValue: "Manage Photos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel", defaultValue: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? String(localized: "common.saving", defaultValue: "Saving…") : String(localized: "common.done", defaultValue: "Done")) {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                    .fontWeight(.semibold)
                }
            }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            PostRunCameraView { image in
                newPhotos.append(PostRunPhoto(image: image, metadata: photoMetadata))
            }
        }
        .alert(String(localized: "activity.photos.save_error", defaultValue: "Couldn’t update photos"), isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button(String(localized: "common.ok", defaultValue: "OK"), role: .cancel) {}
        } message: { Text(saveError ?? "") }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await activityStore.updatePhotos(
                for: activity,
                keeping: keptPhotos,
                adding: newPhotos.map { ($0.image, $0.metadata) }
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Computation Helpers

private func computeSplits(from points: [SavedRoutePoint], unitSystem: MeasurementUnitSystem) -> [ActivitySplit] {
    guard points.count > 1 else { return [] }

    let splitDistanceMeters: Double = unitSystem == .metric ? 1000 : 1609.344
    let distances = cumulativeDistances(from: points)
    var splits: [ActivitySplit] = []
    var lastSplitEndIndex = 0
    var splitNumber = 1

    for i in 1..<points.count {
        if distances[i] >= Double(splitNumber) * splitDistanceMeters || i == points.count - 1 {
            let segStart = lastSplitEndIndex
            let segEnd = i
            let segDistance = distances[segEnd] - distances[segStart]
            let segTime = points[segEnd].timestamp.timeIntervalSince(points[segStart].timestamp)
            let segPace = segDistance > 0 ? segTime / (segDistance / 1000) : 0

            if segDistance > 20 {
                let elevationChange: Double?
                if let startAltitude = points[segStart].altitude,
                   let endAltitude = points[segEnd].altitude {
                    elevationChange = endAltitude - startAltitude
                } else {
                    elevationChange = nil
                }

                splits.append(ActivitySplit(
                    number: splitNumber,
                    timeSeconds: Int(segTime),
                    pace: segPace,
                    distanceMeters: segDistance,
                    elevationChangeM: elevationChange,
                    heartRateBPM: nil
                ))
                lastSplitEndIndex = i
                splitNumber += 1
            }
        }
    }

    return splits
}

private func computeElevationProfilePoints(from points: [SavedRoutePoint]) -> [ActivityElevationProfilePoint] {
    guard points.count > 1 else { return [] }
    let distances = cumulativeDistances(from: points)

    return points.enumerated().compactMap { index, point in
        guard let altitude = point.altitude else { return nil }
        if let verticalAccuracy = point.verticalAccuracy, verticalAccuracy < 0 {
            return nil
        }
        return ActivityElevationProfilePoint(
            id: index,
            distanceMeters: distances[index],
            altitudeMeters: altitude
        )
    }
}

private func elevationChartDomain(
    points: [ActivityElevationProfilePoint],
    unitSystem: MeasurementUnitSystem
) -> ClosedRange<Double> {
    let values = points.map { unitSystem.elevationValue(meters: $0.altitudeMeters) }
    guard let minimum = values.min(), let maximum = values.max() else {
        return 0...1
    }

    let spread = maximum - minimum
    let padding = max(spread * 0.25, unitSystem == .metric ? 8 : 25)
    return (minimum - padding)...(maximum + padding)
}

private func elevationChartDistanceDomain(
    points: [ActivityElevationProfilePoint],
    unitSystem: MeasurementUnitSystem
) -> ClosedRange<Double> {
    let maximum = points
        .map { unitSystem.distanceValue(meters: $0.distanceMeters) }
        .max() ?? 1
    return 0...max(maximum, 0.1)
}

private func maxElevationMeters(from points: [ActivityElevationProfilePoint]) -> Double? {
    points.map(\.altitudeMeters).max()
}

private func splitPaceFraction(pace: Double, fastestPace: Double, slowestPace: Double) -> Double {
    guard pace > 0, fastestPace > 0, slowestPace > fastestPace else {
        return 0.85
    }
    let normalized = (slowestPace - pace) / (slowestPace - fastestPace)
    return 0.28 + (max(0, min(1, normalized)) * 0.72)
}

private func signedElevationString(meters: Double, unitSystem: MeasurementUnitSystem) -> String {
    let value = Int(unitSystem.elevationValue(meters: meters).rounded())
    if value > 0 {
        return "+\(value)"
    }
    return "\(value)"
}

private func computePaceSegments(from points: [SavedRoutePoint]) -> [(startIndex: Int, endIndex: Int, pace: Double)] {
    guard points.count > 2 else { return [] }

    let segmentSize = 15
    var result: [(Int, Int, Double)] = []

    var segStart = 0
    while segStart < points.count - 1 {
        let segEnd = min(segStart + segmentSize, points.count - 1)
        let startLoc = points[segStart]
        let endLoc = points[segEnd]
        let dist = haversineDistance(
            lat1: startLoc.latitude, lon1: startLoc.longitude,
            lat2: endLoc.latitude, lon2: endLoc.longitude
        )
        let time = endLoc.timestamp.timeIntervalSince(startLoc.timestamp)
        let pace = dist > 0 && time > 0 ? time / (dist / 1000) : 0
        result.append((segStart, segEnd, pace))
        segStart = segEnd
    }

    return result
}

private func cumulativeDistances(from points: [SavedRoutePoint]) -> [Double] {
    guard !points.isEmpty else { return [] }
    var distances = [Double](repeating: 0, count: points.count)
    for i in 1..<points.count {
        let d = haversineDistance(
            lat1: points[i-1].latitude, lon1: points[i-1].longitude,
            lat2: points[i].latitude, lon2: points[i].longitude
        )
        distances[i] = distances[i-1] + d
    }
    return distances
}

private func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let r = 6_371_000.0
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let a = sin(dLat / 2) * sin(dLat / 2)
        + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
        * sin(dLon / 2) * sin(dLon / 2)
    return r * 2 * atan2(sqrt(a), sqrt(1 - a))
}

private func paceUIColor(_ pace: Double) -> UIColor {
    guard pace > 0, pace.isFinite else { return .systemOrange }
    let fast: Double = 240  // 4:00/km
    let slow: Double = 420  // 7:00/km
    let t = max(0, min(1, (pace - fast) / (slow - fast)))
    if t < 0.5 {
        let u = t / 0.5
        return UIColor(red: u, green: 1, blue: 0, alpha: 1)
    } else {
        let u = (t - 0.5) / 0.5
        return UIColor(red: 1, green: 1 - u, blue: 0, alpha: 1)
    }
}
