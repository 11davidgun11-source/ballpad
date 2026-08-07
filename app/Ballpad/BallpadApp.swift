import SwiftUI

@main
struct BallpadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            GameHostView()
        }
    }
}
