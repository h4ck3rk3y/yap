// Renders Resources/AppIcon.icns.  Usage: swift scripts/make-icon.swift
import AppKit

func drawIcon(size px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824pt rounded square centred on a 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    ctx.addPath(tilePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let colors = [NSColor(red: 1.00, green: 0.60, blue: 0.25, alpha: 1).cgColor,
                  NSColor(red: 0.98, green: 0.24, blue: 0.43, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 200, y: 924), end: CGPoint(x: 824, y: 100), options: [])
    ctx.restoreGState()

    // Speech bubble with a tail at bottom-left.
    let bubble = CGMutablePath()
    bubble.addRoundedRect(in: CGRect(x: 232, y: 330, width: 560, height: 400), cornerWidth: 140, cornerHeight: 140)
    bubble.move(to: CGPoint(x: 300, y: 380))
    bubble.addQuadCurve(to: CGPoint(x: 250, y: 250), control: CGPoint(x: 300, y: 300))
    bubble.addQuadCurve(to: CGPoint(x: 420, y: 340), control: CGPoint(x: 360, y: 280))
    bubble.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor.black.withAlphaComponent(0.15).cgColor)
    ctx.addPath(bubble)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Waveform bars inside the bubble.
    let heights: [CGFloat] = [90, 190, 260, 170, 110]
    let barWidth: CGFloat = 46, gap: CGFloat = 28
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = 512 - total / 2
    ctx.setFillColor(NSColor(red: 0.98, green: 0.36, blue: 0.36, alpha: 1).cgColor)
    for h in heights {
        let bar = CGRect(x: x, y: 530 - h / 2, width: barWidth, height: h)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        ctx.fillPath()
        x += barWidth + gap
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: base * scale).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}

let out = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try iconutil.run()
iconutil.waitUntilExit()
print("Wrote \(out.path)")
