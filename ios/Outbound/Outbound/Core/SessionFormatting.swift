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
}
