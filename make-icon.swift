// Renders the 1024×1024 app icon: `swift make-icon.swift icon-1024.png`
import AppKit

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Apple's macOS icon grid: an 824 pt body with a 100 pt margin.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.set()
NSColor.white.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colors: [
    NSColor(srgbRed: 1.00, green: 0.80, blue: 0.30, alpha: 1),
    NSColor(srgbRed: 1.00, green: 0.55, blue: 0.16, alpha: 1),
    NSColor(srgbRed: 0.93, green: 0.33, blue: 0.20, alpha: 1),
])!.draw(in: shape, angle: -90)

// Soft highlight in the upper half for depth.
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
NSGraphicsContext.restoreGraphicsState()

let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
let sun = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
let sunRect = NSRect(
    x: body.midX - sun.size.width / 2, y: body.midY - sun.size.height / 2,
    width: sun.size.width, height: sun.size.height
)
NSGraphicsContext.saveGraphicsState()
let glow = NSShadow()
glow.shadowOffset = NSSize(width: 0, height: -6)
glow.shadowBlurRadius = 18
glow.shadowColor = NSColor(srgbRed: 0.6, green: 0.2, blue: 0.0, alpha: 0.35)
glow.set()
sun.draw(in: sunRect)
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
