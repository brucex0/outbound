import SwiftUI
import WidgetKit

private struct HomeWorkoutWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: HomeWorkoutWidgetSnapshot
    let family: WidgetFamily
}

private struct HomeWorkoutWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeWorkoutWidgetEntry {
        recordDiagnostic("placeholder", snapshot: nil)
        return HomeWorkoutWidgetEntry(date: .now, snapshot: sampleSnapshot, family: context.family)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeWorkoutWidgetEntry) -> Void) {
        let sharedSnapshot = HomeWorkoutWidgetStore.read()
        recordDiagnostic(context.isPreview ? "gallery_snapshot" : "snapshot", snapshot: sharedSnapshot)
        completion(HomeWorkoutWidgetEntry(
            date: .now,
            snapshot: sharedSnapshot ?? sampleSnapshot,
            family: context.family
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeWorkoutWidgetEntry>) -> Void) {
        let sharedSnapshot = HomeWorkoutWidgetStore.read()
        recordDiagnostic("timeline", snapshot: sharedSnapshot)
        let entry = HomeWorkoutWidgetEntry(
            date: .now,
            snapshot: sharedSnapshot ?? sampleSnapshot,
            family: context.family
        )
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(6 * 60 * 60))))
    }

    private func recordDiagnostic(_ phase: String, snapshot: HomeWorkoutWidgetSnapshot?) {
#if DEBUG
        UserDefaults.standard.set(
            ["timestamp": Date().timeIntervalSince1970, "hasSharedSnapshot": snapshot != nil],
            forKey: "home_workout_widget_debug_\(phase)"
        )
#endif
    }

    private var sampleSnapshot: HomeWorkoutWidgetSnapshot {
        HomeWorkoutWidgetSnapshot(
            title: String(localized: "widget.fallback.title", table: "HomeWidget"),
            detail: String(localized: "widget.fallback.detail", table: "HomeWidget"),
            systemImageName: "figure.run"
        )
    }
}

private struct SmallHomeWorkoutWidgetContent: View {
    let snapshot: HomeWorkoutWidgetSnapshot

    var body: some View {
        VStack(spacing: 4) {
            Image("FoxAssistantHeadSmall", bundle: .main)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            Text(snapshot.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(snapshot.detail)
                .font(.system(size: 10, weight: .regular))
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct HomeWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: HomeWorkoutWidgetStore.widgetKind,
            provider: HomeWorkoutWidgetProvider()
        ) { entry in
            Group {
                if entry.family == .systemSmall {
                    SmallHomeWorkoutWidgetContent(snapshot: entry.snapshot)
                } else {
                    HomeWorkoutWidgetCard(snapshot: entry.snapshot, family: entry.family)
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .unredacted()
            .containerBackground(for: .widget) {
                Color(red: 0.96, green: 0.87, blue: 0.68)
            }
        }
        .configurationDisplayName(String(localized: "widget.gallery.name", table: "HomeWidget"))
        .description(String(localized: "widget.gallery.description", table: "HomeWidget"))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
