// Generates an AppIcon.iconset for Keryx: a rounded teal tile with a white
// tray glyph. Run on a macOS runner:
//   swift Scripts/make-icon.swift <output-iconset-dir>
// then convert with: iconutil -c icns <dir> -o AppIcon.icns
import AppKit

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.iconset"

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

// White-tinted copy of the template glyph (destinationIn keeps the glyph's alpha).
func whiteGlyph(_ image: NSImage, size: NSSize) -> NSImage {
    let result = NSImage(size: size, flipped: false) { rect in
        NSColor.white.setFill()
        rect.fill()
        image.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
        return true
    }
    result.isTemplate = false
    return result
}

try FileManager.default.createDirectory(
    atPath: outputDir, withIntermediateDirectories: true)

for (name, pixels) in sizes {
    let px = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: px, height: px)
    let inset = px * 0.08
    let tile = NSBezierPath(
        roundedRect: rect.insetBy(dx: inset, dy: inset),
        xRadius: px * 0.22, yRadius: px * 0.22
    )
    // Vertical gradient tile, Keryx teal.
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.58, alpha: 1),
        ending: NSColor(calibratedRed: 0.09, green: 0.42, blue: 0.48, alpha: 1)
    )!
    gradient.draw(in: tile, angle: -90)

    if let base = NSImage(systemSymbolName: "tray", accessibilityDescription: nil) {
        let configured = base.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: px * 0.42, weight: .medium)
        ) ?? base
        let glyphSize = configured.size
        let scale = min((px * 0.52) / glyphSize.width, (px * 0.52) / glyphSize.height)
        let drawSize = NSSize(width: glyphSize.width * scale, height: glyphSize.height * scale)
        let drawRect = NSRect(
            x: (px - drawSize.width) / 2, y: (px - drawSize.height) / 2,
            width: drawSize.width, height: drawSize.height
        )
        let glyph = whiteGlyph(configured, size: drawSize)
        glyph.draw(in: drawRect)
    } else {
        // Defensive: symbol unavailable — fall back to a plain tile.
        FileHandle.standardError.write("warning: tray symbol unavailable\n".data(using: .utf8)!)
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("error: PNG encoding failed for \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    try png.write(to: URL(fileURLWithPath: outputDir).appendingPathComponent(name))
}

print("iconset written to \(outputDir)")