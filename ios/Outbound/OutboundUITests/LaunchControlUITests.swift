import XCTest

/// Real hit-testing and visible state assertions for every Today launch-dock
/// control and each goal editor action. No coordinator methods are called here.
final class LaunchControlUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testPreferencePillsToggleRepeatedlyAndSurviveNavigationAndRelaunch() {
        let app = launchControls()
        tapSport("run", app)
        var saved: [String: String] = [:]
        for label in ["Voice Guide", "Watch app", "Auto Pause"] {
            let button = option(label, app)
            let initial = button.value as? String
            XCTAssertTrue(["On", "Off"].contains(initial ?? ""), label)
            let changed = initial == "On" ? "Off" : "On"
            for expected in [changed, initial!, changed] {
                button.tap()
                expectValue(button, expected)
            }
            saved[label] = changed
        }
        app.buttons["tab.me"].tap()
        app.buttons["tab.today"].tap()
        for (label, value) in saved { expectValue(option(label, app), value) }
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab.start"].waitForExistence(timeout: 10))
        tapSport("run", app)
        for (label, value) in saved { expectValue(option(label, app), value) }
        capture(app, "Persisted launch options")
    }

    @MainActor
    func testEverySportAndPerSportAutoPauseAndOtherTogglePills() {
        let app = launchControls()
        for sport in ["run", "walk", "hike", "bike"] {
            tapSport(sport, app)
            let button = option("Auto Pause", app)
            let original = button.value as! String
            button.tap()
            expectValue(button, original == "On" ? "Off" : "On")
            button.tap()
            expectValue(button, original)
            let dog = option("With dog", app)
            let selected = dog.isSelected
            dog.tap()
            expectSelected(dog, !selected)
            dog.tap()
            expectSelected(dog, selected)
        }
        let outdoor = option("Outdoor", app)
        outdoor.tap()
        let indoor = option("Indoor", app)
        XCTAssertTrue(indoor.isHittable)
        indoor.tap()
        XCTAssertTrue(option("Outdoor", app).isHittable)
        tapSport("planned", app)
        XCTAssertTrue(app.navigationBars["Plan setup"].waitForExistence(timeout: 5))
        app.navigationBars["Plan setup"].buttons["Finish later"].tap()
        tapSport("run", app)
        tapMode("freestyle", app)
        expectSelected(app.buttons["activity.mode.freestyle"], true)
        XCTAssertFalse(app.buttons["activity.goal.edit"].exists)
    }

    @MainActor
    func testEveryGoalEditorPresetCustomCancelDoneAndPauseAtGoal() {
        let app = launchControls()
        tapSport("run", app)
        for mode in ["distance", "time", "calories"] {
            tapMode(mode, app)
            expectSelected(app.buttons["activity.mode.\(mode)"], true)
            let card = app.buttons["activity.goal.edit"]
            XCTAssertTrue(card.waitForExistence(timeout: 5), mode)
            let originalCard = card.label
            card.tap()
            let pause = app.buttons["activity.goal.pauseAtGoal"]
            XCTAssertTrue(pause.waitForExistence(timeout: 5))
            // UIKit scales a presented sheet during its transition; verify a
            // roomy screen-space target while the SwiftUI row specifies 44pt.
            XCTAssertGreaterThan(pause.frame.height, 40)
            let original = pause.value as! String
            pause.tap()
            expectValue(pause, original == "On" ? "Off" : "On")
            pause.tap()
            expectValue(pause, original)
            let presets = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "activity.goal.preset."))
            XCTAssertGreaterThan(presets.count, 0)
            for index in 0..<presets.count {
                let preset = presets.element(boundBy: index)
                revealHorizontally(preset, in: app.scrollViews.containing(.button, identifier: preset.identifier).firstMatch, app: app)
                preset.tap()
                expectSelected(preset, true)
            }
            app.buttons["activity.goal.cancel"].tap()
            XCTAssertTrue(pause.waitForNonExistence(timeout: 5))
            XCTAssertEqual(card.label, originalCard, "Cancel must preserve the target")
            card.tap()
            let custom = app.textFields["activity.goal.custom"]
            XCTAssertTrue(custom.waitForExistence(timeout: 5))
            custom.tap()
            if let value = custom.value as? String, value != "0" {
                custom.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
            }
            let value = mode == "distance" ? "7" : mode == "time" ? "37" : "370"
            custom.typeText(value)
            pause.tap()
            let savedPause = pause.value as! String
            app.buttons["activity.goal.done"].tap()
            XCTAssertTrue(pause.waitForNonExistence(timeout: 5))
            // Calorie targets are normalized to the existing 25-kcal increments.
            let appliedValue = mode == "calories" ? "375" : value
            XCTAssertTrue(card.label.contains(appliedValue), card.label)
            card.tap()
            expectValue(pause, savedPause)
            XCTAssertEqual(custom.value as? String, appliedValue)
            app.buttons["activity.goal.cancel"].tap()
        }
        capture(app, "Goal editor values applied")
    }

    @MainActor
    func testUtilityPillsOpenAndDismissTheirDestinations() {
        let app = launchControls()
        option("Music", app).tap()
        XCTAssertTrue(app.navigationBars["Music"].waitForExistence(timeout: 5))
        app.buttons.containing(.staticText, identifier: "No music").firstMatch.tap()
        app.navigationBars["Music"].buttons["Done"].tap()
        option("Cheer me on", app).tap()
        XCTAssertTrue(app.navigationBars["Cheer me on"].waitForExistence(timeout: 5))
        app.navigationBars["Cheer me on"].buttons["Cancel"].tap()
        option("Cheer me on", app).tap()
        app.navigationBars["Cheer me on"].buttons["Done"].tap()
        option("Shoes", app).tap()
        // Seeded gear opens a menu; an empty gear store opens Add Shoe directly.
        if app.buttons["Add shoe"].exists { app.buttons["Add shoe"].tap() }
        if app.buttons["New Shoe"].exists { app.buttons["New Shoe"].tap() }
        XCTAssertTrue(app.navigationBars["Add Shoe"].waitForExistence(timeout: 5))
        app.navigationBars["Add Shoe"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["today.overflow"].isHittable)
    }

    @MainActor
    func testCuratedRaceAndOverflowDestinations() {
        let app = launchControls()
        tapSport("run", app)
        tapMode("curated", app)
        XCTAssertTrue(app.navigationBars["Workouts"].waitForExistence(timeout: 5))
        app.navigationBars["Workouts"].buttons["Close"].tap()
        tapMode("race", app)
        XCTAssertTrue(app.navigationBars["Plan this race"].waitForExistence(timeout: 5))
        app.navigationBars["Plan this race"].buttons["Cancel"].tap()
        tapMode("race", app)
        app.navigationBars["Plan this race"].buttons["Use race plan"].tap()
        XCTAssertTrue(app.buttons["activity.goal.edit"].waitForExistence(timeout: 5))
        app.buttons["activity.goal.edit"].tap()
        XCTAssertTrue(app.navigationBars["Plan this race"].waitForExistence(timeout: 5))
        app.navigationBars["Plan this race"].buttons["Cancel"].tap()
        app.buttons["today.overflow"].tap()
        app.buttons["Find a route"].tap()
        XCTAssertTrue(app.navigationBars["Select Route"].waitForExistence(timeout: 5))
        app.navigationBars["Select Route"].buttons["Close"].tap()
        app.buttons["today.overflow"].tap()
        app.buttons["Group run"].tap()
        XCTAssertTrue(app.navigationBars["Group run"].waitForExistence(timeout: 5))
        app.navigationBars["Group run"].buttons["Done"].tap()
        app.buttons["today.overflow"].tap()
        app.buttons["Take photo"].tap()
        let cameraClose = app.buttons["activity.photo.close"]
        XCTAssertTrue(cameraClose.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Take photo"].isHittable)
        cameraClose.tap()
        XCTAssertTrue(app.buttons["today.overflow"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchControls() -> XCUIApplication {
        let tips = ["theme_discovery", "activity_overflow", "music_discovery", "cheer_me_on", "voice_guide", "shoes"]
        let app = launchFixtureApp(extraArguments: tips.flatMap { ["-tooltip.\($0).dismissed.v1", "YES"] }
                                  + ["-OutboundUITestLaunchControls", "-theme_discovery_tip_dismissed_v1", "YES",
                                     "-measurement_unit_system_v1", "metric"],
                                  overrideLaunchPreferences: false)
        XCTAssertTrue(app.buttons["tab.start"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func tapSport(_ sport: String, _ app: XCUIApplication) {
        let button = app.buttons["activity.workout.\(sport)"]
        revealHorizontally(button, in: app.scrollViews["activity.launch.workouts"], app: app)
        button.tap()
        if sport != "planned" { expectSelected(button, true) }
        dismissFixturePermissionAlerts(app)
    }

    @MainActor
    private func tapMode(_ mode: String, _ app: XCUIApplication) {
        let button = app.buttons["activity.mode.\(mode)"]
        revealHorizontally(button, in: app.scrollViews["activity.launch.modes"], app: app)
        button.tap()
    }

    @MainActor
    private func option(_ label: String, _ app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[label].firstMatch
        revealHorizontally(button, in: app.scrollViews["activity.launch.options"], app: app)
        return button
    }

    @MainActor
    private func revealHorizontally(_ button: XCUIElement, in scroller: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 {
            if button.exists {
                let frame = button.frame
                let viewport = scroller.frame
                // Accessibility includes the capsule's half-point border outside
                // its layout bounds, so compare the horizontal visible area.
                if frame.minX >= viewport.minX - 1 && frame.maxX <= viewport.maxX + 1
                    && app.frame.insetBy(dx: -1, dy: -1).contains(frame) && button.isHittable { return }
                let left = frame.midX > viewport.midX
                let start = scroller.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.8 : 0.2, dy: 0.5))
                let end = scroller.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.2 : 0.8, dy: 0.5))
                start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
            } else {
                scroller.swipeLeft(velocity: .slow)
            }
        }
        XCTFail("Unreachable control: \(button.identifier)\n\(app.debugDescription)")
    }

    @MainActor
    private func expectValue(_ button: XCUIElement, _ value: String) {
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, "\(button.label) expected \(value), got \(String(describing: button.value))")
    }

    @MainActor
    private func expectSelected(_ button: XCUIElement, _ selected: Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == %@", NSNumber(value: selected)), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, button.label)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
