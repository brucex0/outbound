import SwiftUI
import CoreLocation

struct PostSaveCelebrationView: View {
    let activity: SavedActivity
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color(red: 1.0, green: 0.94, blue: 0.86)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                PostSaveCelebrationCard(activity: activity)
                    .frame(maxWidth: 360)
                    .frame(height: 250)

                Text(String(localized: "activity.post_save.message", defaultValue: "You made time for this today."))
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(red: 0.11, green: 0.16, blue: 0.22))
                    .accessibilityAddTraits(.isHeader)

                Button(action: onContinue) {
                    Text(String(localized: "activity.post_save.done", defaultValue: "Done"))
                        .font(.headline)
                        .frame(minWidth: 112, minHeight: 48)
                        .padding(.horizontal, 14)
                        .foregroundStyle(.white)
                        .background(Color(red: 0.94, green: 0.35, blue: 0.13), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("PostSaveCelebrationDoneButton")
            }
            .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(String(localized: "activity.post_save.accessibility", defaultValue: "Activity saved celebration")))
    }
}

struct PostSaveCelebrationCard: View {
    let activity: SavedActivity

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var routeProgress: CGFloat = 0
    @State private var sundaeBurstProgress: CGFloat = 0
    @State private var sundaeOpacity: CGFloat = 1

    private var routePoints: [CGPoint] {
        let coordinates = activity.routeCoordinates
        guard coordinates.count > 1 else {
            return [
                CGPoint(x: 0.08, y: 0.74), CGPoint(x: 0.24, y: 0.54),
                CGPoint(x: 0.39, y: 0.64), CGPoint(x: 0.57, y: 0.35),
                CGPoint(x: 0.74, y: 0.45), CGPoint(x: 0.92, y: 0.20)
            ]
        }

        let longitudes = coordinates.map(\.longitude)
        let latitudes = coordinates.map(\.latitude)
        guard let minLongitude = longitudes.min(), let maxLongitude = longitudes.max(),
              let minLatitude = latitudes.min(), let maxLatitude = latitudes.max() else { return [] }
        let longitudeSpan = max(maxLongitude - minLongitude, 0.000001)
        let latitudeSpan = max(maxLatitude - minLatitude, 0.000001)
        let scale = min(0.82 / longitudeSpan, 0.58 / latitudeSpan)
        let width = longitudeSpan * scale
        let height = latitudeSpan * scale
        let xOffset = (1 - width) / 2
        let yOffset = (1 - height) / 2

        return coordinates.map { coordinate in
            CGPoint(
                x: xOffset + (coordinate.longitude - minLongitude) * scale,
                y: 1 - yOffset - (coordinate.latitude - minLatitude) * scale
            )
        }
    }

    var body: some View {
        postcard
            .onAppear {
                routeProgress = reduceMotion ? 1 : 0
                sundaeBurstProgress = reduceMotion ? 1 : 0
                sundaeOpacity = 1
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4)) { routeProgress = 1 }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.58).delay(1.18)) {
                    sundaeBurstProgress = 1
                }
            }
            .task(id: activity.id) {
                let holdDuration: UInt64 = reduceMotion ? 2_000_000_000 : 3_600_000_000
                try? await Task.sleep(nanoseconds: holdDuration)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.35)) { sundaeOpacity = 0 }
            }
    }

    private var postcard: some View {
        GeometryReader { proxy in
            let points = routePoints
            let size = proxy.size
            let normalized = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            let mascotPoint = point(on: normalized, fraction: routeProgress)
            let finishPoint = normalized.last ?? CGPoint(x: size.width * 0.9, y: size.height * 0.2)
            let burstPoint = CGPoint(
                x: min(max(finishPoint.x, 46), size.width - 46),
                y: min(max(finishPoint.y - 33, 45), size.height - 45)
            )

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.99, blue: 0.95))
                    .shadow(color: Color(red: 0.23, green: 0.17, blue: 0.12).opacity(0.14), radius: 20, y: 10)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)

                RouteLine(points: normalized)
                    .trim(from: 0, to: routeProgress)
                    .stroke(
                        Color(red: 0.95, green: 0.39, blue: 0.16),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                    )

                if let mascotPoint {
                    PostcardRunner(isReducedMotion: reduceMotion)
                        .frame(width: 48, height: 58)
                        .position(x: mascotPoint.x, y: mascotPoint.y)
                        .opacity(routeProgress > 0.04 ? 1 : 0)
                }

                if sundaeBurstProgress > 0 && sundaeOpacity > 0 {
                    SundaeBurst(progress: sundaeBurstProgress, opacity: sundaeOpacity)
                        .frame(width: 88, height: 88)
                        .position(burstPoint)
                        .accessibilityHidden(true)
                }

                Circle()
                    .fill(Color(red: 0.12, green: 0.20, blue: 0.28))
                    .frame(width: 11, height: 11)
                    .position(normalized.first ?? CGPoint(x: size.width * 0.12, y: size.height * 0.75))

                Circle()
                    .fill(Color(red: 0.12, green: 0.20, blue: 0.28))
                    .frame(width: 11, height: 11)
                    .position(normalized.last ?? CGPoint(x: size.width * 0.9, y: size.height * 0.2))
            }
        }
    }

    private func point(on points: [CGPoint], fraction: CGFloat) -> CGPoint? {
        guard let first = points.first else { return nil }
        guard points.count > 1 else { return first }
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return first }
        var remaining = min(max(fraction, 0), 1) * total
        for (index, length) in lengths.enumerated() {
            if remaining <= length {
                let start = points[index]
                let end = points[index + 1]
                let t = length == 0 ? 0 : remaining / length
                return CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            }
            remaining -= length
        }
        return points.last
    }
}

private struct SundaeBurst: View {
    let progress: CGFloat
    let opacity: CGFloat

    private let sprinkleColors: [Color] = [
        Color(red: 0.96, green: 0.35, blue: 0.48),
        Color(red: 0.25, green: 0.68, blue: 0.57),
        Color(red: 0.99, green: 0.68, blue: 0.20),
        Color(red: 0.46, green: 0.40, blue: 0.78)
    ]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let particleAngles: [CGFloat] = [-150, -112, -72, -28, 18, 58, 105, 148]
            for (index, degrees) in particleAngles.enumerated() {
                let angle = degrees * .pi / 180
                let innerRadius: CGFloat = 18
                let outerRadius: CGFloat = 37 * progress
                let start = CGPoint(
                    x: center.x + cos(angle) * innerRadius,
                    y: center.y + sin(angle) * innerRadius
                )
                let end = CGPoint(
                    x: center.x + cos(angle) * outerRadius,
                    y: center.y + sin(angle) * outerRadius
                )
                var sprinkle = Path()
                sprinkle.move(to: start)
                sprinkle.addLine(to: end)
                context.stroke(
                    sprinkle,
                    with: .color(sprinkleColors[index % sprinkleColors.count]),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
            }

            var cone = Path()
            cone.move(to: CGPoint(x: center.x - 16, y: center.y - 3))
            cone.addLine(to: CGPoint(x: center.x + 16, y: center.y - 3))
            cone.addLine(to: CGPoint(x: center.x + 2, y: center.y + 33))
            cone.addQuadCurve(to: CGPoint(x: center.x - 2, y: center.y + 33), control: CGPoint(x: center.x, y: center.y + 36))
            cone.closeSubpath()
            context.fill(cone, with: .color(Color(red: 0.80, green: 0.48, blue: 0.24)))

            var waffleLines = Path()
            for offset: CGFloat in [-9, 0, 9] {
                waffleLines.move(to: CGPoint(x: center.x + offset - 8, y: center.y + 2))
                waffleLines.addLine(to: CGPoint(x: center.x + offset + 5, y: center.y + 29))
                waffleLines.move(to: CGPoint(x: center.x + offset + 8, y: center.y + 2))
                waffleLines.addLine(to: CGPoint(x: center.x + offset - 5, y: center.y + 29))
            }
            context.stroke(waffleLines, with: .color(Color(red: 0.94, green: 0.69, blue: 0.40)), lineWidth: 1.3)

            let scoops: [(CGPoint, CGFloat, Color)] = [
                (CGPoint(x: center.x - 10, y: center.y - 10), 13, Color(red: 0.55, green: 0.79, blue: 0.63)),
                (CGPoint(x: center.x + 2, y: center.y - 18), 15, Color(red: 0.99, green: 0.54, blue: 0.62)),
                (CGPoint(x: center.x + 13, y: center.y - 8), 12, Color(red: 1.0, green: 0.84, blue: 0.52))
            ]
            for (point, radius, color) in scoops {
                let scoop = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                context.fill(scoop, with: .color(color))
            }

            var cherryStem = Path()
            cherryStem.move(to: CGPoint(x: center.x + 8, y: center.y - 30))
            cherryStem.addQuadCurve(to: CGPoint(x: center.x + 17, y: center.y - 27), control: CGPoint(x: center.x + 15, y: center.y - 34))
            context.stroke(cherryStem, with: .color(Color(red: 0.20, green: 0.48, blue: 0.31)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            let cherry = Path(ellipseIn: CGRect(x: center.x + 3, y: center.y - 36, width: 9, height: 9))
            context.fill(cherry, with: .color(Color(red: 0.88, green: 0.20, blue: 0.30)))
        }
        .scaleEffect(0.72 + 0.28 * progress)
        .opacity(opacity)
    }
}

private struct RouteLine: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }
}

private struct PostcardRunner: View {
    let isReducedMotion: Bool

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let navy = Color(red: 0.12, green: 0.20, blue: 0.28)
            let orange = Color(red: 0.95, green: 0.39, blue: 0.16)
            let cream = Color(red: 1.0, green: 0.84, blue: 0.59)

            let head = Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 24, width: 12, height: 12))
            context.fill(head, with: .color(cream))
            var cap = Path()
            cap.move(to: CGPoint(x: center.x - 7, y: center.y - 18))
            cap.addQuadCurve(to: CGPoint(x: center.x + 8, y: center.y - 20), control: CGPoint(x: center.x, y: center.y - 26))
            cap.addLine(to: CGPoint(x: center.x + 10, y: center.y - 18))
            context.stroke(cap, with: .color(orange), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            var bodyPath = Path()
            bodyPath.move(to: CGPoint(x: center.x, y: center.y - 10))
            bodyPath.addLine(to: CGPoint(x: center.x - 1, y: center.y + 4))
            context.stroke(bodyPath, with: .color(orange), style: StrokeStyle(lineWidth: 8, lineCap: .round))

            var limbs = Path()
            limbs.move(to: CGPoint(x: center.x - 1, y: center.y - 6))
            limbs.addLine(to: CGPoint(x: center.x - 10, y: center.y - 14))
            limbs.move(to: CGPoint(x: center.x + 1, y: center.y - 6))
            limbs.addLine(to: CGPoint(x: center.x + 10, y: center.y - 15))
            limbs.move(to: CGPoint(x: center.x - 1, y: center.y + 3))
            limbs.addLine(to: CGPoint(x: center.x - 10, y: center.y + 14))
            limbs.addLine(to: CGPoint(x: center.x - 15, y: center.y + 14))
            limbs.move(to: CGPoint(x: center.x + 1, y: center.y + 3))
            limbs.addLine(to: CGPoint(x: center.x + 10, y: center.y + 11))
            limbs.addLine(to: CGPoint(x: center.x + 15, y: center.y + 9))
            context.stroke(limbs, with: .color(navy), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        .rotationEffect(.degrees(isReducedMotion ? 0 : 5))
    }
}
