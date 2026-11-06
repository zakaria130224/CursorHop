import AppKit
import ApplicationServices

/// Gives keyboard focus to a window on the display the cursor just jumped to.
///
/// Finding the window uses CGWindowList (no permission needed). Raising that
/// exact window uses the Accessibility API, which needs the user to allow
/// CursorHop in System Settings › Privacy & Security › Accessibility. Without
/// it we fall back to activating the window's app, which may bring forward a
/// different window of that app.
enum FocusManager {
    static let enabledKey = "focusFollowsJump"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system "allow Accessibility access" prompt if not yet trusted.
    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Focus the window under `point`, or else the frontmost window on `display`.
    static func focusWindow(at point: CGPoint, on display: Display) {
        guard isEnabled, let target = topWindow(at: point, on: display) else { return }

        if isTrusted {
            let appElement = AXUIElementCreateApplication(target.pid)
            AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            if let window = axWindow(of: appElement, matching: target.bounds) {
                AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            }
        } else if let app = NSRunningApplication(processIdentifier: target.pid) {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }
    }

    // MARK: - Finding the window

    private struct WindowInfo {
        let pid: pid_t
        let bounds: CGRect
    }

    private static func topWindow(at point: CGPoint, on display: Display) -> WindowInfo? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var firstOnDisplay: WindowInfo?

        // The list is ordered front to back.
        for entry in list {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 40, bounds.height > 40
            else { continue }
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
            guard NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular else { continue }

            let info = WindowInfo(pid: pid, bounds: bounds)
            if bounds.contains(point) { return info }
            if firstOnDisplay == nil && display.bounds.contains(CGPoint(x: bounds.midX, y: bounds.midY)) {
                firstOnDisplay = info
            }
        }
        return firstOnDisplay
    }

    /// The app's AX window whose frame matches the CGWindowList bounds.
    private static func axWindow(of app: AXUIElement, matching bounds: CGRect) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }

        var best: AXUIElement?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for window in windows {
            guard let f = frame(of: window) else { continue }
            let d = abs(f.minX - bounds.minX) + abs(f.minY - bounds.minY)
                + abs(f.width - bounds.width) + abs(f.height - bounds.height)
            if d < bestDistance {
                bestDistance = d
                best = window
            }
        }
        return bestDistance < 4 ? best : nil
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
