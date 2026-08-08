import Foundation

final class LayoutStore: ObservableObject {
    @Published var nodes: [ControlNode]
    private let key: String

    init(deviceClass: String) {
        self.key = "ballpad.layout.\(deviceClass)"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ControlNode].self, from: data),
           !decoded.isEmpty {
            nodes = decoded
        } else {
            nodes = deviceClass == "pad" ? DefaultLayouts.padLandscape() : DefaultLayouts.phoneLandscape()
        }
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

    func reset(deviceClass: String) {
        nodes = deviceClass == "pad" ? DefaultLayouts.padLandscape() : DefaultLayouts.phoneLandscape()
        save()
    }
}
