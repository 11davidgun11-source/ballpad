import SwiftUI
import CoreGraphics

enum ControlID: String, Codable, CaseIterable, Identifiable {
    case stick, cStick, a, b, x, y, start, z, l, r, dpad
    var id: String { rawValue }
}

// GameCube-fidelity skin metadata (docs/05 §3). Colors are recreated shapes,
// never ripped textures.
enum ControlSkin {
    static func fill(_ id: ControlID) -> Color {
        switch id {
        case .a: return Color(red: 0.15, green: 0.78, blue: 0.30)   // A green
        case .b: return Color(red: 0.85, green: 0.20, blue: 0.18)   // B red
        case .x, .y: return Color(white: 0.72)                      // X/Y grey
        case .cStick: return Color(red: 0.95, green: 0.80, blue: 0.12) // C yellow
        case .l, .r, .z: return Color(red: 0.55, green: 0.30, blue: 0.68) // L/R/Z purple
        case .start: return Color(white: 0.62)
        default: return Color(white: 0.55)                          // stick/dpad charcoal
        }
    }
    static func idleOpacity(_ id: ControlID) -> Double { 0.55 }
    static func activeOpacity(_ id: ControlID) -> Double { 0.85 }
}

struct ControlNode: Identifiable, Codable, Equatable {
    var id: ControlID
    var normX: CGFloat // 0...1 left->right
    var normY: CGFloat // 0...1 top->bottom
    var normW: CGFloat
    var normH: CGFloat
    var label: String
    var scale: CGFloat = 1.0
    var hidden: Bool = false
}

enum DefaultLayouts {
    // docs/05 §2.1: normalized 0-1 on the safe area, landscape phone.
    static func phoneLandscape() -> [ControlNode] {
        [
            .init(id: .stick,   normX: 0.16, normY: 0.62, normW: 0.22, normH: 0.28, label: ""),
            .init(id: .cStick,  normX: 0.30, normY: 0.78, normW: 0.14, normH: 0.18, label: ""),
            .init(id: .dpad,    normX: 0.16, normY: 0.38, normW: 0.15, normH: 0.16, label: ""),
            .init(id: .a,       normX: 0.84, normY: 0.62, normW: 0.15, normH: 0.15, label: "A"),
            .init(id: .b,       normX: 0.76, normY: 0.70, normW: 0.11, normH: 0.11, label: "B"),
            .init(id: .x,       normX: 0.92, normY: 0.54, normW: 0.10, normH: 0.10, label: "X"),
            .init(id: .y,       normX: 0.78, normY: 0.52, normW: 0.10, normH: 0.10, label: "Y"),
            .init(id: .l,       normX: 0.12, normY: 0.09, normW: 0.20, normH: 0.09, label: "L"),
            .init(id: .r,       normX: 0.88, normY: 0.09, normW: 0.20, normH: 0.09, label: "R"),
            .init(id: .z,       normX: 0.88, normY: 0.20, normW: 0.14, normH: 0.07, label: "Z"),
            .init(id: .start,   normX: 0.50, normY: 0.88, normW: 0.10, normH: 0.07, label: "START"),
        ]
    }

    static func padLandscape() -> [ControlNode] {
        phoneLandscape().map { n in
            var m = n
            // docs/05 §2.2: ~1.15-1.3x with more bezel margin on iPad.
            m.normW *= 1.2
            m.normH *= 1.2
            m.normY = min(m.normY + 0.03, 0.95)
            return m
        }
    }
}
