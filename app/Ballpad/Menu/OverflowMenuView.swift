import SwiftUI

struct OverflowMenuView: View {
    @Binding var isPresented: Bool
    @Binding var renderScale: Int
    @Binding var aspectMode: String
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
