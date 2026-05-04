import MapKit
import SwiftUI
import UIKit

struct ActivityDetailView: View {
    let activity: SavedActivity
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var measurementPreferences: MeasurementPreferences
    @State private var shareURL: URL?
    @State private var shareError: ShareRouteError?

    private var currentActivity: SavedActivity {
        activityStore.activity(id: activity.id) ?? activity
    }

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

    private var activityStats: [DetailActivityStat] {
        var stats = [
            DetailActivityStat(label: "Distance", value: measurementPreferences.unitSystem.distanceString(meters: currentActivity.distanceM)),
            DetailActivityStat(label: "Time", value: currentActivity.durationSecs.formatted())
        ]
        if let pace = currentActivity.avgPace {
            stats.append(DetailActivityStat(label: "Avg Pace", value: pace.paceString(for: measurementPreferences.unitSystem)))
        }
        if let elevationGainM = currentActivity.elevationGainM {
            stats.append(DetailActivityStat(label: "Elev Gain", value: measurementPreferences.unitSystem.elevationString(meters: elevationGainM)))
        }
        if let averageHeartRate = currentActivity.healthMetrics?.averageHeartRateBPM {
            stats.append(DetailActivityStat(label: "Avg HR", value: "\(averageHeartRate) bpm"))
        }
        return stats
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                mapSection
                routeControls
                statsStrip
                if !currentActivity.coachNudge.isEmpty { coachSection }
                if !currentActivity.photos.isEmpty { photoGrid }
            }
        }
        .navigationTitle(currentActivity.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: isShareSheetPresented) {
            if let shareURL {
                ShareSheet(activityItems: [shareURL])
            }
        }
        .alert(item: $shareError) { error in
            Alert(title: Text("Unable to Share Route"), message: Text(error.message))
        }
    }

    private var mapSection: some View {
        Group {
            if routeCoordinates.count > 1 {
                Map(position: .constant(mapPosition)) {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(.black.opacity(0.15), lineWidth: 7)
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 240)
                .disabled(true)
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

    private var routeControls: some View {
        HStack(spacing: 12) {
            if currentActivity.hasRoute {
                Label("Private Route", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())

                Spacer()

                Text("\(currentActivity.routePoints.count) points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Menu {
                ForEach(RouteExportFormat.allCases) { format in
                    Button {
                        shareRoute(format)
                    } label: {
                        Label("Share \(format.title)", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Label("Share Route", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .disabled(!currentActivity.hasRoute)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var statsStrip: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 0),
                GridItem(.flexible(), spacing: 0),
                GridItem(.flexible(), spacing: 0)
            ],
            spacing: 14
        ) {
            ForEach(activityStats) { stat in
                DetailStatCell(label: stat.label, value: stat.value)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground))
    }

    private var coachSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run.circle.fill")
                .foregroundStyle(.orange)
            Text(currentActivity.coachNudge)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.07))
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var photoGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Photos")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)],
                spacing: 2
            ) {
                ForEach(currentActivity.photos) { photo in
                    if let url = activityStore.imageURL(for: photo) {
                        LocalImageView(url: url) {
                            Color(.systemGroupedBackground)
                        }
                        .frame(height: 160)
                        .clipped()
                    }
                }
            }
        }
    }

    private var isShareSheetPresented: Binding<Bool> {
        Binding(
            get: { shareURL != nil },
            set: { isPresented in
                if !isPresented {
                    shareURL = nil
                }
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
        VStack(spacing: 4) {
            Text(value).font(.callout.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
