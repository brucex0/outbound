import Foundation
import CoreGraphics

func stretchCatalogText(_ suffix: String) -> String {
    NSLocalizedString("stretch.catalog." + suffix, tableName: "StretchCatalog", comment: "Stretch catalog")
}

struct StretchDefinition: Identifiable {
    let id: String
    let bilateral: Bool
    let floor: Bool
    let support: Bool
    let surface: Bool
    let area: String
    let lying: Bool
    let paths: [[CGPoint]]
    var dynamic: Bool = false
    var artwork: String? = nil
    var artworkSide: String = "left"
    var alternating: Bool = false
    var cushion: Bool = false
    var title: String { stretchCatalogText("movement.\(id).title") }
    var instruction: String { stretchCatalogText("movement.\(id).instruction") }
    var requirements: String {
        [floor ? "floor" : nil, support ? "wall" : nil, surface ? "surface" : nil, cushion ? "cushion" : nil].compactMap { $0 }.map { stretchCatalogText("ui." + $0) }.joined(separator: " · ")
    }
}

struct StretchEntry: Codable, Equatable, Identifiable, Sendable {
    var movementID: String
    var seconds: Int
    var id: String { movementID }
}
struct StretchTemplate {
    let id: String
    let wireSuffix: String
    let entries: [StretchEntry]
    var title: String { stretchCatalogText("template." + id) }
}

/// Entry points provide context, not a saved activity. The post-save host supplies its own header.
enum StretchEntryPoint: String { case postSave = "post_save", today, standalone }
struct StretchLaunchContext {
    var entryPoint: StretchEntryPoint = .standalone
    var activityType: ActivityType? = nil
    var isIndoor = false
}

struct StretchMovement: Identifiable, Sendable {
    let id: String
    let title: String
    let instruction: String
    let side: String?
    let duration: Int
    let icon: String
    let cue: String
}
struct StretchRoutine: Identifiable, Sendable {
    let id: String
    let preferenceID: String
    let title: String
    let entries: [StretchEntry]
    let customized: Bool
    var isWarmup: Bool { entries.contains { StretchCatalog.definition($0.movementID)?.dynamic == true } }
    var isStanding: Bool { !entries.contains { StretchCatalog.definition($0.movementID)?.floor == true } }
    var requirements: String {
        let definitions = entries.compactMap { StretchCatalog.definition($0.movementID) }
        let keys = [definitions.contains(where: \.floor) ? "floor" : nil, definitions.contains(where: \.support) ? "wall" : nil, definitions.contains(where: \.surface) ? "surface" : nil, definitions.contains(where: \.cushion) ? "cushion" : nil].compactMap { $0 }
        return (keys.isEmpty ? ["none"] : keys).map { stretchCatalogText("ui." + $0) }.joined(separator: " · ")
    }
    var movements: [StretchMovement] {
        entries.flatMap { entry -> [StretchMovement] in
            guard let definition = StretchCatalog.definition(entry.movementID) else { return [] }
            return (definition.bilateral ? ["left", "right"] : ["both"]).map { side in
                StretchMovement(id: "\(entry.movementID)_\(side)", title: definition.title, instruction: definition.instruction,
                    side: definition.alternating ? stretchCatalogText("ui.alternating") : NSLocalizedString("post_workout_stretch.side." + side, comment: "Side"), duration: entry.seconds,
                    icon: "figure.flexibility", cue: "\(entry.movementID)_\(side)")
            }
        }
    }
    var totalSeconds: Int { movements.reduce(0) { $0 + $1.duration } + 3 + max(0, movements.count - 1) * 5 }
    var calculatedDuration: String { "≈ " + Duration.seconds(totalSeconds).formatted(.time(pattern: .minuteSecond)) }
}

enum StretchCatalog {
    static let durations = [15, 20, 25, 30]
    static func definition(_ id: String) -> StretchDefinition? { StretchCatalogData.definitions.first { $0.id == id } }
    static func valid(_ entries: [StretchEntry]) -> Bool {
        !entries.isEmpty && entries.count <= 20 && Set(entries.map(\.movementID)).count == entries.count && entries.allSatisfy { definition($0.movementID) != nil && durations.contains($0.seconds) } && Set(entries.compactMap { definition($0.movementID)?.dynamic }).count == 1
    }
    static func routine(template: StretchTemplate, entries: [StretchEntry]? = nil, activityType: ActivityType? = nil) -> StretchRoutine {
        let suffix = template.wireSuffix
        let id = activityType.map { "post_save_\($0.rawValue)_\(suffix)" } ?? "stretch_\(suffix)"
        return StretchRoutine(id: id, preferenceID: template.id, title: template.title, entries: entries ?? template.entries, customized: entries != nil)
    }
    static func routines(activityType: ActivityType? = nil, entryPoint: StretchEntryPoint = .standalone, store: StretchCustomizationStore = StretchCustomizationStore()) -> [StretchRoutine] {
        StretchCatalogData.templates.filter { entryPoint != .postSave || $0.id != "pre_run" }.map { routine(template: $0, entries: store.load($0.id), activityType: activityType) }
    }
    static var outdoorFallback: StretchRoutine {
        let original = routine(template: StretchCatalogData.templates[0])
        return StretchRoutine(id: "stretch_outdoor_reset_v1", preferenceID: original.preferenceID, title: original.title, entries: original.entries, customized: false)
    }
    static func initial(_ routines: [StretchRoutine], isIndoor: Bool, last: String?, lastStanding: String?, sport: ActivityType?) -> StretchRoutine {
        let remembered = isIndoor ? last : lastStanding
        return routines.first { $0.preferenceID == remembered && (isIndoor || $0.isStanding) }
            ?? routines.first { $0.preferenceID == (sport == .swimming ? "upper_body" : "standing_quick") && (isIndoor || $0.isStanding) }
            ?? routines.first { isIndoor || $0.isStanding }
            ?? outdoorFallback
    }
}

/// One local customization per template, shared across sports and launch surfaces.
struct StretchCustomizationStore {
    var defaults: UserDefaults = .standard
    private func key(_ id: String) -> String { "stretch_customization_v1_" + id }
    func load(_ id: String) -> [StretchEntry]? {
        guard let data = defaults.data(forKey: key(id)) else { return nil }
        do {
            let entries = try JSONDecoder().decode([StretchEntry].self, from: data)
            guard StretchCatalog.valid(entries) else {
                ActivityDiagnosticLog.error(.lifecycle, "Stretch customization validation failed")
                return nil
            }
            return entries
        } catch {
            ActivityDiagnosticLog.error(.lifecycle, "Stretch customization decode failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            return nil
        }
    }
    func save(_ entries: [StretchEntry], templateID: String) throws {
        guard StretchCatalog.valid(entries) else { throw CocoaError(.coderInvalidValue) }
        defaults.set(try JSONEncoder().encode(entries), forKey: key(templateID))
    }
    func reset(_ id: String) { defaults.removeObject(forKey: key(id)) }
}
