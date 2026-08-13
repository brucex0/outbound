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
        XCTAssertTrue(app.tabBars.buttons["Together"].exists)
        XCTAssertTrue(app.tabBars.buttons["Me"].exists)
        XCTAssertTrue(app.buttons["Quick start"].exists)
        XCTAssertFalse(app.textFields["Phone number"].exists)
    }

    @MainActor
    func testPrimaryNavigationAndSettings() throws {
        let app = launchApp()

        app.tabBars.buttons["Together"].tap()
        XCTAssertTrue(app.navigationBars["Together"].waitForExistence(timeout: 5))
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
        app.launchArguments += ["-OutboundUseMockMusic", "-OutboundDisableFirebase", "-OutboundSkipOnboarding", "-OutboundUITestSeedData"]
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
