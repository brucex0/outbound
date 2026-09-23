import SwiftUI

/// Measurement boundary for the live bottom panel. Camera and map surfaces
/// can use different controls while publishing one obstruction contract.
struct ActivityControlSheet<Content: View>: View {
    let isExpanded: Bool
    @ViewBuilder let content: () -> Content

    init(isExpanded: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        content()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: MapAttributionOcclusionHeightPreferenceKey.self,
                        value: isExpanded ? 0 : proxy.size.height
                    )
                }
            }
    }
}
