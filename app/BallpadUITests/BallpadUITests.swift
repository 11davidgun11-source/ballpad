import XCTest

// A2: document-picker import proof. Drives the real picker (system UI): the
// onboarding shows instructions for a missing game (never a black screen),
// "Import Game" opens the document picker, selecting the disc image imports
// it, and the app switches to the game view (host boots).
final class BallpadUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testImportGameViaDocumentPickerAndBoot() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BALLPAD_LOG_FILE"] = "$HOME/Documents/import.log"
        app.launch()

        // Onboarding shown instead of a black screen.
        let importButton = app.buttons["Import Game"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 15),
                      "onboarding import button (missing game must not be a black screen)")

        importButton.tap()

        // Document picker (Files). The picker may open at "On My iPhone" or
        // Recents — navigate if needed, then tap the disc image. Use the
        // exact filename so the onboarding copy ("Super Mario Strikers")
        // cannot false-match.
        let isoQuery = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Strikers.iso"))
            .firstMatch
        if !isoQuery.waitForExistence(timeout: 8) {
            let tabBar = app.tabBars.firstMatch
            let browse = tabBar.buttons["Browse"]
            if browse.waitForExistence(timeout: 8) {
                browse.tap()
            }
            // "On My iPhone" (phone) / "On My iPad" (tablet) — match both.
            let onMyDevice = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "On My"))
                .firstMatch
            if onMyDevice.waitForExistence(timeout: 8) {
                onMyDevice.tap()
            }
        }
        XCTAssertTrue(isoQuery.waitForExistence(timeout: 20),
                      "Strikers.iso visible in the document picker")
        isoQuery.tap()

        // The import runs (1.4 GB copy + DOL extract), then the onboarding
        // switches to the game view. The host boots the guest; wait for the
        // game view's ⋯ menu button to appear (C1 removed the old
        // "[ballpad] runtime init" banner the test used to probe for).
        let hostProbe = app.buttons["Menu"].firstMatch
        XCTAssertTrue(hostProbe.waitForExistence(timeout: 180),
                      "game view after import (host booted)")
        XCTAssertFalse(app.buttons["Import Game"].exists,
                       "onboarding dismissed after a successful import")
    }
}
