import SwiftUI

/// Sunpad-style primary-action menu. Common settings stay one tap away while
/// the more tactile control sliders live in the compact settings sheet.
struct BallpadMenu: View {
    @Binding var renderScale: Int
    @Binding var aspectMode: String
    @Binding var showFps: Bool
    var onTouchSettings: () -> Void
    var onImportGame: () -> Void
    var onImportCard: () -> Void
    var onExportCard: () -> Void
    var onShareDiagnostics: () -> Void

    private var productActionsEnabled: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    var body: some View {
        Menu {
            Menu("Render Resolution") {
                choice("1× (Native)", selected: renderScale == 1) { renderScale = 1 }
                choice("2×", selected: renderScale == 2) { renderScale = 2 }
                choice("3×", selected: renderScale == 3) { renderScale = 3 }
                choice("4×", selected: renderScale == 4) { renderScale = 4 }
            }
            Menu("Aspect Ratio") {
                choice("Original 4:3", selected: aspectMode == "native") {
                    aspectMode = "native"
                }
                choice("16:9 Crop (Experimental)", selected: aspectMode == "wide") {
                    aspectMode = "wide"
                }
                choice("Fill Screen (Experimental)", selected: aspectMode == "stretch") {
                    aspectMode = "stretch"
                }
            }
            Toggle(isOn: $showFps) {
                Label("Show FPS Counter", systemImage: "speedometer")
            }
            Button(action: onTouchSettings) {
                Label("Touch Control Settings…", systemImage: "hand.draw")
            }
            Menu("Game Data & Saves") {
                Button(action: onImportGame) {
                    Label("Change or Reimport Game…",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!productActionsEnabled)
                Divider()
                Button(action: onExportCard) {
                    Label("Export Memory Card…", systemImage: "square.and.arrow.up")
                }
                .disabled(!productActionsEnabled)
                Button(action: onImportCard) {
                    Label("Import Memory Card…", systemImage: "square.and.arrow.down")
                }
                .disabled(!productActionsEnabled)
            }
            Button(action: onShareDiagnostics) {
                Label("Share Diagnostic Log…", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(!productActionsEnabled)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.72), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.30), lineWidth: 1))
                .contentShape(Circle())
        }
        .accessibilityLabel("Menu")
        .accessibilityIdentifier("ballpadMenu")
    }

    @ViewBuilder
    private func choice(_ title: String, selected: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

struct OverflowMenuView: View {
    @Binding var isPresented: Bool
    @Binding var controlScale: Double
    @Binding var controlOpacity: Double
    @Binding var hideControlsOnController: Bool
    var onEditLayout: () -> Void
    var onResetLayout: () -> Void

    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Touch Controls") {
                    valueSlider("Size", value: $controlScale, range: 0.7...1.35)
                    valueSlider("Opacity", value: $controlOpacity, range: 0.25...1.0)
                    Toggle("Hide when a controller connects",
                           isOn: $hideControlsOnController)
                    Button("Move and resize controls", action: onEditLayout)
                    Button("Reset this device layout", role: .destructive) {
                        confirmReset = true
                    }
                }
                Section("About") {
                    Text("Ballpad \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                        .foregroundStyle(.secondary)
                    Text("Runs your own supported Super Mario Strikers disc image locally. Game data is never bundled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Touch Control Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                }
            }
            .alert("Reset Touch Control Layout?", isPresented: $confirmReset) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive, action: onResetLayout)
            } message: {
                Text("All control positions and sizes on this device return to their defaults.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func valueSlider(_ title: String, value: Binding<Double>,
                             range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
