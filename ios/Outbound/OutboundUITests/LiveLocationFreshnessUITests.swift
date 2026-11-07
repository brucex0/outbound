import XCTest

/// Focused live-location freshness UI checks for the group map.
///
/// The app publishes/subscribes to Ably in this build, so these tests cover the
/// display and freshness side that ships with the one-second publication change:
/// localized update age, reported GPS accuracy, ages advancing with no incoming
/// fixes, and recovery checkpoints never moving a participant backwards.
final class LiveLocationFreshnessUITests: XCTestCase {
    @MainActor
    func testLiveGroupPillsShowUpdateAgeAndAccuracyAndAgeOutWithoutNewFixes() throws {
        continueAfterFailure = false
        let fixture = try LiveLocationFixture()
        let baseURL = try fixture.start()
        defer { fixture.stop() }
        let baseArguments = ["-OutboundAPIBaseURL", baseURL, "-preferred_session_page_v1", "map"]
        // Settle first-install permissions before arming the group fixture.
        let app = launchFixtureApp(extraArguments: baseArguments)
        app.terminate()
        app.launchArguments += ["-OutboundGroupRecoveryUITestSetup", "-OutboundUITestLiveLocationSingleFix"]
        app.launch()
        dismissFixturePermissionAlerts(app)

        let start = app.buttons["tab.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), app.debugDescription)
        start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Pause activity"].waitForExistence(timeout: 20), app.debugDescription)

        let joined = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            fixture.count("POST", "/live/group-runs/activity-events/\(LiveLocationFixture.eventID)") == 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [joined], timeout: 10), .completed,
                       "The recording start must join the live group session exactly once; got \(fixture.count("POST", "/live/group-runs/activity-events/\(LiveLocationFixture.eventID)"))")

        let alice = app.buttons["live.group.participant.person-2"]
        XCTAssertTrue(alice.waitForExistence(timeout: 20), app.debugDescription)
        let maya = app.buttons["live.group.participant.person-3"]
        XCTAssertTrue(maya.waitForExistence(timeout: 10), app.debugDescription)

        // The first recovery checkpoint carries an older measurement at a
        // different coordinate. Merging must keep the fresh join snapshot.
        let checkpointed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            fixture.count("PATCH", "/live/group-runs/\(LiveLocationFixture.sessionID)/participants/me/location") >= 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [checkpointed], timeout: 15), .completed,
                       "Recording must publish a recovery checkpoint")
        XCTAssertEqual(
            fixture.count("PATCH", "/live/group-runs/\(LiveLocationFixture.sessionID)/participants/me/location"), 1,
            "The single measured fix must produce exactly one recovery checkpoint"
        )

        let aliceValue = alice.value as? String ?? ""
        XCTAssertTrue(aliceValue.hasPrefix("Sharing location"), aliceValue)
        XCTAssertTrue(aliceValue.contains("Updated "), "Fresh fix must not be replaced by an older checkpoint: \(aliceValue)")
        XCTAssertTrue(aliceValue.contains("GPS accuracy ±12 m"), aliceValue)

        let mayaValue = maya.value as? String ?? ""
        XCTAssertTrue(mayaValue.contains("Last seen "), "A fix older than 15 seconds must read as stale: \(mayaValue)")
        XCTAssertFalse(mayaValue.contains("GPS accuracy"), "Unreported accuracy must not be invented: \(mayaValue)")

        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Live group freshness fresh and stale pills"
        capture.lifetime = .keepAlways
        add(capture)

        // No new fixes arrive: the one-second display clock alone must age the pin
        // out of the freshness window.
        let checkpointCount = fixture.count("PATCH", "/live/group-runs/\(LiveLocationFixture.sessionID)/participants/me/location")
        let agedOut = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "Last seen "),
            object: alice
        )
        XCTAssertEqual(XCTWaiter.wait(for: [agedOut], timeout: 30), .completed,
                       "Alice must age out without an incoming fix: \(alice.value as? String ?? "")")
        XCTAssertEqual(
            fixture.count("PATCH", "/live/group-runs/\(LiveLocationFixture.sessionID)/participants/me/location"),
            checkpointCount,
            "Expiring a pin must not need a new location write"
        )
        let agedCapture = XCTAttachment(screenshot: app.screenshot())
        agedCapture.name = "Live group freshness aged out without new fixes"
        agedCapture.lifetime = .keepAlways
        add(agedCapture)

        // The map page only exposes Finish once the session is paused.
        let pause = app.buttons["Pause activity"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10), app.debugDescription)
        pause.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Resume activity"].waitForExistence(timeout: 10), app.debugDescription)
        let finish = app.buttons["Finish activity"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 10), app.debugDescription)
        finish.tap()
        XCTAssertTrue(app.buttons["ClosePostRunSummaryButton"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(
            fixture.count("POST", "/live/group-runs/\(LiveLocationFixture.sessionID)/participants/me/finish"), 1,
            "Finishing must still end the live share"
        )
        discardReview(app)
    }
}
