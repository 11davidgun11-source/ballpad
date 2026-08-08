import SwiftUI
import CoreGraphics

enum ControlID: String, Codable, CaseIterable, Identifiable {
    case stick, cStick
    case a, b, x, y, z, start, l, r
    case dpadUp, dpadDown, dpadLeft, dpadRight
    var id: String { rawValue }
}

// GameCube-fidelity skin metadata. Reference: bellpad's iOS overlay
// (ref/bellpad; /Users/chrissotraidis/GitHub/bellpad) — A green, B red,
// X blue, Y yellow, C-stick yellow, shoulders/Z/START dark greys. Colors are
// recreated shapes, never ripped textures.
enum ControlSkin {
    static func fill(_ id: ControlID) -> Color {
        switch id {
        case .a: return Color(red: 0.20, green: 0.72, blue: 0.43)
        case .b: return Color(red: 0.84, green: 0.24, blue: 0.30)
        case .x: return Color(red: 0.30, green: 0.53, blue: 0.88)
        case .y: return Color(red: 0.88, green: 0.64, blue: 0.16)
        case .cStick: return Color(red: 0.95, green: 0.80, blue: 0.12)
        case .z: return Color(white: 0.46)
        case .l, .r: return Color(white: 0.32)
        case .start: return Color(white: 0.28)
        case .dpadUp, .dpadDown, .dpadLeft, .dpadRight: return Color(white: 0.26)
        default: return Color(white: 0.20) // stick well
        }
    }
    // bellpad uses ~0.68-0.76 fill alpha baked into the colors and a 0.76
    // control opacity; we approximate with a uniform 0.76 idle opacity.
    static let idleOpacity: Double = 0.76
    static let activeOpacity: Double = 0.92
}

struct ControlNode: Identifiable, Codable, Equatable {
    var id: ControlID
    var normX: CGFloat // 0...1 left->right (safe area)
    var normY: CGFloat // 0...1 top->bottom (safe area)
    var normW: CGFloat
    var normH: CGFloat
    var label: String
    var scale: CGFloat = 1.0
    var hidden: Bool = false
}

enum DefaultLayouts {
    // bellpad's adaptive layout (LayoutSubviews), converted to normalized
    // safe-area coordinates. Sizes in points follow bellpad: the phone scales
    // controls by min(1, w/800, h/380); the iPad uses fixed larger sizes.
    static func computedPhone(in size: CGSize) -> [ControlNode] {
        layout(in: size, pad: false)
    }
    static func computedPad(in size: CGSize) -> [ControlNode] {
        layout(in: size, pad: true)
    }

    private static func layout(in size: CGSize, pad: Bool) -> [ControlNode] {
        let w = max(size.width, 1)
        let h = max(size.height, 1)
        let baseScale: CGFloat = pad ? 1.0 : min(1.0, min(w / 800.0, h / 380.0))
        let margin: CGFloat = pad ? 34.0 : max(8.0, 18.0 * baseScale)
        let stick: CGFloat = (pad ? 172.0 : 126.0 * baseScale)
        let small: CGFloat = (pad ? 62.0 : 46.0 * baseScale)
        let medium: CGFloat = (pad ? 76.0 : 58.0 * baseScale)
        let large: CGFloat = (pad ? 104.0 : 78.0 * baseScale)
        let camera: CGFloat = (pad ? 112.0 : 86.0 * baseScale)
        let d: CGFloat = (pad ? 48.0 : 36.0 * baseScale)
        let shoulderW: CGFloat = (pad ? 132.0 : 94.0 * baseScale)
        let shoulderH: CGFloat = small
        let shoulderY: CGFloat = pad ? 92.0 : 68.0 * baseScale
        let startW: CGFloat = (pad ? 116.0 : 92.0 * baseScale)
        let startH: CGFloat = small
        let spacing: CGFloat = pad ? 34.0 : 18.0 * baseScale
        let faceGap: CGFloat = pad ? 12.0 : 8.0 * baseScale

        func node(_ id: ControlID, _ x: CGFloat, _ y: CGFloat,
                  _ cw: CGFloat, _ ch: CGFloat, _ label: String) -> ControlNode {
            ControlNode(id: id,
                        normX: (x + cw / 2) / w,
                        normY: (y + ch / 2) / h,
                        normW: cw / w,
                        normH: ch / h,
                        label: label)
        }

        // Move stick: bottom-left.
        let moveX = margin
        let moveY = h - stick - margin
        // Camera stick: bottom-right.
        let camX = w - margin - camera
        let camY = h - margin - camera
        // Face cluster anchored on A (above the camera stick).
        let aX = w - margin - large
        let aY = camY - large - 18.0 * baseScale
        let bX = aX - medium - 12.0 * baseScale
        let bY = aY + 8.0 * baseScale
        let xX = aX + (large - small) / 2
        let xY = aY - small - 10.0 * baseScale
        let yX = aX - small - 8.0 * baseScale
        let yY = aY - small + 8.0 * baseScale
        // Shoulder row.
        let lX = margin
        let rX = w - margin - shoulderW
        let zX = rX - small - 12.0 * baseScale
        // Start: top-center.
        let startX = w / 2 - startW / 2
        // D-pad: compact 4-button grid right of the move stick.
        let dx = moveX + stick + spacing
        let dy = moveY + (stick - d * 3) / 2

        return [
            node(.stick, moveX, moveY, stick, stick, ""),
            node(.cStick, camX, camY, camera, camera, ""),
            node(.a, aX, aY, large, large, "A"),
            node(.b, bX, bY, medium, medium, "B"),
            node(.x, xX, xY, small, small, "X"),
            node(.y, yX, yY, small, small, "Y"),
            node(.l, lX, shoulderY, shoulderW, shoulderH, "L"),
            node(.r, rX, shoulderY, shoulderW, shoulderH, "R"),
            node(.z, zX, shoulderY, small, small, "Z"),
            node(.start, startX, margin, startW, startH, "START"),
            node(.dpadUp, dx + d, dy, d, d, "▲"),
            node(.dpadDown, dx + d, dy + 2 * d, d, d, "▼"),
            node(.dpadLeft, dx, dy + d, d, d, "◀"),
            node(.dpadRight, dx + 2 * d, dy + d, d, d, "▶"),
        ]
    }
}
