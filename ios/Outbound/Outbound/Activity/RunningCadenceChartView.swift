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
                String(format: String(localized: "activity.meta.cadence.average", defaultValue: "Avg %d spm"), locale: .autoupdatingCurrent, $0)
            },
            summary.maxStepsPerMinute.map {
                String(format: String(localized: "activity.meta.cadence.maximum", defaultValue: "Max %d spm"), locale: .autoupdatingCurrent, $0)
            }
        ].compactMap { $0 }.joined(separator: " • ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "activity.meta.cadence.title", defaultValue: "Cadence"))
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
                            y: .value(String(localized: "running_cadence.unit", defaultValue: "spm"), sample.stepsPerMinute),
                            series: .value(String(localized: "activity.meta.cadence.title", defaultValue: "Cadence"), sample.segment)
                        )
                        .foregroundStyle(theme.accentColor)
                        PointMark(
                            x: .value(String(localized: "running_cadence.time_axis", defaultValue: "Active time (min)"), Double(sample.elapsedSeconds) / 60),
                            y: .value(String(localized: "running_cadence.unit", defaultValue: "spm"), sample.stepsPerMinute)
                        )
                        .symbolSize(8)
                        .foregroundStyle(theme.accentColor)
                    }
                }
                .chartXAxisLabel(String(localized: "running_cadence.time_axis", defaultValue: "Active time (min)"))
                .chartYAxisLabel(String(localized: "running_cadence.unit", defaultValue: "spm"))
                .chartLegend(.hidden)
                .frame(height: 160)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "activity.meta.cadence.title", defaultValue: "Cadence"))
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
