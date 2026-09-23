// Renders the 1024px app icon: a pixel-art topaz on a Workbench-blue glass tile.
// The gem is drawn on a tiny 40×40 grid in a 7-colour palette (Amiga style: a lot
// from very little), then scaled up with hard pixel edges.
import AppKit

let out = CommandLine.arguments[1]
let size = 1024.0

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// MARK: Pixel gem

let grid = 40
let gem = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: grid, pixelsHigh: grid, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let gemContext = NSGraphicsContext(bitmapImageRep: gem)!
gemContext.shouldAntialias = false
gemContext.cgContext.setShouldAntialias(false)
NSGraphicsContext.current = gemContext

// Cut outline (y up): table on top, crown down to the girdle, pavilion to the point.
let tableL = NSPoint(x: 13, y: 33), tableR = NSPoint(x: 27, y: 33)
let girdleL = NSPoint(x: 4, y: 25), girdleR = NSPoint(x: 36, y: 25)
let crownL = NSPoint(x: 9, y: 25), crownM = NSPoint(x: 20, y: 25), crownR = NSPoint(x: 31, y: 25)
let point = NSPoint(x: 20, y: 3)

func facet(_ points: [NSPoint], _ hex: UInt32) {
    let path = NSBezierPath()
    path.move(to: points[0])
    points.dropFirst().forEach { path.line(to: $0) }
    path.close()
    color(hex).setFill()
    path.fill()
}

// Palette: highlight, light, mid, deep, shadow (topaz amber), plus outline and sparkle.
let highlight: UInt32 = 0xFFE3A1, light: UInt32 = 0xFFC04D, mid: UInt32 = 0xFF9A1F, deep: UInt32 = 0xE67300, shadow: UInt32 = 0xB35200
// Crown
facet([tableL, tableR, crownM], highlight)
facet([tableL, crownM, crownL], light)
facet([tableR, crownR, crownM], mid)
facet([tableL, crownL, girdleL], mid)
facet([tableR, girdleR, crownR], deep)
// Pavilion, with a narrow reflection down the left side
facet([girdleL, crownL, point], light)
facet([crownL, crownM, point], mid)
facet([crownM, crownR, point], deep)
facet([crownR, girdleR, point], shadow)
facet([crownL, NSPoint(x: 12, y: 25), NSPoint(x: 19, y: 7)], highlight)
gemContext.flushGraphics() // pixels edited below must see the drawing
NSGraphicsContext.restoreGraphicsState()

// Pixel-art outline: every gem pixel touching empty space becomes the dark
// edge colour, so the silhouette is a clean one-pixel line. Raw RGBA bytes,
// rows counted from the top.
let pixels = gem.bitmapData!, rowBytes = gem.bytesPerRow
func alpha(_ x: Int, _ y: Int) -> UInt8 {
    guard (0..<grid).contains(x), (0..<grid).contains(y) else { return 0 }
    return pixels[y * rowBytes + x * 4 + 3]
}
func paint(_ x: Int, _ y: Int, _ hex: UInt32) {
    let i = y * rowBytes + x * 4
    (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]) = (UInt8(hex >> 16 & 0xFF), UInt8(hex >> 8 & 0xFF), UInt8(hex & 0xFF), 255)
}
var edge: [(Int, Int)] = []
for y in 0..<grid {
    for x in 0..<grid where alpha(x, y) > 0 {
        if [(1, 0), (-1, 0), (0, 1), (0, -1)].contains(where: { alpha(x + $0.0, y + $0.1) == 0 }) { edge.append((x, y)) }
    }
}
edge.forEach { paint($0.0, $0.1, 0x5A2600) }
// Pixel sparkle: a 4-point star on the table
for (x, y) in [(24, 7), (24, 8), (24, 9), (24, 10), (24, 11), (22, 9), (23, 9), (25, 9), (26, 9)] { paint(x, y, 0xFFFFFF) }

// MARK: Tile

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let tile = NSRect(x: 100, y: 100, width: size - 200, height: size - 200)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let drop = NSShadow()
drop.shadowColor = .black.withAlphaComponent(0.35)
drop.shadowBlurRadius = 24
drop.shadowOffset = NSSize(width: 0, height: -10)
drop.set()
color(0x0055AA).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

// Workbench blue, a little deeper at the bottom
NSGradient(starting: color(0x1A6FCC), ending: color(0x003F85))!.draw(in: shape, angle: -90)

// Gem, scaled up with hard edges and a soft glow behind it
NSGraphicsContext.saveGraphicsState()
let glow = NSShadow()
glow.shadowColor = color(0xFF9A1F, 0.55)
glow.shadowBlurRadius = 70
glow.set()
NSGraphicsContext.current?.imageInterpolation = .none
let gemSize = 600.0
let gemImage = NSImage(size: NSSize(width: grid, height: grid))
gemImage.addRepresentation(gem)
gemImage.draw(in: NSRect(x: (size - gemSize) / 2, y: (size - gemSize) / 2 - 10, width: gemSize, height: gemSize),
              from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

// Glass: a soft shine over the top half and a thin light rim
NSGraphicsContext.saveGraphicsState()
shape.addClip()
let shine = NSBezierPath(roundedRect: NSRect(x: tile.minX - 40, y: tile.midY + 40, width: tile.width + 80, height: tile.height),
                         xRadius: 400, yRadius: 260)
NSGradient(starting: color(0xFFFFFF, 0.22), ending: color(0xFFFFFF, 0.0))!.draw(in: shine, angle: -90)
NSGraphicsContext.restoreGraphicsState()
let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 3, dy: 3), xRadius: 182, yRadius: 182)
rim.lineWidth = 6
NSGradient(starting: color(0xFFFFFF, 0.45), ending: color(0xFFFFFF, 0.05))!.draw(in: rim.cgPathStroked(width: 6), angle: -90)

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))

extension NSBezierPath {
    /// The outline of this path's stroke, as a fillable path.
    func cgPathStroked(width: CGFloat) -> NSBezierPath {
        let stroked = cgPath.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        return NSBezierPath(cgPath: stroked)
    }
}
