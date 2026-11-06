import SwiftUI

extension Split {
    /// Unmodified Apple SF Symbols; these identify routines, not exact exercise form.
    var workoutSymbol: String {
        switch self {
        case .back: return "figure.strengthtraining.traditional"
        case .legs: return "figure.strengthtraining.functional"
        case .glutes: return "figure.cross.training"
        }
    }
}

extension Optional<Split> {
    /// A nil split is the ab finisher, shown with Apple's core-training glyph.
    var figureSymbol: String { self?.workoutSymbol ?? "figure.core.training" }
}

struct LiftingFigure: View {
    var split: Split? = .back
    let isMoving: Bool
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt = Date.now

    private var shouldAnimate: Bool { isMoving && !reduceMotion && !dimmed && scenePhase == .active }

    var body: some View {
        Group {
            if shouldAnimate {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let elapsed = max(0, context.date.timeIntervalSince(startedAt))
                    let phase = (1 - cos(elapsed / 2.4 * 2 * .pi)) / 2
                    // Smoothstep holds briefly at each end, like a real controlled rep.
                    let rep = phase * phase * (3 - 2 * phase)
                    switch split {
                    case .back: CurlFigure(progress: rep).fill(color)
                    case .legs: LungeFigure(progress: rep).fill(color)
                    case .glutes: SquatFigure(progress: rep).fill(color)
                    case nil: CrunchFigure(progress: rep).fill(color)
                    }
                }
            } else {
                Image(systemName: split.figureSymbol)
                    .resizable().scaledToFit().symbolRenderingMode(.monochrome)
                    .foregroundStyle(color)
            }
        }
        .onChange(of: shouldAnimate, initial: true) { _, active in
            if active { startedAt = .now }
        }
        .accessibilityHidden(true)
    }
}

/// The actual SF core-training symbol peeks into its own reserved area once.
struct AbsInvitationFigure: View {
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    @State private var revealed = false

    var body: some View {
        Image(systemName: "figure.core.training")
            .font(.system(size: 32, weight: .regular))
            .foregroundStyle(Color(red: 0.77, green: 0.98, blue: 0.15))
            .offset(y: reduceMotion || dimmed || revealed ? 0 : 35)
            .frame(width: 48, height: 36, alignment: .top)
            .clipped()
            .animation(reduceMotion || dimmed ? nil : .spring(duration: 0.55, bounce: 0.2), value: revealed)
            .onChange(of: isVisible, initial: true) { _, visible in revealed = visible }
            .accessibilityHidden(true)
    }
}

/// A decorative tiny lift. Taps never log a set or change workout state.
struct PlayfulLiftEmblem: View {
    let color: Color
    var size: CGFloat = 64
    var showsMessage = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    @State private var taps = 0

    private var message: String {
        guard taps > 0 else { return "Less tapping. More lifting." }
        let messages = ["Even the icon lifts.", "Small icon. Big ambition.", "Okay, one more tiny rep."]
        return messages[(taps - 1) % messages.count]
    }

    var body: some View {
        Button { taps += 1 } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(color.opacity(0.16))
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .phaseAnimator([0, 1, 2, 3], trigger: taps) { icon, phase in
                            icon
                                .rotationEffect(.degrees(reduceMotion || dimmed ? 0 : phase == 1 ? -18 : phase == 2 ? 12 : 0))
                                .offset(y: reduceMotion || dimmed ? 0 : phase == 1 ? -size * 0.12 : 0)
                                .scaleEffect(reduceMotion || dimmed ? 1 : phase == 2 ? 1.12 : 1)
                        } animation: { _ in .spring(response: 0.23, dampingFraction: 0.55) }
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.22, weight: .medium))
                        .offset(x: size * 0.32, y: -size * 0.28)
                        .phaseAnimator([false, true, false], trigger: taps) { spark, visible in
                            spark.opacity(visible && !dimmed ? 1 : 0)
                                .scaleEffect(reduceMotion || dimmed ? 1 : visible ? 1.2 : 0.6)
                        } animation: { _ in .easeOut(duration: 0.22) }
                }
                .frame(width: size, height: size)
                .accessibilityHidden(true)
                if showsMessage {
                    Text(message).font(.caption2).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(color)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tiny lift")
        .accessibilityValue(message)
        .accessibilityHint("Play a decorative animation")
    }
}
