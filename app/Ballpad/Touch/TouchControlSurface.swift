import SwiftUI

struct TouchControlSurface: View {
    @ObservedObject var store: LayoutStore
    var editMode: Bool = false
    var onPadChanged: (BallPadStatus) -> Void

    @State private var active: [ControlID: CGPoint] = [:]
    @State private var buttons: Set<ControlID> = []
    @State private var stickVec: CGSize = .zero
    @State private var cStickVec: CGSize = .zero
    @State private var dpadVec: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(store.nodes) { node in
                    controlView(node: node, in: geo.size)
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
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func controlView(node: ControlNode, in size: CGSize) -> some View {
        let rect = CGRect(
            x: node.normX * size.width - node.normW * size.width / 2,
            y: node.normY * size.height - node.normH * size.height / 2,
            width: node.normW * size.width,
            height: node.normH * size.height
        )
        if editMode {
            // Layout editor: drag any control to reposition it; no game input.
            return AnyView(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.yellow.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [6]))
                    Text(node.label).font(.caption.bold()).foregroundStyle(.yellow)
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
        switch node.id {
        case .stick, .cStick:
            return AnyView(stick(node: node, rect: rect))
        case .dpad:
            return AnyView(dpad(node: node, rect: rect))
        default:
            return AnyView(button(node: node, rect: rect))
        }
    }

    private func dpad(node: ControlNode, rect: CGRect) -> some View {
        let v = dpadVec
        let on = v != .zero
        return ZStack {
            Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1)
            Circle()
                .fill(.white.opacity(on ? 0.35 : 0.15))
                .frame(width: rect.width * 0.42, height: rect.height * 0.42)
                .offset(v)
            Text(node.label).font(.caption2).foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let maxR = min(rect.width, rect.height) * 0.30
            var dx = value.translation.width
            var dy = value.translation.height
            let mag = sqrt(dx*dx + dy*dy)
            if mag > maxR { dx *= maxR/mag; dy *= maxR/mag }
            // Snap to 4-way so the guest sees clean U/D/L/R presses.
            if abs(dx) > abs(dy) {
                dpadVec = CGSize(width: dx < 0 ? -maxR : maxR, height: 0)
            } else if dy != 0 {
                dpadVec = CGSize(width: 0, height: dy < 0 ? -maxR : maxR)
            } else {
                dpadVec = .zero
            }
        }.onEnded { _ in dpadVec = .zero })
    }

    private func stick(node: ControlNode, rect: CGRect) -> some View {
        let isC = node.id == .cStick
        let vec = isC ? cStickVec : stickVec
        return ZStack {
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 2)
            Circle()
                .fill(.white.opacity(0.25))
                .frame(width: rect.width * 0.42, height: rect.height * 0.42)
                .offset(vec)
            Text(node.label).font(.caption2).foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let maxR = min(rect.width, rect.height) * 0.28
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

    private func button(node: ControlNode, rect: CGRect) -> some View {
        let on = buttons.contains(node.id)
        return ZStack {
            Capsule().fill(on ? Color.white.opacity(0.45) : Color.white.opacity(0.18))
            Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1)
            Text(node.label).font(.caption.bold()).foregroundStyle(.white)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in buttons.insert(node.id) }
            .onEnded { _ in buttons.remove(node.id) }
        )
    }

    private func emit() {
        var s = BallPadStatus()
        s.err = 0
        s.stickX = i8(from: stickVec.width, limit: 70)
        s.stickY = i8(from: -stickVec.height, limit: 70)
        s.substickX = i8(from: cStickVec.width, limit: 70)
        s.substickY = i8(from: -cStickVec.height, limit: 70)
        var btn: UInt16 = 0
        if buttons.contains(.a) { btn |= UInt16(BALLPAD_BUTTON_A) }
        if buttons.contains(.b) { btn |= UInt16(BALLPAD_BUTTON_B) }
        if buttons.contains(.x) { btn |= UInt16(BALLPAD_BUTTON_X) }
        if buttons.contains(.y) { btn |= UInt16(BALLPAD_BUTTON_Y) }
        if buttons.contains(.start) { btn |= UInt16(BALLPAD_BUTTON_START) }
        if buttons.contains(.z) { btn |= UInt16(BALLPAD_TRIGGER_Z) }
        if buttons.contains(.l) { btn |= UInt16(BALLPAD_TRIGGER_L); s.triggerLeft = 255 }
        if buttons.contains(.r) { btn |= UInt16(BALLPAD_TRIGGER_R); s.triggerRight = 255 }
        if dpadVec.width < 0 { btn |= UInt16(BALLPAD_BUTTON_LEFT) }
        if dpadVec.width > 0 { btn |= UInt16(BALLPAD_BUTTON_RIGHT) }
        if dpadVec.height < 0 { btn |= UInt16(BALLPAD_BUTTON_UP) }
        if dpadVec.height > 0 { btn |= UInt16(BALLPAD_BUTTON_DOWN) }
        s.button = btn
        onPadChanged(s)
    }

    private func i8(from v: CGFloat, limit: CGFloat) -> Int8 {
        let clamped = Swift.max(Swift.min(v / limit, 1), -1)
        return Int8(clamping: Int(clamped * 127))
    }
}
