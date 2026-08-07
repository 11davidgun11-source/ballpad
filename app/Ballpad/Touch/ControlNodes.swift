import SwiftUI
import CoreGraphics

enum ControlID: String, Codable, CaseIterable, Identifiable {
    case stick, cStick, a, b, x, y, start, z, l, r, dpad
    var id: String { rawValue }
}

struct ControlNode: Identifiable, Codable, Equatable {
    var id: ControlID
    var normX: CGFloat // 0...1 left->right
    var normY: CGFloat // 0...1 top->bottom
    var normW: CGFloat
    var normH: CGFloat
    var label: String
}

enum DefaultLayouts {
    static func phoneLandscape() -> [ControlNode] {
        [
            .init(id: .stick, normX: 0.14, normY: 0.68, normW: 0.22, normH: 0.28, label: "L"),
            .init(id: .cStick, normX: 0.78, normY: 0.78, normW: 0.14, normH: 0.18, label: "C"),
            .init(id: .a, normX: 0.86, normY: 0.55, normW: 0.11, normH: 0.12, label: "A"),
            .init(id: .b, normX: 0.76, normY: 0.60, normW: 0.09, normH: 0.10, label: "B"),
            .init(id: .x, normX: 0.90, normY: 0.42, normW: 0.08, normH: 0.09, label: "X"),
            .init(id: .y, normX: 0.80, normY: 0.42, normW: 0.08, normH: 0.09, label: "Y"),
            .init(id: .start, normX: 0.50, normY: 0.88, normW: 0.10, normH: 0.07, label: "START"),
            .init(id: .l, normX: 0.16, normY: 0.12, normW: 0.14, normH: 0.08, label: "L"),
            .init(id: .r, normX: 0.84, normY: 0.12, normW: 0.14, normH: 0.08, label: "R"),
            .init(id: .z, normX: 0.70, normY: 0.20, normW: 0.10, normH: 0.07, label: "Z"),
            .init(id: .dpad, normX: 0.28, normY: 0.82, normW: 0.14, normH: 0.16, label: "D"),
        ]
    }

    static func padLandscape() -> [ControlNode] {
        phoneLandscape().map { n in
            var m = n
            // slightly more margin on iPad
            m.normW *= 0.9
            m.normH *= 0.9
            return m
        }
    }
}
