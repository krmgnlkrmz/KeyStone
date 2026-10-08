import XCTest

/// Walks the real app (no ads, no consent, in-memory progress) and saves screenshots of each screen.
/// SCREENSHOT_DIR (via TEST_RUNNER_SCREENSHOT_DIR) collects PNGs for the App Store set.
final class SmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uitest", "-seedLevels", "12"] + extra
        app.launch()
    }

    private func shot(_ name: String) {
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device"
            let folder = URL(fileURLWithPath: dir).appendingPathComponent(device.replacingOccurrences(of: " ", with: "-"))
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? image.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }

    private func tapPiece(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        // Pieces are invisible accessibility buttons over the SpriteKit view; match by identifier, any type.
        let piece = app.descendants(matching: .any).matching(identifier: "piece.\(id)").firstMatch
        XCTAssertTrue(piece.waitForExistence(timeout: 8), "piece \(id) not found", file: file, line: line)
        piece.tap()
    }

    func testWalkThroughMainScreens() throws {
        launch()
        // Main menu
        let levels = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Levels'")).firstMatch
        XCTAssertTrue(levels.waitForExistence(timeout: 15), "main menu did not appear")
        shot("01-menu")

        // Level map
        levels.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        shot("02-map")

        // Level 1: take a post out from under the beam → collapse replay.
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Level 1 '")).firstMatch.tap()
        sleep(2)
        shot("03-game")
        tapPiece("p1")
        tapPiece("p1")
        let retry = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Retry'")).firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 15), "Collapse replay did not appear")
        sleep(3)
        shot("04-collapse-replay")

        // Retry, then lift the stone block off → Level Clear.
        retry.tap()
        sleep(2)
        tapPiece("tb")
        tapPiece("tb")
        let next = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Next Level'")).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 15), "Level Clear did not appear")
        sleep(2)
        shot("05-level-clear")

        // Level 2: pause and leave.
        next.tap()
        sleep(2)
        let pause = app.buttons["Pause"].firstMatch
        if pause.waitForExistence(timeout: 5) { pause.tap() }
        let resume = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Resume'")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "Pause sheet did not appear")
        shot("06-pause")
        app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Back to Map'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))

        // Settings sheet
        app.navigationBars.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Settings'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        shot("07-settings")
    }

    func testDailySheetOpens() throws {
        launch()
        let daily = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Daily Level'")).firstMatch
        XCTAssertTrue(daily.waitForExistence(timeout: 15))
        daily.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Play'")).firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        shot("08-daily")
    }

    /// A short "monkey": random taps across the game screen must not crash the app.
    func testRandomTapsDoNotCrash() throws {
        launch()
        let levels = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Levels'")).firstMatch
        XCTAssertTrue(levels.waitForExistence(timeout: 15))
        levels.tap()
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Level 5 '")).firstMatch.tap()
        sleep(2)
        let window = app.windows.firstMatch
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<120 {
            let p = window.coordinate(withNormalizedOffset: CGVector(dx: Double.random(in: 0.1...0.9, using: &rng),
                                                                      dy: Double.random(in: 0.2...0.85, using: &rng)))
            p.tap()
            XCTAssertEqual(app.state, .runningForeground)
        }
    }
}
