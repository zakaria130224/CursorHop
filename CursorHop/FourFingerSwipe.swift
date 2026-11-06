import Foundation
import CoreGraphics

/// Detects four-finger horizontal swipes by reading raw trackpad touches from
/// the private MultitouchSupport framework (the approach tools like
/// BetterTouchTool use). It's loaded at runtime so CursorHop still launches if
/// the framework ever changes. Needs no permission, but it can't stop macOS
/// from also handling the swipe, so macOS's own four-finger swipe should be off.
enum FourFingerSwipe {
    private typealias ContactCallback = @convention(c)
        (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void
    private typealias StartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias StopFn = @convention(c) (UnsafeMutableRawPointer) -> Void

    private struct API {
        let createList: CreateListFn
        let register: RegisterFn
        let unregister: RegisterFn
        let start: StartFn
        let stop: StopFn
    }

    private static let api: API? = {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_LAZY),
              let createList = dlsym(handle, "MTDeviceCreateList"),
              let register = dlsym(handle, "MTRegisterContactFrameCallback"),
              let unregister = dlsym(handle, "MTUnregisterContactFrameCallback"),
              let start = dlsym(handle, "MTDeviceStart"),
              let stop = dlsym(handle, "MTDeviceStop")
        else { return nil }
        return API(createList: unsafeBitCast(createList, to: CreateListFn.self),
                   register: unsafeBitCast(register, to: RegisterFn.self),
                   unregister: unsafeBitCast(unregister, to: RegisterFn.self),
                   start: unsafeBitCast(start, to: StartFn.self),
                   stop: unsafeBitCast(stop, to: StopFn.self))
    }()

    // Layout of the framework's per-finger touch record (96 bytes each).
    private static let touchStride = 96
    private static let stateOffset = 20      // Int32
    private static let positionOffset = 32   // Float x, Float y, normalised 0…1
    private static let touchingStates: Set<Int32> = [4, 5] // "make touch" and "touching"

    /// Fraction of the trackpad's width the fingers must travel to trigger.
    private static let threshold: Float = 0.12

    private static var devices: CFArray?
    private static var handler: ((_ swipedRight: Bool) -> Void)?

    // Swipe state. Only touched from the framework's callback thread.
    private static var startPoint: (x: Float, y: Float)?
    private static var fired = false

    static var isRunning: Bool { devices != nil }

    /// Returns false if the framework or a trackpad isn't available.
    /// `onSwipe` is called on the main thread.
    @discardableResult
    static func start(onSwipe: @escaping (_ swipedRight: Bool) -> Void) -> Bool {
        handler = onSwipe
        guard devices == nil else { return true }
        guard let api, let list = api.createList()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else {
            return false
        }
        for i in 0..<CFArrayGetCount(list) {
            guard let device = CFArrayGetValueAtIndex(list, i) else { continue }
            let ref = UnsafeMutableRawPointer(mutating: device)
            api.register(ref, callback)
            api.start(ref, 0)
        }
        devices = list
        return true
    }

    static func stop() {
        guard let api, let list = devices else { return }
        for i in 0..<CFArrayGetCount(list) {
            guard let device = CFArrayGetValueAtIndex(list, i) else { continue }
            let ref = UnsafeMutableRawPointer(mutating: device)
            api.unregister(ref, callback)
            api.stop(ref)
        }
        devices = nil
    }

    private static let callback: ContactCallback = { _, touches, count, _, _ in
        FourFingerSwipe.process(touches, Int(count))
        return 0
    }

    private static func process(_ touches: UnsafeMutableRawPointer?, _ count: Int) {
        var fingers = 0
        var sumX: Float = 0
        var sumY: Float = 0
        if let touches {
            for i in 0..<count {
                let base = i * touchStride
                guard touchingStates.contains(touches.load(fromByteOffset: base + stateOffset, as: Int32.self))
                else { continue }
                fingers += 1
                sumX += touches.load(fromByteOffset: base + positionOffset, as: Float.self)
                sumY += touches.load(fromByteOffset: base + positionOffset + 4, as: Float.self)
            }
        }

        // All fingers lifted: the next four-finger touch is a new swipe.
        if fingers == 0 {
            startPoint = nil
            fired = false
            return
        }
        // Measure only while exactly four fingers are down; restart if that changes.
        guard fingers == 4 else {
            startPoint = nil
            return
        }

        let point = (x: sumX / 4, y: sumY / 4)
        guard let start = startPoint else {
            startPoint = point
            return
        }
        guard !fired else { return }

        let dx = point.x - start.x
        let dy = point.y - start.y
        // Clearly horizontal, so four-finger up/down (Mission Control) doesn't trigger.
        if abs(dx) >= threshold && abs(dx) > abs(dy) * 1.5 {
            fired = true
            let swipedRight = dx > 0
            DispatchQueue.main.async { handler?(swipedRight) }
        }
    }
}
