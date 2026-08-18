import SwiftUI

private struct AssistantHighlightModifier: ViewModifier {
    @EnvironmentObject private var appNavigationStore: AppNavigationStore
    let anchorID: String?

    func body(content: Content) -> some View {
        content
            .id(anchorID)
            .overlay {
                if let anchorID, appNavigationStore.highlightedAssistantAnchorID == anchorID {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .shadow(color: Color.accentColor.opacity(0.55), radius: 8)
                        .padding(2)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: appNavigationStore.highlightedAssistantAnchorID)
            .task(id: appNavigationStore.highlightedAssistantAnchorID) {
                guard let anchorID, appNavigationStore.highlightedAssistantAnchorID == anchorID else { return }
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled else { return }
                appNavigationStore.clearHighlight(anchorID)
            }
    }
}

extension View {
    /// Registers a stable UI element that an assistant destination can spotlight after navigation.
    func assistantHighlightAnchor(_ anchorID: String?) -> some View {
        modifier(AssistantHighlightModifier(anchorID: anchorID))
    }
}
