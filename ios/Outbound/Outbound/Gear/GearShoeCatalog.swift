import Foundation

struct GearShoeCatalogEntry: Identifiable, Hashable {
    var id: String { "\(brand)-\(model)" }
    let brand: String
    let model: String
    let purpose: GearPurpose
    let distanceLimitM: Double?

    var displayName: String {
        "\(brand) \(model)"
    }
}

enum GearShoeCatalog {
    static let entries: [GearShoeCatalogEntry] = [
        GearShoeCatalogEntry(brand: "ASICS", model: "Novablast 5", purpose: .dailyTrainer, distanceLimitM: 640_000),
        GearShoeCatalogEntry(brand: "ASICS", model: "Gel-Nimbus 27", purpose: .recovery, distanceLimitM: 640_000),
        GearShoeCatalogEntry(brand: "ASICS", model: "Metaspeed Sky Paris", purpose: .race, distanceLimitM: 320_000),
        GearShoeCatalogEntry(brand: "Brooks", model: "Ghost 16", purpose: .dailyTrainer, distanceLimitM: 640_000),
        GearShoeCatalogEntry(brand: "Brooks", model: "Glycerin 22", purpose: .recovery, distanceLimitM: 640_000),
        GearShoeCatalogEntry(brand: "Hoka", model: "Clifton 10", purpose: .dailyTrainer, distanceLimitM: 640_000),
        GearShoeCatalogEntry(brand: "Hoka", model: "Bondi 9", purpose: .recovery, distanceLimitM: 640_000),
        GearShoeCatalogEntry(brand: "Hoka", model: "Speedgoat 6", purpose: .trail, distanceLimitM: 800_000),
        GearShoeCatalogEntry(brand: "New Balance", model: "Fresh Foam X 1080v14", purpose: .dailyTrainer, distanceLimitM: 640_000),
        GearShoeCatalogEntry(brand: "New Balance", model: "FuelCell Rebel v4", purpose: .dailyTrainer, distanceLimitM: 560_000),
        GearShoeCatalogEntry(brand: "Nike", model: "Pegasus 41", purpose: .dailyTrainer, distanceLimitM: 640_000),
        GearShoeCatalogEntry(brand: "Nike", model: "Vaporfly 3", purpose: .race, distanceLimitM: 320_000),
        GearShoeCatalogEntry(brand: "Nike", model: "Zegama 2", purpose: .trail, distanceLimitM: 800_000),
        GearShoeCatalogEntry(brand: "On", model: "Cloudmonster 2", purpose: .dailyTrainer, distanceLimitM: 640_000),
        GearShoeCatalogEntry(brand: "On", model: "Cloudsurfer", purpose: .recovery, distanceLimitM: 640_000),
        GearShoeCatalogEntry(brand: "Saucony", model: "Ride 18", purpose: .dailyTrainer, distanceLimitM: 640_000),
        GearShoeCatalogEntry(brand: "Saucony", model: "Endorphin Speed 4", purpose: .race, distanceLimitM: 480_000),
        GearShoeCatalogEntry(brand: "Saucony", model: "Peregrine 15", purpose: .trail, distanceLimitM: 800_000)
    ]

    static func bestMatch(for query: String, purpose: GearPurpose) -> GearShoeCatalogEntry? {
        let normalizedQuery = normalize(query)
        guard normalizedQuery.count >= 2 else { return nil }

        return entries
            .map { entry in (entry: entry, score: score(entry, query: normalizedQuery, purpose: purpose)) }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.entry.displayName < rhs.entry.displayName
                }
                return lhs.score > rhs.score
            }
            .first?
            .entry
    }

    private static func score(_ entry: GearShoeCatalogEntry, query: String, purpose: GearPurpose) -> Int {
        let brand = normalize(entry.brand)
        let model = normalize(entry.model)
        let combined = normalize(entry.displayName)
        let queryTokens = tokens(in: query)
        let entryTokens = tokens(in: combined)
        var score = entry.purpose == purpose ? 3 : 0

        guard queryTokens.allSatisfy({ queryToken in
            entryTokens.contains { $0.hasPrefix(queryToken) }
        }) else { return 0 }

        if combined == query { score += 100 }
        if combined.hasPrefix(query) { score += 40 }
        if brand.hasPrefix(query) || model.hasPrefix(query) { score += 28 }

        for token in queryTokens {
            if brand.hasPrefix(token) || model.hasPrefix(token) {
                score += 10
            } else if entryTokens.contains(where: { $0.hasPrefix(token) }) {
                score += 4
            }
        }

        return score
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokens(in value: String) -> [String] {
        normalize(value)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }
}
