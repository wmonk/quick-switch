import AppKit

final class PermissionWindowController: NSWindowController, NSWindowDelegate {
    var onPermissionGranted: (() -> Void)?

    private let statusLabel = NSTextField(labelWithString: "")
    private var pollTimer: Timer?
    private weak var previouslyActiveApplication: NSRunningApplication?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Quick Switch Setup"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        configureContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        previouslyActiveApplication = NSWorkspace.shared.frontmostApplication
        NSApp.setActivationPolicy(.regular)
        window?.center()
        showWindow(nil)
        NSApp.activate()
        updateStatus()

        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }

    func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
        NSApp.setActivationPolicy(.accessory)
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let icon = NSImageView(image: NSImage(
            systemSymbolName: "rectangle.on.rectangle",
            accessibilityDescription: "Quick Switch"
        ) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 42, weight: .medium)

        let title = NSTextField(labelWithString: "Allow Quick Switch to control windows")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.alignment = .center

        let explanation = NSTextField(wrappingLabelWithString:
            "Quick Switch needs Accessibility permission to list and focus windows and to replace Command-Tab. It never records your screen or reads the contents of your windows. After enabling access, restart Quick Switch if macOS does not update immediately."
        )
        explanation.alignment = .center
        explanation.textColor = .secondaryLabelColor

        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.alignment = .center

        let openSettingsButton = NSButton(
            title: "Open System Settings",
            target: self,
            action: #selector(openSystemSettings)
        )
        if #available(macOS 26.0, *) {
            openSettingsButton.bezelStyle = .glass
        } else {
            openSettingsButton.bezelStyle = .rounded
        }
        openSettingsButton.keyEquivalent = "\r"

        let restartButton = NSButton(
            title: "Restart Quick Switch",
            target: self,
            action: #selector(restartApplication)
        )
        restartButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [openSettingsButton, restartButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [icon, title, explanation, statusLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -36),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func updateStatus() {
        if AccessibilityPermission.isGranted {
            statusLabel.stringValue = "Accessibility access granted"
            statusLabel.textColor = .systemGreen
            finishSetup()
        } else {
            statusLabel.stringValue = "Waiting for Accessibility access…"
            statusLabel.textColor = .secondaryLabelColor
        }
    }

    private func finishSetup() {
        pollTimer?.invalidate()
        pollTimer = nil
        close()
        NSApp.setActivationPolicy(.accessory)
        previouslyActiveApplication?.activate()
        onPermissionGranted?()
    }

    @objc private func openSystemSettings() {
        AccessibilityPermission.openSystemSettings()
    }

    @objc private func restartApplication() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--permission-relaunch"]
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { [weak self] _, error in
            DispatchQueue.main.async {
                if error != nil {
                    self?.statusLabel.stringValue = "Unable to restart. Quit and reopen Quick Switch."
                    self?.statusLabel.textColor = .systemRed
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }
}
