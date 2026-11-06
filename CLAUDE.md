# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

CursorHop is a macOS 13+ menu-bar-only app (`LSUIElement`, no Dock icon) that teleports the cursor between displays via global hotkeys, trackpad swipes, or the status menu, and optionally focuses a window on the destination display. Plain Swift + AppKit, built in code with no storyboards, SwiftUI, or third-party dependencies.

## Commands

```bash
swiftc -typecheck -target "$(uname -m)-apple-macos13.0" CursorHop/*.swift   # fast compile check, leaves build/ alone
./build.sh              # build for this arch -> build/CursorHop.app
./build.sh universal    # arm64 + x86_64 via lipo
./build.sh install      # build, kill the running app, replace /Applications/CursorHop.app, launch
./make-dmg.sh           # universal build -> build/CursorHop-<version>.dmg
swift scripts/make_icon.swift   # regenerate CursorHop/AppIcon.icns from scripts/icon_source.png
```

- `build.sh` starts with `rm -rf build`, so every build also deletes any existing DMG.
- `make-dmg.sh` optionally takes `SIGN_ID` and `NOTARY_PROFILE` env vars (Developer ID signing and notarization). Without them the build is ad-hoc signed.
- There are no tests and no linter. Behaviour has to be checked by running the app, and most of it needs multiple displays or a trackpad.

## Two build systems

`build.sh` compiles `CursorHop/*.swift` directly with `swiftc`; `CursorHop.xcodeproj` is a separate definition of the same target. When adding a source file, the glob picks it up automatically but it must also be added to `project.pbxproj`. When linking a new framework, update the `-framework` list in `build.sh` too. The version lives in `CursorHop/Info.plist` (`make-dmg.sh` reads it for the DMG name).

## Architecture

Nearly everything is a caseless `enum` of static state and functions rather than an instance; `AppDelegate` owns only the status item and the settings window.

All triggers converge on `CursorMover`, the single place that moves the cursor:

```
Carbon hotkey   -> HotKeyCenter -> Shortcuts/HotKeyAction.perform ┐
Two-finger swipe -> GestureMonitor (CGEventTap)                   ├-> CursorMover.jump
Four-finger swipe -> FourFingerSwipe (MultitouchSupport)          │     1. PositionMemory.save (source display)
Status menu      -> AppDelegate                                   ┘     2. PositionMemory.point or display center
                                                                        3. CGWarpMouseCursorPosition
                                                                        4. FocusManager.focusWindow
```

`DisplayManager.displays()` re-queries on every call (nothing is cached), excludes mirrors, and sorts left to right then top to bottom. The order defines next/previous.

### Invariants worth preserving

- **Coordinates:** all math is in global Core Graphics space (top-left origin of the main display, y down), the same space as `CGWarpMouseCursorPosition`, `CGEvent.location`, and `CGWindowList`. Avoid `NSScreen` frames, which are y-flipped; `NSScreen` is only used to look up display names.
- **Display identity:** persist by `Display.uuid`, never `CGDirectDisplayID`, which isn't stable across reconnects. `PositionMemory` stores offsets from the display origin so saved spots survive rearranging.
- **After warping:** `CGAssociateMouseAndMouseCursorPosition(1)` must follow `CGWarpMouseCursorPosition`, or the cursor freezes for about 0.25 s.
- **Event tap callback:** must return quickly or macOS disables the tap, so `GestureMonitor` dispatches the jump to main asynchronously. The handler also re-enables the tap on `tapDisabledByTimeout`/`tapDisabledByUserInput`.
- **`FourFingerSwipe` threading:** its swipe state is touched only on the framework's callback thread; `handler` is hopped to main.
- **`FourFingerSwipe` private API:** `MultitouchSupport` is loaded with `dlopen`/`dlsym` so the app still launches if it changes. Keep it that way rather than linking it. The touch record layout (96-byte stride, field offsets) is hard-coded. It can't swallow the swipe, so macOS's own four-finger swipe should be turned off.
- **Shortcut recording:** `Shortcuts.suspend()` unregisters all hotkeys during recording, and `registerAll()` restores them. `Shortcuts.failed` drives the "already in use" warning in Settings.

### Permissions

| Feature | Accessibility needed? |
|---|---|
| Hotkeys (Carbon), cursor warp, four-finger swipe | No |
| Two-finger swipe (`CGEventTap`) | Yes; `GestureMonitor` retries every 2 s until granted |
| Focus-follows-jump | Preferred; without it, falls back to activating the app, which may raise a different window |

`SettingsWindowController.syncState()` calls `GestureMonitor.update()` to pick up a newly granted permission.

### Settings persistence

All settings are in `UserDefaults.standard`, with keys defined next to the feature that owns them (`shortcut.<id>`, `gesture.*`, `focusFollowsJump`, `rememberPositions`, `savedDisplayOffsets`, `hasLaunchedBefore`).

- Default-on booleans use `object(forKey:) as? Bool ?? true`, because `bool(forKey:)` would read an unset key as `false`.
- For shortcuts, a missing key means use the default, while empty `Data` means explicitly cleared. Don't collapse the two.
