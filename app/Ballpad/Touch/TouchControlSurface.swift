import SwiftUI

struct TouchControlSurface: View {
    @ObservedObject var store: LayoutStore
    var editMode: Bool = false
    var onPadChanged: (BallPadStatus) -> Void

    @State private var buttons: Set<ControlID> = []
    @State private var stickVec: CGSize = .zero
    @State private var cStickVec: CGSize = .zero
    @State private var dpadVec: CGSize = .zero
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
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in }
            )
            .onChange(of: buttons) { _, _ in emit() }
            .onChange(of: stickVec) { _, _ in emit() }
            .onChange(of: cStickVec) { _, _ in emit() }
            .onChange(of: dpadVec) { _, _ in emit() }
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
            // Layout editor: drag any control to reposition it; no game input.
            return AnyView(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.yellow.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [6]))
                    Text(node.label.isEmpty ? node.id.rawValue : node.label).font(.caption.bold()).foregroundStyle(.yellow)
                    // Corner scale handle (docs/05 §5): drag bottom-right to
                    // resize 0.6x-1.8x.
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
        let on = isActive(node.id)
        let opacity = on ? ControlSkin.activeOpacity(node.id) : ControlSkin.idleOpacity(node.id)
        switch node.id {
        case .stick, .cStick:
            return AnyView(stick(node: node, rect: rect, fill: fill, opacity: opacity))
        case .dpad:
            return AnyView(dpad(node: node, rect: rect, opacity: opacity))
        case .l, .r:
            return AnyView(trigger(node: node, rect: rect, fill: fill, opacity: opacity))
        default:
            return AnyView(button(node: node, rect: rect, fill: fill, opacity: opacity))
        }
    }

    private func isActive(_ id: ControlID) -> Bool {
        switch id {
        case .stick: return stickVec != .zero
        case .cStick: return cStickVec != .zero
        case .dpad: return dpadVec != .zero
        case .l: return lTrigger > 0
        case .r: return rTrigger > 0
        default: return buttons.contains(id)
        }
    }

    // 8-way D-pad with center deadzone (docs/05 §4.4).
    private func dpad(node: ControlNode, rect: CGRect, opacity: Double) -> some View {
        let v = dpadVec
        let on = v != .zero
        let crossW = rect.width * 0.30
        return ZStack {
            RoundedRectangle(cornerRadius: crossW / 2)
                .fill(.white.opacity(on ? 0.45 : 0.22))
                .frame(width: rect.width, height: crossW)
            RoundedRectangle(cornerRadius: crossW / 2)
                .fill(.white.opacity(on ? 0.45 : 0.22))
                .frame(width: crossW, height: rect.height)
            Circle()
                .fill(.white.opacity(on ? 0.5 : 0))
                .frame(width: rect.width * 0.28, height: rect.height * 0.28)
                .offset(v)
            Text(node.label).font(.caption2).foregroundStyle(.white.opacity(0.8))
        }
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.35), lineWidth: 1))
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let maxR = min(rect.width, rect.height) * 0.38
            var dx = value.translation.width
            var dy = value.translation.height
            let mag = sqrt(dx*dx + dy*dy)
            if mag < maxR * 0.25 {
                dpadVec = .zero
                return
            }
            if mag > maxR { dx *= maxR/mag; dy *= maxR/mag }
            // Snap to the nearest of 8 directions (22.5 deg bins).
            let deg = atan2(dy, dx) * 180 / .pi
            var dir: CGSize = .zero
            if deg >= -22.5 && deg < 22.5 {
                dir = CGSize(width: maxR, height: 0)
            } else if deg >= 22.5 && deg < 67.5 {
                dir = CGSize(width: maxR * 0.707, height: maxR * 0.707)
            } else if deg >= 67.5 && deg < 112.5 {
                dir = CGSize(width: 0, height: maxR)
            } else if deg >= 112.5 && deg < 157.5 {
                dir = CGSize(width: -maxR * 0.707, height: maxR * 0.707)
            } else if deg >= 157.5 || deg < -157.5 {
                dir = CGSize(width: -maxR, height: 0)
            } else if deg >= -157.5 && deg < -112.5 {
                dir = CGSize(width: -maxR * 0.707, height: -maxR * 0.707)
            } else if deg >= -112.5 && deg < -67.5 {
                dir = CGSize(width: 0, height: -maxR)
            } else {
                dir = CGSize(width: maxR * 0.707, height: -maxR * 0.707)
            }
            dpadVec = dir
        }.onEnded { _ in dpadVec = .zero })
    }

    // Analog stick: octagonal well + knob, deadzone 0.12, curve gamma 1.2.
    private func stick(node: ControlNode, rect: CGRect, fill: Color, opacity: Double) -> some View {
        let isC = node.id == .cStick
        let vec = isC ? cStickVec : stickVec
        return ZStack {
            OctagonShape().strokeBorder(.white.opacity(0.45), lineWidth: 2)
            OctagonShape().fill(.black.opacity(0.35))
            Circle()
                .fill(fill.opacity(opacity))
                .frame(width: rect.width * 0.44, height: rect.height * 0.44)
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

    // Analog shoulder trigger: vertical slide, rest 0, full travel 1 (docs/05
    // §4.3). Digital bit sets at 180/255.
    private func trigger(node: ControlNode, rect: CGRect, fill: Color, opacity: Double) -> some View {
        let isL = node.id == .l
        let value = isL ? lTrigger : rTrigger
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 10)
                .fill(fill.opacity(opacity))
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.35))
                .frame(height: rect.height * value)
            VStack {
                Text(isL ? "L" : "R").font(.caption.bold()).foregroundStyle(.white)
                Spacer()
            }
            .padding(.top, 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.6), lineWidth: 1.5))
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            // Slide up = press. Value from the finger's offset within the plate.
            let rel = (rect.minY - value.location.y) / max(rect.height, 1)
            let v = min(max(rel, 0), 1)
            if isL { lTrigger = v } else { rTrigger = v }
        }.onEnded { _ in
            if isL { lTrigger = 0 } else { rTrigger = 0 }
        })
    }

    // Face buttons: A big circle, B smaller offset circle, X/Y lozenges,
    // Z rectangle, START pill.
    private func button(node: ControlNode, rect: CGRect, fill: Color, opacity: Double) -> some View {
        let on = buttons.contains(node.id)
        let activeOpacity = on ? ControlSkin.activeOpacity(node.id) : opacity
        let body: AnyView
        switch node.id {
        case .a, .b:
            body = AnyView(
                Circle()
                    .fill(fill.opacity(activeOpacity))
                    .overlay(Circle().strokeBorder(.white.opacity(0.75), lineWidth: 2))
            )
        case .x, .y:
            body = AnyView(
                RoundedRectangle(cornerRadius: rect.width * 0.18)
                    .fill(fill.opacity(activeOpacity))
                    .rotationEffect(.degrees(45))
                    .overlay(
                        RoundedRectangle(cornerRadius: rect.width * 0.18)
                            .strokeBorder(.white.opacity(0.75), lineWidth: 2)
                            .rotationEffect(.degrees(45))
                    )
            )
        case .start:
            body = AnyView(
                Capsule()
                    .fill(fill.opacity(activeOpacity))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.75), lineWidth: 1.5))
            )
        default:
            body = AnyView(
                RoundedRectangle(cornerRadius: 8)
                    .fill(fill.opacity(activeOpacity))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.75), lineWidth: 1.5))
            )
        }
        return ZStack {
            body
                .frame(width: rect.width, height: rect.height)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 2)
            Text(node.label)
                .font(.system(size: min(rect.width, rect.height) * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: rect.width * 1.25, height: rect.height * 1.25) // generous hit target
        .position(x: rect.midX, y: rect.midY)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in buttons.insert(node.id) }
            .onEnded { _ in buttons.remove(node.id) }
        )
    }

    // Stick output: deadzone 0.12 of radius, curve gamma 1.2, clamp [-127,127].
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
        if dpadVec.width < 0 { btn |= UInt16(BALLPAD_BUTTON_LEFT) }
        if dpadVec.width > 0 { btn |= UInt16(BALLPAD_BUTTON_RIGHT) }
        if dpadVec.height < 0 { btn |= UInt16(BALLPAD_BUTTON_UP) }
        if dpadVec.height > 0 { btn |= UInt16(BALLPAD_BUTTON_DOWN) }
        s.button = btn
        onPadChanged(s)
    }

    private func stickAxis(_ v: CGFloat) -> Int8 {
        // v is in points; normalize by a nominal full deflection of ~60pt,
        // then apply deadzone + curve.
        let norm = Swift.max(Swift.min(v / 60.0, 1), -1)
        let mag = Swift.abs(norm)
        let dz: CGFloat = 0.12
        guard mag > dz else { return 0 }
        let curved = pow((mag - dz) / (1 - dz), 1.2)
        return Int8(clamping: Int((norm >= 0 ? curved : -curved) * 127))
    }

    private func triggerByte(_ v: CGFloat) -> UInt8 {
        UInt8(clamping: Int(v * 255))
    }
}

// Octagonal well for the analog sticks.
struct OctagonShape: InsettableShape {
    var insetAmount: CGFloat = 0
    func inset(by amount: CGFloat) -> OctagonShape {
        var s = self
        s.insetAmount += amount
        return s
    }
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2 - insetAmount
        let cx = rect.midX
        let cy = rect.midY
        let s = r * 0.4142 // octagon edge offset
        var p = Path()
        p.move(to: CGPoint(x: cx - s, y: cy - r))
        p.addLine(to: CGPoint(x: cx + s, y: cy - r))
        p.addLine(to: CGPoint(x: cx + r, y: cy - s))
        p.addLine(to: CGPoint(x: cx + r, y: cy + s))
        p.addLine(to: CGPoint(x: cx + s, y: cy + r))
        p.addLine(to: CGPoint(x: cx - s, y: cy + r))
        p.addLine(to: CGPoint(x: cx - r, y: cy + s))
        p.addLine(to: CGPoint(x: cx - r, y: cy - s))
        p.closeSubpath()
        return p
    }
}
