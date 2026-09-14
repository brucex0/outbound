import HealthKit
import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WatchWorkoutManager.shared.startFromPhone(configuration: workoutConfiguration)
    }

    func handleActiveWorkoutRecovery() {
        WatchWorkoutManager.shared.recoverActiveWorkout()
    }
}
