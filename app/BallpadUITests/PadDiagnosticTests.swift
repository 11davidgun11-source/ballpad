import XCTest

// Diagnostic (not a gate): press each overlay control and dump the merged pad
// state via BALLPAD_PAD_LOG so the touch->pad mapping can be verified.
final class PadDiagnosticTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSunpadStyleMenuAndSettings() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BALLPAD_LOG_FILE"] = "$HOME/Documents/menu-test.log"
        app.launch()

        let menu = app.buttons["Menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 40), "persistent three-dot menu")
        menu.tap()
        Thread.sleep(forTimeInterval: 1)
        let menuShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        menuShot.name = "Ballpad three-dot menu"
        menuShot.lifetime = .keepAlways
        add(menuShot)
        func item(_ label: String) -> XCUIElement {
            app.descendants(matching: .any)[label].firstMatch
        }
        XCTAssertTrue(item("Render Resolution").waitForExistence(timeout: 5))
        XCTAssertTrue(item("Aspect Ratio").exists)
        XCTAssertTrue(item("Touch Control Settings…").exists)
        XCTAssertTrue(item("Game Data & Saves").exists)
        XCTAssertTrue(item("Share Diagnostic Log…").exists)

        item("Touch Control Settings…").tap()
        XCTAssertTrue(app.navigationBars["Touch Control Settings"]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Hide when a controller connects"].exists)
        XCTAssertTrue(app.buttons["Move and resize controls"].exists)
        app.buttons["Move and resize controls"].tap()
        XCTAssertTrue(app.staticTexts["DRAG CONTROLS • TAP ONE TO RESIZE"]
            .waitForExistence(timeout: 5))
        let a = app.staticTexts["A"].firstMatch
        XCTAssertTrue(a.exists)
        a.tap()
        XCTAssertTrue(app.sliders["Selected control size"]
            .waitForExistence(timeout: 5), "Sunpad-style per-control resizing")
        app.buttons["Cancel"].tap()
    }

    func testDpadAndButtonsReachPad() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BALLPAD_LOG_FILE"] = "$HOME/Documents/pad-diag.log"
        app.launchEnvironment["BALLPAD_PAD_LOG"] = "1"
        app.launchEnvironment["BALLPAD_TOUCH_LOG"] = "1"
        app.launch()

        let a = app.staticTexts["A"].firstMatch
        XCTAssertTrue(a.waitForExistence(timeout: 40), "overlay A button")
        print("A frame: \(a.frame), app frame: \(app.frame)")
        a.press(forDuration: 2.0)
        Thread.sleep(forTimeInterval: 2.0)
        let down = app.staticTexts["▼"].firstMatch
        if down.exists { down.press(forDuration: 2.0); Thread.sleep(forTimeInterval: 1.5) }
        let left = app.staticTexts["◀"].firstMatch
        if left.exists { left.press(forDuration: 2.0); Thread.sleep(forTimeInterval: 1.5) }
        let right = app.staticTexts["▶"].firstMatch
        if right.exists { right.press(forDuration: 2.0); Thread.sleep(forTimeInterval: 1.5) }
        let up = app.staticTexts["▲"].firstMatch
        if up.exists { up.press(forDuration: 2.0); Thread.sleep(forTimeInterval: 1.5) }
    }
}
