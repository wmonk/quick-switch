import ApplicationServices

enum WindowClassification {
    /// AXWindows can contain non-window elements (Finder's desktop is one).
    /// Sheets and floating palettes are parts of another window rather than
    /// independent destinations. Every other top-level AX window is retained,
    /// including dialogs and minimized windows.
    static func isSwitchable(role: String?, subrole: String?) -> Bool {
        guard role == (kAXWindowRole as String) else { return false }
        return subrole != (kAXFloatingWindowSubrole as String)
            && subrole != (kAXSystemFloatingWindowSubrole as String)
    }
}
