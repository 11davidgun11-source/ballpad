import SwiftUI
import CoreGraphics

enum ControlID: String, Codable, CaseIterable, Identifiable {
    case stick, cStick
    case a, b, x, y, z, start, l, r
    case dpadUp, dpadDown, dpadLeft, dpadRight
    var id: String { rawValue }
}

// GameCube-fidelity skin metadata. Reference: Sunpad's iOS overlay
// (ref/sunpad/apple/ios/SunPadGameOverlay.mm) — A green, B red,
// X blue, Y yellow, C-stick yellow, shoulders/Z/START dark greys. Colors are
// recreated shapes, never ripped textures.
enum ControlSkin {
    static func fill(_ id: ControlID) -> Color {
        switch id {
        case .a: return Color(red: 0.08, green: 0.56, blue: 0.29).opacity(0.92)
        case .b: return Color(red: 0.78, green: 0.10, blue: 0.13).opacity(0.92)
        case .x, .y: return Color(white: 0.72).opacity(0.92)
        case .z: return Color(red: 0.38, green: 0.18, blue: 0.58).opacity(0.94)
        case .start: return Color(white: 0.28).opacity(0.92)
        default: return Color(white: 0.22).opacity(0.88)
        }
    }
    static let moveBase = Color(white: 0.13).opacity(0.86)
    static let moveThumb = Color(white: 0.58).opacity(0.94)
    static let cameraBase = Color(red: 0.91, green: 0.66, blue: 0.08).opacity(0.90)
    static let cameraThumb = Color(red: 1.00, green: 0.84, blue: 0.25).opacity(0.98)
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
    // Sunpad's adaptive layout (layoutSubviews), converted to normalized
    // safe-area coordinates. Sizes in points follow Sunpad: the phone scales
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
        let startW: CGFloat = (pad ? 116.0 : 92.0 * baseScale)
        let startH: CGFloat = small
        let spacing: CGFloat = pad ? 34.0 : 18.0 * baseScale
        func node(_ id: ControlID, _ x: CGFloat, _ y: CGFloat,
                  _ cw: CGFloat, _ ch: CGFloat, _ label: String) -> ControlNode {
            ControlNode(id: id,
                        normX: (x + cw / 2) / w,
                        normY: (y + ch / 2) / h,
                        normW: cw / w,
                        normH: ch / h,
                        label: label)
        }

        let moveX = margin
        let moveY = h - stick - margin
        // Camera stick: bottom-right.
        let camX = w - margin - camera
        let camY = h - margin - camera

        // Match SunPadGameOverlay.layoutSubviews exactly. A anchors against
        // the safe right edge; X sits directly above it, Y above-left, and B
        // down-left. This keeps A out of the X/Y column instead of wedging it
        // underneath two overlapping hit targets.
        let aX = w - margin - large
        let aY = h - margin - camera - large - 18.0 * baseScale
        let aCenterX = aX + large / 2
        let aCenterY = aY + large / 2
        let bX = aX - medium - 12.0 * baseScale
        let bY = aCenterY + 8.0
        let xX = aCenterX - small / 2
        let xY = aY - small - 10.0 * baseScale
        let yX = aX - small - 8.0 * baseScale
        let yY = aY - small + 8.0

        // Sunpad shoulders span the top row and START is centered above the
        // game, leaving the entire face cluster unobstructed.
        let shoulderY = pad ? 92.0 : 68.0 * baseScale
        let lX = margin
        let rX = w - margin - shoulderW
        let zX = rX - small - 12.0 * baseScale
        let startX = (w - startW) / 2
        let startY = margin
        // D-pad: compact 4-button grid right of the move stick.
        let dx = moveX + stick + spacing
        let dy = moveY + stick / 2 - d / 2

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
            node(.start, startX, startY, startW, startH, "START"),
            node(.dpadUp, dx + d, dy - d, d, d, "▲"),
            node(.dpadDown, dx + d, dy + d, d, d, "▼"),
            node(.dpadLeft, dx, dy, d, d, "◀"),
            node(.dpadRight, dx + 2 * d, dy, d, d, "▶"),
        ]
    }
}
