import Foundation
final class SettingsStore: ObservableObject {
    @Published var renderScale: Int {
        didSet { UserDefaults.standard.set(renderScale, forKey: "ballpad.renderScale") }
    }
    init() {
        let v = UserDefaults.standard.integer(forKey: "ballpad.renderScale")
        renderScale = v == 0 ? 1 : v
    }
}
