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
        app.buttons["Edit New flight route"].firstMatch.click()
        app.buttons["View in cockpit"].click()
        XCTAssertTrue(app.buttons["pilot-next-step"].waitForExistence(timeout: 4))
        app.typeKey("2", modifierFlags: [.command])
        app.buttons["Close route library"].click()
        app.typeKey("3", modifierFlags: [.command])
        XCTAssertTrue(app.staticTexts["No live video"].waitForExistence(timeout: 5))
        attach(window, "04-virtual-cockpit")
        XCTAssertTrue(app.buttons["pilot-next-step"].exists)
        app.typeKey("/", modifierFlags: [.shift])
        XCTAssertTrue(app.staticTexts["Keyboard guide"].waitForExistence(timeout: 4))
        app.buttons["Practice keys"].click()
        XCTAssertTrue(app.staticTexts["Local practice"].waitForExistence(timeout: 4))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["Practice keys"].waitForExistence(timeout: 4))
        attach(window, "05-pilot-keyboard-guide")
        app.buttons["Close key guide"].click()
        app.buttons["Flight setup"].click()
        XCTAssertTrue(app.buttons["Pair iPhone bridge"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["Authorize real aircraft (15m)"].isEnabled)
        attach(window, "06-flight-setup")
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
