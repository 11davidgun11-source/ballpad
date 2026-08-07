import SwiftUI

struct GameHostView: View {
    @StateObject private var settings = SettingsStore()
    @StateObject private var layout: LayoutStore
    @State private var banner: String = "ballpad shell"
    @State private var showMenu = false
    @State private var editMode = false
    @State private var lastPad = "pad: idle"

    init() {
        let idiom = UIDevice.current.userInterfaceIdiom
        _layout = StateObject(wrappedValue: LayoutStore(deviceClass: idiom == .pad ? "pad" : "phone"))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                HStack {
                    Text(banner)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text(lastPad)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.green.opacity(0.9))
                    Button("⋯") { showMenu = true }
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                Spacer()
            }
            TouchControlSurface(store: layout, editMode: editMode) { status in
                var s = status
                ballpad_pad_set(0, &s)
                ballpad_runtime_frame()
                let aOn = (s.button & UInt16(BALLPAD_BUTTON_A)) != 0
                lastPad = "A:\(aOn ? 1 : 0) stick:\(s.stickX),\(s.stickY)"
            }
        }
        .statusBarHidden(true)
        .onAppear {
            var cfg = BallpadRuntimeConfig(iso_path: nil, dol_path: nil, enable_runtime: 0)
            _ = ballpad_runtime_init(&cfg)
            if let cstr = ballpad_runtime_banner() {
                banner = String(cString: cstr)
            }
        }
        .sheet(isPresented: $showMenu) {
            OverflowMenuView(
                isPresented: $showMenu,
                renderScale: $settings.renderScale,
                onEditLayout: { editMode = true; showMenu = false },
                onResetLayout: {
                    let idiom = UIDevice.current.userInterfaceIdiom
                    layout.reset(deviceClass: idiom == .pad ? "pad" : "phone")
                }
            )
        }
    }
}
