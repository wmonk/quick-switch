import XCTest
@testable import QuickSwitch

final class WindowMRUTests: XCTestCase {
    func testMostRecentlyUsedWindowMovesToFront() {
        var mru = WindowMRU<String>()
        mru.reconcile(with: ["one", "two", "three"])

        mru.recordUse(of: "three")
        mru.recordUse(of: "two")

        XCTAssertEqual(mru.identifiers, ["two", "three", "one"])
    }

    func testReconcilePreservesHistoryAndRemovesClosedWindows() {
        var mru = WindowMRU<String>()
        mru.reconcile(with: ["one", "two", "three"])
        mru.recordUse(of: "two")

        mru.reconcile(with: ["one", "two", "four"])

        XCTAssertEqual(mru.identifiers, ["two", "one", "four"])
    }
}
