import SwiftUI
import WidgetKit

private struct HomeWorkoutWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: HomeWorkoutWidgetSnapshot
    let family: WidgetFamily
}

private struct HomeWorkoutWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeWorkoutWidgetEntry {
        HomeWorkoutWidgetEntry(date: .now, snapshot: sampleSnapshot, family: context.family)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeWorkoutWidgetEntry) -> Void) {
        completion(HomeWorkoutWidgetEntry(
            date: .now,
            snapshot: HomeWorkoutWidgetStore.read() ?? sampleSnapshot,
            family: context.family
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeWorkoutWidgetEntry>) -> Void) {
        let entry = HomeWorkoutWidgetEntry(
            date: .now,
            snapshot: HomeWorkoutWidgetStore.read() ?? sampleSnapshot,
            family: context.family
        )
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(6 * 60 * 60))))
    }

    private var sampleSnapshot: HomeWorkoutWidgetSnapshot {
        HomeWorkoutWidgetSnapshot(
            title: String(localized: "widget.fallback.title", table: "HomeWidget"),
            detail: String(localized: "widget.fallback.detail", table: "HomeWidget"),
            systemImageName: "figure.run"
        )
    }
}

struct HomeWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: HomeWorkoutWidgetStore.widgetKind,
            provider: HomeWorkoutWidgetProvider()
        ) { entry in
            HomeWorkoutWidgetCard(snapshot: entry.snapshot, family: entry.family)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName(String(localized: "widget.gallery.name", table: "HomeWidget"))
        .description(String(localized: "widget.gallery.description", table: "HomeWidget"))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
