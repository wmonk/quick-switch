import AppKit
import ApplicationServices
import CoreGraphics
import XCTest
@testable import QuickSwitch

final class KeyboardShortcutControllerTests: XCTestCase {
    func testCommandTabCyclesAllWindowsAndCommitsOnCommandRelease() {
        let windows = makeWindows(titles: ["Current", "Previous", "Older"])
        let catalog = CatalogRecorder(windows: windows, frontmostProcessIdentifier: 42)
        let panel = PanelRecorder()
        let controller = KeyboardShortcutController(catalog: catalog, panelController: panel)

        XCTAssertNil(controller.handleEventTap(type: .keyDown, event: keyEvent(code: 48)))
        XCTAssertEqual(catalog.requestedScopes, [.all])
        XCTAssertEqual(panel.shownWindowIDs, windows.map(\.id))
        XCTAssertEqual(panel.shownSelection, 1)

        XCTAssertNil(controller.handleEventTap(type: .keyDown, event: keyEvent(code: 48)))
        XCTAssertEqual(panel.updatedSelections, [2])

        let releaseEvent = commandReleaseEvent()
        let passedReleaseEvent = controller.handleEventTap(type: .flagsChanged, event: releaseEvent)
        XCTAssertTrue(passedReleaseEvent != nil)
        XCTAssertEqual(catalog.activatedWindowIDs, [windows[2].id])
        XCTAssertEqual(panel.hideCount, 1)
    }

    func testCommandBackquoteRequestsOnlyFrontmostApplicationWindows() {
        let windows = makeWindows(titles: ["Current", "Previous"])
        let catalog = CatalogRecorder(windows: windows, frontmostProcessIdentifier: 314)
        let panel = PanelRecorder()
        let controller = KeyboardShortcutController(catalog: catalog, panelController: panel)

        XCTAssertNil(controller.handleEventTap(type: .keyDown, event: keyEvent(code: 50)))
        XCTAssertEqual(catalog.requestedScopes, [.application(314)])
        XCTAssertEqual(panel.shownWindowIDs, windows.map(\.id))
        XCTAssertEqual(panel.shownSelection, 1)

        _ = controller.handleEventTap(type: .flagsChanged, event: commandReleaseEvent())
        XCTAssertEqual(catalog.activatedWindowIDs, [windows[1].id])
    }

    func testRepeatedBackquoteMovesForwardWithinCurrentApplicationList() {
        let windows = makeWindows(titles: ["Current", "Previous", "Older"])
        let catalog = CatalogRecorder(windows: windows, frontmostProcessIdentifier: 314)
        let panel = PanelRecorder()
        let controller = KeyboardShortcutController(catalog: catalog, panelController: panel)

        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 50))
        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 50))

        XCTAssertEqual(catalog.requestedScopes, [.application(314)])
        XCTAssertEqual(panel.shownSelection, 1)
        XCTAssertEqual(panel.updatedSelections, [2])
    }

    func testTabMovesForwardAndBackquoteMovesBackwardWithinOpenList() {
        let windows = makeWindows(titles: ["Current", "Previous", "Older"])
        let catalog = CatalogRecorder(windows: windows, frontmostProcessIdentifier: 42)
        let panel = PanelRecorder()
        let controller = KeyboardShortcutController(catalog: catalog, panelController: panel)

        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 48))
        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 48))
        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 50))

        XCTAssertEqual(panel.shownSelection, 1)
        XCTAssertEqual(panel.updatedSelections, [2, 1])
        XCTAssertEqual(catalog.requestedScopes, [.all])
    }

    func testJAndKMoveDownAndUpWithinOpenList() {
        let windows = makeWindows(titles: ["Current", "Previous", "Older"])
        let catalog = CatalogRecorder(windows: windows, frontmostProcessIdentifier: 42)
        let panel = PanelRecorder()
        let controller = KeyboardShortcutController(catalog: catalog, panelController: panel)

        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 48))
        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 38))
        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 40))

        XCTAssertEqual(panel.shownSelection, 1)
        XCTAssertEqual(panel.updatedSelections, [2, 1])
    }

    func testDownAndUpArrowsMoveWithinOpenList() {
        let windows = makeWindows(titles: ["Current", "Previous", "Older"])
        let catalog = CatalogRecorder(windows: windows, frontmostProcessIdentifier: 42)
        let panel = PanelRecorder()
        let controller = KeyboardShortcutController(catalog: catalog, panelController: panel)

        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 48))
        XCTAssertNil(controller.handleEventTap(type: .keyDown, event: keyEvent(code: 125)))
        XCTAssertNil(controller.handleEventTap(type: .keyUp, event: keyEvent(code: 125, keyDown: false)))
        XCTAssertNil(controller.handleEventTap(type: .keyDown, event: keyEvent(code: 126)))
        XCTAssertNil(controller.handleEventTap(type: .keyUp, event: keyEvent(code: 126, keyDown: false)))

        XCTAssertEqual(panel.shownSelection, 1)
        XCTAssertEqual(panel.updatedSelections, [2, 1])
    }

    func testMouseHoverSelectsAndClickActivatesAWindow() {
        let windows = makeWindows(titles: ["Current", "Previous", "Older"])
        let catalog = CatalogRecorder(windows: windows, frontmostProcessIdentifier: 42)
        let panel = PanelRecorder()
        let controller = KeyboardShortcutController(catalog: catalog, panelController: panel)

        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 48))
        panel.hover(row: 0)
        XCTAssertEqual(panel.updatedSelections, [0])

        panel.click(row: 2)
        XCTAssertEqual(panel.updatedSelections, [0, 2])
        XCTAssertEqual(catalog.activatedWindowIDs, [windows[2].id])
        XCTAssertEqual(panel.hideCount, 1)
    }

    func testCommandWAndQAreConsumedWhileSwitcherIsOpen() {
        let windows = makeWindows(titles: ["Current", "Previous", "Older"])
        let catalog = CatalogRecorder(windows: windows, frontmostProcessIdentifier: 42)
        let panel = PanelRecorder()
        let controller = KeyboardShortcutController(catalog: catalog, panelController: panel)

        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 48))

        let wDown = keyEvent(code: 13)
        let wUp = keyEvent(code: 13, keyDown: false)
        let qDown = keyEvent(code: 12)
        let qUp = keyEvent(code: 12, keyDown: false)

        XCTAssertNil(controller.handleEventTap(type: .keyDown, event: wDown))
        XCTAssertNil(controller.handleEventTap(type: .keyUp, event: wUp))
        XCTAssertNil(controller.handleEventTap(type: .keyDown, event: qDown))
        XCTAssertNil(controller.handleEventTap(type: .keyUp, event: qUp))
        XCTAssertTrue(panel.updatedSelections.isEmpty)
        XCTAssertEqual(panel.hideCount, 0)
        XCTAssertTrue(catalog.activatedWindowIDs.isEmpty)
    }

    func testCommandWAndQPassThroughWhileSwitcherIsClosed() {
        let catalog = CatalogRecorder(windows: [], frontmostProcessIdentifier: 42)
        let panel = PanelRecorder()
        let controller = KeyboardShortcutController(catalog: catalog, panelController: panel)
        let wDown = keyEvent(code: 13)
        let qDown = keyEvent(code: 12)

        XCTAssertNotNil(controller.handleEventTap(type: .keyDown, event: wDown))
        XCTAssertNotNil(controller.handleEventTap(type: .keyDown, event: qDown))
    }

    func testEscapeCancelsWithoutActivatingAWindow() {
        let windows = makeWindows(titles: ["Current", "Previous"])
        let catalog = CatalogRecorder(windows: windows, frontmostProcessIdentifier: 42)
        let panel = PanelRecorder()
        let controller = KeyboardShortcutController(catalog: catalog, panelController: panel)

        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 48))
        XCTAssertNil(controller.handleEventTap(type: .keyDown, event: keyEvent(code: 53)))

        XCTAssertTrue(catalog.activatedWindowIDs.isEmpty)
        XCTAssertEqual(panel.hideCount, 1)
    }

    private func keyEvent(code: CGKeyCode, keyDown: Bool = true) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: keyDown)!
        event.flags = .maskCommand
        return event
    }

    private func commandReleaseEvent() -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: false)!
        event.flags = []
        return event
    }

    private func makeWindows(titles: [String]) -> [TrackedWindow] {
        let application = NSRunningApplication.current
        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        let element = AXUIElementCreateApplication(processIdentifier)

        return titles.map { title in
            TrackedWindow(
                element: element,
                processIdentifier: processIdentifier,
                application: application,
                applicationName: "Test App",
                title: title,
                isMinimized: false
            )
        }
    }
}

private final class CatalogRecorder: WindowCatalogProviding {
    let frontmostProcessIdentifier: pid_t?
    private let windows: [TrackedWindow]
    private(set) var requestedScopes: [WindowScope] = []
    private(set) var activatedWindowIDs: [UUID] = []

    init(windows: [TrackedWindow], frontmostProcessIdentifier: pid_t?) {
        self.windows = windows
        self.frontmostProcessIdentifier = frontmostProcessIdentifier
    }

    func orderedWindows(in scope: WindowScope) -> [TrackedWindow] {
        requestedScopes.append(scope)
        return windows
    }

    func activate(_ window: TrackedWindow) {
        activatedWindowIDs.append(window.id)
    }
}

private final class PanelRecorder: SwitcherPanelPresenting {
    private(set) var shownWindowIDs: [UUID] = []
    private(set) var shownSelection: Int?
    private(set) var updatedSelections: [Int] = []
    private(set) var hideCount = 0
    private var onHover: ((Int) -> Void)?
    private var onClick: ((Int) -> Void)?

    func setInteractionHandlers(
        onHover: @escaping (Int) -> Void,
        onClick: @escaping (Int) -> Void
    ) {
        self.onHover = onHover
        self.onClick = onClick
    }

    func hover(row: Int) {
        onHover?(row)
    }

    func click(row: Int) {
        onClick?(row)
    }

    func show(windows: [TrackedWindow], selectedIndex: Int) {
        shownWindowIDs = windows.map(\.id)
        shownSelection = selectedIndex
    }

    func updateSelection(_ selectedIndex: Int) {
        updatedSelections.append(selectedIndex)
    }

    func hide() {
        hideCount += 1
    }
}
