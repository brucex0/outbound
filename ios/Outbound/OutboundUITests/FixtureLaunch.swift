import XCTest

extension XCTestCase {
    @MainActor
    func launchFixtureApp(extraArguments: [String] = [], resetRecording: Bool = true) -> XCUIApplication {
        addUIInterruptionMonitor(withDescription: "Fixture system permissions") { alert in
            for label in ["Allow While Using App", "Allow Once", "OK", "Allow"] {
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-OutboundUseMockMusic", "-OutboundDisableFirebase", "-OutboundSkipOnboarding",
            "-OutboundUITestSeedData", "-home_widget_onboarding_seen_v1", "YES",
            "-push_notification_permission_primer_seen_v1", "YES",
            "-new_user_onboarding_completed_v2.UI test session", "YES",
            "-voice_guide_enabled_v1", "NO", "-watch.startWatchApp", "NO",
            "-auto_pause_running_enabled_v1", "NO",
        ]
        if resetRecording { app.launchArguments.append("-OutboundUITestResetRecording") }
        app.launchArguments += extraArguments
        app.launch()
        dismissFixturePermissionAlerts(app)
        return app
    }

    @MainActor
    func dismissFixturePermissionAlerts(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 1) {
            for label in ["Allow While Using App", "Allow Once", "OK", "Allow"] {
                if springboard.alerts.buttons[label].exists { springboard.alerts.buttons[label].tap(); break }
            }
        }
        let locationAlert = app.alerts["Enable location"]
        if locationAlert.exists { locationAlert.buttons["Close"].tap() }
    }

    @MainActor
    func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8,
                file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Cannot reach \(element)\n\(app.debugDescription)", file: file, line: line)
    }

    @MainActor
    func discardReview(_ app: XCUIApplication) {
        app.buttons["ClosePostRunSummaryButton"].tap()
        let alert = app.alerts["Discard unsaved activity?"]
        if alert.waitForExistence(timeout: 1) { alert.buttons["Discard activity"].tap() }
    }
}
