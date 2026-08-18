import Foundation

enum AnalyticsSanitizer {
    nonisolated static func eventName(_ value: String) -> String {
        identifier(value, maximumLength: 40, fallback: "app_event", reservedPrefixReplacement: "app_")
    }

    nonisolated static func parameterKey(_ value: String) -> String {
        identifier(value, maximumLength: 40, fallback: "parameter", reservedPrefixReplacement: "app_")
    }

    nonisolated static func userPropertyKey(_ value: String) -> String {
        identifier(value, maximumLength: 24, fallback: "property", reservedPrefixReplacement: "app_")
    }

    nonisolated static func screenName(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
    }

    nonisolated static func firebaseParameters(_ parameters: [String: Any]?) -> [String: Any]? {
        guard let parameters else { return nil }
        let sanitized = parameters.reduce(into: [String: Any]()) { result, pair in
            guard let value = firebaseValue(pair.value) else { return }
            result[parameterKey(pair.key)] = value
        }
        return sanitized.isEmpty ? nil : sanitized
    }

    private nonisolated static func identifier(
        _ value: String,
        maximumLength: Int,
        fallback: String,
        reservedPrefixReplacement: String
    ) -> String {
        let lowercase = value.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current).lowercased()
        var result = lowercase.unicodeScalars.reduce(into: "") { output, scalar in
            if CharacterSet.alphanumerics.contains(scalar) {
                output.unicodeScalars.append(scalar)
            } else if output.last != "_" {
                output.append("_")
            }
        }.trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        if result.isEmpty { result = fallback }
        if result.first?.isLetter != true { result = "app_\(result)" }
        if ["firebase_", "google_", "ga_"].contains(where: result.hasPrefix) {
            result = reservedPrefixReplacement + result
        }
        return String(result.prefix(maximumLength))
    }

    private nonisolated static func firebaseValue(_ value: Any) -> Any? {
        switch value {
        case let value as String: return String(value.prefix(100))
        case let value as Bool: return NSNumber(value: value)
        case let value as Int: return NSNumber(value: value)
        case let value as Int8: return NSNumber(value: value)
        case let value as Int16: return NSNumber(value: value)
        case let value as Int32: return NSNumber(value: value)
        case let value as Int64: return NSNumber(value: value)
        case let value as UInt: return NSNumber(value: value)
        case let value as UInt8: return NSNumber(value: value)
        case let value as UInt16: return NSNumber(value: value)
        case let value as UInt32: return NSNumber(value: value)
        case let value as UInt64: return NSNumber(value: value)
        case let value as Float: return NSNumber(value: value)
        case let value as Double: return NSNumber(value: value)
        case let value as Decimal: return NSDecimalNumber(decimal: value)
        case let value as Date: return ISO8601DateFormatter().string(from: value)
        case let value as URL: return String(value.absoluteString.prefix(100))
        case let value as NSNumber: return value
        default: return nil
        }
    }
}
