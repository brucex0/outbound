import SwiftUI
import OSLog

struct GroupMomentResultsView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    let eventID: String
    @State private var results: ActivityEventResultDTO?
    @State private var isLoading = true
    @State private var failed = false
    private static let logger = Logger(subsystem: "plainstride.outbound", category: "GroupMomentResults")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text(String(localized: "group.moment.results", defaultValue: "Participation results"))
                .font(.headline)
            if isLoading {
                ProgressView()
            } else if failed {
                Text(String(localized: "group.moment.results.failed", defaultValue: "Could not load participation results."))
                    .font(.subheadline).foregroundStyle(.secondary)
                Button(String(localized: "group.moment.results.retry", defaultValue: "Try again")) {
                    Task { await load() }
                }
            } else if let results {
                if results.status == "reconciling" {
                    Text(String(localized: "Collecting participant results"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if results.participants.isEmpty {
                    Text(String(localized: "group.moment.results.empty", defaultValue: "No participation results yet."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(results.participants) { participant in
                    HStack(alignment: .top, spacing: 10) {
                        SocialAvatar(name: participant.person.displayName, avatarURL: participant.person.avatarUrl)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(participant.person.displayName).font(.subheadline.weight(.semibold))
                            Text(resultLabel(participant)).font(.caption).foregroundStyle(.secondary)
                            if let photos = participant.result?.photos, !photos.isEmpty {
                                ScrollView(.horizontal) {
                                    HStack(spacing: 8) {
                                        ForEach(photos, id: \.id) { photo in
                                            if let url = photo.thumbnailUrl ?? photo.url {
                                                LocalImageView(url: APIClient.shared.mediaURL(url), maxPixelSize: 720) {
                                                    Image(systemName: "photo").foregroundStyle(.secondary)
                                                }
                                                .frame(width: 132, height: 100)
                                                .clipped()
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .accessibilityLabel(String(localized: "Activity photo preview"))
                                            }
                                        }
                                    }
                                }
                            }
                            if let duration = participant.result?.durationSecs {
                                Text(Duration.seconds(duration).formatted(.time(pattern: .hourMinuteSecond)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .task(id: eventID) { await load() }
    }

    private func resultLabel(_ participant: ActivityEventResultParticipantDTO) -> String {
        if let result = participant.result {
            if let distance = result.distanceM {
                return String(localized: "Completed · \(measurementPreferences.unitSystem.distanceString(meters: distance, fractionDigits: 1))")
            }
            return String(localized: "group.activity.finished")
        }
        switch participant.outcome {
        case "completed": return String(localized: "group.activity.finished")
        case "no_recording": return String(localized: "Finished · No activity saved")
        case "did_not_participate": return String(localized: "Couldn't participate")
        default: return String(localized: "Waiting for result")
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        failed = false
        defer { isLoading = false }
        do {
            results = try await APIClient.shared.fetchActivityEventResults(id: eventID)
            await analyticsManager?.track(.init(.groupMomentResultsLoaded, properties: [
                .result: .string("success"),
                .countBucket: .string(ProductAnalyticsBucket.count(results?.participants.count ?? 0))
            ]))
        } catch is CancellationError {
            // Navigation cancellation is expected and does not need error feedback.
        } catch {
            if (error as NSError).code == NSURLErrorCancelled { return }
            failed = true
            if case let APIError.http(status, _, _) = error {
                Self.logger.error("Load moment participation results failed (HTTP \(status, privacy: .public))")
            } else {
                Self.logger.error("Load moment participation results failed (code \((error as NSError).code, privacy: .public))")
            }
            await analyticsManager?.track(.init(.groupMomentResultsLoaded, properties: [.result: .string("failure")]))
        }
    }
}
