import Foundation

enum MeasurementUnitSystem: String, CaseIterable, Codable, Identifiable {
    case metric
    case imperial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metric: return "Metric"
        case .imperial: return "Imperial"
        }
    }

    var distanceUnit: String {
        switch self {
        case .metric: return "km"
        case .imperial: return "mi"
        }
    }

    var distanceLabel: String {
        "Dist (\(distanceUnit))"
    }

    var elevationUnit: String {
        switch self {
        case .metric: return "m"
        case .imperial: return "ft"
        }
    }

    var elevationLabel: String {
        "Elev (\(elevationUnit))"
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

    private func decimalString(_ value: Double, fractionDigits: Int) -> String {
        let format = "%.\(fractionDigits)f"
        return String(format: format, value)
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

    var spokenPaceString: String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes") \(seconds) \(seconds == 1 ? "second" : "seconds") per kilometer"
    }

    var spokenDistanceString: String {
        let distanceMeters = max(0, self)
        let meters = Int(distanceMeters.rounded())

        if distanceMeters < 995 {
            return meters == 1 ? "1 meter" : "\(meters) meters"
        }

        let roundedHundredths = ((distanceMeters / 1000) * 100).rounded() / 100
        let roundedWhole = roundedHundredths.rounded()
        if abs(roundedHundredths - roundedWhole) < 0.005 {
            let wholeKilometers = Int(roundedWhole)
            return wholeKilometers == 1 ? "1 kilometer" : "\(wholeKilometers) kilometers"
        }

        return String(format: "%.2f kilometers", roundedHundredths)
    }
}

extension String {
    func correctingPrematureCurrentDistanceClaims(currentDistanceMeters: Double) -> String {
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
                return "\(currentMeters.spokenDistanceString) \(corrected[suffixRange])"
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
                return "\(currentMeters.spokenDistanceString) \(corrected[suffixRange])"
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
        var parts: [String] = []

        if hours > 0 {
            parts.append("\(hours) \(hours == 1 ? "hour" : "hours")")
        }

        if minutes > 0 {
            parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")")
        }

        if parts.isEmpty || (seconds > 0 && hours == 0) {
            parts.append("\(seconds) \(seconds == 1 ? "second" : "seconds")")
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
