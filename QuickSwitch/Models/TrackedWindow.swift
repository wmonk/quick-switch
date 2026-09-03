import AppKit
import ApplicationServices

final class TrackedWindow {
    let id: UUID
    let element: AXUIElement
    let processIdentifier: pid_t
    let application: NSRunningApplication
    let applicationIcon: NSImage?

    var applicationName: String
    var title: String
    var isMinimized: Bool

    init(
        id: UUID = UUID(),
        element: AXUIElement,
        processIdentifier: pid_t,
        application: NSRunningApplication,
        applicationName: String,
        title: String,
        isMinimized: Bool
    ) {
        self.id = id
        self.element = element
        self.processIdentifier = processIdentifier
        self.application = application
        self.applicationIcon = application.icon
        self.applicationName = applicationName
        self.title = title
        self.isMinimized = isMinimized
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? applicationName : trimmed
    }

    func represents(_ otherElement: AXUIElement, processIdentifier otherPID: pid_t) -> Bool {
        processIdentifier == otherPID && CFEqual(element, otherElement)
    }
}

enum WindowScope: Equatable {
    case all
    case application(pid_t)
}
