# CursorHop

A tiny macOS menu bar app that teleports your mouse cursor between displays with a hotkey or a trackpad swipe, and can focus a window on the display you land on.

Written in plain Swift and AppKit, with no third-party dependencies.

## Features

- **Global hotkeys:** jump to the next or previous display. Shortcuts can be re-recorded in Settings, and you get a warning if another app already owns a combo.
- **Trackpad swipes:** swipe right for the next display, left for the previous one. The direction can be reversed.
- **Position memory:** each display remembers where you left the cursor. The first visit lands in the center.
- **Focus follows jump:** the window under the cursor on the new display gets keyboard focus.
- **Menu bar list:** shows every display, and clicking one jumps straight to it.
- **Launch at login.**

Displays are ordered by physical arrangement (left to right, then top to bottom), and jumping wraps around.

| Default input | Action |
|---|---|
| ⌃⌥→ (Control + Option + Right) | Next display |
| ⌃⌥← (Control + Option + Left) | Previous display |
| ⌥ + two-finger swipe | Next or previous display, by swipe direction |

## Requirements

- macOS 13 Ventura or newer
- Xcode, or just the Command Line Tools: `xcode-select --install`

## Install from source

```bash
git clone <repository-url>
cd <repository-folder>
./build.sh install     # builds, copies to /Applications, launches
```

Look for the cursor icon in the menu bar. Settings opens automatically the first time.

To quit, use the menu bar icon → **Quit CursorHop**. To uninstall, quit the app and delete `/Applications/CursorHop.app`.

## Permissions

Hotkeys and cursor movement work with no permissions. Some features need access under **System Settings → Privacy & Security → Accessibility**:

| Feature | Accessibility access |
|---|---|
| Hotkeys and the menu bar list | Not needed |
| Four-finger swipe | Not needed |
| Two-finger swipe | Required |
| Focus follows jump | Recommended. Without it, CursorHop activates the app, which may bring forward a different window of that app |

## Swipe styles

Choose a style in Settings:

- **Two fingers + key** (default): hold a modifier (⌥ by default) and swipe. The swipe is swallowed, so the app under the cursor doesn't scroll.
- **Four fingers:** reads raw trackpad touches from Apple's private `MultitouchSupport` framework. It can't stop macOS from handling the same swipe, so turn off the system's four-finger swipe between full-screen apps in **System Settings → Trackpad → More Gestures**. Because it relies on a private framework, it could stop working in a future macOS release.

## Troubleshooting

- **Launch at login fails:** make sure the app is in `/Applications`. `./build.sh install` puts it there.
- **A shortcut does nothing:** another app or macOS may own that combo. Open Settings to check for a warning, then record a different one.

## Contributing

Contributions are welcome. Please open an issue first for large changes, so the approach can be agreed before you put in the work.

### Build and check

```bash
swiftc -typecheck -target "$(uname -m)-apple-macos13.0" CursorHop/*.swift   # fast compile check
./build.sh             # build only -> build/CursorHop.app
./build.sh universal   # Apple Silicon + Intel binary
./build.sh install     # replace the installed app and relaunch it
```

Or open `CursorHop.xcodeproj` and press **⌘R**. No Apple Developer account is needed, because local builds are ad-hoc signed.

`./build.sh` deletes the whole `build/` folder first, including any DMG in it.

### Before opening a pull request

- **Test by hand.** The project has no automated tests yet, so run the app and say in your PR what you tried, including your macOS version and display setup. Multi-display behaviour needs at least two displays (or a virtual one), and swipes need a trackpad.
- **Keep both builds working.** `build.sh` compiles `CursorHop/*.swift` directly, while Xcode uses its own file list. New source files must also be added to the Xcode project, and new frameworks to the `-framework` list in `build.sh`.
- **Stay dependency-free.** Please discuss any third-party dependency in an issue first.
- **Keep the macOS 13 minimum.** Guard newer APIs with `#available`.
- **Update this README** if you change user-visible behaviour.

### Project layout

```
CursorHop/
  main.swift             app entry (menu-bar-only, no Dock icon)
  AppDelegate.swift      status item and menu
  CursorMover.swift      next/previous/jump-to logic and cursor warp
  DisplayManager.swift   display list, ordering, names, stable UUIDs
  PositionMemory.swift   last cursor position per display
  FocusManager.swift     focuses a window on the destination display
  HotKeyCenter.swift     Carbon RegisterEventHotKey wrapper
  Shortcuts.swift        shortcut model, defaults, persistence, key names
  GestureMonitor.swift   swipe settings and the two-finger event tap
  FourFingerSwipe.swift  four-finger detection via MultitouchSupport
  SettingsWindow.swift   settings window and shortcut recorder
  Info.plist             bundle metadata and version
scripts/make_icon.swift  regenerates AppIcon.icns from icon_source.png
build.sh                 swiftc build and ad-hoc codesign
make-dmg.sh              builds and packages a DMG
```

[CLAUDE.md](CLAUDE.md) has the architecture notes and the invariants that are easy to break, such as the coordinate space and event tap threading. It's written for AI coding agents, but it's worth reading before changing the core code.

## Packaging a DMG

```bash
./make-dmg.sh          # -> build/CursorHop-<version>.dmg (Apple Silicon + Intel)
```

This build is ad-hoc signed and not notarized, so on first launch users have to go to **System Settings → Privacy & Security → Open Anyway**.

With a paid Apple Developer account, sign and notarize so it opens with no warning:

```bash
xcrun notarytool store-credentials cursorhop --apple-id you@example.com --team-id TEAMID   # once
SIGN_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=cursorhop ./make-dmg.sh
```

## License

No license has been chosen yet.
