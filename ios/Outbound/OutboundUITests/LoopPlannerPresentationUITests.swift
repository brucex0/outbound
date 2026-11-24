import CoreFoundation
import XCTest
import UIKit

final class LoopPlannerPresentationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testDelayedHTTPGeometryAndSheetsSurviveParentRefreshes() throws {
        let fixture = try LoopPlannerFixture()
        defer { fixture.stop() }
        let tips = ["theme_discovery", "activity_overflow", "music_discovery", "cheer_me_on", "voice_guide", "shoes"]
        let app = launchFixtureApp(extraArguments: ["-OutboundAPIBaseURL", try fixture.start(),
            "-OutboundUITestTodayPrescriptionRefresh", "-OutboundUITestRoutePlannerRefresh",
            "-measurement_unit_system_v1", "metric", "-theme_discovery_tip_dismissed_v1", "YES"]
            + tips.flatMap { ["-tooltip.\($0).dismissed.v1", "YES"] })
        XCTAssertTrue(app.buttons["today.overflow"].waitForExistence(timeout: 20), app.debugDescription)
        refresh()
        // An explicit manual workout must remain selected while the underlying
        // Planned prescription changes independently during route discovery.
        app.buttons["activity.workout.run"].tap()
        app.buttons["activity.mode.time"].tap()
        let goal = app.buttons["activity.goal.edit"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5), app.debugDescription)
        goal.tap()
        let custom = app.textFields["activity.goal.custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5), app.debugDescription)
        custom.tap()
        if let value = custom.value as? String, value != "0" {
            custom.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        custom.typeText("47")
        app.buttons["activity.goal.done"].tap()
        XCTAssertTrue(custom.waitForNonExistence(timeout: 5))
        let originalGoal = goal.label
        XCTAssertTrue(originalGoal.contains("47"), originalGoal)
        let originalWorkout = app.buttons["activity.workout.run"].value as? String
        app.buttons["today.overflow"].tap()
        for _ in 0..<3 {
            refresh()
            XCTAssertTrue(app.buttons["Find a route"].waitForExistence(timeout: 3), app.debugDescription)
        }
        capture(app, "Native menu retained through parent and theme refresh")
        app.buttons["Find a route"].tap()
        XCTAssertTrue(app.buttons["Find a loop"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Find a loop"].tap()
        XCTAssertTrue(app.buttons["3 km"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["3 km"].tap()
        for _ in 0..<3 { refresh(); XCTAssertTrue(app.buttons["3 km"].isHittable, app.debugDescription) }
        capture(app, "Input sheet retained through asynchronous store and theme refresh")
        app.navigationBars["Find a loop"].buttons["Close"].tap()
        let generate = app.buttons["Find loops"].firstMatch
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: generate)
        waitForExpectations(timeout: 20)
        generate.tap()
        for _ in 0..<3 { refresh() }
        let candidate = app.buttons["loop.candidate.0"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").count, 1)
        let map = app.descendants(matching: .any)["loop.map"].firstMatch
        XCTAssertTrue(map.exists, app.debugDescription)
        let paintedRoutes = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.comparisonHasPaintedRoutes(app)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [paintedRoutes], timeout: 15), .completed,
                       "Both route strokes must paint before opening details")
        capture(app, "Settled comparison with painted blue and orange routes")
        candidate.tap()
        XCTAssertTrue(app.navigationBars["Route details"].waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<3 { refresh(); XCTAssertTrue(app.buttons["Use route"].isHittable, app.debugDescription) }
        capture(app, "Details retained through store publications")
        app.navigationBars["Route details"].buttons["Close"].tap()
        app.buttons["Start, distance & via"].tap()
        XCTAssertTrue(app.buttons["3 km"].waitForExistence(timeout: 5))
        app.navigationBars["Find a loop"].buttons["Close"].tap()
        candidate.tap()
        app.buttons["Use route"].tap()
        XCTAssertTrue(app.buttons["today.overflow"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.buttons["today.overflow"].value as? String, "Route selected")
        XCTAssertEqual(goal.label, originalGoal, "Route selection must retain the explicit 47-minute workout")
        XCTAssertTrue(app.buttons["activity.workout.run"].isSelected)
        XCTAssertTrue(app.buttons["activity.mode.time"].isSelected)
        XCTAssertEqual(app.buttons["activity.workout.run"].value as? String, originalWorkout)
        capture(app, "Selected route returns to retained Today workout")
        app.buttons["today.overflow"].tap()
        app.buttons["Change route"].tap()
        app.buttons["Find a loop"].tap()
        XCTAssertTrue(app.buttons["3 km"].waitForExistence(timeout: 5))
        app.navigationBars["Find a loop"].buttons["Close"].tap()
        app.navigationBars["Find a loop"].buttons["Back"].tap()
        XCTAssertTrue(app.navigationBars["Select Route"].waitForExistence(timeout: 5))
        app.navigationBars["Select Route"].buttons["Close"].tap()
        XCTAssertEqual(app.buttons["today.overflow"].value as? String, "Route selected")
        XCTAssertEqual(goal.label, originalGoal, "Backing out must retain the selected route and manual goal")
    }

    /// Inspect painted route strokes, excluding the center strip containing
    /// numbered pins. Candidate cards/annotations alone cannot satisfy this.
    @MainActor private func comparisonHasPaintedRoutes(_ app: XCUIApplication) -> Bool {
        guard let image = app.screenshot().image.cgImage else { return false }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var blueRows = 0, orangeRows = 0
        for y in Int(Double(height) * 0.23)..<Int(Double(height) * 0.72) {
            var blue = 0, orange = 0
            for x in Int(Double(width) * 0.20)..<Int(Double(width) * 0.80) {
                if x > Int(Double(width) * 0.43), x < Int(Double(width) * 0.57) { continue }
                let offset = (y * width + x) * 4
                let red = bytes[offset], green = bytes[offset + 1], blueChannel = bytes[offset + 2]
                if red < 80, green > 65, green < 180, blueChannel > 200 { blue += 1 }
                if red > 230, green > 95, green < 190, blueChannel < 70 { orange += 1 }
            }
            if blue >= 4 { blueRows += 1 }
            if orange >= 4 { orangeRows += 1 }
        }
        return blueRows > 60 && orangeRows > 60
    }

    private func refresh() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: "com.plainstride.outbound.debug.today-prescription-refresh" as CFString), nil, nil, true)
        // Wait for asynchronous network/theme publications, never a production workaround.
        Thread.sleep(forTimeInterval: 0.4)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
