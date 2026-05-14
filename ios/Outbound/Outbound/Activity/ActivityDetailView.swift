import Charts
import MapKit
import SwiftUI
import UIKit

// MARK: - Main View

struct ActivityDetailView: View {
    let activity: SavedActivity
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var measurementPreferences: MeasurementPreferences
    @State private var shareURL: URL?
    @State private var shareError: ShareRouteError?
    @State private var showSplits = false
    @State private var showElevationProfile = false
    @State private var sheetDetent: ActivityDetailSheetDetent = .split
    @State private var sheetDragHeight: CGFloat?

    private var currentActivity: SavedActivity {
        activityStore.activity(id: activity.id) ?? activity
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
        var stats = [
            DetailActivityStat(label: "Distance", value: primaryStat),
        ]
        if let pace = currentActivity.avgPace {
            stats.append(DetailActivityStat(label: "Avg Pace", value: pace.paceString(for: unitSystem)))
        }
        stats.append(DetailActivityStat(label: "Moving Time", value: currentActivity.durationSecs.formatted()))
        if let elevationGainM = currentActivity.elevationGainM {
            stats.append(DetailActivityStat(label: "Elev Gain", value: unitSystem.elevationString(meters: elevationGainM)))
        }
        if let maxElevation = maxElevationMeters(from: elevationProfilePoints) {
            stats.append(DetailActivityStat(label: "Max Elevation", value: unitSystem.elevationString(meters: maxElevation)))
        }
        if let hr = currentActivity.healthMetrics?.averageHeartRateBPM {
            stats.append(DetailActivityStat(label: "Avg HR", value: "\(hr) bpm"))
        }
        return stats
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
                ActivityRouteMapView(
                    routeCoordinates: routeCoordinates,
                    paceSegments: paceSegments,
                    photos: currentActivity.photos,
                    bottomInset: interactiveSheetHeight,
                    isRouteProminent: sheetDetent != .expanded
                )
                .ignoresSafeArea()

                activitySheet(height: interactiveSheetHeight, proxy: proxy)
                    .simultaneousGesture(sheetDragGesture(in: proxy))
            }
            .animation(sheetDragHeight == nil ? .snappy(duration: 0.32) : nil, value: sheetDetent)
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .navigationTitle(currentActivity.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar(sheetDetent == .expanded ? .hidden : .visible, for: .navigationBar)
        .sheet(isPresented: isShareSheetPresented) {
            if let shareURL {
                ShareSheet(activityItems: [shareURL])
            }
        }
        .alert(item: $shareError) { error in
            Alert(title: Text("Unable to Share Route"), message: Text(error.message))
        }
    }

    // MARK: - Sheet

    private func activitySheet(height: CGFloat, proxy: GeometryProxy) -> some View {
        let isExpandedHeight = height >= ActivityDetailSheetDetent.expanded.height(in: proxy) - 1
        let topRadius: CGFloat = isExpandedHeight ? 0 : 22

        return VStack(spacing: 0) {
            sheetGrabber
                .padding(.top, 8)
                .padding(.bottom, sheetDetent == .collapsed ? 2 : 6)

            if sheetDetent == .collapsed {
                collapsedSummary
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                ScrollView(showsIndicators: sheetDetent == .expanded) {
                    VStack(spacing: 0) {
                        statsHeroSection
                        elevationProfileSection
                        if !splits.isEmpty { splitsSection }
                        routeControlsSection
                        if let reflection = currentActivity.reflection { coachHeroCard(reflection) }
                        if !currentActivity.photos.isEmpty { photoSection }
                    }
                    .padding(.bottom, proxy.safeAreaInsets.bottom + 24)
                }
                .scrollDisabled(sheetDetent != .expanded)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
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

    private var sheetGrabber: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 42, height: 5)
            .onTapGesture {
                withAnimation(.snappy) {
                    sheetDetent = sheetDetent == .expanded ? .split : .expanded
                }
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
            withAnimation(.snappy) { sheetDetent = .split }
        }
    }

    private func sheetDragGesture(in proxy: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
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
                withAnimation(.snappy(duration: 0.32)) {
                    sheetDetent = target
                    sheetDragHeight = nil
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
                        Text("Elevation")
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

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20),
                ],
                alignment: .leading,
                spacing: 18
            ) {
                ForEach(activityStats) { stat in
                    DetailStatCell(label: stat.label, value: stat.value)
                }
            }
            .padding(.horizontal, 28)
        }
        .padding(.top, 22)
        .padding(.bottom, 24)
        .background(Color(.systemBackground))
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
                    Text("Splits")
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
                        Text("Pace")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .leading)
                        Spacer()
                        if showElevation {
                            Text("Elev")
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

    // MARK: - Coach Hero Card

    private func coachHeroCard(_ reflection: FinishReflection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(reflection.title)
                        .font(.subheadline.weight(.semibold))
                    Text("Your Coach")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(reflection.body)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !currentActivity.coachNudge.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(currentActivity.coachNudge)
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

    // MARK: - Photos

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Photos")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(currentActivity.photos) { photo in
                        if let url = activityStore.imageURL(for: photo) {
                            VStack(spacing: 4) {
                                LocalImageView(url: url) {
                                    Color(.systemGroupedBackground)
                                }
                                .frame(width: 200, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                                Text("At \(unitSystem.distanceValue(meters: photo.distAtShot), specifier: "%.1f") \(unitSystem.distanceUnit)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Route Controls (inline)

    private var routeControlsSection: some View {
        HStack(spacing: 12) {
            if currentActivity.hasRoute {
                Label("Private", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
            }

            Spacer()

            Menu {
                ForEach(RouteExportFormat.allCases) { format in
                    Button {
                        shareRoute(format)
                    } label: {
                        Label("Export \(format.title)", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .disabled(!currentActivity.hasRoute)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Share Sheet

    private var isShareSheetPresented: Binding<Bool> {
        Binding(
            get: { shareURL != nil },
            set: { isPresented in
                if !isPresented { shareURL = nil }
            }
        )
    }

    private func shareRoute(_ format: RouteExportFormat) {
        do {
            shareURL = try activityStore.exportRoute(for: currentActivity, format: format)
        } catch {
            shareError = ShareRouteError(message: error.localizedDescription)
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

// MARK: - Route Map

private struct ActivityRouteMapView: View {
    let routeCoordinates: [CLLocationCoordinate2D]
    let paceSegments: [(startIndex: Int, endIndex: Int, pace: Double)]
    let photos: [SavedPhoto]
    let bottomInset: CGFloat
    let isRouteProminent: Bool

    var body: some View {
        Group {
            if routeCoordinates.count > 1 {
                ActivityRouteMapRepresentable(
                    routeCoordinates: routeCoordinates,
                    paceSegments: paceSegments,
                    photos: photos,
                    bottomInset: bottomInset,
                    isRouteProminent: isRouteProminent
                )
            } else {
                Color(.systemGroupedBackground)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "map")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No route data")
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

        private var previousRouteSignature: String?
        private var previousPhotoSignature: String?
        private var previousBottomInset: CGFloat?
        private var previousProminence: Bool?
        private var previousMapSize: CGSize?
        private var hasSetInitialRegion = false

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
            guard annotation is ActivityRoutePhotoAnnotation else { return nil }
            let identifier = "activity-photo"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            if let markerView = view as? MKMarkerAnnotationView {
                markerView.glyphImage = UIImage(systemName: "camera.fill")
                markerView.markerTintColor = .systemOrange
                markerView.glyphTintColor = .white
                markerView.displayPriority = .required
            }
            return view
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

    nonisolated init?(photo: SavedPhoto) {
        guard let photoCoordinate = photo.coordinate else { return nil }
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
