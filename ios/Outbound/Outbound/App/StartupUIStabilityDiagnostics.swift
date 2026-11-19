import SwiftUI
#if DEBUG
import Combine
import UIKit

/// Local lifecycle diagnostics only. Call sites supply fixed component/event
/// labels and booleans; never route, account, activity, or user-entered values.
@MainActor
final class StartupUIStabilityDiagnostics: ObservableObject {
    private static var nextPresentation = 0
    private static var didRecordThemeEquality = false
    private let component: String
    private let presentation: Int

    init(_ component: String) {
        self.component = component
        Self.nextPresentation += 1
        presentation = Self.nextPresentation
        record("created")
    }

    func record(_ event: String) {
        Self.emit(
            "ui_stability component=\(component) presentation=\(presentation) event=\(event)")
    }

    static func emit(_ message: String, isError: Bool = false) {
        if isError { ActivityDiagnosticLog.error(.lifecycle, message) }
        else { ActivityDiagnosticLog.notice(.lifecycle, message) }
        // devicectl --console exposes stdout without a broad device log archive.
        print(message)
    }

    static func recordThemeEquality(_ theme: OutboundTheme) {
        guard !didRecordThemeEquality else { return }
        didRecordThemeEquality = true
        let first = theme.accentColor
        let second = theme.accentColor
        let firstUIColor = UIColor(first)
        let secondUIColor = UIColor(second)
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        Self.emit(
            "ui_stability component=theme event=equality_checked color_equal=\(first == second) uicolor_equal=\(firstUIColor.isEqual(secondUIColor)) light_equal=\(firstUIColor.resolvedColor(with: light).isEqual(secondUIColor.resolvedColor(with: light))) dark_equal=\(firstUIColor.resolvedColor(with: dark).isEqual(secondUIColor.resolvedColor(with: dark)))")
    }

    deinit {
        let message = "ui_stability component=\(component) presentation=\(presentation) event=released"
        Task { @MainActor in Self.emit(message) }
    }
}

private struct StartupUIStabilityModifier: ViewModifier {
    @StateObject private var diagnostics: StartupUIStabilityDiagnostics

    init(_ component: String) {
        _diagnostics = StateObject(wrappedValue: StartupUIStabilityDiagnostics(component))
    }

    func body(content: Content) -> some View {
        content
            .onAppear { diagnostics.record("appeared") }
            .onDisappear { diagnostics.record("disappeared") }
    }
}
#endif

extension View {
    @ViewBuilder
    func startupUIStabilityDiagnostics(_ component: String) -> some View {
#if DEBUG
        modifier(StartupUIStabilityModifier(component))
#else
        self
#endif
    }
}
