import XCTest
@testable import DengeNoktasi

final class SmokeTests: XCTestCase {
    func testHostAppLaunches() {
        XCTAssertNotNil(Bundle.main.bundleIdentifier)
    }
}
