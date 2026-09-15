import XCTest

/// Real-touch acceptance for the vendored SunPad interface running inside the native
/// Strikers port (doc 36 R1; stages N4-C and N4-D).
///
/// The app under test is the CMake-built BallpadStrikers.app that
/// scripts/native/run-uitests.sh installs on the Simulator. It is addressed by bundle
/// identifier, so this bundle carries no target application of its own, and the only
/// input used is a real tap, drag, switch flip or slider move delivered through the
/// app's own accessibility tree. Nothing here can pass without the app consuming that
/// input, because every claim is read back from the app afterwards.
final class BallpadSunPadInterfaceTests: XCTestCase {

    private static let bundleIdentifier = "com.ballpad.strikers"

    /// SunPadGameOverlay -buildMenu order, verbatim. The order is part of the fidelity
    /// claim (R1: adopted "exactly as they are"), so it is asserted rather than assumed.
    private static let vendoredMenuRows = [
        "Render Resolution",
        "Aspect Ratio",
        "Show FPS Counter",
        "Experimental Performance Mode (Restart Required)",
        "Experimental 60 FPS (Restart Required)",
        "Controller Button Mapping…",
        "Touch Control Settings…",
        "Game Data & Saves",
        "Report a Problem…",
    ]

    /// The touch-control settings surface, by its vendored accessibility labels.
    private static let vendoredSettingsControls = [
        "Render resolution",
        "Control opacity",
        "Control size",
        "Hide touch controls when controller connected",
        "Modern C-stick left and right",
        "Move touch controls",
    ]

    /// The layout editor is a separate vendored surface, not a row of the panel: enabling
    /// "Move touch controls" hides the settings panel and raises this bar instead. Its size
    /// slider is the control whose label the vendored code rewrites to "<control> size" once a
    /// control is tapped, so the resting form is only observable before a selection.
    private static let vendoredEditorControls = [
        "Drag controls • tap one to resize",
        "Selected control size",
        "Finish moving touch controls",
    ]

    private static let renderScaleSegments = ["1×", "2×", "3×", "4×"]

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: Self.bundleIdentifier)
        app.launchEnvironment = Self.launchEnvironment()
    }

	/// The engine needs its disc image and a writable user/cache directory. The wrapper
	/// script passes them as build settings, which Xcode expands into this bundle's
	/// Info.plist: xcodebuild does not forward command-line build settings into the test
	/// runner's own environment, so the plist is the channel that actually carries them.
	/// An inherited environment of the same name still wins, so a manual run can override.
	private static func launchEnvironment() -> [String: String] {
		let host = ProcessInfo.processInfo.environment
		let bundled = Bundle(for: BallpadSunPadInterfaceTests.self)
		func path(_ hostKey: String, _ infoKey: String) -> String? {
			if let value = host[hostKey], !value.isEmpty { return value }
			guard let value = bundled.object(forInfoDictionaryKey: infoKey) as? String,
			      !value.isEmpty, !value.hasPrefix("$(") else { return nil }
			return value
		}
		var env: [String: String] = ["STRIKERS_LOG_SCENES": "1", "STRIKERS_SEED": "12345"]
		if let iso = path("BALLPAD_UITEST_ISO", "BallpadUITestDiscImage") { env["STRIKERS_DATA"] = iso }
		if let user = path("BALLPAD_UITEST_USER_DIR", "BallpadUITestUserDir") {
			env["STRIKERS_USER_DIR"] = user
		}
		if let cache = path("BALLPAD_UITEST_CACHE_DIR", "BallpadUITestCacheDir") {
			env["STRIKERS_CACHE_DIR"] = cache
		}
		return env
	}

    // MARK: - Harness helpers

    private var menuButton: XCUIElement { app.buttons["Menu"] }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

	/// The element tree exactly as the runner saw it, kept as text next to the screenshot.
	/// A row that is missing from a claim needs the interface's own published hierarchy as
	/// evidence, because "not in the tree" and "below the fold" look identical from a
	/// boolean existence check and lead to opposite conclusions.
	private func attachHierarchy(_ name: String) {
		let attachment = XCTAttachment(string: app.debugDescription)
		attachment.name = name
		attachment.lifetime = .keepAlways
		add(attachment)
	}

    /// Launches the app and waits for the host overlay. A missing three-dot button after a
    /// generous bounded wait is a real failure: it means the overlay never reached the screen.
    private func launchAndWaitForOverlay(timeout: TimeInterval = 240) {
        app.launch()
        XCTAssertTrue(menuButton.waitForExistence(timeout: timeout),
                      "the SunPad three-dot menu button is on screen")
    }

    /// The vendored menu mounts through UIKit's menu machinery, so a row is not guaranteed
    /// to land in one particular element collection. The label is the claim, so any honest
    /// query type that carries it is accepted.
    private func overlayElement(_ label: String) -> XCUIElement? {
        let candidates = [app.buttons[label], app.cells[label], app.staticTexts[label],
                          app.menuItems[label], app.otherElements[label],
                          app.switches[label], app.sliders[label], app.segmentedControls[label]]
        for candidate in candidates where candidate.exists { return candidate }
        return nil
    }

    @discardableResult
    private func waitForOverlayElement(_ label: String, timeout: TimeInterval = 20) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let element = overlayElement(label) { return element }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return nil
    }

    private func openMenu() {
        XCTAssertTrue(menuButton.waitForExistence(timeout: 30), "the three-dot menu button")
        menuButton.tap()
        XCTAssertNotNil(waitForOverlayElement(Self.vendoredMenuRows[0], timeout: 30),
                        "tapping the three-dot button opens the vendored menu")
    }

	/// The vendored menu is a UIKit `UIMenu`, so iOS owns its presentation and the two form
	/// factors differ in a way that is not the overlay's doing. At the iPad's regular height the
	/// whole nine-row list fits in the panel and every row is published at once. On the iPhone
	/// the same list is taller than the panel iOS grants it (322 pt of a 390 pt screen), so it is
	/// a two-page collection view and the cells past the fold are not in the accessibility tree
	/// until they are scrolled into it -- measured, not assumed: the phone run's captured tree
	/// carries "Vertical scroll bar, 2 pages" and stops after the fifth row. The rows themselves
	/// are the vendored ones in either case; only the reading needs a scroll.
	@discardableResult
	private func scrollMenuDown() -> Bool {
		let panel = app.collectionViews.firstMatch
		guard panel.exists else { return false }
		panel.swipeUp()
		return true
	}

	/// Looks for `label`, scrolling the open menu when it is not published yet. Bounded on
	/// purpose: a row that is genuinely absent from the menu still fails rather than scrolling
	/// forever, and the bounded scroll is what the phone form factor needs.
	@discardableResult
	private func scrollMenuForElement(_ label: String, maxScrolls: Int = 6,
	                                  timeout: TimeInterval = 5) -> XCUIElement? {
		for pass in 0...maxScrolls {
			if let element = waitForOverlayElement(label, timeout: timeout) { return element }
			if pass == maxScrolls { break }
			guard scrollMenuDown() else { break }
		}
		return nil
	}

    private func openTouchSettings() {
        guard let row = scrollMenuForElement("Touch Control Settings…", timeout: 30) else {
            XCTFail("the Touch Control Settings row is present in the menu")
            return
        }
        row.tap()
        XCTAssertNotNil(waitForOverlayElement("Render resolution", timeout: 30),
                        "the touch control settings panel opens")
    }

    private func renderScaleSegment(_ title: String) -> XCUIElement {
        app.segmentedControls["Render resolution"].buttons[title]
    }

    private func selectedRenderScaleTitle() -> String? {
        for title in Self.renderScaleSegments {
            let segment = renderScaleSegment(title)
            if segment.exists && segment.isSelected { return title }
        }
        return nil
    }

    private func framesDiffer(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 8) -> Bool {
        abs(a.minX - b.minX) > tolerance || abs(a.minY - b.minY) > tolerance
    }

    private func assertFrameClose(_ actual: CGRect, _ expected: CGRect,
                                  accuracy: CGFloat = 3, _ what: String) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, what + " x")
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, what + " y")
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, what + " width")
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, what + " height")
    }

    private func overlayATitle() -> XCUIElement { app.buttons["A"] }

    // MARK: - The three-dot menu

    func testThreeDotMenuAdoptsTheVendoredRowsInOrder() throws {
        launchAndWaitForOverlay()
        openMenu()

		attachHierarchy("menu-hierarchy-top")
		attach("menu-open")

		// Walk the menu one panel-page at a time. A sighting is the first pass in which a row is
		// published, together with where it sat; the walking order is what the order claim is
		// read from, so a row that only appears after a scroll still has to appear in its place.
		var sightings: [(row: String, minY: CGFloat)] = []
		var seen = Set<String>()
		for pass in 0...6 {
			var onScreen: [(row: String, minY: CGFloat)] = []
			for row in Self.vendoredMenuRows where !seen.contains(row) {
				guard let element = waitForOverlayElement(row, timeout: 5) else { continue }
				seen.insert(row)
				sightings.append((row, element.frame.minY))
				onScreen.append((row, element.frame.minY))
			}
			XCTAssertEqual(onScreen.map(\.minY), onScreen.map(\.minY).sorted(),
			               "rows visible together keep their vendored vertical order (pass \(pass))")
			if seen.count == Self.vendoredMenuRows.count { break }
			if pass == 6 { break }
			guard scrollMenuDown() else { break }
		}

		let missing = Self.vendoredMenuRows.filter { !seen.contains($0) }
		XCTAssertTrue(missing.isEmpty, "every vendored row is reachable in the menu; missing: "
			+ missing.joined(separator: ", "))
		XCTAssertEqual(sightings.map(\.row), Self.vendoredMenuRows,
		               "the rows are first sighted in the vendored order")
		attachHierarchy("menu-hierarchy-walked")
		attach("menu-open-after-walk")
    }

    // MARK: - The touch control settings surface

    func testTouchSettingsPanelExposesTheVendoredControls() throws {
        launchAndWaitForOverlay()
        openMenu()
        openTouchSettings()

        for control in Self.vendoredSettingsControls {
            XCTAssertNotNil(waitForOverlayElement(control, timeout: 5),
                            "settings control present: " + control)
        }
        XCTAssertTrue(app.buttons["Reset This Device Layout"].waitForExistence(timeout: 5),
                      "the layout reset button is present")
        XCTAssertTrue(app.buttons["Close touch control settings"].exists,
                      "the panel close button is present")
        attach("touch-settings-panel")
		attachHierarchy("touch-settings-panel-hierarchy")

        // The layout editor, reached the way the vendored code reaches it: the switch is
        // flipped through the UI and the bar it raises has to answer for itself.
        let moveSwitch = app.switches["Move touch controls"]
        XCTAssertTrue(moveSwitch.waitForExistence(timeout: 10), "the Move touch controls switch")
        if (moveSwitch.value as? String) != "1" { moveSwitch.tap() }

        for control in Self.vendoredEditorControls {
            XCTAssertNotNil(waitForOverlayElement(control, timeout: 10),
                            "layout editor control present: " + control)
        }
        XCTAssertNil(waitForOverlayElement("Render resolution", timeout: 3),
                     "raising the layout editor hides the settings panel")
        attach("layout-editor")

        // Done ends editing without reopening the panel, so the panel is expected to stay
        // down until the menu button raises it again.
        app.buttons["Finish moving touch controls"].tap()
        XCTAssertNil(waitForOverlayElement("Selected control size", timeout: 5),
                     "finishing the layout editor takes its bar away")
        XCTAssertNil(waitForOverlayElement("Render resolution", timeout: 3),
                     "the vendored Done button leaves the settings panel hidden")
        openMenu()
        openTouchSettings()
        XCTAssertNotNil(waitForOverlayElement("Render resolution", timeout: 15),
                        "the settings panel opens again once editing has ended")
    }

    // MARK: - Settings persistence

    func testRenderScaleSelectionPersistsAcrossRelaunch() throws {
        launchAndWaitForOverlay()
        openMenu()
        openTouchSettings()

        let existing = selectedRenderScaleTitle()
        let target = existing == "3×" ? "2×" : "3×"
        renderScaleSegment(target).tap()
        XCTAssertEqual(selectedRenderScaleTitle(), target,
                       "the tap selected render scale " + target)

        // A fresh process reading the same domain is the only honest persistence proof:
        // in-process state cannot survive app.terminate().
        app.terminate()
        launchAndWaitForOverlay()
        openMenu()
        openTouchSettings()
        XCTAssertEqual(selectedRenderScaleTitle(), target,
                       "render scale " + target + " survived a termination and a fresh launch")
        attach("render-scale-after-relaunch")
    }

    // MARK: - Layout editing and layout reset

    func testMovedControlPersistsAndResetRestoresTheDefault() throws {
        launchAndWaitForOverlay()
        openMenu()
        openTouchSettings()

        let aButton = overlayATitle()
        XCTAssertTrue(aButton.waitForExistence(timeout: 30), "the overlay A button is on screen")
        let defaultFrame = aButton.frame

        // SunPad installs its edit gestures disabled and enables them from the panel's own
        // "Move touch controls" switch, so the switch is flipped first, through the UI.
        let moveSwitch = app.switches["Move touch controls"]
        XCTAssertTrue(moveSwitch.waitForExistence(timeout: 10), "the Move touch controls switch")
        if (moveSwitch.value as? String) != "1" { moveSwitch.tap() }
        XCTAssertTrue(app.buttons["Finish moving touch controls"].waitForExistence(timeout: 10),
                      "the layout editor bar appears once moving is on")

        let start = aButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.3, thenDragTo: start.withOffset(CGVector(dx: -110, dy: -150)))
        let movedFrame = overlayATitle().frame
        XCTAssertTrue(framesDiffer(movedFrame, defaultFrame),
                      "the drag moved the A button (default " + String(describing: defaultFrame)
                      + ", moved " + String(describing: movedFrame) + ")")
        attach("a-button-moved")

        app.buttons["Finish moving touch controls"].tap()
        XCTAssertFalse(app.buttons["Finish moving touch controls"].exists,
                       "finishing editing leaves the layout editor")

        // The normalized origin is written to the settings domain, so it must survive a
        // relaunch, and the panel must show it back.
        app.terminate()
        launchAndWaitForOverlay()
        let relaunchedFrame = overlayATitle().frame
        assertFrameClose(relaunchedFrame, movedFrame, "the moved A button after relaunch")

        // Now the reset, through the alert the vendored code raises.
        openMenu()
        openTouchSettings()
        let resetButton = app.buttons["Reset This Device Layout"]
        XCTAssertTrue(resetButton.waitForExistence(timeout: 10), "the reset button")
        resetButton.tap()
        let alert = app.alerts["Reset Touch Control Layout?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "the reset confirmation alert")
        XCTAssertTrue(alert.buttons["Cancel"].exists, "the alert offers Cancel")
        XCTAssertTrue(alert.buttons["Reset"].exists, "the alert offers Reset")
        attach("reset-alert")
        alert.buttons["Reset"].tap()

        XCTAssertFalse(alert.waitForExistence(timeout: 3), "Reset dismisses the alert")
        assertFrameClose(overlayATitle().frame, defaultFrame, "the A button back at its default")

        app.terminate()
        launchAndWaitForOverlay()
        assertFrameClose(overlayATitle().frame, defaultFrame,
                         "the reset layout survived a relaunch")
        attach("a-button-after-reset")
    }

    // MARK: - Lifecycle

    func testBackgroundAndForegroundKeepTheOverlay() throws {
        launchAndWaitForOverlay()
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 5)
        app.activate()

        XCTAssertTrue(menuButton.waitForExistence(timeout: 90),
                      "the overlay is back on screen after resume")
        openMenu()
        XCTAssertNotNil(scrollMenuForElement("Touch Control Settings…", timeout: 20),
                        "the menu still opens after resume")
        openTouchSettings()
        XCTAssertNotNil(waitForOverlayElement("Render resolution", timeout: 20),
                        "the settings panel still opens after resume")
        attach("after-resume")
    }
}
