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
        // The interface rows judge the overlay over a running game, so they hand the engine the
        // disc and the writable directories they were built with. F01/F03's import rows are the
        // opposite case and launch without them, which is why this is here and not in setUp.
        app.launchEnvironment = Self.launchEnvironment()
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
        // Turning the switch on hides the settings panel, so once the editor is up the switch is
        // gone from the tree and can no longer be read back. That makes the panel's own state the
        // read-back: if it is still up, the tap did not land -- which is what a first run of this
        // row measured, on a switch XCUITest had to scroll into view first. One retry distinguishes
        // a consumed tap from a missed one instead of reporting the second as a broken editor.
        if !app.buttons["Finish moving touch controls"].waitForExistence(timeout: 12) {
            attachHierarchy("move-controls-after-first-tap")
            // Only a switch the panel is still showing can be a missed tap: once editing is on the
            // panel is hidden, and re-tapping the switch in that state would turn editing back off.
            if moveSwitch.exists && moveSwitch.isHittable {
                moveSwitch.tap()
            }
        }
        attachHierarchy("move-controls-editor")
        XCTAssertTrue(app.buttons["Finish moving touch controls"].waitForExistence(timeout: 30),
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

    // MARK: - Ballpad's own Files importer (doc 34 F01/F02)

    /// The three files the wrapper script puts in this app's Files-visible Documents folder. They
    /// are the player's own game bytes, derived at run time; see scripts/native/run-uitests.sh.
    private static let validImageName = "uitest-valid.iso"
    private static let truncatedImageName = "uitest-truncated.iso"
    private static let wrongGameImageName = "uitest-wronggame.iso"

    /// The heading the port itself asks for when its disc search finds nothing, verbatim from
    /// src/platform/dvd.c. Asserting this exact string is what makes the row "the app shows the
    /// port's own explanation" rather than "the app shows some screen".
    private static let portRefusalHeading = "Super Mario Strikers: game data not found"

    /// No disc, no writable directories, no seed: the launch of a fresh install. This is the
    /// launch the old build answered by printing its refusal and exiting before UIKit existed.
    private func launchWithNoEnvironment() {
        app.launchEnvironment = [:]
        app.launch()
    }

    private var importScreenTitle: XCUIElement { app.staticTexts["BallpadGameDataImportTitle"] }
    private var importScreenChoose: XCUIElement { app.buttons["BallpadGameDataImportChoose"] }

    /// The body is a multi-line text view, not a label, so it is looked up by whatever type the
    /// interface actually published rather than by the one this bundle assumed.
    private func importScreenElement(_ identifier: String) -> XCUIElement? {
        let candidates = [app.staticTexts[identifier], app.textViews[identifier],
                          app.buttons[identifier], app.otherElements[identifier]]
        for candidate in candidates where candidate.exists { return candidate }
        return nil
    }

    /// Which screen answers a launch with no environment: the game, because a stored disc
    /// resolved, or the importer, because nothing did. Both are legitimate outcomes; which one a
    /// row expects is that row's claim.
    private enum NoEnvironmentLaunch { case game, importer, neither }

    private func classifyNoEnvironmentLaunch(timeout: TimeInterval = 240) -> NoEnvironmentLaunch {
        launchWithNoEnvironment()
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if menuButton.exists { return .game }
            if importScreenTitle.exists { return .importer }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return .neither
    }

    // MARK: The Files picker

    /// One flat query, resolved to a single element, or nil.
    ///
    /// The shape matters. A query that walks through a container -- `app.collectionViews.cells[x]`,
    /// `app.tables.cells[x]` -- raises "Failed to get matching snapshot: No matches found for first
    /// query match sequence" when the *container* matched nothing, which is an exception and not a
    /// false: run f01f02-phone-r2 lost F02 to exactly that on a page of the picker with no collection
    /// view on it. Asking the app for descendants of one type keeps every step flat, so a page that
    /// simply does not have the element answers nil.
    private func pickerDescendant(_ type: XCUIElement.ElementType,
                                  matching predicate: NSPredicate,
                                  excludingIdentifier excluded: String? = nil,
                                  limit: Int = 8) -> XCUIElement? {
        let query = app.descendants(matching: type).matching(predicate)
        let count = query.count
        guard count > 0 else { return nil }
        for index in 0..<min(count, limit) {
            let element = query.element(boundBy: index)
            if let excluded, element.identifier == excluded { continue }
            if element.exists { return element }
        }
        return nil
    }

    private static let pickerRowTypes: [XCUIElement.ElementType] = [.cell, .button, .other]

    /// The picker's tree belongs to another framework, and the same item is a cell on one page and
    /// a button on the next, so every step searches the honest query types rather than assuming one
    /// of them. Only single matches are handed back: "Browse" names both the tab bar's Browse
    /// button and, once inside that location, the navigation bar's back button, and tapping an
    /// ambiguous query raises instead of choosing. That ambiguity is what the first run of this
    /// row hit, so the back button is excluded by identifier here.
    private func pickerMatch(_ labels: [String]) -> XCUIElement? {
        for label in labels {
            let tabBar = app.otherElements["DOC.browsingModeTabBar"]
            if tabBar.exists {
                let tab = tabBar.buttons[label]
                if tab.exists { return tab.firstMatch }
            }
            let byName = NSPredicate(format: "label == %@ OR identifier == %@", label, label)
            for type in Self.pickerRowTypes {
                if let match = pickerDescendant(type, matching: byName,
                                                excludingIdentifier: "BackButton") {
                    return match
                }
            }
        }
        return nil
    }

    /// A row in the picker's *list* of places rather than in its sidebar. The list decorates the
    /// name it was given, and the decoration is not part of the name: the app's own folder is
    /// published as `identifier: 'Ballpad Strikers, Container', label: 'Ballpad Strikers, 4 items'`
    /// (measured, run f01f02-phone-r3, attached as files-picker-in-On-My-iPhone), so an exact
    /// comparison against the folder's name can never find the row. The prefix is the identity;
    /// the suffix is the picker's own annotation of what is inside.
    private func pickerContainer(named name: String, timeout: TimeInterval = 8) -> XCUIElement? {
        let prefix = NSPredicate(format: "identifier BEGINSWITH %@ OR label BEGINSWITH %@",
                                 name, name)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for type in Self.pickerRowTypes {
                if let row = pickerDescendant(type, matching: prefix,
                                              excludingIdentifier: "BackButton") {
                    return row
                }
            }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return nil
    }

    private func pickerElement(_ labels: [String], timeout: TimeInterval = 15) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let element = pickerMatch(labels) { return element }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return nil
    }

    /// The picker's row for the file, in whichever form the current layout publishes it. Icon mode
    /// makes one cell whose identifier and label both open with the file name and then fold in the
    /// size and the date, so the exact match is tried first and a prefix match after it.
    private func pickerRow(named name: String, timeout: TimeInterval = 20) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        let exact = NSPredicate(format: "identifier == %@ OR label == %@", name, name)
        let prefix = NSPredicate(format: "identifier BEGINSWITH %@ OR label BEGINSWITH %@",
                                 name, name)
        repeat {
            for type in Self.pickerRowTypes {
                if let row = pickerDescendant(type, matching: exact) { return row }
                if let row = pickerDescendant(type, matching: prefix) { return row }
            }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return nil
    }

    /// The file itself, row first and label last. A row in icon mode publishes the name twice: once
    /// on the cell and once as a label on top of its icon, and a tap that lands on the label has
    /// been measured to leave the picker standing (run f01f02-phone-r2, whose F01 tapped the label
    /// and then waited out the whole alert timeout). The label is therefore only offered once the
    /// rows have had half the budget to show up, and a label tap that changes nothing is caught by
    /// the caller rather than believed.
    private func pickerFile(named name: String, timeout: TimeInterval = 20) -> XCUIElement? {
        let start = Date()
        let deadline = start.addingTimeInterval(timeout)
        let byName = NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@", name, name)
        repeat {
            if let row = pickerRow(named: name, timeout: 0.5) { return row }
            if Date().timeIntervalSince(start) > timeout / 2,
               let label = pickerDescendant(.staticText, matching: byName) {
                return label
            }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return nil
    }

    /// A selection dismisses the whole picker service, so the tab bar's disappearance is the only
    /// in-process sign that a tap was taken rather than merely delivered.
    private func waitForPickerToClose(timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if !app.otherElements["DOC.browsingModeTabBar"].exists { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return !app.otherElements["DOC.browsingModeTabBar"].exists
    }

    /// Taps the file and requires the picker to go away, retrying against the row itself when the
    /// first tap only reached the label.
    private func selectFileInPicker(named name: String, timeout: TimeInterval = 20) -> Bool {
        guard let first = pickerFile(named: name, timeout: timeout) else { return false }
        attachHierarchy("files-picker-file")
        first.tap()
        if waitForPickerToClose() { return true }

        attachHierarchy("files-picker-still-open")
        guard let row = pickerRow(named: name, timeout: 10) else { return false }
        row.tap()
        return waitForPickerToClose()
    }

    /// Drives the Files picker from wherever it opens to the named image in this app's own folder.
    /// The folder is published to Files because the bundle sets UIFileSharingEnabled, and the
    /// wrapper script fills it before the run (scripts/native/run-uitests.sh), so the selection,
    /// the copy the picker hands back and the staging that follows are all the real ones. The
    /// picker is a remote view service that remembers where it was last left, so a run can meet it
    /// on Recents or already standing in this app's folder; each bounded pass looks for the file,
    /// then comes in through the Browse tab, then walks one container on the way to the folder.
    ///
    /// The order is the one two runs measured rather than a preference. Looking for the file first
    /// covers the run that meets the picker still standing in this app's folder, and it is short on
    /// purpose: the first run of this row spent its whole budget here and tapped a label on a
    /// Recents page instead of the row, which is why nothing is selected until a tap is seen to
    /// dismiss the picker. Browse comes next because it is the route that has worked -- the run that
    /// passed did exactly that tap and then found the file on the first query -- and the container
    /// walk is last because it is the slowest and the least likely.
    ///
    /// Browse is not a shortcut to the folder, it is a shortcut to wherever the picker was left, and
    /// the third run measured both outcomes of it: f01f02-phone-r1 opened onto this app's folder
    /// directly, f01f02-phone-r3 opened onto the locations sidebar with iCloud Drive and On My
    /// iPhone in it. So the walk is what makes the route deterministic, and it needs two hops --
    /// On My iPhone, then the app's own folder -- rather than one.
    private func pickImageThroughFiles(named name: String) {
        // Pass 1: the file may already be on screen.
        if selectFileInPicker(named: name, timeout: 12) { return }

        // Pass 2: in through the Browse tab, which lands wherever Files was last browsing -- in a
        // passing run, this app's own folder, which is the folder the fixture is in.
        if let browse = pickerElement(["Browse"], timeout: 20) {
            browse.tap()
            Thread.sleep(forTimeInterval: 1.5)
            attachHierarchy("files-picker-browse")
            if selectFileInPicker(named: name) { return }
        } else {
            attachHierarchy("files-picker-no-browse")
        }

        // Pass 3: the locations the browse root lists on the way to this app's folder, which is
        // what the picker's Browse tab opens onto -- a sidebar of places, not the last folder (run
        // f01f02-phone-r3: Browse landed on `Title: On My iPhone` with iCloud Drive/On My iPhone in
        // a Locations list). The sidebar entries carry their own name, but the folder list below
        // them decorates it, so both spellings are looked for.
        for container in ["On My iPhone", "On My iPad", "This iPhone", "This iPad",
                          "Ballpad Strikers"] {
            guard let inside = pickerMatch([container])
                                  ?? pickerContainer(named: container, timeout: 6) else { continue }
            inside.tap()
            Thread.sleep(forTimeInterval: 1.5)
            attachHierarchy("files-picker-in-"
                            + container.replacingOccurrences(of: " ", with: "-"))
            if selectFileInPicker(named: name) { return }
        }

        attachHierarchy("files-picker-could-not-reach-the-file")
        XCTFail("the Files picker reached " + name + " in this app's own folder")
    }

    /// Launch with no stored disc and no environment at all: the launch of a fresh install. The
    /// build this port replaced answered it by printing its refusal and exiting before UIKit
    /// existed, so which screen comes up here is the row's first claim.
    func testFreshInstallShowsImportScreenAndActivatesAPickedImage() throws {
        let outcome = classifyNoEnvironmentLaunch()
        XCTAssertEqual(outcome, .importer,
                       "a launch with no data and no environment presents Ballpad's own importer "
                       + "instead of exiting")
        guard outcome == .importer else { return }

        XCTAssertEqual(importScreenTitle.label, Self.portRefusalHeading,
                       "the importer carries the port's own heading, verbatim")
        XCTAssertNotNil(importScreenElement("BallpadGameDataImportBody"),
                        "the importer carries the port's own body text")
        XCTAssertTrue(importScreenChoose.isHittable,
                      "the choose button is hittable without scrolling the explanation")
        attach("f01-import-screen")
        attachHierarchy("f01-import-screen-hierarchy")

        importScreenChoose.tap()
        pickImageThroughFiles(named: Self.validImageName)

        // Staging and validation run on a background queue and answer with this alert, which is
        // the app accepting the copy -- not yet the launch playing it.
        let ready = app.alerts["Game Data Ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 180),
                      "the copy chosen through Files is accepted as this port's disc")
        attach("f01-game-data-ready")
        XCTAssertTrue(ready.buttons["Start the Game"].exists, "the alert continues the launch")
        ready.buttons["Start the Game"].tap()

        // The port re-resolves through the hook the importer records into, so the same process
        // reaching its overlay is what shows the activation landed rather than the alert alone.
        XCTAssertTrue(menuButton.waitForExistence(timeout: 300),
                      "the same launch continues into the game on the copy chosen through Files")
        attach("f01-overlay-after-import")
        attachHierarchy("f01-overlay-after-import-hierarchy")
    }

    /// F02's precondition: a stored disc this app resolves on a launch with no environment. The
    /// row that imports one normally ran first; this makes the state a property of this row rather
    /// than of another method's leftovers.
    private func ensureStoredGameData() {
        guard classifyNoEnvironmentLaunch() == .importer else { return }
        XCTAssertEqual(importScreenTitle.label, Self.portRefusalHeading,
                       "the importer carries the port's own heading, verbatim")
        importScreenChoose.tap()
        pickImageThroughFiles(named: Self.validImageName)
        let ready = app.alerts["Game Data Ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 180),
                      "the image this row sets up is accepted")
        ready.buttons["Start the Game"].tap()
        XCTAssertTrue(menuButton.waitForExistence(timeout: 300),
                      "the image this row set up activated and the game came up")
    }

    /// The running game's own menu, down to the vendored Game Data & Saves submenu. The rows are
    /// the vendored ones; only their destinations are Ballpad's.
    private func openGameDataMenu() {
        openMenu()
        guard let dataRow = scrollMenuForElement("Game Data & Saves", timeout: 25) else {
            XCTFail("the Game Data & Saves row is in the menu")
            return
        }
        dataRow.tap()
    }

    private func tapDataMenuRow(_ title: String) {
        guard let row = waitForOverlayElement(title, timeout: 20) else {
            XCTFail("the vendored row is in the data submenu: " + title)
            return
        }
        row.tap()
    }

    /// A refused import through the menu row: the alert the app raises has to carry the port's own
    /// words, which is what makes this "the engine refused it" rather than "a screen appeared".
    private func importFromMenuExpectingRefusal(named name: String, containing phrase: String) {
        openGameDataMenu()
        tapDataMenuRow("Import or Reimport Game Data")
        pickImageThroughFiles(named: name)

        let refusal = app.alerts["That Disc Cannot Be Used"]
        XCTAssertTrue(refusal.waitForExistence(timeout: 180),
                      "the refused image " + name + " is reported to the player")
        attachHierarchy("f02-refusal-" + name.replacingOccurrences(of: ".", with: "-"))
        let words = refusal.staticTexts.allElementsBoundByIndex.map(\.label)
            .joined(separator: " ")
        XCTAssertTrue(words.contains(phrase),
                      "the refusal is the port's own words (" + phrase + "); saw: " + words)
        refusal.buttons["OK"].tap()
        XCTAssertFalse(refusal.waitForExistence(timeout: 5), "OK dismisses the refusal")
    }

    /// Cancel is the other half of doc 34's "failure/cancel leaves previous installation usable".
    private func cancelMenuImport() {
        openGameDataMenu()
        tapDataMenuRow("Import or Reimport Game Data")
        guard let cancel = pickerElement(["Cancel"], timeout: 60) else {
            attachHierarchy("f02-picker-no-cancel")
            XCTFail("the Files picker offers Cancel")
            return
        }
        cancel.tap()
        XCTAssertFalse(app.alerts["Game Data Imported"].waitForExistence(timeout: 10),
                       "cancelling the picker imports nothing")
    }

    /// The installation is still the one that was there: a fresh process resolves it and reaches
    /// the game. A store a refusal had damaged would show the importer instead.
    private func assertStoredGameDataStillPlays(_ when: String) {
        XCTAssertEqual(classifyNoEnvironmentLaunch(), .game,
                       "the previous installation is still usable " + when)
        attachHierarchy("f02-still-plays-" + when.replacingOccurrences(of: " ", with: "-"))
    }

    /// Removal is the one menu action that is supposed to stop the next launch resolving.
    private func removeStoredGameData() {
        openGameDataMenu()
        tapDataMenuRow("Remove Stored Game Data")

        let confirm = app.alerts["Remove Stored Game Data?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 15), "the vendored confirmation is raised")
        XCTAssertTrue(confirm.buttons["Remove"].exists, "the confirmation offers Remove")
        confirm.buttons["Remove"].tap()

        let done = app.alerts["Game Data Removed"]
        XCTAssertTrue(done.waitForExistence(timeout: 30), "the removal reports what it did")
        attachHierarchy("f02-removed")
        done.buttons["OK"].tap()
    }

    /// F02. Every refusal has to leave the installation that was already there usable and has to
    /// leave the file the player chose untouched. The words the refusals carry are the port's own,
    /// because validation calls the engine's reader rather than a second parser; the two phrases
    /// below are from src/platform/disc.c and this app's own header check.
    func testRefusedImportKeepsThePreviousInstallationUsable() throws {
        ensureStoredGameData()

        importFromMenuExpectingRefusal(named: Self.truncatedImageName, containing: "truncated")
        assertStoredGameDataStillPlays("after a truncated image was refused")

        importFromMenuExpectingRefusal(named: Self.wrongGameImageName,
                                       containing: "is not Super Mario Strikers")
        assertStoredGameDataStillPlays("after another game's disc was refused")

        cancelMenuImport()
        assertStoredGameDataStillPlays("after the picker was cancelled")

        removeStoredGameData()
        XCTAssertEqual(classifyNoEnvironmentLaunch(), .importer,
                       "once the stored disc is removed the next launch asks for one again")
        attach("f02-importer-after-removal")

        // The removal row leaves the machine asking for game data, so this takes it back the way a
        // player would, from the importer that is already up. It decides nothing F02 has not
        // already decided; what it buys is the state the wrapper script reads back afterwards --
        // the store holds a staged copy, and that copy can be compared with the fixture the picker
        // offered instead of with what an alert said about itself.
        XCTAssertTrue(importScreenChoose.isHittable, "the importer is up after the removal")
        importScreenChoose.tap()
        pickImageThroughFiles(named: Self.validImageName)
        let restored = app.alerts["Game Data Ready"]
        XCTAssertTrue(restored.waitForExistence(timeout: 180),
                      "a removed installation can be re-imported from the importer")
        restored.buttons["Start the Game"].tap()
        XCTAssertTrue(menuButton.waitForExistence(timeout: 300),
                      "the re-imported disc activates in the same launch")
        attachHierarchy("f02-reimported")
    }
}
