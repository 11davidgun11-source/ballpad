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
                    Text("Import/Export arrives in Step 13")
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
