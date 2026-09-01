import Foundation
import OSLog

enum ActivityDiagnosticCategory: String, CaseIterable {
    case lifecycle = "ActivityLifecycle"
    case persistence = "ActivityPersistence"
    case recovery = "ActivityRecovery"
    case sync = "ActivitySync"
    case healthKit = "HealthKit"
}

enum ActivityDiagnosticLog {
    private static let subsystem = "plainstride.outbound"
    private static let lifecycleLogger = Logger(subsystem: subsystem, category: ActivityDiagnosticCategory.lifecycle.rawValue)
    private static let persistenceLogger = Logger(subsystem: subsystem, category: ActivityDiagnosticCategory.persistence.rawValue)
    private static let recoveryLogger = Logger(subsystem: subsystem, category: ActivityDiagnosticCategory.recovery.rawValue)
    private static let syncLogger = Logger(subsystem: subsystem, category: ActivityDiagnosticCategory.sync.rawValue)
    private static let healthKitLogger = Logger(subsystem: subsystem, category: ActivityDiagnosticCategory.healthKit.rawValue)

    static func notice(_ category: ActivityDiagnosticCategory, _ message: String) {
        logger(for: category).notice("\(message, privacy: .public)")
    }

    static func error(_ category: ActivityDiagnosticCategory, _ message: String) {
        logger(for: category).error("\(message, privacy: .public)")
    }

    static func durationBucket(seconds: Int) -> String {
        switch max(0, seconds) {
        case 0..<60: "under_1_min"
        case 60..<300: "1_5_min"
        case 300..<900: "5_15_min"
        case 900..<1_800: "15_30_min"
        case 1_800..<3_600: "30_60_min"
        case 3_600..<7_200: "1_2_hours"
        default: "2_hours_plus"
        }
    }

    static func distanceBucket(meters: Double) -> String {
        switch max(0, meters) {
        case 0: "none"
        case 0..<1_000: "under_1_km"
        case 1_000..<5_000: "1_5_km"
        case 5_000..<10_000: "5_10_km"
        case 10_000..<21_100: "10_21_km"
        default: "21_km_plus"
        }
    }

    static func countBucket(_ count: Int) -> String {
        switch max(0, count) {
        case 0: "0"
        case 1: "1"
        case 2...5: "2_5"
        case 6...20: "6_20"
        case 21...100: "21_100"
        default: "101_plus"
        }
    }

    static func errorCategory(_ error: Error) -> String {
        if case let APIError.http(statusCode, _, _) = error {
            return "http_\(statusCode)"
        }
        if error is DecodingError {
            return "decoding"
        }
        if let urlError = error as? URLError {
            return urlError.code == .notConnectedToInternet ? "offline" : "network"
        }
        if let healthError = error as? HealthKitServiceError {
            switch healthError {
            case .unavailable: return "health_unavailable"
            case .requestFailed: return "health_request_failed"
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return "storage_\(nsError.code)"
        }
        return "unknown"
    }

    private static func logger(for category: ActivityDiagnosticCategory) -> Logger {
        switch category {
        case .lifecycle: lifecycleLogger
        case .persistence: persistenceLogger
        case .recovery: recoveryLogger
        case .sync: syncLogger
        case .healthKit: healthKitLogger
        }
    }
}
