import Foundation

enum SessionAnalysisUrgency: String {
    case steady
    case opportunity
    case caution
}

struct SessionAnalysisRequest {
    let profile: GuideProfile?
    let persona: GuidePersona?
    let snapshot: ActiveSessionSnapshot
    let recentSnapshots: [ActiveSessionSnapshot]
    let sessionIntent: SessionIntent?
    let companionBrief: CompanionSessionBriefDTO?
    let momentType: LiveGuidanceMomentType?
    let routeGuidanceActive: Bool

    init(
        profile: GuideProfile?,
        persona: GuidePersona?,
        snapshot: ActiveSessionSnapshot,
        recentSnapshots: [ActiveSessionSnapshot],
        sessionIntent: SessionIntent? = nil,
        companionBrief: CompanionSessionBriefDTO? = nil,
        momentType: LiveGuidanceMomentType? = nil,
        routeGuidanceActive: Bool = false
    ) {
        self.profile = profile
        self.persona = persona
        self.snapshot = snapshot
        self.recentSnapshots = recentSnapshots
        self.sessionIntent = sessionIntent
        self.companionBrief = companionBrief
        self.momentType = momentType
        self.routeGuidanceActive = routeGuidanceActive
    }
}

struct SessionAnalysisResult: Equatable {
    let message: String
    let urgency: SessionAnalysisUrgency
    let shouldSpeak: Bool
    let generatedAt: Date
    let expiresAt: Date
    let providerID: String
    let source: LiveCoachCueSource
    let result: LiveCoachCueResult
    let effectiveMode: LiveCoachAudioMode
    let accessReason: LiveCoachAccessReason
    let latencyBucket: LiveCoachLatencyBucket
    let fixedCueKey: String?
    let audioData: Data?
}

@MainActor
protocol SessionAnalysisProvider: AnyObject {
    var identifier: String { get }
    var displayName: String { get }

    func beginSession(
        profile: GuideProfile?,
        persona: GuidePersona?,
        sessionIntent: SessionIntent?,
        companionBrief: CompanionSessionBriefDTO?
    )
    func analyze(_ request: SessionAnalysisRequest) async throws -> SessionAnalysisResult
    func endSession(report: LiveGuidanceSessionReport?)
}

enum SessionAnalysisProviderFactory {
    @MainActor
    static func makePreferredProvider() -> any SessionAnalysisProvider {
        ServerLiveCoachProvider()
    }
}
