import GameController
import Foundation

// C2: hardware GameCube-style controller support. Mirrors bellpad's iOS
// overlay (apple/ios/BellpadGameOverlay.mm): listen for GCController connect/
// disconnect, merge the extended-gamepad state into ballpad_pad_set, and
// expose `isConnected` so the touch overlay can auto-hide.
final class ControllerManager: ObservableObject {
    @Published private(set) var isConnected = false

    private var observers: [NSObjectProtocol] = []
    private var configured = Set<ObjectIdentifier>()

    init() {
        // Defer ALL GameController interaction: touching the GC framework
        // during SwiftUI view init on the iOS 26 simulator triggers an
        // AttributeGraph layout cycle (the hosting window detaches and the
        // screen goes black — verified 2026-08-08, docs/09). Registering the
        // observers + enumerating controllers once the window has settled is
        // safe.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.setup()
        }
    }

    private func setup() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] note in
            if let controller = note.object as? GCController {
                self?.configure(controller)
            }
            self?.refresh()
        })
        observers.append(center.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main
        ) { [weak self] _ in
            // Release any buttons held when the controller dropped.
            ballpad_pad_clear(0)
            self?.configured.removeAll()
            self?.refresh()
        })
        for controller in GCController.controllers() {
            configure(controller)
        }
        refresh()
        if ProcessInfo.processInfo.environment["BALLPAD_SIMULATE_CONTROLLER"] == "1" {
            // Simulator proof hook: no physical controllers exist on the sim,
            // so fake a connect (hides the overlay) and then self-test the
            // button/stick mapping (logs the merged pad state).
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.isConnected = true
                NSLog("[controller] simulate connect: overlay hidden")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                self?.selfTest()
            }
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func refresh() {
        var connected = false
        // The iOS 26 simulator exposes a virtual MFi gamepad (always present),
        // which would auto-hide the touch overlay on every simulator run and
        // break touch testing. bellpad's overlay does the same: input from
        // connected controllers still merges everywhere (configure()), but
        // overlay visibility only reacts on real devices.
        #if !targetEnvironment(simulator)
        for controller in GCController.controllers() where controller.extendedGamepad != nil {
            connected = true
            break
        }
        #endif
        isConnected = connected
    }

    private func configure(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        if configured.contains(ObjectIdentifier(controller)) { return }
        configured.insert(ObjectIdentifier(controller))
        controller.playerIndex = .index1
        gamepad.valueChangedHandler = { pad, _ in
            let s = ControllerManager.map(
                a: pad.buttonA.isPressed,
                b: pad.buttonB.isPressed,
                x: pad.buttonX.isPressed,
                y: pad.buttonY.isPressed,
                lShoulder: pad.leftShoulder.isPressed,
                rShoulder: pad.rightShoulder.isPressed,
                menu: pad.buttonMenu.isPressed,
                dpadUp: pad.dpad.up.isPressed,
                dpadDown: pad.dpad.down.isPressed,
                dpadLeft: pad.dpad.left.isPressed,
                dpadRight: pad.dpad.right.isPressed,
                lx: pad.leftThumbstick.xAxis.value,
                ly: pad.leftThumbstick.yAxis.value,
                rx: pad.rightThumbstick.xAxis.value,
                ry: pad.rightThumbstick.yAxis.value,
                lt: pad.leftTrigger.value,
                rt: pad.rightTrigger.value
            )
            var out = s
            ballpad_pad_set(0, &out)
        }
    }

    // Pure mapping (testable without a hardware controller). Sign conventions
    // match the touch overlay: stick up -> +stickY, right -> +stickX.
    static func map(a: Bool, b: Bool, x: Bool, y: Bool,
                    lShoulder: Bool, rShoulder: Bool, menu: Bool,
                    dpadUp: Bool, dpadDown: Bool, dpadLeft: Bool, dpadRight: Bool,
                    lx: Float, ly: Float, rx: Float, ry: Float,
                    lt: Float, rt: Float) -> BallPadStatus {
        var s = BallPadStatus()
        s.err = 0
        var btn: UInt16 = 0
        if a { btn |= UInt16(BALLPAD_BUTTON_A) }
        if b { btn |= UInt16(BALLPAD_BUTTON_B) }
        if x { btn |= UInt16(BALLPAD_BUTTON_X) }
        if y { btn |= UInt16(BALLPAD_BUTTON_Y) }
        if lShoulder { btn |= UInt16(BALLPAD_TRIGGER_L) }
        if rShoulder { btn |= UInt16(BALLPAD_TRIGGER_Z) }
        if menu { btn |= UInt16(BALLPAD_BUTTON_START) }
        if dpadUp { btn |= UInt16(BALLPAD_BUTTON_UP) }
        if dpadDown { btn |= UInt16(BALLPAD_BUTTON_DOWN) }
        if dpadLeft { btn |= UInt16(BALLPAD_BUTTON_LEFT) }
        if dpadRight { btn |= UInt16(BALLPAD_BUTTON_RIGHT) }
        // Analog triggers also assert the digital L/R bits past a threshold
        // (bellpad uses ~30/255; the GameCube triggers have a digital click).
        if lt > 30.0 / 255.0 { btn |= UInt16(BALLPAD_TRIGGER_L) }
        if rt > 30.0 / 255.0 { btn |= UInt16(BALLPAD_TRIGGER_R) }
        s.button = btn
        s.stickX = Int8(clamping: Int(lroundf(lx * 127)))
        s.stickY = Int8(clamping: Int(lroundf(ly * 127)))
        s.substickX = Int8(clamping: Int(lroundf(rx * 127)))
        s.substickY = Int8(clamping: Int(lroundf(ry * 127)))
        s.triggerLeft = UInt8(clamping: Int(lroundf(lt * 255)))
        s.triggerRight = UInt8(clamping: Int(lroundf(rt * 255)))
        return s
    }

    private func selfTest() {
        let s = ControllerManager.map(
            a: true, b: true, x: false, y: false,
            lShoulder: true, rShoulder: false, menu: true,
            dpadUp: true, dpadDown: false, dpadLeft: false, dpadRight: true,
            lx: 1.0, ly: 1.0, rx: -1.0, ry: -0.5, lt: 0.8, rt: 0.1)
        let want: UInt16 = UInt16(BALLPAD_BUTTON_A) | UInt16(BALLPAD_BUTTON_B)
            | UInt16(BALLPAD_TRIGGER_L) | UInt16(BALLPAD_BUTTON_START)
            | UInt16(BALLPAD_BUTTON_UP) | UInt16(BALLPAD_BUTTON_RIGHT)
        let ok = (s.button & want) == want
            && s.stickX == 127 && s.stickY == 127
            && s.substickX == -127 && s.substickY == -64
            && s.triggerLeft == 204 && s.triggerRight == 26
        NSLog("[controller] selftest btn=0x%04X stick=%d,%d cstick=%d,%d L=%d R=%d ok=%d",
              s.button, s.stickX, s.stickY, s.substickX, s.substickY,
              s.triggerLeft, s.triggerRight, ok ? 1 : 0)
    }
}
