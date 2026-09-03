import XCTest
@testable import QuickSwitch

final class SelectionCycleTests: XCTestCase {
    func testForwardInvocationInitiallySelectsPreviousMRUWindow() {
        let cycle = SelectionCycle(elements: ["current", "previous", "older"], reverse: false)

        XCTAssertEqual(cycle.selected, "previous")
    }

    func testReverseInvocationInitiallySelectsOldestWindow() {
        let cycle = SelectionCycle(elements: ["current", "previous", "older"], reverse: true)

        XCTAssertEqual(cycle.selected, "older")
    }

    func testAdvancingWrapsInBothDirections() {
        var forward = SelectionCycle(elements: [1, 2, 3], reverse: false)
        forward.advance(reverse: false)
        forward.advance(reverse: false)
        XCTAssertEqual(forward.selected, 1)

        var reverse = SelectionCycle(elements: [1, 2, 3], reverse: true)
        reverse.advance(reverse: true)
        XCTAssertEqual(reverse.selected, 2)
    }

    func testEmptyAndSingleElementCyclesAreSafe() {
        var empty = SelectionCycle<Int>(elements: [], reverse: false)
        empty.advance(reverse: false)
        XCTAssertNil(empty.selected)

        var single = SelectionCycle(elements: [42], reverse: false)
        single.advance(reverse: true)
        XCTAssertEqual(single.selected, 42)
    }
}
