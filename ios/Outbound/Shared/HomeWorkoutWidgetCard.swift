import SwiftUI
import WidgetKit

struct HomeWorkoutWidgetCard: View {
    let snapshot: HomeWorkoutWidgetSnapshot
    let family: WidgetFamily

    private let ink = Color(red: 0.10, green: 0.24, blue: 0.27)
    private let mutedInk = Color(red: 0.23, green: 0.38, blue: 0.40)

    var body: some View {
        if family == .systemSmall {
            smallLayout
        } else {
            mediumLayout
        }
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image("FoxAssistantHead", bundle: .main)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(2)

                Text(snapshot.detail)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(mutedInk)
                    .lineLimit(2)
            }
        }
        .padding(12)
    }

    private var mediumLayout: some View {
        HStack(spacing: 14) {
            Image("FoxAssistantHead", bundle: .main)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(2)

                Text(snapshot.detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(mutedInk)
                    .lineLimit(2)
            }
        }
        .padding(18)
    }
}
