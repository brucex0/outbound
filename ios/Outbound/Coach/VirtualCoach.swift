import Foundation
import AVFoundation

// On-device real-time coach — speaks periodic nudges during a run using
// Apple Foundation Models (iOS 18+) with the downloaded CoachProfile as context.
@MainActor
final class VirtualCoach: ObservableObject {
    @Published var lastNudge: String = ""

    private let synthesizer = AVSpeechSynthesizer()
    private var profile: CoachProfile?
    private var nudgeTimer: Timer?
    private let nudgeIntervalSecs: TimeInterval = 120  // every 2 mins

    func activate(with profile: CoachProfile) {
        self.profile = profile
        scheduleNudges()
    }

    func deactivate() {
        nudgeTimer?.invalidate()
        nudgeTimer = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    func nudge(elapsedSecs: Int, distanceKm: Double, paceSecs: Double?) {
        let message = buildNudge(elapsedSecs: elapsedSecs, distanceKm: distanceKm, paceSecs: paceSecs)
        speak(message)
        lastNudge = message
    }

    // MARK: - Private

    private func scheduleNudges() {
        nudgeTimer = Timer.scheduledTimer(withTimeInterval: nudgeIntervalSecs, repeats: true) { _ in
            // RecordView observes this and passes current stats
            NotificationCenter.default.post(name: .coachNudgeRequested, object: nil)
        }
    }

    private func buildNudge(elapsedSecs: Int, distanceKm: Double, paceSecs: Double?) -> String {
        let mins = elapsedSecs / 60
        let distStr = String(format: "%.1f", distanceKm)

        var parts: [String] = ["\(mins) minutes in, \(distStr) k done."]

        if let pace = paceSecs {
            let paceMin = Int(pace) / 60
            let paceSec = Int(pace) % 60
            parts.append("Current pace \(paceMin):\(String(format: "%02d", paceSec)) per k.")

            if let target = profile?.athlete.preferredPaceSecs {
                let diff = pace - target
                if diff > 15 {
                    parts.append("You're a bit slow. \(profile?.coachName ?? "Coach") says push it.")
                } else if diff < -15 {
                    parts.append("Easy. Don't burn out early.")
                } else {
                    parts.append("Perfect pace. Keep it locked.")
                }
            }
        }

        if let insight = profile?.memorySnapshot.recentInsight, !insight.isEmpty {
            parts.append(insight)
        }

        return parts.joined(separator: " ")
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.volume = 0.9
        synthesizer.speak(utterance)
    }
}

extension Notification.Name {
    static let coachNudgeRequested = Notification.Name("coachNudgeRequested")
}
