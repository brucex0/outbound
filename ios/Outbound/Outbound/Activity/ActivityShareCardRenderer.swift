import CoreLocation
import SwiftUI
import UIKit

enum ActivityShareCardRenderer {
    @MainActor
    static func exportCard(activity: SavedActivity, unitSystem: MeasurementUnitSystem) throws -> URL {
        let card = ActivityShareCardView(activity: activity, unitSystem: unitSystem)
            .frame(width: 1080, height: 1350)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        guard let image = renderer.uiImage,
              let data = image.pngData() else {
            throw ActivityShareCardError.renderFailed
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName(for: activity))
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func fileName(for activity: SavedActivity) -> String {
        let rawTitle = activity.title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
        let title = rawTitle.isEmpty ? "activity-\(activity.id.uuidString.prefix(8))" : rawTitle
        return "\(title)-outbound-card.png"
    }
}

enum ActivityShareCardError: LocalizedError {
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            return "The activity share card could not be rendered."
        }
    }
}

private struct ActivityShareCardView: View {
    let activity: SavedActivity
    let unitSystem: MeasurementUnitSystem

    private var dateText: String {
        activity.startedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
    }

    private var paceText: String {
        activity.avgPace?.paceString(for: unitSystem) ?? "--"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.08),
                    Color(red: 0.10, green: 0.11, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 42) {
                header
                routePanel
                statsGrid
                footer
            }
            .padding(70)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(dateText.uppercased())
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white.opacity(0.64))

            Text(activity.title)
                .font(.system(size: 70, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var routePanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36)
                .fill(Color.white.opacity(0.08))

            if activity.routeCoordinates.count > 1 {
                ActivityRouteTraceShape(coordinates: activity.routeCoordinates)
                    .stroke(
                        LinearGradient(
                            colors: [.orange, .red, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: .orange.opacity(0.34), radius: 22)
                    .padding(66)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 92, weight: .semibold))
                    Text("Activity complete")
                        .font(.system(size: 42, weight: .bold))
                }
                .foregroundStyle(.white.opacity(0.82))
            }
        }
        .frame(height: 530)
        .overlay(alignment: .bottomLeading) {
            Text(activity.routeCoordinates.count > 1 ? "Route trace" : "Stats only")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
                .padding(28)
        }
    }

    private var statsGrid: some View {
        HStack(spacing: 18) {
            ShareStat(label: "Distance", value: unitSystem.distanceString(meters: activity.distanceM))
            ShareStat(label: "Time", value: activity.durationSecs.formatted())
            ShareStat(label: "Pace", value: paceText)
            ShareStat(label: "Elev", value: activity.elevationGainM.map(unitSystem.elevationString(meters:)) ?? "--")
        }
    }

    private var footer: some View {
        HStack {
            Text("OUTBOUND")
                .font(.system(size: 28, weight: .black))
                .tracking(3)
            Spacer()
            Text("Shared from activity")
                .font(.system(size: 28, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.72))
    }
}

private struct ShareStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(value)
                .font(.system(size: 38, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
            Text(label.uppercased())
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct ActivityRouteTraceShape: Shape {
    let coordinates: [CLLocationCoordinate2D]

    func path(in rect: CGRect) -> Path {
        guard coordinates.count > 1 else { return Path() }

        let minLatitude = coordinates.map(\.latitude).min() ?? 0
        let maxLatitude = coordinates.map(\.latitude).max() ?? 0
        let minLongitude = coordinates.map(\.longitude).min() ?? 0
        let maxLongitude = coordinates.map(\.longitude).max() ?? 0
        let latitudeSpan = max(maxLatitude - minLatitude, 0.000001)
        let longitudeSpan = max(maxLongitude - minLongitude, 0.000001)

        func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
            CGPoint(
                x: rect.minX + ((coordinate.longitude - minLongitude) / longitudeSpan) * rect.width,
                y: rect.minY + ((maxLatitude - coordinate.latitude) / latitudeSpan) * rect.height
            )
        }

        var path = Path()
        path.move(to: point(for: coordinates[0]))
        for coordinate in coordinates.dropFirst() {
            path.addLine(to: point(for: coordinate))
        }
        return path
    }
}
