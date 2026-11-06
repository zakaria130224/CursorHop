import AppKit
import Carbon.HIToolbox
import ServiceManagement

/// Button that records a global shortcut when clicked.
final class ShortcutRecorderButton: NSButton {
    let hotKeyAction: HotKeyAction
    var onChange: (() -> Void)?
    private var monitor: Any?

    init(action: HotKeyAction) {
        self.hotKeyAction = action
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        self.action = #selector(toggleRecording)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var isRecording: Bool { monitor != nil }

    func refresh() {
        if isRecording {
            title = "Type shortcut…"
        } else {
            title = Shortcuts.shortcut(for: hotKeyAction)?.displayString ?? "Click to record"
        }
    }

    @objc private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        Shortcuts.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil // swallow the key
        }
        refresh()
    }

    func stopRecording() {
        guard let m = monitor else { return }
        NSEvent.removeMonitor(m)
        monitor = nil
        Shortcuts.registerAll()
        refresh()
        onChange?()
    }

    private func handle(_ event: NSEvent) {
        let code = Int(event.keyCode)
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])

        if code == kVK_Escape && mods.isEmpty { stopRecording(); return }
        if (code == kVK_Delete || code == kVK_ForwardDelete) && mods.isEmpty {
            Shortcuts.set(nil, for: hotKeyAction)
            stopRecording()
            return
        }
        // Require ⌘/⌥/⌃ (shift alone isn't enough) unless it's a function key.
        guard !mods.subtracting(.shift).isEmpty || KeyNames.functionKeys.contains(code) else {
            NSSound.beep()
            return
        }
        let sc = Shortcut(keyCode: UInt32(code),
                          carbonModifiers: Shortcut.carbonModifiers(from: mods),
                          keyLabel: KeyNames.label(for: event))
        Shortcuts.set(sc, for: hotKeyAction)
        stopRecording()
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var recorders: [ShortcutRecorderButton] = []
    private let warningLabel = NSTextField(labelWithString: "")
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let rememberCheckbox = NSButton(checkboxWithTitle: "Return to last position on each display",
                                            target: nil, action: nil)
    private let loginNote = NSTextField(labelWithString: "")
    private let focusCheckbox = NSButton(checkboxWithTitle: "Focus the window on the target display",
                                         target: nil, action: nil)
    private let focusNote = NSTextField(wrappingLabelWithString: "")
    private let accessibilityButton = NSButton(title: "Open Accessibility Settings…", target: nil, action: nil)
    private let gestureCheckbox = NSButton(checkboxWithTitle: "Swipe left/right to change display:",
                                           target: nil, action: nil)
    private let gestureStylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let gestureModifierPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var gestureModifierRow: NSStackView!
    private let gestureReverseCheckbox = NSButton(checkboxWithTitle: "Reverse swipe direction",
                                                  target: nil, action: nil)
    private let gestureNote = NSTextField(wrappingLabelWithString: "")

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "CursorHop Settings"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
        buildUI()
        window.center()
    }

    override func showWindow(_ sender: Any?) {
        syncState()
        super.showWindow(sender)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        var rows: [[NSView]] = []
        for action in HotKeyAction.allCases {
            let recorder = ShortcutRecorderButton(action: action)
            recorder.onChange = { [weak self] in self?.syncState() }
            recorders.append(recorder)
            let label = NSTextField(labelWithString: action.title + ":")
            label.alignment = .right
            rows.append([label, recorder])
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing

        let hint = NSTextField(wrappingLabelWithString:
            "Click a shortcut, then press the new keys. Esc cancels, Delete clears.")
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.preferredMaxLayoutWidth = 390
        hint.textColor = .secondaryLabelColor

        warningLabel.textColor = .systemOrange
        warningLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        warningLabel.lineBreakMode = .byWordWrapping
        warningLabel.maximumNumberOfLines = 0
        warningLabel.preferredMaxLayoutWidth = 390

        rememberCheckbox.target = self
        rememberCheckbox.action = #selector(toggleRemember(_:))
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin(_:))
        loginNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        loginNote.textColor = .secondaryLabelColor
        loginNote.maximumNumberOfLines = 0
        loginNote.lineBreakMode = .byWordWrapping
        loginNote.preferredMaxLayoutWidth = 390

        focusCheckbox.target = self
        focusCheckbox.action = #selector(toggleFocus(_:))
        focusNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        focusNote.textColor = .secondaryLabelColor
        focusNote.preferredMaxLayoutWidth = 390
        accessibilityButton.target = self
        accessibilityButton.action = #selector(openAccessibility)
        accessibilityButton.bezelStyle = .rounded
        accessibilityButton.controlSize = .small

        gestureCheckbox.target = self
        gestureCheckbox.action = #selector(toggleGesture(_:))
        for style in GestureStyle.allCases {
            gestureStylePopup.addItem(withTitle: style.title)
            gestureStylePopup.lastItem?.tag = style.rawValue
        }
        gestureStylePopup.target = self
        gestureStylePopup.action = #selector(changeGestureStyle(_:))
        gestureStylePopup.controlSize = .small
        for modifier in GestureModifier.allCases {
            gestureModifierPopup.addItem(withTitle: modifier.title)
            gestureModifierPopup.lastItem?.tag = modifier.rawValue
        }
        gestureModifierPopup.target = self
        gestureModifierPopup.action = #selector(changeGestureModifier(_:))
        gestureModifierPopup.controlSize = .small
        gestureReverseCheckbox.target = self
        gestureReverseCheckbox.action = #selector(toggleGestureReverse(_:))
        gestureNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        gestureNote.textColor = .secondaryLabelColor
        gestureNote.preferredMaxLayoutWidth = 390
        let gestureRow = NSStackView(views: [gestureCheckbox, gestureStylePopup])
        gestureRow.orientation = .horizontal
        gestureRow.spacing = 6
        let holdLabel = NSTextField(labelWithString: "Hold:")
        gestureModifierRow = NSStackView(views: [holdLabel, gestureModifierPopup])
        gestureModifierRow.orientation = .horizontal
        gestureModifierRow.spacing = 6
        gestureModifierRow.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)

        let reset = NSButton(title: "Restore Default Shortcuts", target: self, action: #selector(resetDefaults))
        reset.bezelStyle = .rounded

        let stack = NSStackView(views: [grid, hint, warningLabel, gestureRow, gestureModifierRow,
                                     gestureReverseCheckbox, gestureNote,
                                     rememberCheckbox, focusCheckbox, focusNote, accessibilityButton,
                                     loginCheckbox, loginNote, reset])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(18, after: warningLabel)
        stack.setCustomSpacing(4, after: gestureRow)
        stack.setCustomSpacing(4, after: gestureModifierRow)
        stack.setCustomSpacing(4, after: gestureReverseCheckbox)
        stack.setCustomSpacing(18, after: gestureNote)
        stack.setCustomSpacing(4, after: focusCheckbox)
        stack.setCustomSpacing(6, after: focusNote)
        stack.setCustomSpacing(4, after: loginCheckbox)
        stack.setCustomSpacing(18, after: loginNote)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ])
        syncState()
    }

    private func syncState() {
        recorders.forEach { $0.refresh() }

        let failed = HotKeyAction.allCases.filter { Shortcuts.failed.contains($0) }
        if failed.isEmpty {
            warningLabel.stringValue = ""
            warningLabel.isHidden = true
        } else {
            let names = failed.compactMap { Shortcuts.shortcut(for: $0)?.displayString }.joined(separator: ", ")
            warningLabel.stringValue = "⚠︎ \(names) is already used by another app or macOS. Pick a different shortcut."
            warningLabel.isHidden = false
        }

        // Picks up a freshly granted Accessibility permission.
        GestureMonitor.update()
        let gestureOn = GestureMonitor.isEnabled
        let style = GestureMonitor.style
        gestureCheckbox.state = gestureOn ? .on : .off
        gestureStylePopup.selectItem(withTag: style.rawValue)
        gestureStylePopup.isEnabled = gestureOn
        gestureModifierPopup.selectItem(withTag: GestureMonitor.modifier.rawValue)
        gestureModifierPopup.isEnabled = gestureOn
        gestureModifierRow.isHidden = (style != .twoFingersWithModifier)
        gestureReverseCheckbox.state = GestureMonitor.isReversed ? .on : .off
        gestureReverseCheckbox.isEnabled = gestureOn
        let (next, previous) = GestureMonitor.isReversed ? ("left", "right") : ("right", "left")
        gestureNote.isHidden = !gestureOn
        switch (style, GestureMonitor.isRunning) {
        case (.twoFingersWithModifier, true):
            gestureNote.stringValue = "Hold \(GestureMonitor.modifier.symbol) and swipe two fingers \(next) for " +
                "the next display, \(previous) for the previous one."
        case (.twoFingersWithModifier, false):
            gestureNote.stringValue = "Allow CursorHop under Privacy & Security › Accessibility to use the swipe " +
                "gesture. If it's already listed and switched on, remove it (−) and add it again."
        case (.fourFingers, true):
            gestureNote.stringValue = "Swipe four fingers \(next) for the next display, \(previous) for the " +
                "previous one. If macOS also switches Spaces, set System Settings › Trackpad › More Gestures › " +
                "Swipe between full-screen applications to three fingers or Off."
        case (.fourFingers, false):
            gestureNote.stringValue = "No trackpad found, or this macOS version doesn't support reading " +
                "four-finger swipes."
        }

        rememberCheckbox.state = PositionMemory.isEnabled ? .on : .off

        focusCheckbox.state = FocusManager.isEnabled ? .on : .off
        if !FocusManager.isEnabled {
            focusNote.isHidden = true
        } else if FocusManager.isTrusted {
            focusNote.stringValue = "Accessibility access granted: the exact window under the cursor is raised."
            focusNote.isHidden = false
        } else {
            focusNote.stringValue = "Allow CursorHop under Privacy & Security › Accessibility to raise the exact " +
                "window. Without it, only the window's app is activated."
            focusNote.isHidden = false
        }
        accessibilityButton.isHidden = FocusManager.isTrusted ||
            !(FocusManager.isEnabled || GestureMonitor.needsAccessibility)

        switch SMAppService.mainApp.status {
        case .enabled:
            loginCheckbox.state = .on
            loginNote.isHidden = true
        case .requiresApproval:
            loginCheckbox.state = .on
            loginNote.stringValue = "Approve CursorHop in System Settings › General › Login Items."
            loginNote.isHidden = false
        default:
            loginCheckbox.state = .off
            loginNote.isHidden = true
        }
    }

    @objc private func toggleRemember(_ sender: NSButton) {
        PositionMemory.isEnabled = (sender.state == .on)
        if !PositionMemory.isEnabled { PositionMemory.clear() }
    }

    @objc private func toggleFocus(_ sender: NSButton) {
        FocusManager.isEnabled = (sender.state == .on)
        if FocusManager.isEnabled && !FocusManager.isTrusted { FocusManager.requestTrust() }
        syncState()
    }

    @objc private func toggleGesture(_ sender: NSButton) {
        GestureMonitor.isEnabled = (sender.state == .on)
        if GestureMonitor.needsAccessibility && !FocusManager.isTrusted { FocusManager.requestTrust() }
        syncState() // starts or stops the monitor
    }

    @objc private func changeGestureStyle(_ sender: NSPopUpButton) {
        if let style = GestureStyle(rawValue: sender.selectedTag()) {
            GestureMonitor.style = style
        }
        if GestureMonitor.needsAccessibility && !FocusManager.isTrusted { FocusManager.requestTrust() }
        syncState() // switches to the matching detector
    }

    @objc private func changeGestureModifier(_ sender: NSPopUpButton) {
        if let modifier = GestureModifier(rawValue: sender.selectedTag()) {
            GestureMonitor.modifier = modifier
        }
        syncState()
    }

    @objc private func toggleGestureReverse(_ sender: NSButton) {
        GestureMonitor.isReversed = (sender.state == .on)
        syncState()
    }

    @objc private func openAccessibility() {
        FocusManager.requestTrust()
        FocusManager.openAccessibilitySettings()
    }

    // Re-check permission when the user comes back from System Settings.
    func windowDidBecomeKey(_ notification: Notification) {
        syncState()
    }

    @objc private func toggleLogin(_ sender: NSButton) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginNote.stringValue = "Couldn't change login item: \(error.localizedDescription). " +
                "Try moving CursorHop.app to /Applications first."
            loginNote.isHidden = false
            loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
            return
        }
        syncState()
    }

    @objc private func resetDefaults() {
        recorders.forEach { $0.stopRecording() }
        Shortcuts.resetToDefaults()
        Shortcuts.registerAll()
        syncState()
    }

    func windowWillClose(_ notification: Notification) {
        recorders.forEach { $0.stopRecording() }
    }
}
