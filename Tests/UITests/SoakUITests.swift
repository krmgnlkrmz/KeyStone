import XCTest

/// Release-gate soak runs (§11.16) against the real app: curated levels played back to back from their
/// verified solutions, and a long random-tap session. Skipped unless SOAK=1 (TEST_RUNNER_SOAK=1 through
/// xcodebuild); CI runs them for a `[forge:soak]` commit.
final class SoakUITests: XCTestCase {
    private var app: XCUIApplication!
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(env["SOAK"] == "1", "soak tests run only with SOAK=1")
    }

    private struct Solution {
        let index: Int
        let path: [String]
    }

    /// Verified solution paths of the shipped curated levels, in play order (bundled with this target).
    private func solutions() throws -> [Solution] {
        let root = try XCTUnwrap(Bundle(for: SoakUITests.self).url(forResource: "Levels", withExtension: nil))
        let dir = root.appendingPathComponent("curated")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return try files.compactMap { url -> Solution? in
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            guard let index = object?["index"] as? Int,
                  let annotation = object?["annotation"] as? [String: Any],
                  let path = annotation["solutionPath"] as? [String] else { return nil }
            return Solution(index: index, path: path)
        }
        .sorted { $0.index < $1.index }
    }

    private func waitGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// Screenshot (attached, and with SCREENSHOT_DIR written next to the screenshots) plus the game's
    /// tap targets, any on-screen text and the last strut request, printed for the CI log.
    private func evidence(_ name: String) {
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let event = supportEvent
        print("[soak] \(name): last strut request: \(event.exists ? event.label : "(not shown)")")
        let marked = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'support.' OR identifier BEGINSWITH 'piece.'"))
        for element in marked.allElementsBoundByIndex.prefix(40) {
            print("[soak]   \(element.identifier) frame \(element.frame) hittable \(element.isHittable)")
        }
        for text in app.staticTexts.allElementsBoundByIndex.prefix(30) where !text.label.isEmpty {
            print("[soak]   text: \(text.label)")
        }
        if let dir = env["SCREENSHOT_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            try? image.pngRepresentation.write(to: url)
        }
    }

    /// UI-test-only element in the game screen: what the last strut request did ("placed +sup@-112", "refused …").
    private var supportEvent: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "debug.supportEvent").firstMatch
    }

    private func button(_ format: String, _ text: String) -> XCUIElement {
        app.buttons.containing(NSPredicate(format: format, text)).firstMatch
    }

    /// Plays the first N curated levels in a row (default 50), each with its verified solution, moving on
    /// with "Next Level". Every level must be won and the app must never leave the foreground.
    func testPlayFiftyLevelsInARow() throws {
        let count = Int(env["SOAK_LEVELS"] ?? "") ?? 50
        let all = try solutions()
        XCTAssertGreaterThanOrEqual(all.count, count, "only \(all.count) annotated curated levels")

        app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
        let levels = button("label CONTAINS[c] %@", "Levels")
        XCTAssertTrue(levels.waitForExistence(timeout: 15), "main menu did not appear")
        levels.tap()
        let first = button("label BEGINSWITH %@", "Level 1 ")
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.tap()

        let started = Date()
        for (n, level) in all.prefix(count).enumerated() {
            for token in level.path {
                let element: XCUIElement
                if token.hasPrefix("+sup@") {
                    element = app.descendants(matching: .any).matching(identifier: "support.\(token)").firstMatch
                    XCTAssertTrue(element.waitForExistence(timeout: 15), "level \(level.index): support spot \(token) not offered")
                    element.tap()
                } else {
                    element = app.descendants(matching: .any).matching(identifier: "piece.\(token)").firstMatch
                    XCTAssertTrue(element.waitForExistence(timeout: 15), "level \(level.index): piece \(token) not found")
                    element.tap()   // select
                    element.tap()   // remove
                }
                // The overlay hides while the move is evaluated; the next element appears once it settles.
                if !waitGone(element, timeout: 10) {
                    evidence("soak-fail-L\(level.index)-\(token)")
                    XCTFail("level \(level.index): move \(token) was not taken (frame \(element.frame), hittable \(element.isHittable))")
                    return
                }
                if token.hasPrefix("+sup@") {
                    // Neighbouring spots sit a few points apart; the tap must have placed this one, not a neighbour.
                    XCTAssertEqual(supportEvent.label, "placed \(token)", "level \(level.index): the tap placed another strut")
                }
                XCTAssertEqual(app.state, .runningForeground)
            }
            let next = button("label CONTAINS[c] %@", "Next Level")
            XCTAssertTrue(next.waitForExistence(timeout: 20), "level \(level.index) was not won with its verified solution")
            print("[soak] level \(level.index) won (\(n + 1)/\(count), \(Int(Date().timeIntervalSince(started))) s)")
            if n + 1 < count { next.tap() }
        }
    }

    /// Random taps for SOAK_MINUTES (default 30), starting in a level. Whatever screen the taps reach, the
    /// app must not crash; if a tap sends it to the background (a system sheet, a link), it is brought back.
    func testRandomTapsForThirtyMinutes() throws {
        let minutes = Double(env["SOAK_MINUTES"] ?? "") ?? 30
        app = XCUIApplication()
        app.launchArguments = ["-uitest", "-seedLevels", "20"]
        app.launch()
        let levels = button("label CONTAINS[c] %@", "Levels")
        XCTAssertTrue(levels.waitForExistence(timeout: 15))
        levels.tap()
        button("label BEGINSWITH %@", "Level 5 ").tap()

        var rng = SystemRandomNumberGenerator()
        let end = Date().addingTimeInterval(minutes * 60)
        var taps = 0
        while Date() < end {
            let window = app.windows.firstMatch
            let point = window.coordinate(withNormalizedOffset: CGVector(dx: Double.random(in: 0.05...0.95, using: &rng),
                                                                         dy: Double.random(in: 0.10...0.92, using: &rng)))
            point.tap()
            taps += 1
            if taps % 25 == 0 {
                XCTAssertNotEqual(app.state, .notRunning, "app crashed after \(taps) taps")
                if app.state != .runningForeground { app.activate() }
            }
        }
        XCTAssertNotEqual(app.state, .notRunning)
        print("[soak] \(taps) random taps in \(Int(minutes)) min without a crash")
    }
}
