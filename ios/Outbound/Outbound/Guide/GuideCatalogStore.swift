import Combine
import Foundation

@MainActor
final class GuideCatalogStore: ObservableObject {
    nonisolated static let themeKey = "outbound_theme_v1"

    @Published private(set) var templates: [GuideTemplate]
    @Published private(set) var selection: GuideSelection
    private let defaults: UserDefaults
    private let selectionKey = "guide_catalog_selection_v2"
    private let learningKey = "live_guidance_learning_v1"
    private var learningState: LiveGuidanceLearningState

    var selectedTemplate: GuideTemplate {
        templates.first { $0.id == selection.coachPersonaId } ?? templates[0]
    }

    var selectedVoice: GuideVoice {
        selectedTemplate.voiceOptions.first { $0.id == selection.voiceProfileId } ?? selectedTemplate.defaultVoice
    }

    var selectedPersona: GuidePersona {
        GuidePersona(
            template: selectedTemplate,
            voice: selectedVoice,
            intensity: selection.intensity,
            nudgeFrequency: selection.nudgeFrequency,
            coachingContract: selection.coachingContract
        )
    }

    var selectedTheme: OutboundTheme { selection.theme }

    init(
        templates: [GuideTemplate] = GuideTemplate.fixtures,
        defaults: UserDefaults = .standard
    ) {
        self.templates = templates
        self.defaults = defaults
        learningState = defaults.data(forKey: learningKey)
            .flatMap { try? JSONDecoder().decode(LiveGuidanceLearningState.self, from: $0) }
            ?? LiveGuidanceLearningState()

        let fallback = templates[0]
        let savedTheme = defaults.string(forKey: Self.themeKey)
            .flatMap(OutboundTheme.init(rawValue:)) ?? .victoryGold
        if let data = defaults.data(forKey: selectionKey),
           let decoded = try? JSONDecoder().decode(GuideSelection.self, from: data) {
            selection = decoded
        } else {
            selection = GuideSelection(
                coachPersonaId: fallback.id,
                voiceProfileId: fallback.defaultVoice.id,
                theme: savedTheme,
                intensity: .balanced,
                nudgeFrequency: .normal,
                coachingContract: .responsive
            )
        }
        normalizeSelection()
        defaults.set(selection.theme.rawValue, forKey: Self.themeKey)
        updateAudioPackSelection()
    }

    func refreshServerCatalog() async {
        await LiveCoachFeatureState.shared.refresh()
        guard let catalog = LiveCoachFeatureState.shared.catalog else { return }
        let serverTemplates = GuideTemplate.from(catalog: catalog)
        guard !serverTemplates.isEmpty else { return }
        templates = serverTemplates
        normalizeSelection()
        updateAudioPackSelection()
    }

    func setCoachPersona(id: String) {
        guard let template = templates.first(where: { $0.id == id }) else { return }
        selection.coachPersonaId = id
        if !template.allowedVoiceIds.contains(selection.voiceProfileId) {
            selection.voiceProfileId = template.defaultVoice.id
        }
        saveSelection()
        updateAudioPackSelection()
    }

    func setVoice(id: String) {
        guard selectedTemplate.allowedVoiceIds.contains(id),
              selectedTemplate.voiceOptions.contains(where: { $0.id == id })
        else { return }
        selection.voiceProfileId = id
        saveSelection()
        updateAudioPackSelection()
    }

    func refreshInstalledVoices() {
        normalizeSelection()
        updateAudioPackSelection()
    }

    func setTheme(_ theme: OutboundTheme) {
        selection.theme = theme
        defaults.set(theme.rawValue, forKey: Self.themeKey)
        saveSelection()
    }

    func setIntensity(_ intensity: GuidanceIntensity) {
        selection.intensity = intensity
        saveSelection()
    }

    func setNudgeFrequency(_ frequency: NudgeFrequency) {
        selection.nudgeFrequency = frequency
        saveSelection()
    }

    func setCoachingContract(_ contract: CoachingContract) {
        selection.coachingContract = contract
        saveSelection()
    }

    func suppressedMomentTypes(for contract: CoachingContract) -> Set<LiveGuidanceMomentType> {
        guard contract == .responsive else { return [] }
        return Set(learningState.moments.compactMap { rawType, evidence in
            guard evidence.evaluatedCount >= 3,
                  Double(evidence.helpfulCount) / Double(evidence.evaluatedCount) < 0.34
            else { return nil }
            return LiveGuidanceMomentType(rawValue: rawType)
        })
    }

    func recordGuidanceReport(_ report: LiveGuidanceSessionReport) {
        for cue in report.cues where cue.outcome != .pending && cue.outcome != .notMeasured {
            var evidence = learningState.moments[cue.momentType.rawValue] ?? LiveGuidanceMomentEvidence()
            evidence.evaluatedCount += 1
            if cue.outcome.isHelpfulResult { evidence.helpfulCount += 1 }
            learningState.moments[cue.momentType.rawValue] = evidence
        }
        saveLearningState()
    }

    func recordGuidanceFeedback(_ feedback: LiveGuidanceFeedback) {
        learningState.feedbackCounts[feedback.rawValue, default: 0] += 1
        saveLearningState()
    }

    private func normalizeSelection() {
        guard let template = templates.first(where: { $0.id == selection.coachPersonaId }) else {
            selection.coachPersonaId = templates[0].id
            selection.voiceProfileId = templates[0].defaultVoice.id
            saveSelection()
            return
        }
        if !template.allowedVoiceIds.contains(selection.voiceProfileId)
            || !template.voiceOptions.contains(where: { $0.id == selection.voiceProfileId }) {
            selection.voiceProfileId = template.defaultVoice.id
            saveSelection()
        }
    }

    private func updateAudioPackSelection() {
        GuideAudioPackStore.shared.select(
            coachPersonaID: selectedTemplate.id,
            voiceProfileID: selectedVoice.id,
            scriptStyleID: selectedTemplate.fixedScriptStyleId
        )
    }

    private func saveSelection() {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: selectionKey)
    }

    private func saveLearningState() {
        guard let data = try? JSONEncoder().encode(learningState) else { return }
        defaults.set(data, forKey: learningKey)
    }
}

struct GuideSelection: Codable, Equatable {
    var coachPersonaId: String
    var voiceProfileId: String
    var theme: OutboundTheme
    var intensity: GuidanceIntensity
    var nudgeFrequency: NudgeFrequency
    var coachingContract: CoachingContract
}

private struct LiveGuidanceLearningState: Codable {
    var moments: [String: LiveGuidanceMomentEvidence] = [:]
    var feedbackCounts: [String: Int] = [:]
}

private struct LiveGuidanceMomentEvidence: Codable {
    var evaluatedCount = 0
    var helpfulCount = 0
}
