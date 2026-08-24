import Combine
import Foundation
import UIKit

@MainActor
final class AvatarImageCache {
    static let shared = AvatarImageCache()

    private let images = NSCache<NSString, UIImage>()
    private var requests: [String: Task<UIImage?, Never>] = [:]
    fileprivate let updates = PassthroughSubject<String, Never>()

    private init() {
        images.countLimit = 200
    }

    func cachedImage(for url: String?) -> UIImage? {
        guard let url else { return nil }
        return images.object(forKey: url as NSString)
    }

    func store(_ image: UIImage, for url: String) {
        images.setObject(image, forKey: url as NSString)
        updates.send(url)
    }

    func image(for url: String?) async -> UIImage? {
        guard let url, let remoteURL = URL(string: url) else { return nil }
        if let image = cachedImage(for: url) { return image }
        if let request = requests[url] { return await request.value }

        let request = Task<UIImage?, Never> {
            var request = URLRequest(url: remoteURL)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else { return nil }
            return UIImage(data: data)
        }
        requests[url] = request
        let image = await request.value
        requests[url] = nil
        if let image { store(image, for: url) }
        return image
    }
}

@MainActor
final class AvatarImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private var currentURL: String?
    private var cacheUpdates: AnyCancellable?

    init(url: String?) {
        currentURL = url
        image = AvatarImageCache.shared.cachedImage(for: url)
        cacheUpdates = AvatarImageCache.shared.updates.sink { [weak self] updatedURL in
            guard let self, self.currentURL == updatedURL else { return }
            self.image = AvatarImageCache.shared.cachedImage(for: updatedURL)
        }
    }

    func load(url: String?) async {
        if currentURL != url {
            currentURL = url
            image = AvatarImageCache.shared.cachedImage(for: url)
        }
        guard image == nil else { return }
        let loadedImage = await AvatarImageCache.shared.image(for: url)
        guard currentURL == url else { return }
        image = loadedImage
    }
}
