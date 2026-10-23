#if DEBUG
import StoreKit
import SwiftUI

/// Manual StoreKit exercise; deliberately leaves production eligibility untouched.
struct DebugAppReviewView: View {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.analyticsManager) private var analyticsManager

    var body: some View {
        Form {
            Section {
                Button(String(localized: "request", table: "AppReviewDebug")) {
                    requestReview()
                    Task {
                        await analyticsManager?.track(.init(.featureExposed, properties: [
                            .feature: .string("debug_app_review_request")
                        ]))
                    }
                }
                .disabled(scenePhase != .active)
                .accessibilityIdentifier("DebugAppReviewRequestButton")
            } footer: {
                Text(String(localized: "explanation", table: "AppReviewDebug"))
            }
        }
        .navigationTitle(String(localized: "title", table: "AppReviewDebug"))
    }
}
#endif
