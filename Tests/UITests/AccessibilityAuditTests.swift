import XCTest

/// Xcode's accessibility audit (contrast, hit regions, descriptions, Dynamic Type, clipped text, traits)
/// on the main screens of the real app, in light and dark appearance. Each issue is recorded as a test
/// failure with its description; `[a11y]` lines mark which screen is being audited. CI runs this test on
/// its own (report-only until the screens are clean, then strict).
final class AccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func launch(_ extra: [String]) {
        app = XCUIApplication()
        app.launchArguments = ["-uitest", "-seedLevels", "12"] + extra
        app.launch()
    }

    private func audit(_ screen: String) throws {
        print("[a11y] auditing \(screen)")
        try app.performAccessibilityAudit()
    }

    private func walk(_ appearance: String, extra: [String]) throws {
        launch(extra)
        let levels = app.buttons["menu.levels"]
        XCTAssertTrue(levels.waitForExistence(timeout: 15), "main menu did not appear")
        try audit("\(appearance)/menu")

        levels.tap()
        let first = app.buttons["level.1"]
        XCTAssertTrue(first.waitForExistence(timeout: 8), "map did not appear")
        try audit("\(appearance)/map")

        first.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "piece.tb").firstMatch.waitForExistence(timeout: 10),
                      "level 1 did not load")
        try audit("\(appearance)/game")

        app.terminate()
        launch(extra)
        let settings = app.buttons["menu.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        sleep(1)
        try audit("\(appearance)/settings")

        app.terminate()
        launch(extra)
        let daily = app.buttons["menu.daily"]
        XCTAssertTrue(daily.waitForExistence(timeout: 15))
        daily.tap()
        XCTAssertTrue(app.buttons["daily.play"].waitForExistence(timeout: 10), "daily sheet did not open")
        try audit("\(appearance)/daily")
        app.terminate()
    }

    func testAuditMainScreens() throws {
        try walk("light", extra: [])
        try walk("dark", extra: ["-appearance", "dark"])
    }
}
