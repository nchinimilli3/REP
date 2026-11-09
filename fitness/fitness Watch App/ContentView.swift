import SwiftUI
import HealthKit
import WatchKit

struct ContentView: View {
    @ObservedObject var records: TrainingStore
    @ObservedObject var workout: WorkoutManager
    @ObservedObject var sync: DeviceSync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.scenePhase) private var scenePhase
    @State private var countdown: WorkoutRoutine?
    @State private var choosingExercise = false
    @State private var editor: NumericEdit?
    @State private var page = 0
    /// 0 = controls (swipe right from the workout), 1 = vertical workout pages.
    @State private var sidePage = 1
    @State private var swipeStartPage: Int?
    @State private var horizontalDrag: CGFloat = 0
    @State private var swipeIsHorizontal = false
    @State private var swipeIsSettling = false
    @State private var swipeSettlingRevision = 0
    @State private var savedSetFeedback = false
    @State private var savedSetRecord: StrengthSession?
    @State private var showSummary = true
    @State private var healthCheckResult: String?
    @State private var showingHealthCheck = false
    @State private var checkingHealth = false
    @State private var autoChecked = false

    // Read-only simulator fixture: never enters storage, sync, or HealthKit.
    static var isLoggerPreview: Bool {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--logger-preview") ||
            ProcessInfo.processInfo.environment["REP_VISUAL_PREVIEW"] == "logger"
        #else
        false
        #endif
    }
    static var isCountdownPreview: Bool {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--countdown-preview") ||
            ProcessInfo.processInfo.environment["REP_VISUAL_PREVIEW"] == "countdown"
        #else
        false
        #endif
    }
    static var isControlsPreview: Bool {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["REP_VISUAL_PREVIEW"] == "controls"
        #else
        false
        #endif
    }
    static var isVisualPreview: Bool { isLoggerPreview || isCountdownPreview || isControlsPreview }
    private var loggerPreviewRecord: StrengthSession {
        let exerciseID = ProcessInfo.processInfo.environment["REP_PREVIEW_EXERCISE"] ?? "pullup"
        let exercise = TrainingPlan.seed.exercises.first { $0.id == exerciseID } ?? TrainingPlan.seed.exercises.first { $0.id == "pullup" }!
        var record = StrengthSession(id: UUID(), day: exercise.split?.day ?? 1, startedAt: .now,
                                     routine: [exercise], draftLoad: exercise.load, draftReps: 10)
        record.sets = (1...2).map { ordinal in
            CompletedSet(id: UUID(), exerciseID: exercise.id, exerciseName: exercise.name,
                         ordinal: ordinal, load: exercise.load, reps: 10, completedAt: .now)
        }
        return record
    }

    private var workoutAccent: Color {
        if Self.isLoggerPreview || Self.isControlsPreview { return loggerPreviewRecord.currentExercise?.identityColor ?? REPStyle.accent }
        return workout.record.map { $0.identityColor } ?? REPStyle.accent
    }

    var body: some View {
        NavigationStack {
        Group {
            if Self.isCountdownPreview {
                StartCountdown(split: .builtIn(.back, exercises: []), onFinish: {})
            } else if Self.isLoggerPreview || Self.isControlsPreview {
                workoutPages(loggerPreviewRecord)
            } else if let split = countdown {
                StartCountdown(split: split) {
                    Task {
                        // Keep the countdown mounted until start owns the handoff.
                        countdown = nil
                        await workout.start(routineID: split.id)
                    }
                }
            } else if workout.isStarting {
                // A durable local record exists before HealthKit collection starts.
                // That normal startup interval is not an interrupted workout.
                ProgressView("Starting workout…")
                    .tint(workoutAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar(.hidden, for: .navigationBar)
            } else if let record = workout.record, record.endedAt == nil {
                workoutPages(record)
            } else if let record = workout.record, showSummary {
                summary(record)
            } else {
                home
            }
        }
        .task(id: savedSetRecord?.pendingSetID) {
            guard savedSetFeedback, savedSetRecord != nil else { return }
            do { try await Task.sleep(for: .milliseconds(650)) }
            catch { return }
            guard !Task.isCancelled else { return }
            savedSetFeedback = false
            savedSetRecord = nil
        }
        .onChange(of: workout.recordID) { _, _ in
            // A previous workout's page, sheet or feedback must not leak into the next.
            choosingExercise = false
            editor = nil
            savedSetFeedback = false
            savedSetRecord = nil
            autoChecked = false
            healthCheckResult = nil
            page = 0
            sidePage = 1
            resetSwipePresentation()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { resetSwipePresentation() }
        }
        .alert("REP.", isPresented: Binding(get: { records.errorMessage != nil }, set: { if !$0 { records.errorMessage = nil } })) {
            Button("OK") { records.errorMessage = nil }
        } message: { Text(records.errorMessage ?? "") }
        .alert("Apple Health", isPresented: $showingHealthCheck) {
            Button("OK", role: .cancel) {}
        } message: { Text(healthCheckResult ?? "") }
        .sheet(isPresented: $choosingExercise) {
            if let record = workout.record { exerciseChooser(record) }
        }
        .sheet(item: $editor) { edit in
            if let record = workout.record {
                WatchNumberEditor(mode: edit, load: record.draftLoad, reps: record.draftReps,
                                  tint: workoutAccent) { load, reps in
                    try records.editDraft(record.id, load: load, reps: reps)
                    WKInterfaceDevice.current().play(.click)
                }
            }
        }
        .alert("Workout conflict", isPresented: Binding(
            get: { workout.conflictMessage != nil },
            set: { if !$0 { workout.conflictMessage = nil } }
        )) {
            Button("OK", role: .cancel) { workout.conflictMessage = nil }
        } message: { Text(workout.conflictMessage ?? "") }
        }
    }
    private func resetSwipePresentation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            horizontalDrag = 0
            swipeIsHorizontal = false
            swipeStartPage = nil
            swipeIsSettling = false
            swipeSettlingRevision += 1
        }
    }
    @discardableResult
    private func confirmEdit(_ change: () throws -> Void) -> Bool {
        do {
            try change()
            // Only acknowledge an edit after the local archive has been written.
            WKInterfaceDevice.current().play(.click)
            return true
        } catch {
            records.errorMessage = error.localizedDescription
            WKInterfaceDevice.current().play(.failure)
            return false
        }
    }
    private var home: some View {
        VStack(spacing: REPStyle.detail) {
            WorkoutChoiceCarousel(routines: records.archive.plan.availableRoutines, canStart: workout.canStart) { split in
                guard workout.canStart, countdown == nil else { return }
                healthCheckResult = nil
                showSummary = true
                page = 0
                sidePage = 1
                // HealthKit starts after the countdown; no routine confirmation tap.
                countdown = split
            } more: {
                moreMenu
            }
            if workout.status != "Ready" && !workout.status.hasPrefix("Ready.") && !workout.status.hasPrefix("Saved to Apple Health") && !workout.status.hasPrefix("Existing Apple Health") {
                Text(workout.status).font(.caption2).foregroundStyle(.secondary)
            }
            #if !targetEnvironment(simulator)
            if workout.needsRecovery {
                Button("Recover Workout", systemImage: "arrow.clockwise") {
                    Task { await workout.recover() }
                }.disabled(workout.busy)
            }
            #endif
        }
        .navigationTitle("REP.")
        .toolbarTitleDisplayMode(.inline)
    }
    private var moreMenu: some View {
        List {
            if let last = records.history.first {
                Button {
                    guard !workout.busy, !workout.active, !workout.isStarting else { return }
                    workout.recordID = last.id
                    healthCheckResult = nil
                    showSummary = true
                } label: { Label("Last Workout", systemImage: "clock.arrow.circlepath") }
                .disabled(workout.busy || workout.active || workout.isStarting)
            }
            Section {
                Button("Retry Sync", systemImage: "arrow.triangle.2.circlepath") { sync.retry() }
            } header: { Text("iPhone Sync") } footer: { Text(sync.status) }
        }.navigationTitle("More")
    }
    private func workoutPages(_ record: StrengthSession) -> some View {
        // Only the vertical pager owns native page/Crown focus. Nesting it in
        // another TabView lets the outer pager consume its gestures and Crown.
        GeometryReader { geometry in
            workoutStrip(record, size: geometry.size)
                .contentShape(Rectangle())
                .simultaneousGesture(workoutSwipe(width: geometry.size.width))
        }
        .ignoresSafeArea(edges: .bottom)
        .contentShape(Rectangle())
        .toolbar(.hidden, for: .navigationBar)
        .background(.black)
        .onAppear { if Self.isControlsPreview { sidePage = 0 } }
        .task(id: record.restUntil) {
            guard let deadline = record.restUntil else { return }
            let remaining = max(0, deadline.timeIntervalSinceNow)
            do {
                try await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled, records.session(record.id)?.restUntil == deadline else { return }
                if records.session(record.id)?.restHapticDelivered == false {
                    try records.markRestHaptic(record.id)
                    WKInterfaceDevice.current().play(.notification)
                }
                try records.rest(record.id, extend: false)
            } catch is CancellationError {} catch { records.errorMessage = error.localizedDescription }
        }
    }
    private var swipeIsInFlight: Bool { swipeIsHorizontal || swipeIsSettling }

    private func workoutStrip(_ record: StrengthSession, size: CGSize) -> some View {
        let offset = (sidePage == 0 ? 0 : -size.width) + horizontalDrag
        return HStack(spacing: 0) {
            controlsPage(record)
                .frame(width: size.width, height: size.height)
                // Animate the strip's position without animating individual controls.
                .transaction { $0.animation = nil }
                .compositingGroup()
                .allowsHitTesting(sidePage == 0 && !swipeIsInFlight)
                .accessibilityHidden(sidePage != 0)
            workoutSurface(record)
                .transition(.identity)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(sidePage == 1 && !swipeIsInFlight && !Self.isControlsPreview)
                .accessibilityHidden(sidePage != 1 || Self.isControlsPreview)
        }
        .frame(width: size.width * 2, height: size.height, alignment: .leading)
        .offset(x: offset)
        .frame(width: size.width, height: size.height, alignment: .leading)
    }

    @ViewBuilder private func workoutSurface(_ record: StrengthSession) -> some View {
        // The native pager hosts its page index outside its frame.
        // Slide only the selected content so that layer can't trail it.
        if swipeIsInFlight {
            workoutPage(record)
        } else if sidePage == 1 {
            TabView(selection: $page) {
                exercisePage(record).tag(0)
                metricsPage.tag(1)
                activityPage.tag(2)
            }
            .tabViewStyle(.verticalPage(transitionStyle: .identity))
        } else {
            Color.clear
        }
    }

    @ViewBuilder private func workoutPage(_ record: StrengthSession) -> some View {
        switch page {
        case 1: metricsPage
        case 2: activityPage
        default: exercisePage(record)
        }
    }
    // Explicit touch paging leaves the native vertical pager as Crown owner.
    private func workoutSwipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard !Self.isControlsPreview, !swipeIsSettling else { return }
                if swipeStartPage == nil { swipeStartPage = page }
                let dx = value.translation.width
                let dy = value.translation.height
                if !swipeIsHorizontal, abs(dx) > abs(dy) * 1.5 {
                    page = swipeStartPage ?? page
                    swipeIsHorizontal = true
                }
                guard swipeIsHorizontal, !reduceMotion, !dimmed else { return }
                horizontalDrag = sidePage == 0 ? max(-width, min(0, dx)) : min(width, max(0, dx))
            }
            .onEnded { value in
                guard !Self.isControlsPreview, !swipeIsSettling, let initialPage = swipeStartPage else { return }
                swipeStartPage = nil
                let dx = value.translation.width
                let dy = value.translation.height
                if swipeIsHorizontal {
                    swipeIsSettling = true
                    swipeIsHorizontal = false
                    swipeSettlingRevision += 1
                    let revision = swipeSettlingRevision
                    withAnimation(reduceMotion || dimmed ? nil : .easeOut(duration: 0.16), completionCriteria: .removed) {
                        horizontalDrag = 0
                        if abs(dx) >= 28 { sidePage = dx > 0 ? 0 : 1 }
                    } completion: {
                        if swipeSettlingRevision == revision { swipeIsSettling = false }
                    }
                } else if sidePage == 1, abs(dy) >= 28, abs(dy) > abs(dx) * 1.5 {
                    withAnimation(reduceMotion || dimmed ? nil : .easeOut(duration: 0.22)) {
                        page = min(2, max(0, initialPage + (dy < 0 ? 1 : -1)))
                    }
                }
            }
    }
    private func exercisePage(_ record: StrengthSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !workout.active && !Self.isLoggerPreview {
                Label("Interrupted", systemImage: "exclamationmark.triangle").font(.headline).foregroundStyle(.yellow)
                Button("Try Recovery") { Task { await workout.recover() } }.disabled(workout.busy)
                Button("Finalize Local Log") { workout.end(completed: true, advanceFromDay: nil) }.disabled(workout.busy)
            } else if savedSetFeedback, let saved = savedSetRecord, let exercise = saved.currentExercise {
                Text(exercise.name).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                HStack {
                    Text("Saved locally").font(.caption2).foregroundStyle(workoutAccent)
                    Spacer(minLength: 2)
                    SetProgressDots(completed: saved.count(for: exercise.id), planned: exercise.sets, revealsLatest: true, tint: exercise.identityColor)
                }
                HStack(spacing: 6) {
                    WatchLoadValue(load: saved.draftLoad)
                    WatchSetValue(value: "\(saved.draftReps)", label: "Reps")
                }
                Spacer(minLength: 8)
                SetSavedCapsule(tint: workoutAccent)
                    .padding(.horizontal, REPStyle.compact)
            } else if record.restUntil != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    RestCountdown(seconds: record.remainingRest(at: context.date), total: record.currentExercise?.restSeconds ?? 90, tint: workoutAccent)
                }
                if let exercise = record.currentExercise {
                    Text(exercise.name).font(.footnote.weight(.semibold)).lineLimit(2)
                    Text("Next: \(record.draftLoad.label)").font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                HStack {
                    Button("Skip Rest") { confirmEdit { try records.rest(record.id, extend: false) } }
                        .buttonStyle(.borderedProminent).foregroundStyle(.black)
                    Button { confirmEdit { try records.rest(record.id, extend: true) } } label: { Image(systemName: "plus") }
                        .frame(width: 48).accessibilityLabel("Add 30 seconds")
                }
                .tint(workoutAccent)
                .padding(.bottom, 4)
            } else if let exercise = record.currentExercise {
                ViewThatFits(in: .vertical) {
                    setEntryLayout(record, exercise: exercise, compact: false)
                    setEntryLayout(record, exercise: exercise, compact: true)
                }
            } else if record.needsFinisherChoice {
                HStack(spacing: 6) {
                    AbsInvitationFigure(isVisible: page == 0 && sidePage == 1 && !swipeIsInFlight)
                    Text("Add Abs?").font(.headline)
                }
                Spacer(minLength: 4)
                Button("Add Abs") { confirmEdit { try records.chooseFinisher(record.id, include: true) } }
                    .tint(workoutAccent).foregroundStyle(.black).buttonStyle(.borderedProminent)
                Button("Not Today") { confirmEdit { try records.chooseFinisher(record.id, include: false) } }
            } else {
                Image(systemName: "checkmark").font(.title2).foregroundStyle(workoutAccent)
                Text("Ready to finish").font(.headline)
                Text("\(record.effectiveSets.count) sets logged").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button("End Workout") { workout.end(completed: true, advanceFromDay: nil) }.buttonStyle(.borderedProminent).tint(workoutAccent).foregroundStyle(.black)
            }
        }
        .animation(reduceMotion || dimmed ? nil : .easeInOut(duration: 0.18), value: savedSetFeedback)
        // Keep the exercise heading below watchOS's clock/status area.
        // This stays inside the page; Set Done is never pinned over content.
        .padding(.top, 18)
        .padding(.horizontal, REPStyle.compact).padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func setEntryLayout(_ record: StrengthSession, exercise: Exercise, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: REPStyle.compact) {
                LiftingFigure(split: exercise.id == "abs" ? nil : exercise.split ?? .back,
                              isMoving: workout.active && !workout.paused && !workout.busy && page == 0 && sidePage == 1 && !swipeIsInFlight,
                              color: workoutAccent)
                    .frame(width: compact ? 24 : 28, height: compact ? 24 : 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.id == "pullup" ? "Assisted Pull Up" : exercise.name)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(exercise.id == "pullup" ? 1 : 2)
                        .minimumScaleFactor(exercise.id == "pullup" ? 0.65 : 0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let description = exercise.routineDescription {
                        Text(description).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(.trailing, REPStyle.compact)
            // Center dots with the reference and share the title's trailing inset.
            // Retain stacking when accessibility text or a long load basis needs it.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 0) {
                    setReferenceStatus(record, exercise: exercise)
                    Spacer(minLength: REPStyle.compact)
                    previousSetReference(exercise)
                }
                VStack(alignment: .leading, spacing: REPStyle.detail) {
                    setReferenceStatus(record, exercise: exercise)
                    previousSetReference(exercise, allowsWrapping: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.trailing, REPStyle.compact)
            .padding(.top, compact ? 6 : 8)
            Spacer(minLength: compact ? 8 : 12)
            HStack(alignment: .center, spacing: REPStyle.compact) {
                Button { editor = .load } label: {
                    WatchLoadValue(load: record.draftLoad, compact: compact, needsStartingWeight: exercise.needsStartingWeight)
                }
                .buttonStyle(.plain).allowsHitTesting(!Self.isLoggerPreview)
                .frame(maxWidth: .infinity, minHeight: REPStyle.minimumTarget)
                .accessibilityLabel(exercise.needsStartingWeight && record.draftLoad.kind == .unknown ? "Set starting weight" : "Edit load, \(record.draftLoad.label)")
                Button { editor = .reps } label: {
                    WatchSetValue(value: "\(record.draftReps)", label: "Reps", compact: compact)
                }
                .buttonStyle(.plain).allowsHitTesting(!Self.isLoggerPreview)
                .frame(maxWidth: .infinity, minHeight: REPStyle.minimumTarget)
                .accessibilityLabel("Edit repetitions, \(record.draftReps)")
            }
            Spacer(minLength: compact ? 8 : 12)
            // Workout.app keeps its primary button clear of the page indicator.
            logSetButton(record)
                .padding(.bottom, compact ? 2 : 6)
        }
    }
    private func exerciseChooser(_ record: StrengthSession) -> some View {
        NavigationStack {
            List {
                if record.currentExercise != nil {
                    Button("Skip This Exercise", systemImage: "forward.end.fill", role: .destructive) {
                        guard confirmEdit({ try records.skipExercise(record.id) }) else { return }
                        choosingExercise = false
                        page = 0
                        sidePage = 1
                    }
                    .accessibilityLabel("Skip remaining sets of this exercise")
                }
                ForEach(record.routine) { exercise in
                    Button {
                        do {
                            try records.selectExercise(record.id, exerciseID: exercise.id)
                            choosingExercise = false
                            page = 0
                            sidePage = 1
                            WKInterfaceDevice.current().play(.click)
                        } catch { records.errorMessage = error.localizedDescription }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(exercise.name).font(.caption.weight(.semibold))
                            Text("\(record.count(for: exercise.id))/\(exercise.sets) sets\(record.skipped.contains(exercise.id) ? " · skipped" : "")")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }.disabled(!record.isSelectable(exercise))
                }
            }.navigationTitle("Exercises")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { choosingExercise = false } } }
        }
    }
    private func logSetButton(_ record: StrengthSession) -> some View {
        Button {
            let token = record.pendingSetID
            records.perform {
                if try records.logSet(record.id, token: token) {
                    WKInterfaceDevice.current().play(.success)
                    // Presentation snapshot only; persistence and the rest deadline are already committed.
                    var feedback = record
                    if let updated = records.session(record.id) { feedback.sets = updated.sets }
                    savedSetRecord = feedback
                    savedSetFeedback = true

                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark").font(.footnote.weight(.semibold))
                Text("Set Done").font(.callout.weight(.semibold))
            }
        }
        .buttonStyle(SetDoneButtonStyle(tint: workoutAccent))
        .disabled(Self.isLoggerPreview || !workout.canLog)
        .opacity(workout.canLog || Self.isLoggerPreview ? 1 : 0.4)
        .accessibilityHint("Manually confirms the displayed load and repetitions")
    }
    @ViewBuilder private func setReferenceStatus(_ record: StrengthSession, exercise: Exercise) -> some View {
        if workout.paused {
            Text("Paused").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        } else {
            SetProgressDots(completed: record.count(for: exercise.id), planned: exercise.sets, tint: exercise.identityColor)
        }
    }
    @ViewBuilder private func previousSetReference(_ exercise: Exercise, allowsWrapping: Bool = false) -> some View {
        if let label = previousLabel(exercise) {
            Text(label)
                .font(.footnote.weight(.semibold).monospacedDigit()).foregroundStyle(workoutAccent)
                .lineLimit(allowsWrapping ? 2 : 1)
                .fixedSize(horizontal: !allowsWrapping, vertical: true)
        }
    }
    private func previousLabel(_ exercise: Exercise) -> String? {
        if Self.isLoggerPreview { return lastLoadLabel(loggerPreviewRecord.draftLoad) }
        let previous = records.archive.sessions.filter { $0.id != workout.recordID }.flatMap(\.effectiveSets)
            .filter { $0.original.exerciseID == exercise.id && $0.load.comparisonKey == exercise.load.comparisonKey }
            .max { $0.original.completedAt < $1.original.completedAt }
        return previous.map { lastLoadLabel($0.load) }
    }
    private func lastLoadLabel(_ load: TrainingLoad) -> String {
        guard let pounds = load.pounds else { return "Last: \(load.label)" }
        let basis = load.kind == .smith ? " / side" : load.kind == .addedBodyweight ? " added" : ""
        return "Last: \(pounds.repNumber)lbs\(basis)"
    }
    private var metricsPage: some View {
            VStack(alignment: .leading, spacing: 2) {
                if workout.paused { Label("Paused", systemImage: "pause.fill").font(.caption2).foregroundStyle(.secondary) }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    LiveWorkoutMetric(value: Duration.seconds(workout.duration(at: context.date)).formatted(.time(pattern: .hourMinuteSecond)), label: nil, accessibilityName: "Elapsed time", color: WatchPalette.time)
                }
                LiveWorkoutMetric(value: workout.calories.map { "\(Int($0))" } ?? "—", label: "ACTIVE\nCAL", accessibilityName: "Active calories", color: .white)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    LiveWorkoutMetric(value: workout.liveHeartRate(at: context.date).map { "\(Int($0))" } ?? "—", label: nil, accessibilityName: "Heart rate in beats per minute", color: .white, showsHeart: true, heartRate: workout.heartRate, heartIsVisible: page == 1 && sidePage == 1 && !swipeIsInFlight)
                }
            }.padding(.horizontal, 6).padding(.vertical, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    private var activityPage: some View {
        VStack(spacing: 6) {
            if let summary = workout.activitySummary {
                ActivityRingView(summary: summary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Today's Activity rings")
                HStack(spacing: 6) {
                    activityTotal("Move", value: Int(summary.activeEnergyBurned.doubleValue(for: .kilocalorie())), goal: Int(summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())), color: WatchPalette.move)
                    activityTotal("Min", value: Int(summary.appleExerciseTime.doubleValue(for: .minute())), goal: Int(summary.appleExerciseTimeGoal.doubleValue(for: .minute())), color: WatchPalette.workout)
                    activityTotal("Stand", value: Int(summary.appleStandHours.doubleValue(for: .count())), goal: Int(summary.appleStandHoursGoal.doubleValue(for: .count())), color: WatchPalette.stand)
                }
            } else {
                Label("Activity", systemImage: "figure.stand").font(.title3.bold())
                Text("Activity rings unavailable").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 6).padding(.bottom, REPStyle.detail)
            .accessibilityHint(workout.activityStatus)
    }
    private func activityTotal(_ title: String, value: Int, goal: Int, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.caption2)
            Text("\(value)/\(goal)").font(.footnote.weight(.semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
        }.foregroundStyle(color).frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore).accessibilityLabel("\(title), \(value) of \(goal)")
    }
    private func controlsPage(_ record: StrengthSession) -> some View {
        let interrupted = !workout.active && !Self.isLoggerPreview && !Self.isControlsPreview
        let paused = workout.paused || Self.isControlsPreview
        let canChoose = (workout.active || Self.isControlsPreview) && !workout.busy
        let canUndo = workout.active && !workout.busy && !record.effectiveSets.isEmpty
        return GeometryReader { geometry in
            // Proportions measured from Workout.app's paused controls on the full screen (fractions of width):
            // status top 0.17, grid top 0.31, capsule 0.42 × 0.265, column gap 0.074, row pitch 0.377.
            let w = geometry.size.width
            let height = w * 0.265
            if interrupted {
                VStack(spacing: 0) {
                    Text("Interrupted")
                        .font(.system(size: w * 0.085, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Spacer(minLength: 12)
                    HStack(alignment: .top, spacing: w * 0.074) {
                        WorkoutControl(symbol: "xmark", title: "End", color: .red,
                                       disabled: workout.busy, height: height, labelSize: w * 0.065,
                                       accessibilityName: "End Workout") {
                            guard !Self.isVisualPreview else { return }
                            workout.end(completed: true, advanceFromDay: nil)
                        }
                        WorkoutControl(symbol: "arrow.clockwise",
                                       title: workout.busy ? "Recovering" : "Recover", color: workoutAccent,
                                       disabled: workout.busy, height: height, labelSize: w * 0.065,
                                       accessibilityName: "Recover Workout", isBusy: workout.busy) {
                            guard !Self.isVisualPreview else { return }
                            Task { await workout.recover() }
                        }
                        .accessibilitySortPriority(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, w * 0.17)
                .padding(.bottom, w * 0.09)
                .padding(.horizontal, w * 0.05)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
            VStack(spacing: 0) {
                Text(paused ? "Paused" : " ")
                    .font(.system(size: w * 0.085, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: w * 0.14, maxHeight: w * 0.14, alignment: .trailing)
                    .accessibilityHidden(!paused)
                Grid(horizontalSpacing: w * 0.074, verticalSpacing: REPStyle.compact) {
                    GridRow {
                        WorkoutControl(symbol: "xmark", title: "End", color: .red,
                                       disabled: Self.isLoggerPreview || workout.busy, height: height, labelSize: w * 0.065) {
                            guard !Self.isVisualPreview else { return }
                            workout.end(completed: true, advanceFromDay: nil)
                        }
                        WorkoutControl(symbol: paused ? "arrow.clockwise" : "pause.fill",
                                       title: paused ? "Resume" : "Pause", color: workoutAccent,
                                       disabled: Self.isLoggerPreview || (!workout.active && !Self.isControlsPreview) || workout.busy, height: height, labelSize: w * 0.065) {
                            guard !Self.isVisualPreview else { return }
                            workout.togglePause()
                        }
                    }
                    GridRow {
                        WorkoutControl(symbol: "list.bullet", title: "Exercise", color: workoutAccent,
                                       disabled: Self.isLoggerPreview || !canChoose, height: height, labelSize: w * 0.065,
                                       accessibilityName: "Choose or skip exercise") {
                            guard !Self.isVisualPreview else { return }
                            choosingExercise = true
                        }
                        WorkoutControl(symbol: "arrow.uturn.backward", title: "Undo Set", color: .white,
                                       disabled: Self.isLoggerPreview || !canUndo, height: height, labelSize: w * 0.065,
                                       accessibilityName: "Undo last set") {
                            guard !Self.isVisualPreview else { return }
                            confirmEdit { try records.undoLastSet(record.id) }
                            sidePage = 1
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, w * 0.17)
            .padding(.horizontal, w * 0.05)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea(.container, edges: .vertical)
    }
    private func summary(_ record: StrengthSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: record.artworkSymbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(record.identityColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(record.title).font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                        Text(record.completed ? "Workout complete" : "Workout ended")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 6)
                summaryRow("Total Time", record.elapsed.map { Duration.seconds($0).formatted(.time(pattern: .hourMinuteSecond)) } ?? "—",
                           color: WatchPalette.time)
                summaryRow("Active Calories", record.activeEnergy.map { "\(Int($0)) CAL" } ?? "—", color: WatchPalette.energy)
                summaryRow("Sets", "\(record.effectiveSets.count)")
                summaryRow("Reps", "\(record.effectiveSets.reduce(0) { $0 + $1.reps })")
                // Save status only surfaces when Health did not save; a check runs automatically first.
                if record.healthState != .saved && !workout.busy && autoChecked {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Apple Health needs review", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.yellow)
                        Text("Your sets are saved on Watch.").font(.caption2).foregroundStyle(.secondary)
                        if let message = healthCheckResult ?? record.healthError {
                            Text(message).font(.caption2).foregroundStyle(.secondary)
                        }
                        Button {
                            healthCheckResult = nil
                            checkingHealth = true
                            Task {
                                await workout.reconcile(record)
                                healthCheckResult = workout.status
                                checkingHealth = false
                            }
                        } label: {
                            if checkingHealth { ProgressView().accessibilityLabel("Checking Apple Health") }
                            else { Label("Check Again", systemImage: "arrow.clockwise") }
                        }.disabled(workout.active)
                        #if !targetEnvironment(simulator)
                        if [.recording, .saving, .recovery].contains(record.healthState) {
                            Button("Recover Workout") { Task { await workout.recover() } }.disabled(workout.active)
                        }
                        #endif
                    }
                    .padding(.vertical, REPStyle.compact)
                }
                Button {
                    workout.releaseEndedSession()
                    autoChecked = false
                    showSummary = false
                } label: {
                    Text("Done").font(.headline).foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: REPStyle.minimumTarget)
                        .background(workoutAccent, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                #if targetEnvironment(simulator)
                // UI testing can leave the summary while simulated HealthKit stalls.
                // Retain busy/live handles; never fabricate a successful Health save.
                .accessibilityHint("Return to workout choices. Any Apple Health save continues.")
                #else
                .disabled(workout.busy || workout.active)
                #endif
                .padding(.vertical, 10)
            }
            .padding(.horizontal, REPStyle.compact)
        }
        .task(id: "\(record.id)-\(workout.busy)") {
            // One quiet reconcile once any in-flight save finishes; reconcile never creates a workout.
            guard !autoChecked, !workout.busy, !workout.active else { return }
            autoChecked = true
            if record.healthState != .saved { await workout.reconcile(record) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(.black)
    }
    private func summaryRow(_ label: String, _ value: String, color: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            Text(label).font(.footnote).foregroundStyle(.white).padding(.top, 6)
            Text(value).font(.system(size: 30, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
                .padding(.bottom, REPStyle.detail)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value == "—" ? "unavailable" : value)")
    }

}

enum NumericEdit: String, Identifiable { case load, reps; var id: String { rawValue } }
struct WatchNumberEditor: View {
    let mode: NumericEdit
    let tint: Color
    let save: (TrainingLoad, Int) throws -> Void
    @State private var load: TrainingLoad
    @State private var reps: Int
    @State private var value: Double
    @State private var crownLoad: Double
    @State private var saveError: String?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    init(mode: NumericEdit, load: TrainingLoad, reps: Int, tint: Color = REPStyle.accent, save: @escaping (TrainingLoad, Int) throws -> Void) {
        self.mode = mode; self.tint = tint; self.save = save
        _load = State(initialValue: load); _reps = State(initialValue: reps)
        _value = State(initialValue: mode == .reps ? Double(reps) : load.pounds ?? 0)
        _crownLoad = State(initialValue: ((load.pounds ?? 0) / 5).rounded() * 5)
    }
    private var step: Double { mode == .reps ? 1 : 0.5 }
    private var maximumValue: Double { mode == .reps ? 100 : 1000 }
    private var crownValue: Binding<Double> {
        if mode == .reps { return $value }
        // Apply the Crown's movement relative to the exact load, including fractions.
        return Binding(get: { crownLoad }, set: { detent in
            value = min(maximumValue, max(0, value + (detent - crownLoad)))
            crownLoad = detent
        })
    }
    private var acceptsValue: Bool {
        mode == .reps || (load.kind != .unknown && load.kind != .bodyweight)
    }
    private var valueLabel: String {
        if mode == .reps { return "Repetitions" }
        switch load.kind {
        case .assistance: return "Assistance · lb"
        case .smith: return "Plates · lb per side"
        case .machine: return "Resistance · lb"
        case .addedBodyweight: return "Added weight · lb"
        case .bodyweight: return "Bodyweight"
        case .unknown: return "Load not specified"
        }
    }
    var body: some View {
        NavigationStack {
            ViewThatFits(in: .vertical) {
                editorLayout(compact: false)
                editorLayout(compact: true)
            }
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
            }
        }
        .onAppear { focused = acceptsValue }
        .onChange(of: load.kind) { _, _ in focused = acceptsValue }
        .alert("Couldn’t Save", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(saveError ?? "") }
    }
    private func editorLayout(compact: Bool) -> some View {
        VStack(spacing: 0) {
            Text(valueLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
            Spacer(minLength: compact ? 4 : 8)
            if acceptsValue {
                valueControls(compact: compact)
            } else {
                Picker("Weight basis", selection: $load.kind) {
                    ForEach(LoadKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.navigationLink)
                .frame(minHeight: REPStyle.minimumTarget)
            }
            Spacer(minLength: compact ? 8 : 14)
            Button(action: commit) {
                Text("Save")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: REPStyle.minimumTarget, maxHeight: 44)
                    .background(tint, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .padding(.bottom, REPStyle.detail)
    }
    private func valueControls(compact: Bool) -> some View {
        let crownStep: Double = mode == .reps ? 1 : 5
        let crownMinimum: Double = mode == .reps ? 0 : -crownStep
        let crownMaximum = maximumValue - crownMinimum
        let crownSensitivity: DigitalCrownRotationalSensitivity = mode == .reps ? .low : .medium
        return HStack(alignment: .center, spacing: 0) {
            adjustmentButton(increasing: false)
            Text(value.repNumber)
                .font(.system(size: compact ? 36 : 42, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: compact ? 44 : 54)
                .focusable().focused($focused)
                // One extra detent at each end lets fractional loads reach the bounds.
                .digitalCrownRotation(detent: crownValue, from: crownMinimum, through: crownMaximum,
                                      by: crownStep, sensitivity: crownSensitivity,
                                      isContinuous: false, isHapticFeedbackEnabled: true)
                .accessibilityLabel(mode == .reps ? "Repetitions" : "Pounds, \(load.kind.title)")
            adjustmentButton(increasing: true)
        }
    }
    private func adjustmentButton(increasing: Bool) -> some View {
        Button {
            value = min(maximumValue, max(0, value + (increasing ? step : -step)))
            if mode == .load { crownLoad = (value / 5).rounded() * 5 }
        } label: {
            Image(systemName: increasing ? "plus" : "minus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.16), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(increasing
                            ? (mode == .reps ? "Increase repetitions" : "Increase load")
                            : (mode == .reps ? "Decrease repetitions" : "Decrease load"))
    }
    private func commit() {
        if mode == .reps { reps = Int(value.rounded()) }
        else { load.pounds = load.kind == .unknown || load.kind == .bodyweight ? nil : value }
        do {
            try save(load, reps)
            dismiss()
        } catch {
            saveError = error.localizedDescription
            WKInterfaceDevice.current().play(.failure)
        }
    }
}

struct ActivityRingView: WKInterfaceObjectRepresentable {
    let summary: HKActivitySummary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    class Coordinator { var values: [Double] = []; var animated: Bool? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeWKInterfaceObject(context: Context) -> WKInterfaceActivityRing { WKInterfaceActivityRing() }
    func updateWKInterfaceObject(_ object: WKInterfaceActivityRing, context: Context) {
        let values = [summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                      summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                      summary.appleExerciseTime.doubleValue(for: .minute()),
                      summary.appleExerciseTimeGoal.doubleValue(for: .minute()),
                      summary.appleStandHours.doubleValue(for: .count()),
                      summary.appleStandHoursGoal.doubleValue(for: .count())]
        let animated = !reduceMotion && !dimmed
        guard context.coordinator.values != values || context.coordinator.animated != animated else { return }
        context.coordinator.values = values
        context.coordinator.animated = animated
        object.setActivitySummary(summary, animated: animated)
    }
}
