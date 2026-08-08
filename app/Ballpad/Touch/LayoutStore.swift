import Foundation
import UIKit

final class LayoutStore: ObservableObject {
    @Published var nodes: [ControlNode]
    private let key: String
    private var snapshot: [ControlNode] = []

    init(deviceClass: String) {
        self.key = "ballpad.layout.\(deviceClass)"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ControlNode].self, from: data),
           !decoded.isEmpty {
            nodes = decoded
        } else {
            nodes = Self.defaults(for: deviceClass)
        }
    }

    // bellpad-style adaptive defaults computed from the current screen size
    // (landscape): small screens scale controls down, iPads use fixed larger
    // sizes. Falls back to the last saved layout when present.
    private static func defaults(for deviceClass: String) -> [ControlNode] {
        let bounds = UIScreen.main.bounds
        let size = CGSize(width: max(bounds.width, bounds.height),
                          height: min(bounds.width, bounds.height))
        return deviceClass == "pad" ? DefaultLayouts.computedPad(in: size)
                                    : DefaultLayouts.computedPhone(in: size)
    }

    func node(_ id: ControlID) -> ControlNode {
        nodes.first(where: { $0.id == id }) ?? ControlNode(id: id, normX: 0.5, normY: 0.5, normW: 0.1, normH: 0.1, label: id.rawValue)
    }

    func save() {
        if let data = try? JSONEncoder().encode(nodes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func move(id: ControlID, to newCenter: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0,
              let idx = nodes.firstIndex(where: { $0.id == id }) else { return }
        var node = nodes[idx]
        node.normX = min(max(newCenter.x / size.width, 0.03), 0.97)
        node.normY = min(max(newCenter.y / size.height, 0.03), 0.97)
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
    }
    func commitSnapshot() {
        snapshot = []
        save()
    }
    func revertSnapshot() {
        if !snapshot.isEmpty {
            nodes = snapshot
            snapshot = []
            save()
        }
    }

    func reset(deviceClass: String) {
        nodes = Self.defaults(for: deviceClass)
        save()
    }
}
