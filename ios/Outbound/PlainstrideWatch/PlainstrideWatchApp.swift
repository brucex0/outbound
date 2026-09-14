import SwiftUI

@main
struct PlainstrideWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @StateObject private var workout = WatchWorkoutManager.shared

    var body: some Scene {
        WindowGroup {
            WatchWorkoutView()
                .environmentObject(workout)
        }
    }
}
