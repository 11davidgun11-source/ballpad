import SwiftUI

@main
struct BallpadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

// A2: route to the onboarding (missing game) or the game view. A missing game
// shows import instructions, never a black screen.
struct AppRootView: View {
    @State private var hasGame = ballpad_ios_host_game_files_present()

    var body: some View {
        Group {
            if hasGame {
                GameHostView()
            } else {
                OnboardingView(hasGame: $hasGame)
            }
        }
    }
}
