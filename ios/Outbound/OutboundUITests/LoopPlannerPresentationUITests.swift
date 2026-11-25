import CoreFoundation
import XCTest
import UIKit

final class LoopPlannerPresentationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testPersistentCacheReopenRelaunchAndExplicitBypass() throws {
        let fixture = try LoopPlannerFixture()
        defer { fixture.stop() }
        let tips = ["theme_discovery", "activity_overflow", "music_discovery", "cheer_me_on", "voice_guide", "shoes"]
        let app = launchFixtureApp(extraArguments: ["-OutboundAPIBaseURL", try fixture.start(),
            "-OutboundUITestPlannerCacheAccount", "-measurement_unit_system_v1", "metric",
            "-theme_discovery_tip_dismissed_v1", "YES"]
            + tips.flatMap { ["-tooltip.\($0).dismissed.v1", "YES"] })
        openFindRoute(app)
        waitForReady(app.buttons["loop.candidate.0"], app: app)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").count, 1)
        capture(app, "Fresh generated routes before closing planner")
        app.navigationBars.buttons["Back"].tap()
        openFindRoute(app)
        waitForReady(app.buttons["loop.candidate.0"], app: app)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").count, 1, "Reopening must reuse the device cache without a provider call")
        app.terminate(); app.launch(); dismissFixturePermissionAlerts(app)
        openFindRoute(app)
        waitForReady(app.buttons["loop.candidate.0"], app: app)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").count, 1, "The cache must survive process death")
        let painted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.comparisonHasPaintedRoutes(app) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [painted], timeout: 15), .completed)
        capture(app, "Persistent cached canonical routes painted after relaunch")
        fixture.failGeneration()
        app.buttons["New routes"].tap()
        let attempted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            fixture.bodies("POST /routes/generate").count == 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [attempted], timeout: 10), .completed)
        waitForReady(app.buttons["loop.candidate.0"], app: app)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").count, 2, "New routes must attempt generation")
        XCTAssertTrue(app.staticTexts["Couldn’t load new routes. Showing saved suggestions."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Loop generation is unavailable. Try again later, or choose an existing route."].exists,
                       "Usable cached routes must not be paired with the unrecovered-failure message")
        XCTAssertTrue(app.buttons["loop.candidate.0"].isEnabled)
        capture(app, "Failed explicit refresh keeps cached routes with temporary fallback feedback")
    }

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
        XCTAssertTrue(app.buttons["loop.candidate.0"].waitForExistence(timeout: 20))
        app.buttons["loop.distance"].tap()
        XCTAssertTrue(app.buttons["3 km"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["3 km"].tap()
        for _ in 0..<3 { refresh(); XCTAssertTrue(app.buttons["3 km"].isHittable, app.debugDescription) }
        capture(app, "Input sheet retained through asynchronous store and theme refresh")
        app.buttons["Done"].tap()
        for _ in 0..<3 { refresh() }
        let candidate = app.buttons["loop.candidate.0"]
        waitForReady(candidate, app: app)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").count, 2)
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
        app.buttons["loop.distance"].tap()
        XCTAssertTrue(app.buttons["3 km"].waitForExistence(timeout: 5))
        app.navigationBars["Distance"].buttons["Close"].tap()
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
        app.buttons["loop.saved_routes"].tap()
        XCTAssertTrue(app.navigationBars["Select Route"].waitForExistence(timeout: 5))
        let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Loop 1")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), app.debugDescription)
        saved.tap() // Deselect the current snapshot.
        saved.tap() // Select canonical cached geometry with a fresh attachment policy.
        let useSaved = app.buttons["Use This Route"]
        XCTAssertTrue(useSaved.waitForExistence(timeout: 5))
        XCTAssertTrue(useSaved.isEnabled)
        useSaved.tap()
        XCTAssertTrue(app.buttons["today.overflow"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(goal.label, originalGoal, "Saved-route attachment must retain the explicit 47-minute Run")
        XCTAssertTrue(app.buttons["activity.mode.time"].isSelected)
        app.buttons["today.overflow"].tap()
        app.buttons["Change route"].tap()
        app.buttons["loop.distance"].tap()
        XCTAssertTrue(app.buttons["3 km"].waitForExistence(timeout: 5))
        app.navigationBars["Distance"].buttons["Close"].tap()
        app.navigationBars["Find a loop"].buttons["Back"].tap()
        XCTAssertTrue(app.buttons["today.overflow"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["today.overflow"].value as? String, "Route selected")
        XCTAssertEqual(goal.label, originalGoal, "Backing out must retain the selected route and manual goal")
    }

    @MainActor
    func testUntouchedInitialDarkInputsSurviveLateLocationAndParks() throws {
        try initialInputs(appearance: "dark")
    }

    @MainActor
    func testUntouchedInitialLightInputsSurviveLateLocationAndParks() throws {
        try initialInputs(appearance: "light")
    }

    @MainActor
    func testNaturalInitialDarkInputsSurviveLocationAndParks() throws {
        try initialInputs(appearance: "dark", deferredLocation: false)
    }

    @MainActor private func initialInputs(appearance: String, deferredLocation: Bool = true) throws {
        let fixture = try LoopPlannerFixture()
        defer { fixture.stop() }
        let tips = ["theme_discovery", "activity_overflow", "music_discovery", "cheer_me_on", "voice_guide", "shoes"]
        let app = launchFixtureApp(extraArguments: ["-OutboundAPIBaseURL", try fixture.start(),
            "-OutboundUITestTodayPrescriptionRefresh", "-OutboundDebugPlannerFrameProbe", "-appearance_mode_v1", appearance,
            "-outbound_theme_v1", "victoryGold", "-measurement_unit_system_v1", "metric",
            "-tooltip.activity_overflow.dismissed.v1", "YES"]
            + tips.flatMap { ["-tooltip.\($0).dismissed.v1", "YES"] }
            + (deferredLocation ? ["-OutboundUITestDeferredPlannerLocation"] : []))
        XCTAssertTrue(app.buttons["today.overflow"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["today.overflow"].frame.width, 44, accuracy: 1)
        XCTAssertEqual(app.buttons["today.overflow"].frame.height, 44, accuracy: 1)
        app.buttons["today.overflow"].tap()
        for _ in 0..<3 {
            refresh()
            XCTAssertTrue(app.buttons["Find a route"].exists, "Native menu must remain open during store refreshes")
        }
        app.buttons["Find a route"].tap()
        app.buttons["loop.distance"].tap()
        let close = app.navigationBars["Distance"].buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 0.7) // Let the one native opening transition finish.
        let baseline = close.frame
        refresh() // Real CoreLocation followed by real MKLocalSearch, after inputs are open.
        let end = Date().addingTimeInterval(12)
        var sample = 0
        while Date() < end {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Initial \(appearance) frame \(sample)"; screenshot.lifetime = .keepAlways; add(screenshot)
            XCTAssertTrue(close.exists, "Explicit distance editor disappeared at sample \(sample)")
            XCTAssertLessThan(abs(close.frame.minY - baseline.minY), 8, "Explicit distance editor moved at sample \(sample)")
            XCTAssertTrue(app.buttons["3 km"].isHittable)
            sample += 1
        }
        let evidence = app.descendants(matching: .any)["loop.stability"].firstMatch.value as? String ?? ""
        XCTAssertNotNil(evidence.range(of: "parks=[1-9]", options: .regularExpression), "Real MapKit park response must arrive: \(evidence)")
        for counter in ["sheetReplacements=0", "sheetMissing=0", "sheetMoves=0", "inputStateLost=0", "mapReplacements=0", "mapMissing=0"] {
            XCTAssertTrue(evidence.contains(counter), evidence)
        }
        XCTAssertEqual(fixture.bodies("POST /routes/generate").count, 1)
    }

    @MainActor
    func testAutomaticDefaultAndConfirmedStartsPreserveSelectedDistance() throws {
        let fixture = try LoopPlannerFixture()
        defer { fixture.stop() }
        let tips = ["theme_discovery", "activity_overflow", "music_discovery", "cheer_me_on", "voice_guide", "shoes"]
        let app = launchFixtureApp(extraArguments: ["-OutboundAPIBaseURL", try fixture.start(),
            "-measurement_unit_system_v1", "metric"] + tips.flatMap { ["-tooltip.\($0).dismissed.v1", "YES"] })
        openFindRoute(app)
        let candidate = app.buttons["loop.candidate.0"]
        waitForReady(candidate, app: app)
        XCTAssertFalse(app.navigationBars["Distance"].exists, "Initial results must remain uncovered")
        XCTAssertFalse(app.navigationBars["Select Route"].exists, "Today opens the map directly")
        XCTAssertEqual(fixture.bodies("POST /routes/generate").count, 1)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").last?["targetDistanceM"] as? Double, 5000)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").last?["preference"] as? String, "balanced")
        capture(app, "Automatic default route comparison")
        app.buttons["loop.distance"].tap()
        app.buttons["10 km"].tap()
        XCTAssertEqual(fixture.bodies("POST /routes/generate").count, 1, "Distance remains a draft until Done")
        app.buttons["Done"].tap()
        XCTAssertFalse(candidate.isEnabled, "Old geometry cannot be selected while replacement is loading")
        waitForReady(candidate, app: app)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").count, 2)
        app.buttons["loop.start"].tap()
        app.buttons["My location"].tap()
        waitForReady(candidate, app: app)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").count, 2, "Unchanged My location reuses the valid current-input routes")
        XCTAssertEqual(fixture.bodies("POST /routes/generate").last?["targetDistanceM"] as? Double, 10000)
        app.buttons["loop.start"].tap()
        let search = app.textFields["Search places"]
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        search.typeText("10201 NE 4th St Bellevue")
        waitForSettledPlaceSearchControl(app)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").count, 2, "Search typing does not generate")
        app.buttons["loop.place.search"].tap()
        let place = app.buttons["loop.place.0"]
        let feedback = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            place.exists || app.staticTexts["Searching places…"].exists || app.progressIndicators["Searching places…"].exists
                || app.staticTexts["No places found. Try another address."].exists
                || app.staticTexts["Places could not be loaded. Try again."].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [feedback], timeout: 5), .completed, "A submitted search must expose loading, results, empty or failure feedback")
        XCTAssertTrue(place.waitForExistence(timeout: 15), app.debugDescription)
        place.tap()
        XCTAssertFalse(app.buttons["Confirm pin"].exists, "Ordinary address selection has no entrance gate")
        waitForReady(candidate, app: app)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").count, 3)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").last?["targetDistanceM"] as? Double, 10000)
        let initialStart = fixture.bodies("POST /routes/generate").first?["start"] as? NSDictionary
        let addressStart = fixture.bodies("POST /routes/generate").last?["start"] as? NSDictionary
        XCTAssertNotEqual(initialStart, addressStart, "The selected address must become the request start")
        capture(app, "Selected address generates ten kilometer loops directly")
        app.buttons["loop.saved_routes"].tap()
        XCTAssertTrue(app.navigationBars["Select Route"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Import GPX or GeoJSON"].exists)
        XCTAssertFalse(app.buttons["Find a loop"].exists, "Saved routes must not recursively open another planner")
        app.navigationBars["Select Route"].buttons["Close"].tap()
        waitForReady(candidate, app: app)
        app.buttons["loop.options"].tap()
        let climbing = app.switches["loop.less_climbing"]
        XCTAssertTrue(climbing.waitForExistence(timeout: 5))
        climbing.tap()
        XCTAssertEqual(fixture.bodies("POST /routes/generate").count, 3, "Preferences remain a draft until Done")
        app.buttons["Done"].tap()
        waitForReady(candidate, app: app)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").count, 4)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").last?["preference"] as? String, "less_climbing")
    }

    @MainActor
    func testManualDistanceGoalSeedsInitialQuery() throws {
        let fixture = try LoopPlannerFixture()
        defer { fixture.stop() }
        let tips = ["theme_discovery", "activity_overflow", "music_discovery", "cheer_me_on", "voice_guide", "shoes"]
        let app = launchFixtureApp(extraArguments: ["-OutboundAPIBaseURL", try fixture.start(),
            "-measurement_unit_system_v1", "metric"] + tips.flatMap { ["-tooltip.\($0).dismissed.v1", "YES"] })
        XCTAssertTrue(app.buttons["today.overflow"].waitForExistence(timeout: 20))
        app.buttons["activity.workout.run"].tap()
        app.buttons["activity.mode.distance"].tap()
        let goal = app.buttons["activity.goal.edit"]
        goal.tap()
        let custom = app.textFields["activity.goal.custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.tap()
        if let value = custom.value as? String, value != "0" {
            custom.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        custom.typeText("10")
        app.buttons["activity.goal.done"].tap()
        XCTAssertTrue(custom.waitForNonExistence(timeout: 5))
        let originalGoal = goal.label
        app.buttons["today.overflow"].tap()
        app.buttons["Find a route"].tap()
        waitForReady(app.buttons["loop.candidate.0"], app: app)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").count, 1)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").last?["targetDistanceM"] as? Double, 10000)
        XCTAssertEqual(fixture.bodies("POST /routes/generate").last?["activityType"] as? String, "running")
        app.navigationBars["Find a loop"].buttons["Back"].tap()
        XCTAssertTrue(app.buttons["today.overflow"].waitForExistence(timeout: 10))
        XCTAssertEqual(goal.label, originalGoal)
    }

    @MainActor private func waitForSettledPlaceSearchControl(_ app: XCUIApplication) {
        let button = app.buttons["loop.place.search"], keyboard = app.keyboards.firstMatch
        var lastButtonFrame = CGRect.null, lastKeyboardFrame = CGRect.null
        var stableSamples = 0
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard keyboard.exists, button.exists, button.isHittable else { stableSamples = 0; return false }
            let buttonFrame = button.frame, keyboardFrame = keyboard.frame
            guard buttonFrame.maxY < keyboardFrame.minY else { stableSamples = 0; return false }
            stableSamples = buttonFrame == lastButtonFrame && keyboardFrame == lastKeyboardFrame ? stableSamples + 1 : 0
            lastButtonFrame = buttonFrame; lastKeyboardFrame = keyboardFrame
            return stableSamples >= 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed,
                       "The keyboard/sheet transition must settle before computing the magnifier tap point")
    }

    @MainActor private func openFindRoute(_ app: XCUIApplication) {
        let overflow = app.buttons["today.overflow"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            overflow.exists && overflow.isHittable && overflow.frame.width >= 43 && overflow.frame.minY >= 0
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed, app.debugDescription)
        overflow.tap()
        let find = app.buttons["Find a route"]
        XCTAssertTrue(find.waitForExistence(timeout: 5), "Native overflow must open before planner entry: \(app.debugDescription)")
        XCTAssertTrue(find.isHittable)
        find.tap()
    }

    @MainActor private func waitForReady(_ candidate: XCUIElement, app: XCUIApplication) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: candidate)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 25), .completed, app.debugDescription)
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
