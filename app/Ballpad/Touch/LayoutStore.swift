import Foundation
import UIKit

final class LayoutStore: ObservableObject {
    @Published var nodes: [ControlNode]
    private let key: String
    private let deviceClass: String
    private var canvasSize: CGSize
    private var hasCustomLayout: Bool
    private var snapshot: [ControlNode] = []
    private var snapshotWasCustom = false

    init(deviceClass: String) {
        self.deviceClass = deviceClass
        // Version the persisted coordinates whenever the reference layout
        // changes. Old Ballpad defaults used full UIScreen coordinates while
        // SwiftUI laid controls out in a safe-area-sized canvas, which made
        // phones and iPads visibly diverge from Sunpad.
        self.key = "ballpad.layout.sunpad-v5.\(deviceClass)"
        let bounds = UIScreen.main.bounds
        let initialSize = CGSize(width: max(bounds.width, bounds.height),
                                 height: min(bounds.width, bounds.height))
        self.canvasSize = initialSize
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ControlNode].self, from: data),
           !decoded.isEmpty {
            nodes = decoded
            hasCustomLayout = true
        } else {
            nodes = Self.defaults(for: deviceClass, in: initialSize)
            hasCustomLayout = false
        }
    }

    // Sunpad-style adaptive defaults computed from the current screen size
    // (landscape): small screens scale controls down, iPads use fixed larger
    // sizes. Falls back to the last saved layout when present.
    private static func defaults(for deviceClass: String,
                                 in size: CGSize) -> [ControlNode] {
        return deviceClass == "pad" ? DefaultLayouts.computedPad(in: size)
                                    : DefaultLayouts.computedPhone(in: size)
    }

    /// Rebuild untouched defaults from the exact safe-area canvas used by
    /// SwiftUI. Sunpad performs the same calculation in `layoutSubviews`
    /// after applying `safeAreaInsets`; using UIScreen dimensions here makes
    /// phone controls shrink and drift when rendered inside a narrower view.
    func updateCanvas(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let changed = abs(size.width - canvasSize.width) > 0.5 ||
            abs(size.height - canvasSize.height) > 0.5
        canvasSize = size
        guard changed, !hasCustomLayout else { return }
        nodes = Self.defaults(for: deviceClass, in: size)
    }

    func node(_ id: ControlID) -> ControlNode {
        nodes.first(where: { $0.id == id }) ?? ControlNode(id: id, normX: 0.5, normY: 0.5, normW: 0.1, normH: 0.1, label: id.rawValue)
    }

    func save() {
        hasCustomLayout = true
        if let data = try? JSONEncoder().encode(nodes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func move(id: ControlID, to newCenter: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0,
              let idx = nodes.firstIndex(where: { $0.id == id }) else { return }
        var node = nodes[idx]
        let halfWidth = min(node.normW * node.scale / 2, 0.5)
        let halfHeight = min(node.normH * node.scale / 2, 0.5)
        node.normX = min(max(newCenter.x / size.width, halfWidth), 1 - halfWidth)
        node.normY = min(max(newCenter.y / size.height, halfHeight), 1 - halfHeight)
        nodes[idx] = node
        save()
    }

    func setScale(id: ControlID, _ scale: CGFloat) {
        guard let idx = nodes.firstIndex(where: { $0.id == id }) else { return }
        var node = nodes[idx]
        node.scale = min(max(scale, 0.6), 1.8)
        nodes[idx] = node
        save()
    }

    func toggleHidden(id: ControlID) {
        guard let idx = nodes.firstIndex(where: { $0.id == id }) else { return }
        var node = nodes[idx]
        node.hidden.toggle()
        nodes[idx] = node
        save()
    }

    // Editor lifecycle (docs/05 §5): Done saves, Cancel reverts.
    func takeSnapshot() {
        snapshot = nodes
        snapshotWasCustom = hasCustomLayout
    }
    func commitSnapshot() {
        snapshot = []
        save()
    }
    func revertSnapshot() {
        if !snapshot.isEmpty {
            nodes = snapshot
            snapshot = []
            hasCustomLayout = snapshotWasCustom
            if hasCustomLayout, let data = try? JSONEncoder().encode(nodes) {
                UserDefaults.standard.set(data, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    func reset(deviceClass: String) {
        hasCustomLayout = false
        UserDefaults.standard.removeObject(forKey: key)
        nodes = Self.defaults(for: self.deviceClass, in: canvasSize)
    }
}
