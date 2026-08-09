import SwiftUI

struct TouchControlSurface: View {
    @ObservedObject var store: LayoutStore
    var editMode: Bool = false
    var controlScale: CGFloat = 1.0
    var controlOpacity: Double = 0.76
    // C2: a hardware controller is connected -> hide the touch overlay. Folded
    // into the per-control opacity value (the documented-safe pattern): this
    // view must stay ONE unconditional structure with all differentiation as
    // value expressions (iPadOS 26 AttributeGraph cycle otherwise detaches
    // the hosting window).
    var controllerConnected: Bool = false
    var onPadChanged: (BallPadStatus) -> Void

    @State private var buttons: Set<ControlID> = []
    @State private var stickVec: CGSize = .zero
    @State private var cStickVec: CGSize = .zero
    @State private var lTrigger: CGFloat = 0
    @State private var rTrigger: CGFloat = 0

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
        }
        .allowsHitTesting(!controllerConnected)
    }

    // Unified control view: ONE unconditional structure for every control.
    // iPadOS 26 triggers an AttributeGraph layout cycle (detaching the hosting
    // window) for any conditional view structure inside this overlay, so all
    // differentiation (colors, sizes, shapes, gestures, active state) is done
    // with value expressions — never if/else view branching. Each bellpad
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
        let isStart = node.id == .start
        let isZ = node.id == .z
        let isFace = !isStick && !isTrigger && !isStart && !isZ
        let fill = ControlSkin.fill(node.id)
        let on = isActive(node.id)
        let vec = activeVec(node.id)
        let trigVal = triggerValue(node.id)
        let hidden = controllerConnected || (editMode == false && node.hidden)
        let shapeOpacity = on ? min(0.95, controlOpacity + 0.2) : controlOpacity
        let labelSize = min(rect.width, rect.height) * 0.30
        return ZStack {
            // Stick well (dark) + white border.
            Circle()
                .fill(Color(white: 0.08).opacity(shapeOpacity))
                .opacity(isStick ? 1 : 0)
            Circle()
                .strokeBorder(.white.opacity(0.46), lineWidth: 2)
                .opacity(isStick ? 1 : 0)
            // Stick thumb.
            Circle()
                .fill(fill.opacity(on ? ControlSkin.activeOpacity : ControlSkin.idleOpacity))
                .frame(width: rect.width * 0.42, height: rect.height * 0.42)
                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.4), radius: 3)
                .offset(isStick ? vec : .zero)
                .opacity(isStick ? 1 : 0)
            // Shoulder trigger plate + analog fill.
            RoundedRectangle(cornerRadius: rect.height * 0.25)
                .fill(fill.opacity(shapeOpacity))
                .overlay(RoundedRectangle(cornerRadius: rect.height * 0.25)
                    .strokeBorder(.white.opacity(0.42), lineWidth: 1.5))
                .frame(width: rect.width, height: rect.height)
                .opacity(isTrigger ? 1 : 0)
            RoundedRectangle(cornerRadius: rect.height * 0.25)
                .fill(.white.opacity(0.35))
                .frame(width: rect.width, height: max(rect.height * trigVal, 0))
                .frame(height: rect.height, alignment: .bottom)
                .opacity(isTrigger ? 1 : 0)
            // Z plate.
            RoundedRectangle(cornerRadius: 8)
                .fill(fill.opacity(shapeOpacity))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.42), lineWidth: 1.5))
                .frame(width: rect.width, height: rect.height)
                .opacity(isZ ? 1 : 0)
            // START pill.
            Capsule()
                .fill(fill.opacity(shapeOpacity))
                .overlay(Capsule().strokeBorder(.white.opacity(0.42), lineWidth: 1.5))
                .frame(width: rect.width, height: rect.height)
                .opacity(isStart ? 1 : 0)
            // Face / D-pad circles.
            Circle()
                .fill(fill.opacity(shapeOpacity))
                .overlay(Circle().strokeBorder(.white.opacity(0.38), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 2)
                .frame(width: rect.width, height: rect.height)
                .scaleEffect(on && isFace ? 0.92 : 1.0)
                .opacity(isFace ? 1 : 0)
            // Layout-editor chrome: yellow dashed outline + drag-to-move,
            // always in the tree but only visible in edit mode.
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.yellow.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [6]))
                .frame(width: rect.width, height: rect.height)
                .opacity(editMode ? 1 : 0)
            // Label.
            Text(node.label)
                .font(.system(size: labelSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .opacity(editMode ? 1 : (isStick ? 0.85 : 1))
        }
        .frame(width: rect.width, height: rect.height)
        .contentShape(Circle())
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
                    store.move(id: node.id,
                               to: CGPoint(x: rect.midX + value.translation.width,
                                           y: rect.midY + value.translation.height),
                               in: size)
                } else if isStick {
                    let maxR = min(rect.width, rect.height) * 0.36
                    var dx = value.translation.width
                    var dy = value.translation.height
                    let mag = sqrt(dx*dx + dy*dy)
                    if mag > maxR { dx *= maxR/mag; dy *= maxR/mag }
                    if node.id == .cStick { cStickVec = CGSize(width: dx, height: dy) }
                    else { stickVec = CGSize(width: dx, height: dy) }
                } else if isTrigger {
                    let rel = (rect.minY - value.location.y) / max(rect.height, 1)
                    let v = min(max(rel, 0), 1)
                    if node.id == .l { lTrigger = v } else { rTrigger = v }
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
        .opacity(hidden ? 0 : 1)
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

    private func triggerValue(_ id: ControlID) -> CGFloat {
        switch id {
        case .l: return lTrigger
        case .r: return rTrigger
        default: return 0
        }
    }

    // Stick output: deadzone 0.12 of radius, linear curve, clamp [-127,127].
    private func emit() {
        var s = BallPadStatus()
        s.err = 0
        s.stickX = stickAxis(stickVec.width)
        s.stickY = stickAxis(-stickVec.height)
        s.substickX = stickAxis(cStickVec.width)
        s.substickY = stickAxis(-cStickVec.height)
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

    private func stickAxis(_ v: CGFloat) -> Int8 {
        let norm = Swift.max(Swift.min(v / 60.0, 1), -1)
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
