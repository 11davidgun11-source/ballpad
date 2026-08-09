import XCTest

// A3: re-prove M3 (start a match with touch only) through the REAL touch
// overlay. The autostart's block thresholds are guest-time anchors; at the
// phone's ~20.6M blocks/s they map to wall-time offsets from launch:
//   health ~57s, mem check ~66s, save prompt ~73s, title ~108s,
//   main menu ~126s, then the D_LEFT + A x3 match-start cadence to ~345s.
// Each press holds the touch ~1.5 s so the guest's per-frame pad sampling
// sees a real press edge (a bare XCUITest tap is too brief).
final class TouchMatchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func pressA(_ app: XCUIApplication, at date: Date) {
        let a = app.staticTexts["A"].firstMatch
        XCTAssertTrue(a.waitForExistence(timeout: 10), "A button visible at t=\(Int(Date().timeIntervalSince(date)))")
        a.press(forDuration: 1.5)
    }

    private func pressDown(_ app: XCUIApplication, at date: Date) {
        // The D-pad Down key label is the downward arrow glyph.
        let down = app.staticTexts["▼"].firstMatch
        if down.waitForExistence(timeout: 5) {
            down.press(forDuration: 1.5)
        } else {
            let alt = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "▼")).firstMatch
            XCTAssertTrue(alt.waitForExistence(timeout: 5), "D-pad down visible")
            alt.press(forDuration: 1.5)
        }
    }

    private func pressLeft(_ app: XCUIApplication, at date: Date) {
        let left = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "◀")).firstMatch
        XCTAssertTrue(left.waitForExistence(timeout: 5), "D-pad left visible")
        left.press(forDuration: 1.5)
    }

    func testStartMatchWithTouchOnly() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BALLPAD_LOG_FILE"] = "$HOME/Documents/a3-match.log"
        app.launchEnvironment["BALLPAD_NO_QUICKBOOT"] = "1"
        app.launchEnvironment["BALLPAD_DEBUG_THREADS"] = "1"
        app.launchEnvironment["BALLPAD_PAD_LOG"] = "1"
        app.launch()

        let t0 = Date()
        let wait = { (s: Double) in
            let el = Date().timeIntervalSince(t0)
            if el < s { Thread.sleep(forTimeInterval: s - el) }
        }

        // Wait for the game's first frame (health screen) + autostart-drive
        // sequence. The overlay's A button exists as soon as the game view
        // mounts, so gate on it before the first press.
        let a = app.staticTexts["A"].firstMatch
        XCTAssertTrue(a.waitForExistence(timeout: 40), "game view + overlay A button")
        wait(65)
        pressA(app, at: t0)            // health screen (autostart A@1.3B)
        wait(72.5)
        pressA(app, at: t0)            // memory card check (A@1.45B)
        wait(75)
        pressDown(app, at: t0)         // CONTINUE WITHOUT SAVING (D_DOWN@1.5B)
        wait(79)
        pressA(app, at: t0)
        wait(110)
        pressA(app, at: t0)            // title (A@2.2B)
        wait(125)
        pressDown(app, at: t0)         // SHOULD_LOAD_OR_SAVE prompt (D_DOWN@2.5B)
        wait(129)
        pressA(app, at: t0)
        wait(145)
        pressA(app, at: t0)            // main menu (A@2.9B)
        // Match-start cadence (the autostart's D_LEFT + A x3 retries from
        // 3.0B to 6.9B). Stops at ~354 s so the extra presses cannot disturb
        // the match intro once the final A starts the match.
        var cadence = 150.0
        for cycle in 0..<8 {
            wait(cadence)
            pressLeft(app, at: t0)
            wait(cadence + 6)
            pressA(app, at: t0)
            wait(cadence + 12)
            pressA(app, at: t0)
            wait(cadence + 18)
            pressA(app, at: t0)
            cadence += 26
        }
        // Two more D_LEFT + A pairs cover the final 6.6-6.9B window.
        wait(cadence)
        pressLeft(app, at: t0)
        wait(cadence + 6)
        pressA(app, at: t0)
        wait(cadence + 12)
        pressA(app, at: t0)
        wait(cadence + 18)
        pressA(app, at: t0)

        // The match starts ~6.9B blocks (~345 s). Let the match load settle,
        // then check the game is running (the FPS label from the overlay).
        let fps = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "fps"))
            .firstMatch
        XCTAssertTrue(fps.waitForExistence(timeout: 120),
                      "in-match after touch-only navigation (t=\(Int(Date().timeIntervalSince(t0)))s)")
    }
}
