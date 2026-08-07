import SwiftUI

struct GameHostView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("ballpad shell")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Step 6: empty host")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .statusBarHidden(true)
    }
}

#Preview {
    GameHostView()
}
