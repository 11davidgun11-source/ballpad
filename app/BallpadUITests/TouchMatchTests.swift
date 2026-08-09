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

        // Menu navigation anchors (mirror the host autostart table):
        //   health 1.15B, mem check 1.3B, save prompt 1.45B, title 2.2B,
        //   load-or-save 2.5B, main menu 2.6B, then the match drive 3.0-6.9B.
        XCTAssertTrue(waitBlocks(1_280_000_000), "health screen reached")
        press("A")
        XCTAssertTrue(waitBlocks(1_430_000_000), "memory-card check reached")
        press("A")
        XCTAssertTrue(waitBlocks(1_490_000_000), "save prompt reached")
        press("▼")  // CONTINUE WITHOUT SAVING
        XCTAssertTrue(waitBlocks(1_560_000_000))
        press("A")
        XCTAssertTrue(waitBlocks(2_180_000_000), "title reached")
        press("A")
        XCTAssertTrue(waitBlocks(2_480_000_000), "load-or-save prompt reached")
        press("▼")
        XCTAssertTrue(waitBlocks(2_580_000_000))
        press("A")
        XCTAssertTrue(waitBlocks(2_880_000_000), "main menu reached")
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
    }
}
