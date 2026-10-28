// Renders assets/icon.png (1024 px): white dashed-square symbol on an orange macOS-style rounded square.
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let tile = rect.insetBy(dx: 100, dy: 100)  // macOS icon grid: 824 px tile with transparent margin
    let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(srgbRed: 1.0, green: 0.66, blue: 0.22, alpha: 1),
               ending: NSColor(srgbRed: 0.98, green: 0.45, blue: 0.08, alpha: 1))?.draw(in: path, angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .regular)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "inset.filled.square.dashed", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height))
    }
    return true
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
