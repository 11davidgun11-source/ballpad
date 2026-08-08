import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        #if targetEnvironment(simulator)
        let screen = windowScene.screen
        NSLog("[scene] coordinateSpace=%@ bounds=%@ screen=%@ native=%@ interfaceOrientation=%ld",
              NSCoder.string(for: windowScene.coordinateSpace.bounds),
              NSCoder.string(for: windowScene.screen.bounds),
              NSCoder.string(for: screen.bounds),
              NSCoder.string(for: screen.nativeBounds),
              windowScene.interfaceOrientation.rawValue)
        #endif
        ballpad_ios_host_set_window_scene(Unmanaged.passUnretained(windowScene).toOpaque())
        // Force an opaque full-screen window: the SwiftUI WindowGroup window on
        // the iPad simulator can otherwise present as a transparent floating
        // panel over the springboard.
        DispatchQueue.main.async {
            for (i, w) in windowScene.windows.enumerated() {
                NSLog("[scene] window[%d]=%@ root=%@ hidden=%d key=%d",
                      i, NSCoder.string(for: w.frame),
                      String(describing: type(of: w.rootViewController ?? UIViewController())),
                      w.isHidden ? 1 : 0, w.isKeyWindow ? 1 : 0)
                w.backgroundColor = .black
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            for (i, w) in windowScene.windows.enumerated() {
                NSLog("[scene] +3s window[%d]=%@ hidden=%d key=%d",
                      i, NSCoder.string(for: w.frame),
                      w.isHidden ? 1 : 0, w.isKeyWindow ? 1 : 0)
            }
        }
        // The SDL backend creates its own UIWindow and keeps it key, which
        // deactivates the SwiftUI window hosting the EFB image + touch
        // overlay (its content never attaches — container.window == nil).
        // Keep the SwiftUI window key and visible so its content lays out.
        let keepSwiftUIKey = {
            for w in windowScene.windows {
                if let root = w.rootViewController,
                   String(describing: type(of: root)).contains("UIHostingController") {
                    if !w.isKeyWindow { w.makeKey() }
                    if w.isHidden { w.isHidden = false }
                    w.rootViewController?.view.setNeedsLayout()
                }
            }
        }
        keepSwiftUIKey()
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            keepSwiftUIKey()
        }
    }
}
