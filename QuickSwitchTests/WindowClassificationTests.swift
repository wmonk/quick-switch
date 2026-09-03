import ApplicationServices
import XCTest
@testable import QuickSwitch

final class WindowClassificationTests: XCTestCase {
    func testStandardAndDialogWindowsAreSwitchable() {
        XCTAssertTrue(WindowClassification.isSwitchable(
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String
        ))
        XCTAssertTrue(WindowClassification.isSwitchable(
            role: kAXWindowRole as String,
            subrole: kAXDialogSubrole as String
        ))
    }

    func testFinderDesktopAndChildSurfacesAreNotSwitchable() {
        XCTAssertFalse(WindowClassification.isSwitchable(
            role: kAXScrollAreaRole as String,
            subrole: nil
        ))
        XCTAssertFalse(WindowClassification.isSwitchable(
            role: kAXSheetRole as String,
            subrole: nil
        ))
        XCTAssertFalse(WindowClassification.isSwitchable(
            role: kAXWindowRole as String,
            subrole: kAXFloatingWindowSubrole as String
        ))
    }
}
