import SwiftUI
import UIKit

struct SDLGameContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.attach(to: view)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        weak var container: UIView?
        var timer: Timer?
        var imageView: UIImageView?

        func attach(to view: UIView) {
            container = view
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFit
            iv.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                iv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                iv.topAnchor.constraint(equalTo: view.topAnchor),
                iv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            imageView = iv
            ballpad_ios_host_set_container_view(Unmanaged.passUnretained(view).toOpaque())
            var cfg = BallpadIosHostConfig()
            cfg.iso_path = nil
            cfg.dol_path = nil
            cfg.card_path = nil
            cfg.enable_audio = false
            cfg.verbose = true
            ballpad_ios_host_start(&cfg)
            timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
                ballpad_ios_host_step_frame()
                self?.updateFrame()
            }
        }

        func updateFrame() {
            var w: UInt32 = 0
            var h: UInt32 = 0
            guard ballpad_ios_host_frame_size(&w, &h) else {
                if frameDiag == 0 { NSLog("[ballpad] no frame yet") }
                return
            }
            let count = Int(w * h * 4)
            var buf = [UInt8](repeating: 0, count: count)
            guard ballpad_ios_host_take_frame(&buf, &w, &h) else {
                if frameDiag == 0 { NSLog("[ballpad] take_frame failed") }
                return
            }
            if let container = container, let imageView = imageView {
                container.bringSubviewToFront(imageView)
            }
            guard let provider = CGDataProvider(data: Data(buf) as CFData) else {
                if frameDiag == 0 { NSLog("[ballpad] CGDataProvider failed %ux%u", w, h) }
                return
            }
            guard let cg = CGImage(width: Int(w), height: Int(h), bitsPerComponent: 8,
                                   bitsPerPixel: 32, bytesPerRow: Int(w) * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true,
                                   intent: .defaultIntent) else {
                if frameDiag == 0 { NSLog("[ballpad] CGImage failed %ux%u", w, h) }
                return
            }
            imageView?.image = UIImage(cgImage: cg)
            if frameDiag == 0 {
                NSLog("[ballpad] first frame displayed %ux%u", w, h)
                frameDiag = 1
            }
        }

        var frameDiag = 0
    }
}

struct GameHostView: View {
    @StateObject private var settings = SettingsStore()
    @StateObject private var layout: LayoutStore
    @State private var banner: String = "ballpad booting…"
    @State private var showMenu = false
    @State private var editMode = false
    @State private var lastPad = "pad: idle"

    init() {
        let idiom = UIDevice.current.userInterfaceIdiom
        _layout = StateObject(wrappedValue: LayoutStore(deviceClass: idiom == .pad ? "pad" : "phone"))
    }

    var body: some View {
        ZStack {
            SDLGameContainer()
                .ignoresSafeArea()
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
