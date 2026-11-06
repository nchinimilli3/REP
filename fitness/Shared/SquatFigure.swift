import SwiftUI

/// Glutes box squat drawn live in the style of `figure.cross.training`: round-capped limbs, a round head and a fixed box.
/// Every limb, joint and radius was measured from that glyph, so progress 0 is its pose; the pieces only rotate rigidly
/// about round joints, so the figure moves smoothly with no stretching or seams. Progress 1 is standing.
struct SquatFigure: Shape {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    // Rest (glyph) joints, as fractions of the square.
    private static let hip = CGPoint(x: 0.255, y: 0.485), knee = CGPoint(x: 0.523, y: 0.478), foot = CGPoint(x: 0.446, y: 0.721)
    private static let shoulder = CGPoint(x: 0.381, y: 0.297)

    func path(in rect: CGRect) -> Path {
        typealias F = FigureSketch
        let p = min(max(progress, 0), 1), s = FigureSketch(rect)
        let (h0, k0, f) = (Self.hip, Self.knee, Self.foot)

        // The foot stays planted. Leaving the box the weight shifts forward over the foot first, then the hip
        // drives up until the legs are straight with a soft knee.
        let hip = CGPoint(x: h0.x + 0.19 * sin(p * .pi / 2), y: h0.y - 0.282 * p)
        let knee = F.knee(hip: hip, foot: f, thigh: F.distance(h0, k0), shin: F.distance(k0, f))
        let lean = -0.55 * p
        let torso = { (q: CGPoint) in F.moved(q, about: h0, to: hip, by: lean) }
        // Arms reach forward to counterbalance at the bottom and lower once standing.
        let armAngle = 0.8 * p
        // Every round end sits on its own pivot, so turning a joint never shows a lump.
        let shoulder = torso(Self.shoulder)
        let arm = { (q: CGPoint) in F.moved(q, about: Self.shoulder, to: shoulder, by: armAngle) }

        return s.union([
            s.capsule(hip, 0.065, shoulder, 0.072),
            s.circle(torso(CGPoint(x: 0.461, y: 0.091)), 0.092),
            s.capsule(arm(CGPoint(x: 0.381, y: 0.272)), 0.045, arm(CGPoint(x: 0.787, y: 0.27)), 0.045),
            s.capsule(hip, 0.065, knee, 0.045),
            s.capsule(knee, 0.045, f, 0.044),
            s.rect(CGRect(x: 0.254, y: 0.803, width: 0.383, height: 0.194), corner: 0.035),
        ])
    }
}
