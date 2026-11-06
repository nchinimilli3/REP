import Foundation

extension Double {
    /// Display precision only: stored loads and historical observations are unchanged.
    var repNumber: String { formatted(.number.precision(.fractionLength(0...2))) }
}

enum LoadKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case machine, smith, assistance, bodyweight, addedBodyweight, unknown
    var id: String { rawValue }
    var title: String {
        switch self {
        case .machine: return "Machine resistance"
        case .smith: return "Smith plates per side"
        case .assistance: return "Bodyweight assistance"
        case .bodyweight: return "Bodyweight"
        case .addedBodyweight: return "Added bodyweight resistance"
        case .unknown: return "Not specified"
        }
    }
}

struct TrainingLoad: Codable, Equatable, Sendable {
    var kind: LoadKind
    var pounds: Double?
    var smithBarPounds: Double?
    var label: String {
        guard kind != .unknown else { return "Resistance not specified" }
        guard kind != .bodyweight else { return "Bodyweight" }
        guard let pounds else { return "Load not configured" }
        let value = pounds.repNumber
        switch kind {
        case .smith: return "\(value) lb / side"
        case .assistance: return "\(value) lb assistance"
        case .addedBodyweight: return "Bodyweight + \(value) lb"
        default: return "\(value) lb"
        }
    }
    var addedPlates: Double? { kind == .smith ? pounds.map { $0 * 2 } : nil }
    // Assistance, unknown resistance and bodyweight are never weight-lifted volume.
    var volumeLoad: Double? {
        switch kind {
        case .machine: return pounds
        case .smith: return addedPlates.map { $0 + (smithBarPounds ?? 0) }
        default: return nil
        }
    }
    var comparisonKey: String {
        "\(kind.rawValue):\(smithBarPounds.map(String.init(describing:)) ?? "bar-excluded")"
    }
    func validate() throws {
        if let pounds, !pounds.isFinite || pounds < 0 || pounds > 5000 { throw TrainingError.invalidLoad }
        if let smithBarPounds, !smithBarPounds.isFinite || smithBarPounds < 0 || kind != .smith { throw TrainingError.invalidLoad }
        if kind != .unknown && kind != .bodyweight && pounds == nil { throw TrainingError.invalidLoad }
        if (kind == .unknown || kind == .bodyweight) && pounds != nil { throw TrainingError.invalidLoad }
    }
}

enum Split: String, Codable, CaseIterable, Identifiable, Sendable {
    case back, glutes, legs
    var id: String { rawValue }
    var title: String {
        switch self { case .back: return "Back + Biceps"; case .glutes: return "Glutes"; case .legs: return "Legs" }
    }
    var day: Int { switch self { case .back: return 1; case .glutes: return 2; case .legs: return 3 } }
    static let workoutTypes: [Split] = [.back, .legs, .glutes]
    static func at(day: Int) -> Split { allCases[((day - 1) % 3 + 3) % 3] }
}

struct Exercise: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var split: Split?
    var load: TrainingLoad
    var sets = 4
    var reps = 10
    var restSeconds: Double = 90
    var increment: Double = 5
    var notes = ""
    var preferredRoutineColor: RoutineColor?
    var preferenceUpdatedAt: Date = .distantPast
    var withConfirmedDefaults: Exercise {
        guard id == "abs", load.kind == .unknown, preferenceUpdatedAt == .distantPast else { return self }
        var exercise = self
        exercise.load = TrainingLoad(kind: .addedBodyweight, pounds: 3)
        exercise.increment = 1
        return exercise
    }
}

enum RoutineColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case purple, pink, lime, blue, orange, teal
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct WorkoutRoutine: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var color: RoutineColor
    var legacySplit: Split?
    var exercises: [Exercise]
    var archived = false
    var title: String { name }
    var symbol: String {
        if legacySplit == .glutes { return "figure.cross.training" }
        if legacySplit == .legs { return "figure.strengthtraining.functional" }
        return "figure.strengthtraining.traditional"
    }
    static func builtIn(_ split: Split, exercises: [Exercise]) -> WorkoutRoutine {
        .init(id: split.rawValue, name: split.title,
              color: split == .back ? .purple : split == .glutes ? .pink : .lime,
              legacySplit: split, exercises: exercises)
    }
}

struct TrainingPlan: Codable, Equatable, Sendable {
    var routineLibrary: [WorkoutRoutine]?
    var revision = 0
    var exercises: [Exercise]
    var absDays: [Int] = [1, 3, 5]
    var defaultRestSeconds: Double = 90
    init(revision: Int = 0, exercises: [Exercise], absDays: [Int] = [1, 3, 5], defaultRestSeconds: Double = 90) {
        self.revision = revision; self.exercises = exercises; self.absDays = absDays; self.defaultRestSeconds = defaultRestSeconds
    }
    private enum CodingKeys: String, CodingKey { case revision, exercises, absDays, defaultRestSeconds, routineLibrary }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        routineLibrary = try values.decodeIfPresent([WorkoutRoutine].self, forKey: .routineLibrary)
        revision = try values.decode(Int.self, forKey: .revision)
        exercises = try values.decode([Exercise].self, forKey: .exercises)
        absDays = try values.decode([Int].self, forKey: .absDays)
        defaultRestSeconds = try values.decodeIfPresent(Double.self, forKey: .defaultRestSeconds) ?? 90
    }
    var routines: [WorkoutRoutine] {
        routineLibrary ?? Split.workoutTypes.map { split in
            WorkoutRoutine.builtIn(split, exercises: exercises.filter { $0.split == split }.map(\.withConfirmedDefaults))
        }
    }
    var availableRoutines: [WorkoutRoutine] { routines.filter { !$0.archived } }
    func routine(id: String) -> WorkoutRoutine? { routines.first { $0.id == id } }
    mutating func saveRoutine(_ routine: WorkoutRoutine) {
        var values = routines
        if let index = values.firstIndex(where: { $0.id == routine.id }) { values[index] = routine }
        else { values.append(routine) }
        for exercise in routine.exercises where !exercises.contains(where: { $0.id == exercise.id }) { exercises.append(exercise) }
        routineLibrary = values
    }
    func routine(day: Int) -> [Exercise] {
        if let routineLibrary, let routine = routineLibrary.first(where: { $0.legacySplit == Split.at(day: day) }) {
            return routine.exercises.map(\.withConfirmedDefaults)
        }
        return exercises.filter { $0.split == Split.at(day: day) }
            .map(\.withConfirmedDefaults)
    }
    static let seed = TrainingPlan(exercises: [
        Exercise(id: "pullup", name: "Assisted Pull-up", split: .back, load: .init(kind: .assistance, pounds: 70)),
        Exercise(id: "back-extension", name: "Back Extension Machine", split: .back, load: .init(kind: .unknown, pounds: nil)),
        Exercise(id: "row", name: "Row Machine", split: .back, load: .init(kind: .machine, pounds: 35)),
        Exercise(id: "curl", name: "Bicep Curl Machine", split: .back, load: .init(kind: .machine, pounds: 20)),
        Exercise(id: "hamstring", name: "Hamstring Curl Machine", split: .glutes, load: .init(kind: .machine, pounds: 35)),
        Exercise(id: "thrust", name: "Smith Machine Hip Thrust", split: .glutes, load: .init(kind: .smith, pounds: 25)),
        Exercise(id: "abduction", name: "Hip Abduction", split: .glutes, load: .init(kind: .machine, pounds: 65)),
        Exercise(id: "press", name: "Seated Leg Press", split: .legs, load: .init(kind: .machine, pounds: 80)),
        Exercise(id: "squat", name: "Smith Machine Squat", split: .legs, load: .init(kind: .smith, pounds: 10)),
        Exercise(id: "adduction", name: "Hip Adduction", split: .legs, load: .init(kind: .machine, pounds: 65)),
        Exercise(id: "abs", name: "Abs", split: nil, load: .init(kind: .unknown, pounds: nil), notes: "Weighted mat routine. Log your added weight, sets and reps.")
    ])
    func validate() throws {
        if let routineLibrary {
            guard Set(routineLibrary.map(\.id)).count == routineLibrary.count else { throw TrainingError.invalidPlan }
            for routine in routineLibrary {
                guard !routine.id.isEmpty, !routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      routine.name.count <= 80, !routine.exercises.isEmpty else { throw TrainingError.invalidPlan }
                try TrainingPlan(exercises: routine.exercises).validate()
            }
        }
        guard revision >= 0, revision < Int.max, defaultRestSeconds.isFinite, (0...1800).contains(defaultRestSeconds), Set(exercises.map(\.id)).count == exercises.count,
              !exercises.isEmpty, Set(absDays).count == absDays.count,
              absDays.allSatisfy({ (1...6).contains($0) }) else { throw TrainingError.invalidPlan }
        for exercise in exercises {
            guard !exercise.id.isEmpty, !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (1...20).contains(exercise.sets), (0...100).contains(exercise.reps),
                  exercise.restSeconds.isFinite, (0...1800).contains(exercise.restSeconds),
                  exercise.increment.isFinite, (0.25...100).contains(exercise.increment) else { throw TrainingError.invalidPlan }
            try exercise.load.validate()
        }
    }
}

struct ExerciseDraft: Codable, Equatable, Sendable {
    var load: TrainingLoad
    var reps: Int
}

// Completed observations never change. Corrections are separate append-only events.
struct CompletedSet: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let exerciseID: String
    let exerciseName: String
    let ordinal: Int
    let load: TrainingLoad
    let reps: Int
    let completedAt: Date
}
struct SetCorrection: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let setID: UUID
    let load: TrainingLoad
    let reps: Int
    let voided: Bool
    let date: Date
}
struct LoggedSet: Identifiable, Equatable, Sendable {
    let original: CompletedSet
    let load: TrainingLoad
    let reps: Int
    var id: UUID { original.id }
}

enum HealthSaveState: String, Codable, Sendable {
    case notStarted, recording, saving, saved, recovery, notFound
    var title: String {
        switch self {
        case .notStarted: return "Health workout not started"
        case .recording: return "Health workout recording"
        case .saving: return "Saving to Apple Health"
        case .saved: return "Saved to Apple Health"
        case .recovery: return "Health save needs review"
        case .notFound: return "Health record unavailable or deleted"
        }
    }
}

struct StrengthSession: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let day: Int
    let startedAt: Date
    let routine: [Exercise]
    var routineID: String?
    var routineName: String?
    var routineColor: RoutineColor?
    var routineSymbol: String?
    var revision = 0
    var sets: [CompletedSet] = []
    var corrections: [SetCorrection] = []
    var skipped: [String] = []
    // Optional fields keep archives from the original six-session app readable.
    var offersFinisher: Bool?
    var finisherChoice: Bool?
    var exerciseDrafts: [String: ExerciseDraft]?
    var exerciseIndex = 0
    var draftLoad: TrainingLoad
    var draftReps: Int
    var pendingSetID = UUID()
    var lastTapAt: Date?
    var restUntil: Date?
    var restHapticDelivered = false
    var endedAt: Date?
    var completed = false
    var nextDayAfterCompletion: Int?
    var cycleID: UUID?
    var rotationAfterCompletion: RotationState?
    var healthState: HealthSaveState = .notStarted
    var healthUUID: UUID?
    var healthError: String?
    var elapsed: Double?
    var activeEnergy: Double?
    var currentExercise: Exercise? { routine.indices.contains(exerciseIndex) ? routine[exerciseIndex] : nil }
    var effectiveSets: [LoggedSet] {
        sets.compactMap { set in
            let correction = corrections.last { $0.setID == set.id }
            guard correction?.voided != true else { return nil }
            return LoggedSet(original: set, load: correction?.load ?? set.load, reps: correction?.reps ?? set.reps)
        }
    }
    func isAvailable(_ exercise: Exercise) -> Bool {
        (offersFinisher != true || exercise.id != "abs" || finisherChoice == true)
            && !skipped.contains(exercise.id) && count(for: exercise.id) < exercise.sets
    }
    // Explicitly choosing an unfinished finisher opts into it. Automatic
    // advancement still uses isAvailable, so Abs remains optional until chosen.
    func isSelectable(_ exercise: Exercise) -> Bool {
        !skipped.contains(exercise.id) && count(for: exercise.id) < exercise.sets &&
            (isAvailable(exercise) || (offersFinisher == true && exercise.id == "abs"))
    }
    var remainingExerciseIndices: [Int] { routine.indices.filter { isAvailable(routine[$0]) } }
    var needsFinisherChoice: Bool {
        offersFinisher == true && finisherChoice == nil && currentExercise == nil
    }
    var plannedSets: Int {
        routine.filter { offersFinisher != true || $0.id != "abs" || finisherChoice == true }
            .reduce(0) { $0 + $1.sets }
    }
    func count(for id: String) -> Int { effectiveSets.filter { $0.original.exerciseID == id }.count }
    func remainingRest(at date: Date) -> Int { max(0, Int(ceil(restUntil?.timeIntervalSince(date) ?? 0))) }
    var title: String { routineName ?? Split.at(day: day).title }
}

struct CorrectionRequest: Codable, Equatable, Sendable {
    let sessionID: UUID
    let expectedRevision: Int
    let correction: SetCorrection
}

enum SyncPayload: Codable, Equatable, Sendable {
    case workout(StrengthSession)
    case restoreWorkout(StrengthSession)
    case plan(TrainingPlan)
    case correction(CorrectionRequest)
    case requestHistory
    case planBackup(TrainingPlan)
    case rotation(RotationState)
    case receipt(UUID, String?)
}
struct SyncEvent: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let payload: SyncPayload
    nonisolated var requiresReceipt: Bool { if case .receipt = payload { return false }; return true }
}
struct SyncReceipt: Codable, Equatable, Sendable {
    var revision: Int
    var date: Date
}
struct TrainingArchive: Codable, Equatable, Sendable {
    // Optional for compatibility with existing device archives. Phone deletion survives stale snapshots.
    var deletedSessionIDs: Set<UUID>?
    var schemaVersion = 1
    var plan = TrainingPlan.seed
    var sessions: [StrengthSession] = []
    var nextDay = 1
    var rotationRevision = 0
    var rotation: RotationState?
    var outbox: [SyncEvent] = []
    var processedRequests: [UUID: String] = [:]
    var received: [UUID: SyncReceipt] = [:]
    var syncIssues: [String] = []
}

enum TrainingError: LocalizedError {
    case invalidLoad, invalidPlan, noExercise, activeSession, invalidState, duplicateTap, conflict, invalidArchive
    var errorDescription: String? {
        switch self {
        case .invalidLoad: return "Enter a valid load with the correct weight basis."
        case .invalidPlan: return "Check the exercise names, targets, rest durations and increments."
        case .noExercise: return "No remaining exercise. End the workout when ready."
        case .activeSession: return "Review the existing session before starting another."
        case .invalidState: return "This action is unavailable in the current workout state."
        case .duplicateTap: return "Set already recorded."
        case .conflict: return "This record changed. Refresh it before correcting the set."
        case .invalidArchive: return "This backup is unsupported or contains invalid records."
        }
    }
}

struct ProgressPoint: Identifiable {
    let id: UUID
    let sessionID: UUID
    let date: Date
    let load: Double
    let reps: Int
    let comparisonKey: String
}

struct SessionLoadPoint: Identifiable, Equatable {
    let id: UUID
    let setID: UUID
    let date: Date
    let load: Double
    let reps: Int
}

struct ExercisePerformance: Identifiable {
    let id: UUID
    let date: Date
    let sets: Int
    let reps: Int
    let workingLoad: Double?
    let volume: Double?
}

struct WorkingLoadRecord: Identifiable {
    let id: UUID
    let sessionID: UUID
    let date: Date
    let load: Double
    let previous: Double?
}

enum TrainingProgress {
    /// One verifiable representative set per completed session and exact load basis.
    static func sessionLoadPoints(exerciseID: String, comparisonKey: String,
                                  sessions: [StrengthSession]) -> [SessionLoadPoint] {
        let assistance = comparisonKey.hasPrefix("assistance:")
        return sessions.filter(\.completed).compactMap { session in
            let sets = session.effectiveSets.filter {
                $0.original.exerciseID == exerciseID && $0.load.comparisonKey == comparisonKey
                    && $0.load.pounds != nil && $0.reps > 0
            }
            let selected = sets.sorted { a, b in
                let lhs = a.load.pounds!, rhs = b.load.pounds!
                if lhs != rhs { return assistance ? lhs < rhs : lhs > rhs }
                if a.reps != b.reps { return a.reps > b.reps }
                return a.original.completedAt < b.original.completedAt
            }.first
            guard let selected, let pounds = selected.load.pounds else { return nil }
            return SessionLoadPoint(id: session.id, setID: selected.id, date: session.startedAt,
                                    load: pounds, reps: selected.reps)
        }.sorted { $0.date < $1.date }
    }

    /// A suggestion only; never advances a schedule or overrides a same-day choice.
    static func suggestedWorkout(sessions: [StrengthSession], today: Date = .now,
                                 calendar: Calendar = .current) -> Split? {
        let completed = sessions.filter { $0.completed && $0.endedAt != nil }
        if completed.contains(where: { calendar.isDate($0.endedAt!, inSameDayAs: today) }) { return nil }
        guard let latest = completed.max(by: { $0.endedAt! < $1.endedAt! }) else { return nil }
        if let id = latest.routineID, !Split.allCases.contains(where: { $0.rawValue == id }) { return nil }
        switch Split.at(day: latest.day) {
        case .glutes: return .back
        case .back: return .legs
        case .legs: return .glutes
        }
    }

    static func performances(exerciseID: String, comparisonKey: String, sessions: [StrengthSession]) -> [ExercisePerformance] {
        sessions.filter(\.completed).compactMap { session in
            let sets = session.effectiveSets.filter { $0.original.exerciseID == exerciseID && $0.load.comparisonKey == comparisonKey }
            guard !sets.isEmpty else { return nil }
            let loads = sets.compactMap { $0.load.pounds }
            let assistance = sets.first?.load.kind == .assistance
            let volume = sets.allSatisfy { $0.load.volumeLoad != nil }
                ? sets.reduce(0.0) { $0 + ($1.load.volumeLoad ?? 0) * Double($1.reps) } : nil
            return ExercisePerformance(id: session.id, date: session.startedAt, sets: sets.count,
                                       reps: sets.reduce(0) { $0 + $1.reps },
                                       workingLoad: assistance ? loads.min() : loads.max(), volume: volume)
        }.sorted { $0.date < $1.date }
    }
    static func records(exercise: Exercise, comparisonKey: String, sessions: [StrengthSession]) -> [WorkingLoadRecord] {
        let assistance = comparisonKey.hasPrefix("assistance:")
        var best: Double?
        var results: [WorkingLoadRecord] = []
        for point in points(exerciseID: exercise.id, sessions: sessions)
            where point.comparisonKey == comparisonKey && point.reps > 0 && point.reps >= exercise.reps {
            if let best, assistance ? point.load >= best : point.load <= best { continue }
            results.append(WorkingLoadRecord(id: point.id, sessionID: point.sessionID, date: point.date, load: point.load, previous: best))
            best = point.load
        }
        return results
    }
    static func points(exerciseID: String, sessions: [StrengthSession]) -> [ProgressPoint] {
        sessions.filter(\.completed).flatMap { session in
            session.effectiveSets.filter { $0.original.exerciseID == exerciseID }.compactMap { set in
                set.load.pounds.map { ProgressPoint(id: set.id, sessionID: session.id, date: set.original.completedAt, load: $0, reps: set.reps, comparisonKey: set.load.comparisonKey) }
            }
        }.sorted { $0.date < $1.date }
    }
    static func suggestion(exercise: Exercise, sessions: [StrengthSession]) -> TrainingLoad? {
        guard exercise.load.kind == .machine || exercise.load.kind == .smith || exercise.load.kind == .assistance,
              let last = sessions.filter({ $0.completed && $0.effectiveSets.contains { $0.original.exerciseID == exercise.id } })
                .max(by: { $0.startedAt < $1.startedAt }) else { return nil }
        let sets = last.effectiveSets.filter { $0.original.exerciseID == exercise.id }
        guard sets.count == exercise.sets, let load = sets.first?.load, let pounds = load.pounds,
              (sets.last?.original.completedAt ?? .distantPast) > exercise.preferenceUpdatedAt,
              load.comparisonKey == exercise.load.comparisonKey,
              sets.allSatisfy({ $0.reps > 0 && $0.reps >= exercise.reps && $0.load == load }) else { return nil }
        var next = load
        next.pounds = max(0, pounds + (load.kind == .assistance ? -exercise.increment : exercise.increment))
        return next == load ? nil : next
    }
}
