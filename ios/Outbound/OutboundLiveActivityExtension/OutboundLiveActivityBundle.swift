import ActivityKit
import SwiftUI
import WidgetKit

@main
struct OutboundLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        OutboundSessionLiveActivityWidget()
    }
}

struct OutboundSessionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OutboundLiveActivityAttributes.self) { context in
            LockScreenSessionView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.86))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.sportName, systemImage: context.attributes.sportSystemImageName)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    statusBadge(for: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 18) {
                        metric(title: "Time", value: elapsedView(for: context.state))
                        metric(title: "Dist", value: Text(context.state.distanceText))
                        metric(title: "Pace", value: Text(context.state.paceText))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.attributes.sportSystemImageName)
            } compactTrailing: {
                elapsedView(for: context.state)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: context.attributes.sportSystemImageName)
            }
        }
    }

    private func statusBadge(for state: OutboundLiveActivityAttributes.ContentState) -> some View {
        Text(state.statusText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(state.isPaused ? Color.orange.opacity(0.85) : Color.green.opacity(0.85), in: Capsule())
    }

    private func metric(title: String, value: some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.68))
            value
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func elapsedView(for state: OutboundLiveActivityAttributes.ContentState) -> some View {
        if let elapsedReferenceDate = state.elapsedReferenceDate, !state.isPaused {
            Text(timerInterval: elapsedReferenceDate...Date.now, countsDown: false)
                .monospacedDigit()
        } else {
            Text(formattedElapsed(state.elapsedSeconds))
                .monospacedDigit()
        }
    }

    private func formattedElapsed(_ elapsedSeconds: Int) -> String {
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        let seconds = elapsedSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct LockScreenSessionView: View {
    let context: ActivityViewContext<OutboundLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(context.attributes.sportName, systemImage: context.attributes.sportSystemImageName)
                        .font(.headline)
                    Text(context.attributes.activityName)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(1)
                }

                Spacer()

                Text(context.state.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(context.state.isPaused ? Color.orange.opacity(0.85) : Color.green.opacity(0.85), in: Capsule())
            }

            HStack(spacing: 18) {
                metric(title: "Time", value: elapsedView)
                metric(title: "Dist", value: Text(context.state.distanceText))
                metric(title: "Pace", value: Text(context.state.paceText))
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 6)
    }

    private func metric(title: String, value: some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.68))
            value
                .font(.title3.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var elapsedView: some View {
        if let elapsedReferenceDate = context.state.elapsedReferenceDate, !context.state.isPaused {
            Text(timerInterval: elapsedReferenceDate...Date.now, countsDown: false)
                .monospacedDigit()
        } else {
            Text(formattedElapsed(context.state.elapsedSeconds))
                .monospacedDigit()
        }
    }

    private func formattedElapsed(_ elapsedSeconds: Int) -> String {
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        let seconds = elapsedSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }
}
