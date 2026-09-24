// Writes the one-colour Magnetite mark as SVG: the same octahedron as the app
// icon (same turn), its four visible faces as solid shapes separated by even gaps.
// usage: swift make-logo.swift <out.svg> <hex colour, e.g. 111111>
import Foundation

let out = CommandLine.arguments[1]
let fill = "#" + CommandLine.arguments[2]

struct V { var x, y, z: Double }
func - (a: V, b: V) -> V { V(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
func cross(_ a: V, _ b: V) -> V { V(x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x) }
func turn(_ p: V, yaw: Double, pitch: Double, roll: Double) -> V {
    var q = V(x: p.x * cos(yaw) + p.z * sin(yaw), y: p.y, z: -p.x * sin(yaw) + p.z * cos(yaw))
    q = V(x: q.x, y: q.y * cos(pitch) - q.z * sin(pitch), z: q.y * sin(pitch) + q.z * cos(pitch))
    return V(x: q.x * cos(roll) - q.y * sin(roll), y: q.x * sin(roll) + q.y * cos(roll), z: q.z)
}

// Same octahedron and orientation as scripts/make-icon.swift
let corners = [V(x: 1, y: 0, z: 0), V(x: -1, y: 0, z: 0), V(x: 0, y: 1, z: 0), V(x: 0, y: -1, z: 0), V(x: 0, y: 0, z: 1), V(x: 0, y: 0, z: -1)]
let faces: [[Int]] = [[2, 4, 0], [2, 1, 4], [2, 5, 1], [2, 0, 5], [3, 0, 4], [3, 4, 1], [3, 1, 5], [3, 5, 0]]
let turned = corners.map { turn($0, yaw: 0.30, pitch: 0.26, roll: 0.08) }
let visible = faces.filter { f in
    var n = cross(turned[f[1]] - turned[f[0]], turned[f[2]] - turned[f[0]])
    let c = V(x: f.map { turned[$0].x }.reduce(0, +), y: f.map { turned[$0].y }.reduce(0, +), z: f.map { turned[$0].z }.reduce(0, +))
    if n.x * c.x + n.y * c.y + n.z * c.z < 0 { n = V(x: -n.x, y: -n.y, z: -n.z) }
    return n.z > 0.01
}

// Fit into a 512 box with padding (SVG y points down)
let xs = turned.map(\.x), ys = turned.map(\.y)
let span = max(xs.max()! - xs.min()!, ys.max()! - ys.min()!)
let scale = 440 / span, cx = (xs.max()! + xs.min()!) / 2, cy = (ys.max()! + ys.min()!) / 2
func screen(_ v: V) -> (Double, Double) { (256 + (v.x - cx) * scale, 256 - (v.y - cy) * scale) }

/// Shrinks a triangle about its incentre so every edge moves in by `gap / 2`,
/// leaving an even gap between neighbouring faces.
func inset(_ t: [(Double, Double)], gap: Double) -> [(Double, Double)] {
    func dist(_ a: (Double, Double), _ b: (Double, Double)) -> Double { hypot(a.0 - b.0, a.1 - b.1) }
    let a = dist(t[1], t[2]), b = dist(t[0], t[2]), c = dist(t[0], t[1]), p = a + b + c
    let incentre = ((a * t[0].0 + b * t[1].0 + c * t[2].0) / p, (a * t[0].1 + b * t[1].1 + c * t[2].1) / p)
    let s = p / 2, r = sqrt((s - a) * (s - b) * (s - c) / s)
    let k = (r - gap / 2) / r
    return t.map { (incentre.0 + ($0.0 - incentre.0) * k, incentre.1 + ($0.1 - incentre.1) * k) }
}

var svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">"# + "\n"
svg += "  <g fill=\"\(fill)\" stroke=\"\(fill)\" stroke-width=\"6\" stroke-linejoin=\"round\">\n"
for f in visible {
    let pts = inset(f.map { screen(turned[$0]) }, gap: 22)
    svg += "    <polygon points=\"" + pts.map { String(format: "%.1f,%.1f", $0.0, $0.1) }.joined(separator: " ") + "\"/>\n"
}
svg += "  </g>\n</svg>\n"
try! svg.write(toFile: out, atomically: true, encoding: .utf8)
