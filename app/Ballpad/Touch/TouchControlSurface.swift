import SwiftUI

struct TouchControlSurface: View {
    @ObservedObject var store: LayoutStore
    var editMode: Bool = false
    var onPadChanged: (BallPadStatus) -> Void

    @State private var buttons: Set<ControlID> = []
    @State private var stickVec: CGSize = .zero
    @State private var cStickVec: CGSize = .zero
    @State private var lTrigger: CGFloat = 0
    @State private var rTrigger: CGFloat = 0

    // Fixed logical layout space. Controls are framed/positioned here with
    // constant sizes, and the whole overlay is scaled to the screen.
    private let logicalW: CGFloat = 1000
    private let logicalH: CGFloat = 600

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / logicalW, geo.size.height / logicalH)
            ZStack {
                controlView(node: store.node(.stick), uiScale: scale)
                controlView(node: store.node(.cStick), uiScale: scale)
                controlView(node: store.node(.a), uiScale: scale)
                controlView(node: store.node(.b), uiScale: scale)
                controlView(node: store.node(.x), uiScale: scale)
                controlView(node: store.node(.y), uiScale: scale)
                controlView(node: store.node(.z), uiScale: scale)
                controlView(node: store.node(.l), uiScale: scale)
                controlView(node: store.node(.r), uiScale: scale)
                controlView(node: store.node(.start), uiScale: scale)
                controlView(node: store.node(.dpadUp), uiScale: scale)
                controlView(node: store.node(.dpadDown), uiScale: scale)
                controlView(node: store.node(.dpadLeft), uiScale: scale)
                controlView(node: store.node(.dpadRight), uiScale: scale)
            }
            .frame(width: 1000, height: 600)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onChange(of: buttons) { _, _ in emit() }
            .onChange(of: stickVec) { _, _ in emit() }
            .onChange(of: cStickVec) { _, _ in emit() }
            .onChange(of: lTrigger) { _, _ in emit() }
            .onChange(of: rTrigger) { _, _ in emit() }
        }
        .allowsHitTesting(true)
    }

    // Unified control view: ONE unconditional structure for every control.
    // iPadOS 26 triggers an AttributeGraph layout cycle (detaching the hosting
    // window) for any conditional view structure inside this overlay, so all
    // differentiation (colors, sizes, gestures, active state) is done with
    // value expressions — never if/else view branching.
    private func controlView(node: ControlNode, uiScale: CGFloat) -> some View {
        let scale = node.scale
        let rect = CGRect(
            x: node.normX * logicalW - node.normW * logicalW * scale / 2,
            y: node.normY * logicalH - node.normH * logicalH * scale / 2,
            width: node.normW * logicalW * scale,
            height: node.normH * logicalH * scale
        )
        let isStick = node.id == .stick || node.id == .cStick
        let isTrigger = node.id == .l || node.id == .r
        let isFace = !isStick && !isTrigger
        let fill = ControlSkin.fill(node.id)
        let on = isActive(node.id)
        let vec = activeVec(node.id)
        let hidden = editMode == false && node.hidden
        return ZStack {
            Circle()
                .fill(Color(white: 0.08).opacity(on ? 0.5 : 0.38))
            Circle()
                .strokeBorder(.white.opacity(0.46), lineWidth: 2)
            Circle()
                .fill(fill.opacity(on ? ControlSkin.activeOpacity : ControlSkin.idleOpacity))
                .frame(width: rect.width * 0.42, height: rect.height * 0.42)
                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.4), radius: 3)
                .scaleEffect(on && isFace ? 0.92 : 1.0)
                .offset(isStick ? vec : .zero)
            Text(node.label)
                .font(.system(size: min(rect.width, rect.height) * 0.30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .opacity(hidden ? 0 : 1)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                if isStick {
                    let maxR = min(rect.width, rect.height) * 0.36
                    var dx = value.translation.width / uiScale
                    var dy = value.translation.height / uiScale
                    let mag = sqrt(dx*dx + dy*dy)
                    if mag > maxR { dx *= maxR/mag; dy *= maxR/mag }
                    if node.id == .cStick { cStickVec = CGSize(width: dx, height: dy) }
                    else { stickVec = CGSize(width: dx, height: dy) }
                } else if isTrigger {
                    let rel = (rect.minY - value.location.y / uiScale) / max(rect.height, 1)
                    let v = min(max(rel, 0), 1)
                    if node.id == .l { lTrigger = v } else { rTrigger = v }
                } else {
                    buttons.insert(node.id)
                }
            }
            .onEnded { _ in
                if isStick {
                    if node.id == .cStick { cStickVec = .zero } else { stickVec = .zero }
                } else if isTrigger {
                    if node.id == .l { lTrigger = 0 } else { rTrigger = 0 }
                } else {
                    buttons.remove(node.id)
                }
            }
        )
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
