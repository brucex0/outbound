import Foundation
import Combine

enum VoiceSelectionRequirementReason {
    case appLanguageChanged
    case selectedVoiceUnavailable
    case initialSelection
}

@MainActor
final class GuideCatalogStore: ObservableObject {
    nonisolated static let themeKey = "outbound_theme_v1"
    @Published private(set) var templates: [GuideTemplate]
    @Published private(set) var selection: GuideSelection
    @Published private(set) var requiresVoiceSelection = false
    @Published private(set) var isVoiceSelectionPromptPresented = false
    @Published private(set) var voiceSelectionRequirementReason: VoiceSelectionRequirementReason?

    private let defaults: UserDefaults
    private let selectionKey = "guide_catalog_selection_v1"
    private let voiceLanguageKey = "guide_catalog_voice_language_v1"

    var selectedTemplate: GuideTemplate {
        templates.first { $0.id == selection.templateId } ?? templates[0]
    }

    var selectedVoice: GuideVoice {
        selectedTemplate.voiceOptions.first { $0.id == selection.voiceId } ?? selectedTemplate.defaultVoice
    }

    var selectedPersona: GuidePersona {
        GuidePersona(
            template: selectedTemplate,
            voice: selectedVoice,
            intensity: selection.intensity,
            nudgeFrequency: selection.nudgeFrequency
        )
    }

    var selectedTheme: OutboundTheme { selection.theme }

    var hasDownloadedAppleVoices: Bool {
        selectedTemplate.voiceOptions.contains { $0.appleVoiceIdentifier != nil && !$0.isStandardQuality }
    }

    init(
        templates: [GuideTemplate] = GuideTemplate.fixtures,
        defaults: UserDefaults = .standard
    ) {
        self.templates = templates
        self.defaults = defaults

        let fallbackTemplate = templates[0]
        let fallbackSelection = GuideSelection(
            templateId: fallbackTemplate.id,
            voiceId: fallbackTemplate.defaultVoice.id,
            theme: .indigo,
            intensity: .balanced,
            nudgeFrequency: .normal
        )

        let hasSavedSelection: Bool
        if let data = defaults.data(forKey: selectionKey),
           let decoded = try? JSONDecoder().decode(GuideSelection.self, from: data) {
            selection = decoded
            hasSavedSelection = true
        } else {
            selection = fallbackSelection
            hasSavedSelection = false
        }

        let savedVoiceIsCompatible = templates
            .first(where: { $0.id == selection.templateId })?
            .voiceOptions
            .contains(where: { $0.id == selection.voiceId }) == true
        if hasSavedSelection,
           savedVoiceIsCompatible,
           defaults.string(forKey: voiceLanguageKey) == nil {
            // Migrate selections created before voice-language tracking existed.
            defaults.set(AppLanguage.currentIdentifier, forKey: voiceLanguageKey)
        }

        let confirmedLanguage = defaults.string(forKey: voiceLanguageKey)
        normalizeSelection()
        if !hasSavedSelection {
            voiceSelectionRequirementReason = .initialSelection
        } else if confirmedLanguage != nil,
                  confirmedLanguage != AppLanguage.currentIdentifier {
            voiceSelectionRequirementReason = .appLanguageChanged
        } else if !savedVoiceIsCompatible {
            voiceSelectionRequirementReason = .selectedVoiceUnavailable
        }
        requiresVoiceSelection = voiceSelectionRequirementReason != nil
        isVoiceSelectionPromptPresented = requiresVoiceSelection
        defaults.set(selection.theme.rawValue, forKey: Self.themeKey)
    }

    func setVoice(id: String) {
        guard selectedTemplate.voiceOptions.contains(where: { $0.id == id }) else { return }
        selection.voiceId = id
        defaults.set(AppLanguage.currentIdentifier, forKey: voiceLanguageKey)
        requiresVoiceSelection = false
        isVoiceSelectionPromptPresented = false
        voiceSelectionRequirementReason = nil
        saveSelection()
    }

    func requestVoiceSelection() {
        guard requiresVoiceSelection else { return }
        isVoiceSelectionPromptPresented = true
    }

    func dismissVoiceSelectionPrompt() {
        defaults.set(AppLanguage.currentIdentifier, forKey: voiceLanguageKey)
        requiresVoiceSelection = false
        isVoiceSelectionPromptPresented = false
        voiceSelectionRequirementReason = nil
        saveSelection()
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

    func refreshInstalledVoices() {
        if defaults.string(forKey: voiceLanguageKey) != AppLanguage.currentIdentifier {
            requiresVoiceSelection = true
            isVoiceSelectionPromptPresented = true
            voiceSelectionRequirementReason = .appLanguageChanged
        }
        let voiceOptions = GuideVoice.availableOptions
        guard selectedTemplate.voiceOptions != voiceOptions else { return }
        templates = templates.map { template in
            GuideTemplate(
                id: template.id,
                sport: template.sport,
                displayName: template.displayName,
                tagline: template.tagline,
                personality: template.personality,
                guidanceStyle: template.guidanceStyle,
                defaultVoiceId: template.defaultVoiceId,
                voiceOptions: voiceOptions,
                systemPromptSeed: template.systemPromptSeed
            )
        }
        normalizeSelection()
    }

    private func normalizeSelection() {
        guard let template = templates.first(where: { $0.id == selection.templateId }) else {
            selection = GuideSelection(
                templateId: templates[0].id,
                voiceId: templates[0].defaultVoice.id,
                theme: .indigo,
                intensity: .balanced,
                nudgeFrequency: .normal
            )
            saveSelection()
            return
        }

        var changed = false
        if !template.voiceOptions.contains(where: { $0.id == selection.voiceId }) {
            selection.voiceId = template.defaultVoice.id
            requiresVoiceSelection = true
            voiceSelectionRequirementReason = .selectedVoiceUnavailable
            changed = true
        }
        if changed {
            saveSelection()
        }
    }

    private func saveSelection() {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: selectionKey)
    }

}

struct GuideSelection: Codable, Equatable {
    var templateId: String
    var voiceId: String
    var theme: OutboundTheme
    var intensity: GuidanceIntensity
    var nudgeFrequency: NudgeFrequency

    private enum CodingKeys: String, CodingKey {
        case templateId, voiceId, theme, intensity, nudgeFrequency
    }

    init(
        templateId: String,
        voiceId: String,
        theme: OutboundTheme,
        intensity: GuidanceIntensity,
        nudgeFrequency: NudgeFrequency
    ) {
        self.templateId = templateId
        self.voiceId = voiceId
        self.theme = theme
        self.intensity = intensity
        self.nudgeFrequency = nudgeFrequency
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        templateId = try values.decode(String.self, forKey: .templateId)
        voiceId = try values.decode(String.self, forKey: .voiceId)
        theme = try values.decodeIfPresent(OutboundTheme.self, forKey: .theme) ?? .indigo
        intensity = try values.decode(GuidanceIntensity.self, forKey: .intensity)
        nudgeFrequency = try values.decode(NudgeFrequency.self, forKey: .nudgeFrequency)
    }
}
