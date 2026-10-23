import SwiftUI

/// Place after content in a lazy list. The page identity advances only when the
/// cursor changes, so a failed request cannot spin in an automatic retry loop.
struct AutomaticPaginationRow<PageID: Hashable>: View {
    let pageID: PageID
    var isReady = true
    let load: () async -> Void

    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, OutboundSpacing.compact)
            .task(id: isReady ? pageID : nil) {
                guard isReady else { return }
                await load()
            }
    }
}
