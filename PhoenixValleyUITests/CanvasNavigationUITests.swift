import XCTest

@MainActor
final class CanvasNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func launchEditor() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["new-design-map"].waitForExistence(timeout: 40))
        if app.buttons["新建"].exists && app.buttons["新建"].isHittable {
            app.buttons["Toggle Sidebar"].tap()
        }
        let previousMap = element("road-canvas").value as? String ?? ""
        app.buttons["new-design-map"].tap()
        XCTAssertTrue(element("road-canvas").waitForExistence(timeout: 30))
        let created = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", previousMap), object: element("road-canvas"))
        XCTAssertEqual(XCTWaiter.wait(for: [created], timeout: 60), .completed)

        let finger = app.buttons["finger-drawing-toggle"]
        XCTAssertTrue(finger.waitForExistence(timeout: 8))
        if !finger.isSelected { finger.tap() }
        XCTAssertTrue(finger.isSelected)
    }

    func testFingerDrawingNavigationAndPersistenceKeepRoadsAttached() {
        launchEditor()
        app.buttons["road-tool-street"].tap()
        let canvas = element("canvas-viewport")
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.31, dy: 0.56))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.69, dy: 0.56))
        start.press(forDuration: 0.08, thenDragTo: end)
        app.buttons["undo-button"].tap()
        app.buttons["redo-button"].tap()
        // Native navigation must also work while finger drawing is enabled.
        let drawingZoom = canvas.value as? String
        app.pinch(withScale: 1.4, velocity: 1)
        XCTAssertNotEqual(canvas.value as? String, drawingZoom)
        let drawingHeading = canvas.value as? String
        app.rotate(0.4, withVelocity: 1)
        XCTAssertNotEqual(canvas.value as? String, drawingHeading)
        element("finger-drawing-toggle").tap()
        let beforePan = app.screenshot().pngRepresentation
        app.swipeRight()
        XCTAssertNotEqual(app.screenshot().pngRepresentation, beforePan)
        let before = canvas.value as? String
        app.pinch(withScale: 1.7, velocity: 1)
        XCTAssertNotEqual(canvas.value as? String, before)
        app.rotate(0.6, withVelocity: 1)
        let compass = element("native-map-compass")
        XCTAssertTrue(compass.waitForExistence(timeout: 5))
        XCTAssertTrue(compass.isHittable)
        compass.tap()
        let north = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value ENDSWITH %@", "朝向 0°"), object: canvas)
        XCTAssertEqual(XCTWaiter.wait(for: [north], timeout: 8), .completed)
        let palette = element("floating-tool-palette")
        let expandedWidth = palette.frame.width
        app.buttons["palette-collapse"].tap()
        let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            palette.frame.width < expandedWidth * 0.6
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 5), .completed)
        attach("Collapsed toolbar fits its content")
        app.buttons["palette-collapse"].tap()
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            palette.frame.width > expandedWidth * 0.9
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
        app.terminate()
        app.launch()
        XCTAssertTrue(element("road-canvas").waitForExistence(timeout: 20))
        attach("Design canvas after navigation and relaunch")
    }

    func testInterchangePreviewCommitAndUndo() {
        launchEditor()
        app.buttons["road-interchange-tool"].tap()
        let practice = app.buttons["interchange-practice"]
        XCTAssertTrue(practice.waitForExistence(timeout: 8))
        practice.tap()
        let preview = app.buttons["interchange-quick-ramp"]
        XCTAssertTrue(preview.waitForExistence(timeout: 8))
        preview.tap()
        XCTAssertTrue(app.buttons["interchange-cycle-ramp"].waitForExistence(timeout: 5))
        app.buttons["interchange-cycle-ramp"].tap()
        app.buttons["interchange-commit-ramp"].tap()
        XCTAssertTrue(app.buttons["interchange-delete-ramp"].waitForExistence(timeout: 8))
        app.buttons["undo-button"].tap()
        XCTAssertFalse(app.buttons["interchange-delete-ramp"].exists)
        app.buttons["redo-button"].tap()
        attach("Interchange preview, commit, undo and redo")
    }

    func testExportPreviewExtentTextAndCoordinatedTheme() {
        launchEditor()
        app.buttons["export-map-menu"].tap()
        let preview = element("export-preview-card")
        XCTAssertTrue(preview.waitForExistence(timeout: 15))
        XCTAssertTrue(element("export-format-picker").exists)

        let extent = element("export-extent-picker")
        XCTAssertTrue(extent.exists)
        extent.buttons["当前视野"].tap()
        attach("Current-viewport export preview")

        app.swipeUp()
        let theme = element("map-theme-coastal")
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        theme.tap()
        XCTAssertTrue(theme.waitForExistence(timeout: 2))
        attach("Coordinated export theme preview")

        app.swipeUp()
        XCTAssertTrue(element("export-title-toggle").waitForExistence(timeout: 5))
        XCTAssertTrue(element("export-scale-toggle").exists)
        XCTAssertTrue(element("export-information-toggle").exists)
        element("export-title-toggle").tap()
        element("export-scale-toggle").tap()
        element("export-information-toggle").tap()
        attach("Export text options reflected in preview")
        let confirm = app.buttons["export-confirm"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: confirm)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
        confirm.tap()
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 10))
        attach("System file export destination")
    }

    func testNativeMapControlsAndBoundedZoom() {
        launchEditor()
        XCTAssertTrue(element("native-map-compass").isHittable)
        XCTAssertTrue(element("native-map-scale").exists)
        XCTAssertFalse(element("canvas-zoom-in").isHittable)
        XCTAssertFalse(element("canvas-zoom-out").isHittable)
        let viewport = element("canvas-viewport")
        for _ in 0..<3 { app.pinch(withScale: 0.6, velocity: -1) }
        attach("Minimum zoom with native scale and compass")
        let text = viewport.value as? String ?? ""
        let percent = Double(text.components(separatedBy: "%")[0]) ?? 0
        XCTAssertGreaterThan(percent, 75)
        XCTAssertLessThan(percent, 120)
        app.pinch(withScale: 2, velocity: 1)
        XCTAssertNotEqual(viewport.value as? String, text)
        attach("Native zoom and metric scale")
    }

    func testAppleMapImportKeepsNativeBasemapVisible() {
        launchEditor()
        let sidebar = app.buttons["Toggle Sidebar"]
        if sidebar.exists { sidebar.tap() }
        else { app.navigationBars.buttons.element(boundBy: 0).tap() }
        let create = app.buttons["新建"]
        XCTAssertTrue(create.waitForExistence(timeout: 5), app.debugDescription)
        create.tap()
        app.buttons["import-real-map"].tap()
        XCTAssertTrue(app.buttons["real-map-apple"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["real-map-download"].exists)
        app.buttons["real-map-apple"].tap()
        XCTAssertTrue(element("native-map").waitForExistence(timeout: 10))
        XCTAssertTrue(element("native-map-scale").exists)
        attach("Apple basemap after import")
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
