import Foundation

extension Double {
    var paceString: String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    var spokenPaceString: String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes") \(seconds) \(seconds == 1 ? "second" : "seconds") per kilometer"
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
}
