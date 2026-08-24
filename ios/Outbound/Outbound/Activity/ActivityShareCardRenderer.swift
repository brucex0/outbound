import CoreLocation
import CoreImage
import MapKit
import SwiftUI
import UIKit

enum ActivityShareCardRenderer {
    private static let cardSize = CGSize(width: 1080, height: 1920)

    @MainActor
    static func renderCard(
        activity: SavedActivity,
        unitSystem: MeasurementUnitSystem,
        referralURL: URL
    ) async throws -> UIImage {
        async let mapImageTask = try? ActivityShareMapSnapshotRenderer.snapshot(for: activity, size: cardSize)
        async let avatarImageTask = loadCurrentUserAvatar()
        let (mapImage, avatarImage) = await (mapImageTask, avatarImageTask)
        let qrCodeImage = makeQRCode(for: referralURL)
        let appLogoImage = loadAppIcon()
        let card = ActivityShareCardView(
            activity: activity,
            unitSystem: unitSystem,
            mapImage: mapImage,
            avatarImage: avatarImage,
            qrCodeImage: qrCodeImage,
            appLogoImage: appLogoImage
        )
            .frame(width: cardSize.width, height: cardSize.height)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        guard let image = renderer.uiImage else {
            throw ActivityShareCardError.renderFailed
        }
        return image
    }

    private static func makeQRCode(for url: URL) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        // The centered avatar intentionally covers a small part of the code, so use
        // the highest correction level to preserve reliable scanning.
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }

        let quietZoneModules: CGFloat = 1
        let codeSize = outputImage.extent.size
        let imageSize = CGSize(
            width: codeSize.width + quietZoneModules * 2,
            height: codeSize.height + quietZoneModules * 2
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: imageSize, format: format).image { rendererContext in
            rendererContext.cgContext.setFillColor(UIColor.white.cgColor)
            rendererContext.cgContext.fill(CGRect(origin: .zero, size: imageSize))
            UIImage(cgImage: cgImage).draw(
                in: CGRect(origin: CGPoint(x: quietZoneModules, y: quietZoneModules), size: codeSize)
            )
        }
    }

    private static func loadCurrentUserAvatar() async -> UIImage? {
        guard let profile = try? await APIClient.shared.fetchMyProfile(),
              let avatarURLString = profile.avatarUrl,
              let avatarURL = URL(string: avatarURLString) else { return nil }

        return await AvatarImageCache.shared.image(for: avatarURL.absoluteString)
    }

    private static func loadAppIcon() -> UIImage? {
        // App-icon asset catalogs are emitted as standalone bundle PNGs and are not
        // reliably available through UIImage(named: "AppIcon") at runtime.
        let candidates = ["AppIcon60x60@3x", "AppIcon60x60@2x", "AppIcon60x60"]
        for name in candidates {
            if let path = Bundle.main.path(forResource: name, ofType: "png"),
               let image = UIImage(contentsOfFile: path) {
                return image
            }
        }
        return nil
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
    let avatarImage: UIImage?
    let qrCodeImage: UIImage?
    let appLogoImage: UIImage?

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

                VStack(alignment: .center, spacing: 20) {
                    if let qrCodeImage {
                        Text("Run With Me")
                            .font(.system(size: 32, weight: .heavy))
                            .tracking(1.6)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                            .frame(width: 264, height: 52, alignment: .center)

                        ZStack {
                            Image(uiImage: qrCodeImage)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 264, height: 264)

                            if let avatarImage {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 106, height: 106)

                                Image(uiImage: avatarImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 96, height: 96)
                                    .clipShape(Circle())
                                    .overlay {
                                        Circle()
                                            .stroke(.white, lineWidth: 3)
                                    }
                            }
                        }
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    }

                    HStack(spacing: 16) {
                        if let appLogoImage {
                            Image(uiImage: appLogoImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }

                        Text("Plainstride")
                            .font(.system(size: 34, weight: .medium))
                            .tracking(1.1)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.bottom, 168)
            }
            .padding(.horizontal, 104)
            .padding(.bottom, 128)
        }
    }

    private var statsStack: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top, spacing: 72) {
                ShareStat(label: String(localized: "Distance"), value: unitSystem.distanceString(meters: activity.distanceM))
                ShareStat(label: String(localized: "Time"), value: activity.durationSecs.formatted())
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
