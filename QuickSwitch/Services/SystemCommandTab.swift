import Darwin
import Foundation

private let restoreCommandTabAtProcessExit: @convention(c) () -> Void = {
    SystemCommandTab.restoreNativeSwitcher()
}

/// Temporarily disables the Dock-owned Command-Tab shortcuts so our session
/// event tap receives them. macOS has no public API for replacing Command-Tab,
/// so the private symbol is resolved dynamically and never linked directly.
/// If it disappears in a future macOS release the app fails closed.
enum SystemCommandTab {
    private typealias SetSymbolicHotKeyEnabled = @convention(c) (Int32, Bool) -> Int32

    private static let commandTabIdentifier: Int32 = 1
    private static let commandShiftTabIdentifier: Int32 = 2

    private static let setEnabled: SetSymbolicHotKeyEnabled? = {
        let libraryPaths = [
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            "/System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics"
        ]

        for path in libraryPaths {
            guard let library = dlopen(path, RTLD_LAZY),
                  let symbol = dlsym(library, "CGSSetSymbolicHotKeyEnabled") else {
                continue
            }
            return unsafeBitCast(symbol, to: SetSymbolicHotKeyEnabled.self)
        }
        return nil
    }()

    private(set) static var isNativeSwitcherDisabled = false
    private static var hasRegisteredExitHandler = false
    static var isAvailable: Bool { setEnabled != nil }

    @discardableResult
    static func disableNativeSwitcher() -> Bool {
        guard let setEnabled else { return false }
        let forwardResult = setEnabled(commandTabIdentifier, false)
        let reverseResult = setEnabled(commandShiftTabIdentifier, false)

        // A partial takeover still needs restoring during teardown.
        if forwardResult == 0 || reverseResult == 0 {
            isNativeSwitcherDisabled = true
            if !hasRegisteredExitHandler {
                atexit(restoreCommandTabAtProcessExit)
                hasRegisteredExitHandler = true
            }
        }
        return forwardResult == 0 && reverseResult == 0
    }

    static func restoreNativeSwitcher() {
        guard isNativeSwitcherDisabled, let setEnabled else { return }
        let forwardResult = setEnabled(commandTabIdentifier, true)
        let reverseResult = setEnabled(commandShiftTabIdentifier, true)
        if forwardResult == 0 && reverseResult == 0 {
            isNativeSwitcherDisabled = false
        }
    }
}
