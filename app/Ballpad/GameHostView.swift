import SwiftUI
import UIKit

struct SDLGameContainer: UIViewRepresentable {
    var renderScale: CGFloat = 1

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.attach(to: view)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        if context.coordinator.renderScale != renderScale {
            context.coordinator.renderScale = renderScale
            FileHandle.standardError.write(Data("[display] scale=\(renderScale)\n".utf8))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        weak var container: UIView?
        var timer: Timer?
        var imageView: UIImageView?
        var renderScale: CGFloat = 1

        func attach(to view: UIView) {
            container = view
            let iv = UIImageView()
            iv.backgroundColor = .black
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
            // Display diagnostics: every ~120 frames report the frame stats and
            // whether the image view got updated.
            diagCount += 1
            if diagCount % 120 == 0 {
                let n = Int(w * h)
                var sum: UInt64 = 0
                for i in stride(from: 0, to: min(n, 640*528) * 4, by: 4) {
                    sum += UInt64(buf[i]) + UInt64(buf[i+1]) + UInt64(buf[i+2])
                }
                let mean = Double(sum) / (3.0 * Double(min(n, 640*528)))
                FileHandle.standardError.write(Data("[display] diag mean=\(Int(mean)) imageSet=\(imageView?.image != nil) size=\(w)x\(h)\n".utf8))
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
            // EFB-native frames are full-brightness; a display filter is not
            // needed (the old boost was compensating for the dark crop bug).
            imageView?.image = UIImage(cgImage: cg)
            if frameDiag == 0 {
                NSLog("[ballpad] first frame displayed %ux%u", w, h)
                frameDiag = 1
            }
        }

        var frameDiag = 0
        var diagCount = 0
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
            SDLGameContainer(renderScale: CGFloat(settings.renderScale))
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
            runUITest()
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

    // Automated gate proofs: BALLPAD_UI_TEST=move|verify|menu drives the UI and
    // logs results (no manual touches needed on the simulator).
    private func runUITest() {
        let mode = ProcessInfo.processInfo.environment["BALLPAD_UI_TEST"] ?? ""
        guard !mode.isEmpty else { return }
        func log(_ msg: String) {
            FileHandle.standardError.write(Data("[uitest] \(msg)\n".utf8))
        }
        switch mode {
        case "move":
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if let idx = self.layout.nodes.firstIndex(where: { $0.id == .a }) {
                    let before = self.layout.nodes[idx]
                    log("move A from \(before.normX),\(before.normY)")
                    self.layout.move(id: .a, to: CGPoint(x: 0.62, y: 0.38), in: CGSize(width: 1, height: 1))
                    let after = self.layout.nodes[idx]
                    let saved = UserDefaults.standard.data(forKey: "ballpad.layout.phone") != nil
                    log("moved A to \(after.normX),\(after.normY) saved=\(saved)")
                }
            }
        case "verify":
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if let a = self.layout.nodes.first(where: { $0.id == .a }) {
                    let persisted = (fabs(a.normX - 0.62) < 0.01 && fabs(a.normY - 0.38) < 0.01)
                    log("A position \(a.normX),\(a.normY) persisted=\(persisted)")
                }
            }
        case "menu":
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                log("opening menu")
                self.showMenu = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.settings.renderScale = 2
                    log("scale set to 2")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.showMenu = false
                        log("menu closed")
                    }
                }
            }
        default:
            break
        }
    }
}
