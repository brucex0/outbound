import Combine
import SwiftUI
import UIKit

/// Retains one hosting controller for an opening. Parent SwiftUI updates never
/// replace its root view or restart the catalog's StateObject/task.
@MainActor
final class StandaloneWorkoutPresenter: NSObject, UIAdaptivePresentationControllerDelegate {
    private weak var anchor: UIViewController?
    private var appearance: StandaloneWorkoutPresentationAppearance?
    private var controller: UIViewController?

    fileprivate func attach(to anchor: UIViewController, values: StandaloneWorkoutPresentationAppearance.Values) {
        self.anchor = anchor
        if let appearance {
            guard appearance.values != values else { return }
            // A real theme/accessibility change can update the open picker,
            // without publishing during UIViewControllerRepresentable updates.
            Task { @MainActor [weak appearance] in
                if appearance?.values != values { appearance?.values = values }
            }
        } else {
            appearance = StandaloneWorkoutPresentationAppearance(values: values)
        }
    }

    func present(sport: SportType, onSelect: @escaping (StandaloneWorkout) -> Void) {
        guard controller == nil else { return }
        guard let root = anchor?.viewIfLoaded?.window?.rootViewController,
              let appearance else {
            ActivityDiagnosticLog.error(.lifecycle, "curated_picker_present_failed reason=missing_visible_anchor")
            return
        }
        var presenting = root
        while let presented = presenting.presentedViewController { presenting = presented }
        guard !presenting.isBeingDismissed else {
            ActivityDiagnosticLog.error(.lifecycle, "curated_picker_present_failed reason=presenter_dismissing")
            return
        }
        let content = StandaloneWorkoutPresentedView(
            appearance: appearance, sport: sport,
            onClose: { [weak self] in self?.dismiss() },
            onSelect: { [weak self] workout in
                self?.dismiss { onSelect(workout) }
            }
        )
        let hosting = UIHostingController(rootView: content)
        hosting.modalPresentationStyle = .pageSheet
        hosting.sheetPresentationController?.detents = [.large()]
        hosting.presentationController?.delegate = self
        controller = hosting
        presenting.present(hosting, animated: true)
    }

    private func dismiss(completion: (() -> Void)? = nil) {
        guard let controller, !controller.isBeingDismissed else { return }
        controller.dismiss(animated: true) { [weak self] in
            self?.controller = nil
            completion?()
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        controller = nil
    }
}

@MainActor
fileprivate final class StandaloneWorkoutPresentationAppearance: ObservableObject {
    struct Values: Equatable {
        let theme: OutboundTheme
        let colorScheme: ColorScheme
        let dynamicTypeSize: DynamicTypeSize
        let locale: Locale
        let layoutDirection: LayoutDirection

        init(_ environment: EnvironmentValues) {
            theme = environment.outboundTheme
            colorScheme = environment.colorScheme
            dynamicTypeSize = environment.dynamicTypeSize
            locale = environment.locale
            layoutDirection = environment.layoutDirection
        }
    }

    @Published var values: Values

    init(values: Values) { self.values = values }
}

private struct StandaloneWorkoutPresentedView: View {
    @ObservedObject var appearance: StandaloneWorkoutPresentationAppearance
    let sport: SportType
    let onClose: () -> Void
    let onSelect: (StandaloneWorkout) -> Void

    var body: some View {
        StandaloneWorkoutPickerView(sport: sport, onClose: onClose, onSelect: onSelect)
            .environment(\.outboundTheme, appearance.values.theme)
            .environment(\.dynamicTypeSize, appearance.values.dynamicTypeSize)
            .environment(\.locale, appearance.values.locale)
            .environment(\.layoutDirection, appearance.values.layoutDirection)
            .preferredColorScheme(appearance.values.colorScheme)
            .tint(appearance.values.theme.accentColor)
    }
}

/// Supplies a window in this scene; it does not own the presented controller.
/// Even if this SwiftUI anchor remounts, UIKit retains the open picker.
struct StandaloneWorkoutPresentationHost: UIViewControllerRepresentable {
    let presenter: StandaloneWorkoutPresenter

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        controller.view.accessibilityElementsHidden = true
        presenter.attach(to: controller, values: .init(context.environment))
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        presenter.attach(to: uiViewController, values: .init(context.environment))
    }
}
