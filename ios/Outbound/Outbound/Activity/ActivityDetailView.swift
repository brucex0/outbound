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
    @State private var showFullMap = false
    @State private var showSplits = false
    @State private var showElevationProfile = false

    private var currentActivity: SavedActivity {
        activityStore.activity(id: activity.id) ?? activity
    }

    private var unitSystem: MeasurementUnitSystem { measurementPreferences.unitSystem }

    // MARK: Map

    private var mapPosition: MapCameraPosition {
        guard currentActivity.hasRoute else { return .automatic }
        let lats = currentActivity.routePoints.map(\.latitude)
        let lngs = currentActivity.routePoints.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.5, 0.005),
            longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.5, 0.005)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        currentActivity.routeCoordinates
    }

    // MARK: Computed values

    private var primaryStat: String {
        unitSystem.distanceString(meters: currentActivity.distanceM)
    }

    private var activityStats: [DetailActivityStat] {
        var stats = [
            DetailActivityStat(label: "Time", value: currentActivity.durationSecs.formatted()),
        ]
        if let pace = currentActivity.avgPace {
            stats.append(DetailActivityStat(label: "Avg Pace", value: pace.paceString(for: unitSystem)))
        }
        if let elevationGainM = currentActivity.elevationGainM {
            stats.append(DetailActivityStat(label: "Elev Gain", value: unitSystem.elevationString(meters: elevationGainM)))
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
        ScrollView {
            VStack(spacing: 0) {
                mapSection
                statsHeroSection
                elevationProfileSection
                if !splits.isEmpty { splitsSection }
                routeControlsSection
                if let reflection = currentActivity.reflection { coachHeroCard(reflection) }
                if !currentActivity.photos.isEmpty { photoSection }
            }
            .padding(.bottom, 110)
        }
        .navigationTitle(currentActivity.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: isShareSheetPresented) {
            if let shareURL {
                ShareSheet(activityItems: [shareURL])
            }
        }
        .fullScreenCover(isPresented: $showFullMap) {
            FullScreenMapView(
                routeCoordinates: routeCoordinates,
                photos: currentActivity.photos,
                activityStore: activityStore,
                mapPosition: mapPosition
            )
        }
        .alert(item: $shareError) { error in
            Alert(title: Text("Unable to Share Route"), message: Text(error.message))
        }
    }

    // MARK: - Map Section

    private var mapSection: some View {
        Group {
            if routeCoordinates.count > 1 {
                ZStack(alignment: .topTrailing) {
                    Map(position: .constant(mapPosition)) {
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(.black.opacity(0.15), lineWidth: 7)
                        ForEach(paceSegments.indices, id: \.self) { index in
                            let seg = paceSegments[index]
                            let coords = Array(routeCoordinates[seg.startIndex...seg.endIndex])
                            if coords.count > 1 {
                                MapPolyline(coordinates: coords)
                                    .stroke(paceColor(seg.pace),
                                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                            }
                        }
                        ForEach(currentActivity.photos) { photo in
                            if let coord = photo.coordinate {
                                Annotation("", coordinate: CLLocationCoordinate2D(
                                    latitude: coord.latitude, longitude: coord.longitude
                                )) {
                                    Image(systemName: "camera.fill")
                                        .font(.caption2)
                                        .padding(4)
                                        .background(.ultraThinMaterial, in: Circle())
                                }
                            }
                        }
                    }
                    .frame(height: 260)

                    Button {
                        showFullMap = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .padding(8)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(10)
                    }
                }
            } else {
                Color(.systemGroupedBackground)
                    .frame(height: 240)
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
                    Chart(elevationProfilePoints) { point in
                        LineMark(
                            x: .value("Distance", unitSystem.distanceValue(meters: point.distanceMeters)),
                            y: .value("Elevation", unitSystem.elevationValue(meters: point.altitudeMeters))
                        )
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(Color.orange.gradient)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                            AxisValueLabel()
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                            AxisValueLabel()
                        }
                    }
                    .chartXAxisLabel(unitSystem.distanceUnit, alignment: .trailing)
                    .chartYAxisLabel(unitSystem.elevationUnit, alignment: .trailing)
                    .frame(height: 80)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(Color(.secondarySystemBackground).opacity(0.3))
        }
    }

    // MARK: - Stats Hero

    private var statsHeroSection: some View {
        VStack(spacing: 6) {
            // Primary: large distance
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(primaryStat)
                        .font(.largeTitle.bold().monospacedDigit())
                    Text("Distance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            // Secondary: 2×2 grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 0),
                    GridItem(.flexible(), spacing: 0),
                ],
                spacing: 8
            ) {
                ForEach(activityStats) { stat in
                    DetailStatCell(label: stat.label, value: stat.value)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Splits

    private var splitsSection: some View {
        VStack(spacing: 0) {
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
                    HStack(spacing: 0) {
                        Text(unitSystem.distanceUnit.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 36, alignment: .leading)
                        Text("Time")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("Pace")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        if currentActivity.elevationGainM != nil {
                            Text("Elev")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 44, alignment: .trailing)
                        }
                        if currentActivity.healthMetrics?.averageHeartRateBPM != nil {
                            Text("HR")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                    Divider()

                    ForEach(Array(splits.enumerated()), id: \.offset) { _, split in
                        SplitRow(
                            split: split,
                            unitSystem: unitSystem,
                            showElevation: currentActivity.elevationGainM != nil,
                            showHeartRate: currentActivity.healthMetrics?.averageHeartRateBPM != nil
                        )
                        Divider().padding(.leading, 16)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.secondarySystemBackground).opacity(0.15))
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
                .foregroundStyle(.secondary)
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
        .background(Color.orange.opacity(0.06))
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

// MARK: - Full-Screen Map

private struct FullScreenMapView: View {
    let routeCoordinates: [CLLocationCoordinate2D]
    let photos: [SavedPhoto]
    let activityStore: ActivityStore
    let mapPosition: MapCameraPosition
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Map(position: .constant(mapPosition)) {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(.black.opacity(0.12), lineWidth: 8)
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                ForEach(photos) { photo in
                    if let coord = photo.coordinate {
                        Annotation("", coordinate: CLLocationCoordinate2D(
                            latitude: coord.latitude, longitude: coord.longitude
                        )) {
                            Image(systemName: "camera.fill")
                                .font(.caption)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                }
            }
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
    let showElevation: Bool
    let showHeartRate: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("\(split.number)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)

            Text(split.timeSeconds.formatted())
                .font(.callout.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(split.pace.paceString(for: unitSystem))
                .font(.callout.monospacedDigit())
                .frame(maxWidth: .infinity)

            if showElevation {
                Text(unitSystem.elevationString(meters: split.elevationChangeM ?? 0))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }

            if showHeartRate {
                Text(split.heartRateBPM.map { "\($0)" } ?? "--")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
        VStack(spacing: 2) {
            Text(value).font(.subheadline.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
                splits.append(ActivitySplit(
                    number: splitNumber,
                    timeSeconds: Int(segTime),
                    pace: segPace,
                    distanceMeters: segDistance,
                    elevationChangeM: nil,
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

private func paceColor(_ pace: Double) -> Color {
    guard pace > 0, pace.isFinite else { return .orange }
    let fast: Double = 240  // 4:00/km
    let slow: Double = 420  // 7:00/km
    let t = max(0, min(1, (pace - fast) / (slow - fast)))
    if t < 0.5 {
        let u = t / 0.5
        return Color(red: u, green: 1, blue: 0)
    } else {
        let u = (t - 0.5) / 0.5
        return Color(red: 1, green: 1 - u, blue: 0)
    }
}
