import XCTest

/// Named, focused flows invoked by scripts/run-ui-flow.sh.
final class UIFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppearanceChooserOpensFromSettings() {
        let app = launchFixtureApp()
        XCTAssertTrue(app.buttons["tab.me"].waitForExistence(timeout: 10))
        // iOS 27 can report {-1, -1} as the custom dock's AX hit point.
        app.buttons["tab.me"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        // Appearance moved from Today's retired palette/tip to Settings.
        let theme = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Theme")).firstMatch
        reveal(theme, in: app)
        theme.tap()
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 5))
        let indigo = app.buttons["Indigo"]
        XCTAssertTrue(indigo.waitForExistence(timeout: 5))
        indigo.tap()
        XCTAssertEqual(indigo.value as? String, "Selected")
        capture(app, name: "Appearance chooser from Settings")

        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        reveal(theme, in: app)
        XCTAssertTrue(theme.label.contains("Indigo"))
        theme.tap()
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Indigo"].value as? String, "Selected")
        capture(app, name: "Retained theme after reopening chooser")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
