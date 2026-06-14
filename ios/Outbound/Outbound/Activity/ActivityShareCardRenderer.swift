import CoreLocation
import MapKit
import SwiftUI
import UIKit

enum ActivityShareCardRenderer {
    @MainActor
    static func exportCard(activity: SavedActivity, unitSystem: MeasurementUnitSystem) async throws -> URL {
        let mapImage = try? await ActivityShareMapSnapshotRenderer.snapshot(for: activity)
        let card = ActivityShareCardView(activity: activity, unitSystem: unitSystem, mapImage: mapImage)
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
    let mapImage: UIImage?

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

            if let mapImage {
                Image(uiImage: mapImage)
                    .resizable()
                    .scaledToFill()
                    .overlay {
                        LinearGradient(
                            colors: [
                                .black.opacity(0.02),
                                .black.opacity(0.12),
                                .black.opacity(0.70)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
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
        .frame(height: 760)
        .clipShape(RoundedRectangle(cornerRadius: 36))
        .overlay(alignment: .bottomLeading) {
            statsGrid
                .padding(28)
        }
        .overlay(alignment: .topLeading) {
            Text(mapImage == nil && activity.routeCoordinates.count <= 1 ? "Stats only" : "Route map")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.black.opacity(0.32), in: Capsule())
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

private enum ActivityShareMapSnapshotRenderer {
    private static let imageSize = CGSize(width: 940, height: 760)

    static func snapshot(for activity: SavedActivity) async throws -> UIImage {
        let coordinates = activity.routeCoordinates
        guard coordinates.count > 1 else { throw ActivityShareCardError.renderFailed }

        let options = MKMapSnapshotter.Options()
        options.size = imageSize
        options.scale = 1
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        options.mapRect = mapRect(for: coordinates, size: imageSize)

        let snapshot = try await MKMapSnapshotter(options: options).start()
        return drawRoute(coordinates, on: snapshot)
    }

    private static func mapRect(for coordinates: [CLLocationCoordinate2D], size: CGSize) -> MKMapRect {
        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }

        if rect.width < 300 {
            rect = rect.insetBy(dx: -300, dy: 0)
        }
        if rect.height < 300 {
            rect = rect.insetBy(dx: 0, dy: -300)
        }

        let targetAspect = size.width / size.height
        let currentAspect = rect.width / rect.height
        if currentAspect > targetAspect {
            let targetHeight = rect.width / targetAspect
            rect = rect.insetBy(dx: 0, dy: -(targetHeight - rect.height) / 2)
        } else {
            let targetWidth = rect.height * targetAspect
            rect = rect.insetBy(dx: -(targetWidth - rect.width) / 2, dy: 0)
        }

        return rect.insetBy(dx: -rect.width * 0.18, dy: -rect.height * 0.22)
    }

    private static func drawRoute(_ coordinates: [CLLocationCoordinate2D], on snapshot: MKMapSnapshotter.Snapshot) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { context in
            snapshot.image.draw(at: .zero)

            let path = UIBezierPath()
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: snapshot.point(for: coordinates[0]))
            for coordinate in coordinates.dropFirst() {
                path.addLine(to: snapshot.point(for: coordinate))
            }

            UIColor.black.withAlphaComponent(0.28).setStroke()
            path.lineWidth = 15
            path.stroke()

            UIColor.systemOrange.setStroke()
            path.lineWidth = 10
            path.stroke()

            drawEndpoint(at: snapshot.point(for: coordinates[0]), fill: .systemGreen, in: context.cgContext)
            drawEndpoint(at: snapshot.point(for: coordinates[coordinates.count - 1]), fill: .systemPink, in: context.cgContext)
        }
    }

    private static func drawEndpoint(at point: CGPoint, fill: UIColor, in context: CGContext) {
        let outer = CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28)
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: outer)

        let inner = outer.insetBy(dx: 5, dy: 5)
        context.setFillColor(fill.cgColor)
        context.fillEllipse(in: inner)
    }
}
