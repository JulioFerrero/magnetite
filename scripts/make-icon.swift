// Renders the 1024px app icon: a magnetite crystal on a slate tile.
// Magnetite grows as octahedra: opaque, iron-black, metallic, often with
// triangular growth lines on the faces. The crystal is a real octahedron,
// turned and lit like polished metal (it reflects a bright sky and a dark
// ground, plus a key highlight). usage: swift make-icon.swift <out.png>
import AppKit

let out = CommandLine.arguments[1]
let size = 1024.0

// MARK: Vectors

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

// MARK: Octahedron

let corners = [V(x: 1, y: 0, z: 0), V(x: -1, y: 0, z: 0), V(x: 0, y: 1, z: 0), V(x: 0, y: -1, z: 0), V(x: 0, y: 0, z: 1), V(x: 0, y: 0, z: -1)]
let faces: [[Int]] = [[2, 4, 0], [2, 1, 4], [2, 5, 1], [2, 0, 5], [3, 0, 4], [3, 4, 1], [3, 1, 5], [3, 5, 0]]
let turned = corners.map { turn($0, yaw: 0.30, pitch: 0.26, roll: 0.08) }
func normal(_ f: [Int]) -> V {
    var n = norm(cross(turned[f[1]] - turned[f[0]], turned[f[2]] - turned[f[0]]))
    let centre = (turned[f[0]] + turned[f[1]] + turned[f[2]]) * (1.0 / 3)
    if dot(n, centre) < 0 { n = n * -1 }
    return n
}
let normals = faces.map(normal)
let visible = faces.indices.filter { normals[$0].z > 0.01 }

let xs = turned.map(\.x), ys = turned.map(\.y)
let scale = 600 / max(xs.max()! - xs.min()!, ys.max()! - ys.min()!)
let cx = (xs.max()! + xs.min()!) / 2, cy = (ys.max()! + ys.min()!) / 2
func screen(_ v: V) -> NSPoint { NSPoint(x: 512 + (v.x - cx) * scale, y: 512 + (v.y - cy) * scale) }

// MARK: Metal shading

let key = norm(V(x: -0.45, y: 0.8, z: 0.5))
let fill = norm(V(x: 0.85, y: -0.35, z: 0.45)) // a faint second light, low on the right
let halfway = norm(key + V(x: 0, y: 0, z: 1))
/// Iron-black to steel, with a faint cool tint; only glints reach near-white.
let ramp: [(Double, V)] = [
    (0.00, V(x: 0.03, y: 0.035, z: 0.04)), (0.25, V(x: 0.09, y: 0.10, z: 0.115)),
    (0.50, V(x: 0.22, y: 0.24, z: 0.27)), (0.70, V(x: 0.44, y: 0.47, z: 0.52)),
    (0.86, V(x: 0.72, y: 0.75, z: 0.80)), (1.00, V(x: 0.95, y: 0.96, z: 0.98)),
]
func steel(_ t: Double) -> NSColor {
    let t = min(1, max(0, t))
    var c = ramp.last!.1
    for i in 1..<ramp.count where t <= ramp[i].0 {
        let (t0, c0) = ramp[i - 1], (t1, c1) = ramp[i]
        c = c0 + (c1 - c0) * ((t - t0) / (t1 - t0))
        break
    }
    return NSColor(srgbRed: c.x, green: c.y, blue: c.z, alpha: 1)
}
/// Metal mostly shows what it reflects: a bright sky above, dark ground below.
func light(_ n: V) -> Double {
    let view = V(x: 0, y: 0, z: 1)
    let reflected = norm(n * (2 * dot(n, view)) - view)
    let sky = pow(max(0, reflected.y * 0.5 + 0.5), 2.2)
    return 0.10 + 0.42 * sky + 0.14 * pow(max(0, dot(n, key)), 2) + 0.62 * pow(max(0, dot(n, halfway)), 14)
        + 0.22 * pow(max(0, dot(n, fill)), 6)
}

func hex(_ h: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(h >> 16 & 0xFF) / 255, green: CGFloat(h >> 8 & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: alpha)
}

// MARK: Draw

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Tile: cool slate, lighter behind the crystal so the black stone separates
let tile = NSRect(x: 100, y: 100, width: size - 200, height: size - 200)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let drop = NSShadow()
drop.shadowColor = NSColor(white: 0, alpha: 0.4)
drop.shadowBlurRadius = 24
drop.shadowOffset = NSSize(width: 0, height: -10)
drop.set()
hex(0x1C1F24).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(starting: hex(0x4A515C), ending: hex(0x1A1D22))!.draw(in: shape, angle: -90)
NSGradient(colors: [hex(0x8C96A4, 0.22), hex(0x8C96A4, 0)])!
    .draw(fromCenter: NSPoint(x: 512, y: 540), radius: 0, toCenter: NSPoint(x: 512, y: 540), radius: 420, options: [])
NSGraphicsContext.restoreGraphicsState()

/// A face as a screen triangle, optionally shrunk toward its centre (growth lines).
func tri(_ f: [Int], shrink: Double = 1) -> NSBezierPath {
    let pts = f.map { screen(turned[$0]) }
    let c = NSPoint(x: pts.map(\.x).reduce(0, +) / 3, y: pts.map(\.y).reduce(0, +) / 3)
    let path = NSBezierPath()
    for (i, q) in pts.enumerated() {
        let s = NSPoint(x: c.x + (q.x - c.x) * shrink, y: c.y + (q.y - c.y) * shrink)
        i == 0 ? path.move(to: s) : path.line(to: s)
    }
    path.close()
    return path
}
let silhouette = NSBezierPath()
visible.forEach { silhouette.append(tri(faces[$0])) }

// Soft contact shadow under the crystal
NSGraphicsContext.saveGraphicsState()
let under = NSShadow()
under.shadowColor = NSColor(white: 0, alpha: 0.55)
under.shadowBlurRadius = 40
under.shadowOffset = NSSize(width: 0, height: -24)
under.set()
hex(0x0A0B0D).setFill()
silhouette.fill()
NSGraphicsContext.restoreGraphicsState()

for f in visible {
    let face = faces[f], n = normals[f]
    // Metal shows a strong gradient across a flat face: shade each corner with a
    // slightly bent normal and run the gradient from its darkest to lightest corner.
    let centre = (turned[face[0]] + turned[face[1]] + turned[face[2]]) * (1.0 / 3)
    let corner = face.map { i -> (NSPoint, Double) in
        (screen(turned[i]), light(norm(n + norm(turned[i] - centre) * 0.65)))
    }
    let bright = corner.max { $0.1 < $1.1 }!, dark = corner.min { $0.1 < $1.1 }!
    NSGraphicsContext.saveGraphicsState()
    tri(face).addClip()
    NSGradient(colors: [steel(dark.1), steel(light(n)), steel(bright.1)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(from: dark.0, to: bright.0, options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
    // Triangular growth lines, as on natural magnetite octahedra: faint, and
    // unevenly spaced like real growth layers
    for s in [0.86, 0.71, 0.50] {
        let line = tri(face, shrink: s)
        line.lineWidth = 1.6
        NSColor(white: 1, alpha: 0.045).setStroke()
        line.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
}

// Edges: polished ridges catch the light, strongest where they face the key
var edges: [String: [Int]] = [:]
for f in visible {
    let face = faces[f]
    for i in 0..<3 { let a = face[i], b = face[(i + 1) % 3]; edges["\(min(a, b))-\(max(a, b))", default: []].append(f) }
}
for (id, fs) in edges {
    let ends = id.split(separator: "-").map { Int($0)! }
    let edge = NSBezierPath()
    edge.move(to: screen(turned[ends[0]]))
    edge.line(to: screen(turned[ends[1]]))
    edge.lineCapStyle = .round
    let n = norm(fs.map { normals[$0] }.reduce(V(x: 0, y: 0, z: 0), +))
    edge.lineWidth = fs.count == 2 ? 2.5 : 3
    NSColor(white: 1, alpha: 0.10 + 0.55 * pow(max(0, dot(n, key)), 1.5)).setStroke()
    edge.stroke()
}

// Tile finish: hairline rim
let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
rim.lineWidth = 3
NSColor(white: 1, alpha: 0.10).setStroke()
rim.stroke()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
