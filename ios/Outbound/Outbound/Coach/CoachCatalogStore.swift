import Foundation
import Combine

@MainActor
final class CoachCatalogStore: ObservableObject {
    @Published private(set) var templates: [CoachTemplate]
    @Published private(set) var selection: CoachSelection

    private let defaults: UserDefaults
    private let selectionKey = "coach_catalog_selection_v1"

    var selectedTemplate: CoachTemplate {
        templates.first { $0.id == selection.templateId } ?? templates[0]
    }

    var selectedVoice: CoachVoice {
        selectedTemplate.voiceOptions.first { $0.id == selection.voiceId } ?? selectedTemplate.defaultVoice
    }

    var selectedFace: CoachFace {
        selectedTemplate.faceOptions.first { $0.id == selection.faceId } ?? selectedTemplate.defaultFace
    }

    var selectedPersona: CoachPersona {
        CoachPersona(
            template: selectedTemplate,
            voice: selectedVoice,
            face: selectedFace,
            intensity: selection.intensity,
            nudgeFrequency: selection.nudgeFrequency
        )
    }

    init(
        templates: [CoachTemplate] = CoachTemplate.fixtures,
        defaults: UserDefaults = .standard
    ) {
        self.templates = templates
        self.defaults = defaults

        let fallbackTemplate = templates[0]
        let fallbackSelection = CoachSelection(
            templateId: fallbackTemplate.id,
            voiceId: fallbackTemplate.defaultVoice.id,
            faceId: fallbackTemplate.defaultFace.id,
            intensity: .balanced,
            nudgeFrequency: .normal
        )

        if let data = defaults.data(forKey: selectionKey),
           let decoded = try? JSONDecoder().decode(CoachSelection.self, from: data) {
            selection = decoded
        } else {
            selection = fallbackSelection
        }

        normalizeSelection()
    }

    func templates(for sport: SportType) -> [CoachTemplate] {
        templates.filter { $0.sport == sport }
    }

    func select(_ template: CoachTemplate) {
        selection.templateId = template.id
        if !template.voiceOptions.contains(where: { $0.id == selection.voiceId }) {
            selection.voiceId = template.defaultVoice.id
        }
        if !template.faceOptions.contains(where: { $0.id == selection.faceId }) {
            selection.faceId = template.defaultFace.id
        }
        saveSelection()
    }

    func setVoice(id: String) {
        guard selectedTemplate.voiceOptions.contains(where: { $0.id == id }) else { return }
        selection.voiceId = id
        saveSelection()
    }

    func setFace(id: String) {
        guard selectedTemplate.faceOptions.contains(where: { $0.id == id }) else { return }
        selection.faceId = id
        saveSelection()
    }

    func setIntensity(_ intensity: CoachingIntensity) {
        selection.intensity = intensity
        saveSelection()
    }

    func setNudgeFrequency(_ frequency: NudgeFrequency) {
        selection.nudgeFrequency = frequency
        saveSelection()
    }

    private func normalizeSelection() {
        guard let template = templates.first(where: { $0.id == selection.templateId }) else {
            selection = CoachSelection(
                templateId: templates[0].id,
                voiceId: templates[0].defaultVoice.id,
                faceId: templates[0].defaultFace.id,
                intensity: .balanced,
                nudgeFrequency: .normal
            )
            saveSelection()
            return
        }

        var changed = false
        if !template.voiceOptions.contains(where: { $0.id == selection.voiceId }) {
            selection.voiceId = template.defaultVoice.id
            changed = true
        }
        if !template.faceOptions.contains(where: { $0.id == selection.faceId }) {
            selection.faceId = template.defaultFace.id
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

struct CoachSelection: Codable, Equatable {
    var templateId: String
    var voiceId: String
    var faceId: String
    var intensity: CoachingIntensity
    var nudgeFrequency: NudgeFrequency
}
