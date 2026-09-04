import AppKit
import CoreGraphics

private func quickSwitchEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    context: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let context else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<KeyboardShortcutController>.fromOpaque(context).takeUnretainedValue()
    return controller.handleEventTap(type: type, event: event)
}

protocol WindowCatalogProviding: AnyObject {
    var frontmostProcessIdentifier: pid_t? { get }
    func orderedWindows(in scope: WindowScope) -> [TrackedWindow]
    func activate(_ window: TrackedWindow)
    func close(_ window: TrackedWindow)
    func quitApplication(owning window: TrackedWindow)
}

enum SwitcherDestructiveAction: Equatable {
    case closeWindow
    case quitApplication
}

protocol SwitcherPanelPresenting: AnyObject {
    func setInteractionHandlers(
        onHover: @escaping (Int) -> Void,
        onClick: @escaping (Int) -> Void
    )
    func show(windows: [TrackedWindow], selectedIndex: Int)
    func updateSelection(_ selectedIndex: Int)
    func hide()
    func confirm(
        _ action: SwitcherDestructiveAction,
        for window: TrackedWindow,
        completion: @escaping (Bool) -> Void
    )
}

extension WindowCatalog: WindowCatalogProviding {}
extension SwitcherPanelController: SwitcherPanelPresenting {}

final class KeyboardShortcutController {
    var onEventTapFailure: (() -> Void)?
    var confirmsDestructiveActions = true

    private enum Shortcut: Int64 {
        case commandTab = 48
        case commandBackquote = 50
    }

    private enum ListNavigationKey: Int64 {
        case moveDown = 38 // J
        case moveUp = 40 // K
        case arrowDown = 125
        case arrowUp = 126

        var movesUp: Bool {
            self == .moveUp || self == .arrowUp
        }
    }

    private enum DestructiveActionKey: Int64 {
        case quit = 12 // Q
        case close = 13 // W

        var action: SwitcherDestructiveAction {
            switch self {
            case .quit:
                return .quitApplication
            case .close:
                return .closeWindow
            }
        }
    }

    private let catalog: WindowCatalogProviding
    private let panelController: SwitcherPanelPresenting
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var selection: SelectionCycle<TrackedWindow>?
    private var activeShortcut: Shortcut?
    private var isConfirmingDestructiveAction = false
    private var consumedDestructiveKeyCode: Int64?

    init(catalog: WindowCatalogProviding, panelController: SwitcherPanelPresenting) {
        self.catalog = catalog
        self.panelController = panelController

        panelController.setInteractionHandlers(
            onHover: { [weak self] index in
                self?.selectWindow(at: index)
            },
            onClick: { [weak self] index in
                self?.selectWindow(at: index)
                self?.commitSelection()
            }
        )
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask = eventMask(for: [
            .keyDown,
            .keyUp,
            .flagsChanged
        ])
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: quickSwitchEventTapCallback,
            userInfo: context
        ) else {
            onEventTapFailure?()
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            onEventTapFailure?()
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        guard SystemCommandTab.disableNativeSwitcher() else {
            stop()
            onEventTapFailure?()
            return false
        }
        return true
    }

    func stop() {
        cancelSelection()

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }

        runLoopSource = nil
        eventTap = nil
        SystemCommandTab.restoreNativeSwitcher()
    }

    func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelSelection()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            if !event.flags.contains(.maskCommand) {
                consumedDestructiveKeyCode = nil
                if selection != nil, !isConfirmingDestructiveAction {
                    commitSelection()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if consumedDestructiveKeyCode == keyCode {
            if type == .keyUp {
                consumedDestructiveKeyCode = nil
            }
            return nil
        }

        if isConfirmingDestructiveAction {
            if DestructiveActionKey(rawValue: keyCode) != nil {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown, keyCode == 53, selection != nil {
            cancelSelection()
            return nil
        }

        if selection != nil, let navigationKey = ListNavigationKey(rawValue: keyCode) {
            if type == .keyDown {
                advanceSelection(reverse: navigationKey.movesUp)
            }
            return nil
        }

        if let actionKey = DestructiveActionKey(rawValue: keyCode),
           selection != nil {
            if type == .keyDown {
                consumedDestructiveKeyCode = keyCode
                requestDestructiveAction(actionKey.action)
            }
            return nil
        }

        guard let shortcut = Shortcut(rawValue: keyCode),
              event.flags.contains(.maskCommand) else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let reverse = event.flags.contains(.maskShift)
            if selection == nil {
                beginSelection(for: shortcut, reverse: reverse)
            } else {
                let movesBackward: Bool
                if shortcut == .commandBackquote {
                    movesBackward = activeShortcut == .commandBackquote ? reverse : !reverse
                } else {
                    movesBackward = reverse
                }
                advanceSelection(reverse: movesBackward)
            }
            return nil
        }

        if type == .keyUp, activeShortcut != nil {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func beginSelection(for shortcut: Shortcut, reverse: Bool) {
        let scope: WindowScope
        switch shortcut {
        case .commandTab:
            scope = .all
        case .commandBackquote:
            guard let processIdentifier = catalog.frontmostProcessIdentifier else { return }
            scope = .application(processIdentifier)
        }

        let windows = catalog.orderedWindows(in: scope)
        guard !windows.isEmpty else { return }

        let newSelection = SelectionCycle(elements: windows, reverse: reverse)
        selection = newSelection
        activeShortcut = shortcut
        panelController.show(
            windows: windows,
            selectedIndex: newSelection.selectedIndex
        )
    }

    private func advanceSelection(reverse: Bool) {
        guard var selection else { return }
        selection.advance(reverse: reverse)
        self.selection = selection
        panelController.updateSelection(selection.selectedIndex)
    }

    private func selectWindow(at index: Int) {
        guard var selection, selection.elements.indices.contains(index) else { return }
        selection.select(index: index)
        self.selection = selection
        panelController.updateSelection(index)
    }

    private func commitSelection() {
        let selectedWindow = selection?.selected
        panelController.hide()
        selection = nil
        activeShortcut = nil

        if let selectedWindow {
            catalog.activate(selectedWindow)
        }
    }

    private func requestDestructiveAction(_ action: SwitcherDestructiveAction) {
        guard let selectedWindow = selection?.selected else { return }

        guard confirmsDestructiveActions else {
            perform(action, on: selectedWindow)
            return
        }

        isConfirmingDestructiveAction = true

        panelController.confirm(action, for: selectedWindow) { [weak self] confirmed in
            guard let self else { return }
            self.isConfirmingDestructiveAction = false
            guard confirmed else { return }

            self.perform(action, on: selectedWindow)
        }
    }

    private func perform(_ action: SwitcherDestructiveAction, on window: TrackedWindow) {
        switch action {
        case .closeWindow:
            catalog.close(window)
        case .quitApplication:
            catalog.quitApplication(owning: window)
        }

        removeAffectedWindows(for: action, selectedWindow: window)
    }

    private func removeAffectedWindows(
        for action: SwitcherDestructiveAction,
        selectedWindow: TrackedWindow
    ) {
        guard var selection else { return }

        selection.removeAll { window in
            switch action {
            case .closeWindow:
                return window.id == selectedWindow.id
            case .quitApplication:
                return window.processIdentifier == selectedWindow.processIdentifier
            }
        }

        guard !selection.elements.isEmpty else {
            panelController.hide()
            self.selection = nil
            activeShortcut = nil
            return
        }

        self.selection = selection
        panelController.show(
            windows: selection.elements,
            selectedIndex: selection.selectedIndex
        )
    }

    private func cancelSelection() {
        panelController.hide()
        selection = nil
        activeShortcut = nil
        consumedDestructiveKeyCode = nil
    }

    private func eventMask(for types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }
    }
}
