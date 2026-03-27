import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        let rootView = WorkSelectionView()
        let hostingController = UIHostingController(rootView: rootView)

        window.rootViewController = hostingController
        self.window = window
        window.makeKeyAndVisible()
    }
}
