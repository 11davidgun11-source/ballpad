import SwiftUI
import UniformTypeIdentifiers

// A2: first-run onboarding. Shown instead of the game view when the sandbox
// has no game.iso/main.dol, so a missing game never shows a black screen.
// The user imports their own GameCube disc image through the document picker;
// the host copies it into Documents and extracts sys/main.dol from it.
struct OnboardingView: View {
    @Binding var hasGame: Bool
    @State private var showImporter = false
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 28) {
                Image(systemName: "soccerball")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text("Welcome to Ballpad")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("Ballpad runs your own copy of Super Mario Strikers "
                    + "(GameCube) locally. No game data is bundled — provide a "
                    + "disc image to start playing.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 64)
                if importing {
                    ProgressView("Importing game…")
                        .tint(.white)
                        .foregroundStyle(.white)
                } else {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import Game", systemImage: "folder.badge.plus")
                            .font(.title3.bold())
                            .padding(.horizontal, 36)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                if let importError {
                    Text(importError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 40)
                }
                Text("Supported: GameCube .iso disc images (~1.4 GB). "
                    + "The import runs locally on your device.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 64)
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes:
                          [.data, UTType(filenameExtension: "iso") ?? .data],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importISO(url)
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
    }

    private func importISO(_ url: URL) {
        importing = true
        importError = nil
        let access = url.startAccessingSecurityScopedResource()
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = ballpad_ios_host_import_game(url.path)
            if access {
                url.stopAccessingSecurityScopedResource()
            }
            DispatchQueue.main.async {
                importing = false
                if ok {
                    hasGame = true
                } else {
                    importError =
                        "Could not import that file. Make sure it is a "
                        + "GameCube disc image (.iso)."
                }
            }
        }
    }
}
