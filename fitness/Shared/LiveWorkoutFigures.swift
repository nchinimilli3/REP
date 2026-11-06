import SwiftUI

// Back, Legs and Abs drawn live like `SquatFigure`. Every head, limb, joint and radius was pixel-fitted to its
// Apple glyph, so progress 0 is exactly that glyph and the static symbol can stand in for it. Pieces only turn
// rigidly about round joints, so nothing stretches or seams while moving.

/// Back + Biceps barbell curl in the style of `figure.strengthtraining.traditional`, seen from the front. Progress 0 is
/// the glyph with the bar at the thighs. The upper arms stay pinned to the sides while each forearm swings up toward the
/// viewer, so only its vertical length shortens, as a real curl looks head-on, and the bar rises with the hands.
/// Where the bar passes in front of the torso and upper arms, Apple's knockout gap keeps it reading as in front.
struct CurlFigure: Shape {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let p = min(max(progress, 0), 1), s = FigureSketch(rect), c = 0.474
        // About 130 degrees of elbow flexion; the hands hold the bar 0.05 below its centre line.
        let handY = 0.4387 + 0.1413 * cos(2.27 * p), barY = handY - 0.05
        // The glyph's waist opening is the gap above and below the bar; it narrows to a knockout across the chest.
        let gap = 0.036 - 0.016 * p

        var body = [
            s.rect(CGRect(x: c - 0.087, y: 0.25, width: 0.174, height: 0.221), corner: 0.01),
            s.capsule(CGPoint(x: c - 0.057, y: 0.294), 0.08, CGPoint(x: c + 0.057, y: 0.294), 0.08),
            // The waist fills in below the bar as it rises.
            s.rect(CGRect(x: c - 0.087, y: 0.471, width: 0.174, height: 0.12), corner: 0),
        ]
        var front = [
            s.circle(CGPoint(x: c, y: 0.0865), 0.0865),
            s.rect(CGRect(x: c - 0.106, y: 0.591, width: 0.212, height: 0.04), corner: 0.005),
        ]
        for side in [-1.0, 1.0] {
            let at = { (dx: Double, y: Double) in CGPoint(x: c + side * dx, y: y) }
            let elbow = at(0.1778, 0.4387)
            body.append(s.capsule(at(0.092, 0.266), 0.04, elbow, 0.04))
            front += [
                s.capsule(elbow, 0.04, at(0.248, handY), 0.04),
                s.capsule(at(0.0695, 0.6375), 0.049, at(0.1165, 0.7485), 0.04),
                s.capsule(at(0.1165, 0.7485), 0.04, at(0.153, 0.9195), 0.04),
                s.rect(CGRect(x: c + side * 0.38075 - 0.03825, y: barY - 0.133, width: 0.0765, height: 0.2665), corner: 0.0265),
            ]
        }
        let bar = s.capsule(CGPoint(x: 0.0245, y: barY), 0.0235, CGPoint(x: 2 * c - 0.0245, y: barY), 0.0235)
        return s.union([s.knockout(s.union(body), by: bar, gap: gap), bar] + front)
    }
}

/// Legs split squat in the style of `figure.strengthtraining.functional`. Progress 0 is the glyph at the bottom of the
/// lunge. Both feet stay planted while the hip drives straight up; the knees follow by two-bone IK until the
/// back leg is nearly straight, and the upright torso with hands on hips rides on the hip.
struct LungeFigure: Shape {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let hip = CGPoint(x: 0.478, y: 0.6455)
    private static let frontKnee = CGPoint(x: 0.8125, y: 0.66), frontFoot = CGPoint(x: 0.814, y: 0.9365)
    private static let backKnee = CGPoint(x: 0.373, y: 0.87), backFoot = CGPoint(x: 0.123, y: 0.935)

    func path(in rect: CGRect) -> Path {
        typealias F = FigureSketch
        let p = min(max(progress, 0), 1), s = FigureSketch(rect)
        let h0 = Self.hip, hip = CGPoint(x: h0.x, y: h0.y - 0.08 * p)
        let up = { (q: CGPoint) in CGPoint(x: q.x + hip.x - h0.x, y: q.y + hip.y - h0.y) }
        let frontKnee = F.knee(hip: hip, foot: Self.frontFoot,
                               thigh: F.distance(h0, Self.frontKnee), shin: F.distance(Self.frontKnee, Self.frontFoot))
        let backKnee = F.knee(hip: hip, foot: Self.backFoot,
                              thigh: F.distance(h0, Self.backKnee), shin: F.distance(Self.backKnee, Self.backFoot))
        let elbow = up(CGPoint(x: 0.2575, y: 0.43))

        return s.union([
            s.circle(up(CGPoint(x: 0.508, y: 0.099)), 0.099),
            s.capsule(up(CGPoint(x: 0.514, y: 0.337)), 0.092, up(CGPoint(x: 0.513, y: 0.612)), 0.094),
            s.capsule(up(CGPoint(x: 0.443, y: 0.294)), 0.0445, elbow, 0.0445),
            s.capsule(elbow, 0.0445, up(CGPoint(x: 0.437, y: 0.5495)), 0.0445),
            s.capsule(hip, 0.0605, frontKnee, 0.046),
            s.capsule(frontKnee, 0.046, Self.frontFoot, 0.046),
            s.capsule(hip, 0.067, backKnee, 0.045),
            s.capsule(backKnee, 0.045, Self.backFoot, 0.047),
        ])
    }
}

/// Ab crunch with knee tuck in the style of `figure.core.training`. Progress 0 is the glyph: shoulders curled up, hands
/// behind the head and the near knee drawn in under the elbow. Opening up, the upper body rolls back about the lower
/// back while the floor-side elbow stays down, and the near leg extends out to hover over the straight far leg, which
/// keeps Apple's knockout gap wherever the near leg crosses in front of it.
struct CrunchFigure: Shape {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let lowerBack = CGPoint(x: 0.334, y: 0.596), hip = CGPoint(x: 0.469, y: 0.592)
    private static let farShoulder = CGPoint(x: 0.182, y: 0.559)
    private static let knee = CGPoint(x: 0.466, y: 0.365), foot = CGPoint(x: 0.665, y: 0.365)

    func path(in rect: CGRect) -> Path {
        typealias F = FigureSketch
        let p = min(max(progress, 0), 1), s = FigureSketch(rect)
        let back = Self.lowerBack, hip = Self.hip
        let upper = { (q: CGPoint) in F.moved(q, about: back, to: back, by: -0.3 * p) }
        let farShoulder = upper(Self.farShoulder)
        let farArm = { (q: CGPoint) in F.moved(upper(q), about: farShoulder, to: farShoulder, by: 0.6 * p) }
        let nearElbow = upper(CGPoint(x: 0.3665, y: 0.365)), farElbow = farArm(CGPoint(x: 0.039, y: 0.625))
        // The thigh swings out from vertical while the knee opens, so the leg ends nearly straight.
        let knee = F.moved(Self.knee, about: hip, to: hip, by: 1.13 * p)
        let foot = F.moved(Self.foot, about: Self.knee, to: knee, by: (1.13 - 1.4) * p)
        let nearLeg = s.union([s.capsule(hip, 0.055, knee, 0.032), s.capsule(knee, 0.032, foot, 0.032)])

        let farKnee = CGPoint(x: 0.6675, y: 0.55)
        let farLeg = s.union([s.capsule(hip, 0.043, farKnee, 0.034), s.capsule(farKnee, 0.034, CGPoint(x: 0.926, y: 0.55), 0.034)])

        return s.union([
            s.knockout(farLeg, by: nearLeg, gap: 0.031),
            s.circle(upper(CGPoint(x: 0.134, y: 0.396)), 0.069),
            s.capsule(upper(CGPoint(x: 0.2525, y: 0.3645)), 0.0325, nearElbow, 0.0325),
            s.capsule(nearElbow, 0.0325, upper(CGPoint(x: 0.238, y: 0.5205)), 0.0325),
            s.capsule(farArm(CGPoint(x: 0.071, y: 0.503)), 0.032, farElbow, 0.032),
            s.capsule(farElbow, 0.032, farShoulder, 0.032),
            s.capsule(upper(CGPoint(x: 0.214, y: 0.567)), 0.059, back, 0.065),
            s.capsule(back, 0.065, hip, 0.055),
            nearLeg,
        ])
    }
}
