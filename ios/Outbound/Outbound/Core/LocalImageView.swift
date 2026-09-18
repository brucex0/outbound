import SwiftUI
import UIKit

/// Loads local activity photos and remote social photo URLs through the
/// shared photo cache. When `maxPixelSize` is provided the image is decoded
/// downsampled and can reuse a cached thumbnail file, which keeps small
/// surfaces such as carousels and map pins fast even for full-size camera
/// JPEGs and freshly signed remote media URLs.
struct LocalImageView<Placeholder: View>: View {
    let url: URL
    let placeholder: Placeholder
    private let maxPixelSize: CGFloat?

    @State private var uiImage: UIImage?

    init(url: URL, maxPixelSize: CGFloat? = nil, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: url) {
            if let image = ActivityPhotoCache.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
                uiImage = image
                return
            }
            guard uiImage == nil else { return }
            uiImage = await ActivityPhotoCache.shared.image(for: url, maxPixelSize: maxPixelSize)
        }
    }
}
