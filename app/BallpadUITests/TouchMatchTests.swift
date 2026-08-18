import XCTest

// A3: re-prove M3 (start a match with touch only) through the REAL touch
// overlay, driven by the guest's platform-independent block anchors (the same
// thresholds the host autostart uses, verified against the Path C oracle).
// The app exposes the live block count + cGame state via a test-only
// accessibility label (BALLPAD_TEST_HOOKS=1), so this works on any simulator
// regardless of wall-clock throughput (the iPad runs the guest ~2.4x faster
// than the phone; a wall-clock-calibrated driver fails there).
// Each press holds the touch ~1.5 s so the guest's per-frame pad sampling
// sees a real press edge (a bare XCUITest tap is too brief).
final class TouchMatchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testStartMatchWithTouchOnly() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BALLPAD_LOG_FILE"] = "$HOME/Documents/a3-match.log"
        app.launchEnvironment["BALLPAD_NO_QUICKBOOT"] = "1"
        app.launchEnvironment["BALLPAD_TEST_HOOKS"] = "1"
        app.launchEnvironment["BALLPAD_DEBUG_THREADS"] = "1"
        app.launchEnvironment["BALLPAD_PAD_LOG"] = "1"
        app.launch()

        // The test hook label appears as soon as the game view mounts.
        let probe = app.staticTexts["guestBlocks"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 40),
                      "game view + guest-block test hook")

        func blocks() -> UInt64 {
            let parts = probe.label.split(separator: " ")
            return parts.first.flatMap { UInt64($0) } ?? 0
        }
        func state() -> Int {
            let parts = probe.label.split(separator: " ")
            return parts.count > 1 ? (Int(parts[1]) ?? -1) : -1
        }
        func waitBlocks(_ target: UInt64, timeout: TimeInterval = 300) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if blocks() >= target { return true }
                Thread.sleep(forTimeInterval: 1.0)
            }
            return blocks() >= target
        }
        func press(_ label: String, hold: TimeInterval = 1.5) {
            let el = app.staticTexts[label].firstMatch
            if el.waitForExistence(timeout: 8) {
                el.press(forDuration: hold)
            } else {
                let alt = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@", label)).firstMatch
                XCTAssertTrue(alt.waitForExistence(timeout: 8),
                              "overlay control \(label) visible")
                alt.press(forDuration: hold)
            }
        }

        // Menu navigation anchors exactly mirror the host autostart table.
        // Do not compact the waits: the save-prompt selection needs to settle
        // before its confirming A at 2.20B, or that A lands on the wrong menu.
        XCTAssertTrue(waitBlocks(1_150_000_000), "health screen reached")
        press("A")
        XCTAssertTrue(waitBlocks(1_300_000_000), "memory-card check reached")
        press("A")
        XCTAssertTrue(waitBlocks(1_450_000_000), "save prompt reached")
        press("▼")  // CONTINUE WITHOUT SAVING
        XCTAssertTrue(waitBlocks(2_200_000_000), "title reached")
        press("A")
        XCTAssertTrue(waitBlocks(2_500_000_000), "load-or-save prompt reached")
        press("▼")
        XCTAssertTrue(waitBlocks(2_600_000_000))
        press("A")
        XCTAssertTrue(waitBlocks(2_900_000_000), "main menu reached")
        press("A")

        // Match-start drive: D_LEFT + A x3 at the autostart cadence. A D_LEFT
        // landing on the side-choice screen picks the left side; the A chain
        // advances rosters; the final A@6.9B starts the match. In-match the
        // presses are harmless (left + tackle).
        let driveAnchors: [UInt64] = [
            3_000_000_000, 3_400_000_000, 3_900_000_000, 4_300_000_000,
            4_800_000_000, 5_200_000_000, 5_700_000_000, 6_100_000_000,
            6_600_000_000,
        ]
        for a in driveAnchors {
            XCTAssertTrue(waitBlocks(a), "match-drive anchor \(a)")
            press("◀")
            XCTAssertTrue(waitBlocks(a + 100_000_000))
            press("A")
            XCTAssertTrue(waitBlocks(a + 200_000_000))
            press("A")
            XCTAssertTrue(waitBlocks(a + 300_000_000))
            press("A")
        }

        // The match starts after the final A@6.9B. Wait for the guest cGame
        // state to reach 4 (in-match).
        let deadline = Date().addingTimeInterval(150)
        var inMatch = false
        while Date() < deadline {
            if state() == 4 { inMatch = true; break }
            Thread.sleep(forTimeInterval: 2.0)
        }
        XCTAssertTrue(inMatch, "in-match (cGame state 4) after touch-only navigation")

        // P0 endurance gate: do not stop at a menu-to-field transition. Drive
        // the real movement stick, face buttons, and both shoulders for at
        // least a minute, then require the guest to still be playing and
        // making progress. Coordinates are used for the unlabeled stick well;
        // the other controls are found by their stable accessibility IDs.
        func control(_ identifier: String) -> XCUIElement {
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
        }
        let stick = control("control.stick")
        let a = control("control.a")
        let b = control("control.b")
        let l = control("control.l")
        let r = control("control.r")
        for element in [stick, a, b, l, r] {
            XCTAssertTrue(element.waitForExistence(timeout: 8),
                          "in-match control \(element.identifier) visible")
        }

        let blocksBeforeExercise = blocks()
        for cycle in 0..<6 {
            let direction = cycle.isMultiple(of: 2)
                ? CGVector(dx: 0.82, dy: 0.22)
                : CGVector(dx: 0.18, dy: 0.78)
            let stickTarget = stick.coordinate(withNormalizedOffset: direction)
            // Begin the drag from the stick centre, then hold at its rim so
            // the SwiftUI DragGesture emits a non-zero analog axis for two
            // seconds before releasing.
            stick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: stickTarget)
            stickTarget.press(forDuration: 2.0)
            a.press(forDuration: 2.0)
            b.press(forDuration: 2.0)
            l.press(forDuration: 2.0)
            r.press(forDuration: 2.0)
        }

        XCTAssertGreaterThan(blocks(), blocksBeforeExercise,
                             "guest advances during sustained touch input")
        // cGame transitions between 4 (active play) and 2 (on-field
        // introduction/replay sequence) without leaving the live match. Both
        // were captured in the renderer; rejecting state 2 would turn a valid
        // sustained-play run into a false failure.
        XCTAssertTrue([2, 4].contains(state()),
                      "still in a live-match cGame state after sustained touch input")
    }
}
