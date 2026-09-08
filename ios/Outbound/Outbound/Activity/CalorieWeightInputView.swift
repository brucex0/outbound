import SwiftUI

struct CalorieWeightInputView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @State private var weightText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(weightLabel, text: $weightText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text(String(localized: "activity.calories.weight.title", defaultValue: "Weight"))
                } footer: {
                    Text(String(
                        localized: "activity.calories.weight.footer",
                        defaultValue: "Your weight is private and helps Plainstride calculate calories for your activities."
                    ))
                }
            }
            .navigationTitle(String(localized: "activity.calories.add_weight", defaultValue: "Add Weight"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel", defaultValue: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save", defaultValue: "Save")) {
                        saveWeight()
                    }
                    .disabled(parsedWeightKilograms == nil || isSaving)
                }
            }
            .overlay(alignment: .top) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(radius: 8)
                        .padding(.top, 8)
                }
            }
        }
    }

    private var usesMetric: Bool { measurementPreferences.unitSystem == .metric }

    private var weightLabel: String {
        usesMetric ? String(localized: "Weight (kg)") : String(localized: "Weight (lb)")
    }

    private var parsedWeightKilograms: Double? {
        guard let value = Double(
            weightText.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
        ) else { return nil }
        let kilograms = usesMetric ? value : value * 0.45359237
        return (25...350).contains(kilograms) ? kilograms : nil
    }

    private func saveWeight() {
        guard let weightKilograms = parsedWeightKilograms else { return }
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let current = try await APIClient.shared.fetchTrainingProfile()
                let updated = try await APIClient.shared.updateTrainingProfile(
                    TrainingProfileUpdateDTO(
                        sexAtBirth: current.sexAtBirth,
                        birthDate: current.birthDate,
                        heightCentimeters: current.heightCentimeters,
                        weightKilograms: weightKilograms,
                        primaryMotivation: current.primaryMotivation,
                        preferredRunGoalType: current.preferredRunGoalType
                    )
                )
                onboardingStore.applyTrainingProfile(updated)
                await analyticsManager?.track(.init(.preferenceChanged, properties: [
                    .changeType: .string("body_weight"),
                    .selectionType: .string("post_run_calories"),
                ]))
                dismiss()
            } catch {
                isSaving = false
                errorMessage = String(
                    localized: "record.goal.calories.weight_prompt.save_failed",
                    defaultValue: "Couldn’t save your weight. Try again."
                )
            }
        }
    }
}
