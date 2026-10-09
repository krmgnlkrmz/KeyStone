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
        sleep(4)   // stars are revealed one by one; a loaded CI simulator is slow
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

    /// A full-screen ad (the interstitial before the next level, a rewarded hint or undo) covers the game and
    /// takes it out of the window; the level must play on afterwards. `-coverProbe` stands in for the ad:
    /// a plain full-screen controller over level 1 for 1.5 s, a second after it opens.
    func testLevelPlaysOnAfterAFullScreenCover() throws {
        launch(["-coverProbe"])
        let levels = app.buttons["menu.levels"]
        XCTAssertTrue(levels.waitForExistence(timeout: 15), "main menu did not appear")
        levels.tap()
        let first = app.buttons["level.1"]
        XCTAssertTrue(first.waitForExistence(timeout: 8), "map did not appear")
        first.tap()
        sleep(5)   // the cover comes and goes
        tapPiece("tb")
        tapPiece("tb")
        let next = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Next Level'")).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 15), "level 1 did not play on after a full-screen cover")
    }

    /// Dark mode with accessibility-size text (Dynamic Type "accessibility1"): menu, map, settings and
    /// the daily sheet must lay out; screenshots let a person check nothing is clipped.
    func testDarkLargeTextScreens() throws {
        launch(["-appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"])
        try walkStaticScreens(prefix: "ax-dark-")
    }

    /// Turkish UI (the second shipped language).
    func testTurkishScreens() throws {
        launch(["-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"])
        try walkStaticScreens(prefix: "tr-")
    }

    /// Menu → map → a level → back; settings; daily — by identifier, so it works in any language.
    private func walkStaticScreens(prefix: String) throws {
        let levels = app.buttons["menu.levels"]
        XCTAssertTrue(levels.waitForExistence(timeout: 15), "main menu did not appear")
        shot(prefix + "01-menu")
        levels.tap()
        let first = app.buttons["level.1"]
        XCTAssertTrue(first.waitForExistence(timeout: 8), "map did not appear")
        sleep(1)
        shot(prefix + "02-map")
        first.tap()
        sleep(3)
        shot(prefix + "03-game")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["menu.settings"].waitForExistence(timeout: 15))
        app.buttons["menu.settings"].tap()
        sleep(1)
        shot(prefix + "07-settings")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["menu.daily"].waitForExistence(timeout: 15))
        app.buttons["menu.daily"].tap()
        XCTAssertTrue(app.buttons["daily.play"].waitForExistence(timeout: 5), "daily sheet did not open")
        sleep(1)
        shot(prefix + "08-daily")
    }

    /// Cold start → main menu, four launches. The app reports, on the kernel's process clock, when
    /// AppModel was created (before that: dyld, frameworks, runtime), when the catalog was decoded and
    /// when the menu appeared. The first launch after install does one-time work and is left out of the
    /// medians. The release bound (2 s to the menu) is for a device; on the CI simulator the system part
    /// varies wildly, so this bounds the app's own part (AppModel → menu).
    func testColdStartReachesTheMenu() throws {
        var menu: [Double] = [], own: [Double] = [], system: [Double] = [], catalog: [Double] = []
        for _ in 0..<4 {
            app = XCUIApplication()
            app.launchArguments = ["-uitest", "-testProbes"]
            app.launch()
            let probe = app.descendants(matching: .any).matching(identifier: "debug.launch").firstMatch
            XCTAssertTrue(probe.waitForExistence(timeout: 30), "main menu did not report its launch time")
            let t = probe.label.split(separator: " ").compactMap { Double($0) }
            if t.count == 3 {
                menu.append(t[0]); system.append(t[1]); catalog.append(t[2] - t[1]); own.append(t[0] - t[1])
            }
            app.terminate()
        }
        XCTAssertEqual(menu.count, 4, "launch probe unreadable")
        func median(_ xs: [Double]) -> Double { let s = xs.dropFirst().sorted(); return s.isEmpty ? .infinity : s[s.count / 2] }
        let fmt = { (xs: [Double]) in xs.map { String(format: "%.2f", $0) }.joined(separator: ", ") }
        print("[launch] menu after process start: \(fmt(menu)) s; before AppModel (system): \(fmt(system)) s; " +
              "AppModel → catalog: \(fmt(catalog)) s; AppModel → menu (app): \(fmt(own)) s; app median \(String(format: "%.2f", median(own))) s")
        XCTAssertLessThan(median(own), 2.0, "the app's own launch path (AppModel → menu) took \(median(own)) s")
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
