import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var keyLabel: String

    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyLabel
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }
}

enum HotKeyAction: UInt32, CaseIterable {
    case nextDisplay = 1
    case previousDisplay = 2

    var title: String {
        switch self {
        case .nextDisplay: return "Next display"
        case .previousDisplay: return "Previous display"
        }
    }

    /// ⌃⌥→ and ⌃⌥← by default.
    var defaultShortcut: Shortcut {
        let mods = UInt32(controlKey | optionKey)
        switch self {
        case .nextDisplay: return Shortcut(keyCode: UInt32(kVK_RightArrow), carbonModifiers: mods, keyLabel: "→")
        case .previousDisplay: return Shortcut(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: mods, keyLabel: "←")
        }
    }

    func perform() {
        switch self {
        case .nextDisplay: CursorMover.jump(.next)
        case .previousDisplay: CursorMover.jump(.previous)
        }
    }

    fileprivate var defaultsKey: String { "shortcut.\(rawValue)" }
}

enum Shortcuts {
    /// Actions whose shortcut could not be registered (taken by another app).
    private(set) static var failed: Set<HotKeyAction> = []

    static func shortcut(for action: HotKeyAction) -> Shortcut? {
        guard let data = UserDefaults.standard.data(forKey: action.defaultsKey) else {
            return action.defaultShortcut // never customised
        }
        if data.isEmpty { return nil }     // explicitly cleared
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    static func set(_ shortcut: Shortcut?, for action: HotKeyAction) {
        // The same combo can't drive two actions: clear it from the other one.
        if let shortcut {
            for other in HotKeyAction.allCases where other != action && self.shortcut(for: other) == shortcut {
                UserDefaults.standard.set(Data(), forKey: other.defaultsKey)
            }
        }
        let data = shortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        UserDefaults.standard.set(data, forKey: action.defaultsKey)
    }

    static func resetToDefaults() {
        for action in HotKeyAction.allCases {
            UserDefaults.standard.removeObject(forKey: action.defaultsKey)
        }
    }

    static func registerAll() {
        HotKeyCenter.shared.unregisterAll()
        failed = []
        for action in HotKeyAction.allCases {
            guard let sc = shortcut(for: action) else { continue }
            let ok = HotKeyCenter.shared.register(id: action.rawValue, keyCode: sc.keyCode,
                                                  modifiers: sc.carbonModifiers) { action.perform() }
            if !ok { failed.insert(action) }
        }
    }

    /// Stop listening while the user records a new shortcut, so pressing an
    /// existing combo is captured instead of moving the cursor.
    static func suspend() {
        HotKeyCenter.shared.unregisterAll()
    }
}

enum KeyNames {
    private static let special: [Int: String] = [
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_KeypadEnter: "⌤",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    static func label(for event: NSEvent) -> String {
        if let s = special[Int(event.keyCode)] { return s }
        let base = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? "?"
        return base.uppercased()
    }
}
