import SwiftUI
import UIKit

/// Loads local activity photos and short-lived remote social photo URLs.
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
            guard uiImage == nil else { return }
            if url.isFileURL {
                let path = url.path(percentEncoded: false)
                uiImage = await Task.detached(priority: .userInitiated) {
                    UIImage(contentsOfFile: path)
                }.value
            } else if let (data, response) = try? await URLSession.shared.data(from: url),
                      (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) != false {
                uiImage = UIImage(data: data)
            }
        }
    }
}
