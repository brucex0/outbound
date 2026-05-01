import ActivityKit
import Foundation

struct OutboundLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let elapsedSeconds: Int
        let elapsedReferenceDate: Date?
        let distanceText: String
        let paceText: String
        let statusText: String
        let isPaused: Bool
    }

    let activityName: String
    let sportName: String
    let sportSystemImageName: String
}
