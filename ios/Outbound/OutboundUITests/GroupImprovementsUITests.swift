import XCTest

final class GroupImprovementsUITests: XCTestCase {
    @MainActor
    private func launch(_ fixture: GroupImprovementsFixture) throws -> XCUIApplication {
        continueAfterFailure = false
        let app = launchFixtureApp(extraArguments: ["-OutboundAPIBaseURL", try fixture.start(), "-OutboundGroupNetworkUITest"])
        XCTAssertTrue(app.buttons["tab.social"].waitForExistence(timeout: 20), app.debugDescription)
        // A first-install permission interruption can consume the first tap.
        // Require the actual Social controls before advancing the scenario.
        for _ in 0..<3 {
            app.buttons["tab.social"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if app.buttons["Groups"].waitForExistence(timeout: 3) { break }
            dismissFixturePermissionAlerts(app)
        }
        XCTAssertTrue(app.buttons["Groups"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Groups"].tap()
        return app
    }

    @MainActor
    private func openGroup(_ app: XCUIApplication) {
        let group = app.staticTexts["Golden Gate Community"].firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 10), app.debugDescription)
        group.tap()
        XCTAssertTrue(app.buttons["Group settings"].waitForExistence(timeout: 10) || app.buttons["group.invite.members"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor
    func testOwnerSavesPoliciesAndReviewsAcceptedMemberInvitations() throws {
        let fixture = try GroupImprovementsFixture()
        defer { fixture.stop() }
        let app = try launch(fixture)
        openGroup(app)
        app.buttons["Group settings"].tap()
        let settings = app.buttons["group.membership.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        settings.tap()
        let approval = app.switches["group.membership.approval_required"]
        XCTAssertTrue(approval.waitForExistence(timeout: 5), app.debugDescription)
        if approval.switches.firstMatch.exists { approval.switches.firstMatch.tap() } else { approval.tap() }
        app.buttons["group.membership.save"].tap()
        waitFor { !fixture.bodies("PATCH /social/groups/ui-test-group").isEmpty }
        XCTAssertEqual(fixture.bodies("PATCH /social/groups/ui-test-group").last?["memberInviteApprovalRequired"] as? Bool, false)
        let approve = app.buttons["group.request.approve.approve-request"]
        reveal(approve, in: app)
        approve.tap()
        let deny = app.buttons["group.request.deny.deny-request"]
        reveal(deny, in: app)
        deny.tap()
        XCTAssertTrue(app.staticTexts["No membership requests to review"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(fixture.bodies("POST /social/groups/ui-test-group/join-requests/approve-request/approve").count, 1)
        XCTAssertEqual(fixture.bodies("POST /social/groups/ui-test-group/join-requests/deny-request/deny").count, 1)
        attach(app, name: "Owner membership review")
    }

    @MainActor
    func testOrdinaryMemberCanInviteConnection() throws {
        let fixture = try GroupImprovementsFixture(viewer: "member")
        defer { fixture.stop() }
        let app = try launch(fixture)
        openGroup(app)
        XCTAssertFalse(app.buttons["Group settings"].exists)
        app.buttons["group.invite.members"].firstMatch.tap()
        let connection = app.buttons["group.invite.connection.fixture-target"]
        XCTAssertTrue(connection.waitForExistence(timeout: 10), app.debugDescription)
        connection.tap()
        app.buttons["group.invite.send"].tap()
        waitFor { fixture.bodies("POST /social/groups/ui-test-group/invitations").count == 1 }
        XCTAssertEqual(fixture.bodies("POST /social/groups/ui-test-group/invitations").first?["recipientUserIds"] as? [String], ["fixture-target"])
    }

    @MainActor
    func testAcceptanceWaitsForApprovalAndCanBeWithdrawn() throws {
        let fixture = try GroupImprovementsFixture(viewer: "invitee")
        defer { fixture.stop() }
        let app = try launch(fixture)
        let invitation = app.buttons["group.invitation.open.fixture-invitation"]
        XCTAssertTrue(invitation.waitForExistence(timeout: 10), app.debugDescription)
        invitation.tap()
        let accept = app.buttons["group.invitation.preview.accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10), app.debugDescription)
        accept.tap()
        XCTAssertTrue(app.staticTexts["group.membership.pending"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["group.invitation.preview.accept"].exists)
        XCTAssertFalse(app.buttons["Group settings"].exists)
        XCTAssertFalse(app.buttons["group.plan.activity"].exists)
        attach(app, name: "Accepted invitation pending approval")
        app.buttons["group.invitation.preview.decline"].tap()
        XCTAssertTrue(invitation.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(fixture.bodies("POST /social/groups/invitations/fixture-invitation/accept").count, 1)
        XCTAssertEqual(fixture.bodies("POST /social/groups/invitations/fixture-invitation/decline").count, 1)
    }

    @MainActor
    func testWeeklyActivityRetainsDraftAndIdempotencyKeyAfterFailure() throws {
        let fixture = try GroupImprovementsFixture()
        defer { fixture.stop() }
        let app = try launch(fixture)
        openGroup(app)
        let plan = app.buttons["group.plan.activity"]
        reveal(plan, in: app)
        plan.tap()
        let title = app.textFields.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        title.tap()
        title.typeText("Weekly fixture activity\n")
        let done = app.keyboards.buttons["Done"]
        if done.exists { done.tap() }
        let repeats = app.switches["group.activity.repeat"]
        reveal(repeats, in: app)
        repeats.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let monday = app.switches["group.activity.weekday.1"]
        reveal(monday, in: app)
        if monday.value as? String != "1" { monday.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
        let save = app.buttons["group.activity.save"]
        reveal(save, in: app, maxSwipes: 14)
        save.tap()
        XCTAssertTrue(app.staticTexts["Activity could not be saved. Try again."].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(save.exists, "A failed save must keep the composer open")
        save.tap()
        waitFor { fixture.bodies("POST /social/activity-events").count == 2 }
        let bodies = fixture.bodies("POST /social/activity-events")
        XCTAssertEqual(bodies[0]["idempotencyKey"] as? String, bodies[1]["idempotencyKey"] as? String)
        XCTAssertEqual(bodies[1]["title"] as? String, "Weekly fixture activity")
        XCTAssertEqual(bodies[1]["groupId"] as? String, "ui-test-group")
        let rule = try XCTUnwrap(bodies[1]["recurrence"] as? [String: Any])
        XCTAssertEqual(rule["intervalWeeks"] as? Int, 1)
        XCTAssertTrue((rule["weekdays"] as? [Int])?.contains(1) == true)
        XCTAssertNotNil(rule["timeZone"] as? String)
        XCTAssertNil(rule["untilDate"])
        XCTAssertTrue(app.buttons["group.plan.activity"].waitForExistence(timeout: 10), app.debugDescription)
        attach(app, name: "Created weekly Group activity")
    }

    @MainActor
    private func waitFor(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, file: file, line: line)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
