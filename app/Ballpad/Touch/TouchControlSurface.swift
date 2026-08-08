import SwiftUI

struct TouchControlSurface: View {
    @ObservedObject var store: LayoutStore
    var editMode: Bool = false
    var onPadChanged: (BallPadStatus) -> Void

    @State private var buttons: Set<ControlID> = []
    @State private var stickVec: CGSize = .zero
    @State private var cStickVec: CGSize = .zero
    @State private var lTrigger: CGFloat = 0   // 0...1
    @State private var rTrigger: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(store.nodes) { node in
                    if !(editMode == false && node.hidden) {
                        controlView(node: node, in: geo.size)
                    }
                }
            }
            .contentShape(Rectangle())
            .onChange(of: buttons) { _, _ in emit() }
            .onChange(of: stickVec) { _, _ in emit() }
            .onChange(of: cStickVec) { _, _ in emit() }
            .onChange(of: lTrigger) { _, _ in emit() }
            .onChange(of: rTrigger) { _, _ in emit() }
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func controlView(node: ControlNode, in size: CGSize) -> some View {
        let scale = node.scale
        let rect = CGRect(
            x: node.normX * size.width - node.normW * size.width * scale / 2,
            y: node.normY * size.height - node.normH * size.height * scale / 2,
            width: node.normW * size.width * scale,
            height: node.normH * size.height * scale
        )
        if editMode {
            return AnyView(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.yellow.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [6]))
                    Text(node.label.isEmpty ? node.id.rawValue : node.label)
                        .font(.caption.bold()).foregroundStyle(.yellow)
                    Circle()
                        .fill(.yellow)
                        .frame(width: 18, height: 18)
                        .overlay(Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.black))
                        .position(x: rect.maxX, y: rect.maxY)
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let startW = node.normW * size.width * node.scale
                                let startH = node.normH * size.height * node.scale
                                let newW = max(startW + value.translation.width, 44)
                                let newH = max(startH + value.translation.height, 44)
                                store.setScale(id: node.id,
                                               max(newW / startW, newH / startH) * node.scale)
                            })
                }
                .frame(width: max(rect.width, 64), height: max(rect.height, 44))
                .position(x: rect.midX, y: rect.midY)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        store.move(id: node.id,
                                   to: CGPoint(x: rect.midX + value.translation.width,
                                               y: rect.midY + value.translation.height),
                                   in: size)
                    })
            )
        }
        let fill = ControlSkin.fill(node.id)
        switch node.id {
        case .stick, .cStick:
            return AnyView(stick(node: node, rect: rect, fill: fill))
        case .l, .r:
            return AnyView(trigger(node: node, rect: rect, fill: fill))
        default:
            return AnyView(button(node: node, rect: rect, fill: fill))
        }
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

    // bellpad-style analog stick: circular dark well, white border, thumb.
    // Output maps linearly to [-127,127] (deadzone 0.12 applied in emit).
    private func stick(node: ControlNode, rect: CGRect, fill: Color) -> some View {
        let isC = node.id == .cStick
        let vec = isC ? cStickVec : stickVec
        let on = vec != .zero
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
                .offset(vec)
            Text(node.label).font(.caption2).foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let maxR = min(rect.width, rect.height) * 0.36
            var dx = value.translation.width
            var dy = value.translation.height
            let mag = sqrt(dx*dx + dy*dy)
            if mag > maxR { dx *= maxR/mag; dy *= maxR/mag }
            if isC { cStickVec = CGSize(width: dx, height: dy) }
            else { stickVec = CGSize(width: dx, height: dy) }
        }.onEnded { _ in
            if isC { cStickVec = .zero } else { stickVec = .zero }
        })
    }

    // Analog shoulder trigger: vertical slide, rest 0, full travel 1.
    // Digital bit sets at 180/255 (docs/05 §4.3).
    private func trigger(node: ControlNode, rect: CGRect, fill: Color) -> some View {
        let isL = node.id == .l
        let value = isL ? lTrigger : rTrigger
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 10)
                .fill(fill.opacity(ControlSkin.idleOpacity))
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.35))
                .frame(height: rect.height * value)
            VStack {
                Text(isL ? "L" : "R").font(.caption.bold()).foregroundStyle(.white)
                Spacer()
            }
            .padding(.top, 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.42), lineWidth: 1.5))
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let rel = (rect.minY - value.location.y) / max(rect.height, 1)
            let v = min(max(rel, 0), 1)
            if isL { lTrigger = v } else { rTrigger = v }
        }.onEnded { _ in
            if isL { lTrigger = 0 } else { rTrigger = 0 }
        })
    }

    // Face buttons + D-pad keys: bellpad-style round caps, press animation
    // (0.92 scale), white bold label, white 0.38 border.
    private func button(node: ControlNode, rect: CGRect, fill: Color) -> some View {
        let on = isActive(node.id)
        let opacity = on ? ControlSkin.activeOpacity : ControlSkin.idleOpacity
        let label = node.label
        return ZStack {
            Circle()
                .fill(fill.opacity(opacity))
                .overlay(Circle().strokeBorder(.white.opacity(0.38), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 2)
                .scaleEffect(on ? 0.92 : 1.0)
            Text(label)
                .font(.system(size: min(rect.width, rect.height) * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in buttons.insert(node.id) }
            .onEnded { _ in buttons.remove(node.id) }
        )
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
