import SwiftUI

struct GameHostView: View {
    @State private var banner: String = "ballpad shell"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Text(banner)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding()
                Text("AOT host shell")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .statusBarHidden(true)
        .onAppear {
            var cfg = BallpadRuntimeConfig(iso_path: nil, dol_path: nil, enable_runtime: 0)
            if ballpad_runtime_init(&cfg) {
                if let cstr = ballpad_runtime_banner() {
                    banner = String(cString: cstr)
                }
            }
        }
    }
}

#Preview {
    GameHostView()
}
