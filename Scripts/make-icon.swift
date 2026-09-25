// Generates an AppIcon.iconset for Keryx: a rounded teal tile with a white
// caduceus glyph. Run on a macOS runner:
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

// Caduceus geometry in a 16×16 unit space, y-down (flipped context).
func drawCaduceus(px: CGFloat, color: NSColor) {
    let s = px / 16.0
    color.setStroke()
    color.setFill()

    func path(_ points: [(CGFloat, CGFloat)], _ width: CGFloat) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: points[0].0 * s, y: points[0].1 * s))
        for point in points.dropFirst() {
            p.line(to: NSPoint(x: point.0 * s, y: point.1 * s))
        }
        p.lineWidth = width * s
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.stroke()
    }
    func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        NSBezierPath(ovalIn: NSRect(x: (x - r) * s, y: (y - r) * s,
                                    width: 2 * r * s, height: 2 * r * s)).fill()
    }
    func snake(phase: Double) -> [(CGFloat, CGFloat)] {
        let n = 60
        return (0...n).map { i in
            let t = Double(i) / Double(n)
            let y = 5.4 + t * 7.6
            let x = 8.0 + 2.1 * sin(t * .pi * 2.1 + phase)
            return (CGFloat(x), CGFloat(y))
        }
    }

    dot(8, 1.7, 1.05)
    path([(8, 2.9), (8, 15.1)], 1.35)
    for side in [-1.0, 1.0] {
        path([(8 + side * 0.6, 3.6), (8 + side * 3.4, 2.2), (8 + side * 4.9, 1.5)], 1.1)
        path([(8 + side * 0.6, 4.8), (8 + side * 2.9, 3.9), (8 + side * 4.3, 3.9)], 1.1)
    }
    let snakeA = snake(phase: 0)
    let snakeB = snake(phase: .pi)
    path(snakeA, 1.15)
    path(snakeB, 1.15)
    dot(snakeA.last!.0 + 0.35, snakeA.last!.1 + 0.1, 0.8)
    dot(snakeB.last!.0 - 0.35, snakeB.last!.1 + 0.1, 0.8)
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

    // White caduceus centered on the tile, ~58% of the tile edge.
    let glyphEdge = px * 0.58
    let whiteCaduceus = NSImage(size: NSSize(width: glyphEdge, height: glyphEdge), flipped: true) { _ in
        drawCaduceus(px: glyphEdge, color: .white)
        return true
    }
    let drawRect = NSRect(
        x: (px - glyphEdge) / 2, y: (px - glyphEdge) / 2,
        width: glyphEdge, height: glyphEdge
    )
    whiteCaduceus.draw(in: drawRect)

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("error: PNG encoding failed for \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    try png.write(to: URL(fileURLWithPath: outputDir).appendingPathComponent(name))
}

print("iconset written to \(outputDir)")