import XCTest

/// Xcode's accessibility audit (contrast, hit regions, descriptions, Dynamic Type, clipped text, traits)
/// on the main screens of the real app, in light and dark appearance. Every issue is printed as an
/// `[a11y]` line for the CI log; with AUDIT_STRICT=1 (TEST_RUNNER_AUDIT_STRICT through xcodebuild) any
/// issue that is not listed in `accepted` fails the test.
final class AccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!
    private var found: [String] = []
    private var failing = 0
    private var strict: Bool { ProcessInfo.processInfo.environment["AUDIT_STRICT"] == "1" }

    /// Issues that are deliberate, with the reason. Matched against "<screen> <audit> <identifier>".
    private let accepted: [(pattern: String, reason: String)] = []

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func launch(_ extra: [String]) {
        app = XCUIApplication()
        app.launchArguments = ["-uitest", "-seedLevels", "12"] + extra
        app.launch()
    }

    private static func name(_ type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .contrast: return "contrast"
        case .elementDetection: return "elementDetection"
        case .hitRegion: return "hitRegion"
        case .sufficientElementDescription: return "description"
        case .dynamicType: return "dynamicType"
        case .textClipped: return "textClipped"
        case .trait: return "trait"
        default: return "audit(\(type.rawValue))"
        }
    }

    private func audit(_ screen: String) throws {
        try app.performAccessibilityAudit { issue in
            let type = Self.name(issue.auditType)
            let id = issue.element?.identifier ?? ""
            let label = issue.element?.label ?? ""
            let key = "\(screen) \(type) \(id)"
            let isAccepted = self.accepted.contains { key.range(of: $0.pattern, options: .regularExpression) != nil }
            self.found.append("[a11y] \(isAccepted ? "accepted" : "ISSUE") \(key) '\(label.prefix(60))': \(issue.compactDescription)")
            if !isAccepted { self.failing += 1 }
            return true
        }
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
        for line in found { print(line) }
        print("[a11y] \(found.count) issues, \(failing) not accepted")
        if strict { XCTAssertEqual(failing, 0, "accessibility audit found \(failing) issues; see the [a11y] lines") }
    }
}
