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

        XCTAssertTrue(app.staticTexts["Outbound"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Record"].exists)
        XCTAssertTrue(app.tabBars.buttons["Me"].exists)
        XCTAssertFalse(app.textFields["Phone number"].exists)
    }

    @MainActor
    func testRecordStartOpensCameraOverlayAndCanFinish() throws {
        addPermissionMonitor()
        let app = launchApp()

        app.tabBars.buttons["Record"].tap()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
        app.buttons["Start"].tap()
        dismissPermissionAlerts(app)

        XCTAssertTrue(app.otherElements["CameraDataOverlay"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Time"].exists)
        XCTAssertTrue(app.staticTexts["Distance"].exists)
        XCTAssertTrue(app.staticTexts["Pace"].exists)
        XCTAssertTrue(app.staticTexts["Heart Rate"].exists)
        XCTAssertTrue(app.buttons["Capture Photo"].exists)
        XCTAssertTrue(app.buttons["Finish"].exists)

        app.buttons["Finish"].tap()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
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
