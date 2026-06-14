import CoreLocation
import MapKit
import SwiftUI
import UIKit

enum ActivityShareCardRenderer {
    private static let cardSize = CGSize(width: 1080, height: 1920)

    @MainActor
    static func exportCard(activity: SavedActivity, unitSystem: MeasurementUnitSystem) async throws -> URL {
        let mapImage = try? await ActivityShareMapSnapshotRenderer.snapshot(for: activity, size: cardSize)
        let card = ActivityShareCardView(activity: activity, unitSystem: unitSystem, mapImage: mapImage)
            .frame(width: cardSize.width, height: cardSize.height)

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
            if let mapImage {
                Image(uiImage: mapImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.76, green: 0.82, blue: 0.84),
                        Color(red: 0.42, green: 0.48, blue: 0.50)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.00), location: 0.18),
                    .init(color: .black.opacity(0.12), location: 0.48),
                    .init(color: .black.opacity(0.66), location: 0.78),
                    .init(color: .black.opacity(0.82), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            shareOverlay
        }
    }

    private var shareOverlay: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom, spacing: 42) {
                VStack(alignment: .leading, spacing: 34) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 78, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(activity.title)
                            .font(.system(size: 62, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)

                        Text(dateText.uppercased())
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.76))
                    }

                    statsStack
                }

                Spacer()

                Text("OUTBOUND")
                    .font(.system(size: 44, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .padding(.bottom, 252)
            }
            .padding(.horizontal, 104)
            .padding(.bottom, 128)
        }
    }

    private var statsStack: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top, spacing: 72) {
                ShareStat(label: "Distance", value: unitSystem.distanceString(meters: activity.distanceM))
                ShareStat(label: "Time", value: activity.durationSecs.formatted())
            }

            HStack(alignment: .top, spacing: 72) {
                ShareStat(label: "Pace", value: paceText)
                if let elevation = activity.elevationGainM {
                    ShareStat(label: "Elev", value: unitSystem.elevationString(meters: elevation))
                }
            }
        }
    }
}

private struct ShareStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(value)
                .font(.system(size: 62, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.58)
            Text(label.uppercased())
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.80))
        }
        .frame(width: 250, alignment: .leading)
    }
}

private enum ActivityShareMapSnapshotRenderer {
    static func snapshot(for activity: SavedActivity, size: CGSize) async throws -> UIImage {
        let coordinates = activity.routeCoordinates
        guard coordinates.count > 1 else { throw ActivityShareCardError.renderFailed }

        let options = MKMapSnapshotter.Options()
        options.size = size
        options.scale = 1
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        options.mapRect = mapRect(for: coordinates, size: size)

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
