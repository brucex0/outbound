import XCTest

final class GroupRecoveryUITests: XCTestCase {
    @MainActor
    func testGroupRecordingSurvivesTwoAppRestarts() throws {
        continueAfterFailure = false
        let fixture = try GroupRecoveryFixture()
        let baseURL = try fixture.start()
        defer { fixture.stop() }
        let baseArguments = [
            "-OutboundAPIBaseURL", baseURL, "-preferred_session_page_v1", "map"
        ]
        // Settle first-install system permissions before arming the recovery
        // fixture. This test owns recovery, not permission-prompt/start timing.
        let app = launchFixtureApp(extraArguments: baseArguments)
        app.terminate()
        app.launchArguments.append("-OutboundGroupRecoveryUITestSetup")
        app.launch()
        dismissFixturePermissionAlerts(app)
        let joined = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            fixture.requestCount("POST /live/group-runs/activity-events/ui-recovery-event") == 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [joined], timeout: 10), .completed)
        let start = app.buttons["tab.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), app.debugDescription)
        // iOS 27 can report {-1, -1} for this custom dock's AX hit point.
        // Tap its visible bounds, then require the real recording controls.
        XCTAssertTrue(app.frame.contains(start.frame))
        start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let pause = app.buttons["Pause activity"]
        XCTAssertTrue(pause.waitForExistence(timeout: 20), app.debugDescription)
        pause.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Resume activity"].waitForExistence(timeout: 10))
        verifyGroupUI(in: app)

        for restart in 1...2 {
            app.terminate()
            // Deliberately omit setup: all event/session context must come from disk.
            app.launchArguments.removeAll { $0 == "-OutboundGroupRecoveryUITestSetup" || $0 == "-OutboundUITestResetRecording" }
            app.launch()
            dismissFixturePermissionAlerts(app)
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
}
