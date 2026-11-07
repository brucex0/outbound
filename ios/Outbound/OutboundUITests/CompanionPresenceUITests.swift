import XCTest

/// Focused UI coverage for the fox companion presence contract.
///
/// Runs against synthetic seeded fixtures only: no backend, no push delivery, and no
/// production account. The DEBUG-only ledger reset and delivery-delay arguments keep
/// preview timing deterministic without changing shipped behavior.
final class CompanionPresenceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Launcher and envelope

    @MainActor
    func testFoxLauncherIsSingleControlAndAlwaysOpensAssistant() {
        let app = launchCompanionFixture(deliveryDelaySeconds: 60)

        let launcher = app.buttons["assistant.launcher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: "assistant.launcher").count, 1,
                       "Only one fox/assistant control may exist in the shell")
        XCTAssertTrue(app.buttons["fox.companion.envelope"].waitForExistence(timeout: 15),
                      "Unread actionable items keep a separate envelope control")
        capture(app, name: "Fox launcher and envelope")

        launcher.tap()
        XCTAssertTrue(app.navigationBars["Assistant"].waitForExistence(timeout: 10),
                      "Fox taps always open the assistant")
        capture(app, name: "Fox opens assistant")
        dismissAssistantSheet(app)

        // Today exposes the contextual Start control as `tab.start`; the resting tab is `tab.today`.
        for (tab, anchor) in [("tab.social", "Feed"), ("tab.me", "Settings"), ("tab.today", "tab.start")] {
            app.buttons[tab].tap()
            XCTAssertTrue(app.buttons[anchor].waitForExistence(timeout: 10), anchor)
            XCTAssertTrue(app.buttons["assistant.launcher"].exists, "Launcher must persist on \(tab)")
            XCTAssertEqual(app.buttons.matching(identifier: "assistant.launcher").count, 1,
                           "Duplicate assistant launcher on \(tab)")
            XCTAssertTrue(app.buttons["fox.companion.envelope"].exists,
                          "Envelope must stay reachable on \(tab)")
        }
    }

    @MainActor
    func testEnvelopeOpensExistingNotificationCenter() {
        let app = launchCompanionFixture(deliveryDelaySeconds: 60)

        let envelope = app.buttons["fox.companion.envelope"]
        XCTAssertTrue(envelope.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(envelope.isHittable, "Envelope keeps a 44 pt target")
        for identifier in ["tab.start", "tab.social", "tab.me"] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.exists, identifier)
            XCTAssertFalse(envelope.frame.intersects(control.frame),
                           "Envelope overlaps the \(identifier) navigation control")
        }
        envelope.tap()

        XCTAssertTrue(app.navigationBars["Notification Center"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Leo Martinez wants to connect."].waitForExistence(timeout: 10))
        capture(app, name: "Envelope opens Notification Center")

        app.buttons["NotificationCenterCloseButton"].tap()
        XCTAssertTrue(app.buttons["assistant.launcher"].waitForExistence(timeout: 10),
                      "Closing the inbox returns to the shell launcher")
    }

    // MARK: - Preview

    @MainActor
    func testPreviewRoutesToMatchingNotificationDestination() {
        let app = launchCompanionFixture()

        let preview = app.buttons["fox.companion.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Leo Martinez wants to connect."].exists,
                      "The preview must reuse the durable inbox message")
        XCTAssertFalse(app.staticTexts["Maya Chen cheered your activity."].exists,
                       "A higher-ranked actionable item must win delivery")
        XCTAssertTrue(preview.isHittable, "Preview stays reachable above the dock")
        for identifier in ["tab.start", "tab.social", "tab.me"] {
            XCTAssertFalse(preview.frame.intersects(app.buttons[identifier].frame),
                           "Preview overlaps the \(identifier) navigation control")
        }
        capture(app, name: "Companion preview for connection request")

        preview.tap()
        XCTAssertTrue(app.navigationBars["Connections"].waitForExistence(timeout: 10),
                      "The preview must open the real notification destination, not a new inbox")
        XCTAssertTrue(app.staticTexts["Leo Martinez"].waitForExistence(timeout: 10))
        capture(app, name: "Preview routed to Connections")

        // The inbox's Close control is inherited by the pushed route, so pick the
        // leading Back control by position instead of the first matching button.
        let back = app.navigationBars["Connections"].buttons.allElementsBoundByIndex
            .first { $0.isHittable && $0.frame.minX < 100 }
        XCTAssertNotNil(back, "Connections must keep a leading Back control")
        back?.tap()
        XCTAssertTrue(app.navigationBars["Notification Center"].waitForExistence(timeout: 10),
                      "Back returns to the existing inbox underneath the destination")
    }

    @MainActor
    func testDismissedPreviewStaysGoneAndKeepsInboxItemUnread() {
        let app = launchCompanionFixture()

        let preview = app.buttons["fox.companion.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 20), app.debugDescription)
        let dismiss = app.buttons["fox.companion.dismiss"]
        XCTAssertTrue(dismiss.isHittable, "Dismissal needs a clear, reachable target")
        capture(app, name: "Preview before dismissal")
        dismiss.tap()
        XCTAssertTrue(preview.waitForNonExistence(timeout: 5))

        // Switching tabs must not replay the claimed preview.
        app.buttons["tab.social"].tap()
        XCTAssertTrue(app.buttons["Feed"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["fox.companion.preview"].waitForExistence(timeout: 3),
                       "Tab change must not replay a dismissed preview")

        // Background/foreground must not replay it either.
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)
        app.activate()
        XCTAssertTrue(app.buttons["assistant.launcher"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["fox.companion.preview"].waitForExistence(timeout: 3),
                       "Foreground transition must not replay a dismissed preview")

        // A relaunch without the ledger reset keeps the receipt and the unread inbox item.
        let relaunched = relaunchCompanionFixtureWithoutReset()
        XCTAssertTrue(relaunched.buttons["assistant.launcher"].waitForExistence(timeout: 15),
                      relaunched.debugDescription)
        XCTAssertFalse(relaunched.buttons["fox.companion.preview"].waitForExistence(timeout: 5),
                       "A relaunch must not replay the same notification")

        let envelope = relaunched.buttons["fox.companion.envelope"]
        XCTAssertTrue(envelope.waitForExistence(timeout: 10),
                      "Dismissing the preview must not change read state or hide the inbox")
        envelope.tap()
        XCTAssertTrue(relaunched.navigationBars["Notification Center"].waitForExistence(timeout: 10))
        XCTAssertTrue(relaunched.staticTexts["Leo Martinez wants to connect."].waitForExistence(timeout: 10),
                      "The durable inbox item must survive preview dismissal")
        capture(relaunched, name: "Dismissed preview still present in inbox")
    }

    @MainActor
    func testPreviewIsSuppressedDuringRecordingAndDeliveredAfterExit() {
        // The live fixture seeds the recording for this launch, so delivery is scheduled
        // past the moment the session owns the screen.
        let app = launchCompanionFixture(extraArguments: liveRunArguments, deliveryDelaySeconds: 3)

        XCTAssertTrue(app.buttons["Pause activity"].waitForExistence(timeout: 15),
                      "Seeded live session must be recording")
        XCTAssertFalse(app.buttons["fox.companion.preview"].exists,
                       "Recording must never show an unsolicited preview")
        XCTAssertFalse(app.buttons["fox.companion.envelope"].exists,
                       "Recording must not add a second launcher affordance")
        XCTAssertTrue(app.buttons["assistant.launcher"].exists,
                      "Compact recording keeps exactly one fox entry")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(app.buttons["fox.companion.preview"].exists,
                       "No preview may appear while recording continues")

        finishAndDiscardLiveRun(app)
        XCTAssertTrue(app.buttons["assistant.launcher"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["fox.companion.preview"].waitForExistence(timeout: 20),
                      "Leaving recording must deliver the deferred preview instead of losing it")
        capture(app, name: "Preview delivered after recording")
    }

    @MainActor
    func testPreviewIsSuppressedWhileTheAssistantSheetIsOpen() {
        // Notification Center is not a valid suppression probe: opening it marks the
        // durable inbox read, which legitimately removes the delivery candidate.
        let app = launchCompanionFixture(deliveryDelaySeconds: 5)

        let launcher = app.buttons["assistant.launcher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 15), app.debugDescription)
        launcher.tap()
        XCTAssertTrue(app.navigationBars["Assistant"].waitForExistence(timeout: 10))

        Thread.sleep(forTimeInterval: 6)
        XCTAssertFalse(app.buttons["fox.companion.preview"].exists,
                       "The dock preview must not appear behind or over a presented sheet")

        dismissAssistantSheet(app)
        XCTAssertTrue(app.buttons["fox.companion.preview"].waitForExistence(timeout: 20),
                      "Closing the sheet delivers the deferred preview instead of dropping it")
        capture(app, name: "Preview after assistant sheet closes")
    }

    // MARK: - Save celebration

    @MainActor
    func testCelebrationIsShownOnlyOnTheSavedPage() {
        let app = launchCompanionFixture(extraArguments: liveRunArguments)
        XCTAssertTrue(app.buttons["Pause activity"].waitForExistence(timeout: 15))

        app.buttons["Pause activity"].press(forDuration: 1.1)
        XCTAssertTrue(app.buttons["Finish activity"].waitForExistence(timeout: 5))
        app.buttons["Finish activity"].tap()
        XCTAssertTrue(app.buttons["Save activity"].waitForExistence(timeout: 8))

        XCTAssertFalse(celebrationMark(app).exists,
                       "The unsaved review must not show a fox celebration")
        capture(app, name: "Unsaved review without celebration")

        app.buttons["Save activity"].tap()
        XCTAssertTrue(app.staticTexts["You made time for this today."].waitForExistence(timeout: 15))
        XCTAssertTrue(celebrationMark(app).waitForExistence(timeout: 5),
                      "The successful save page owns the one fox celebration")
        capture(app, name: "Saved page with fox celebration")

        let done = app.buttons["Done"]
        for _ in 0..<5 where !done.isHittable { app.swipeUp() }
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(app.buttons["tab.start"].waitForExistence(timeout: 10))
        XCTAssertFalse(celebrationMark(app).exists,
                       "The celebration must not leak onto history or the shell")
    }

    @MainActor
    func testDiscardedReviewNeverShowsCelebration() {
        let app = launchCompanionFixture(extraArguments: liveRunArguments)
        XCTAssertTrue(app.buttons["Pause activity"].waitForExistence(timeout: 15))

        app.buttons["Pause activity"].press(forDuration: 1.1)
        XCTAssertTrue(app.buttons["Finish activity"].waitForExistence(timeout: 5))
        app.buttons["Finish activity"].tap()
        XCTAssertTrue(app.buttons["Save activity"].waitForExistence(timeout: 8))
        XCTAssertFalse(celebrationMark(app).exists)

        XCTAssertTrue(app.buttons["ClosePostRunSummaryButton"].exists)
        app.buttons["ClosePostRunSummaryButton"].tap()
        let alert = app.alerts["Discard unsaved activity?"]
        if alert.waitForExistence(timeout: 2) { alert.buttons["Discard activity"].tap() }
        XCTAssertTrue(app.buttons["tab.start"].waitForExistence(timeout: 10))
        XCTAssertFalse(celebrationMark(app).exists,
                       "Discarding must never celebrate a save")
    }

    // MARK: - Helpers

    private var liveRunArguments: [String] {
        ["-OutboundUITestLive10K", "-measurement_unit_system_v1", "metric"]
    }

    private var companionTooltipArguments: [String] {
        // Fresh installs can present a discovery popover, which correctly pauses
        // companion presence. Keep unrelated tips outside these focused scenarios.
        ["theme_discovery", "activity_overflow", "music_discovery", "cheer_me_on", "voice_guide", "shoes", "swipe_to_map"]
            .flatMap { ["-tooltip.\($0).dismissed.v1", "YES"] }
    }

    @MainActor
    private func launchCompanionFixture(
        extraArguments: [String] = [],
        deliveryDelaySeconds: Int? = nil
    ) -> XCUIApplication {
        var arguments = companionTooltipArguments + extraArguments
        // Deterministic ledger reset for the seeded UI-test account only.
        arguments.append("-OutboundUITestResetCompanionPresence")
        if let deliveryDelaySeconds {
            arguments += ["-OutboundCompanionDeliveryDelaySeconds", "\(deliveryDelaySeconds)"]
        }
        return launchFixtureApp(extraArguments: arguments)
    }

    /// Relaunch keeps the presentation ledger: only the recording journal is reset.
    @MainActor
    private func relaunchCompanionFixtureWithoutReset() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-OutboundUseMockMusic", "-OutboundDisableFirebase", "-OutboundSkipOnboarding",
            "-OutboundUITestSeedData", "-home_widget_onboarding_seen_v1", "YES",
            "-push_notification_permission_primer_seen_v1", "YES",
            "-new_user_onboarding_completed_v2.UI test session", "YES",
            "-voice_guide_enabled_v1", "NO", "-watch.startWatchApp", "NO",
            "-auto_pause_running_enabled_v1", "NO",
            "-OutboundUITestResetRecording",
        ]
        app.launchArguments += companionTooltipArguments
        app.launch()
        dismissFixturePermissionAlerts(app)
        return app
    }

    @MainActor
    private func dismissAssistantSheet(_ app: XCUIApplication) {
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.navigationBars["Assistant"].waitForNonExistence(timeout: 5),
                      "Assistant sheet must dismiss back to the shell")
    }

    @MainActor
    private func finishAndDiscardLiveRun(_ app: XCUIApplication) {
        app.buttons["Pause activity"].press(forDuration: 1.1)
        XCTAssertTrue(app.buttons["Finish activity"].waitForExistence(timeout: 8))
        app.buttons["Finish activity"].tap()
        XCTAssertTrue(app.buttons["Save activity"].waitForExistence(timeout: 10))
        discardReview(app)
    }

    @MainActor
    private func celebrationMark(_ app: XCUIApplication) -> XCUIElement {
        // The combined saved heading and the animated mark inside it can both carry
        // this identifier, so resolve one matching element rather than raising.
        app.descendants(matching: .any).matching(identifier: "fox.companion.celebration").firstMatch
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
