import Foundation
final class SettingsStore: ObservableObject {
    @Published var renderScale: Int {
        didSet { UserDefaults.standard.set(renderScale, forKey: "ballpad.renderScale") }
    }
    // docs/06 Display: native = 4:3 letterboxed, wide = 16:9 crop,
    // stretch = fill (distorted).
    @Published var aspectMode: String {
        didSet { UserDefaults.standard.set(aspectMode, forKey: "ballpad.aspectMode") }
    }
    init() {
        let v = UserDefaults.standard.integer(forKey: "ballpad.renderScale")
        renderScale = v == 0 ? 1 : v
        aspectMode = UserDefaults.standard.string(forKey: "ballpad.aspectMode") ?? "native"
    }
}
