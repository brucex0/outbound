import SwiftUI
import WidgetKit

struct HomeWorkoutWidgetCard: View {
    let snapshot: HomeWorkoutWidgetSnapshot
    let family: WidgetFamily

    private let ink = Color(red: 0.10, green: 0.24, blue: 0.27)
    private let mutedInk = Color(red: 0.23, green: 0.38, blue: 0.40)

    var body: some View {
        Group {
            if family == .systemSmall {
                smallLayout
            } else {
                mediumLayout
            }
        }
        .padding(family == .systemSmall ? 14 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            LinearGradient(
                colors: [Color(red: 0.94, green: 0.84, blue: 0.63), Color(red: 0.98, green: 0.91, blue: 0.77)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 2) {
                VStack(alignment: .leading, spacing: 5) {
                    eyebrow
                    Text(snapshot.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                foxMark(size: 54)
                    .padding(.top, 1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Image(systemName: snapshot.systemImageName)
                    .font(.caption2.weight(.bold))
                Text(snapshot.detail)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(mutedInk)
        }
    }

    private var mediumLayout: some View {
        HStack(spacing: 14) {
            foxMark(size: 92)
                .frame(width: 96, height: 100)

            VStack(alignment: .leading, spacing: 7) {
                eyebrow
                Text(snapshot.title)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Label(snapshot.detail, systemImage: snapshot.systemImageName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Text(String(localized: "widget.action.open", table: "HomeWidget"))
                        .font(.caption.weight(.bold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(mutedInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var eyebrow: some View {
        Text(String(localized: "widget.label.today", table: "HomeWidget"))
            .font(.caption2.weight(.heavy))
            .tracking(1.1)
            .foregroundStyle(mutedInk)
    }

    private func foxMark(size: CGFloat) -> some View {
        Image("FoxAssistantHead")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
