import MapKit
import SwiftUI

struct PostRunSummaryView: View {
    let summary: ActivitySummary
    let photos: [(UIImage, PhotoMetadata)]
    let lastNudge: String
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroImage
                statsSection
                if summary.trackPoints.count > 1 { routeMap }
                if !lastNudge.isEmpty { coachSection }
                if !photos.isEmpty { photoGrid }
                actionButtons
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var heroImage: some View {
        Group {
            if let (image, _) = photos.first {
                Image(uiImage: image)
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
        VStack(spacing: 20) {
            Text("Activity Complete")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                SummaryStatColumn(
                    label: "Distance",
                    value: String(format: "%.2f", summary.distanceM / 1000),
                    unit: "km"
                )
                Divider().frame(height: 48)
                SummaryStatColumn(
                    label: "Time",
                    value: summary.durationSecs.formatted(),
                    unit: ""
                )
                if let pace = summary.avgPace {
                    Divider().frame(height: 48)
                    SummaryStatColumn(label: "Avg Pace", value: pace.paceString, unit: "")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private var coachSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            Text(lastNudge)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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

    private var photoGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photos")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)],
                spacing: 2
            ) {
                ForEach(photos.indices, id: \.self) { i in
                    Image(uiImage: photos[i].0)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 160)
                        .clipped()
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: onSave) {
                Label("Save Run", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Button(role: .destructive, action: onDiscard) {
                Text("Discard")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
    }
}

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
