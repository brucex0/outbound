import SwiftUI

/// Plainstride's visual shorthand for a Group.
/// The enclosing ring communicates privacy; the two figures leaning together
/// communicate closeness without reusing a generic contacts symbol.
struct GroupMark: View {
    var body: some View {
        Canvas { context, size in
            let designSize = CGSize(width: 19, height: 19)
            let scale = min(size.width / designSize.width, size.height / designSize.height)
            let transform = CGAffineTransform(
                translationX: (size.width - designSize.width * scale) / 2,
                y: (size.height - designSize.height * scale) / 2
            ).scaledBy(x: scale, y: scale)
            let center = CGPoint(x: 9.5, y: 9.5)

            let ring = Path(ellipseIn: CGRect(x: 2.3, y: 2.3, width: 14.4, height: 14.4))
                .applying(transform)
            context.stroke(
                ring,
                with: .foreground,
                style: StrokeStyle(lineWidth: 1.7 * scale, lineCap: .round, lineJoin: .round)
            )

            var huddle = Path()
            for side in [CGFloat(-1), CGFloat(1)] {
                let head = CGPoint(x: center.x + side * 1.55, y: center.y - 1.55)
                huddle.addEllipse(in: CGRect(
                    x: head.x - 1.45,
                    y: head.y - 1.45,
                    width: 2.9,
                    height: 2.9
                ))

                var body = Path(
                    roundedRect: CGRect(x: -2.1, y: -1.25, width: 4.2, height: 2.5),
                    cornerRadius: 1.25
                )
                body = body.applying(CGAffineTransform(rotationAngle: side * .pi / 18))
                body = body.applying(CGAffineTransform(
                    translationX: center.x + side * 1.75,
                    y: center.y + 1.65
                ))
                huddle.addPath(body)
            }
            context.fill(huddle.applying(transform), with: .foreground)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 20) {
        GroupMark()
            .frame(width: 18, height: 18)
        GroupMark()
            .frame(width: 32, height: 32)
    }
    .foregroundStyle(.indigo)
    .padding()
}
