import SwiftUI

/// Alternative Circle marks, kept behind a debug launch argument so the shipped
/// `CircleMark` can be compared against them in the real Social tab bar metrics.
///
/// Why these exist: the shipped mark puts two figures inside a ring. Rendered at tab
/// size the ring stays readable but the figures collapse into one rounded mass, so the
/// group reads as a single blob in a circle. These candidates drop the container and
/// carry intimacy with contact instead, which keeps the figures at full size.
///
/// Design space is 24 x 19 pt, matching the tab bar slot and the neighbouring system
/// symbols measured at 15 pt semibold (person.2 ink 20.8 x 14.0 pt, stroke 1.8 pt).
enum CircleMarkCandidate: String, CaseIterable, Identifiable {
    case ringPair
    case mergedTrio
    case mergedPair
    case headHuddle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ringPair: "Ring with clean figures"
        case .mergedTrio: "Close trio"
        case .mergedPair: "Close pair"
        case .headHuddle: "Head huddle"
        }
    }

    var note: String {
        switch self {
        case .ringPair:
            "Keeps the shipped ring but redraws the interior as two clean person silhouettes at Apple's person.2.circle proportions, instead of two rotated capsules that merge into a blob."
        case .mergedTrio:
            "No container, so the figures stay full size. Heads nearly touch and torsos merge into one silhouette, so the group reads as one unit."
        case .mergedPair:
            "The most intimate read, but it sits next to People (person.2) in the same bar, so two similar person marks compete."
        case .headHuddle:
            "Heads clustered over a shared base instead of a row. Distinct round silhouette, but at 15 pt the cluster reads as one shape."
        }
    }
}

/// Geometry for the alternative marks: 24 x 19 design space, y down.
enum CircleMarkCandidateGeometry {
    static let boxWidth: CGFloat = 24
    static let boxHeight: CGFloat = 19
    static let center = CGPoint(x: 12, y: 9.5)
    /// Matches the neighbouring system symbols at 15 pt semibold.
    static let stroke: CGFloat = 1.8

    static func figure(
        headCenter: CGPoint,
        headRadius: CGFloat,
        torsoSize: CGSize,
        torsoCenter: CGPoint,
        torsoCornerRadius: CGFloat,
        lean: Angle
    ) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(
            x: headCenter.x - headRadius,
            y: headCenter.y - headRadius,
            width: headRadius * 2,
            height: headRadius * 2
        ))
        var torso = Path(
            roundedRect: CGRect(
                x: -torsoSize.width / 2,
                y: -torsoSize.height / 2,
                width: torsoSize.width,
                height: torsoSize.height
            ),
            cornerRadius: torsoCornerRadius
        )
        torso = torso.applying(CGAffineTransform(rotationAngle: lean.radians))
        torso = torso.applying(CGAffineTransform(translationX: torsoCenter.x, y: torsoCenter.y))
        path.addPath(torso)
        return path
    }

    /// The shipped concept, but with the figures drawn as recognisable person
    /// silhouettes: round head plus a wide, flat-bottomed shoulder shape, matching how
    /// Apple draws the interior of `person.2.circle`.
    static func ringPath(radius: CGFloat = 6.9) -> Path {
        Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }

    static func ringPairFigures() -> Path {
        var path = Path()
        for side in [CGFloat(-1), CGFloat(1)] {
            path.addPath(figure(
                headCenter: CGPoint(x: center.x + side * 1.75, y: 6.9),
                headRadius: 1.45,
                torsoSize: CGSize(width: 4.3, height: 4.8),
                torsoCenter: CGPoint(x: center.x + side * 1.95, y: 11.9),
                torsoCornerRadius: 1.1,
                lean: .degrees(side * 8)
            ))
        }
        return path
    }

    /// Three full-size figures whose torsos overlap into one closed silhouette.
    static func mergedTrio() -> Path {
        let torso = CGSize(width: 6.6, height: 8.6)
        var path = Path()
        let figures: [(x: CGFloat, headY: CGFloat, torsoY: CGFloat, lean: Double)] = [
            (7.8, 4.9, 12.2, -5),
            (12.0, 4.5, 11.8, 0),
            (16.2, 4.9, 12.2, 5)
        ]
        for figure in figures {
            path.addPath(self.figure(
                headCenter: CGPoint(x: figure.x, y: figure.headY),
                headRadius: 2.0,
                torsoSize: torso,
                torsoCenter: CGPoint(x: figure.x, y: figure.torsoY),
                torsoCornerRadius: torso.height / 2,
                lean: .degrees(figure.lean)
            ))
        }
        return path
    }

    /// Two full-size figures leaning into a single mass.
    static func mergedPair() -> Path {
        let torso = CGSize(width: 6.8, height: 9.4)
        var path = Path()
        for side in [CGFloat(-1), CGFloat(1)] {
            path.addPath(figure(
                headCenter: CGPoint(x: center.x + side * 2.5, y: 4.8),
                headRadius: 2.2,
                torsoSize: torso,
                torsoCenter: CGPoint(x: center.x + side * 2.6, y: 12.1),
                torsoCornerRadius: torso.height / 2,
                lean: .degrees(side * 9)
            ))
        }
        return path
    }

    /// Three heads clustered over one shared base.
    static func headHuddle() -> Path {
        var path = Path()
        let headRadius: CGFloat = 3.4
        for head in [CGPoint(x: 8.8, y: 11.4), CGPoint(x: 15.2, y: 11.4), CGPoint(x: 12.0, y: 6.0)] {
            path.addEllipse(in: CGRect(
                x: head.x - headRadius,
                y: head.y - headRadius,
                width: headRadius * 2,
                height: headRadius * 2
            ))
        }
        let base = CGRect(x: 6.0, y: 12.5, width: 12.0, height: 3.4)
        path.addPath(Path(roundedRect: base, cornerRadius: base.height / 2))
        return path
    }

    static func path(for candidate: CircleMarkCandidate) -> Path {
        switch candidate {
        case .ringPair: mergedTrio()
        case .mergedTrio: mergedTrio()
        case .mergedPair: mergedPair()
        case .headHuddle: headHuddle()
        }
    }
}

struct CircleMarkCandidateIcon: View {
    let candidate: CircleMarkCandidate

    var body: some View {
        Canvas { context, size in
            let scale = min(
                size.width / CircleMarkCandidateGeometry.boxWidth,
                size.height / CircleMarkCandidateGeometry.boxHeight
            )
            let transform = CGAffineTransform(
                translationX: (size.width - CircleMarkCandidateGeometry.boxWidth * scale) / 2,
                y: (size.height - CircleMarkCandidateGeometry.boxHeight * scale) / 2
            ).scaledBy(x: scale, y: scale)
            if candidate == .ringPair {
                context.stroke(
                    CircleMarkCandidateGeometry.ringPath().applying(transform),
                    with: .foreground,
                    style: StrokeStyle(
                        lineWidth: CircleMarkCandidateGeometry.stroke * scale,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                context.fill(
                    CircleMarkCandidateGeometry.ringPairFigures().applying(transform),
                    with: .foreground
                )
            } else {
                context.fill(
                    CircleMarkCandidateGeometry.path(for: candidate).applying(transform),
                    with: .foreground
                )
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
/// Review screen for the Circle mark. Launch the Outbound scheme with
/// `-OutboundDebugCircleMark` to show it.
struct DebugCircleMarkReviewHarness: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Circle mark review").font(.headline)
                Spacer()
                Text("24 x 19 pt slots · 15 pt semibold neighbours · 1.8 pt stroke")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("Shipped mark, as wired (17 pt frame)")
                .font(.caption.weight(.semibold))
            MockSocialTabBar {
                CircleMark().frame(width: 17, height: 17)
            }

            Text("Shipped mark at neighbour optical size (19 pt frame)")
                .font(.caption.weight(.semibold))
            MockSocialTabBar {
                CircleMark().frame(width: 19, height: 19)
            }

            Divider()

            ForEach(CircleMarkCandidate.allCases) { candidate in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(candidate.title).font(.subheadline.weight(.semibold))
                        Text(candidate.note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    MockSocialTabBar {
                        CircleMarkCandidateIcon(candidate: candidate)
                            .frame(width: 24, height: 19)
                    }
                    HStack(alignment: .bottom, spacing: 12) {
                        CircleMarkCandidateIcon(candidate: candidate).frame(width: 24, height: 19)
                        CircleMarkCandidateIcon(candidate: candidate).frame(width: 48, height: 38)
                        CircleMarkCandidateIcon(candidate: candidate).frame(width: 96, height: 76)
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemGroupedBackground))
    }
}

/// Rebuilds the Social tab bar metrics so marks can be judged in context.
private struct MockSocialTabBar<CircleSlot: View>: View {
    @ViewBuilder let circleSlot: () -> CircleSlot

    var body: some View {
        HStack(spacing: 2) {
            tab("Feed", "rectangle.stack")
            tab("People", "person.2")
            VStack(spacing: 3) {
                ZStack {
                    Color.clear.frame(width: 24, height: 19)
                    circleSlot()
                }
                Text("Circle")
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(OutboundPalette.companion)
            .frame(maxWidth: .infinity, minHeight: 44)
            tab("Groups", "flag")
            tab("Routes", "map")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func tab(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 24, height: 19)
            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 44)
    }
}
#endif
