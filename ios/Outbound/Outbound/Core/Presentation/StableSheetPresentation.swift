import Combine
import SwiftUI
import UIKit

/// A close/selection action belongs to one opening, never a later sheet.
@MainActor
struct StableSheetDismissal {
    fileprivate let perform: ((() -> Void)?) -> Void
    func callAsFunction(completion: (() -> Void)? = nil) { perform(completion) }
}

/// One hosting root per opening, owned above transient buttons/layout candidates.
/// Attach refreshes appearance only; it never replaces a presented root view.
@MainActor
final class StableSheetPresenter: NSObject, UIAdaptivePresentationControllerDelegate {
    private weak var anchor: UIViewController?
    private var appearance: StableSheetAppearance?
    private var latestAppearanceValues: StableSheetAppearance.Values?
    private var controller: UIViewController?
    private var opening: UUID?
    private var afterDismiss: (() -> Void)?
    private var selectionCompletion: (() -> Void)?
    private var dismissRequested = false
    // Keep lifecycle/account observers alive even if the source scene is removed.
    // Every dismissal path releases this retention in finish(opening:).
    private var activeLifetime: StableSheetPresenter?

    fileprivate func attach(to anchor: UIViewController, values: StableSheetAppearance.Values) {
        self.anchor = anchor
        latestAppearanceValues = values
        if let appearance {
            guard appearance.values != values else { return }
            Task { @MainActor [weak self] in
                guard let self, let values = self.latestAppearanceValues else { return }
                // Defer observable publication out of the representable update,
                // but use its latest snapshot if another update arrived meanwhile.
                self.controller?.overrideUserInterfaceStyle = values.userInterfaceStyle
                if appearance.values != values { appearance.values = values }
            }
        } else { appearance = StableSheetAppearance(values: values) }
    }

    @discardableResult
    func present<Content: View>(diagnosticName: String, fullScreen: Bool = false, onPresented: @escaping () -> Void = {}, onDismiss: @escaping () -> Void = {},
                               content: (StableSheetDismissal) -> Content) -> Bool {
        guard controller == nil else { return false }
        guard let root = anchor?.viewIfLoaded?.window?.rootViewController, let appearance, let values = latestAppearanceValues else {
            ActivityDiagnosticLog.error(.lifecycle, "\(diagnosticName)_present_failed reason=missing_visible_anchor")
            return false
        }
        var presenting = root
        while let presented = presenting.presentedViewController { presenting = presented }
        guard !presenting.isBeingDismissed else {
            ActivityDiagnosticLog.error(.lifecycle, "\(diagnosticName)_present_failed reason=presenter_dismissing")
            return false
        }
        let id = UUID()
        let dismissal = StableSheetDismissal { [weak self] completion in
            guard let self, self.opening == id else { return }
            self.dismiss(completion: completion)
        }
        let view = content(dismissal)
        if appearance.values != values { appearance.values = values }
        let hosting = StableSheetHostingController(rootView: StableSheetContent(appearance: appearance, content: view))
        // UIKit starts the transition before SwiftUI applies preferredColorScheme.
        // Seed native traits first so the map and presentation chrome never flash
        // the device appearance when the app has selected a different mode.
        hosting.overrideUserInterfaceStyle = values.userInterfaceStyle
        hosting.onRemoved = { [weak self] in self?.finish(opening: id) }
        hosting.onAppeared = { [weak self] in self?.resumeDismissalAfterTransition(opening: id) }
        hosting.modalPresentationStyle = fullScreen ? .fullScreen : .pageSheet
        hosting.sheetPresentationController?.detents = [.large()]
        hosting.presentationController?.delegate = self
        opening = id
        controller = hosting
        afterDismiss = onDismiss
        activeLifetime = self
        presenting.present(hosting, animated: true) { [weak self] in
            guard let self, self.opening == id else { return }
            // A close requested during the outer transition takes precedence
            // over opening a nested editor when that transition completes.
            if self.dismissRequested { self.dismiss() }
            else { onPresented() }
        }
        return true
    }

    func dismiss(completion: (() -> Void)? = nil) {
        guard let controller, let id = opening else { return }
        if let completion, selectionCompletion == nil { selectionCompletion = completion }
        dismissRequested = true
        if controller.isBeingDismissed || controller.isBeingPresented {
            // Interactive dismissal can cancel. Keep the request until the root is
            // gone, and resume after cancellation/appearance rather than dropping it.
            controller.transitionCoordinator?.animate(alongsideTransition: nil) { [weak self] transition in
                if transition.isCancelled { self?.resumeDismissalAfterTransition(opening: id) }
            }
            return
        }
        // Dismiss the owned root, including any nested editor/guidance sheets.
        let owner = controller.presentingViewController ?? controller
        owner.dismiss(animated: true) { [weak self] in self?.finish(opening: id) }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === controller, let opening else { return }
        finish(opening: opening)
    }

    private func resumeDismissalAfterTransition(opening id: UUID) {
        guard opening == id, dismissRequested else { return }
        Task { @MainActor [weak self] in
            // Leave UIKit's transition callback before consulting transition flags.
            await Task.yield()
            guard let self, self.opening == id, self.dismissRequested else { return }
            self.dismiss()
        }
    }

    private func finish(opening id: UUID) {
        guard opening == id else { return }
        let onDismiss = afterDismiss
        let completion = selectionCompletion
        opening = nil
        controller = nil
        afterDismiss = nil
        selectionCompletion = nil
        dismissRequested = false
        activeLifetime = nil
        onDismiss?()
        completion?()
    }
}

@MainActor
private final class StableSheetHostingController<Content: View>: UIHostingController<Content> {
    var onRemoved: (() -> Void)?
    var onAppeared: (() -> Void)?
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onAppeared?()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Covering with a nested sheet/full-screen controller is not dismissal.
        if presentingViewController == nil { onRemoved?() }
    }
}

@MainActor
fileprivate final class StableSheetAppearance: ObservableObject {
    struct Values: Equatable {
        let theme: OutboundTheme
        let colorScheme: ColorScheme
        let dynamicTypeSize: DynamicTypeSize
        let locale: Locale
        let layoutDirection: LayoutDirection
        // colorScheme is resolved by the app root, including live System changes.
        var userInterfaceStyle: UIUserInterfaceStyle { colorScheme == .dark ? .dark : .light }
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

private struct StableSheetContent<Content: View>: View {
    @ObservedObject var appearance: StableSheetAppearance
    let content: Content
    var body: some View {
        content
            .environment(\.outboundTheme, appearance.values.theme)
            .environment(\.dynamicTypeSize, appearance.values.dynamicTypeSize)
            .environment(\.locale, appearance.values.locale)
            .environment(\.layoutDirection, appearance.values.layoutDirection)
            .preferredColorScheme(appearance.values.colorScheme)
            .tint(appearance.values.theme.accentColor)
    }
}

/// Place once at the durable scene/flow owner, never in a ViewThatFits candidate.
struct StableSheetPresentationHost: UIViewControllerRepresentable {
    let presenter: StableSheetPresenter
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
