import Foundation
import CoreGraphics

/// Remembers where the cursor was last left on each display, so jumping back
/// returns to that spot. Stored as an offset from the display's origin and
/// keyed by display UUID, so it survives unplugging and rearranging displays.
enum PositionMemory {
    private static let storeKey = "savedDisplayOffsets"
    static let enabledKey = "rememberPositions"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static func save(_ point: CGPoint, on display: Display) {
        guard isEnabled, display.bounds.contains(point) else { return }
        var store = load()
        store[display.uuid] = [Double(point.x - display.bounds.minX), Double(point.y - display.bounds.minY)]
        UserDefaults.standard.set(store, forKey: storeKey)
    }

    /// The remembered point on `display`, or nil if none is saved or it no
    /// longer fits (e.g. the resolution changed).
    static func point(for display: Display) -> CGPoint? {
        guard isEnabled, let offset = load()[display.uuid], offset.count == 2 else { return nil }
        let p = CGPoint(x: display.bounds.minX + offset[0], y: display.bounds.minY + offset[1])
        return display.bounds.insetBy(dx: 1, dy: 1).contains(p) ? p : nil
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storeKey)
    }

    private static func load() -> [String: [Double]] {
        UserDefaults.standard.dictionary(forKey: storeKey) as? [String: [Double]] ?? [:]
    }
}
