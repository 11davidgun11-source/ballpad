import XCTest

// Diagnostic (not a gate): press each overlay control and dump the merged pad
// state via BALLPAD_PAD_LOG so the touch->pad mapping can be verified.
final class PadDiagnosticTests: XCTestCase {
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
