import SwiftUI
import WatchKit

// Semantic workout colors stay independent of the routine's category color.
enum WatchPalette {
    static let workout = Color(red: 0.77, green: 0.98, blue: 0.15)
    static let time = Color.yellow
    static let energy = Color(red: 1, green: 0.29, blue: 0.36)
    static let heart = Color.red
    static let move = Color(red: 1, green: 0.18, blue: 0.35)
    static let stand = Color.cyan
}

extension Split {
    var workoutColor: Color { identityColor }
}

/// Native scrolling owns Crown input; focusing a card never starts a workout.
struct WorkoutChoiceCarousel<More: View>: View {
    let routines: [WorkoutRoutine]
    let canStart: Bool
    let onChoose: (WorkoutRoutine) -> Void
    @ViewBuilder let more: () -> More
    @ScaledMetric(relativeTo: .body) private var minimumCardHeight: CGFloat = 110

    var body: some View {
        GeometryReader { geometry in
            // Leave the next workout visible, as in Workout.app. The native
            // carousel owns focus, edge compression, Crown detents and motion preferences.
            let cardHeight = max(minimumCardHeight, geometry.size.height * 0.56)
            List {
                ForEach(routines) { split in
                    card(split, height: cardHeight)
                        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.carousel)
            .contentMargins(.top, 0, for: .scrollContent)
            .padding(.top, -4)
        }
    }

    private func card(_ split: WorkoutRoutine, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: REPStyle.detail) {
            Image(systemName: split.workoutSymbol)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(split.workoutColor)
                .frame(width: 48, height: 48, alignment: .leading)
                .accessibilityHidden(true)
            Text(split.title)
                .font(.body.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        // Reference: 10-point top inset; title and glyph share an 8-point leading edge.
        .padding(EdgeInsets(top: 10, leading: 8, bottom: 8, trailing: 8))
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        .background(split.workoutColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            // Keep the artwork outside the system's plain-button label dimming.
            // A separate native button still owns hit testing and accessibility.
            Button { onChoose(split) } label: {
                Color.clear.contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(!canStart)
            .accessibilityLabel("Start \(split.title)")
            .accessibilityHint("Double-tap to start the workout countdown")
        }
        .overlay(alignment: .topTrailing) {
            // Sibling of the card button so tapping it never starts a workout.
            NavigationLink(destination: more) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(split.workoutColor)
                    .frame(width: 22, height: 22)
                    .background(split.workoutColor.opacity(0.25), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            // Match the upper-right circle without shrinking its touch target.
            .offset(y: -2)
            .accessibilityLabel("More")
        }
    }
}

struct SetProgressDots: View {
    let completed: Int
    let planned: Int
    var revealsLatest = false
    var tint: Color = REPStyle.accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    @State private var appeared = false
    var body: some View {
        HStack(spacing: REPStyle.detail) {
            if planned <= 8 {
                ForEach(0..<max(0, planned), id: \.self) { index in
                    Circle().fill(index < completed ? tint : Color.white.opacity(0.25))
                        .frame(width: 5, height: 5)
                        .scaleEffect(revealsLatest && index == completed - 1 && !appeared && !reduceMotion && !dimmed ? 0.3 : 1)
                        .animation(reduceMotion || dimmed ? nil : .spring(duration: 0.32, bounce: 0.3), value: appeared)
                        .animation(reduceMotion || dimmed ? nil : .spring(duration: 0.32, bounce: 0.3), value: completed)
                }
            } else {
                Text("\(completed)/\(planned)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completed) of \(planned) sets completed")
        .onAppear { appeared = true }
    }
}

struct RestCountdown: View {
    let seconds: Int
    let total: Double
    var tint: Color = REPStyle.accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Rest", systemImage: "timer").font(.caption2.weight(.semibold))
                .symbolEffect(.bounce, options: .nonRepeating, value: !reduceMotion && !dimmed && (1...3).contains(seconds) ? seconds : 0)
            Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
                .font(.system(.largeTitle, design: .rounded).weight(.medium).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.65)
                .contentTransition(.numericText(countsDown: true))
                .animation(reduceMotion || dimmed ? nil : .easeOut(duration: 0.2), value: seconds)
                .accessibilityAddTraits(.updatesFrequently)
            ProgressView(value: min(max(0, Double(seconds)), max(1, total)), total: max(1, total))
                .tint(tint)
                .scaleEffect(y: 1.35, anchor: .center)
                .animation(reduceMotion || dimmed ? nil : .easeOut(duration: 0.35), value: seconds)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rest, \(seconds) seconds remaining")
    }
}

/// A number-first Workout-style countdown. Recording starts only after completion or skip.
struct StartCountdown: View {
    let split: WorkoutRoutine
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    @State private var startedAt = Date.now
    @State private var finished = false

    // Read-only simulator frame: no countdown task, haptics or start callback.
    private var previewElapsed: TimeInterval? {
        #if targetEnvironment(simulator)
        guard ContentView.isCountdownPreview else { return nil }
        return 0.35
        #else
        return nil
        #endif
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion || dimmed ? 0.1 : 1.0 / 30)) { context in
            let elapsed = min(3, max(0, previewElapsed ?? context.date.timeIntervalSince(startedAt)))
            let number = max(1, 3 - Int(elapsed))
            // Like Workout.app, the ring drains once per number rather than across all three.
            let sweep: CGFloat = reduceMotion ? 1 : CGFloat(1 - (elapsed - elapsed.rounded(.down)))
            GeometryReader { geometry in
                // Keep the gradient ring prominent, with a larger, lighter numeral.
                let w = geometry.size.width
                let diameter = min(w * 0.70, geometry.size.height - w * 0.22)
                let lineWidth = w * 0.062
                Button(action: finish) {
                    VStack(spacing: w * 0.055) {
                        ZStack {
                            // Like Workout.app: a uniform dim track and one arc that brightens toward its head.
                            Circle()
                                .stroke(split.workoutColor.opacity(0.24), lineWidth: lineWidth)
                            Circle()
                                .trim(from: 0, to: sweep)
                                // Gradient spans only the visible arc so no seam appears at 12 o'clock.
                                .stroke(AngularGradient(colors: [split.workoutColor.opacity(0.75), split.workoutColor],
                                                        center: .center,
                                                        startAngle: .zero,
                                                        endAngle: .degrees(360 * max(0.001, sweep))),
                                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            Text("\(number)")
                                .font(.system(size: diameter * 0.52, weight: .light).monospacedDigit())
                                .foregroundStyle(.white)
                                .id(number)
                                .transition(.identity)
                        }
                        .frame(width: diameter, height: diameter)
                        Text(split.title)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(previewElapsed == nil)
                .accessibilityLabel("Starting \(split.title) in \(number)")
                .accessibilityHint("Double-tap to skip the countdown and start now")
            }
        }
        .background(.black)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image(systemName: split.workoutSymbol)
                    .font(.system(size: 14))
                    .foregroundStyle(split.workoutColor)
                    .accessibilityHidden(true)
            }
        }
        .task {
            guard previewElapsed == nil else { return }
            let clock = ContinuousClock()
            let origin = clock.now
            startedAt = .now
            do {
                // One shared origin prevents relative sleeps from accumulating drift.
                for beat in 0..<3 {
                    try await clock.sleep(until: origin.advanced(by: .seconds(beat)))
                    guard !Task.isCancelled, !finished else { return }
                    WKInterfaceDevice.current().play(.click)
                }
                try await clock.sleep(until: origin.advanced(by: .seconds(3)))
            } catch {
                return // Removing the view must never start a workout.
            }
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { onFinish() }
    }
}

/// Continuous visual cadence, using the last measured BPM when available.
/// The idle cadence before the first reading is decorative; it supplies no BPM value.
struct LiveHeartIcon: View {
    let beatsPerMinute: Double?
    var isVisible = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        TimelineView(.animation(minimumInterval: dimmed || reduceMotion ? 1.0 / 10 : 1.0 / 30,
                                paused: !isVisible || scenePhase != .active)) { context in
            let bpm = beatsPerMinute.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            let period = bpm.map { 60 / $0 } ?? 1
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            let pulse = pow(max(0, cos(phase * 2 * .pi)), 6)
            Image(systemName: "heart.fill")
                .scaleEffect(1 + (reduceMotion ? 0.03 : 0.18) * pulse)
        }
        .accessibilityHidden(true)
    }
}

/// Large, value-first typography for the live Workout-style metrics page.
struct LiveWorkoutMetric: View {
    let value: String
    let label: String?
    let accessibilityName: String
    let color: Color
    var showsHeart = false
    var heartRate: Double? = nil
    var heartIsVisible = true
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 38

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(value)
                .font(.system(size: valueSize, weight: .medium, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(color)
                .layoutPriority(1)
            if showsHeart {
                LiveHeartIcon(beatsPerMinute: heartRate, isVisible: heartIsVisible)
                    .font(.title3)
                    .foregroundStyle(WatchPalette.heart)
            }
            if let label {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibilityName), \(value == "—" ? "unavailable" : value)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct WatchMetric: View {
    let symbol: String
    let value: String
    let unit: String
    let color: Color
    var heartRate: Double? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(unit).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(.title, design: .rounded).weight(.medium).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.65)
                if symbol == "heart.fill" {
                    LiveHeartIcon(beatsPerMinute: heartRate).font(.headline)
                }
            }.foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(unit), \(value == "—" ? "unavailable" : value)")
    }
}

struct ActivityValueRow: View {
    let title: String
    let value: String
    let goal: String
    let unit: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.white)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)/\(goal)")
                    .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.65)
                Text(unit).font(.caption2.weight(.semibold))
            }.foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value) of \(goal) \(unit)")
    }
}

/// Workout.app-style control: tinted capsule, coloured symbol, label beneath.
struct WorkoutControl: View {
    let symbol: String
    let title: String
    let color: Color
    let disabled: Bool
    var height: CGFloat = 52
    var labelSize: CGFloat = 15
    var accessibilityName: String? = nil
    var isBusy = false
    let action: () -> Void
    var body: some View {
        VStack(spacing: height * 0.11) {
            Button(action: action) {
                Group {
                    if isBusy { ProgressView().tint(color) }
                    else { Image(systemName: symbol).font(.system(size: height * 0.42, weight: .semibold)) }
                }
                    .foregroundStyle(color.opacity(disabled ? 0.45 : 1))
                    .frame(maxWidth: .infinity, minHeight: max(44, height), maxHeight: max(44, height))
                    .background(color.opacity(disabled ? 0.10 : 0.30), in: Capsule())
                    .contentShape(Capsule())
            }.buttonStyle(WorkoutControlButtonStyle()).disabled(disabled)
                .accessibilityLabel(accessibilityName ?? "\(title) workout")
            Text(title).font(.system(size: labelSize, weight: .medium))
                .foregroundStyle(.white.opacity(disabled ? 0.65 : 1))
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WorkoutControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct SavedSetMark: View {
    let isSaved: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RevealedSetCheckmark(progress: isSaved ? 1 : 0)
            .foregroundStyle(.black)
            .padding(6)
            .frame(width: 22, height: 22)
            .background(WatchPalette.workout, in: Circle())
            .opacity(isSaved ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: isSaved)
            .accessibilityHidden(true)
    }
}

/// Reveal the actual SF checkmark without redrawing or changing its geometry.
struct RevealedSetCheckmark: View {
    let progress: CGFloat
    var body: some View {
        Image(systemName: "checkmark")
            .resizable().scaledToFit()
            .fontWeight(.semibold)
            .mask(alignment: .leading) {
                Rectangle().scaleEffect(x: min(1, max(0, progress)), anchor: .leading)
            }
    }
}

/// A single restrained press response; confirmation stays after durable logging.
struct SetDoneButtonStyle: ButtonStyle {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(tint, in: Capsule())
            .frame(minHeight: REPStyle.minimumTarget)
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion && !dimmed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion || dimmed ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SetSavedCapsule: View {
    var tint: Color = WatchPalette.workout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 7) {
            RevealedSetCheckmark(progress: appeared ? 1 : 0)
                .frame(width: 18, height: 18)
                .animation(reduceMotion || dimmed ? nil : .easeOut(duration: 0.24), value: appeared)
            Text("Set logged").font(.body.weight(.semibold))
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, minHeight: REPStyle.minimumTarget)
        .background(tint, in: Capsule())
        .onAppear { appeared = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Set saved locally")
    }
}

// Both editable set values share the same baselines and column sizing.
struct WatchSetValue: View {
    let value: String
    let label: String
    var compact = false
    var tint: Color = .primary

    var body: some View {
        VStack(spacing: 0) {
            Text(value).foregroundStyle(tint)
                .font(.system(size: compact ? 30 : 32, weight: .semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
            Text(label)
                .font(.system(size: 14)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: REPStyle.minimumTarget)
        .contentShape(Rectangle())
    }
}

struct WatchLoadValue: View {
    let load: TrainingLoad
    var compact = false
    var needsStartingWeight = false
    var body: some View {
        Group {
            if let pounds = load.pounds {
                // Keep the logger concise; the editor and accessibility label retain the load basis.
                WatchSetValue(value: pounds.repNumber,
                              label: load.kind == .smith ? "Lbs / side" :
                     load.kind == .addedBodyweight ? "Lbs added" : "Lbs", compact: compact)
            } else if needsStartingWeight && load.kind == .unknown {
                VStack(spacing: REPStyle.detail) {
                    Image(systemName: "plus.circle").font(.title3)
                    Text("Set starting weight").font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, minHeight: REPStyle.minimumTarget)
            } else {
                WatchSetValue(value: load.kind == .bodyweight ? "Bodyweight" : "Set load",
                              label: load.kind == .unknown ? "Unknown" : "", compact: compact)
            }
        }
    }
}
