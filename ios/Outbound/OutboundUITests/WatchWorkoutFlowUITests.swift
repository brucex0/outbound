import XCTest

/// Runs entirely on an unpaired iPhone simulator. Watch scenarios use encoded
/// mirroring messages, not fabricated UI results or real HealthKit sensor data.
final class WatchWorkoutFlowUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testUnavailableWatchStillRecordsAndSavesOnPhone() throws {
        let app = launch("unavailable")
        expect(app, "connection=unavailable")
        expect(app, "ownership=phone_write_back")
        expect(app, "launches=1")
        try pauseResumeFinishAndSave(app)
    }

    @MainActor
    func testWatchPreparationTimeoutFallsBackWithoutStoppingRecording() throws {
        let app = launch("timeout")
        expect(app, "connection=unavailable", timeout: 10)
        expect(app, "ownership=phone_write_back")
        XCTAssertTrue(app.buttons["Pause activity"].exists)
        try pauseResumeFinishAndSave(app)
    }

    @MainActor
    func testConnectedWatchKeepsHealthOwnershipThroughPhoneControlsAndSave() throws {
        let app = launch("connected")
        expect(app, "connection=connected")
        expect(app, "ownership=apple_watch_primary")
        expect(app, "heart=166")
        expect(app, "phone_heart=166")
        try pauseResumeFinish(app)
        expect(app, "outbound=pause,resume,pause,finishRequest")
        expect(app, "reference=saved")
        expect(app, "ownership=apple_watch_primary")
        try saveAndExit(app, ownership: "apple_watch_primary", reference: "saved")
    }

    @MainActor
    func testRemoteControlsDisconnectReconnectAndStaleMessages() throws {
        let app = launch("connected")
        app.buttons["WatchFixture-pause"].tap()
        XCTAssertTrue(app.buttons["Resume activity"].waitForExistence(timeout: 5))
        app.buttons["WatchFixture-resume"].tap()
        XCTAssertTrue(app.buttons["Pause activity"].waitForExistence(timeout: 5))
        app.buttons["WatchFixture-disconnect"].tap()
        expect(app, "connection=disconnected")
        XCTAssertTrue(app.buttons["Pause activity"].exists, "Losing Watch transport must not stop phone recording")
        app.buttons["WatchFixture-reconnect"].tap()
        expect(app, "connection=connected")
        app.buttons["WatchFixture-stale"].tap()
        expect(app, "lifecycle=active")
        XCTAssertTrue(app.buttons["Pause activity"].exists, "Duplicate or unrelated-session pause messages must be ignored")
        try pauseResumeFinish(app)
        expect(app, "reference=saved")
        try saveAndExit(app, ownership: "apple_watch_primary", reference: "saved")
    }

    @MainActor
    func testPhoneOnlyModeNeverLaunchesPlainstrideWatch() throws {
        let app = launch("phone_only")
        expect(app, "ownership=phone_write_back")
        expect(app, "launches=0")
        expect(app, "heart=0")
        try pauseResumeFinish(app)
        try saveAndExit(app)
    }

    @MainActor
    func testWatchSaveFailureRestoresPhoneWriteBack() throws {
        let app = launch("save_failure")
        expect(app, "ownership=apple_watch_primary")
        try pauseResumeFinish(app)
        expect(app, "ownership=phone_write_back")
        expect(app, "reference=none")
        try saveAndExit(app)
    }

    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-OutboundUseMockMusic", "-OutboundDisableFirebase", "-OutboundSkipOnboarding",
            "-OutboundUITestSeedData", "-OutboundUITestLive10K",
            "-OutboundUITestWatchScenario", scenario,
            "-new_user_onboarding_completed_v2.UI test session", "YES",
            "-measurement_unit_system_v1", "metric",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Pause activity"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["WatchFlowProbe"].exists)
        return app
    }

    @MainActor
    private func expect(_ app: XCUIApplication, _ fragment: String, timeout: TimeInterval = 5,
                        file: StaticString = #filePath, line: UInt = #line) {
        let probe = app.staticTexts["WatchFlowProbe"]
        let predicate = NSPredicate(format: "value CONTAINS %@", fragment)
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: probe)], timeout: timeout) == .completed,
                      "Expected \(fragment); got \(probe.value ?? "missing")", file: file, line: line)
    }

    @MainActor
    private func pauseResumeFinish(_ app: XCUIApplication) throws {
        app.buttons["Pause activity"].press(forDuration: 1.1)
        XCTAssertTrue(app.buttons["Resume activity"].waitForExistence(timeout: 5))
        app.buttons["Resume activity"].tap()
        XCTAssertTrue(app.buttons["Pause activity"].waitForExistence(timeout: 5))
        app.buttons["Pause activity"].press(forDuration: 1.1)
        XCTAssertTrue(app.buttons["Finish activity"].waitForExistence(timeout: 5))
        app.buttons["Finish activity"].tap()
        XCTAssertTrue(app.buttons["Save activity"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func pauseResumeFinishAndSave(_ app: XCUIApplication) throws {
        try pauseResumeFinish(app)
        try saveAndExit(app)
    }

    @MainActor
    private func saveAndExit(_ app: XCUIApplication, ownership: String = "phone_write_back", reference: String = "none") throws {
        expect(app, "phase=review")
        app.buttons["Save activity"].tap()
        let message = app.staticTexts["You made time for this today."]
        XCTAssertTrue(message.waitForExistence(timeout: 15), "Local save must reach the celebration without a Watch or server response")
        expect(app, "saved_count=1")
        expect(app, "saved_ownership=" + ownership)
        expect(app, "saved_reference=" + reference)
        let done = app.buttons["Done"]
        for _ in 0..<5 where !done.isHittable { app.swipeUp() }
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: message)], timeout: 5) == .completed)
        XCTAssertFalse(app.buttons["Save activity"].exists, "Done must close the saved review")
        XCTAssertFalse(app.buttons["Pause activity"].exists, "Leaving the celebration must not start another recording")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
