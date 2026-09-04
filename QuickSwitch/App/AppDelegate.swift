import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum PreferenceKey {
        static let confirmDestructiveActions = "confirmDestructiveActions"
    }

    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var confirmationMenuItem: NSMenuItem?
    private var catalog: WindowCatalog?
    private var panelController: SwitcherPanelController?
    private var keyboardController: KeyboardShortcutController?
    private lazy var permissionWindowController: PermissionWindowController = {
        let controller = PermissionWindowController()
        controller.onPermissionGranted = { [weak self] in
            self?.startQuickSwitch()
        }
        return controller
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests load this executable as their host. They must be allowed to
        // bootstrap without starting the menu-bar app, installing an event tap,
        // or participating in the single-instance check.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        if ProcessInfo.processInfo.arguments.contains("--diagnose") {
            runDiagnosticsAndExit()
            return
        }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") {
            showDebugPreview()
            return
        }
#endif

        let isPermissionRelaunch = ProcessInfo.processInfo.arguments.contains("--permission-relaunch")
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let alreadyRunning = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.willmonk.QuickSwitch"
        ).contains { $0.processIdentifier != currentPID }
        if alreadyRunning && !isPermissionRelaunch {
            NSApp.terminate(nil)
            return
        }

        // The app Info.plist declares that this intentionally windowless
        // utility does not support automatic or sudden termination. Keep the
        // runtime sudden-termination counter raised as an additional safeguard
        // so shutdown reaches applicationWillTerminate and restores Command-Tab.
        ProcessInfo.processInfo.disableSuddenTermination()

        UserDefaults.standard.register(defaults: [
            PreferenceKey.confirmDestructiveActions: true
        ])

        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()

        if AccessibilityPermission.isGranted {
            startQuickSwitch()
        } else {
            statusMenuItem?.title = "Accessibility access required"
            AccessibilityPermission.requestIfNeeded()
            permissionWindowController.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardController?.stop()
        catalog?.stop()
    }

    private func startQuickSwitch() {
        guard keyboardController == nil else { return }
        guard AccessibilityPermission.isGranted else {
            permissionWindowController.show()
            return
        }

        let catalog = WindowCatalog()
        let panelController = SwitcherPanelController()
        let keyboardController = KeyboardShortcutController(
            catalog: catalog,
            panelController: panelController
        )
        keyboardController.confirmsDestructiveActions = confirmsDestructiveActions
        keyboardController.onEventTapFailure = { [weak self] in
            self?.statusMenuItem?.title = "Keyboard access unavailable"
        }

        self.catalog = catalog
        self.panelController = panelController
        self.keyboardController = keyboardController

        catalog.start()
        guard keyboardController.start() else {
            keyboardController.stop()
            catalog.stop()
            self.keyboardController = nil
            self.panelController = nil
            self.catalog = nil
            statusMenuItem?.title = AccessibilityPermission.isGranted
                ? "Unable to take over Command-Tab"
                : "Accessibility access required"
            if !AccessibilityPermission.isGranted {
                permissionWindowController.show()
            }
            return
        }
        statusMenuItem?.title = "Quick Switch is active"
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(named: "MenuBarIcon")
        icon?.isTemplate = true
        icon?.accessibilityDescription = "Quick Switch"
        statusItem.button?.image = icon

        let menu = NSMenu()
        let status = NSMenuItem(title: "Starting Quick Switch…", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let permissionItem = NSMenuItem(
            title: "Accessibility Settings…",
            action: #selector(showPermissionWindow),
            keyEquivalent: ","
        )
        permissionItem.target = self
        menu.addItem(permissionItem)

        let confirmationItem = NSMenuItem(
            title: "Confirm Before Closing or Quitting",
            action: #selector(toggleDestructiveActionConfirmation(_:)),
            keyEquivalent: ""
        )
        confirmationItem.target = self
        confirmationItem.state = confirmsDestructiveActions ? .on : .off
        menu.addItem(confirmationItem)

        let quitItem = NSMenuItem(
            title: "Quit Quick Switch",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
        statusMenuItem = status
        confirmationMenuItem = confirmationItem
    }

    private func runDiagnosticsAndExit() {
        let isTrusted = AccessibilityPermission.isGranted
        var windowCount = 0
        var applicationCount = 0
        var keyboardCaptureStarted = false
        var commandTabRestoredAfterCheck = true

        if isTrusted {
            let diagnosticCatalog = WindowCatalog()
            diagnosticCatalog.start()
            let windows = diagnosticCatalog.orderedWindows(in: .all)
            windowCount = windows.count
            applicationCount = Set(windows.map(\.processIdentifier)).count

            let diagnosticPanel = SwitcherPanelController()
            let diagnosticKeyboard = KeyboardShortcutController(
                catalog: diagnosticCatalog,
                panelController: diagnosticPanel
            )
            keyboardCaptureStarted = diagnosticKeyboard.start()
            diagnosticKeyboard.stop()
            commandTabRestoredAfterCheck = !SystemCommandTab.isNativeSwitcherDisabled
            diagnosticCatalog.stop()
        }

        let result: [String: Any] = [
            "accessibilityGranted": isTrusted,
            "commandTabRestoredAfterCheck": commandTabRestoredAfterCheck,
            "commandTabTakeoverAvailable": SystemCommandTab.isAvailable,
            "keyboardCaptureStarted": keyboardCaptureStarted,
            "switchableApplicationCount": applicationCount,
            "switchableWindowCount": windowCount
        ]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
           var output = String(data: data, encoding: .utf8) {
            output.append("\n")
            FileHandle.standardOutput.write(Data(output.utf8))
        }

        NSApp.terminate(nil)
    }

#if DEBUG
    private func showDebugPreview() {
        NSApp.setActivationPolicy(.accessory)
        let previewCatalog = WindowCatalog()
        let previewPanel = SwitcherPanelController()
        catalog = previewCatalog
        panelController = previewPanel
        previewCatalog.start()

        let windows = previewCatalog.orderedWindows(in: .all)
        previewPanel.show(windows: windows, selectedIndex: min(1, max(0, windows.count - 1)))
    }
#endif

    @objc private func showPermissionWindow() {
        permissionWindowController.show()
    }

    @objc private func toggleDestructiveActionConfirmation(_ sender: NSMenuItem) {
        let enabled = !confirmsDestructiveActions
        UserDefaults.standard.set(enabled, forKey: PreferenceKey.confirmDestructiveActions)
        sender.state = enabled ? .on : .off
        confirmationMenuItem?.state = sender.state
        keyboardController?.confirmsDestructiveActions = enabled
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private var confirmsDestructiveActions: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.confirmDestructiveActions)
    }
}
