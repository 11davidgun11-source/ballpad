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

    /// Scene-driven replacement for the historical block-anchor endurance
    /// gate above. It waits on the host's source-named scene automation to
    /// reach a real match, then exercises the actual touch overlay without
    /// assuming a fixed guest-throughput budget.
    func testTouchControlsSustainSceneDrivenMatch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BALLPAD_LOG_FILE"] = "$HOME/Documents/touch-scene-match.log"
        app.launchEnvironment["BALLPAD_NO_QUICKBOOT"] = "1"
        app.launchEnvironment["BALLPAD_AUTOSTART"] = "1"
        app.launchEnvironment["BALLPAD_TEST_HOOKS"] = "1"
        app.launch()

        let probe = app.staticTexts["guestBlocks"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 40),
                      "scene-driven guest progress probe")

        func snapshot() -> (UInt64, Int) {
            let parts = probe.label.split(separator: " ")
            return (
                parts.first.flatMap { UInt64($0) } ?? 0,
                parts.dropFirst().first.flatMap { Int($0) } ?? -1
            )
        }

        let matchDeadline = Date().addingTimeInterval(240)
        while Date() < matchDeadline && snapshot().1 != 4 {
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertEqual(snapshot().1, 4, "scene automation reaches an active match")

        func control(_ id: String) -> XCUIElement {
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@", "control.\(id)"))
                .firstMatch
        }
        let stick = control("stick")
        let a = control("a")
        let b = control("b")
        let l = control("l")
        let r = control("r")
        for element in [stick, a, b, l, r] {
            XCTAssertTrue(element.waitForExistence(timeout: 10),
                          "scene-driven touch control \(element.identifier)")
        }

        let before = snapshot().0
        for cycle in 0..<4 {
            let target = stick.coordinate(withNormalizedOffset: cycle.isMultiple(of: 2)
                                          ? CGVector(dx: 0.82, dy: 0.25)
                                          : CGVector(dx: 0.20, dy: 0.78))
            stick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: target)
            target.press(forDuration: 1.0)
            a.press(forDuration: 1.0)
            b.press(forDuration: 1.0)
            l.press(forDuration: 1.0)
            r.press(forDuration: 1.0)
        }

        XCTAssertGreaterThan(snapshot().0, before,
                             "guest continues progressing under real touch input")
        XCTAssertTrue([2, 4].contains(snapshot().1),
                      "guest remains in a live match state after touch exercise")
    }

    /// The overlay must remain attached to the normalized display canvas while
    /// the source-driven decomp path moves through boot, menus, selection, and
    /// match setup—not only after cGame reaches the field.
    func testTouchOverlayPersistsAcrossDecompScenes() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BALLPAD_LOG_FILE"] = "$HOME/Documents/touch-scene-overlay.log"
        app.launchEnvironment["BALLPAD_NO_QUICKBOOT"] = "1"
        app.launchEnvironment["BALLPAD_AUTOSTART"] = "1"
        app.launchEnvironment["BALLPAD_TEST_HOOKS"] = "1"
        app.launch()

        let sceneProbe = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "guestBlocks"))
            .firstMatch
        XCTAssertTrue(sceneProbe.waitForExistence(timeout: 40),
                      "source-named scene probe")

        func sceneSeenMask() -> UInt64 {
            UInt64(sceneProbe.label.split(separator: " ").dropFirst(4).first ?? "0") ?? 0
        }
        func control(_ id: String) -> XCUIElement {
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@", "control.\(id)"))
                .firstMatch
        }
        let controls = ["stick", "a", "b", "l", "r"].map(control)

        // IDs observed in the pinned decomp scene timeline during fresh
        // phone/iPad passes: health, card/save, title, main menu,
        // side/captain selection, stadium-card, and match setup.
        let milestones = [51, 39, 53, 2, 1, 8, 27, 9, 43]
        for expected in milestones {
            let bit = UInt64(1) << UInt64(expected)
            let deadline = Date().addingTimeInterval(60)
            while Date() < deadline && sceneSeenMask() & bit == 0 {
                Thread.sleep(forTimeInterval: 0.5)
            }
            XCTAssertNotEqual(sceneSeenMask() & bit, 0,
                              "decomp scene milestone \(expected) was observed")
            for (id, element) in zip(["stick", "a", "b", "l", "r"], controls) {
                XCTAssertTrue(element.waitForExistence(timeout: 3),
                              "overlay control \(id) mounted after scene \(expected)")
                // The stick is a coordinate-driven drag surface rather than
                // a UIButton-shaped accessibility target; its existence and
                // frame are the stable assertion. Face/shoulder controls
                // must remain directly hittable.
                if id != "stick" {
                    XCTAssertTrue(element.isHittable,
                                  "control.\(id) remains hittable after scene \(expected)")
                }
            }
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "Touch overlay after scene \(expected)"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }
}
