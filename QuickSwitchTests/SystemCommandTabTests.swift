import XCTest
@testable import QuickSwitch

final class SystemCommandTabTests: XCTestCase {
    func testRequiredTakeoverSymbolExistsOnCurrentMacOS() {
        XCTAssertTrue(
            SystemCommandTab.isAvailable,
            "This macOS version no longer exposes the symbolic-hotkey control needed to replace Command-Tab"
        )
    }
}
