import AppKit
import ApplicationServices

private func catalogObserverCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let catalog = Unmanaged<WindowCatalog>.fromOpaque(context).takeUnretainedValue()
    catalog.receiveAccessibilityNotification(element: element, notification: notification)
}

private struct DiscoveredWindow {
    let element: AXUIElement
    let processIdentifier: pid_t
    let application: NSRunningApplication
    let applicationName: String
    let title: String
    let isMinimized: Bool
}

private struct WindowDiscovery {
    var windows: [DiscoveredWindow] = []
    var scannedProcessIdentifiers = Set<pid_t>()
}

/// Tracks top-level windows exposed by macOS Accessibility and maintains the
/// MRU order independently of the order returned by individual applications.
final class WindowCatalog {
    private(set) var windows: [TrackedWindow] = []
    private var mru = WindowMRU<UUID>()
    private var orderedWindowCache: [TrackedWindow]?
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private var refreshTimer: Timer?
    private var isStarted = false
    private var isRefreshing = false
    private var backgroundRefreshInProgress = false
    private var backgroundRefreshPending = false
    private var focusRequestGeneration = 0
    private var hasSeededInitialOrder = false
    private let discoveryQueue = DispatchQueue(
        label: "com.willmonk.QuickSwitch.discovery",
        qos: .utility
    )
    private let focusQueue = DispatchQueue(
        label: "com.willmonk.QuickSwitch.focus",
        qos: .userInitiated
    )
    private let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier

    var frontmostProcessIdentifier: pid_t? {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return pid == ownProcessIdentifier ? nil : pid
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleBackgroundRefresh()
            },
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else {
                    self?.scheduleBackgroundRefresh()
                    return
                }
                self?.removeApplication(processIdentifier: application.processIdentifier)
            },
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else {
                    return
                }
                self?.recordFocusedWindow(for: application.processIdentifier)
            }
        ]

        // Seed synchronously once so Command-Tab is ready immediately after
        // launch. All later Accessibility scans happen away from the UI loop.
        refresh()

        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            self?.scheduleBackgroundRefresh()
        }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stop() {
        isStarted = false
        focusRequestGeneration &+= 1
        refreshTimer?.invalidate()
        refreshTimer = nil
        backgroundRefreshPending = false

        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach(center.removeObserver)
        workspaceTokens.removeAll()

        for observer in observers.values {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observers.removeAll()
        windows.removeAll(keepingCapacity: false)
        orderedWindowCache = nil
        mru.reconcile(with: [])
    }

    func orderedWindows(in scope: WindowScope) -> [TrackedWindow] {
        let ordered: [TrackedWindow]
        if let orderedWindowCache {
            ordered = orderedWindowCache
        } else {
            let byID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
            ordered = mru.identifiers.compactMap { byID[$0] }
            orderedWindowCache = ordered
        }

        switch scope {
        case .all:
            return ordered
        case let .application(processIdentifier):
            return ordered.filter { $0.processIdentifier == processIdentifier }
        }
    }

    /// Performs the one synchronous launch/diagnostic scan. Runtime safety
    /// scans use `scheduleBackgroundRefresh()` instead.
    func refresh() {
        guard AccessibilityPermission.isGranted, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let applications = eligibleApplications()
        applyFullDiscovery(
            Self.discoverWindows(in: applications),
            applications: applications
        )
    }

    func activate(_ window: TrackedWindow) {
        guard windows.contains(where: { $0.id == window.id }) else {
            scheduleBackgroundRefresh()
            return
        }

        recordUse(of: window)

        let element = window.element
        let application = window.application
        let wasMinimized = window.isMinimized
        if application.isHidden {
            application.unhide()
        }
        application.activate()

        focusQueue.async {
            AXUIElementSetMessagingTimeout(element, 0.1)
            if wasMinimized {
                AXUIElementSetAttributeValue(
                    element,
                    kAXMinimizedAttribute as CFString,
                    kCFBooleanFalse
                )
            }
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(
                element,
                kAXMainAttribute as CFString,
                kCFBooleanTrue
            )
            AXUIElementSetAttributeValue(
                element,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
        }
    }

    func close(_ window: TrackedWindow) {
        guard windows.contains(where: { $0.id == window.id }) else {
            scheduleBackgroundRefresh()
            return
        }

        let element = window.element
        focusQueue.async { [weak self] in
            AXUIElementSetMessagingTimeout(element, 0.1)
            guard let closeButton: AXUIElement = AXHelpers.value(
                kAXCloseButtonAttribute as CFString,
                from: element
            ) else {
                DispatchQueue.main.async {
                    self?.scheduleBackgroundRefresh()
                }
                return
            }

            AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
            DispatchQueue.main.async {
                self?.scheduleBackgroundRefresh()
            }
        }
    }

    func quitApplication(owning window: TrackedWindow) {
        guard windows.contains(where: { $0.id == window.id }),
              window.processIdentifier != ownProcessIdentifier else {
            scheduleBackgroundRefresh()
            return
        }

        window.application.terminate()
    }

    func receiveAccessibilityNotification(element: AXUIElement, notification: CFString) {
        let notificationName = notification as String

        switch notificationName {
        case kAXFocusedWindowChangedNotification,
             kAXMainWindowChangedNotification:
            let processIdentifier = processIdentifier(of: element)
            recordFocusedWindow(for: processIdentifier, candidate: element)

        case kAXTitleChangedNotification:
            guard existingWindow(for: element) != nil else {
                scheduleBackgroundRefresh()
                return
            }
            updateTitle(for: element)

        case kAXWindowMiniaturizedNotification:
            guard let tracked = existingWindow(for: element) else {
                scheduleBackgroundRefresh()
                return
            }
            tracked.isMinimized = true

        case kAXWindowDeminiaturizedNotification:
            guard let tracked = existingWindow(for: element) else {
                scheduleBackgroundRefresh()
                return
            }
            tracked.isMinimized = false

        case kAXUIElementDestroyedNotification:
            removeWindow(element)

        case kAXWindowCreatedNotification:
            scheduleBackgroundRefresh()

        default:
            break
        }
    }

    private func scheduleBackgroundRefresh() {
        guard isStarted, AccessibilityPermission.isGranted else { return }
        guard !backgroundRefreshInProgress else {
            backgroundRefreshPending = true
            return
        }

        backgroundRefreshInProgress = true
        let applications = eligibleApplications()
        discoveryQueue.async { [weak self] in
            let discovered = Self.discoverWindows(in: applications)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.backgroundRefreshInProgress = false

                if self.isStarted {
                    self.applyFullDiscovery(discovered, applications: applications)
                }

                if self.backgroundRefreshPending {
                    self.backgroundRefreshPending = false
                    self.scheduleBackgroundRefresh()
                }
            }
        }
    }

    private static func discoverWindows(
        in applications: [NSRunningApplication]
    ) -> WindowDiscovery {
        var discovery = WindowDiscovery()
        discovery.windows.reserveCapacity(applications.count * 2)

        for application in applications {
            autoreleasepool {
                let processIdentifier = application.processIdentifier
                let applicationElement = AXUIElementCreateApplication(processIdentifier)
                AXUIElementSetMessagingTimeout(applicationElement, 0.1)
                let applicationName = application.localizedName ?? "Application"
                guard let snapshots = AXHelpers.windows(for: applicationElement) else { return }
                discovery.scannedProcessIdentifiers.insert(processIdentifier)

                for snapshot in snapshots {
                    discovery.windows.append(
                        DiscoveredWindow(
                            element: snapshot.element,
                            processIdentifier: processIdentifier,
                            application: application,
                            applicationName: applicationName,
                            title: snapshot.title,
                            isMinimized: snapshot.isMinimized
                        )
                    )
                }
            }
        }
        return discovery
    }

    private func applyFullDiscovery(
        _ discovery: WindowDiscovery,
        applications: [NSRunningApplication]
    ) {
        let livePIDs = Set(applications.map(\.processIdentifier))
        removeObserversForTerminatedApplications(livePIDs: livePIDs)

        var newlyObservedPIDs = Set<pid_t>()
        for application in applications {
            let processIdentifier = application.processIdentifier
            let applicationElement = AXUIElementCreateApplication(processIdentifier)
            AXUIElementSetMessagingTimeout(applicationElement, 0.1)
            if installObserverIfNeeded(
                for: applicationElement,
                processIdentifier: processIdentifier
            ) {
                newlyObservedPIDs.insert(processIdentifier)
            }
        }

        var existingByPID = Dictionary(grouping: windows, by: \.processIdentifier)
        var liveWindows: [TrackedWindow] = []
        liveWindows.reserveCapacity(discovery.windows.count)

        for item in discovery.windows {
            var candidates = existingByPID[item.processIdentifier] ?? []
            let candidateIndex = candidates.firstIndex {
                CFEqual($0.element, item.element)
            }
            let tracked: TrackedWindow
            let isNew: Bool

            if let candidateIndex {
                tracked = candidates.remove(at: candidateIndex)
                existingByPID[item.processIdentifier] = candidates
                tracked.applicationName = item.applicationName
                tracked.title = item.title
                tracked.isMinimized = item.isMinimized
                isNew = false
            } else {
                tracked = TrackedWindow(
                    element: item.element,
                    processIdentifier: item.processIdentifier,
                    application: item.application,
                    applicationName: item.applicationName,
                    title: item.title,
                    isMinimized: item.isMinimized
                )
                isNew = true
            }

            if isNew || newlyObservedPIDs.contains(item.processIdentifier) {
                installWindowNotifications(for: tracked)
            }
            liveWindows.append(tracked)
        }

        // A timed-out application is not the same thing as an application with
        // no windows. Retain its last known snapshot until a later scan succeeds.
        for (processIdentifier, existing) in existingByPID
            where livePIDs.contains(processIdentifier)
                && !discovery.scannedProcessIdentifiers.contains(processIdentifier) {
            liveWindows.append(contentsOf: existing)
        }

        let previousMRU = mru.identifiers
        windows = liveWindows
        if hasSeededInitialOrder {
            mru.reconcile(with: liveWindows.map(\.id))
        } else {
            let initialOrder = seedOrderFromWindowStack(liveWindows)
            mru.reconcile(with: initialOrder.map(\.id))
            hasSeededInitialOrder = true
        }
        if mru.identifiers != previousMRU {
            orderedWindowCache = nil
        }
        recordFocusedWindow()
    }

    private func eligibleApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { application in
            application.processIdentifier != ownProcessIdentifier
                && !application.isTerminated
                && application.activationPolicy != .prohibited
        }
    }

    private func processIdentifier(of element: AXUIElement) -> pid_t {
        var processIdentifier: pid_t = 0
        AXUIElementGetPid(element, &processIdentifier)
        return processIdentifier
    }

    private func existingWindow(for element: AXUIElement) -> TrackedWindow? {
        let processIdentifier = processIdentifier(of: element)
        return windows.first {
            $0.represents(element, processIdentifier: processIdentifier)
        }
    }

    private func updateTitle(for element: AXUIElement) {
        let processIdentifier = processIdentifier(of: element)
        discoveryQueue.async { [weak self] in
            AXUIElementSetMessagingTimeout(element, 0.1)
            let title = AXHelpers.title(of: element)

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.isStarted,
                      let tracked = self.windows.first(where: {
                          $0.represents(element, processIdentifier: processIdentifier)
                      }) else {
                    return
                }
                tracked.title = title
            }
        }
    }

    private func recordFocusedWindow(
        for processIdentifier: pid_t,
        candidate: AXUIElement? = nil
    ) {
        guard processIdentifier != 0, processIdentifier != ownProcessIdentifier else { return }
        focusRequestGeneration &+= 1
        let requestGeneration = focusRequestGeneration

        if let candidate,
           let tracked = windows.first(where: {
               $0.represents(candidate, processIdentifier: processIdentifier)
           }) {
            recordUse(of: tracked)
            return
        }

        focusQueue.async { [weak self] in
            let applicationElement = AXUIElementCreateApplication(processIdentifier)
            AXUIElementSetMessagingTimeout(applicationElement, 0.1)
            guard let focused = AXHelpers.focusedWindow(for: applicationElement) else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.isStarted,
                      self.focusRequestGeneration == requestGeneration,
                      let tracked = self.windows.first(where: {
                          $0.represents(focused, processIdentifier: processIdentifier)
                      }) else {
                    return
                }
                self.recordUse(of: tracked)
            }
        }
    }

    private func recordFocusedWindow() {
        guard let application = NSWorkspace.shared.frontmostApplication else { return }
        recordFocusedWindow(for: application.processIdentifier)
    }

    private func recordUse(of window: TrackedWindow) {
        guard mru.identifiers.first != window.id else { return }
        mru.recordUse(of: window.id)
        orderedWindowCache = nil
    }

    @discardableResult
    private func installObserverIfNeeded(
        for applicationElement: AXUIElement,
        processIdentifier: pid_t
    ) -> Bool {
        guard observers[processIdentifier] == nil else { return false }

        var observer: AXObserver?
        guard AXObserverCreate(processIdentifier, catalogObserverCallback, &observer) == .success,
              let observer else {
            return false
        }

        observers[processIdentifier] = observer
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )

        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in [
            kAXWindowCreatedNotification,
            kAXFocusedWindowChangedNotification,
            kAXMainWindowChangedNotification
        ] {
            AXObserverAddNotification(
                observer,
                applicationElement,
                notification as CFString,
                context
            )
        }
        return true
    }

    private func installWindowNotifications(for window: TrackedWindow) {
        guard let observer = observers[window.processIdentifier] else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()

        for notification in [
            kAXUIElementDestroyedNotification,
            kAXTitleChangedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification
        ] {
            AXObserverAddNotification(
                observer,
                window.element,
                notification as CFString,
                context
            )
        }
    }

    private func removeWindow(_ element: AXUIElement) {
        let processIdentifier = processIdentifier(of: element)
        let previousCount = windows.count
        windows.removeAll {
            $0.represents(element, processIdentifier: processIdentifier)
        }
        guard windows.count != previousCount else {
            scheduleBackgroundRefresh()
            return
        }
        mru.reconcile(with: windows.map(\.id))
        orderedWindowCache = nil
    }

    private func removeApplication(processIdentifier: pid_t) {
        windows.removeAll { $0.processIdentifier == processIdentifier }
        mru.reconcile(with: windows.map(\.id))
        orderedWindowCache = nil

        guard let observer = observers.removeValue(forKey: processIdentifier) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    private func removeObserversForTerminatedApplications(livePIDs: Set<pid_t>) {
        for processIdentifier in Array(observers.keys) where !livePIDs.contains(processIdentifier) {
            guard let observer = observers.removeValue(forKey: processIdentifier) else { continue }
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
    }

    /// The window server exposes front-to-back order, which is the closest
    /// available seed for windows that existed before Quick Switch launched.
    /// From that point onward AX focus notifications maintain true MRU order.
    private func seedOrderFromWindowStack(_ liveWindows: [TrackedWindow]) -> [TrackedWindow] {
        guard let stack = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return liveWindows
        }

        var remaining = liveWindows
        var ordered: [TrackedWindow] = []
        ordered.reserveCapacity(liveWindows.count)

        for entry in stack {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let processIdentifier = entry[kCGWindowOwnerPID as String] as? pid_t else {
                continue
            }

            let windowTitle = entry[kCGWindowName as String] as? String
            let exactIndex = remaining.firstIndex {
                $0.processIdentifier == processIdentifier
                    && windowTitle != nil
                    && $0.title == windowTitle
            }
            let sameAppIndex = remaining.firstIndex {
                $0.processIdentifier == processIdentifier
            }

            if let index = exactIndex ?? sameAppIndex {
                ordered.append(remaining.remove(at: index))
            }
        }

        ordered.append(contentsOf: remaining)
        return ordered
    }
}
