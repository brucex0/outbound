import Charts
import SwiftUI

struct RunningCadenceChartView: View {
    let summary: ActivityCadenceSummary
    @Environment(\.outboundTheme) private var theme
    @Environment(\.analyticsManager) private var analyticsManager

    private var samples: [ActivityCadenceSample] { summary.samples ?? [] }
    private var summaryText: String {
        [
            summary.averageStepsPerMinute.map {
                String(format: String(localized: "running_cadence.average_format", defaultValue: "Avg %d steps / min"), locale: .autoupdatingCurrent, $0)
            },
            summary.maxStepsPerMinute.map {
                String(format: String(localized: "running_cadence.maximum_format", defaultValue: "Max %d steps / min"), locale: .autoupdatingCurrent, $0)
            }
        ].compactMap { $0 }.joined(separator: " • ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "running_cadence.live_label", defaultValue: "Steps / min"))
                    .font(.headline)
                Spacer()
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if samples.count > 1 {
                Chart {
                    ForEach(samples.indices, id: \.self) { index in
                        let sample = samples[index]
                        LineMark(
                            x: .value(String(localized: "running_cadence.time_axis", defaultValue: "Active time (min)"), Double(sample.elapsedSeconds) / 60),
                            y: .value(String(localized: "running_cadence.unit", defaultValue: "steps / min"), sample.stepsPerMinute),
                            series: .value(String(localized: "running_cadence.live_label", defaultValue: "Steps / min"), sample.segment)
                        )
                        .foregroundStyle(theme.accentColor)
                        PointMark(
                            x: .value(String(localized: "running_cadence.time_axis", defaultValue: "Active time (min)"), Double(sample.elapsedSeconds) / 60),
                            y: .value(String(localized: "running_cadence.unit", defaultValue: "steps / min"), sample.stepsPerMinute)
                        )
                        .symbolSize(8)
                        .foregroundStyle(theme.accentColor)
                    }
                }
                .chartXAxisLabel(String(localized: "running_cadence.time_axis", defaultValue: "Active time (min)"))
                .chartYAxisLabel(String(localized: "running_cadence.unit", defaultValue: "steps / min"))
                .chartLegend(.hidden)
                .frame(height: 160)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "running_cadence.live_label", defaultValue: "Steps / min"))
                .accessibilityValue(summaryText)
            }
            Text(String(localized: "running_cadence.coverage", defaultValue: "Based on available motion readings."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("RunningCadenceSummary")
        .task {
            await analyticsManager?.track(.init(.featureExposed, properties: [
                .feature: .string("running_cadence_summary")
            ]))
        }
    }
}
