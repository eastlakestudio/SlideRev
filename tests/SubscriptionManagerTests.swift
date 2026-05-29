import XCTest
@testable import SlideRev

final class SubscriptionManagerTests: XCTestCase {
    
    @MainActor
    func testLegacyVersionParsing() {
        let manager = SubscriptionManager.shared
        
        // Test older versions (should be legacy)
        XCTAssertTrue(manager.isVersionLegacy("1.0.0"))
        XCTAssertTrue(manager.isVersionLegacy("1.0.1"))
        XCTAssertTrue(manager.isVersionLegacy("0.9.9"))
        XCTAssertTrue(manager.isVersionLegacy("1.0"))
        XCTAssertTrue(manager.isVersionLegacy("0.1"))
        XCTAssertTrue(manager.isVersionLegacy("65"))
        XCTAssertTrue(manager.isVersionLegacy("50"))
        
        // Test newer versions (should NOT be legacy)
        XCTAssertFalse(manager.isVersionLegacy("1.0.2"))
        XCTAssertFalse(manager.isVersionLegacy("1.1.0"))
        XCTAssertFalse(manager.isVersionLegacy("2.0.0"))
        XCTAssertFalse(manager.isVersionLegacy("1.0.1.1"))
        XCTAssertFalse(manager.isVersionLegacy("66"))
        XCTAssertFalse(manager.isVersionLegacy("100"))
    }
}
