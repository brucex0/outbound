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
            "If this is more than ordinary tiredness, Plainstride can offer a shorter easy option before you start."
        case .sore:
            "Soreness can change today's recommendation. Pain should not be treated as a training signal to push through."
        case .shortOnTime:
            "Plainstride can preserve the purpose of this run in a shorter version."
        case .good, .none:
            "Your recent load supports the planned easy run. Nothing changes unless you want it to."
        }
    }
}

struct CompanionMemoryView: View {
    @State private var memories: [CompanionMemoryDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editingMemory: CompanionMemoryDTO?
    @State private var editedSummary = ""

    var body: some View {
        List {
            Section {
                Text("These are the facts and patterns Plainstride may use when adapting training. You can correct or forget any item.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if isLoading && memories.isEmpty {
                ProgressView("Loading your runner model…")
            } else if memories.isEmpty {
                ContentUnavailableView(
                    "Nothing learned yet",
                    systemImage: "sparkles",
                    description: Text("Complete your profile and a few runs to build a transparent runner model.")
                )
            } else {
                ForEach(memories) { memory in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(memory.label)
                                .font(.headline)
                            Spacer()
                            Text(memory.status == "confirmed" ? "Confirmed" : confidenceLabel(memory.confidence))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(memory.status == "confirmed" ? OutboundPalette.companion : .secondary)
                        }
                        Text(memory.summary)
                            .font(.subheadline)
                        Text(provenanceLine(memory))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Correct") {
                                editedSummary = memory.summary
                                editingMemory = memory
                            }
                            Button("Forget", role: .destructive) {
                                Task { await forget(memory) }
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("What Plainstride knows")
        .task { await refresh() }
        .refreshable { await refresh() }
        .sheet(item: $editingMemory) { memory in
            NavigationStack {
                Form {
                    Section(memory.label) {
                        TextField("What should Plainstride remember?", text: $editedSummary, axis: .vertical)
                            .lineLimit(2...6)
                    }
                    Section {
                        Text("Your correction becomes a confirmed fact and takes precedence over prior inferences.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Correct memory")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingMemory = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await correct(memory) } }
                            .disabled(editedSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            memories = try await APIClient.shared.fetchCompanionMemories().memories
            errorMessage = nil
        } catch {
            errorMessage = "Your runner model is unavailable right now."
        }
    }

    private func correct(_ memory: CompanionMemoryDTO) async {
        let summary = editedSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return }
        do {
            let corrected = try await APIClient.shared.correctCompanionMemory(stableKey: memory.stableKey, summary: summary, label: memory.label).memory
            memories = memories.map { $0.stableKey == corrected.stableKey ? corrected : $0 }
            editingMemory = nil
            errorMessage = nil
        } catch {
            errorMessage = "That correction could not be saved."
        }
    }

    private func forget(_ memory: CompanionMemoryDTO) async {
        do {
            let response = try await APIClient.shared.forgetCompanionMemory(stableKey: memory.stableKey)
            if response.forgotten { memories.removeAll { $0.stableKey == memory.stableKey } }
            errorMessage = nil
        } catch {
            errorMessage = "That memory could not be forgotten."
        }
    }

    private func confidenceLabel(_ confidence: Double) -> String {
        confidence >= 0.8 ? "High confidence" : confidence >= 0.55 ? "Medium confidence" : "Learning"
    }

    private func provenanceLine(_ memory: CompanionMemoryDTO) -> String {
        let source = memory.source == "runner" ? "You told Plainstride" : "Inferred from training"
        return "\(source) · \(memory.evidenceCount) evidence point\(memory.evidenceCount == 1 ? "" : "s")"
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
