import AppKit
import CoreGraphics

/// A physical display, described in global Core Graphics coordinates
/// (origin at the top-left of the main display, y grows downward) —
/// the same space that CGWarpMouseCursorPosition and CGEvent.location use.
struct Display {
    let id: CGDirectDisplayID
    let bounds: CGRect
    let name: String
    /// Stable across reconnects/reboots, unlike CGDirectDisplayID.
    let uuid: String
}

enum DisplayManager {
    /// Active, non-mirrored displays ordered by physical arrangement:
    /// left to right, then top to bottom.
    static func displays() -> [Display] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        let capacity = count
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(capacity))
        guard CGGetActiveDisplayList(capacity, &ids, &count) == .success else { return [] }

        let names = screenNames()
        var result: [Display] = []
        for id in ids.prefix(Int(count)) where CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay {
            let fallback = CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "Display"
            let name: String = names[id] ?? fallback
            result.append(Display(id: id, bounds: CGDisplayBounds(id), name: name, uuid: uuidString(for: id)))
        }
        result.sort { (a: Display, b: Display) -> Bool in
            if a.bounds.minX != b.bounds.minX { return a.bounds.minX < b.bounds.minX }
            return a.bounds.minY < b.bounds.minY
        }

        // Two identical monitors share a name; disambiguate them.
        var totals: [String: Int] = [:]
        for d in result { totals[d.name, default: 0] += 1 }
        var seen: [String: Int] = [:]
        for i in result.indices {
            let d = result[i]
            guard let total = totals[d.name], total > 1 else { continue }
            let n = (seen[d.name] ?? 0) + 1
            seen[d.name] = n
            result[i] = Display(id: d.id, bounds: d.bounds, name: "\(d.name) (\(n))", uuid: d.uuid)
        }
        return result
    }

    /// Index of the display containing `point`, or the nearest one if the point
    /// sits exactly on an edge / in a gap between displays.
    static func index(containing point: CGPoint, in displays: [Display]) -> Int? {
        if let i = displays.firstIndex(where: { $0.bounds.contains(point) }) { return i }
        return displays.indices.min { distance(point, displays[$0].bounds) < distance(point, displays[$1].bounds) }
    }

    private static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }

    private static func screenNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[CGDirectDisplayID(n.uint32Value)] = screen.localizedName
            }
        }
        return names
    }

    private static func uuidString(for id: CGDirectDisplayID) -> String {
        guard let unmanaged = CGDisplayCreateUUIDFromDisplayID(id) else { return "display-\(id)" }
        let uuid = unmanaged.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }
}
