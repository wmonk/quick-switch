# Contributing to Quick Switch

Thanks for helping improve Quick Switch.

## Before you start

Quick Switch supports macOS 14 and later and requires Xcode 26 or later to compile. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen), clone the repository, and generate the project:

```sh
brew install xcodegen
git clone https://github.com/wmonk/quick-switch.git
cd quick-switch
xcodegen generate
open QuickSwitch.xcodeproj
```

The project uses ad-hoc signing by default. An Apple Developer account is not required, although selecting your own Development Team in Xcode can keep Accessibility authorization stable across rebuilds.

## Making changes

- Keep changes focused and explain the user-visible behavior they affect.
- Add or update tests for keyboard handling, selection behavior, and window classification changes.
- Update `project.yml` before regenerating `QuickSwitch.xcodeproj`; both files are committed.
- Do not commit DerivedData, release builds, signing material, or user-specific Xcode settings.
- Preserve the privacy model: window metadata stays on the Mac, and the app makes no network requests.

Run the test suite before opening a pull request:

```sh
xcodegen generate
xcodebuild test \
  -project QuickSwitch.xcodeproj \
  -scheme QuickSwitch \
  -destination 'platform=macOS'
```

For manual testing, run the app from Xcode and verify both `Command-Tab` and `Command-Backquote`. Debug builds also support `--preview`, and every build supports `--diagnose`.

## Reporting bugs

Please include your macOS version, Mac architecture, reproduction steps, and whether Secure Input or another window-management utility was active. Do not include private window titles or other sensitive information in logs or screenshots.

Security issues should not be filed publicly. Follow [SECURITY.md](SECURITY.md) instead.
