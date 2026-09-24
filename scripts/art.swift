import AppKit

struct V { var x, y, z: Double }
func + (a: V, b: V) -> V { V(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
func - (a: V, b: V) -> V { V(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
func * (a: V, s: Double) -> V { V(x: a.x * s, y: a.y * s, z: a.z * s) }
func dot(_ a: V, _ b: V) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
func cross(_ a: V, _ b: V) -> V { V(x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x) }
func norm(_ a: V) -> V { a * (1 / sqrt(dot(a, a))) }
func turn(_ p: V, yaw: Double, pitch: Double, roll: Double) -> V {
    var q = V(x: p.x * cos(yaw) + p.z * sin(yaw), y: p.y, z: -p.x * sin(yaw) + p.z * cos(yaw))
    q = V(x: q.x, y: q.y * cos(pitch) - q.z * sin(pitch), z: q.y * sin(pitch) + q.z * cos(pitch))
    return V(x: q.x * cos(roll) - q.y * sin(roll), y: q.x * sin(roll) + q.y * cos(roll), z: q.z)
}

let args = CommandLine.arguments, out = args[2]
let corners = [V(x: 1, y: 0, z: 0), V(x: -1, y: 0, z: 0), V(x: 0, y: 1, z: 0), V(x: 0, y: -1, z: 0), V(x: 0, y: 0, z: 1), V(x: 0, y: 0, z: -1)]
let faces = [[2, 4, 0], [2, 1, 4], [2, 5, 1], [2, 0, 5], [3, 0, 4], [3, 4, 1], [3, 1, 5], [3, 5, 0]]
let turned = corners.map { turn($0, yaw: 0.30, pitch: 0.26, roll: 0.08) }
func centre(_ f: [Int]) -> V { (turned[f[0]] + turned[f[1]] + turned[f[2]]) * (1.0 / 3) }
let normals = faces.map { f in
    let n = norm(cross(turned[f[1]] - turned[f[0]], turned[f[2]] - turned[f[0]]))
    return dot(n, centre(f)) < 0 ? n * -1 : n
}
let visible = faces.indices.filter { normals[$0].z > 0.01 }
let xs = turned.map(\.x), ys = turned.map(\.y), span = max(xs.max()! - xs.min()!, ys.max()! - ys.min()!)
let cx = (xs.max()! + xs.min()!) / 2, cy = (ys.max()! + ys.min()!) / 2

if args[1] == "logo" {
    let fill = "#" + args[3], gap = args.count > 4 ? Double(args[4])! : 22, scale = 440 / span
    func screen(_ v: V) -> (Double, Double) { (256 + (v.x - cx) * scale, 256 - (v.y - cy) * scale) }
    func inset(_ t: [(Double, Double)]) -> [(Double, Double)] {
        let a = hypot(t[1].0 - t[2].0, t[1].1 - t[2].1), b = hypot(t[0].0 - t[2].0, t[0].1 - t[2].1), c = hypot(t[0].0 - t[1].0, t[0].1 - t[1].1)
        let p = a + b + c, s = p / 2, r = sqrt((s - a) * (s - b) * (s - c) / s), k = (r - gap / 2) / r
        let incentre = ((a * t[0].0 + b * t[1].0 + c * t[2].0) / p, (a * t[0].1 + b * t[1].1 + c * t[2].1) / p)
        return t.map { (incentre.0 + ($0.0 - incentre.0) * k, incentre.1 + ($0.1 - incentre.1) * k) }
    }
    let polygons = visible.map { f in
        "    <polygon points=\"" + inset(faces[f].map { screen(turned[$0]) }).map { String(format: "%.1f,%.1f", $0.0, $0.1) }.joined(separator: " ") + "\"/>\n"
    }
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">"# + "\n"
        + "  <g fill=\"\(fill)\" stroke=\"\(fill)\" stroke-width=\"6\" stroke-linejoin=\"round\">\n" + polygons.joined() + "  </g>\n</svg>\n"
    try! svg.write(toFile: out, atomically: true, encoding: .utf8)
    exit(0)
}

let scale = 600 / span, key = norm(V(x: -0.45, y: 0.8, z: 0.5)), fillLight = norm(V(x: 0.85, y: -0.35, z: 0.45)), halfway = norm(key + V(x: 0, y: 0, z: 1))
func screen(_ v: V) -> NSPoint { NSPoint(x: 512 + (v.x - cx) * scale, y: 512 + (v.y - cy) * scale) }
let ramp: [(Double, V)] = [
    (0.00, V(x: 0.03, y: 0.035, z: 0.04)), (0.25, V(x: 0.09, y: 0.10, z: 0.115)), (0.50, V(x: 0.22, y: 0.24, z: 0.27)),
    (0.70, V(x: 0.44, y: 0.47, z: 0.52)), (0.86, V(x: 0.72, y: 0.75, z: 0.80)), (1.00, V(x: 0.95, y: 0.96, z: 0.98)),
]
func steel(_ t: Double) -> NSColor {
    let t = min(1, max(0, t)), i = ramp.firstIndex { t <= $0.0 } ?? ramp.count - 1
    let c = i == 0 ? ramp[0].1 : ramp[i - 1].1 + (ramp[i].1 - ramp[i - 1].1) * ((t - ramp[i - 1].0) / (ramp[i].0 - ramp[i - 1].0))
    return NSColor(srgbRed: c.x, green: c.y, blue: c.z, alpha: 1)
}
func light(_ n: V) -> Double {
    let view = V(x: 0, y: 0, z: 1), reflected = norm(n * (2 * dot(n, view)) - view)
    return 0.10 + 0.42 * pow(max(0, reflected.y * 0.5 + 0.5), 2.2) + 0.14 * pow(max(0, dot(n, key)), 2)
        + 0.62 * pow(max(0, dot(n, halfway)), 14) + 0.22 * pow(max(0, dot(n, fillLight)), 6)
}
func hex(_ h: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(h >> 16 & 0xFF) / 255, green: CGFloat(h >> 8 & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: alpha)
}
func shadowed(_ color: NSColor, blur: CGFloat, y: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    (shadow.shadowColor, shadow.shadowBlurRadius, shadow.shadowOffset) = (color, blur, NSSize(width: 0, height: y))
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}
func tri(_ f: [Int], shrink: Double = 1) -> NSBezierPath {
    let pts = f.map { screen(turned[$0]) }, c = NSPoint(x: pts.map(\.x).reduce(0, +) / 3, y: pts.map(\.y).reduce(0, +) / 3), path = NSBezierPath()
    path.move(to: NSPoint(x: c.x + (pts[0].x - c.x) * shrink, y: c.y + (pts[0].y - c.y) * shrink))
    pts.dropFirst().forEach { path.line(to: NSPoint(x: c.x + ($0.x - c.x) * shrink, y: c.y + ($0.y - c.y) * shrink)) }
    path.close()
    return path
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let tile = NSRect(x: 100, y: 100, width: 824, height: 824), shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
shadowed(NSColor(white: 0, alpha: 0.4), blur: 24, y: -10) {
    hex(0x1C1F24).setFill()
    shape.fill()
}
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(starting: hex(0x4A515C), ending: hex(0x1A1D22))!.draw(in: shape, angle: -90)
NSGradient(colors: [hex(0x8C96A4, 0.22), hex(0x8C96A4, 0)])!.draw(fromCenter: NSPoint(x: 512, y: 540), radius: 0, toCenter: NSPoint(x: 512, y: 540), radius: 420, options: [])
NSGraphicsContext.restoreGraphicsState()
let silhouette = NSBezierPath()
visible.forEach { silhouette.append(tri(faces[$0])) }
shadowed(NSColor(white: 0, alpha: 0.55), blur: 40, y: -24) {
    hex(0x0A0B0D).setFill()
    silhouette.fill()
}
for f in visible {
    let face = faces[f], n = normals[f]
    let corner = face.map { (screen(turned[$0]), light(norm(n + norm(turned[$0] - centre(face)) * 0.65))) }
    let bright = corner.max { $0.1 < $1.1 }!, dark = corner.min { $0.1 < $1.1 }!
    NSGraphicsContext.saveGraphicsState()
    tri(face).addClip()
    NSGradient(colors: [steel(dark.1), steel(light(n)), steel(bright.1)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(from: dark.0, to: bright.0, options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
    NSColor(white: 1, alpha: 0.045).setStroke()
    for s in [0.86, 0.71, 0.50] {
        let line = tri(face, shrink: s)
        line.lineWidth = 1.6
        line.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
}
var edges: [[Int]: [Int]] = [:]
for f in visible { for i in 0..<3 { edges[[faces[f][i], faces[f][(i + 1) % 3]].sorted(), default: []].append(f) } }
for (ends, fs) in edges.sorted(by: { $0.key.lexicographicallyPrecedes($1.key) }) {
    let edge = NSBezierPath(), n = norm(fs.map { normals[$0] }.reduce(V(x: 0, y: 0, z: 0), +))
    edge.move(to: screen(turned[ends[0]]))
    edge.line(to: screen(turned[ends[1]]))
    (edge.lineCapStyle, edge.lineWidth) = (.round, fs.count == 2 ? 2.5 : 3)
    NSColor(white: 1, alpha: 0.10 + 0.55 * pow(max(0, dot(n, key)), 1.5)).setStroke()
    edge.stroke()
}
let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
rim.lineWidth = 3
NSColor(white: 1, alpha: 0.10).setStroke()
rim.stroke()
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
