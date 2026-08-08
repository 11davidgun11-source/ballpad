import SwiftUI

struct OverflowMenuView: View {
    @Binding var isPresented: Bool
    @Binding var renderScale: Int
    @Binding var aspectMode: String
    @Binding var controlScale: Double
    @Binding var controlOpacity: Double
    @Binding var showFps: Bool
    var onEditLayout: () -> Void
    var onResetLayout: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Picker("Resolution", selection: $renderScale) {
                        Text("1x").tag(1)
                        Text("2x").tag(2)
                        Text("3x").tag(3)
                        Text("4x").tag(4)
                    }
                    .onChange(of: renderScale) { _, newValue in
                        print("[menu] scale=\(newValue)")
                    }
                    Picker("Aspect", selection: $aspectMode) {
                        Text("Native").tag("native")
                        Text("16:9").tag("wide")
                        Text("Stretch").tag("stretch")
                    }
                    .onChange(of: aspectMode) { _, newValue in
                        print("[menu] aspect=\(newValue)")
                    }
                }
                Section("Controls") {
                    Button("Edit layout", action: onEditLayout)
                    Button("Reset layout", role: .destructive, action: onResetLayout)
                    HStack {
                        Text("Size")
                        Slider(value: $controlScale, in: 0.7...1.35)
                            .onChange(of: controlScale) { _, newValue in
                                print("[menu] controlScale=\(newValue)")
                            }
                        Text(String(format: "%.2f", controlScale))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    HStack {
                        Text("Opacity")
                        Slider(value: $controlOpacity, in: 0.25...1.0)
                            .onChange(of: controlOpacity) { _, newValue in
                                print("[menu] controlOpacity=\(newValue)")
                            }
                        Text(String(format: "%.2f", controlOpacity))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Section("Saves") {
                    // M11: file-level card export/import (docs/06). The active
                    // card is Documents/Saves/CardA.dolcard.
                    if let card = ballpad_ios_host_card_path() {
                        Text("Card: \(URL(fileURLWithPath: String(cString: card)).lastPathComponent)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Export card…") {
                        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
                        let dir = (docs as NSString).appendingPathComponent("Saves")
                        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                        let date = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
                            .replacingOccurrences(of: "/", with: "-")
                            .replacingOccurrences(of: ":", with: "-")
                        let dest = (dir as NSString).appendingPathComponent("Export-\(date).dolcard")
                        let ok = ballpad_ios_host_export_card(dest)
                        print("[saves] export to \(dest) ok=\(ok)")
                    }
                    Button("Import card…") {
                        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
                        let dir = (docs as NSString).appendingPathComponent("Saves")
                        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir))?
                            .filter { $0.hasSuffix(".dolcard") } ?? []
                        print("[saves] import candidates: \(files)")
                        if let newest = files.sorted().last {
                            let src = (dir as NSString).appendingPathComponent(newest)
                            let ok = ballpad_ios_host_import_card(src)
                            print("[saves] import \(newest) ok=\(ok)")
                        }
                    }
                }
                Section("Graphics") {
                    Toggle("Show FPS", isOn: $showFps)
                }
                Section("About") {
                    Text("Ballpad \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                        .foregroundStyle(.secondary)
                    Text("Provide your own game copy. Ballpad runs your GameCube disc image locally; no game data is bundled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ballpad")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}
