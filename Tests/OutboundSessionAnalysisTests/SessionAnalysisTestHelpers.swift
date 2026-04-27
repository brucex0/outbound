import Foundation
import XCTest
@testable import OutboundSessionAnalysis

func makeSnapshot(
    elapsedSeconds: Int,
    distanceMeters: Double,
    paceSecsPerKm: Double?,
    heartRate: Int? = nil,
    isActive: Bool = true
) -> ActiveSessionSnapshot {
    ActiveSessionSnapshot(
        recordedAt: Date(timeIntervalSince1970: Double(elapsedSeconds)),
        startedAt: Date(timeIntervalSince1970: 0),
        elapsedSeconds: elapsedSeconds,
        distanceMeters: distanceMeters,
        currentPaceSecsPerKm: paceSecsPerKm,
        heartRate: heartRate,
        location: nil,
        isActive: isActive
    )
}

func makeProfile(preferredPaceSecs: Double?) -> CoachProfile {
    CoachProfile(
        version: 1,
        coachName: "Coach",
        personality: "direct",
        voiceId: "en-US",
        athlete: CoachProfile.AthleteSnapshot(
            fitnessLevel: "intermediate",
            weeklyVolumeKm: 25,
            preferredPaceSecs: preferredPaceSecs,
            strengths: ["consistency"],
            weaknesses: ["late pace drift"],
            records: [:]
        ),
        goals: [
            CoachProfile.GoalItem(
                type: "pace",
                description: "Hold target pace",
                targetDate: nil,
                targetValue: preferredPaceSecs,
                achieved: false
            )
        ],
        memorySnapshot: CoachProfile.MemorySnapshot(
            recentActivities: [],
            weeklyVolumeKm: 25,
            longestRunKm: 12,
            consistencyScore: 0.8,
            recentInsight: "Start controlled and finish strong."
        ),
        systemPrompt: "Coach concise in-session decisions.",
        builtAt: Date(timeIntervalSince1970: 0)
    )
}

@MainActor
func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    predicate: @escaping @MainActor () -> Bool
) async throws {
    let pollIntervalNanoseconds: UInt64 = 10_000_000
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        if predicate() {
            return
        }

        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }

    XCTFail("Timed out waiting for condition")
}

@MainActor
func waitForMainActor() async throws {
    try await Task.sleep(nanoseconds: 10_000_000)
}
