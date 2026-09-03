import AppKit
import ApplicationServices

enum AXHelpers {
    struct WindowSnapshot {
        let element: AXUIElement
        let title: String
        let isMinimized: Bool
    }

    static func value<T>(
        _ attribute: CFString,
        from element: AXUIElement,
        as type: T.Type = T.self
    ) -> T? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &rawValue) == .success else {
            return nil
        }
        return rawValue as? T
    }

    static func windows(for applicationElement: AXUIElement) -> [WindowSnapshot]? {
        guard let windows: [AXUIElement] = value(
            kAXWindowsAttribute as CFString,
            from: applicationElement
        ) else {
            return nil
        }
        return windows.compactMap(snapshot)
    }

    static func title(of window: AXUIElement) -> String {
        value(kAXTitleAttribute as CFString, from: window) ?? ""
    }

    static func isMinimized(_ window: AXUIElement) -> Bool {
        value(kAXMinimizedAttribute as CFString, from: window) ?? false
    }

    static func focusedWindow(for applicationElement: AXUIElement) -> AXUIElement? {
        value(kAXFocusedWindowAttribute as CFString, from: applicationElement)
    }

    private static func snapshot(of window: AXUIElement) -> WindowSnapshot? {
        let attributes = [
            kAXRoleAttribute,
            kAXSubroleAttribute,
            kAXTitleAttribute,
            kAXMinimizedAttribute
        ] as CFArray
        var rawValues: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(
            window,
            attributes,
            [],
            &rawValues
        ) == .success,
        let values = rawValues as? [Any],
        values.count == 4 else {
            return nil
        }

        let role = values[0] as? String
        let subrole = values[1] as? String
        guard WindowClassification.isSwitchable(role: role, subrole: subrole) else {
            return nil
        }

        return WindowSnapshot(
            element: window,
            title: values[2] as? String ?? "",
            isMinimized: values[3] as? Bool ?? false
        )
    }
}
