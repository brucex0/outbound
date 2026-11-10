import XCTest

/// Explicitly selected, isolated local-API UI verification. Never calls production.
final class DirectWorkoutEditUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private let base = "http://127.0.0.1:28481"

    @MainActor
    func testDirectEditActualTodayFlow() async throws {
        try await control("reset")
        let app = launchFixtureApp(extraArguments: ["-OutboundAPIBaseURL", base + "/v1", "-measurement_unit_system_v1", "metric", "-outbound_theme_v1", "victoryGold", "-appearance_mode_v1", "light"])
        let change = app.buttons["todayDirectEdit"]
        XCTAssertTrue(change.waitForExistence(timeout: 30), app.debugDescription)
        change.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let target = app.textFields["todayEditTarget"]
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(target.value as? String, "28:30")
        capture("01-real-today-initial")
        target.tap()
        target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "25:30")
        capture("02-keyboard-edit")
        app.buttons["Done"].firstMatch.tap()
        app.buttons["todayEditReason"].tap()
        app.buttons["Low energy"].tap()
        XCTAssertEqual(target.value as? String, "25:30", "Reason must preserve draft")
        app.buttons["todayEditChooseWorkout"].tap()
        XCTAssertTrue(app.navigationBars["Workouts"].waitForExistence(timeout: 8))
        app.buttons["Close"].tap()
        XCTAssertEqual(target.value as? String, "25:30", "Picker cancel must preserve draft")
        app.buttons["todayEditEffort"].tap()
        app.buttons.matching(identifier: "Very easy").allElementsBoundByIndex.last!.tap()
        capture("03-reason-effort-draft")
        try await control("fail-next")
        app.buttons["todayChangeApply"].tap()
        XCTAssertTrue(app.staticTexts["todayEditFailure"].waitForExistence(timeout: 8), app.debugDescription)
        capture("04-failure-retains-draft")
        XCTAssertEqual(target.value as? String, "25:30")
        try await control("delay-next")
        app.buttons["todayChangeApply"].tap()
        capture("05-loading")
        XCTAssertTrue(target.waitForNonExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.buttons["todayDirectEdit"].exists)
        capture("06-applied-today")
        app.terminate()
        app.launch()
        XCTAssertTrue(change.waitForExistence(timeout: 30))
        change.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertEqual(target.value as? String, "25:30", "Canonical reload must keep the saved target")
        app.buttons["todayEditChooseWorkout"].tap()
        XCTAssertTrue(app.navigationBars["Workouts"].waitForExistence(timeout: 8))
        let workout = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Easy 30")).firstMatch
        reveal(workout, in: app)
        workout.tap()
        let use = app.buttons["todayEditUseWorkout"]
        reveal(use, in: app)
        capture("07-catalog-details-use")
        try await control("fail-next")
        use.tap()
        XCTAssertTrue(app.staticTexts["todayEditUseFailure"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(use.exists && use.isEnabled)
        capture("07b-use-failure-retains-selection")
        try await control("delay-next")
        use.tap()
        if use.exists {
            XCTAssertFalse(use.isEnabled)
            if app.buttons["Close"].exists { XCTAssertFalse(app.buttons["Close"].isEnabled) }
            XCTAssertFalse(app.navigationBars.buttons["Back"].exists)
            capture("07c-use-loading-dismissal-blocked")
        }
        XCTAssertTrue(use.waitForNonExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(target.waitForNonExistence(timeout: 5))
        XCTAssertTrue(change.exists)
        XCTAssertFalse(app.buttons["Pause"].exists, "Use must not start recording")
        capture("08-use-closes-entire-flow")
        change.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        app.buttons["todayEditSkip"].tap()
        app.buttons.matching(identifier: "Cancel").allElementsBoundByIndex.last!.tap()
        XCTAssertTrue(target.exists)
        app.buttons["todayEditSkip"].tap()
        app.buttons.matching(identifier: "Skip today").allElementsBoundByIndex.last!.tap()
        XCTAssertTrue(change.waitForNonExistence(timeout: 15))
        capture("09-skip-confirmed")
    }

    @MainActor
    func testMissingCapabilitiesKeepLocalDraftEditable() async throws {
        try await control("reset")
        let app = launchFixtureApp(extraArguments: ["-OutboundAPIBaseURL", base + "/v1", "-OutboundWorkoutEditMissingContextUITest", "-measurement_unit_system_v1", "metric"])
        let change = app.buttons["todayDirectEdit"]
        XCTAssertTrue(change.waitForExistence(timeout: 30))
        change.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let target = app.textFields["todayEditTarget"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertTrue(target.isEnabled)
        XCTAssertTrue(app.buttons["todayEditGoal"].isEnabled)
        XCTAssertTrue(app.buttons["todayEditEffort"].isEnabled)
        XCTAssertTrue(app.buttons["todayEditChooseWorkout"].isEnabled)
        XCTAssertTrue(app.buttons["todayEditSkip"].isEnabled)
        app.buttons["todayEditGoal"].tap(); app.buttons["Distance"].tap()
        target.tap(); target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "4")
        app.buttons["Done"].firstMatch.tap()
        app.buttons["todayEditEffort"].tap(); app.buttons.matching(identifier: "Steady").allElementsBoundByIndex.last!.tap()
        app.buttons["todayEditReason"].tap(); app.buttons["Other"].tap()
        XCTAssertEqual(target.value as? String, "4")
        capture("25-local-draft-without-capabilities")
        // Goal drafting is local; the existing multi-phase fixture only authorizes time saves.
        app.buttons["todayEditGoal"].tap(); app.buttons["Time"].tap()
        target.tap(); target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "25:30")
        app.buttons["Done"].firstMatch.tap()
        app.buttons["todayEditChooseWorkout"].tap()
        let workout = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Easy 30")).firstMatch
        reveal(workout, in: app); workout.tap()
        let use = app.buttons["todayEditUseWorkout"]
        reveal(use, in: app)
        try await control("fail-next")
        use.tap()
        XCTAssertTrue(app.staticTexts["todayEditUseFailure"].waitForExistence(timeout: 10))
        XCTAssertTrue(use.isEnabled)
        capture("26-local-picker-selection-retained-after-failure")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Close"].tap()
        XCTAssertEqual(target.value as? String, "25:30")
        XCTAssertTrue(app.buttons["todayEditEffort"].label.contains("Steady"))
        try await control("drop-response-next")
        app.buttons["todayChangeApply"].tap()
        XCTAssertTrue(app.staticTexts["todayEditFailure"].waitForExistence(timeout: 10))
        XCTAssertEqual(target.value as? String, "25:30")
        XCTAssertTrue(target.isEnabled)
        capture("27-local-draft-retained-after-apply-failure")
        app.buttons["todayChangeApply"].tap()
        XCTAssertTrue(target.waitForNonExistence(timeout: 15))
        capture("28-local-draft-retry-saved")
        change.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.tap(); target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "5")
        app.buttons["Done"].firstMatch.tap()
        _ = try await fixtureJSON("/__fixture/reset", body: ["duration": 1800])
        app.buttons["todayChangeApply"].tap()
        XCTAssertTrue(app.staticTexts["todayEditFailure"].waitForExistence(timeout: 10))
        XCTAssertEqual(target.value as? String, "5", "Changed canonical slot must not retarget this draft")
        capture("29-changed-baseline-retains-local-draft")
        app.buttons["Cancel"].tap()
        change.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertEqual(target.value as? String, "30", "Next opening uses the refreshed canonical workout")
    }

    @MainActor
    func testNarrowLargestSpanishDark() async throws {
        try await control("reset")
        let app = launchFixtureApp(extraArguments: [
            "-OutboundAPIBaseURL", base + "/v1", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-outbound_theme_v1", "neonPulse", "-appearance_mode_v1", "dark",
        ])
        let change = app.buttons["todayDirectEdit"]
        XCTAssertTrue(change.waitForExistence(timeout: 30), app.debugDescription)
        reveal(change, in: app); change.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let target = app.textFields["todayEditTarget"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        capture("10-narrow-largest-spanish-dark-top")
        let reason = app.buttons["todayEditReason"]
        reveal(reason, in: app); reason.tap()
        let other = app.buttons["todayEditReasonOption-other"]
        reveal(other, in: app)
        other.tap()
        let apply = app.buttons["todayChangeApply"]
        XCTAssertTrue(apply.exists && apply.isHittable)
        capture("11-narrow-largest-reason-actions")
        for _ in 0..<8 where !target.isHittable { app.swipeDown() }
        XCTAssertTrue(target.isHittable, app.debugDescription)
        target.tap()
        try Data("focused".utf8).write(to: URL(fileURLWithPath: "/tmp/outbound-narrow-keyboard-focus-ready"))
        try await Task.sleep(for: .seconds(20))
        capture("12-narrow-largest-keyboard")
        let keyboard = app.keyboards.firstMatch
        let done = app.buttons["Listo"].firstMatch.exists ? app.buttons["Listo"].firstMatch : app.buttons["Done"].firstMatch
        XCTAssertTrue(keyboard.exists, "Narrow verification requires the real software keyboard")
        XCTAssertTrue(done.isHittable)
        XCTAssertLessThanOrEqual(done.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertLessThanOrEqual(apply.frame.maxY, keyboard.frame.minY + 1)
        let proof: [String: Any] = ["softwareKeyboardPresent": keyboard.exists,
            "keyboardTop": keyboard.frame.minY, "doneBottom": done.frame.maxY,
            "applyBottom": apply.frame.maxY, "doneHittable": done.isHittable,
            "applyHittable": apply.isHittable]
        try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/outbound-direct-edit-ui/12-narrow-keyboard-viewport.json"))
        done.tap()
        XCTAssertTrue(apply.isHittable)
    }

    @MainActor
    func testNarrowLargestCatalogDetailsUse() async throws {
        try await control("reset")
        let app = launchFixtureApp(extraArguments: [
            "-OutboundAPIBaseURL", base + "/v1", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-outbound_theme_v1", "neonPulse", "-appearance_mode_v1", "dark",
        ])
        let change = app.buttons["todayDirectEdit"]
        XCTAssertTrue(change.waitForExistence(timeout: 30))
        change.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let choose = app.buttons["todayEditChooseWorkout"]
        reveal(choose, in: app); choose.tap()
        let workout = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Easy 30")).firstMatch
        reveal(workout, in: app, maxSwipes: 15); workout.tap()
        let use = app.buttons["todayEditUseWorkout"]
        reveal(use, in: app, maxSwipes: 20)
        XCTAssertTrue(use.isHittable && use.isEnabled)
        capture("17-narrow-largest-details-use")
        use.tap()
        XCTAssertTrue(use.waitForNonExistence(timeout: 20))
        XCTAssertFalse(app.textFields["todayEditTarget"].exists)
    }

    @MainActor
    func testStaleEditorKeepsOriginalDraft() async throws {
        try await control("reset")
        let app = launchFixtureApp(extraArguments: ["-OutboundAPIBaseURL", base + "/v1"])
        let change = app.buttons["todayDirectEdit"]
        XCTAssertTrue(change.waitForExistence(timeout: 30))
        change.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let target = app.textFields["todayEditTarget"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.tap()
        target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "24")
        app.buttons["Done"].firstMatch.tap()
        // Replacing the canonical slot while its editor remains open must reject, never retarget.
        try await control("reset")
        app.buttons["todayChangeApply"].tap()
        XCTAssertTrue(app.staticTexts["todayEditFailure"].waitForExistence(timeout: 8))
        XCTAssertEqual(target.value as? String, "24")
        capture("13-stale-source-preserves-draft")
    }

    @MainActor
    func testExtremeInputAndReactiveThemes() async throws {
        try await control("reset")
        let app = launchFixtureApp(extraArguments: ["-OutboundAPIBaseURL", base + "/v1"], overrideLaunchPreferences: false)
        let change = app.buttons["todayDirectEdit"]
        XCTAssertTrue(change.waitForExistence(timeout: 30))
        change.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let target = app.textFields["todayEditTarget"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.tap()
        target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + String(Int.max))
        XCTAssertFalse(app.buttons["todayChangeApply"].isEnabled)
        capture("14-input-overflow-rejected")
        app.buttons["Done"].firstMatch.tap()
        app.buttons["Cancel"].firstMatch.tap()

        func selectTheme(_ name: String, mode: String) {
            app.buttons["tab.me"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let settings = app.buttons["Settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
            let theme = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Theme")).firstMatch
            reveal(theme, in: app); theme.tap()
            let choice = app.buttons[name]
            reveal(choice, in: app); choice.tap()
            XCTAssertEqual(choice.value as? String, "Selected")
            let modeButton = app.buttons[mode]
            for _ in 0..<8 where !modeButton.isHittable { app.swipeDown() }
            XCTAssertTrue(modeButton.isHittable); modeButton.tap()
            app.buttons["Done"].tap()
            app.navigationBars["Settings"].buttons.firstMatch.tap()
            let todayTab = app.buttons["tab.today"].exists ? app.buttons["tab.today"] : app.buttons["tab.start"]
            todayTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(change.waitForExistence(timeout: 5))
            change.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(target.waitForExistence(timeout: 5))
        }
        selectTheme("Neon Pulse", mode: "Dark")
        capture("15-dark-theme-reactive-editor")
        app.buttons["Cancel"].firstMatch.tap()
        selectTheme("Victory Gold", mode: "Light")
        capture("16-light-gold-reactive-editor")
    }

    @MainActor
    func testEditedWorkoutRecoveryKeepsPerformedRevision() async throws {
        try await control("reset")
        let app = launchFixtureApp(extraArguments: ["-OutboundAPIBaseURL", base + "/v1", "-OutboundWorkoutEditRecoveryUITest"])
        let change = app.buttons["todayDirectEdit"]
        XCTAssertTrue(change.waitForExistence(timeout: 30))
        change.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let target = app.textFields["todayEditTarget"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertEqual(target.value as? String, "28:30")
        target.tap(); target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "25:30")
        app.buttons["Done"].firstMatch.tap()
        app.buttons["todayChangeApply"].tap()
        XCTAssertTrue(target.waitForNonExistence(timeout: 10))
        let before = try await fixtureJSON("/v1/planning/activity-suggestion")
        let primary = try XCTUnwrap(before["primary"] as? [String: Any])
        let performedID = try XCTUnwrap(primary["workoutEditId"] as? String)
        let performedRevision = try XCTUnwrap(primary["workoutRevision"] as? String)
        let plannedID = try XCTUnwrap(primary["plannedWorkoutId"] as? String)
        let outdoor = app.buttons["Outdoor"]
        if outdoor.exists {
            let options = app.scrollViews["activity.launch.options"]
            for _ in 0..<8 where !app.frame.contains(outdoor.frame) { options.swipeLeft() }
            XCTAssertTrue(app.frame.contains(outdoor.frame))
            outdoor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        let start = app.buttons["tab.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let pause = app.buttons["Pause activity"]
        XCTAssertTrue(pause.waitForExistence(timeout: 25), app.debugDescription)
        pause.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Resume activity"].waitForExistence(timeout: 8))
        capture("18-edited-recording-before-restart")
        let latest = try await fixtureJSON("/v1/planning/activity-suggestion")
        let source = try XCTUnwrap(latest["primary"] as? [String: Any])
        let context = try XCTUnwrap(latest["editContext"] as? [String: Any])
        _ = try await fixtureJSON("/v1/planning/workout-edits/apply", body: [
            "plannedWorkoutId": plannedID, "suggestionId": source["id"]!, "validForDate": latest["validForDate"]!,
            "baseRevision": context["baseRevision"]!, "idempotencyKey": UUID().uuidString, "reason": NSNull(),
            "change": ["operation": "edit", "edits": ["target": ["kind": "time", "seconds": 1200], "effortPreset": "steady"]],
        ])
        app.terminate()
        app.launchArguments.removeAll { $0 == "-OutboundUITestResetRecording" || $0 == "-OutboundWorkoutEditRecoveryUITest" }
        app.launch(); dismissFixturePermissionAlerts(app)
        XCTAssertTrue(app.buttons["Resume activity"].waitForExistence(timeout: 20), app.debugDescription)
        capture("19-edited-recording-recovered")
        app.buttons["Finish activity"].tap()
        let save = app.buttons["Save activity"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(save.isEnabled, "Synthetic canonical start supplies six minutes; production thresholds remain active")
        save.tap()
        XCTAssertTrue(app.staticTexts["You made time for this today."].waitForExistence(timeout: 20), app.debugDescription)
        capture("20-recovered-workout-saved")
        var evidence = try await fixtureJSON("/__fixture/evidence")
        for _ in 0..<12 where (evidence["completions"] as? [[String: Any]])?.isEmpty != false {
            try await Task.sleep(for: .milliseconds(500))
            evidence = try await fixtureJSON("/__fixture/evidence")
        }
        let completions = try XCTUnwrap(evidence["completions"] as? [[String: Any]])
        XCTAssertEqual(completions.count, 1)
        let completion = try XCTUnwrap(completions.first)
        XCTAssertEqual(completion["plannedWorkoutId"] as? String, plannedID)
        XCTAssertEqual(completion["workoutEditId"] as? String, performedID)
        XCTAssertEqual(completion["workoutRevision"] as? String, performedRevision)
        let proof: [String: Any] = ["performed": primary, "completion": completion, "edits": evidence["edits"] ?? []]
        let data = try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/outbound-direct-edit-ui/21-recovery-completion-linkage.json"))
    }

    private func fixtureJSON(_ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: base + path)!)
        if let body {
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @MainActor
    func testCanonicalWorkoutReminderResolution() async throws {
        try await control("reset")
        let original = try await fixtureJSON("/v1/planning/activity-suggestion")
        let source = try XCTUnwrap(original["primary"] as? [String: Any])
        let context = try XCTUnwrap(original["editContext"] as? [String: Any])
        let plannedID = try XCTUnwrap(source["plannedWorkoutId"] as? String)
        let applied = try await fixtureJSON("/v1/planning/workout-edits/apply", body: [
            "plannedWorkoutId": plannedID, "suggestionId": source["id"]!, "validForDate": original["validForDate"]!,
            "baseRevision": context["baseRevision"]!, "idempotencyKey": UUID().uuidString,
            "change": ["operation": "edit", "edits": ["target": ["kind": "time", "seconds": 1530]]],
        ])
        let receipt = try XCTUnwrap(applied["receipt"] as? [String: Any])
        let path = "/tmp/outbound-direct-edit-ui/23-reminder-resolution.json"
        try? FileManager.default.removeItem(atPath: path)
        let app = launchFixtureApp(extraArguments: ["-OutboundAPIBaseURL", base + "/v1", "-OutboundWorkoutReminderUITest", plannedID])
        for _ in 0..<60 where !FileManager.default.fileExists(atPath: path) { try await Task.sleep(for: .milliseconds(500)) }
        let proof = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        let reference = try XCTUnwrap(proof["workoutReference"] as? [String: Any])
        XCTAssertEqual(reference["id"] as? String, plannedID)
        XCTAssertEqual(reference["workoutEditId"] as? String, receipt["workoutEditId"] as? String)
        XCTAssertEqual(reference["workoutRevision"] as? String, receipt["revision"] as? String)
        XCTAssertEqual(proof["targetDurationSeconds"] as? Int, 1530)
        XCTAssertEqual(proof["startedFromWorkoutReminder"] as? Bool, true)
        XCTAssertEqual((proof["workoutSteps"] as? [[String: Any]])?.count, 3)
        XCTAssertNotEqual(proof["title"] as? String, "Stale cached title")
        capture("23-canonical-reminder-launch")
        app.terminate()
        try FileManager.default.copyItem(atPath: path, toPath: "/tmp/outbound-direct-edit-ui/23-canonical-reminder-proof.json")
        try FileManager.default.removeItem(atPath: path)
        app.launchArguments += ["-OutboundWorkoutReminderStaleUITest"]
        app.launch()
        for _ in 0..<60 where !FileManager.default.fileExists(atPath: path) { try await Task.sleep(for: .milliseconds(500)) }
        let stale = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        XCTAssertEqual(stale["unavailable"] as? Bool, true)
        XCTAssertTrue(app.buttons["todayDirectEdit"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Pause activity"].exists)
        capture("24-stale-reminder-returns-today")
    }

    @MainActor
    func testFocusedKeyboardViewport() async throws {
        try await control("reset")
        let app = launchFixtureApp(extraArguments: ["-OutboundAPIBaseURL", base + "/v1", "-outbound_theme_v1", "victoryGold", "-appearance_mode_v1", "light"])
        let change = app.buttons["todayDirectEdit"]
        XCTAssertTrue(change.waitForExistence(timeout: 30))
        change.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let target = app.textFields["todayEditTarget"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertEqual(target.value as? String, "28:30")
        target.tap(); target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "25:30")
        try Data("focused".utf8).write(to: URL(fileURLWithPath: "/tmp/outbound-keyboard-focus-ready"))
        // A host-side, task-device-only keyboard toggle may run in this diagnostic window.
        try await Task.sleep(for: .seconds(20))
        let keyboard = app.keyboards.firstMatch
        let done = app.buttons["Done"].firstMatch
        let apply = app.buttons["todayChangeApply"]
        capture("22-stable-focused-keyboard-viewport")
        let limit = keyboard.exists ? keyboard.frame.minY : app.frame.maxY
        let proof: [String: Any] = ["softwareKeyboardPresent": keyboard.exists,
            "viewportBottom": limit, "doneBottom": done.frame.maxY, "applyBottom": apply.frame.maxY,
            "doneHittable": done.isHittable, "applyHittable": apply.isHittable]
        try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/outbound-direct-edit-ui/22-keyboard-viewport.json"))
        XCTAssertTrue(done.exists && done.isHittable)
        XCTAssertLessThanOrEqual(done.frame.maxY, limit + 1)
        XCTAssertLessThanOrEqual(apply.frame.maxY, limit + 1)
        done.tap()
        XCTAssertEqual(target.value as? String, "25:30")
    }

    private func control(_ action: String) async throws {
        var request = URLRequest(url: URL(string: base + "/__fixture/" + action)!)
        request.httpMethod = "POST"
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }
    @MainActor private func capture(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot); attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
        let directory = ProcessInfo.processInfo.environment["DIRECT_EDIT_SCREENSHOTS"] ?? "/tmp/outbound-direct-edit-ui"
        do {
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
        }
    }
}
