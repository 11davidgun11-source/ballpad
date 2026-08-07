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

    func reset(deviceClass: String) {
        nodes = deviceClass == "pad" ? DefaultLayouts.padLandscape() : DefaultLayouts.phoneLandscape()
        save()
    }
}
