#!/usr/bin/env swift
// Generates Resources/AppIcon.icns: a white mic glyph on an indigo rounded tile.
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = "build-app/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let size = NSSize(width: px, height: px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Rounded-rect background with a subtle vertical gradient.
    let inset = CGFloat(px) * 0.08
    let rect = NSRect(x: inset, y: inset, width: CGFloat(px) - inset * 2, height: CGFloat(px) - inset * 2)
    let radius = rect.width * 0.22
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.40, green: 0.36, blue: 0.92, alpha: 1),
        NSColor(calibratedRed: 0.30, green: 0.24, blue: 0.78, alpha: 1),
    ])!
    gradient.draw(in: path, angle: -90)

    // White mic glyph, centered.
    let cfg = NSImage.SymbolConfiguration(pointSize: CGFloat(px) * 0.52, weight: .semibold)
    if let sym = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: sym.size)
        tinted.lockFocus()
        sym.draw(at: .zero, from: NSRect(origin: .zero, size: sym.size), operation: .sourceOver, fraction: 1)
        NSColor.white.set()
        NSRect(origin: .zero, size: sym.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let s = tinted.size
        let origin = NSPoint(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2)
        tinted.draw(at: origin, from: NSRect(origin: .zero, size: s), operation: .sourceOver, fraction: 1)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for px in sizes {
    let data = render(px)
    let base = px / 2
    switch px {
    case 16, 32, 128, 256, 512:
        try! data.write(to: URL(fileURLWithPath: "\(iconset)/icon_\(px)x\(px).png"))
    default: break
    }
    if [32, 64, 256, 512, 1024].contains(px) {
        try! data.write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)@2x.png"))
    }
}
print("wrote \(iconset)")
