// Renders the app icon PNGs into App/Assets.xcassets: an SF Symbol on a macOS-style rounded square.
// Usage: swift scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = size / 1024
    // Apple's macOS icon grid: 824pt body centred in a 1024pt canvas, ~185pt corner radius.
    let body = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let path = NSBezierPath(roundedRect: body, xRadius: 185 * scale, yRadius: 185 * scale)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 20 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -8 * scale)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(srgbRed: 0.35, green: 0.68, blue: 1.0, alpha: 1),
                        NSColor(srgbRed: 0.04, green: 0.40, blue: 0.95, alpha: 1)])!
        .draw(in: path, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: 440 * scale, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2 + 30 * scale, width: s.width, height: s.height))
    }
    if let sparkle = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 230 * scale, weight: .semibold)
            .applying(.init(paletteColors: [.white]))) {
        let s = sparkle.size
        sparkle.draw(in: NSRect(x: 600 * scale, y: 560 * scale, width: s.width, height: s.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let catalog = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset")
try fm.createDirectory(at: catalog, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: CGFloat(base)).write(to: catalog.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: CGFloat(base * 2)).write(to: catalog.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("Wrote \(catalog.path)")
