import XCTest

/// Uses the real recent-activity/editor/store/picker/Photos export flow. Only
/// simulator camera hardware is substituted with a deterministic image.
final class SavedActivityPhotoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCapturedPhotoRefreshesActivityAndSurvivesMetadataSaveAndRelaunch() {
        let app = launchPhotoEditingApp()
        openRecentActivity(app)
        openPhotoEditor(app)
        capturePhoto(app)
        assertPhotoCount(1, prefix: "EditActivityPhoto-", in: app)
        saveMetadata(app, title: "Photo regression run")
        assertDetailPhoto(0, in: app)
        assertGalleryContainsExport(app)

        app.terminate()
        let restored = launchPhotoEditingApp(restore: true)
        openRecentActivity(restored, title: "Photo regression run")
        assertDetailPhoto(0, in: restored)
        openPhotoEditor(restored)
        assertPhotoCount(1, prefix: "EditActivityPhoto-", in: restored)
        attach(restored, name: "Captured photo restored from disk")
    }

    @MainActor
    func testImportedPhotoRefreshesActivityAndSurvivesMetadataSaveAndRelaunch() {
        let app = launchPhotoEditingApp()
        openRecentActivity(app)
        openPhotoEditor(app)
        // Export a camera photo first, providing a real asset for the system
        // picker without bypassing PhotosPicker or ActivityPhotoImporter.
        capturePhoto(app)
        saveEditor(app)
        assertDetailPhoto(0, in: app)
        openPhotoEditor(app)
        assertPhotoCount(1, prefix: "EditActivityPhoto-", in: app)
        app.buttons["EditActivityImportPhotoButton"].tap()
        selectExportedPhoto(app)
        assertPhotoCount(2, prefix: "EditActivityPhoto-", in: app)
        saveMetadata(app, title: "Imported photo regression run")
        assertDetailPhoto(1, in: app)

        app.terminate()
        let restored = launchPhotoEditingApp(restore: true)
        openRecentActivity(restored, title: "Imported photo regression run")
        assertDetailPhoto(1, in: restored)
        openPhotoEditor(restored)
        assertPhotoCount(2, prefix: "EditActivityPhoto-", in: restored)
        attach(restored, name: "Captured and imported photos restored from disk")
    }

    @MainActor
    private func launchPhotoEditingApp(restore: Bool = false) -> XCUIApplication {
        addUIInterruptionMonitor(withDescription: "Photo library access") { alert in
            for label in ["Allow Full Access", "Allow Access to All Photos", "Allow", "OK"] {
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }
        var arguments = ["-OutboundUITestPhotoEditing", "-saveActivityPhotosToPhotoAlbum", "YES"]
        for tip in ["activity_overflow", "music_discovery", "theme_discovery", "photo_management", "save_route"] {
            arguments += ["-tooltip.\(tip).dismissed.v1", "YES"]
        }
        if restore { arguments.append("-OutboundUITestRestorePhotoEditing") }
        return launchFixtureApp(extraArguments: arguments)
    }

    @MainActor
    private func openRecentActivity(_ app: XCUIApplication, title: String = "Golden Gate Easy Run") {
        XCTAssertTrue(app.buttons["tab.me"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["today.conditions"].waitForExistence(timeout: 10))
        for _ in 0..<3 {
            app.buttons["tab.me"].tap()
            if app.buttons["Settings"].waitForExistence(timeout: 3) { break }
        }
        XCTAssertTrue(app.buttons["Settings"].exists, app.debugDescription)
        let activity = app.staticTexts[title].firstMatch
        reveal(activity, in: app)
        activity.tap()
        XCTAssertTrue(app.buttons["Edit activity"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    private func openPhotoEditor(_ app: XCUIApplication) {
        app.buttons["Edit activity"].tap()
        XCTAssertTrue(app.navigationBars["Edit Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["EditActivityTakePhotoButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func capturePhoto(_ app: XCUIApplication) {
        app.buttons["EditActivityTakePhotoButton"].tap()
        let shutter = app.buttons["Take photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        shutter.tap()
        XCTAssertTrue(app.navigationBars["Edit Activity"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func saveEditor(_ app: XCUIApplication) {
        app.buttons["Save Changes"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let manager = app.navigationBars["Edit Activity"]
        for _ in 0..<10 {
            if manager.waitForNonExistence(timeout: 1) { break }
            for alerts in [app.alerts, springboard.alerts] {
                for label in ["Allow Full Access", "Allow Access to All Photos", "Allow"] {
                    if alerts.buttons[label].exists { alerts.buttons[label].tap(); break }
                }
            }
        }
        XCTAssertFalse(manager.exists, app.debugDescription)
        XCTAssertTrue(app.buttons["Edit activity"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    private func saveMetadata(_ app: XCUIApplication, title: String) {
        let field = app.textFields["EditActivityTitle"]
        field.tap()
        if let current = field.value as? String {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(title)
        saveEditor(app)
        XCTAssertTrue(app.buttons["Edit activity"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    private func assertPhotoCount(_ count: Int, prefix: String, in app: XCUIApplication) {
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == %d", count), object: rows)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed, app.debugDescription)
    }

    @MainActor
    private func assertDetailPhoto(_ index: Int, in app: XCUIApplication) {
        let photo = app.descendants(matching: .any)["SavedActivityPhoto-\(index)"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    private func assertGalleryContainsExport(_ app: XCUIApplication) {
        openPhotoEditor(app)
        app.buttons["EditActivityImportPhotoButton"].tap()
        openPlainstrideAlbum(app)
        attach(app, name: "Real Photos album contains captured photo")
        app.buttons["Cancel"].firstMatch.tap()
        app.navigationBars["Edit Activity"].buttons["Cancel"].tap()
    }

    @MainActor
    private func selectExportedPhoto(_ app: XCUIApplication) {
        openPlainstrideAlbum(app)
        let image = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Photo,")).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5), app.debugDescription)
        // The remote Photos grid exposes non-hittable image AX nodes on some
        // runtimes. Tap the visible asset's center, then verify real selection.
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let done = app.navigationBars["Plainstride"].buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(done.isEnabled)
        done.tap()
    }

    @MainActor
    private func openPlainstrideAlbum(_ app: XCUIApplication) {
        let collections = app.buttons["Collections"]
        XCTAssertTrue(collections.waitForExistence(timeout: 5), app.debugDescription)
        collections.tap()
        let album = app.staticTexts["Plainstride"].firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 5), "Export must create the real Plainstride album.\n\(app.debugDescription)")
        album.tap()
        XCTAssertTrue(app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Photo,")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
