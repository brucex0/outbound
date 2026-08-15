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

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Social"].exists)
        XCTAssertTrue(app.tabBars.buttons["Me"].exists)
        XCTAssertTrue(app.buttons["Quick start"].exists)
        XCTAssertFalse(app.textFields["Phone number"].exists)
    }

    @MainActor
    func testPrimaryNavigationAndSettings() throws {
        let app = launchApp()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Social"].tap()
        XCTAssertTrue(app.navigationBars["Social"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saturday waterfront 5K"].exists)
        XCTAssertTrue(app.staticTexts["Golden Gate Run Club"].exists)
        XCTAssertTrue(app.staticTexts["Presidio Morning Run"].exists)

        app.tabBars.buttons["Me"].tap()
        XCTAssertTrue(app.navigationBars["Me"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Golden Gate Easy Run"].waitForExistence(timeout: 5))
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sign out"].exists)
    }

    @MainActor
    func testSeededSocialFeedRunAndComments() throws {
        let app = launchApp()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Social"].tap()
        XCTAssertTrue(app.navigationBars["Social"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saturday waterfront 5K"].exists)
        XCTAssertTrue(app.staticTexts["Presidio Morning Run"].exists)

        let cheerButton = app.buttons["Cheer · 2"]
        XCTAssertTrue(cheerButton.waitForExistence(timeout: 5))
        cheerButton.tap()
        XCTAssertTrue(app.buttons["Cheered · 3"].waitForExistence(timeout: 5))

        app.buttons["Comment · 1"].tap()
        XCTAssertTrue(app.navigationBars["Comments"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["See you next time!"].exists)
        app.buttons["Done"].tap()

        app.buttons["View run"].tap()
        XCTAssertTrue(app.navigationBars["Saturday waterfront 5K"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Going"].waitForExistence(timeout: 5))
        app.buttons["I'm going"].tap()
        XCTAssertTrue(app.buttons["Leave run"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSeededSocialConnectionsGroupsAndNotifications() throws {
        let app = launchApp()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Social"].tap()
        XCTAssertTrue(app.navigationBars["Social"].waitForExistence(timeout: 5))

        app.buttons["Social community"].tap()
        app.buttons["Connections"].tap()
        XCTAssertTrue(app.navigationBars["Connections"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Maya Chen"].exists)
        XCTAssertTrue(app.staticTexts["Leo Martinez"].exists)
        XCTAssertTrue(app.staticTexts["Priya Shah"].exists)
        XCTAssertTrue(app.staticTexts["Blocked Runner"].exists)
        app.buttons["Accept connection request"].tap()
        XCTAssertTrue(app.buttons["Accept connection request"].waitForNonExistence(timeout: 5))

        app.navigationBars["Connections"].buttons.firstMatch.tap()
        app.buttons["Social community"].tap()
        app.buttons["Groups"].tap()
        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Golden Gate Run Club"].exists)
        XCTAssertTrue(app.staticTexts["Sunset Striders"].exists)
        app.buttons["Join"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "Leave").count, 2)

        app.navigationBars["Groups"].buttons.firstMatch.tap()
        app.buttons["Social notifications"].tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Maya Chen cheered your run."].exists)
        XCTAssertTrue(app.staticTexts["Maya Chen invited you to Saturday waterfront 5K."].exists)
        app.buttons["Accept run invitation"].tap()
        XCTAssertTrue(app.buttons["Accept run invitation"].waitForNonExistence(timeout: 5))

    }

    @MainActor
    func testSeededSocialDeclinesConnectionRequest() throws {
        let app = launchApp()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Social"].tap()
        XCTAssertTrue(app.navigationBars["Social"].waitForExistence(timeout: 5))
        app.buttons["Social community"].tap()
        app.buttons["Connections"].tap()
        XCTAssertTrue(app.navigationBars["Connections"].waitForExistence(timeout: 5))

        let declineButton = app.buttons["Decline connection request"]
        XCTAssertTrue(declineButton.waitForExistence(timeout: 5))
        declineButton.tap()
        XCTAssertTrue(declineButton.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Leo Martinez"].exists)
    }

    @MainActor
    func testTodayFreestyleStartOpensRecordingFlowAndCanFinish() throws {
        addPermissionMonitor()
        let app = launchApp()

        app.buttons["Quick start"].tap()
        XCTAssertTrue(app.staticTexts["Freestyle run"].waitForExistence(timeout: 5))
        if app.buttons["Connect Apple Music"].exists {
            app.buttons["Connect Apple Music"].tap()
            XCTAssertTrue(app.staticTexts["Mock upbeat run mix"].waitForExistence(timeout: 5))
            app.buttons["Select Mock upbeat run mix"].tap()
        }
        XCTAssertTrue(app.buttons["Start now"].exists)
        app.buttons["Start now"].tap()
        dismissPermissionAlerts(app)

        XCTAssertTrue(app.buttons["Pause activity"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["Pace"].exists)

        app.buttons["Pause activity"].tap()
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 5))
        app.buttons["Finish"].tap()
        XCTAssertTrue(app.buttons["Save activity"].waitForExistence(timeout: 5))
        app.buttons["Discard activity"].tap()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Quick start"].exists)
    }

    @MainActor
    func testPostRunSummaryCanManageCapturedPhotos() throws {
        let app = launchApp(extraArguments: ["-OutboundDebugPostRunSummary"])

        XCTAssertTrue(app.staticTexts["3 selected"].waitForExistence(timeout: 5))
        app.buttons["Manage"].tap()
        XCTAssertTrue(app.navigationBars["Choose Photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["3 of 3 selected"].exists)
        app.buttons["Clear"].tap()
        XCTAssertTrue(app.staticTexts["0 of 3 selected"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["None selected"].waitForExistence(timeout: 3))
        app.buttons["Discard"].tap()
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
        let app = XCUIApplication()
        app.launchArguments += [
            "-OutboundUseMockMusic",
            "-OutboundDisableFirebase",
            "-OutboundSkipOnboarding",
            "-OutboundUITestSeedData",
            "-new_user_onboarding_completed_v2.UI test session",
            "YES",
        ]
        app.launchArguments += extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func addPermissionMonitor() {
        addUIInterruptionMonitor(withDescription: "System permissions") { alert in
            for button in ["Allow While Using App", "Allow Once", "OK", "Allow"] {
                if alert.buttons[button].exists {
                    alert.buttons[button].tap()
                    return true
                }
            }
            return false
        }
    }

    @MainActor
    private func dismissPermissionAlerts(_ app: XCUIApplication) {
        for _ in 0..<3 {
            if app.otherElements["CameraDataOverlay"].exists { break }
            app.tap()
        }
    }
}
