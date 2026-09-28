import Foundation

enum AutoPauseDefaults {
    static func isEnabled(for activityType: ActivityType) -> Bool {
        switch activityType {
        case .running, .cycling, .swimming: true
        case .hiking, .walking, .strengthTraining, .mobility: false
        }
    }
}
