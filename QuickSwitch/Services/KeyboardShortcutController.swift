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
}

protocol SwitcherPanelPresenting: AnyObject {
    func setInteractionHandlers(
        onHover: @escaping (Int) -> Void,
        onClick: @escaping (Int) -> Void
    )
    func show(windows: [TrackedWindow], selectedIndex: Int)
    func updateSelection(_ selectedIndex: Int)
    func hide()
}

extension WindowCatalog: WindowCatalogProviding {}
extension SwitcherPanelController: SwitcherPanelPresenting {}

final class KeyboardShortcutController {
    var onEventTapFailure: (() -> Void)?

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

    private enum SuppressedWhileSwitchingKey: Int64 {
        case quit = 12 // Q
        case close = 13 // W
    }

    private let catalog: WindowCatalogProviding
    private let panelController: SwitcherPanelPresenting
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var selection: SelectionCycle<TrackedWindow>?
    private var activeShortcut: Shortcut?

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
            if selection != nil && !event.flags.contains(.maskCommand) {
                commitSelection()
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

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

        if selection != nil, SuppressedWhileSwitchingKey(rawValue: keyCode) != nil {
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

    private func cancelSelection() {
        panelController.hide()
        selection = nil
        activeShortcut = nil
    }

    private func eventMask(for types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }
    }
}
