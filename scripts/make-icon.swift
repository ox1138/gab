#!/usr/bin/env swift
// Generates Resources/AppIcon.icns from Resources/AppIcon.png (the app logo).
import AppKit

let source = "Resources/AppIcon.png"
let iconset = "build-app/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

guard let src = NSImage(contentsOfFile: source) else {
    fputs("error: could not load \(source)\n", stderr)
    exit(1)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 0, y: 0, width: px, height: px)
    src.draw(in: rect, from: NSRect(origin: .zero, size: src.size),
             operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for px in [16, 32, 128, 256, 512] {
    try! render(px).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(px)x\(px).png"))
    try! render(px * 2).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(px)x\(px)@2x.png"))
}
print("wrote \(iconset) — run: iconutil -c icns \(iconset) -o Resources/AppIcon.icns")
