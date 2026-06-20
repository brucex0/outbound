import Combine
import Foundation

struct GearItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, Hashable {
        case shoe
    }

    let id: UUID
    var kind: Kind
    var purpose: GearPurpose
    var name: String
    var brand: String
    var model: String
    var startedAt: Date
    var retiredAt: Date?
    var distanceLimitM: Double
    var notes: String

    var displayName: String {
        [brand, model].filter { !$0.isEmpty }.joined(separator: " ").isEmpty
            ? name
            : [brand, model].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case purpose
        case name
        case brand
        case model
        case startedAt
        case retiredAt
        case distanceLimitM
        case notes
    }

    init(
        id: UUID,
        kind: Kind,
        purpose: GearPurpose,
        name: String,
        brand: String,
        model: String,
        startedAt: Date,
        retiredAt: Date?,
        distanceLimitM: Double,
        notes: String
    ) {
        self.id = id
        self.kind = kind
        self.purpose = purpose
        self.name = name
        self.brand = brand
        self.model = model
        self.startedAt = startedAt
        self.retiredAt = retiredAt
        self.distanceLimitM = distanceLimitM
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        purpose = try container.decodeIfPresent(GearPurpose.self, forKey: .purpose) ?? .dailyTrainer
        name = try container.decode(String.self, forKey: .name)
        brand = try container.decode(String.self, forKey: .brand)
        model = try container.decode(String.self, forKey: .model)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        retiredAt = try container.decodeIfPresent(Date.self, forKey: .retiredAt)
        distanceLimitM = try container.decode(Double.self, forKey: .distanceLimitM)
        notes = try container.decode(String.self, forKey: .notes)
    }
}

enum GearPurpose: String, CaseIterable, Codable, Identifiable, Hashable {
    case dailyTrainer
    case race
    case trail
    case recovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dailyTrainer: return "Daily trainer"
        case .race: return "Race"
        case .trail: return "Trail"
        case .recovery: return "Recovery"
        }
    }

    var suggestedNickname: String {
        switch self {
        case .dailyTrainer: return "Daily trainer"
        case .race: return "Race shoe"
        case .trail: return "Trail shoe"
        case .recovery: return "Recovery shoe"
        }
    }

    var suggestedDistanceLimitM: Double {
        switch self {
        case .dailyTrainer: return 640_000
        case .race: return 320_000
        case .trail: return 800_000
        case .recovery: return 640_000
        }
    }

    var suggestedDistanceRangeM: ClosedRange<Double> {
        switch self {
        case .dailyTrainer: return 480_000...800_000
        case .race: return 240_000...400_000
        case .trail: return 640_000...965_606.4
        case .recovery: return 480_000...800_000
        }
    }

    var retirementHintPrefix: String {
        switch self {
        case .dailyTrainer: return "Most road trainers last about"
        case .race: return "Race shoes usually feel best for about"
        case .trail: return "Trail shoes often last about"
        case .recovery: return "Cushioned recovery shoes usually last about"
        }
    }
}

struct GearMileageSummary: Identifiable, Hashable {
    let item: GearItem
    let distanceMeters: Double
    let lastUsedAt: Date?

    var id: UUID { item.id }

    var remainingMeters: Double {
        max(0, item.distanceLimitM - distanceMeters)
    }

    var usageFraction: Double {
        guard item.distanceLimitM > 0 else { return 0 }
        return min(1, max(0, distanceMeters / item.distanceLimitM))
    }
}

@MainActor
final class GearStore: ObservableObject {
    @Published private(set) var shoes: [GearItem] = []
    @Published var defaultShoeID: UUID? {
        didSet { defaults.set(defaultShoeID?.uuidString, forKey: defaultShoeIDKey) }
    }

    private let defaults: UserDefaults
    private let shoesKey = "gear_shoes_v1"
    private let defaultShoeIDKey = "gear_default_shoe_id_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.shoes = Self.loadShoes(defaults: defaults, key: shoesKey)
        self.defaultShoeID = defaults.string(forKey: defaultShoeIDKey).flatMap(UUID.init(uuidString:))
    }

    var defaultShoe: GearItem? {
        guard let defaultShoeID else { return activeShoes.first }
        return shoes.first { $0.id == defaultShoeID } ?? activeShoes.first
    }

    var activeShoes: [GearItem] {
        shoes.filter { $0.retiredAt == nil }
    }

    func addShoe(
        name: String,
        brand: String,
        model: String,
        purpose: GearPurpose = .dailyTrainer,
        distanceLimitM: Double = 640_000,
        notes: String = ""
    ) {
        let item = GearItem(
            id: UUID(),
            kind: .shoe,
            purpose: purpose,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Running Shoes" : name,
            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            startedAt: Date(),
            retiredAt: nil,
            distanceLimitM: distanceLimitM,
            notes: notes
        )
        shoes.insert(item, at: 0)
        if defaultShoeID == nil { defaultShoeID = item.id }
        persist()
    }

    func retire(_ item: GearItem) {
        guard let index = shoes.firstIndex(where: { $0.id == item.id }) else { return }
        shoes[index].retiredAt = Date()
        if defaultShoeID == item.id { defaultShoeID = activeShoes.first?.id }
        persist()
    }

    func setDefault(_ item: GearItem) {
        defaultShoeID = item.id
    }

    func attachment(for item: GearItem?) -> ActivityGearAttachment? {
        guard let item else { return nil }
        return ActivityGearAttachment(shoeID: item.id, shoeName: item.displayName)
    }

    func mileageSummaries(from activities: [SavedActivity]) -> [GearMileageSummary] {
        shoes.map { item in
            let matchingActivities = activities.filter { $0.gear?.shoeID == item.id }
            return GearMileageSummary(
                item: item,
                distanceMeters: matchingActivities.reduce(0) { $0 + max(0, $1.distanceM) },
                lastUsedAt: matchingActivities.map(\.startedAt).max()
            )
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(shoes) else { return }
        defaults.set(data, forKey: shoesKey)
    }

    private static func loadShoes(defaults: UserDefaults, key: String) -> [GearItem] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([GearItem].self, from: data) else {
            return []
        }
        return decoded
    }
}
