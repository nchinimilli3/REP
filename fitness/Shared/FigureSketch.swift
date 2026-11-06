import SwiftUI

/// Draws SF-Symbol-style figure pieces (round heads, round-capped limbs, knockout gaps) from unit coordinates,
/// scaled into the largest square centred in a rect. The live-drawn workout figures share it.
struct FigureSketch {
    let origin: CGPoint
    let side: Double

    init(_ rect: CGRect) {
        side = min(rect.width, rect.height)
        origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
    }

    func circle(_ c: CGPoint, _ r: Double) -> Path {
        polygon((0..<64).map { i in CGPoint(x: c.x + r * cos(Double(i) * .pi / 32), y: c.y + r * sin(Double(i) * .pi / 32)) })
    }

    /// The convex hull of two circles: a limb that may taper from one end to the other.
    func capsule(_ a: CGPoint, _ ra: Double, _ b: CGPoint, _ rb: Double) -> Path {
        let theta = Self.angle(a, b), alpha = acos(min(max((ra - rb) / max(Self.distance(a, b), 0.0001), -1), 1))
        let arc = { (c: CGPoint, r: Double, from: Double, to: Double) in
            (0...24).map { i -> CGPoint in let t = from + (to - from) * Double(i) / 24; return CGPoint(x: c.x + r * cos(t), y: c.y + r * sin(t)) }
        }
        return polygon(arc(b, rb, theta - alpha, theta + alpha) + arc(a, ra, theta + alpha, theta + 2 * .pi - alpha))
    }

    func rect(_ r: CGRect, corner: Double) -> Path {
        Path(roundedRect: CGRect(x: origin.x + r.minX * side, y: origin.y + r.minY * side, width: r.width * side, height: r.height * side),
             cornerRadius: corner * side, style: .continuous)
    }

    func union(_ pieces: [Path]) -> Path {
        pieces.dropFirst().reduce(pieces[0]) { $0.union($1) }
    }

    /// Apple's knockout: clears a thin gap around `front` so the part behind it reads as passing underneath.
    func knockout(_ behind: Path, by front: Path, gap: Double) -> Path {
        behind.subtracting(front.union(front.strokedPath(StrokeStyle(lineWidth: 2 * gap * side, lineJoin: .round))))
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        Path { $0.addLines(points.map { CGPoint(x: origin.x + $0.x * side, y: origin.y + $0.y * side) }); $0.closeSubpath() }
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(b.x - a.x, b.y - a.y) }
    static func angle(_ a: CGPoint, _ b: CGPoint) -> Double { atan2(b.y - a.y, b.x - a.x) }

    /// Rigidly carries `c` from a frame pivoting at `o` to one pivoting at `d`, turned by `a` radians.
    static func moved(_ c: CGPoint, about o: CGPoint, to d: CGPoint, by a: Double) -> CGPoint {
        CGPoint(x: d.x + (c.x - o.x) * cos(a) - (c.y - o.y) * sin(a), y: d.y + (c.x - o.x) * sin(a) + (c.y - o.y) * cos(a))
    }

    /// Two-bone joint with fixed bone lengths, bending to the left of the hip-to-foot direction (forward for these figures).
    static func knee(hip: CGPoint, foot: CGPoint, thigh: Double, shin: Double) -> CGPoint {
        let dx = foot.x - hip.x, dy = foot.y - hip.y
        let d = min(hypot(dx, dy), thigh + shin - 0.0001)
        let a = (thigh * thigh - shin * shin + d * d) / (2 * d)
        let h = sqrt(max(thigh * thigh - a * a, 0))
        return CGPoint(x: hip.x + (a * dx + h * dy) / d, y: hip.y + (a * dy - h * dx) / d)
    }
}
