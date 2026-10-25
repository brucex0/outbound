#if DEBUG
import SwiftUI

/// Manual QA of the standalone entry point without fabricating or saving an activity.
struct DebugStretchHarness: View {
    let voiceProfileID: String
    @State private var showing = true
    var body: some View {
        if showing {
            StretchSessionView(launch: StretchLaunchContext(entryPoint: .standalone), voiceProfileID: voiceProfileID) { showing = false }
        } else {
            Button(stretchCatalogText("ui.customize")) { showing = true }
        }
    }
}
#endif
