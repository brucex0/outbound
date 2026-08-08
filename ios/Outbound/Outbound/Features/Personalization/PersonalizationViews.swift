import SwiftUI

struct CalibrationProgressBanner: View {
    let summary: CalibrationSummaryDTO

    var body: some View {
        HStack(spacing: OutboundSpacing.compact) {
            Image(systemName: "sparkles")
                .foregroundStyle(OutboundPalette.companion)
            VStack(alignment: .leading, spacing: 2) {
                Text("Getting to know your running")
                    .font(.subheadline.weight(.semibold))
                Text("Run \(nextSessionNumber) of \(summary.targetSessionCount) · normal training, not a test")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var nextSessionNumber: Int {
        min(summary.completedSessionCount + 1, summary.targetSessionCount)
    }
}

struct ReadinessCheckInView: View {
    let workoutTitle: String
    let onContinue: (ReadinessChoice?) -> Void
    @State private var selection: ReadinessChoice?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                    Text("How are you arriving today?")
                        .font(.title2.weight(.semibold))
                    Text("One tap helps your companion fit \(workoutTitle.lowercased()) to today.")
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: OutboundSpacing.compact) {
                        ForEach(ReadinessChoice.allCases) { choice in
                            Button {
                                selection = choice
                            } label: {
                                Label(choice.title, systemImage: choice.systemImage)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.bordered)
                            .tint(selection == choice ? OutboundPalette.companion : .secondary)
                            .accessibilityAddTraits(selection == choice ? .isSelected : [])
                        }
                    }

                    AIExplanationView(text: explanation)

                    OutboundPrimaryButton(title: "Continue to workout", systemImage: "figure.run") {
                        onContinue(selection)
                    }

                    Button("Skip check-in") {
                        onContinue(nil)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(OutboundSpacing.screen)
            }
            .background(OutboundPalette.background)
            .navigationTitle("Before you run")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private var explanation: String {
        switch selection {
        case .tired:
            "If this is more than ordinary tiredness, Outbound can offer a shorter easy option before you start."
        case .sore:
            "Soreness can change today's recommendation. Pain should not be treated as a training signal to push through."
        case .shortOnTime:
            "Outbound can preserve the purpose of this run in a shorter version."
        case .good, .none:
            "Your recent load supports the planned easy run. Nothing changes unless you want it to."
        }
    }
}

private extension ReadinessChoice {
    var title: String {
        switch self {
        case .good: "Good"
        case .tired: "Tired"
        case .sore: "Sore"
        case .shortOnTime: "Short on time"
        }
    }

    var systemImage: String {
        switch self {
        case .good: "sun.max"
        case .tired: "moon.zzz"
        case .sore: "bandage"
        case .shortOnTime: "clock"
        }
    }
}
