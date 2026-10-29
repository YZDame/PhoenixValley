import XCTest

@MainActor
final class RealMapImportUITests: XCTestCase {
    private var app: XCUIApplication!

    private func openImporter() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let create = app.buttons["新建"]
        if !create.exists {
            app.buttons["显示边栏"].tap()
        }
        XCTAssertTrue(create.waitForExistence(timeout: 30))
        create.tap()
        let entry = app.buttons["import-real-map"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.buttons["real-map-download"].waitForExistence(timeout: 5))
    }

    func testLiveOSMPreviewSaveAndReload() {
        openImporter()
        let mapName = "OSM UI validation \(UUID().uuidString.prefix(6))"
        let name = app.textFields["real-map-name"]
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + mapName)
        app.buttons["real-map-download"].tap()
        let save = app.buttons["real-map-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 120), app.debugDescription)
        let attribution = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "OpenStreetMap contributors")).firstMatch
        for _ in 0..<5 {
            if attribution.exists { break }
            app.swipeUp()
        }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Real map preview hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTAssertTrue(attribution.exists, app.debugDescription)
        attach("Real OSM import preview")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[mapName].waitForExistence(timeout: 10))
        let source = app.descendants(matching: .any)["real-map-attribution"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(source.isHittable)
        attach("Imported real-world map")
        app.terminate()
        app.launch()
        if !app.buttons["新建"].exists {
            app.buttons["显示边栏"].tap()
        }
        XCTAssertTrue(app.staticTexts[mapName].waitForExistence(timeout: 30))
        attach("Imported map after process restart")
    }

    func testInvalidLocationDoesNotOfferSave() {
        openImporter()
        let latitude = app.textFields["real-map-latitude"]
        latitude.tap()
        latitude.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "999")
        app.buttons["real-map-download"].tap()
        XCTAssertTrue(app.staticTexts["real-map-error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["real-map-save"].exists)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["real-map-download"].waitForNonExistence(timeout: 5))
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
