import XCTest
import UIKit

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
    @MainActor
    func testPinchOrbitAndInterruptionLeaveUsableGestures() throws {
        let app = XCUIApplication(bundleIdentifier: "net.ptudor.tudorpcb")
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "boardA", withExtension: "gko", subdirectory: "Fixtures"))
        app.launchArguments = [fixture.path]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["boardA"].waitForExistence(timeout: 30))
        let board = app.otherElements["physical-board"]
        XCTAssertTrue(board.waitForExistence(timeout: 10))
        let before = greenPixels(board.screenshot())
        XCTAssertGreaterThan(before, 500)
        board.pinch(withScale: 1.4, velocity: 0.5)
        XCTAssertGreaterThan(greenPixels(board.screenshot()), before)
        let pinched = board.screenshot().pngRepresentation
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).press(forDuration: 0.1, thenDragTo: board.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.6)))
        XCTAssertNotEqual(board.screenshot().pngRepresentation, pinched)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(board.waitForExistence(timeout: 10))
        let resumed = greenPixels(board.screenshot())
        board.pinch(withScale: 0.7, velocity: -0.5)
        XCTAssertLessThan(greenPixels(board.screenshot()), resumed)
        let screenshot = XCTAttachment(screenshot: board.screenshot())
        screenshot.name = "Pinch after orbit and application interruption"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testProofGalleryFitsLargeTextAndRotatesWithReachableImageInspection() throws {
        let app = XCUIApplication(bundleIdentifier: "net.ptudor.tudorpcb")
        func visibleDone() -> XCUIElement {
            app.buttons.matching(identifier: "Done").allElementsBoundByIndex.first(where: \.isHittable) ?? app.buttons["Done"].firstMatch
        }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "boardA", withExtension: "gko", subdirectory: "Fixtures"))
        let folder = FileManager.default.temporaryDirectory.appending(path: "gallery-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.copyItem(at: fixture, to: folder.appending(path: "boardA.gko"))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 300)).pngData { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 300))
            UIColor.red.setFill(); context.fill(CGRect(x: 10, y: 10, width: 80, height: 40))
        }
        try image.write(to: folder.appending(path: "boardA_top.png"))
        try image.write(to: folder.appending(path: "boardA_bottom.png"))
        app.launchArguments = [folder.path, "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.navigationBars[folder.lastPathComponent].waitForExistence(timeout: 30))
        if !app.buttons["Color proofs"].firstMatch.exists { app.buttons["OverflowBarButtonItem"].tap() }
        app.buttons["Color proofs"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Color proofs"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(visibleDone().isHittable, app.debugDescription)
        let inspect = app.buttons["Inspect Image…"].firstMatch
        for _ in 0..<5 where !inspect.isHittable { app.swipeUp() }
        XCTAssertTrue(inspect.isHittable, app.debugDescription)
        inspect.tap()
        XCTAssertTrue(app.buttons["Fit Image"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Zoom In"].firstMatch.tap()
        let proof = app.descendants(matching: .any)["proof-inspection-image"].firstMatch
        XCTAssertTrue(proof.exists, app.debugDescription)
        proof.swipeLeft()
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(visibleDone().waitForExistence(timeout: 5))
            XCTAssertTrue(visibleDone().isHittable, app.debugDescription)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "Adaptive proof inspection \(orientation.rawValue)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        visibleDone().tap()
        XCTAssertTrue(app.navigationBars["Color proofs"].waitForExistence(timeout: 5))
        visibleDone().tap()
        XCTAssertTrue(app.navigationBars[folder.lastPathComponent].waitForExistence(timeout: 5))
    }

    @MainActor
    private func greenPixels(_ screenshot: XCUIScreenshot) -> Int {
        guard let image = screenshot.image.cgImage else { return 0 }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = buffer.bindMemory(to: UInt8.self)
            var count = 0
            for i in stride(from: 0, to: pixels.count, by: 4) {
                let red = Double(pixels[i]), green = Double(pixels[i + 1]), blue = Double(pixels[i + 2])
                if green > red * 1.1 && green > blue * 1.1 && green > 20 { count += 1 }
            }
            return count
        }
    }

}
