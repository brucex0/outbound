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
        XCTAssertTrue(app.buttons["Start freestyle"].exists)
        XCTAssertFalse(app.textFields["Phone number"].exists)
    }

    @MainActor
    func testTodayFreestyleStartOpensRecordingFlowAndCanFinish() throws {
        addPermissionMonitor()
        let app = launchApp()

        app.buttons["Start freestyle"].tap()
        XCTAssertTrue(app.staticTexts["Freestyle run"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start now"].exists)
        app.buttons["Start now"].tap()
        dismissPermissionAlerts(app)

        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Time"].exists)
        XCTAssertTrue(app.staticTexts["Distance (km)"].exists)
        XCTAssertTrue(app.staticTexts["Pace"].exists)
        XCTAssertTrue(app.buttons["Capture Photo"].exists)
        XCTAssertTrue(app.buttons["Show Map"].exists)

        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Finish"].exists)
        app.buttons["Finish"].tap()
        XCTAssertTrue(app.buttons["Save Activity"].waitForExistence(timeout: 5))
        app.buttons["Discard"].tap()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start freestyle"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            _ = launchApp()
        }
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
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
