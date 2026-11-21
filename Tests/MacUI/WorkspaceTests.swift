import XCTest

final class WorkspaceTests: XCTestCase {
    func testProjectRoutesAndCockpit() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchEnvironment["GROUNDSTATION_TEMPORARY_ROUTES"] = "1"
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        let panel = app.buttons["Hide team panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        attach(window, "01-project")
        panel.click()
        app.buttons["Show team panel"].click()
        app.buttons["Map layers"].click()
        XCTAssertTrue(app.checkBoxes["Flight track"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        app.buttons["nav-Flight Route Library"].click()
        XCTAssertTrue(app.staticTexts["Route Library"].waitForExistence(timeout: 5))
        app.buttons["Create route"].firstMatch.click()
        let field = app.textFields["Latitude (−90 to 90)"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("54.5")
        let longitude = app.textFields["Longitude (−180 to 180)"]
        longitude.click()
        longitude.typeText("-3")
        app.buttons["Add waypoint"].click()
        XCTAssertTrue(app.staticTexts["Waypoints (1)"].waitForExistence(timeout: 5))
        let map = app.descendants(matching: .any).matching(identifier: "GroundStationMap").firstMatch
        let rendered = expectation(for: NSPredicate(format: "value == %@", "Map ready"), evaluatedWith: map)
        // MapKit tile availability is external; capture the actual native state in either case.
        _ = XCTWaiter.wait(for: [rendered], timeout: 12)
        attach(window, "03-waypoint-editor")
        app.buttons["Back to Route Library"].click()
        XCTAssertTrue(app.buttons["Edit New flight route"].waitForExistence(timeout: 5))
        attach(window, "02-route-library")
        app.buttons["Close route library"].click()
        app.buttons["nav-Virtual Cockpit"].click()
        XCTAssertTrue(app.staticTexts["No live video"].waitForExistence(timeout: 5))
        attach(window, "04-virtual-cockpit")
        app.buttons["Return to project"].click()
        app.buttons["nav-Activity"].click()
        XCTAssertTrue(app.staticTexts["Session activity"].waitForExistence(timeout: 5))
        app.buttons["Bridge connection"].click()
        XCTAssertTrue(app.secureTextFields["Session code"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Connect"].isEnabled)
    }

    private func attach(_ window: XCUIElement, _ name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
