import SwiftUI

/// Optional current planning decision, distinct from calendar weeks and race completion.
struct RunningProgrammeProgress: Codable, Equatable {
    struct SourceWeek: Codable, Equatable { let weekIndex: Int; let status: String }
    let programme: SourceWeek?
    let nominalSourceWeeks: Int?
    let minimumRemainingCalendarWeeks: Int?
    let minimumCalendarEstimateCondition: String?
    let programmeTimelineStatus: String?
    let programmeDoseStatus: String?
    let programmeReviewReason: String?
    let programmeReviewAction: String?
    let preparationOnly: Bool?
    let futureWeeksProvisional: Bool?
}

struct RunningProgrammeProgressView: View {
    let progress: RunningProgrammeProgress
    @Environment(\.analyticsManager) private var analytics

    private var needsReview: Bool { progress.programmeDoseStatus == "needs_review" || progress.programmeTimelineStatus == "needs_review" }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let source = progress.programme, let count = progress.nominalSourceWeeks {
                Text(String(format: String(localized: "planning.programme.source_week"), source.weekIndex, count))
                    .font(.subheadline.weight(.semibold))
                if source.status == "completed" {
                    Text(String(localized: "planning.programme.preparation_complete"))
                } else if needsReview {
                    Text(String(localized: progress.programmeDoseStatus != "needs_review" ? "planning.programme.timeline_review" : progress.programmeReviewReason == "conservative_recipe_fit" ? "planning.programme.recipe_review" : "planning.programme.schedule_review"))
                } else if let weeks = progress.minimumRemainingCalendarWeeks {
                    Text(String(format: String(localized: "planning.programme.minimum_remaining"), weeks))
                }
                Text(String(localized: "planning.programme.exposure_notice"))
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: needsReview) {
            if needsReview { await analytics?.track(.init(.featureExposed, properties: [.feature: .string("running_programme_review")])) }
        }
    }
}
