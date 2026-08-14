import Combine
import Foundation

enum CycleTrainingSignal: String, Codable, CaseIterable {
    case noAdjustment
    case offerFlexibleOption
    case reduceLoad
    case recommendRest

    var title: String {
        switch self {
        case .noAdjustment: String(localized: "No change needed")
        case .offerFlexibleOption: String(localized: "Offer flexibility")
        case .reduceLoad: String(localized: "Gentler workout suggested")
        case .recommendRest: String(localized: "Rest suggested")
        }
    }
}

struct CycleWellbeingLog: Codable, Identifiable {
    let id: UUID
    let date: Date
    let bleeding: Bool
    let energy: Int
    let discomfort: Int
}

@MainActor
final class CycleAwareStore: ObservableObject {
    @Published var isEnabled: Bool { didSet { persist() } }
    @Published private(set) var logs: [CycleWellbeingLog]
    private let defaults: UserDefaults
    private let api = APIClient.shared
    private let key = "private_cycle_wellbeing_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let state = try? JSONDecoder().decode(State.self, from: data) {
            isEnabled = state.isEnabled
            logs = state.logs
        } else {
            isEnabled = false
            logs = []
        }
    }

    var currentSignal: CycleTrainingSignal {
        guard isEnabled, let latest = logs.first else { return .noAdjustment }
        if latest.discomfort >= 4 || latest.energy == 1 { return .recommendRest }
        if latest.discomfort >= 3 || latest.energy == 2 { return .reduceLoad }
        if latest.bleeding || latest.energy == 3 { return .offerFlexibleOption }
        return .noAdjustment
    }

    var summary: String { isEnabled ? currentSignal.title : String(localized: "Cycle-aware coaching is off") }

    func log(bleeding: Bool, energy: Int, discomfort: Int) {
        logs.insert(CycleWellbeingLog(id: UUID(), date: Date(), bleeding: bleeding, energy: energy, discomfort: discomfort), at: 0)
        logs = Array(logs.prefix(90))
        persist()
        let signal = currentSignal
        Task {
            _ = try? await api.submitCycleTrainingSignal(
                CycleTrainingSignalRequestDTO(
                    signal: signal,
                    workoutId: nil,
                    day: Date.formattedCycleDay,
                    idempotencyKey: "\(Date.formattedCycleDay)-\(signal.rawValue)"
                )
            )
        }
    }

    func clear() {
        logs = []
        isEnabled = false
        defaults.removeObject(forKey: key)
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(State(isEnabled: isEnabled, logs: logs)), forKey: key)
    }

    private struct State: Codable { let isEnabled: Bool; let logs: [CycleWellbeingLog] }
}

struct CycleTrainingSignalRequestDTO: Codable {
    let signal: CycleTrainingSignal
    let workoutId: String?
    let day: String
    let idempotencyKey: String
}

struct CycleTrainingSignalResponseDTO: Codable {
    let workoutId: String?
    let day: String
    let signal: CycleTrainingSignal
    let action: String
    let explanation: String
    let rawHealthDataStored: Bool
}

private extension Date {
    static var formattedCycleDay: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
