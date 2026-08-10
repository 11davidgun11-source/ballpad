import SwiftUI

struct TouchControlSurface: View {
    @ObservedObject var store: LayoutStore
    var editMode: Bool = false
    var controlScale: CGFloat = 1.0
    var controlOpacity: Double = 0.82
    // C2: a hardware controller is connected -> hide the touch overlay. Folded
    // into the per-control opacity value (the documented-safe pattern): this
    // view must stay ONE unconditional structure with all differentiation as
    // value expressions (iPadOS 26 AttributeGraph cycle otherwise detaches
    // the hosting window).
    var controllerConnected: Bool = false
    @Binding var selectedControl: ControlID?
    var onPadChanged: (BallPadStatus) -> Void

    @State private var buttons: Set<ControlID> = []
    @State private var stickVec: CGSize = .zero
    @State private var cStickVec: CGSize = .zero
    @State private var lTrigger: CGFloat = 0
    @State private var rTrigger: CGFloat = 0
    @State private var stickMaxRadius: CGFloat = 1
    @State private var cStickMaxRadius: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            ZStack {
                controlView(node: store.node(.stick), size: geo.size)
                controlView(node: store.node(.cStick), size: geo.size)
                controlView(node: store.node(.a), size: geo.size)
                controlView(node: store.node(.b), size: geo.size)
                controlView(node: store.node(.x), size: geo.size)
                controlView(node: store.node(.y), size: geo.size)
                controlView(node: store.node(.z), size: geo.size)
                controlView(node: store.node(.l), size: geo.size)
                controlView(node: store.node(.r), size: geo.size)
                controlView(node: store.node(.start), size: geo.size)
                controlView(node: store.node(.dpadUp), size: geo.size)
                controlView(node: store.node(.dpadDown), size: geo.size)
                controlView(node: store.node(.dpadLeft), size: geo.size)
                controlView(node: store.node(.dpadRight), size: geo.size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onChange(of: buttons) { _, _ in emit() }
            .onChange(of: stickVec) { _, _ in emit() }
            .onChange(of: cStickVec) { _, _ in emit() }
            .onChange(of: lTrigger) { _, _ in emit() }
            .onChange(of: rTrigger) { _, _ in emit() }
            .onAppear {
                DispatchQueue.main.async { store.updateCanvas(geo.size) }
            }
            .onChange(of: geo.size) { _, newSize in
                DispatchQueue.main.async { store.updateCanvas(newSize) }
            }
        }
        .allowsHitTesting(!controllerConnected)
    }

    // Unified control view: ONE unconditional structure for every control.
    // iPadOS 26 triggers an AttributeGraph layout cycle (detaching the hosting
    // window) for any conditional view structure inside this overlay, so all
    // differentiation (colors, sizes, shapes, gestures, active state) is done
    // with value expressions — never if/else view branching. Each Sunpad
    // shape (stick well+thumb, shoulder plate, Z plate, START pill, face
    // circle, D-pad key) is always in the ZStack and gated by .opacity().
    private func controlView(node: ControlNode, size: CGSize) -> some View {
        let scale = node.scale * controlScale
        let rect = CGRect(
            x: node.normX * size.width - node.normW * size.width * scale / 2,
            y: node.normY * size.height - node.normH * size.height * scale / 2,
            width: node.normW * size.width * scale,
            height: node.normH * size.height * scale
        )
        let isStick = node.id == .stick || node.id == .cStick
        let isTrigger = node.id == .l || node.id == .r
        let fill = ControlSkin.fill(node.id)
        let on = isActive(node.id)
        let vec = activeVec(node.id)
        let hidden = controllerConnected || (editMode == false && node.hidden)
        let inputRadius = node.id == .cStick ? cStickMaxRadius : stickMaxRadius
        let visualTravel = max(0, min(rect.width, rect.height) * 0.29 - 3)
        let displayVec = isStick
            ? CGSize(width: vec.width / max(inputRadius, 1) * visualTravel,
                     height: vec.height / max(inputRadius, 1) * visualTravel)
            : .zero
        let stickBase = node.id == .cStick ? ControlSkin.cameraBase : ControlSkin.moveBase
        let stickThumb = node.id == .cStick ? ControlSkin.cameraThumb : ControlSkin.moveThumb
        let corner = min(rect.width, rect.height) * 0.5
        return ZStack {
            // Sunpad stick wells: movement is charcoal; C-stick is yellow.
            Circle()
                .fill(stickBase)
                .opacity(isStick ? 1 : 0)
            Circle()
                .strokeBorder(.white.opacity(0.68), lineWidth: 2)
                .opacity(isStick ? 1 : 0)
            Circle()
                .fill(stickThumb)
                .frame(width: rect.width * 0.42, height: rect.height * 0.42)
                .offset(displayVec)
                .opacity(isStick ? 1 : 0)
            // Sunpad gives every UIButton maximum-radius rounding: squares
            // become circles while shoulders and START become full pills.
            RoundedRectangle(cornerRadius: corner)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(.white.opacity(0.68), lineWidth: 2))
                .frame(width: rect.width, height: rect.height)
                .scaleEffect(on && !isStick ? 0.92 : 1.0)
                .opacity(isStick ? 0 : 1)
            // Layout-editor chrome: yellow dashed outline + drag-to-move,
            // always in the tree but only visible in edit mode.
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selectedControl == node.id ? .cyan : .yellow.opacity(0.9),
                              style: StrokeStyle(lineWidth: selectedControl == node.id ? 4 : 3,
                                                 dash: [6]))
                .frame(width: rect.width, height: rect.height)
                .opacity(editMode ? 1 : 0)
            // Label.
            Text(node.label)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(node.id == .x || node.id == .y ? .black : .white)
                .opacity(isStick ? 0 : 1)
        }
        .frame(width: rect.width, height: rect.height)
        // Match UIButton's full rectangular hit target. The visible maximum
        // corner radius still makes square controls circular and shoulders
        // pill-shaped, but taps near a pill's ends must not be discarded.
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                if ProcessInfo.processInfo.environment["BALLPAD_TOUCH_LOG"] != nil {
                    NSLog("[touch] %@ loc=%.0f,%.0f rect=%.0f,%.0f %.0fx%.0f start=%.0f,%.0f",
                          node.id.rawValue,
                          value.location.x, value.location.y,
                          rect.minX, rect.minY, rect.width, rect.height,
                          value.startLocation.x, value.startLocation.y)
                }
                if editMode {
                    selectedControl = node.id
                    store.move(id: node.id,
                               to: CGPoint(x: rect.midX + value.translation.width,
                                           y: rect.midY + value.translation.height),
                               in: size)
                } else if isStick {
                    let maxR = min(rect.width, rect.height) * 0.5
                    var dx = value.location.x - rect.width / 2
                    var dy = value.location.y - rect.height / 2
                    let mag = sqrt(dx*dx + dy*dy)
                    if mag > maxR { dx *= maxR/mag; dy *= maxR/mag }
                    if node.id == .cStick {
                        cStickMaxRadius = maxR
                        cStickVec = CGSize(width: dx, height: dy)
                    } else {
                        stickMaxRadius = maxR
                        stickVec = CGSize(width: dx, height: dy)
                    }
                } else if isTrigger {
                    // Sunpad-style shoulders: a tap is a complete GameCube
                    // trigger press. Strikers actions must not require an
                    // upward swipe or a precise hit near the top edge.
                    if node.id == .l { lTrigger = 1 } else { rTrigger = 1 }
                } else {
                    buttons.insert(node.id)
                }
            }
            .onEnded { _ in
                if editMode {
                    store.save()
                } else if isStick {
                    if node.id == .cStick { cStickVec = .zero } else { stickVec = .zero }
                } else if isTrigger {
                    if node.id == .l { lTrigger = 0 } else { rTrigger = 0 }
                } else {
                    buttons.remove(node.id)
                }
            }
        )
        // Position AFTER the frame + gesture so the drag hit area stays
        // bounded to the control (a touch anywhere on the container used to
        // fire every control's gesture — A3 finding, docs/09 2026-08-08).
        .position(x: rect.midX, y: rect.midY)
        .opacity(hidden ? 0 : (editMode ? 1 : controlOpacity))
        .accessibilityLabel(node.label.isEmpty ?
                            (node.id == .stick ? "Move stick" : "C stick") : node.label)
        .accessibilityIdentifier("control.\(node.id.rawValue)")
    }

    private func isActive(_ id: ControlID) -> Bool {
        switch id {
        case .stick: return stickVec != .zero
        case .cStick: return cStickVec != .zero
        case .l: return lTrigger > 0
        case .r: return rTrigger > 0
        default: return buttons.contains(id)
        }
    }

    private func activeVec(_ id: ControlID) -> CGSize {
        switch id {
        case .stick: return stickVec
        case .cStick: return cStickVec
        default: return .zero
        }
    }

    // Stick output: deadzone 0.12 of radius, linear curve, clamp [-127,127].
    private func emit() {
        var s = BallPadStatus()
        s.err = 0
        s.stickX = stickAxis(stickVec.width, radius: stickMaxRadius)
        s.stickY = stickAxis(-stickVec.height, radius: stickMaxRadius)
        s.substickX = stickAxis(cStickVec.width, radius: cStickMaxRadius)
        s.substickY = stickAxis(-cStickVec.height, radius: cStickMaxRadius)
        s.triggerLeft = triggerByte(lTrigger)
        s.triggerRight = triggerByte(rTrigger)
        var btn: UInt16 = 0
        if buttons.contains(.a) { btn |= UInt16(BALLPAD_BUTTON_A) }
        if buttons.contains(.b) { btn |= UInt16(BALLPAD_BUTTON_B) }
        if buttons.contains(.x) { btn |= UInt16(BALLPAD_BUTTON_X) }
        if buttons.contains(.y) { btn |= UInt16(BALLPAD_BUTTON_Y) }
        if buttons.contains(.start) { btn |= UInt16(BALLPAD_BUTTON_START) }
        if buttons.contains(.z) { btn |= UInt16(BALLPAD_TRIGGER_Z) }
        if lTrigger >= 180.0 / 255.0 { btn |= UInt16(BALLPAD_TRIGGER_L) }
        if rTrigger >= 180.0 / 255.0 { btn |= UInt16(BALLPAD_TRIGGER_R) }
        if buttons.contains(.dpadLeft) { btn |= UInt16(BALLPAD_BUTTON_LEFT) }
        if buttons.contains(.dpadRight) { btn |= UInt16(BALLPAD_BUTTON_RIGHT) }
        if buttons.contains(.dpadUp) { btn |= UInt16(BALLPAD_BUTTON_UP) }
        if buttons.contains(.dpadDown) { btn |= UInt16(BALLPAD_BUTTON_DOWN) }
        s.button = btn
        onPadChanged(s)
    }

    private func stickAxis(_ v: CGFloat, radius: CGFloat) -> Int8 {
        let norm = Swift.max(Swift.min(v / max(radius, 1), 1), -1)
        let mag = Swift.abs(norm)
        let dz: CGFloat = 0.12
        guard mag > dz else { return 0 }
        let scaled = (mag - dz) / (1 - dz)
        return Int8(clamping: Int((norm >= 0 ? scaled : -scaled) * 127))
    }

    private func triggerByte(_ v: CGFloat) -> UInt8 {
        UInt8(clamping: Int(v * 255))
    }
}
