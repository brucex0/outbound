import MapKit
import SwiftUI

struct ActivityDetailView: View {
    let activity: SavedActivity
    @EnvironmentObject var activityStore: ActivityStore

    private var mapPosition: MapCameraPosition {
        guard !activity.trackPoints.isEmpty else { return .automatic }
        let lats = activity.trackPoints.map(\.latitude)
        let lngs = activity.trackPoints.map(\.longitude)
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
        activity.trackPoints.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                mapSection
                statsStrip
                if !activity.coachNudge.isEmpty { coachSection }
                if !activity.photos.isEmpty { photoGrid }
            }
        }
        .navigationTitle(activity.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var mapSection: some View {
        Group {
            if routeCoordinates.count > 1 {
                Map(position: .constant(mapPosition)) {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(.orange, lineWidth: 4)
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

    private var statsStrip: some View {
        HStack(spacing: 0) {
            DetailStatCell(label: "Distance",
                           value: String(format: "%.2f km", activity.distanceM / 1000))
            Divider().frame(height: 40)
            DetailStatCell(label: "Time",
                           value: activity.durationSecs.formatted())
            if let pace = activity.avgPace {
                Divider().frame(height: 40)
                DetailStatCell(label: "Avg Pace", value: pace.paceString)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground))
    }

    private var coachSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run.circle.fill")
                .foregroundStyle(.orange)
            Text(activity.coachNudge)
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
                ForEach(activity.photos) { photo in
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
