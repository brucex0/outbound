import SwiftUI

/// Coarse surfaces only: never report a field label, identifier, value, or query.
enum InputSubmissionSurface: String {
    case onboarding, profile, shoes, rewards, comments, routes, groups, people
    case activityEntry = "activity_entry"
    case activityEdit = "activity_edit"
    case activityEvent = "activity_event"
    case routePublish = "route_publish"
}

private struct InputSubmissionAnalytics: ViewModifier {
    @Environment(\.analyticsManager) private var analyticsManager
    let surface: InputSubmissionSurface

    func body(content: Content) -> some View {
        content.onSubmit {
            Task {
                await analyticsManager?.track(.init(.inputSubmitted, properties: [
                    .sourceType: .string(surface.rawValue)
                ]))
            }
        }
    }
}

extension View {
    /// Apply to an individual field, never an ancestor form or navigation container.
    /// Observes native submission without changing focus or multiline Return behavior.
    func inputSubmissionAnalytics(_ surface: InputSubmissionSurface) -> some View {
        modifier(InputSubmissionAnalytics(surface: surface))
    }
}
