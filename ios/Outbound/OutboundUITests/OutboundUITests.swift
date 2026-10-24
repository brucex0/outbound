//
//  OutboundUITests.swift
//  OutboundUITests
//
//  Created by Zhi Feng Xia on 4/26/26.
//

import XCTest

final class OutboundUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchSkipsLoginAndShowsPrimaryTabs() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["tab.start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.social"].exists)
        XCTAssertTrue(app.buttons["tab.me"].exists)
        XCTAssertTrue(app.buttons["today.conditions"].exists)
        XCTAssertFalse(app.textFields["Phone number"].exists)
    }

    @MainActor
    func testPrimaryNavigationAndSettings() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["tab.start"].waitForExistence(timeout: 5))
        app.buttons["tab.social"].tap()
        XCTAssertTrue(app.buttons["Feed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saturday waterfront 5K"].exists)
        XCTAssertTrue(app.staticTexts["Presidio Morning Run"].exists)

        app.buttons["tab.me"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Golden Gate Easy Run"].waitForExistence(timeout: 5))
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        reveal(app.buttons["Sign out"], in: app)
    }

    @MainActor
    func testSeededSocialFeedRunAndComments() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["tab.start"].waitForExistence(timeout: 5))
        app.buttons["tab.social"].tap()
        XCTAssertTrue(app.buttons["Feed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saturday waterfront 5K"].exists)
        XCTAssertTrue(app.staticTexts["Presidio Morning Run"].exists)

        let cheerButton = app.buttons["Cheer"].firstMatch
        XCTAssertTrue(cheerButton.waitForExistence(timeout: 5))
        XCTAssertEqual(cheerButton.value as? String, "2")
        cheerButton.tap()
        let cheered = app.buttons["Remove cheer"].firstMatch
        XCTAssertTrue(cheered.waitForExistence(timeout: 5))
        XCTAssertEqual(cheered.value as? String, "3")

        app.buttons["Comments"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Comments (1)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["See you next time!"].exists)
        app.buttons["Close comments"].tap()

        app.staticTexts["Saturday waterfront 5K"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Saturday waterfront 5K"].waitForExistence(timeout: 5))
        let join = app.buttons["Join activity"]
        reveal(join, in: app)
        join.tap()
        app.buttons["Crissy Field"].tap()
        reveal(app.buttons["Leave run"], in: app, maxSwipes: 12)
    }

    @MainActor
    func testSeededSocialConnectionsGroupsAndNotifications() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["tab.start"].waitForExistence(timeout: 5))
        app.buttons["tab.social"].tap()
        XCTAssertTrue(app.buttons["Feed"].waitForExistence(timeout: 5))

        app.buttons["People"].tap()
        XCTAssertTrue(app.staticTexts["Maya Chen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Maya Chen"].exists)
        XCTAssertTrue(app.staticTexts["Leo Martinez"].exists)
        XCTAssertTrue(app.staticTexts["Priya Shah"].exists)
        app.buttons["Accept connection request"].tap()
        XCTAssertTrue(app.buttons["Accept connection request"].waitForNonExistence(timeout: 5))

        app.staticTexts["Maya Chen"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        let disconnect = app.buttons["Disconnect"]
        XCTAssertTrue(disconnect.waitForExistence(timeout: 5))
        disconnect.tap()
        XCTAssertTrue(app.alerts["Remove connection?"].waitForExistence(timeout: 5))
        app.alerts["Remove connection?"].buttons["Cancel"].tap()
        XCTAssertTrue(disconnect.exists)
        disconnect.tap()
        app.alerts["Remove connection?"].buttons["Disconnect"].tap()
        XCTAssertTrue(app.buttons["People"].waitForExistence(timeout: 5))
        app.buttons["People"].tap()
        XCTAssertFalse(app.staticTexts["Maya Chen"].exists)
        reveal(app.buttons["Unblock Blocked Runner"], in: app)

        app.buttons["Groups"].tap()
        XCTAssertTrue(app.staticTexts["Bruce, Daniel, Rina's Group"].waitForExistence(timeout: 5))
        app.staticTexts["Bruce, Daniel, Rina's Group"].tap()
        XCTAssertTrue(app.staticTexts["Daniel Runner"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Notification Center"].tap()
        XCTAssertTrue(app.navigationBars["Notification Center"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Maya Chen cheered your activity."].exists)
        let invitation = app.buttons.containing(.staticText, identifier: "Maya Chen invited you to Saturday waterfront 5K.").firstMatch
        reveal(invitation, in: app)
        invitation.tap()
        XCTAssertTrue(app.navigationBars["Run invitation"].waitForExistence(timeout: 5))
        let accept = app.buttons["Meet in person"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        accept.tap()
        XCTAssertTrue(accept.waitForNonExistence(timeout: 5))

    }

    @MainActor
    func testSeededSocialDeclinesConnectionRequest() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["tab.start"].waitForExistence(timeout: 5))
        app.buttons["tab.social"].tap()
        XCTAssertTrue(app.buttons["Feed"].waitForExistence(timeout: 5))
        app.buttons["People"].tap()
        XCTAssertTrue(app.staticTexts["Maya Chen"].waitForExistence(timeout: 5))

        let declineButton = app.buttons["Decline connection request"]
        XCTAssertTrue(declineButton.waitForExistence(timeout: 5))
        declineButton.tap()
        XCTAssertTrue(declineButton.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Leo Martinez"].exists)
    }

    @MainActor
    func testGroupInvitePickerShowsSelectionState() throws {
        let app = launchApp()

        app.buttons["tab.social"].tap()
        XCTAssertTrue(app.buttons["Groups"].waitForExistence(timeout: 5))
        app.buttons["Groups"].tap()
        let groupName = "Bruce, Daniel, Rina's Group"
        let groupRow = app.staticTexts[groupName]
        XCTAssertTrue(groupRow.waitForExistence(timeout: 5))
        groupRow.tap()
        XCTAssertTrue(app.navigationBars[groupName].waitForExistence(timeout: 5))
        app.buttons["group.invite.members"].tap()
        XCTAssertTrue(app.navigationBars["Invite connections"].waitForExistence(timeout: 5))

        let maya = app.buttons["group.invite.connection.ui-maya"]
        XCTAssertTrue(maya.waitForExistence(timeout: 5))
        XCTAssertEqual(maya.value as? String, "Not selected")
        maya.tap()
        XCTAssertEqual(maya.value as? String, "Selected")
        maya.tap()
        XCTAssertEqual(maya.value as? String, "Not selected")
    }

    @MainActor
    func testGroupMembersAndWeeklyThemePersistAfterReopening() throws {
        let app = launchApp()

        app.buttons["tab.social"].tap()
        XCTAssertTrue(app.buttons["Groups"].waitForExistence(timeout: 5))
        app.buttons["Groups"].tap()

        let groupName = "Bruce, Daniel, Rina's Group"
        let groupRow = app.staticTexts[groupName]
        XCTAssertTrue(groupRow.waitForExistence(timeout: 5))
        groupRow.tap()

        XCTAssertTrue(app.navigationBars[groupName].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["3 members"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Daniel Runner"].exists)
        XCTAssertTrue(app.staticTexts["Rina Runner"].exists)
        XCTAssertTrue(app.staticTexts["Build consistency"].exists)

        app.buttons["group.invite.members"].tap()
        XCTAssertTrue(app.navigationBars["Invite connections"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["group.invite.connection.ui-maya"].exists)
        app.buttons["Close"].tap()

        app.buttons["group.theme.edit"].tap()
        app.buttons["group.theme.option.one_small_step"].tap()
        app.buttons["group.focus.save"].tap()
        XCTAssertTrue(app.navigationBars["Weekly Theme"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["One small step"].waitForExistence(timeout: 5))

        app.navigationBars[groupName].buttons.firstMatch.tap()
        let groupsTab = app.buttons["Groups"]
        XCTAssertTrue(groupsTab.waitForExistence(timeout: 5))
        groupsTab.tap()
        app.staticTexts[groupName].tap()

        XCTAssertTrue(app.navigationBars[groupName].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["3 members"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Daniel Runner"].exists)
        XCTAssertTrue(app.staticTexts["Rina Runner"].exists)
        XCTAssertTrue(app.staticTexts["One small step"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTodayFreestyleStartOpensRecordingFlowAndCanFinish() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["tab.start"].waitForExistence(timeout: 5))
        let outdoor = app.buttons["Outdoor"].firstMatch
        // Setup options are a horizontal row; bring Outdoor into view without
        // replacing real start/countdown behavior with a seeded recording.
        for _ in 0..<6 {
            if outdoor.exists && outdoor.frame.intersects(app.frame) && outdoor.isHittable { break }
            app.scrollViews["activity.launch.options"].swipeLeft()
        }
        XCTAssertTrue(outdoor.isHittable)
        outdoor.tap()
        XCTAssertTrue(app.buttons["Indoor"].exists)
        app.buttons["tab.start"].tap()
        XCTAssertTrue(app.buttons["Pause activity"].waitForExistence(timeout: 12))
        app.buttons["Pause activity"].press(forDuration: 1.1)
        XCTAssertTrue(app.buttons["Finish activity"].waitForExistence(timeout: 5))
        app.buttons["Finish activity"].tap()
        XCTAssertTrue(app.buttons["PostRunSaveEligibilityExplanation"].waitForExistence(timeout: 5)
                      || app.staticTexts["Record at least 5 minutes or 500 meters to save this activity."].exists)
        discardReview(app)
        XCTAssertTrue(app.buttons["tab.start"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSeededLive10KRunMetricsAndLifecycle() throws {
        let app = launchApp(extraArguments: [
            "-OutboundUITestLive10K",
            "-measurement_unit_system_v1",
            "metric",
        ])

        XCTAssertTrue(app.buttons["Pause activity"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["7.8/10km"].exists)
        app.buttons["Expand workout dashboard"].tap()
        XCTAssertTrue(app.staticTexts["61"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "152")).firstMatch.exists)
        app.buttons["Collapse workout dashboard"].tap()
        XCTAssertTrue(app.buttons["Show Camera"].exists)
        XCTAssertTrue(app.buttons["Recenter Map"].exists)

        app.buttons["Pause activity"].tap()
        XCTAssertTrue(app.buttons["Pause activity"].exists, "A brief touch must not pause the run")
        XCTAssertFalse(app.buttons["Resume activity"].exists)
        app.buttons["Pause activity"].press(forDuration: 1.1)
        XCTAssertTrue(app.buttons["Resume activity"].waitForExistence(timeout: 5))
        app.buttons["Resume activity"].tap()
        XCTAssertTrue(app.buttons["Pause activity"].waitForExistence(timeout: 5))
        app.buttons["Pause activity"].press(forDuration: 1.1)
        XCTAssertTrue(app.buttons["Finish activity"].waitForExistence(timeout: 5))
        app.buttons["Finish activity"].tap()

        XCTAssertTrue(app.buttons["Save activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["7.82"].exists)
        // The seeded recorder keeps ticking while real pause/resume controls run.
        let pace = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "5:5[2-9] /km")).firstMatch
        XCTAssertTrue(pace.exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["152"].exists, app.debugDescription)
        discardReview(app)
        XCTAssertTrue(app.buttons["tab.start"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testPostRunSummaryCanManageCapturedPhotos() throws {
        let app = launchApp(extraArguments: ["-OutboundDebugPostRunSummary", "-measurement_unit_system_v1", "metric"])
        let first = app.descendants(matching: .any)["FinishPhotoThumbnail-0"].firstMatch
        reveal(first, in: app)
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "FinishPhotoThumbnail-")).count, 3)
        first.tap()
        let closePreview = app.buttons["CloseFinishPhotoPreviewButton"]
        XCTAssertTrue(closePreview.waitForExistence(timeout: 5))
        closePreview.tap()
        first.press(forDuration: 0.6)
        let delete = app.buttons["Delete selected photos"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(first.isSelected)
        let secondCaption = app.descendants(matching: .any)["FinishPhotoThumbnail-1"].firstMatch.label
        let last = app.descendants(matching: .any)["FinishPhotoThumbnail-2"].firstMatch
        first.press(forDuration: 0.6, thenDragTo: last)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", secondCaption), object: first)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        XCTAssertTrue(last.isSelected)
        delete.tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "FinishPhotoThumbnail-")).count, 2)
        XCTAssertFalse(delete.exists)
        reveal(app.buttons["Save activity"], in: app)
        app.buttons["Save activity"].tap()
        XCTAssertTrue(app.staticTexts["Saved 2"].waitForExistence(timeout: 5), "Only the remaining photos must reach onSave")
    }

    @MainActor
    func testDemoCaptureHarvestHalfMarathon() throws {
        let app = launchDemoCaptureApp()

        let todayTab = app.buttons["tab.start"]
        XCTAssertTrue(todayTab.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Redmond Harvest Half Marathon"].waitForExistence(timeout: 8))
        pacedPause(6)

        todayTab.tap()

        let pauseButton = app.buttons["Pause activity"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["Run Simulation"].waitForExistence(timeout: 5))
        pacedPause(3)

        let advanceButton = app.buttons["+5m"]
        XCTAssertTrue(advanceButton.waitForExistence(timeout: 5))
        advanceButton.tap()
        pacedPause(2)
        advanceButton.tap()
        pacedPause(4)

        pauseButton.press(forDuration: 1.1)
        let resumeButton = app.buttons["Resume activity"]
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 5))
        pacedPause(2)
        resumeButton.tap()
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 5))
        pacedPause(3)

        pauseButton.press(forDuration: 1.1)
        let finishButton = app.buttons["Finish activity"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5))
        pacedPause(1)
        finishButton.tap()

        XCTAssertTrue(app.buttons["Save activity"].waitForExistence(timeout: 8))
        pacedPause(6)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            _ = launchApp()
        }
    }

    @MainActor
    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        launchFixtureApp(extraArguments: extraArguments)
    }

    @MainActor
    private func launchDemoCaptureApp() -> XCUIApplication {
        launchFixtureApp(extraArguments: [
            "-OutboundDemoCapture", "-OutboundSimulatedHarvestRun",
            "-measurement_unit_system_v1", "metric", "-workout_reminders_enabled_v1", "NO",
        ])
    }

    private func pacedPause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

}
