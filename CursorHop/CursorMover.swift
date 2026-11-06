import AppKit
import CoreGraphics

enum JumpDirection {
    case next, previous
}

enum CursorMover {
    /// Current cursor position in global CG coordinates (top-left origin).
    static var currentLocation: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    static func jump(_ direction: JumpDirection) {
        let displays = DisplayManager.displays()
        guard displays.count > 1 else { return }
        let p = currentLocation
        let current = DisplayManager.index(containing: p, in: displays) ?? 0
        let target: Int
        switch direction {
        case .next:     target = (current + 1) % displays.count
        case .previous: target = (current - 1 + displays.count) % displays.count
        }
        move(from: displays[current], at: p, to: displays[target])
    }

    static func jump(toDisplayAt index: Int) {
        let displays = DisplayManager.displays()
        guard displays.indices.contains(index) else { return }
        let p = currentLocation
        let current = DisplayManager.index(containing: p, in: displays)
        guard current != index else { return }
        move(from: current.map { displays[$0] }, at: p, to: displays[index])
    }

    private static func move(from source: Display?, at point: CGPoint, to destination: Display) {
        if let source { PositionMemory.save(point, on: source) }
        let target = PositionMemory.point(for: destination)
            ?? CGPoint(x: destination.bounds.midX, y: destination.bounds.midY)

        CGWarpMouseCursorPosition(target)
        // Warping briefly decouples the mouse from the cursor (~0.25 s of
        // "frozen" cursor). Re-associating immediately removes that lag.
        CGAssociateMouseAndMouseCursorPosition(1)

        FocusManager.focusWindow(at: target, on: destination)
    }
}
