import XCTest

final class GroupRecoveryUITests: XCTestCase {
    @MainActor
    func testSingleGroupRecordingSurvivesSceneReentryAndRestarts() throws {
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

        // Repeated scene transitions must preserve the same paused recording.
        for entry in 1...3 {
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(app.buttons["Resume activity"].waitForExistence(timeout: 10),
                          "Activation \(entry) must retain the paused recording: \(app.debugDescription)")
            XCTAssertFalse(app.buttons["Pause activity"].exists)
            XCTAssertEqual(app.buttons.matching(identifier: "Finish activity").count, 1)
            verifyGroupUI(in: app)
        }

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
        // A second coordinator must not leave a recoverable copy after finishing.
        app.terminate()
        app.launch()
        dismissFixturePermissionAlerts(app)
        XCTAssertTrue(app.buttons["tab.start"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["Resume activity"].exists)
        XCTAssertFalse(app.buttons["Finish activity"].exists)
    }

    @MainActor
    func testTodayJoinAndIndependentLocationSharing() throws {
        continueAfterFailure = false
        let fixture = try GroupRecoveryFixture()
        let baseURL = try fixture.start()
        defer { fixture.stop() }
        let app = launchFixtureApp(extraArguments: ["-OutboundAPIBaseURL", baseURL,
            "-preferred_session_page_v1", "map"])
        app.terminate()
        app.launchArguments.append("-OutboundTodayGroupJoinUITest")
        app.launch()
        dismissFixturePermissionAlerts(app)

        let join = app.buttons["today.group.join"]
        XCTAssertTrue(join.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(join.value as? String, "0")
        join.tap()
        XCTAssertEqual(join.value as? String, "1")
        XCTAssertEqual(fixture.requestCount("POST /live/group-runs/activity-events/ui-recovery-event"), 0,
                       "Joining a recording must not consent to location sharing")
        let share = app.switches["today.group.shareLocation"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            fixture.requestCount("POST /live/group-runs/activity-events/ui-recovery-event") == 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        let start = app.buttons["tab.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let pause = app.buttons["Pause activity"]
        XCTAssertTrue(pause.waitForExistence(timeout: 20), app.debugDescription)
        pause.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Resume activity"].waitForExistence(timeout: 10))
        verifyGroupUI(in: app)

        let panel = app.buttons.matching(identifier: "live.group.activity").firstMatch
        panel.tap()
        let liveSwitch = app.switches["live.group.shareLocation"]
        XCTAssertTrue(liveSwitch.waitForExistence(timeout: 5))
        liveSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: liveSwitch)
        XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 5), .completed)
        XCTAssertEqual(app.buttons["live.group.participant.person-1"].value as? String, "Not sharing location")
        XCTAssertEqual(app.buttons["live.group.participant.person-2"].value as? String, "Sharing location",
                       "Stopping my sharing must preserve the other attendee's status")
        panel.tap()
        app.buttons["Finish activity"].tap()
        XCTAssertTrue(app.buttons["ClosePostRunSummaryButton"].waitForExistence(timeout: 10))
        discardReview(app)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-OutboundUITestResetRecording" }
        app.launch()
        dismissFixturePermissionAlerts(app)
        XCTAssertTrue(app.buttons["tab.start"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["today.group.join"].exists)
        XCTAssertFalse(app.switches["today.group.shareLocation"].exists)
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
        let locationSwitch = app.switches["live.group.shareLocation"]
        XCTAssertTrue(locationSwitch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(locationSwitch.value as? String, "1")
        panel.tap()
    }
}
