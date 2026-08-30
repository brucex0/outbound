import Foundation

enum MeasurementUnitSystem: String, CaseIterable, Codable, Identifiable {
    case metric
    case imperial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metric: return String(localized: "measurement.system.metric", defaultValue: "Metric (km)")
        case .imperial: return String(localized: "measurement.system.imperial", defaultValue: "Imperial (mi)")
        }
    }

    static func deviceDefault(locale: Locale = .autoupdatingCurrent) -> MeasurementUnitSystem {
        switch locale.measurementSystem {
        case .us, .uk:
            return .imperial
        default:
            return .metric
        }
    }

    var distanceUnit: String {
        switch self {
        case .metric: return "km"
        case .imperial: return "mi"
        }
    }

    var distanceLabel: String {
        String(
            format: String(localized: "measurement.distance.label.format", defaultValue: "Dist (%@)"),
            locale: Locale.autoupdatingCurrent,
            distanceUnit
        )
    }

    var elevationUnit: String {
        switch self {
        case .metric: return "m"
        case .imperial: return "ft"
        }
    }

    var elevationLabel: String {
        String(
            format: String(localized: "measurement.elevation.label.format", defaultValue: "Elev (%@)"),
            locale: Locale.autoupdatingCurrent,
            elevationUnit
        )
    }

    var paceUnitSuffix: String {
        switch self {
        case .metric: return "/km"
        case .imperial: return "/mi"
        }
    }

    func distanceValue(meters: Double) -> Double {
        switch self {
        case .metric:
            return meters / 1000
        case .imperial:
            return meters / 1609.344
        }
    }

    func distanceMeters(from value: Double) -> Double {
        switch self {
        case .metric:
            return value * 1000
        case .imperial:
            return value * 1609.344
        }
    }

    func distanceValueString(meters: Double, fractionDigits: Int = 2) -> String {
        decimalString(distanceValue(meters: meters), fractionDigits: fractionDigits)
    }

    func distanceString(meters: Double, fractionDigits: Int = 2) -> String {
        "\(distanceValueString(meters: meters, fractionDigits: fractionDigits)) \(distanceUnit)"
    }

    func paceString(secondsPerKilometer: Double) -> String {
        let preferredUnitSeconds: Double
        switch self {
        case .metric:
            preferredUnitSeconds = secondsPerKilometer
        case .imperial:
            preferredUnitSeconds = secondsPerKilometer * 1.609344
        }
        return preferredUnitSeconds.paceString(unitSuffix: paceUnitSuffix)
    }

    func elevationValue(meters: Double) -> Double {
        switch self {
        case .metric:
            return meters
        case .imperial:
            return meters * 3.28084
        }
    }

    func elevationValueString(meters: Double) -> String {
        decimalString(elevationValue(meters: meters), fractionDigits: 0)
    }

    func elevationString(meters: Double) -> String {
        "\(elevationValueString(meters: meters)) \(elevationUnit)"
    }

    func spokenDistanceString(meters: Double, language: AppLanguage = .current) -> String {
        let clampedMeters = max(0, meters)
        switch self {
        case .metric:
            if clampedMeters < 995 {
                let value = Int(clampedMeters.rounded())
                switch language {
                case .english: return value == 1 ? "1 meter" : "\(value) meters"
                case .spanish: return value == 1 ? "1 metro" : "\(value) metros"
                case .simplifiedChinese: return "\(value) 米"
                }
            }
            return spokenLongDistance(
                value: clampedMeters / 1_000,
                singular: ("kilometer", "kilómetro", "公里"),
                plural: ("kilometers", "kilómetros", "公里"),
                language: language
            )
        case .imperial:
            let feet = clampedMeters * 3.28084
            if clampedMeters < 160.9344 {
                let value = Int(feet.rounded())
                switch language {
                case .english: return value == 1 ? "1 foot" : "\(value) feet"
                case .spanish: return value == 1 ? "1 pie" : "\(value) pies"
                case .simplifiedChinese: return "\(value) 英尺"
                }
            }
            return spokenLongDistance(
                value: clampedMeters / 1_609.344,
                singular: ("mile", "milla", "英里"),
                plural: ("miles", "millas", "英里"),
                language: language
            )
        }
    }

    func spokenPaceString(secondsPerKilometer: Double, language: AppLanguage = .current) -> String {
        let secondsPerUnit = self == .metric
            ? secondsPerKilometer
            : secondsPerKilometer * 1.609344
        let minutes = Int(secondsPerUnit) / 60
        let seconds = Int(secondsPerUnit) % 60
        switch (language, self) {
        case (.english, .metric):
            return "\(minutes) \(minutes == 1 ? "minute" : "minutes") \(seconds) \(seconds == 1 ? "second" : "seconds") per kilometer"
        case (.english, .imperial):
            return "\(minutes) \(minutes == 1 ? "minute" : "minutes") \(seconds) \(seconds == 1 ? "second" : "seconds") per mile"
        case (.spanish, .metric):
            return "\(minutes) \(minutes == 1 ? "minuto" : "minutos") \(seconds) \(seconds == 1 ? "segundo" : "segundos") por kilómetro"
        case (.spanish, .imperial):
            return "\(minutes) \(minutes == 1 ? "minuto" : "minutos") \(seconds) \(seconds == 1 ? "segundo" : "segundos") por milla"
        case (.simplifiedChinese, .metric):
            return "每公里 \(minutes) 分 \(seconds) 秒"
        case (.simplifiedChinese, .imperial):
            return "每英里 \(minutes) 分 \(seconds) 秒"
        }
    }

    private func spokenLongDistance(
        value: Double,
        singular: (String, String, String),
        plural: (String, String, String),
        language: AppLanguage
    ) -> String {
        let roundedHundredths = (value * 100).rounded() / 100
        let roundedWhole = roundedHundredths.rounded()
        let isWhole = abs(roundedHundredths - roundedWhole) < 0.005
        let valueText = isWhole
            ? String(Int(roundedWhole))
            : roundedHundredths.formatted(.number.locale(.autoupdatingCurrent).precision(.fractionLength(0...2)))
        let isSingular = isWhole && Int(roundedWhole) == 1
        switch language {
        case .english: return "\(valueText) \(isSingular ? singular.0 : plural.0)"
        case .spanish: return "\(valueText) \(isSingular ? singular.1 : plural.1)"
        case .simplifiedChinese: return "\(valueText) \(singular.2)"
        }
    }

    private func decimalString(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(
            .number
                .locale(Locale.autoupdatingCurrent)
                .precision(.fractionLength(fractionDigits))
                .grouping(.automatic)
        )
    }
}

enum TemperatureUnit: String, CaseIterable, Codable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }

    var title: String {
        switch self {
        case .celsius:
            String(localized: "measurement.temperature.celsius", defaultValue: "Celsius (°C)")
        case .fahrenheit:
            String(localized: "measurement.temperature.fahrenheit", defaultValue: "Fahrenheit (°F)")
        }
    }

    static func deviceDefault(locale: Locale = .autoupdatingCurrent) -> TemperatureUnit {
        locale.measurementSystem == .us ? .fahrenheit : .celsius
    }
}

extension Double {
    var paceString: String {
        paceString(unitSuffix: "/km")
    }

    func paceString(for unitSystem: MeasurementUnitSystem) -> String {
        unitSystem.paceString(secondsPerKilometer: self)
    }

    fileprivate func paceString(unitSuffix: String) -> String {
        guard isFinite, self > 0 else { return "--" }
        let totalSeconds = Int(self)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d %@", minutes, seconds, unitSuffix)
    }

}

extension String {
    func correctingPrematureCurrentDistanceClaims(
        currentDistanceMeters: Double,
        unitSystem: MeasurementUnitSystem = .metric
    ) -> String {
        let currentMeters = max(0, currentDistanceMeters)
        var corrected = self

        let numericPatterns: [(pattern: String, multiplier: Double)] = [
            (#"\b([0-9]+(?:\.[0-9]+)?)\s*(?:km|k|kilometer|kilometers)\s+(in|done|covered|complete|completed)\b"#, 1_000),
            (#"\b([0-9]+(?:\.[0-9]+)?)\s*(?:mi|mile|miles)\s+(in|done|covered|complete|completed)\b"#, 1_609.344)
        ]

        for numericPattern in numericPatterns {
            corrected = corrected.replacingCurrentDistanceClaims(
                matching: numericPattern.pattern
            ) { match in
                guard let valueRange = Range(match.range(at: 1), in: corrected),
                      let suffixRange = Range(match.range(at: 2), in: corrected),
                      let value = Double(corrected[valueRange])
                else {
                    return nil
                }

                let claimedMeters = value * numericPattern.multiplier
                guard claimedMeters > currentMeters + 25 else { return nil }
                return "\(unitSystem.spokenDistanceString(meters: currentMeters)) \(corrected[suffixRange])"
            }
        }

        let wordPatterns: [String] = [
            #"\b(?:one|a)\s+(?:km|k|kilometer|kilometre)\s+(in|done|covered|complete|completed)\b"#,
            #"\bjust\s+over\s+(?:one|a)\s+(?:km|k|kilometer|kilometre)\s+(in|done|covered|complete|completed)\b"#,
            #"\bover\s+(?:one|a)\s+(?:km|k|kilometer|kilometre)\s+(in|done|covered|complete|completed)\b"#
        ]

        for pattern in wordPatterns where currentMeters < 1_000 {
            corrected = corrected.replacingCurrentDistanceClaims(
                matching: pattern
            ) { match in
                guard let suffixRange = Range(match.range(at: 1), in: corrected) else {
                    return nil
                }
                return "\(unitSystem.spokenDistanceString(meters: currentMeters)) \(corrected[suffixRange])"
            }
        }

        return corrected
    }

    private func replacingCurrentDistanceClaims(
        matching pattern: String,
        replacement: (NSTextCheckingResult) -> String?
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return self
        }

        var result = self
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        for match in regex.matches(in: result, range: range).reversed() {
            guard let replacementText = replacement(match),
                  let matchRange = Range(match.range, in: result)
            else {
                continue
            }
            result.replaceSubrange(matchRange, with: replacementText)
        }
        return result
    }
}

extension Int {
    func formatted() -> String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }

    var spokenDurationString: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60
        if AppLanguage.current == .simplifiedChinese {
            var result = ""
            if hours > 0 { result += "\(hours) 小时" }
            if minutes > 0 { result += "\(minutes) 分钟" }
            if result.isEmpty || (seconds > 0 && hours == 0) { result += "\(seconds) 秒" }
            return result
        }

        let spanish = AppLanguage.current == .spanish
        var parts: [String] = []

        if hours > 0 {
            parts.append("\(hours) \(spanish ? (hours == 1 ? "hora" : "horas") : (hours == 1 ? "hour" : "hours"))")
        }

        if minutes > 0 {
            parts.append("\(minutes) \(spanish ? (minutes == 1 ? "minuto" : "minutos") : (minutes == 1 ? "minute" : "minutes"))")
        }

        if parts.isEmpty || (seconds > 0 && hours == 0) {
            parts.append("\(seconds) \(spanish ? (seconds == 1 ? "segundo" : "segundos") : (seconds == 1 ? "second" : "seconds"))")
        }

        return parts.joined(separator: " ")
    }

    var conversationalDurationString: String {
        switch self {
        case ..<60:
            return "\(self) \(self == 1 ? "second" : "seconds") in"
        case ..<3600:
            let minutes = self / 60
            let seconds = self % 60
            if seconds == 0 {
                return "\(minutes) \(minutes == 1 ? "minute" : "minutes") in"
            }
            return "\(minutes) \(minutes == 1 ? "minute" : "minutes") \(seconds) \(seconds == 1 ? "second" : "seconds") in"
        default:
            let hours = self / 3600
            let minutes = (self % 3600) / 60
            if minutes == 0 {
                return "\(hours) \(hours == 1 ? "hour" : "hours") in"
            }
            return "\(hours) \(hours == 1 ? "hour" : "hours") \(minutes) \(minutes == 1 ? "minute" : "minutes") in"
        }
    }
}
