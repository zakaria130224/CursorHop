import AppKit

// Menu bar-only app entry point (no Dock icon; LSUIElement is also set in Info.plist).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
