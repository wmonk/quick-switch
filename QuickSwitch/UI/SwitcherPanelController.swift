import AppKit

private enum SwitcherMetrics {
    static let preferredWidth: CGFloat = 860
    static let minimumWidth: CGFloat = 480
    static let preferredRowHeight: CGFloat = 38
    static let minimumRowHeight: CGFloat = 30
    static let outerCornerRadius: CGFloat = 26
    static let contentInset: CGFloat = 8
    static let fittingReserve: CGFloat = 2
    static let screenEdgeInset: CGFloat = 32

    static var chromeHeight: CGFloat {
        contentInset * 2
    }
}

private final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class SwitcherTableView: NSTableView {
    var onHoverRow: ((Int) -> Void)?
    var onClickRow: ((Int) -> Void)?

    private var pointerTrackingArea: NSTrackingArea?
    private var hoveredRow = -1
    private var pressedRow: Int?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoveredRow(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredRow = -1
    }

    override func mouseDown(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else {
            pressedRow = nil
            return
        }

        pressedRow = row
        notifyHoverIfNeeded(row)
    }

    override func mouseDragged(with event: NSEvent) {
        updateHoveredRow(for: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedRow = nil }
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0, row == pressedRow else { return }
        onClickRow?(row)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func updateHoveredRow(for event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else {
            hoveredRow = -1
            return
        }
        notifyHoverIfNeeded(row)
    }

    private func notifyHoverIfNeeded(_ row: Int) {
        guard row != hoveredRow || selectedRow != row else { return }
        hoveredRow = row
        onHoverRow?(row)
    }
}

private final class WindowRowView: NSTableRowView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("window-row")

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }

        let selectionColor = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            ? NSColor.unemphasizedSelectedContentBackgroundColor
            : NSColor.labelColor.withAlphaComponent(0.095)
        selectionColor.setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0, dy: 1),
            xRadius: 13,
            yRadius: 13
        ).fill()
    }
}

private final class WindowCellView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("window-cell")

    private let iconView = NSImageView()
    private let applicationLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")

    override var backgroundStyle: NSView.BackgroundStyle {
        get { .normal }
        set {
            super.backgroundStyle = .normal
            titleLabel.cell?.backgroundStyle = .normal
            applicationLabel.cell?.backgroundStyle = .normal
            applyTextColors()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown

        applicationLabel.translatesAutoresizingMaskIntoConstraints = false
        applicationLabel.font = .systemFont(ofSize: 13, weight: .regular)
        applicationLabel.textColor = .secondaryLabelColor
        applicationLabel.lineBreakMode = .byTruncatingTail
        applicationLabel.setContentHuggingPriority(.required, for: .horizontal)
        applicationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(applicationLabel)
        addSubview(iconView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            applicationLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 10),
            applicationLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            applicationLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with window: TrackedWindow) {
        let displayTitle = window.displayTitle
        iconView.image = window.applicationIcon
        applicationLabel.stringValue = window.applicationName + (window.isMinimized ? "  ·  Minimized" : "")
        titleLabel.stringValue = displayTitle
        applyTextColors()
        setAccessibilityLabel("\(window.applicationName), \(displayTitle)")
    }

    private func applyTextColors() {
        titleLabel.textColor = .labelColor
        applicationLabel.textColor = .secondaryLabelColor
    }
}

final class SwitcherPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let panel: SwitcherPanel
    private let tableView = SwitcherTableView()
    private let scrollView = NSScrollView()
    private var windows: [TrackedWindow] = []
    private var onHover: ((Int) -> Void)?
    private var onClick: ((Int) -> Void)?
    private var isScrollingEnabled = false

    override init() {
        panel = SwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: SwitcherMetrics.preferredWidth, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]

        let contentView = NSView()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = .zero
        tableView.rowHeight = SwitcherMetrics.preferredRowHeight
        tableView.dataSource = self
        tableView.delegate = self
        tableView.focusRingType = .none
        tableView.autoresizingMask = [.width]
        tableView.onHoverRow = { [weak self] row in
            guard let self, self.windows.indices.contains(row) else { return }
            self.onHover?(row)
        }
        tableView.onClickRow = { [weak self] row in
            guard let self, self.windows.indices.contains(row) else { return }
            self.onClick?(row)
        }

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        scrollView.verticalScrollElasticity = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: SwitcherMetrics.contentInset
            ),
            scrollView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -SwitcherMetrics.contentInset
            ),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: SwitcherMetrics.contentInset),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -SwitcherMetrics.contentInset)
        ])

        panel.contentView = makeSwitcherSurface(containing: contentView)
    }

    func setInteractionHandlers(
        onHover: @escaping (Int) -> Void,
        onClick: @escaping (Int) -> Void
    ) {
        self.onHover = onHover
        self.onClick = onClick
    }

    func show(windows: [TrackedWindow], selectedIndex: Int) {
        guard !windows.isEmpty else {
            hide()
            return
        }

        let screen = screenUnderPointer() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let maximumWidth = max(320, screen.visibleFrame.width - SwitcherMetrics.screenEdgeInset * 2)
        let preferredResponsiveWidth = max(
            SwitcherMetrics.minimumWidth,
            floor(screen.visibleFrame.width * 0.66)
        )
        let panelWidth = min(SwitcherMetrics.preferredWidth, preferredResponsiveWidth, maximumWidth)
        let maximumHeight = max(
            SwitcherMetrics.minimumRowHeight + SwitcherMetrics.chromeHeight,
            screen.visibleFrame.height - SwitcherMetrics.screenEdgeInset * 2
        )
        let availableRowsHeight = maximumHeight
            - SwitcherMetrics.chromeHeight
            - SwitcherMetrics.fittingReserve
        let fittingRowHeight = floor(availableRowsHeight / CGFloat(windows.count))
        tableView.rowHeight = min(
            SwitcherMetrics.preferredRowHeight,
            max(SwitcherMetrics.minimumRowHeight, fittingRowHeight)
        )

        self.windows = windows

        let estimatedRowsHeight = ceil(CGFloat(windows.count) * tableView.rowHeight)
        let estimatedPanelSize = NSSize(
            width: panelWidth,
            height: min(
                estimatedRowsHeight + SwitcherMetrics.chromeHeight,
                maximumHeight
            )
        )

        panel.setFrame(centeredFrame(for: estimatedPanelSize, on: screen), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()

        tableView.frame = NSRect(
            x: 0,
            y: 0,
            width: scrollView.contentSize.width,
            height: estimatedRowsHeight
        )
        tableView.reloadData()
        tableView.layoutSubtreeIfNeeded()

        let laidOutRowsHeight: CGFloat
        if let lastRow = windows.indices.last {
            laidOutRowsHeight = ceil(tableView.rect(ofRow: lastRow).maxY)
        } else {
            laidOutRowsHeight = estimatedRowsHeight
        }

        let finalPanelSize = NSSize(
            width: panelWidth,
            height: min(
                laidOutRowsHeight + SwitcherMetrics.chromeHeight,
                maximumHeight
            )
        )
        if panel.frame.size != finalPanelSize {
            panel.setFrame(centeredFrame(for: finalPanelSize, on: screen), display: false)
            panel.contentView?.layoutSubtreeIfNeeded()
        }

        tableView.frame = NSRect(
            x: 0,
            y: 0,
            width: scrollView.contentSize.width,
            height: laidOutRowsHeight
        )

        let needsScrolling = laidOutRowsHeight > scrollView.contentSize.height + 0.5
        isScrollingEnabled = needsScrolling
        scrollView.hasVerticalScroller = needsScrolling
        scrollView.verticalScrollElasticity = needsScrolling ? .automatic : .none

        let safeIndex = min(max(selectedIndex, 0), windows.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: safeIndex), byExtendingSelection: false)
        if needsScrolling {
            tableView.scrollRowToVisible(safeIndex)
        } else {
            scrollView.contentView.setBoundsOrigin(.zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        panel.orderFrontRegardless()
    }

    func updateSelection(_ selectedIndex: Int) {
        guard windows.indices.contains(selectedIndex) else { return }
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        if isScrollingEnabled {
            tableView.scrollRowToVisible(selectedIndex)
        }
    }

    func hide() {
        panel.orderOut(nil)
        isScrollingEnabled = false
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        windows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard windows.indices.contains(row) else { return nil }
        let cell = tableView.makeView(
            withIdentifier: WindowCellView.reuseIdentifier,
            owner: nil
        ) as? WindowCellView ?? WindowCellView(frame: .zero)
        cell.identifier = WindowCellView.reuseIdentifier
        cell.configure(with: windows[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = tableView.makeView(
            withIdentifier: WindowRowView.reuseIdentifier,
            owner: nil
        ) as? WindowRowView ?? WindowRowView()
        rowView.identifier = WindowRowView.reuseIdentifier
        return rowView
    }

    private func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }

    private func centeredFrame(for size: NSSize, on screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func makeSwitcherSurface(containing contentView: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.style = .regular
            glassView.cornerRadius = SwitcherMetrics.outerCornerRadius
            glassView.contentView = contentView
            return glassView
        }

        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = SwitcherMetrics.outerCornerRadius
        effectView.layer?.masksToBounds = true
        contentView.frame = effectView.bounds
        contentView.autoresizingMask = [.width, .height]
        effectView.addSubview(contentView)
        return effectView
    }
}
