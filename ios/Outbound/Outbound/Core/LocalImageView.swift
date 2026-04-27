import SwiftUI
import UIKit

/// Loads a local file:// URL into an Image. AsyncImage only works with http(s) URLs.
struct LocalImageView<Placeholder: View>: View {
    let url: URL
    let placeholder: Placeholder

    @State private var uiImage: UIImage?

    init(url: URL, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let img = uiImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: url) {
            uiImage = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: url.path)
            }.value
        }
    }
}
