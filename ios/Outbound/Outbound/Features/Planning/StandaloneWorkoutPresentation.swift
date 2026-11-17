import SwiftUI

/// The flow owns this adapter; the shared presenter retains one root per opening.
@MainActor
final class StandaloneWorkoutPresenter {
    let sheet = StableSheetPresenter()

    func present(sport: SportType, onSelect: @escaping (StandaloneWorkout) -> Void) {
        sheet.present(diagnosticName: "curated_picker") { dismiss in
            StandaloneWorkoutPickerView(sport: sport, onClose: { dismiss() }) { workout in
                dismiss(completion: { onSelect(workout) })
            }
        }
    }
}
