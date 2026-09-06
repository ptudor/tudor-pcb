import XCTest

final class WorkspaceUITests: XCTestCase {
    @MainActor
    func testLoadedWorkspaceCanReplaceCancelAndRetryAtLargeTextSize() throws {
        let app = XCUIApplication(bundleIdentifier: "net.ptudor.tudorpcb")
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "boardA", withExtension: "gko", subdirectory: "Fixtures"))
        app.launchArguments = [fixture.path, "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["boardA"].waitForExistence(timeout: 30), app.debugDescription)
        for _ in 0..<2 {
            var open = app.buttons["open-package"].firstMatch
            if !open.waitForExistence(timeout: 3), app.buttons["OverflowBarButtonItem"].exists {
                app.buttons["OverflowBarButtonItem"].tap()
                if !open.exists { open = app.buttons["Replace Package…"].firstMatch }
            }
            XCTAssertTrue(open.waitForExistence(timeout: 3), app.debugDescription)
            XCTAssertTrue(open.isHittable)
            open.tap()
            let cancel = app.buttons["Cancel"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
            cancel.tap()
            XCTAssertTrue(app.navigationBars["boardA"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["open-package"].firstMatch.exists || app.buttons["OverflowBarButtonItem"].exists)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Loaded workspace replacement at accessibility text size"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
