import Foundation

// Mirror of backend CoachProfilePayload — synced and stored on device
struct CoachProfile: Codable, Identifiable {
    var id: String { coachName + "\(version)" }
    let version: Int
    let coachName: String
    let personality: String
    let voiceId: String
    let athlete: AthleteSnapshot
    let goals: [GoalItem]
    let memorySnapshot: MemorySnapshot
    let systemPrompt: String
    let builtAt: Date

    struct AthleteSnapshot: Codable {
        let fitnessLevel: String
        let weeklyVolumeKm: Double
        let preferredPaceSecs: Double?
        let strengths: [String]
        let weaknesses: [String]
        let records: [String: Double]
    }

    struct GoalItem: Codable {
        let type: String
        let description: String
        let targetDate: String?
        let targetValue: Double?
        let achieved: Bool
    }

    struct MemorySnapshot: Codable {
        let recentActivities: [RecentActivity]
        let weeklyVolumeKm: Double
        let longestRunKm: Double
        let consistencyScore: Double
        let recentInsight: String

        struct RecentActivity: Codable {
            let date: String
            let type: String
            let distanceKm: Double
            let avgPaceSecs: Double
        }
    }
}
