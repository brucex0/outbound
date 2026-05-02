import UIKit
import FirebaseAuth

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        let handled = Auth.auth().canHandle(url)
        print("[Outbound][AppDelegate] openURL handled=\(handled) url=\(url.absoluteString)")
        return handled
    }
}
