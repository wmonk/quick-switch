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

    func testWConfirmsBeforeClosingSelectedWindow() {
        let windows = makeWindows(titles: ["Current", "Previous", "Older"])
        let catalog = CatalogRecorder(windows: windows, frontmostProcessIdentifier: 42)
        let panel = PanelRecorder()
        let controller = KeyboardShortcutController(catalog: catalog, panelController: panel)

        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 48))

        XCTAssertNil(controller.handleEventTap(type: .keyDown, event: keyEvent(code: 13)))
        XCTAssertNil(controller.handleEventTap(type: .keyUp, event: keyEvent(code: 13, keyDown: false)))
        XCTAssertEqual(
            panel.confirmationRequests,
            [ConfirmationRequest(action: .closeWindow, windowID: windows[1].id)]
        )
        XCTAssertEqual(panel.hideCount, 0)
        XCTAssertTrue(catalog.closedWindowIDs.isEmpty)

        _ = controller.handleEventTap(type: .flagsChanged, event: commandReleaseEvent())
        XCTAssertTrue(catalog.activatedWindowIDs.isEmpty)

        panel.respondToConfirmation(confirmed: true)
        XCTAssertEqual(catalog.closedWindowIDs, [windows[1].id])
        XCTAssertTrue(catalog.quitApplicationWindowIDs.isEmpty)
        XCTAssertEqual(panel.shownWindowIDs, [windows[0].id, windows[2].id])
        XCTAssertEqual(panel.shownSelection, 1)
        XCTAssertEqual(panel.hideCount, 0)
    }

    func testQConfirmsBeforeQuittingSelectedApplication() {
        let windows = makeWindows(
            titles: ["Current", "Previous", "Same App", "Older"],
            processIdentifiers: [100, 200, 200, 300]
        )
        let catalog = CatalogRecorder(windows: windows, frontmostProcessIdentifier: 42)
        let panel = PanelRecorder()
        let controller = KeyboardShortcutController(catalog: catalog, panelController: panel)

        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 48))

        XCTAssertNil(controller.handleEventTap(type: .keyDown, event: keyEvent(code: 12)))
        XCTAssertNil(controller.handleEventTap(type: .keyUp, event: keyEvent(code: 12, keyDown: false)))
        XCTAssertEqual(
            panel.confirmationRequests,
            [ConfirmationRequest(action: .quitApplication, windowID: windows[1].id)]
        )
        XCTAssertTrue(catalog.quitApplicationWindowIDs.isEmpty)

        panel.respondToConfirmation(confirmed: true)
        XCTAssertEqual(catalog.quitApplicationWindowIDs, [windows[1].id])
        XCTAssertTrue(catalog.closedWindowIDs.isEmpty)
        XCTAssertEqual(panel.shownWindowIDs, [windows[0].id, windows[3].id])
        XCTAssertEqual(panel.shownSelection, 1)
        XCTAssertEqual(panel.hideCount, 0)
    }

    func testCancellingDestructiveConfirmationLeavesWindowAndApplicationOpen() {
        let windows = makeWindows(titles: ["Current", "Previous"])
        let catalog = CatalogRecorder(windows: windows, frontmostProcessIdentifier: 42)
        let panel = PanelRecorder()
        let controller = KeyboardShortcutController(catalog: catalog, panelController: panel)

        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 48))
        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 13))
        panel.respondToConfirmation(confirmed: false)

        XCTAssertTrue(catalog.activatedWindowIDs.isEmpty)
        XCTAssertTrue(catalog.closedWindowIDs.isEmpty)
        XCTAssertTrue(catalog.quitApplicationWindowIDs.isEmpty)
        XCTAssertEqual(panel.shownWindowIDs, windows.map(\.id))
        XCTAssertEqual(panel.shownSelection, 1)
        XCTAssertEqual(panel.hideCount, 0)
    }

    func testWAndQRemainConsumedWhileConfirmationIsOpen() {
        let windows = makeWindows(titles: ["Current", "Previous"])
        let catalog = CatalogRecorder(windows: windows, frontmostProcessIdentifier: 42)
        let panel = PanelRecorder()
        let controller = KeyboardShortcutController(catalog: catalog, panelController: panel)

        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 48))
        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 13))

        XCTAssertNil(controller.handleEventTap(type: .keyDown, event: keyEvent(code: 13)))
        XCTAssertNil(controller.handleEventTap(type: .keyUp, event: keyEvent(code: 13, keyDown: false)))
        XCTAssertNil(controller.handleEventTap(type: .keyDown, event: keyEvent(code: 12)))
        XCTAssertNil(controller.handleEventTap(type: .keyUp, event: keyEvent(code: 12, keyDown: false)))
        XCTAssertEqual(panel.confirmationRequests.count, 1)
    }

    func testWClosesSelectedWindowImmediatelyWhenConfirmationIsDisabled() {
        let windows = makeWindows(titles: ["Current", "Previous"])
        let catalog = CatalogRecorder(windows: windows, frontmostProcessIdentifier: 42)
        let panel = PanelRecorder()
        let controller = KeyboardShortcutController(catalog: catalog, panelController: panel)
        controller.confirmsDestructiveActions = false

        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 48))

        XCTAssertNil(controller.handleEventTap(type: .keyDown, event: keyEvent(code: 13)))
        XCTAssertNil(controller.handleEventTap(type: .keyUp, event: keyEvent(code: 13, keyDown: false)))
        XCTAssertTrue(panel.confirmationRequests.isEmpty)
        XCTAssertEqual(catalog.closedWindowIDs, [windows[1].id])
        XCTAssertTrue(catalog.quitApplicationWindowIDs.isEmpty)
        XCTAssertEqual(panel.shownWindowIDs, [windows[0].id])
        XCTAssertEqual(panel.shownSelection, 0)
        XCTAssertEqual(panel.hideCount, 0)

        _ = controller.handleEventTap(type: .flagsChanged, event: commandReleaseEvent())
        XCTAssertEqual(catalog.activatedWindowIDs, [windows[0].id])
        XCTAssertEqual(panel.hideCount, 1)
    }

    func testQQuitsSelectedApplicationImmediatelyWhenConfirmationIsDisabled() {
        let windows = makeWindows(
            titles: ["Current", "Previous", "Same App", "Older"],
            processIdentifiers: [100, 200, 200, 300]
        )
        let catalog = CatalogRecorder(windows: windows, frontmostProcessIdentifier: 42)
        let panel = PanelRecorder()
        let controller = KeyboardShortcutController(catalog: catalog, panelController: panel)
        controller.confirmsDestructiveActions = false

        _ = controller.handleEventTap(type: .keyDown, event: keyEvent(code: 48))

        XCTAssertNil(controller.handleEventTap(type: .keyDown, event: keyEvent(code: 12)))
        XCTAssertNil(controller.handleEventTap(type: .keyUp, event: keyEvent(code: 12, keyDown: false)))
        XCTAssertTrue(panel.confirmationRequests.isEmpty)
        XCTAssertEqual(catalog.quitApplicationWindowIDs, [windows[1].id])
        XCTAssertTrue(catalog.closedWindowIDs.isEmpty)
        XCTAssertEqual(panel.shownWindowIDs, [windows[0].id, windows[3].id])
        XCTAssertEqual(panel.shownSelection, 1)
        XCTAssertEqual(panel.hideCount, 0)
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

    private func makeWindows(
        titles: [String],
        processIdentifiers: [pid_t]? = nil
    ) -> [TrackedWindow] {
        let application = NSRunningApplication.current
        let defaultProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        precondition(processIdentifiers == nil || processIdentifiers?.count == titles.count)

        return titles.enumerated().map { index, title in
            let processIdentifier = processIdentifiers?[index] ?? defaultProcessIdentifier
            return TrackedWindow(
                element: AXUIElementCreateApplication(processIdentifier),
                processIdentifier: processIdentifier,
                application: application,
                applicationName: "Test App \(processIdentifier)",
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
    private(set) var closedWindowIDs: [UUID] = []
    private(set) var quitApplicationWindowIDs: [UUID] = []

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

    func close(_ window: TrackedWindow) {
        closedWindowIDs.append(window.id)
    }

    func quitApplication(owning window: TrackedWindow) {
        quitApplicationWindowIDs.append(window.id)
    }
}

private struct ConfirmationRequest: Equatable {
    let action: SwitcherDestructiveAction
    let windowID: UUID
}

private final class PanelRecorder: SwitcherPanelPresenting {
    private(set) var shownWindowIDs: [UUID] = []
    private(set) var shownSelection: Int?
    private(set) var updatedSelections: [Int] = []
    private(set) var hideCount = 0
    private(set) var confirmationRequests: [ConfirmationRequest] = []
    private var onHover: ((Int) -> Void)?
    private var onClick: ((Int) -> Void)?
    private var confirmationCompletion: ((Bool) -> Void)?

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

    func confirm(
        _ action: SwitcherDestructiveAction,
        for window: TrackedWindow,
        completion: @escaping (Bool) -> Void
    ) {
        confirmationRequests.append(ConfirmationRequest(action: action, windowID: window.id))
        confirmationCompletion = completion
    }

    func respondToConfirmation(confirmed: Bool) {
        let completion = confirmationCompletion
        confirmationCompletion = nil
        completion?(confirmed)
    }
}
