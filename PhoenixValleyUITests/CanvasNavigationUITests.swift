import XCTest

/// These tests navigate only: no project data, roads, or preferences are changed.
@MainActor
final class CanvasNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launchMap() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["canvas-zoom-in"].waitForExistence(timeout: 30))
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Canvas accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private var viewport: XCUIElement { app.otherElements["canvas-viewport"] }
    private var zoomIn: XCUIElement { app.buttons["canvas-zoom-in"] }
    private var compass: XCUIElement { app.buttons["canvas-compass"] }

    private var zoomPercent: Double {
        Double((zoomIn.value as? String ?? "").replacingOccurrences(of: "%", with: "")) ?? -1
    }

    func testNativePinchAndZoomButtons() {
        launchMap()
        XCTAssertFalse(compass.exists)
        let initial = zoomPercent
        XCTAssertGreaterThan(initial, 0)
        zoomIn.tap()
        let enlarged = zoomPercent
        XCTAssertGreaterThan(enlarged, initial)
        app.buttons["canvas-zoom-out"].tap()
        XCTAssertLessThan(zoomPercent, enlarged)
        let beforePinch = zoomPercent
        viewport.pinch(withScale: 1.6, velocity: 1)
        XCTAssertGreaterThan(zoomPercent, beforePinch)
        let afterPinch = zoomPercent
        viewport.pinch(withScale: 0.7, velocity: -1)
        XCTAssertLessThan(zoomPercent, afterPinch)
        XCTAssertFalse(compass.exists)
        attachScreenshot("Pinch and zoom controls")
    }

    func testNativeRotationShowsCompassAndTapReturnsNorth() {
        launchMap()
        XCTAssertFalse(compass.exists)
        viewport.rotate(0.7, withVelocity: 1)
        XCTAssertTrue(compass.waitForExistence(timeout: 5))
        XCTAssertTrue(compass.isHittable)
        let rotatedHeading = compass.value as? String
        XCTAssertNotNil(rotatedHeading)
        attachScreenshot("Rotated map and compass")
        // Zooming while rotated retains the heading and keeps the compass available.
        let beforeZoom = zoomPercent
        viewport.pinch(withScale: 1.3, velocity: 1)
        XCTAssertGreaterThan(zoomPercent, beforeZoom)
        XCTAssertTrue(compass.exists)
        XCTAssertEqual(compass.value as? String, rotatedHeading)
        compass.tap()
        XCTAssertTrue(compass.waitForNonExistence(timeout: 5))
        attachScreenshot("North-up after compass reset")
        viewport.rotate(-0.5, withVelocity: -1)
        XCTAssertTrue(compass.waitForExistence(timeout: 5))
        XCTAssertNotEqual(compass.value as? String, rotatedHeading)
        compass.tap()
        XCTAssertTrue(compass.waitForNonExistence(timeout: 5))
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
