import XCTest

/// A focused runtime gate for the SceneDelegate lifecycle bridge. It starts a
/// real guest, backgrounds the app through SpringBoard, returns to it, and
/// requires the existing guest worker to make further progress. This detects
/// a common emulator failure where presentation or the guest thread is never
/// resumed after UIKit deactivates the scene.
final class LifecycleTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBackgroundForegroundResumesGuest() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BALLPAD_LOG_FILE"] = "$HOME/Documents/lifecycle-resume.log"
        app.launchEnvironment["BALLPAD_NO_QUICKBOOT"] = "1"
        app.launchEnvironment["BALLPAD_TEST_HOOKS"] = "1"
        app.launch()

        let probe = app.staticTexts["guestBlocks"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 40),
                      "guest progress probe is mounted before lifecycle change")

        func blocks() -> UInt64 {
            probe.label.split(separator: " ").first.flatMap { UInt64($0) } ?? 0
        }
        func waitForProgress(after baseline: UInt64,
                             timeout: TimeInterval = 75) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if blocks() > baseline { return true }
                Thread.sleep(forTimeInterval: 1)
            }
            return blocks() > baseline
        }

        XCTAssertTrue(waitForProgress(after: 0), "guest advances before backgrounding")
        let beforeBackground = blocks()

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 3)
        app.activate()

        XCTAssertTrue(probe.waitForExistence(timeout: 20),
                      "game scene returns after foregrounding")
        XCTAssertTrue(waitForProgress(after: beforeBackground),
                      "guest advances after foregrounding")
    }

    /// Opening the controls sheet is the in-app pause surface (as distinct
    /// from the short-lived SwiftUI action popover behind the three-dot
    /// button).  This proves the pause is observable at the guest boundary
    /// and that dismissing the sheet does not strand the guest worker.
    func testTouchSettingsPausesAndResumesGuest() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BALLPAD_LOG_FILE"] = "$HOME/Documents/menu-pause.log"
        app.launchEnvironment["BALLPAD_NO_QUICKBOOT"] = "1"
        app.launchEnvironment["BALLPAD_TEST_HOOKS"] = "1"
        app.launch()

        let probe = app.staticTexts["guestBlocks"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 40),
                      "guest progress probe is mounted before opening settings")

        func blocks() -> UInt64 {
            probe.label.split(separator: " ").first.flatMap { UInt64($0) } ?? 0
        }
        func waitForProgress(after baseline: UInt64,
                             timeout: TimeInterval = 75) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if blocks() > baseline { return true }
                Thread.sleep(forTimeInterval: 1)
            }
            return blocks() > baseline
        }

        XCTAssertTrue(waitForProgress(after: 0), "guest advances before opening settings")
        let menu = app.buttons["Menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "persistent three-dot menu")
        menu.tap()
        let touchSettings = app.descendants(matching: .any)["Touch Control Settings…"].firstMatch
        XCTAssertTrue(touchSettings.waitForExistence(timeout: 8),
                      "touch settings action is available from the three-dot menu")
        touchSettings.tap()
        XCTAssertTrue(app.navigationBars["Touch Control Settings"].waitForExistence(timeout: 10),
                      "touch settings sheet is presented")

        // Allow the representable update to signal the guest worker, then use
        // two samples separated by several seconds to reject a one-frame race.
        Thread.sleep(forTimeInterval: 2)
        let pausedBaseline = blocks()
        Thread.sleep(forTimeInterval: 4)
        XCTAssertEqual(blocks(), pausedBaseline,
                       "guest block counter remains frozen while settings is open")

        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "settings sheet has a dismiss action")
        done.tap()
        XCTAssertFalse(app.navigationBars["Touch Control Settings"].waitForExistence(timeout: 5),
                       "touch settings sheet dismisses")
        XCTAssertTrue(waitForProgress(after: pausedBaseline),
                      "guest advances after settings is dismissed")
    }

    /// The Simulator must not query its synthetic MFi device (that can detach
    /// the iPad window), but its isolated proof hook exercises the exact
    /// published handoff state used by a real controller connection.  Verify
    /// that the visible touch surface becomes non-interactive rather than
    /// merely relying on a controller diagnostic line.
    func testSimulatedControllerHidesTouchOverlay() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BALLPAD_LOG_FILE"] = "$HOME/Documents/controller-handoff.log"
        app.launchEnvironment["BALLPAD_SIMULATE_CONTROLLER"] = "1"
        app.launchEnvironment["BALLPAD_SIMULATE_CONTROLLER_DELAY"] = "6.0"
        app.launch()

        let a = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "control.a"))
            .firstMatch
        XCTAssertTrue(a.waitForExistence(timeout: 40),
                      "touch overlay is initially mounted")
        XCTAssertTrue(a.isHittable,
                      "touch A accepts input before a controller connects")

        // Wait for the deferred hook to publish its connection state and for
        // SwiftUI to make the actual control non-interactive. It remains in
        // the accessibility tree by design: the unconditional overlay avoids
        // an iPadOS graph cycle.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline && a.isHittable {
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertFalse(a.isHittable,
                       "touch A is non-interactive while a controller is connected")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Simulated controller handoff hides touch overlay"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
