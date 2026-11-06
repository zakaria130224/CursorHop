// Generates CursorHop/AppIcon.icns from scripts/icon_source.png
// (black artwork inside a black ring, on a white background).
//
//   swift scripts/make_icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("scripts/icon_source.png")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
let output = root.appendingPathComponent("CursorHop/AppIcon.icns")

guard let sourceRep = NSImage(contentsOf: source)?.representations.first as? NSBitmapImageRep ?? {
    NSImage(contentsOf: source)?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
}() else { fatalError("Can't read \(source.path)") }

let srcW = sourceRep.pixelsWide
let srcH = sourceRep.pixelsHigh

func luminance(_ x: Int, _ y: Int) -> CGFloat {
    guard let c = sourceRep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return 1 }
    return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
}

// The ring is the outermost artwork, so the bounding box of dark pixels gives
// its centre and outer radius.
var minX = srcW, minY = srcH, maxX = 0, maxY = 0
for y in 0..<srcH {
    for x in 0..<srcW where luminance(x, y) < 0.5 {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
let ringCenter = CGPoint(x: CGFloat(minX + maxX + 1) / 2, y: CGFloat(minY + maxY + 1) / 2)
let ringRadius = CGFloat(max(maxX - minX + 1, maxY - minY + 1)) / 2

// Turn the artwork into black ink with alpha = darkness, so the white
// background disappears and edges stay anti-aliased.
guard let ink = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: srcW, pixelsHigh: srcH,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
else { fatalError("alloc failed") }
let inkColor = (r: 0.0, g: 0.0, b: 0.0)
for y in 0..<srcH {
    for x in 0..<srcW {
        let alpha = max(0, min(1, (1 - luminance(x, y)) * 1.05))
        ink.setColor(NSColor(deviceRed: inkColor.r, green: inkColor.g, blue: inkColor.b, alpha: alpha), atX: x, y: y)
    }
}
let inkImage = NSImage(size: NSSize(width: srcW, height: srcH))
inkImage.addRepresentation(ink)

/// Draws the icon on a 1024×1024 canvas: a white disc (824 pt, the macOS icon
/// grid's circle) with the ring and cursor on top and a soft shadow below.
func renderIcon(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    rep.size = NSSize(width: 1024, height: 1024)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    let disc = NSRect(x: 100, y: 100, width: 824, height: 824)
    let scale = disc.width / (ringRadius * 2)

    // White disc with drop shadow, slightly inside the ring so no white peeks out.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: disc.insetBy(dx: 4, dy: 4)).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Artwork scaled so the ring fills the disc. Source y runs top-down.
    let drawRect = NSRect(x: disc.midX - ringCenter.x * scale,
                          y: disc.midY - (CGFloat(srcH) - ringCenter.y) * scale,
                          width: CGFloat(srcW) * scale, height: CGFloat(srcH) * scale)
    inkImage.draw(in: drawRect)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        guard let png = renderIcon(pixels: points * scale) else { fatalError("render failed") }
        try png.write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(output.path)")
