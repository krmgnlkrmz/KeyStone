import XCTest

/// Collects audit issues. The issue handler is sent to XCTest, so under Swift 6 it may only capture
/// Sendable state: this box, not the test case.
private final class AuditLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func add(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

/// Xcode's accessibility audit (contrast, hit regions, descriptions, Dynamic Type, clipped text, traits)
/// on the main screens of the real app, in light and dark appearance. Every issue is printed as an
/// `[a11y]` line with the element it concerns. With AUDIT_STRICT=1 (TEST_RUNNER_AUDIT_STRICT through
/// xcodebuild) any issue not listed in `accepted` fails the test.
final class AccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!
    private let log = AuditLog()

    /// Deliberate exceptions, matched (regex) against the printed line, each with its reason.
    private let accepted: [(pattern: String, reason: String)] = [
        (#"^\[a11y\] \w+/game \| Dynamic Type font sizes are unsupported"#,
         "the game HUD and bottom bar keep fixed sizes by design, so the play area keeps its room"),
        (#"\| type 48 id '' label 'AD' frame \(\d+\.0, \d+\.0, [23]\d\d\.0"#,
         "the empty banner slot's placeholder: decorative, hidden from VoiceOver, replaced by the ad"),
        (#"^\[a11y\] \w+/map \| Contrast failed \| type 48 id '' label '10' "#,
         "level 10's number sits half under the banner inset at the map's initial scroll position"),
        (#"\| Dynamic Type font sizes are partially unsupported \|"#,
         "the text does scale (accessibility-size screenshots on every device); the audit calls text in "
            + "scroll containers, forms and system bar buttons 'partial'"),
        (#"^\[a11y\] \w+/settings \| Contrast failed \| type 48 id '' label 'Remove Ads' "#,
         "the purchase button's element includes its icon tile: title ≥ 14:1, brass glyph on its tint 4.9:1 (light) "
            + "and 6:1 (dark), each computed from the palette"),
        (#"\| (Contrast (failed|nearly passed)|Text clipped) \| no element$"#,
         "the audit could not attribute the issue to an element; the screens are checked in the screenshots"),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func launch(_ extra: [String]) {
        app = XCUIApplication()
        app.launchArguments = ["-uitest", "-seedLevels", "12"] + extra
        app.launch()
    }

    private func audit(_ screen: String) throws {
        let log = self.log
        try app.performAccessibilityAudit { issue in
            let what = issue.element.map {
                "type \($0.elementType.rawValue) id '\($0.identifier)' label '\($0.label.prefix(50))' frame \($0.frame.integral)"
            } ?? "no element"
            log.add("[a11y] \(screen) | \(issue.compactDescription) | \(what)")
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
        var open = 0
        for line in log.all {
            let ok = accepted.contains { line.range(of: $0.pattern, options: .regularExpression) != nil }
            if !ok { open += 1 }
            print(ok ? line.replacingOccurrences(of: "[a11y]", with: "[a11y] (accepted)") : line)
        }
        print("[a11y] \(log.all.count) issues, \(open) not accepted")
        if ProcessInfo.processInfo.environment["AUDIT_STRICT"] == "1" {
            XCTAssertEqual(open, 0, "accessibility audit: \(open) issues; see the [a11y] lines")
        }
    }
}
