import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SDLGameContainer: UIViewRepresentable {
    var renderScale: CGFloat = 1
    var aspectMode: String = "native"
    var paused: Bool = false

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.attach(to: view)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        if context.coordinator.renderScale != renderScale {
            context.coordinator.renderScale = renderScale
            // M10: recreate the EFB render targets at the new supersample scale.
            ballpad_ios_host_set_efb_scale(Int32(renderScale))
            FileHandle.standardError.write(Data("[display] scale=\(renderScale)\n".utf8))
        }
        if context.coordinator.aspectMode != aspectMode {
            context.coordinator.aspectMode = aspectMode
            context.coordinator.applyAspect()
            FileHandle.standardError.write(Data("[display] aspect=\(aspectMode)\n".utf8))
        }
        if context.coordinator.paused != paused {
            context.coordinator.paused = paused
            ballpad_ios_host_set_paused(paused)
            FileHandle.standardError.write(Data("[display] paused=\(paused)\n".utf8))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.timer?.invalidate()
        coordinator.timer = nil
        coordinator.imageView?.image = nil
        ballpad_ios_host_set_container_view(nil)
        ballpad_ios_host_stop()
    }

    class Coordinator {
        weak var container: UIView?
        var timer: Timer?
        var imageView: UIImageView?
        var renderScale: CGFloat = 1
        var aspectMode: String = "native"
        var paused: Bool = false

        func attach(to view: UIView) {
            container = view
            #if targetEnvironment(simulator)
            NSLog("[window] container initial frame=%@", NSCoder.string(for: view.frame))
            #endif
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
            // B4: ship quiet. The per-present [gfxN] log spam comes from
            // cfg.verbose (info_logging/graphics_logging in Aurora). Keep it
            // env-overridable for diagnostics (BALLPAD_VERBOSE=1).
            cfg.verbose = ProcessInfo.processInfo.environment["BALLPAD_VERBOSE"] == "1"
            // M10: apply the persisted EFB supersample scale before boot so the
            // first EFB target creation uses it.
            ballpad_ios_host_set_efb_scale(Int32(renderScale))
            ballpad_ios_host_start(&cfg)
            timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
                // B1: the guest runs on a dedicated worker thread; the display
                // timer reads the latest EFB frame and pumps the SDL window
                // attach (UI-thread work the worker must not touch).
                ballpad_ios_host_pump_ui()
                self?.updateFrame()
            }
        }

        func updateFrame() {
            #if targetEnvironment(simulator)
            if displayDiagnostics, diagCount % 300 == 0, let container = container {
                let w = container.window
                let winFrame = w?.frame ?? .zero
                let screenBounds = w?.screen.bounds ?? .zero
                NSLog("[window] container=%@ windowNil=%d window=%@ screen=%@ super=%@",
                      NSCoder.string(for: container.frame),
                      w == nil ? 1 : 0,
                      NSCoder.string(for: winFrame),
                      NSCoder.string(for: screenBounds),
                      String(describing: type(of: container.superview ?? UIView())))
            }
            #endif
            var w: UInt32 = 0
            var h: UInt32 = 0
            // Perf: skip the copy + CGImage render when the guest has not
            // produced a new frame (slow scenes: the display timer runs at
            // 60 Hz regardless, and re-rendering the same image steals
            // main-thread CPU the guest loop needs).
            let version = ballpad_ios_host_frame_version()
            if version == lastFrameVersion {
                return
            }
            lastFrameVersion = version
            // B2: zero-copy — reference the host's double-buffered RGBA
            // staging directly (no per-frame array alloc or Data copy).
            guard let framePtr = ballpad_ios_host_frame_ptr(&w, &h) else {
                if frameDiag == 0 { NSLog("[ballpad] no frame data") }
                return
            }
            let count = Int(w * h * 4)
            if let container = container, let imageView = imageView {
                container.bringSubviewToFront(imageView)
            }
            // Display diagnostics: every ~120 frames report the frame stats and
            // whether the image view got updated.
            diagCount += 1
            if displayDiagnostics, diagCount % 120 == 0 {
                let n = Int(w * h)
                var sum: UInt64 = 0
                for i in stride(from: 0, to: min(n, 640*528) * 4, by: 4) {
                    sum += UInt64(framePtr[i]) + UInt64(framePtr[i+1]) + UInt64(framePtr[i+2])
                }
                let mean = Double(sum) / (3.0 * Double(min(n, 640*528)))
                FileHandle.standardError.write(Data("[display] diag mean=\(Int(mean)) imageSet=\(imageView?.image != nil) size=\(w)x\(h)\n".utf8))
            }
            let provider = CGDataProvider(dataInfo: nil, data: framePtr,
                                          size: count) { _, _, _ in }
            guard let provider else {
                if frameDiag == 0 { NSLog("[ballpad] CGDataProvider failed %ux%u", w, h) }
                return
            }
            guard let cg = CGImage(width: Int(w), height: Int(h), bitsPerComponent: 8,
                                   bitsPerPixel: 32, bytesPerRow: Int(w) * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: [CGBitmapInfo.byteOrder32Little,
                                                CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)],
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

        // docs/06 Display aspect policy: native 4:3 letterbox vs 16:9 crop vs
        // stretch. Crop (wide) loses the top/bottom HUD band; stretch distorts.
        func applyAspect() {
            switch aspectMode {
            case "wide":
                imageView?.contentMode = .scaleAspectFill
            case "stretch":
                imageView?.contentMode = .scaleToFill
            default:
                imageView?.contentMode = .scaleAspectFit
            }
        }

        var frameDiag = 0
        var diagCount = 0
        var lastFrameVersion: UInt64 = 0
        let displayDiagnostics = ProcessInfo.processInfo.environment[
            "BALLPAD_DISPLAY_DIAGNOSTICS"] == "1"
    }
}

struct GameHostView: View {
    @StateObject private var settings = SettingsStore()
    @StateObject private var layout: LayoutStore
    // C2: hardware controller state (auto-hides the touch overlay on connect).
    @StateObject private var controller = ControllerManager()
    @State private var showMenu = false
    @State private var editMode = false
    @State private var selectedControl: ControlID?
    @State private var fps: Double = 0
    @State private var guestInfo = ""
    @State private var statsTimer: Timer?
    @State private var showGameImporter = false
    @State private var showCardImporter = false
    @State private var operationActive = false
    @State private var importingGame = false
    @State private var shareItem: ShareItem?
    @State private var notice: Notice?
    @State private var confirmDiagnostics = false

    init() {
        let idiom = UIDevice.current.userInterfaceIdiom
        _layout = StateObject(wrappedValue: LayoutStore(deviceClass: idiom == .pad ? "pad" : "phone"))
    }

    var body: some View {
        ZStack {
            SDLGameContainer(renderScale: CGFloat(settings.renderScale),
                             aspectMode: settings.aspectMode,
                             paused: showMenu || showGameImporter ||
                                showCardImporter || operationActive)
                .ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    // A3 test hook (BALLPAD_TEST_HOOKS=1): the guest block
                    // count + cGame state as an accessibility label the
                    // XCUITest polls to drive the overlay at block anchors.
                    if ProcessInfo.processInfo.environment["BALLPAD_TEST_HOOKS"] == "1" {
                        Text(guestInfo)
                            .font(.system(size: 8).monospaced())
                            .foregroundStyle(.white.opacity(0.25))
                            .accessibilityIdentifier("guestBlocks")
                    }
                    if settings.showFps {
                        Text(String(format: "%.0f fps", fps))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.yellow.opacity(0.9))
                    }
                    BallpadMenu(
                        renderScale: $settings.renderScale,
                        aspectMode: $settings.aspectMode,
                        showFps: $settings.showFps,
                        onTouchSettings: { showMenu = true },
                        onImportGame: { showGameImporter = true },
                        onImportCard: { showCardImporter = true },
                        onExportCard: exportCard,
                        onShareDiagnostics: { confirmDiagnostics = true }
                    )
                }
                .padding(.horizontal)
                .padding(.top, 8)
                if editMode {
                    // Layout editor toolbar (docs/05 §5): Done saves, Cancel
                    // reverts to the snapshot taken at enter.
                    HStack {
                        Button("Cancel") {
                            layout.revertSnapshot()
                            selectedControl = nil
                            editMode = false
                        }
                        .foregroundStyle(.red)
                        Spacer()
                        if let selectedControl {
                            Text(selectedControl.rawValue.uppercased())
                                .font(.caption.bold())
                                .foregroundStyle(.cyan)
                            Slider(
                                value: Binding(
                                    get: { Double(layout.node(selectedControl).scale) },
                                    set: { layout.setScale(id: selectedControl, CGFloat($0)) }
                                ),
                                in: 0.6...1.75
                            )
                            .frame(maxWidth: 220)
                            .accessibilityLabel("Selected control size")
                        } else {
                            Text("DRAG CONTROLS • TAP ONE TO RESIZE")
                                .font(.caption.bold())
                                .foregroundStyle(.yellow)
                        }
                        Spacer()
                        Button("Done") {
                            layout.commitSnapshot()
                            selectedControl = nil
                            editMode = false
                        }
                        .foregroundStyle(.green)
                    }
                    .padding(.horizontal)
                }
                Spacer()
            }
            .zIndex(10)
            TouchControlSurface(store: layout,
                                editMode: editMode,
                                controlScale: CGFloat(settings.controlScale),
                                controlOpacity: settings.controlOpacity,
                                controllerConnected: controller.isConnected &&
                                    settings.hideControlsOnController,
                                selectedControl: $selectedControl) { status in
                var s = status
                ballpad_pad_set(0, &s)
            }
            #if !targetEnvironment(simulator)
            ProductActionHost(
                showGameImporter: $showGameImporter,
                showCardImporter: $showCardImporter,
                importingGame: importingGame,
                shareItem: $shareItem,
                notice: $notice,
                confirmDiagnostics: $confirmDiagnostics,
                onGameImport: handleGameImport,
                onCardImport: handleCardImport,
                onShareDiagnostics: shareDiagnostics
            )
            #endif
        }
        .statusBarHidden(true)
        .onAppear {
            statsTimer?.invalidate()
            statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                fps = ballpad_ios_host_fps()
                guestInfo = "\(ballpad_ios_host_guest_blocks()) \(ballpad_ios_host_game_state())"
            }
            runUITest()
        }
        .onDisappear {
            statsTimer?.invalidate()
            statsTimer = nil
            ballpad_pad_clear(0)
        }
        .onChange(of: controller.isConnected) { _, connected in
            if connected && settings.hideControlsOnController {
                ballpad_pad_clear_touch(0)
            }
        }
        .onChange(of: settings.hideControlsOnController) { _, hide in
            if hide && controller.isConnected {
                ballpad_pad_clear_touch(0)
            }
        }
        .sheet(isPresented: $showMenu) {
            OverflowMenuView(
                isPresented: $showMenu,
                controlScale: $settings.controlScale,
                controlOpacity: $settings.controlOpacity,
                hideControlsOnController: $settings.hideControlsOnController,
                onEditLayout: {
                    layout.takeSnapshot()
                    selectedControl = nil
                    editMode = true
                    showMenu = false
                },
                onResetLayout: {
                    let idiom = UIDevice.current.userInterfaceIdiom
                    layout.reset(deviceClass: idiom == .pad ? "pad" : "phone")
                }
            )
        }
    }

    private func handleGameImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result {
                notice = Notice(title: "Import Failed", message: error.localizedDescription)
            }
            return
        }
        importingGame = true
        operationActive = true
        let access = url.startAccessingSecurityScopedResource()
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = ballpad_ios_host_import_game(url.path)
            if access { url.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async {
                importingGame = false
                operationActive = false
                notice = ok
                    ? Notice(title: "Game Imported",
                             message: "The supported game image was replaced safely. Restart Ballpad to use the new copy.")
                    : Notice(title: "Import Failed",
                             message: "Choose a raw Super Mario Strikers USA G4QE01 ISO or GCM image.")
            }
        }
    }

    private func handleCardImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result {
                notice = Notice(title: "Import Failed", message: error.localizedDescription)
            }
            return
        }
        operationActive = true
        let access = url.startAccessingSecurityScopedResource()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let ok = ballpad_ios_host_import_card(url.path)
            if access { url.stopAccessingSecurityScopedResource() }
            operationActive = false
            notice = Notice(title: ok ? "Memory Card Imported" : "Import Failed",
                            message: ok
                                ? "The active memory card now uses the selected backup."
                                : "Ballpad could not read that memory-card backup.")
        }
    }

    private func exportCard() {
        operationActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let formatter = ISO8601DateFormatter()
            let stamp = formatter.string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Ballpad-CardA-\(stamp).dolcard")
            let ok = ballpad_ios_host_export_card(url.path)
            operationActive = false
            if ok {
                shareItem = ShareItem(url: url)
            } else {
                notice = Notice(title: "Export Failed",
                                message: "The active memory card is not available yet.")
            }
        }
    }

    private func shareDiagnostics() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let screen = UIScreen.main
        let text = """
        Ballpad diagnostic snapshot
        App: \(version)
        OS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.model)
        Display: \(Int(screen.nativeBounds.width))x\(Int(screen.nativeBounds.height)) @ \(screen.nativeScale)x
        Controller connected: \(controller.isConnected)
        Render scale: \(settings.renderScale)x
        Aspect mode: \(settings.aspectMode)
        FPS: \(String(format: "%.1f", fps))
        Guest running: \(ballpad_ios_host_running())
        Guest blocks: \(ballpad_ios_host_guest_blocks())
        Game state: \(ballpad_ios_host_game_state())
        Game data present: \(ballpad_ios_host_game_files_present())
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ballpad-Diagnostics.log")
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            shareItem = ShareItem(url: url)
        } catch {
            notice = Notice(title: "Diagnostic Log Unavailable",
                            message: error.localizedDescription)
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
                    let persisted = (abs(a.normX - 0.62) < 0.01 && abs(a.normY - 0.38) < 0.01)
                    log("A position \(a.normX),\(a.normY) persisted=\(persisted)")
                }
            }
        case "menu":
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                log("opening menu")
                self.showMenu = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.settings.renderScale = 2
                    self.settings.showFps = true
                    log("scale set to 2")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.showMenu = false
                        log("menu closed")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            log("fps=\(String(format: "%.0f", self.fps))")
                        }
                    }
                }
            }
        case "multitouch":
            // M6: stick + trigger + two face buttons simultaneously. Proves the
            // pad buffer merges multi-input in one sample (the touch surface
            // emits the same assembled status on multi-touch).
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                var s = BallPadStatus()
                s.err = 0
                s.stickX = 100
                s.stickY = -80
                s.substickX = 60
                s.triggerLeft = 255
                s.triggerRight = 220
                s.button = UInt16(BALLPAD_BUTTON_A) | UInt16(BALLPAD_BUTTON_B)
                ballpad_pad_set(0, &s)
            }
        case "controls":
            // M5: sweep every GC control through the pad buffer, logging each.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let checks: [(String, UInt16)] = [
                    ("D-LEFT", UInt16(BALLPAD_BUTTON_LEFT)),
                    ("D-RIGHT", UInt16(BALLPAD_BUTTON_RIGHT)),
                    ("D-DOWN", UInt16(BALLPAD_BUTTON_DOWN)),
                    ("D-UP", UInt16(BALLPAD_BUTTON_UP)),
                    ("Z", UInt16(BALLPAD_TRIGGER_Z)),
                    ("R", UInt16(BALLPAD_TRIGGER_R)),
                    ("L", UInt16(BALLPAD_TRIGGER_L)),
                    ("A", UInt16(BALLPAD_BUTTON_A)),
                    ("B", UInt16(BALLPAD_BUTTON_B)),
                    ("X", UInt16(BALLPAD_BUTTON_X)),
                    ("Y", UInt16(BALLPAD_BUTTON_Y)),
                    ("START", UInt16(BALLPAD_BUTTON_START)),
                ]
                for (name, bit) in checks {
                    var s = BallPadStatus()
                    s.err = 0
                    s.button = bit
                    ballpad_pad_set(0, &s)
                    var out = BallPadStatus()
                    ballpad_pad_get(0, &out)
                    log("control \(name)=0x\(String(out.button, radix: 16)) ok=\((out.button & bit) == bit)")
                }
                var stick = BallPadStatus()
                stick.err = 0
                stick.stickX = 127
                stick.stickY = -127
                stick.substickX = 127
                stick.substickY = -127
                ballpad_pad_set(0, &stick)
                var out = BallPadStatus()
                ballpad_pad_get(0, &out)
                log("stick full=\(out.stickX),\(out.stickY) cstick=\(out.substickX),\(out.substickY) ok=\(out.stickX == 127 && out.stickY == -127)")
            }
        case "saves":
            // M11: export the active card, then import it back and verify the
            // file round-trips byte-identically.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
                let dir = (docs as NSString).appendingPathComponent("Saves")
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let card = String(cString: ballpad_ios_host_card_path())
                guard FileManager.default.fileExists(atPath: card) else {
                    log("saves: active card missing at \(card)")
                    return
                }
                let cardData = (try? Data(contentsOf: URL(fileURLWithPath: card))) ?? Data()
                let export = (dir as NSString).appendingPathComponent("uitest-roundtrip.dolcard")
                let exported = ballpad_ios_host_export_card(export)
                let exportedData = (try? Data(contentsOf: URL(fileURLWithPath: export))) ?? Data()
                let exportMatch = exported && cardData == exportedData
                log("saves: export ok=\(exported) bytes=\(exportedData.count) match=\(exportMatch)")
                // Corrupt the active card, then import the export back.
                try? Data(repeating: 0xEE, count: cardData.count).write(to: URL(fileURLWithPath: card))
                let imported = ballpad_ios_host_import_card(export)
                let restoredData = (try? Data(contentsOf: URL(fileURLWithPath: card))) ?? Data()
                let restoredMatch = imported && restoredData == cardData
                log("saves: import ok=\(imported) restored=\(restoredMatch) bytes=\(restoredData.count)")
            }
        default:
            break
        }
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct Notice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController,
                                context: Context) {}
}

/// Keep document pickers, alerts, and share sheets off the view that owns the
/// SDL container. On iPadOS 26, attaching those presentation modifiers to the
/// `UIViewRepresentable` root creates an AttributeGraph cycle and detaches the
/// game window. Sunpad likewise keeps product actions separate from gameplay.
private struct ProductActionHost: View {
    @Binding var showGameImporter: Bool
    @Binding var showCardImporter: Bool
    let importingGame: Bool
    @Binding var shareItem: ShareItem?
    @Binding var notice: Notice?
    @Binding var confirmDiagnostics: Bool
    let onGameImport: (Result<[URL], Error>) -> Void
    let onCardImport: (Result<[URL], Error>) -> Void
    let onShareDiagnostics: () -> Void

    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .allowsHitTesting(importingGame)
            .overlay {
                if importingGame {
                    ZStack {
                        Color.black.opacity(0.65).ignoresSafeArea()
                        ProgressView("Importing game…")
                            .padding(24)
                            .background(.regularMaterial,
                                        in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .fileImporter(isPresented: $showGameImporter,
                          allowedContentTypes: [.data,
                              UTType(filenameExtension: "iso") ?? .data,
                              UTType(filenameExtension: "gcm") ?? .data],
                          allowsMultipleSelection: false,
                          onCompletion: onGameImport)
            .fileImporter(isPresented: $showCardImporter,
                          allowedContentTypes: [.data,
                              UTType(filenameExtension: "dolcard") ?? .data],
                          allowsMultipleSelection: false,
                          onCompletion: onCardImport)
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.url])
            }
            .alert(item: $notice) { notice in
                Alert(title: Text(notice.title), message: Text(notice.message),
                      dismissButton: .default(Text("OK")))
            }
            .alert("Share Diagnostic Log?", isPresented: $confirmDiagnostics) {
                Button("Cancel", role: .cancel) {}
                Button("Continue", action: onShareDiagnostics)
            } message: {
                Text("The log includes app, OS, device, display, controller, and runtime status. It does not include your game image, extracted game data, or saves.")
            }
    }
}
