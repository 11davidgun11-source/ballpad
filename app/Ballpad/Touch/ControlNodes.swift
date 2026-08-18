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
    // SunPad's adaptive layout (SunPadGameOverlay.layoutSubviews), converted
    // to normalized safe-area coordinates. The reference has deliberately
    // different default anchors for phone and iPad; do not replace these with
    // the generic edge-pinned fallback just because it looks more symmetric.
    // Sizes in points follow SunPad: the phone scales controls by
    // min(1, w/800, h/380); the large iPad uses fixed larger sizes.
    static func computedPhone(in size: CGSize) -> [ControlNode] {
        layout(in: size, pad: false)
    }
    static func computedPad(in size: CGSize) -> [ControlNode] {
        layout(in: size, pad: true)
    }

    private static func layout(in size: CGSize, pad: Bool) -> [ControlNode] {
        let w = max(size.width, 1)
        let h = max(size.height, 1)
        // SunPad uses its fixed iPad profile only on the large landscape
        // canvas. A compact Split View iPad follows the scalable fallback.
        let largePad = pad && w >= 1000.0
        let baseScale: CGFloat = largePad ? 1.0 : min(1.0, min(w / 800.0, h / 380.0))
        let margin: CGFloat = largePad ? 34.0 : max(8.0, 18.0 * baseScale)
        let stick: CGFloat = (largePad ? 172.0 : 126.0 * baseScale)
        let small: CGFloat = (largePad ? 62.0 : 46.0 * baseScale)
        let medium: CGFloat = (largePad ? 76.0 : 58.0 * baseScale)
        let large: CGFloat = (largePad ? 104.0 : 78.0 * baseScale)
        let camera: CGFloat = (largePad ? 112.0 : 86.0 * baseScale)
        let d: CGFloat = (largePad ? 48.0 : 36.0 * baseScale)
        let shoulderW: CGFloat = (largePad ? 132.0 : 94.0 * baseScale)
        let shoulderH: CGFloat = small
        let rightShoulderW = shoulderW + 2.0 * small + 24.0 * baseScale
        let startW: CGFloat = (largePad ? 116.0 : 92.0 * baseScale)
        let startH: CGFloat = small
        func node(_ id: ControlID, _ x: CGFloat, _ y: CGFloat,
                  _ cw: CGFloat, _ ch: CGFloat, _ label: String,
                  scale: CGFloat = 1.0) -> ControlNode {
            ControlNode(id: id,
                        normX: (x + cw / 2) / w,
                        normY: (y + ch / 2) / h,
                        normW: cw / w,
                        normH: ch / h,
                        label: label,
                        scale: scale)
        }
        func nodeAt(_ id: ControlID, _ centerX: CGFloat, _ centerY: CGFloat,
                    _ cw: CGFloat, _ ch: CGFloat, _ label: String,
                    scale: CGFloat = 1.0) -> ControlNode {
            ControlNode(id: id,
                        normX: centerX,
                        normY: centerY,
                        normW: cw / w,
                        normH: ch / h,
                        label: label,
                        scale: scale)
        }

        // The scalable fallback is retained for nonstandard compact canvases.
        let moveX = margin
        let moveY = h - stick - margin
        let camX = w - margin - camera
        let camY = h - margin - camera
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

        let shoulderY = largePad ? 92.0 : 68.0 * baseScale
        let lX = margin
        let rX = w - margin - rightShoulderW
        let zX = w - margin - shoulderW - small - 12.0 * baseScale
        let startX = (w - startW) / 2
        let startY = margin
        let dx = moveX + stick + (largePad ? 34.0 : 18.0 * baseScale)
        let dy = moveY + stick / 2 - d / 2

        if !largePad && !pad {
            // These phone defaults are the exact normalized SunPad anchors,
            // including its larger B control and the shared R/Z touch plate.
            let dpadX: CGFloat = 0.0812777778
            let dpadY: CGFloat = 0.4677364865
            return [
                nodeAt(.stick, 0.1234722222, 0.7803490991, stick, stick, ""),
                nodeAt(.cStick, 0.9233055556, 0.8130067568, camera, camera, ""),
                node(.a, aX, aY, large, large, "A"),
                nodeAt(.b, 0.8398611111, 0.6898648649, medium, medium, "B",
                       scale: 1.158457040786743),
                nodeAt(.x, 0.9034166667, 0.4258445946, small, small, "X"),
                nodeAt(.y, 0.8452500000, 0.5268581081, small, small, "Y"),
                nodeAt(.l, 0.0905833333, 0.2539977477, shoulderW, shoulderH, "L"),
                nodeAt(.r, 0.8687500000, 0.2729166667, rightShoulderW, shoulderH, "R"),
                nodeAt(.z, 0.9712500000, 0.4350788288, small, small, "Z"),
                nodeAt(.start, 0.0902222222, 0.1128941441, startW, startH, "START"),
                nodeAt(.dpadUp, dpadX, dpadY - d / h, d, d, "▲"),
                nodeAt(.dpadDown, dpadX, dpadY + d / h, d, d, "▼"),
                nodeAt(.dpadLeft, dpadX - d / w, dpadY, d, d, "◀"),
                nodeAt(.dpadRight, dpadX + d / w, dpadY, d, d, "▶"),
            ]
        }

        if largePad {
            // Exact large-iPad SunPad anchors. They intentionally keep the
            // face cluster and menu actions clear of the broader left stick.
            let dpadX: CGFloat = 0.2686676428
            let dpadY: CGFloat = 0.7947259566
            return [
                nodeAt(.stick, 0.1310395315, 0.7905894519, stick, stick, ""),
                nodeAt(.cStick, 0.9062957540, 0.8583247156, camera, camera, ""),
                nodeAt(.a, 0.8916544656, 0.7409513961, large, large, "A"),
                nodeAt(.b, 0.8360175695, 0.8092037229, medium, medium, "B"),
                nodeAt(.x, 0.9593704246, 0.7156153051, small, small, "X"),
                nodeAt(.y, 0.9542459736, 0.7869700103, small, small, "Y"),
                nodeAt(.l, 0.1281112738, 0.6633919338, shoulderW, shoulderH, "L"),
                nodeAt(.r, 0.8960468521, 0.6478800414, rightShoulderW, shoulderH, "R"),
                nodeAt(.z, 0.8275988287, 0.7213029990, small, small, "Z"),
                nodeAt(.start, 0.8967789165, 0.5780765253, startW, startH, "START"),
                nodeAt(.dpadUp, dpadX, dpadY - d / h, d, d, "▲"),
                nodeAt(.dpadDown, dpadX, dpadY + d / h, d, d, "▼"),
                nodeAt(.dpadLeft, dpadX - d / w, dpadY, d, d, "◀"),
                nodeAt(.dpadRight, dpadX + d / w, dpadY, d, d, "▶"),
            ]
        }

        return [
            node(.stick, moveX, moveY, stick, stick, ""),
            node(.cStick, camX, camY, camera, camera, ""),
            node(.a, aX, aY, large, large, "A"),
            node(.b, bX, bY, medium, medium, "B"),
            node(.x, xX, xY, small, small, "X"),
            node(.y, yX, yY, small, small, "Y"),
            node(.l, lX, shoulderY, shoulderW, shoulderH, "L"),
            node(.r, rX, shoulderY, rightShoulderW, shoulderH, "R"),
            node(.z, zX, shoulderY, small, small, "Z"),
            node(.start, startX, startY, startW, startH, "START"),
            node(.dpadUp, dx + d, dy - d, d, d, "▲"),
            node(.dpadDown, dx + d, dy + d, d, d, "▼"),
            node(.dpadLeft, dx, dy, d, d, "◀"),
            node(.dpadRight, dx + 2 * d, dy, d, d, "▶"),
        ]
    }
}
