import AppKit

/// Modifier that must be held while swiping for the swipe to jump displays.
enum GestureModifier: Int, CaseIterable {
    case option, control, command, controlOption

    var title: String {
        switch self {
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .command: return "⌘ Command"
        case .controlOption: return "⌃⌥ Control-Option"
        }
    }

    var symbol: String {
        switch self {
        case .option: return "⌥"
        case .control: return "⌃"
        case .command: return "⌘"
        case .controlOption: return "⌃⌥"
        }
    }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .option: return .option
        case .control: return .control
        case .command: return .command
        case .controlOption: return [.control, .option]
        }
    }
}

/// Which swipe jumps displays.
enum GestureStyle: Int, CaseIterable {
    case twoFingersWithModifier, fourFingers

    var title: String {
        switch self {
        case .twoFingersWithModifier: return "Two fingers + key"
        case .fourFingers: return "Four fingers"
        }
    }
}

/// Turns a horizontal swipe into a display jump. Swipe right → next display,
/// left → previous.
///
/// Two fingers + modifier uses a CGEventTap on scroll events, which needs
/// Accessibility access. While the modifier is held, the swipe is swallowed so
/// the app under the cursor doesn't scroll as well. Four fingers is handled by
/// `FourFingerSwipe`.
enum GestureMonitor {
    private static let enabledKey = "gesture.enabled"
    private static let styleKey = "gesture.style"
    private static let modifierKey = "gesture.modifier"
    private static let reversedKey = "gesture.reversed"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var style: GestureStyle {
        get { GestureStyle(rawValue: UserDefaults.standard.integer(forKey: styleKey)) ?? .twoFingersWithModifier }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: styleKey) }
    }

    /// Only the two-finger swipe needs Accessibility access.
    static var needsAccessibility: Bool { isEnabled && style == .twoFingersWithModifier }

    static var modifier: GestureModifier {
        get { GestureModifier(rawValue: UserDefaults.standard.integer(forKey: modifierKey)) ?? .option }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modifierKey) }
    }

    /// Swap directions: swipe left → next display.
    static var isReversed: Bool {
        get { UserDefaults.standard.bool(forKey: reversedKey) }
        set { UserDefaults.standard.set(newValue, forKey: reversedKey) }
    }

    static var isRunning: Bool {
        switch style {
        case .twoFingersWithModifier: return tap != nil
        case .fourFingers: return FourFingerSwipe.isRunning
        }
    }

    private static var tap: CFMachPort?
    private static var source: CFRunLoopSource?
    private static var retryTimer: Timer?

    // State of the swipe in progress.
    private static var swiping = false
    private static var firedThisSwipe = false
    private static var swallowMomentum = false
    private static var accumulated: CGFloat = 0
    private static var lastEventTime: TimeInterval = 0

    /// Horizontal travel (in points) needed to trigger a jump.
    private static let threshold: CGFloat = 60
    /// Mouse wheels have no gesture phases; a pause this long starts a new swipe.
    private static let idleReset: TimeInterval = 0.3

    /// Start or stop listening to match `isEnabled` and `style`.
    static func update() {
        let two = isEnabled && style == .twoFingersWithModifier
        let four = isEnabled && style == .fourFingers
        if two { startTap() } else { stopTap() }
        if four {
            FourFingerSwipe.start { swipedRight in
                CursorMover.jump((swipedRight != isReversed) ? .next : .previous)
            }
        } else {
            FourFingerSwipe.stop()
        }
    }

    private static func startTap() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                           place: .headInsertEventTap,
                                           options: .defaultTap,
                                           eventsOfInterest: mask,
                                           callback: { _, type, event, _ in GestureMonitor.handle(type, event) },
                                           userInfo: nil)
        else {
            NSLog("CursorHop: swipe gesture unavailable until Accessibility access is granted")
            scheduleRetry()
            return
        }
        tap = port
        source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        retryTimer?.invalidate()
        retryTimer = nil
    }

    private static func stopTap() {
        retryTimer?.invalidate()
        retryTimer = nil
        guard let port = tap else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        tap = nil
        source = nil
        reset()
    }

    /// The tap can't be created until Accessibility access is granted; keep
    /// trying so the gesture starts working as soon as the user allows it.
    private static func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            if needsAccessibility && AXIsProcessTrusted() { startTap() }
        }
    }

    private static func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables a tap that is too slow or on user request; turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel, let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }
        return shouldSwallow(nsEvent) ? nil : Unmanaged.passUnretained(event)
    }

    /// Tracks the swipe and returns true if the event belongs to it.
    private static func shouldSwallow(_ e: NSEvent) -> Bool {
        // The glide after lifting the fingers: swallow it if it follows our swipe.
        if !e.momentumPhase.isEmpty {
            return swallowMomentum
        }

        if e.phase.contains(.began) || e.phase.contains(.mayBegin) || e.timestamp - lastEventTime > idleReset {
            reset()
        }
        lastEventTime = e.timestamp

        var dx = e.scrollingDeltaX
        let dy = e.scrollingDeltaY
        if !e.hasPreciseScrollingDeltas { dx *= 10 } // wheel deltas are in lines, not points

        if !swiping {
            let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
            guard mods == modifier.flags, abs(dx) > abs(dy) else { return false }
            swiping = true
        }

        if e.phase.contains(.ended) || e.phase.contains(.cancelled) {
            swiping = false // keep swallowMomentum for the glide that follows
            return true
        }

        if !firedThisSwipe {
            // Natural scrolling reports deltas in finger direction; classic scrolling inverts them.
            accumulated += e.isDirectionInvertedFromDevice ? dx : -dx
            if abs(accumulated) >= threshold {
                firedThisSwipe = true
                swallowMomentum = true
                let swipedRight = accumulated > 0
                let direction: JumpDirection = (swipedRight != isReversed) ? .next : .previous
                // Leave the tap callback quickly; focusing a window can be slow.
                DispatchQueue.main.async { CursorMover.jump(direction) }
            }
        }
        return true
    }

    private static func reset() {
        swiping = false
        firedThisSwipe = false
        swallowMomentum = false
        accumulated = 0
    }
}
