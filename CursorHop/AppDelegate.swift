import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private lazy var settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "CursorHop")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "CursorHop"
        }
        menu.delegate = self
        statusItem.menu = menu

        Shortcuts.registerAll()
        GestureMonitor.update()

        // Focus-follows-jump and the swipe gesture both need Accessibility access.
        if (FocusManager.isEnabled || GestureMonitor.needsAccessibility) && !FocusManager.isTrusted {
            FocusManager.requestTrust()
        }

        // Show settings once on first launch so the user sees the shortcuts.
        let firstLaunchKey = "hasLaunchedBefore"
        if !UserDefaults.standard.bool(forKey: firstLaunchKey) {
            UserDefaults.standard.set(true, forKey: firstLaunchKey)
            openSettings()
        }
    }

    // Rebuild the menu each time it opens so the display list is always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(item(title: "Next Display", shortcut: Shortcuts.shortcut(for: .nextDisplay),
                          action: #selector(nextDisplay)))
        menu.addItem(item(title: "Previous Display", shortcut: Shortcuts.shortcut(for: .previousDisplay),
                          action: #selector(previousDisplay)))
        menu.addItem(.separator())

        let displays = DisplayManager.displays()
        let header = NSMenuItem(title: displays.count == 1 ? "1 Display" : "\(displays.count) Displays",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let current = DisplayManager.index(containing: CursorMover.currentLocation, in: displays)
        for (i, display) in displays.enumerated() {
            let it = NSMenuItem(title: "\(i + 1). \(display.name)", action: #selector(jumpToDisplay(_:)),
                                keyEquivalent: "")
            it.target = self
            it.tag = i
            it.state = (i == current) ? .on : .off
            it.indentationLevel = 1
            menu.addItem(it)
        }

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quit = NSMenuItem(title: "Quit CursorHop", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func item(title: String, shortcut: Shortcut?, action: Selector) -> NSMenuItem {
        let label = shortcut.map { "\(title)    \($0.displayString)" } ?? title
        let it = NSMenuItem(title: label, action: action, keyEquivalent: "")
        it.target = self
        return it
    }

    @objc private func nextDisplay() { CursorMover.jump(.next) }
    @objc private func previousDisplay() { CursorMover.jump(.previous) }
    @objc private func jumpToDisplay(_ sender: NSMenuItem) { CursorMover.jump(toDisplayAt: sender.tag) }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settings.showWindow(nil)
        settings.window?.makeKeyAndOrderFront(nil)
    }
}
