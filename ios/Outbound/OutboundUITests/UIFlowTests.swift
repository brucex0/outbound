import XCTest

/// Named, focused flows invoked by scripts/run-ui-flow.sh.
final class UIFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppearanceTipOpensChooserAndKeepsToolbarVisible() {
        let app = launchAppearanceTip()
        let tip = app.buttons["today.appearanceTip"]
        XCTAssertTrue(tip.waitForExistence(timeout: 10))
        assertToolbarVisible(app, tip: tip)
        capture(app, name: "Appearance tip and toolbar")
        tip.tap()
        assertChooserAndReturn(app)
    }

    @MainActor
    func testAppearancePaletteOpensChooserWhileTipVisible() {
        let app = launchAppearanceTip()
        let tip = app.buttons["today.appearanceTip"]
        XCTAssertTrue(tip.waitForExistence(timeout: 10))
        assertToolbarVisible(app, tip: tip)
        app.buttons["today.appearance"].tap()
        assertChooserAndReturn(app)
    }

    @MainActor
    private func launchAppearanceTip() -> XCUIApplication {
        let app = launchFixtureApp(extraArguments: [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-OutboundUseMockMusic", "-OutboundDisableFirebase",
            "-OutboundSkipOnboarding", "-OutboundUITestSeedData",
            "-new_user_onboarding_completed_v2.UI test session", "YES",
            "-home_widget_onboarding_seen_v1", "YES",
            "-push_notification_permission_primer_seen_v1", "YES",
            "-theme_discovery_tip_dismissed_v1", "NO",
            "-tooltip.theme_discovery.dismissed.v1", "NO",
            "-tooltip.theme_discovery.presentations.v1", "0",
            "-tooltip.daily.stamp.v1", "2000-01-01",
            "-tooltip.daily.count.v1", "0",
            "-tooltip.activity_overflow.dismissed.v1", "YES",
            "-tooltip.music_discovery.dismissed.v1", "YES",
            "-tooltip.cheer_me_on.dismissed.v1", "YES",
            "-tooltip.voice_guide.dismissed.v1", "YES",
            "-tooltip.shoes.dismissed.v1", "YES",
            "-tooltip.swipe_to_map.dismissed.v1", "YES",
        ])
        return app
    }

    @MainActor
    private func assertToolbarVisible(_ app: XCUIApplication, tip: XCUIElement) {
        for identifier in ["today.appearance", "today.conditions", "today.inbox", "today.overflow"] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.waitForExistence(timeout: 5), identifier)
            XCTAssertTrue(control.isHittable, identifier)
            XCTAssertFalse(control.frame.intersects(tip.frame), "Tip overlaps \(identifier)")
        }
    }

    @MainActor
    private func assertChooserAndReturn(_ app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Indigo"].exists)
        capture(app, name: "Appearance chooser")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["today.conditions"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.appearanceTip"].exists)
        XCTAssertTrue(app.buttons["today.inbox"].isHittable)
        XCTAssertTrue(app.buttons["today.overflow"].isHittable)
        capture(app, name: "Toolbar after appearance chooser")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
