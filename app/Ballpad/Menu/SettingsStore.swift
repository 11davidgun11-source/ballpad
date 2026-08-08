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
    // Global touch-control scale (0.7-1.35) and opacity (0.25-1.0),
    // modeled on bellpad's settings sliders.
    @Published var controlScale: Double {
        didSet { UserDefaults.standard.set(controlScale, forKey: "ballpad.controlScale") }
    }
    @Published var controlOpacity: Double {
        didSet { UserDefaults.standard.set(controlOpacity, forKey: "ballpad.controlOpacity") }
    }
    @Published var showFps: Bool {
        didSet { UserDefaults.standard.set(showFps, forKey: "ballpad.showFps") }
    }
    init() {
        let v = UserDefaults.standard.integer(forKey: "ballpad.renderScale")
        renderScale = v == 0 ? 1 : v
        aspectMode = UserDefaults.standard.string(forKey: "ballpad.aspectMode") ?? "native"
        let cs = UserDefaults.standard.double(forKey: "ballpad.controlScale")
        controlScale = cs >= 0.7 && cs <= 1.35 ? cs : 1.0
        let co = UserDefaults.standard.double(forKey: "ballpad.controlOpacity")
        controlOpacity = co >= 0.25 && co <= 1.0 ? co : 0.76
        showFps = UserDefaults.standard.bool(forKey: "ballpad.showFps")
    }
}
