import XCTest

final class GroupRecoveryUITests: XCTestCase {
    @MainActor
    func testGroupRecordingSurvivesTwoAppRestarts() throws {
        continueAfterFailure = false
        let fixture = try GroupRecoveryFixture()
        let baseURL = try fixture.start()
        defer { fixture.stop() }
        let app = XCUIApplication()
        let baseArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-OutboundDisableFirebase", "-OutboundUseMockMusic", "-OutboundSkipOnboarding",
            "-OutboundUITestSeedData", "-OutboundAPIBaseURL", baseURL,
            "-preferred_session_page_v1", "map", "-voice_guide_enabled_v1", "NO",
            "-home_widget_onboarding_seen_v1", "YES",
            "-push_notification_permission_primer_seen_v1", "YES",
            "-watch.startWatchApp", "NO", "-auto_pause_running_enabled_v1", "NO",
            "-new_user_onboarding_completed_v2.UI test session", "YES"
        ]
        app.launchArguments = baseArguments + ["-OutboundGroupRecoveryUITestSetup", "-OutboundUITestResetRecording"]
        app.launch()
        dismissLocationDialog(in: app)
        let start = app.buttons["tab.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), app.debugDescription)
        start.tap()
        let pause = app.buttons["Pause activity"]
        XCTAssertTrue(pause.waitForExistence(timeout: 20), app.debugDescription)
        pause.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Resume activity"].waitForExistence(timeout: 10))
        verifyGroupUI(in: app)

        for restart in 1...2 {
            app.terminate()
            // Deliberately omit setup: all event/session context must come from disk.
            app.launchArguments = baseArguments
            app.launch()
            dismissLocationDialog(in: app)
            XCTAssertTrue(app.buttons["Resume activity"].waitForExistence(timeout: 20), "Restart \(restart): \(app.debugDescription)")
            verifyGroupUI(in: app)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Group recovery restart \(restart)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertEqual(fixture.requestCount("POST /live/group-runs/activity-events/ui-recovery-event"), 1,
                       "Recovery must reuse the original live group session")
        XCTAssertGreaterThanOrEqual(fixture.requestCount("GET /live/group-runs/ui-recovery-live"), 2)
        app.buttons["Finish activity"].tap()
        XCTAssertTrue(app.buttons["ClosePostRunSummaryButton"].waitForExistence(timeout: 5))
        discardReview(app)
    }

    @MainActor
    private func verifyGroupUI(in app: XCUIApplication) {
        let panel = app.buttons.matching(identifier: "live.group.activity")
            .matching(NSPredicate(format: "label CONTAINS %@", "Recovery group run")).firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(panel.label.contains("Recovery group run"), panel.label)
        XCTAssertTrue(panel.isHittable)
        let firstPill = app.buttons["live.group.participant.person-1"]
        XCTAssertTrue(firstPill.waitForExistence(timeout: 15), app.debugDescription)
        let pills = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live.group.participant."))
        XCTAssertEqual(pills.count, 5)
        XCTAssertEqual(app.buttons.matching(identifier: "assistant.launcher").count, 1)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Open assistant")).count, 1)
        XCTAssertEqual(firstPill.value as? String, "Sharing location")
        XCTAssertTrue(app.buttons["live.group.participant.person-2"].label.contains("Alice"))
        panel.tap()
        XCTAssertTrue(app.buttons["Stop sharing"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["Share live map with attendees"].exists)
        panel.tap()
    }

    @MainActor
    private func dismissLocationDialog(in app: XCUIApplication) {
        if app.buttons["Close"].waitForExistence(timeout: 2), app.staticTexts["Enable location"].exists {
            app.buttons["Close"].tap()
        }
    }
}
