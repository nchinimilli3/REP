import Foundation
import Combine

@MainActor
final class TrainingStore: ObservableObject {
    @Published private(set) var archive: TrainingArchive
    @Published var errorMessage: String?
    private let fileURL: URL
    @Published private(set) var storageReady = false
    @Published private(set) var preservedArchiveURL: URL?
    @Published private(set) var maintenanceMessage: String?
    let isPreview: Bool
    let isWatch: Bool
    var didCommit: (() -> Void)?
    private let journal: TrainingJournal

    init(fileURL: URL? = nil, isWatch: Bool, isPreview: Bool = false) {
        self.isPreview = isPreview
        self.isWatch = isWatch
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("REP", isDirectory: true).appendingPathComponent("training-v1.json")
        journal = TrainingJournal(fileURL: self.fileURL)
        archive = TrainingArchive()
        do {
            let decoded = try journal.load()
            try Self.validate(decoded)
            archive = decoded
            preservedArchiveURL = journal.preservedOriginalURL
            storageReady = true
        } catch {
            errorMessage = "Local records could not be opened: \(error.localizedDescription). The file has been preserved. Restore a backup before recording."
        }
    }

    var activeSession: StrengthSession? { archive.sessions.last { $0.endedAt == nil } }
    var visibleSessions: [StrengthSession] { archive.sessions.filter { !(archive.deletedSessionIDs ?? []).contains($0.id) } }
    var history: [StrengthSession] { visibleSessions.sorted { $0.startedAt > $1.startedAt } }
    func session(_ id: UUID) -> StrengthSession? { archive.sessions.first { $0.id == id } }
    /// Called only after confirmed Health deletion, or for a finished log with no Health record.
    func deleteFromPhone(_ id: UUID) throws {
        guard !isWatch, let session = session(id), session.endedAt != nil,
              session.healthState != .recording, session.healthState != .saving else { throw TrainingError.invalidState }
        try commit { archive in
            archive.deletedSessionIDs = (archive.deletedSessionIDs ?? []).union([id])
            archive.sessions.removeAll { $0.id == id }
            archive.outbox.removeAll { event in
                if case .correction(let request) = event.payload { return request.sessionID == id }
                if case .restoreWorkout(let value) = event.payload { return value.id == id }
                return false
            }
        }
    }
    func syncLabel(_ session: StrengthSession) -> String {
        if let receipt = archive.received[session.id], receipt.revision >= session.revision { return "Received by iPhone" }
        return isWatch ? "iPhone receipt pending" : "Watch record stored on iPhone"
    }

    private func commit(_ change: (inout TrainingArchive) throws -> Void) throws {
        guard storageReady else { throw TrainingError.invalidArchive }
        var next = archive
        try change(&next)
        try persist(next)
    }
    private func persist(_ next: TrainingArchive) throws {
        try Self.validateChanges(from: archive, to: next)
        do { try journal.append(before: archive, after: next) }
        catch {
            // A failed flush may leave an ambiguous last transaction. Reopen or
            // recover before accepting another edit rather than overwriting it.
            storageReady = false
            throw error
        }
        archive = next
        storageReady = true
        didCommit?()
    }
    private static func queue(_ payload: SyncPayload, in archive: inout TrainingArchive) {
        // Coalesce only replaceable snapshots; receipts reference exact event IDs.
        archive.outbox.removeAll { event in
            switch (event.payload, payload) {
            case (.workout(let a), .workout(let b)): return a.id == b.id
            case (.restoreWorkout(let a), .restoreWorkout(let b)): return a.id == b.id
            case (.planBackup, .planBackup): return true
            case (.plan, .plan): return true
            case (.rotation, .rotation): return true
            default: return false
            }
        }
        archive.outbox.append(SyncEvent(id: UUID(), payload: payload))
    }
    private static func establishRotation(in archive: inout TrainingArchive) -> RotationState {
        if let rotation = archive.rotation { return rotation }
        let state = RotationState(revision: archive.rotationRevision, nextDay: archive.nextDay, cycleID: UUID())
        archive.rotation = state
        return state
    }
    private func mutate(_ id: UUID, _ change: (inout StrengthSession, inout TrainingArchive) throws -> Void) throws {
        guard isWatch else { throw TrainingError.invalidState }
        try commit { archive in
            guard let index = archive.sessions.firstIndex(where: { $0.id == id }) else { throw TrainingError.invalidState }
            var session = archive.sessions[index]
            try change(&session, &archive)
            session.revision += 1
            archive.sessions[index] = session
            Self.queue(.workout(session), in: &archive)
        }
    }
    func perform(_ action: () throws -> Void) {
        do { try action(); errorMessage = nil } catch { errorMessage = error.localizedDescription }
    }

    func recalledLoad(_ exercise: Exercise) -> TrainingLoad {
        let set = visibleSessions.flatMap(\.effectiveSets)
            .filter { $0.original.exerciseID == exercise.id && $0.load.comparisonKey == exercise.load.comparisonKey }
            .max { $0.original.completedAt < $1.original.completedAt }
        guard let set, set.original.completedAt > exercise.preferenceUpdatedAt else { return exercise.load }
        return set.load
    }
    @discardableResult
    func begin(routineID: String, date: Date = .now) throws -> UUID {
        guard let routine = archive.plan.routine(id: routineID), !routine.archived else { throw TrainingError.noExercise }
        return try begin(day: routine.legacySplit?.day ?? 1, date: date, selectedRoutine: routine)
    }
    @discardableResult
    func begin(day: Int, date: Date = .now, selectedRoutine: WorkoutRoutine? = nil) throws -> UUID {
        guard isWatch, (1...6).contains(day) else { throw TrainingError.invalidState }
        guard activeSession == nil else { throw TrainingError.activeSession }
        let mainRoutine = selectedRoutine?.exercises ?? archive.plan.routine(day: day)
        guard let first = mainRoutine.first else { throw TrainingError.noExercise }
        let routine = mainRoutine + archive.plan.exercises.filter { $0.id == "abs" }.map(\.withConfirmedDefaults)
        let id = UUID()
        let load = recalledLoad(first)
        try commit { archive in
            let rotation = Self.establishRotation(in: &archive)
            var record = StrengthSession(id: id, day: day, startedAt: date, routine: routine,
                                         draftLoad: load, draftReps: first.reps)
            if let selectedRoutine {
                record.routineID = selectedRoutine.id
                record.routineName = selectedRoutine.name
                record.routineColor = selectedRoutine.color
                record.routineSymbol = selectedRoutine.symbol
            }
            record.offersFinisher = routine.contains { $0.id == "abs" }
            record.cycleID = rotation.cycleID
            archive.sessions.append(record)
            Self.queue(.workout(record), in: &archive)
            Self.queue(.rotation(rotation), in: &archive)
        }
        return id
    }
    func setHealth(_ id: UUID, state: HealthSaveState, uuid: UUID? = nil, error: String? = nil,
                   elapsed: Double? = nil, energy: Double? = nil) throws {
        try mutate(id) { session, _ in
            session.healthState = state
            if let uuid { session.healthUUID = uuid }
            session.healthError = error
            if let elapsed { session.elapsed = elapsed }
            if let energy { session.activeEnergy = energy }
        }
    }
    func editDraft(_ id: UUID, load: TrainingLoad, reps: Int) throws {
        try load.validate()
        guard (0...100).contains(reps) else { throw TrainingError.invalidState }
        try mutate(id) { session, _ in
            guard session.endedAt == nil else { throw TrainingError.invalidState }
            session.draftLoad = load
            session.draftReps = reps
        }
    }
    @discardableResult
    func logSet(_ id: UUID, token: UUID, date: Date = .now) throws -> Bool {
        guard let existing = session(id) else { throw TrainingError.invalidState }
        if existing.sets.contains(where: { $0.id == token }) { return false }
        try mutate(id) { session, _ in
            guard session.endedAt == nil, session.healthState == .recording,
                  session.restUntil == nil, let exercise = session.currentExercise else { throw TrainingError.invalidState }
            guard token == session.pendingSetID, date.timeIntervalSince(session.lastTapAt ?? .distantPast) > 0.8 else { throw TrainingError.duplicateTap }
            session.sets.append(CompletedSet(id: token, exerciseID: exercise.id, exerciseName: exercise.name,
                                            ordinal: session.count(for: exercise.id) + 1, load: session.draftLoad,
                                            reps: session.draftReps, completedAt: date))
            session.lastTapAt = date
            session.pendingSetID = UUID()
            session.restUntil = date.addingTimeInterval(exercise.restSeconds)
            session.restHapticDelivered = false
            session.draftReps = exercise.reps
            if session.count(for: exercise.id) >= exercise.sets {
                session.exerciseDrafts?[exercise.id] = nil
                advanceExercise(&session)
                if session.currentExercise == nil { session.restUntil = nil }
            }
        }
        return true
    }
    func skipExercise(_ id: UUID) throws {
        try mutate(id) { session, _ in
            guard session.endedAt == nil, let current = session.currentExercise else { throw TrainingError.noExercise }
            session.skipped.append(current.id)
            advanceExercise(&session)
            session.restUntil = nil
        }
    }
    private func activateExercise(_ index: Int, in session: inout StrengthSession) {
        session.exerciseIndex = index
        session.pendingSetID = UUID()
        if let exercise = session.currentExercise {
            let draft = session.exerciseDrafts?[exercise.id]
            session.draftLoad = draft?.load ?? recalledLoad(exercise)
            session.draftReps = draft?.reps ?? exercise.reps
        }
    }
    private func advanceExercise(_ session: inout StrengthSession) {
        let next = session.remainingExerciseIndices.first ?? session.routine.count
        activateExercise(next, in: &session)
    }
    func selectExercise(_ id: UUID, exerciseID: String) throws {
        try mutate(id) { session, _ in
            guard session.endedAt == nil,
                  let index = session.routine.firstIndex(where: { $0.id == exerciseID }),
                  session.isSelectable(session.routine[index]) else { throw TrainingError.invalidState }
            if session.offersFinisher == true && session.routine[index].id == "abs" {
                session.finisherChoice = true
            }
            if let current = session.currentExercise {
                var drafts = session.exerciseDrafts ?? [:]
                drafts[current.id] = ExerciseDraft(load: session.draftLoad, reps: session.draftReps)
                session.exerciseDrafts = drafts
            }
            activateExercise(index, in: &session)
            // Rest belongs to the last logged set and survives a machine change.
        }
    }
    func chooseFinisher(_ id: UUID, include: Bool) throws {
        try mutate(id) { session, _ in
            guard session.endedAt == nil, session.needsFinisherChoice else { throw TrainingError.invalidState }
            session.finisherChoice = include
            if include { advanceExercise(&session) }
        }
    }
    func rest(_ id: UUID, extend: Bool) throws {
        try mutate(id) { session, _ in
            guard session.endedAt == nil else { throw TrainingError.invalidState }
            session.restUntil = extend ? max(session.restUntil ?? .now, .now).addingTimeInterval(30) : nil
            if extend { session.restHapticDelivered = false }
        }
    }
    func markRestHaptic(_ id: UUID) throws {
        try mutate(id) { session, _ in session.restHapticDelivered = true }
    }
    func undoLastSet(_ id: UUID) throws {
        try mutate(id) { session, _ in
            guard session.endedAt == nil, let last = session.effectiveSets.last,
                  let index = session.routine.firstIndex(where: { $0.id == last.original.exerciseID }) else { throw TrainingError.invalidState }
            session.corrections.append(.init(id: UUID(), setID: last.id, load: last.load, reps: last.reps, voided: true, date: .now))
            session.exerciseIndex = index
            if session.finisherChoice == false { session.finisherChoice = nil }
            session.skipped.removeAll { $0 == last.original.exerciseID }
            session.draftLoad = last.load
            session.draftReps = last.reps
            session.pendingSetID = UUID()
            session.restUntil = nil
        }
    }
    func finalizeLocal(_ id: UUID, completed: Bool, advanceFromDay: Int?, date: Date = .now) throws {
        try mutate(id) { session, archive in
            guard session.endedAt == nil else { throw TrainingError.invalidState }
            session.endedAt = date
            session.completed = completed
            session.restUntil = nil
            if completed, let day = advanceFromDay, (1...6).contains(day) {
                let current = Self.establishRotation(in: &archive)
                let next = try current.advancing(from: day)
                if session.cycleID == nil { session.cycleID = current.cycleID }
                session.nextDayAfterCompletion = next.nextDay
                session.rotationAfterCompletion = next
                try archive.adoptRotation(next)
                Self.queue(.rotation(next), in: &archive)
            }
        }
        if journal.pendingTransactionCount >= 128 {
            do { try journal.compact(archive); maintenanceMessage = nil }
            catch { maintenanceMessage = "Your local log is saved. Storage cleanup will need to be retried." }
        }
    }
    func savePlan(_ plan: TrainingPlan) throws {
        guard !isWatch else { throw TrainingError.invalidState }
        try plan.validate()
        try commit { archive in
            var next = plan
            next.revision = archive.plan.revision + 1
            guard plan.revision == archive.plan.revision else { throw TrainingError.conflict }
            archive.plan = next
            Self.queue(.plan(next), in: &archive)
        }
    }
    func requestCorrection(session: StrengthSession, set: LoggedSet, load: TrainingLoad, reps: Int) throws {
        try load.validate()
        guard session.endedAt != nil, (0...100).contains(reps) else { throw TrainingError.invalidState }
        let correction = SetCorrection(id: UUID(), setID: set.id, load: load, reps: reps, voided: false, date: .now)
        if isPreview {
            try commit { archive in
                guard let index = archive.sessions.firstIndex(where: { $0.id == session.id }),
                      archive.sessions[index].revision == session.revision else { throw TrainingError.conflict }
                archive.sessions[index].corrections.append(correction)
                archive.sessions[index].revision += 1
            }
        } else if isWatch {
            try mutate(session.id) { current, _ in
                guard current.revision == session.revision else { throw TrainingError.conflict }
                current.corrections.append(correction)
            }
        } else {
            try commit { archive in
                Self.queue(.correction(.init(sessionID: session.id, expectedRevision: session.revision, correction: correction)), in: &archive)
            }
        }
    }
    func hasPendingCorrection(_ id: UUID) -> Bool {
        archive.outbox.contains { if case .correction(let request) = $0.payload { return request.sessionID == id }; return false }
    }
    func resendSnapshots() throws {
        try commit { archive in
            if isWatch {
                let rotation = Self.establishRotation(in: &archive)
                Self.queue(.rotation(rotation), in: &archive)
                for session in archive.sessions where archive.received[session.id]?.revision != session.revision {
                    if !archive.outbox.contains(where: { if case .workout(let value) = $0.payload { return value.id == session.id }; return false }) {
                        Self.queue(.workout(session), in: &archive)
                    }
                }
            } else if !archive.outbox.contains(where: { if case .plan = $0.payload { return true }; return false }) {
                Self.queue(.plan(archive.plan), in: &archive)
            }
            if !isWatch && !archive.outbox.contains(where: { if case .requestHistory = $0.payload { return true }; return false }) {
                Self.queue(.requestHistory, in: &archive)
            }
        }
    }
    func restoreWatchHistory() throws {
        guard !isWatch else { throw TrainingError.invalidState }
        try commit { archive in
            for session in archive.sessions where session.endedAt != nil {
                Self.queue(.restoreWorkout(session), in: &archive)
            }
        }
    }
    func transferFinished(_ id: UUID) throws {
        guard archive.outbox.contains(where: { $0.id == id && !$0.requiresReceipt }) else { return }
        try commit { $0.outbox.removeAll { $0.id == id && !$0.requiresReceipt } }
    }
    func receive(_ event: SyncEvent) throws {
        try commit { archive in
            if case .receipt(let eventID, let issue) = event.payload {
                if let pending = archive.outbox.first(where: { $0.id == eventID }) {
                    if let issue { archive.syncIssues.append(issue) }
                    else if case .workout(let session) = pending.payload {
                        let old = archive.received[session.id]?.revision ?? -1
                        archive.received[session.id] = .init(revision: max(old, session.revision), date: .now)
                    }
                    archive.outbox.removeAll { $0.id == eventID }
                }
                return
            }
            var rejection: String?
            switch event.payload {
            case .workout(let incoming):
                guard !isWatch else { throw TrainingError.invalidState }
                if archive.deletedSessionIDs?.contains(incoming.id) == true { break }
                if let i = archive.sessions.firstIndex(where: { $0.id == incoming.id }) {
                    let current = archive.sessions[i]
                    if incoming.revision > current.revision { archive.sessions[i] = incoming }
                    else if incoming.revision == current.revision && incoming != current { throw TrainingError.conflict }
                } else { archive.sessions.append(incoming) }
                try archive.reconcileRotationFromHistory()
            case .restoreWorkout(let incoming):
                guard isWatch, incoming.endedAt != nil else { throw TrainingError.invalidState }
                if let current = archive.sessions.first(where: { $0.id == incoming.id }) {
                    if incoming.revision > current.revision || (incoming.revision == current.revision && incoming != current) {
                        rejection = "Watch history differs from the backup. Export both copies before reconciling; no records were overwritten."
                    }
                } else if archive.sessions.contains(where: { $0.endedAt == nil }) {
                    rejection = "Finish the active Watch session before restoring history."
                } else {
                    archive.sessions.append(incoming)
                    try archive.reconcileRotationFromHistory()
                }
            case .plan(let incoming):
                guard isWatch else { throw TrainingError.invalidState }
                if incoming.revision > archive.plan.revision { archive.plan = incoming }
                else if incoming.revision == archive.plan.revision && incoming != archive.plan { throw TrainingError.conflict }
            case .correction(let request):
                guard isWatch else { throw TrainingError.invalidState }
                if let prior = archive.processedRequests[event.id] {
                    rejection = prior.isEmpty ? nil : prior
                } else {
                    if let i = archive.sessions.firstIndex(where: { $0.id == request.sessionID }),
                       archive.sessions[i].revision == request.expectedRevision,
                       archive.sessions[i].endedAt != nil,
                       archive.sessions[i].effectiveSets.contains(where: { $0.id == request.correction.setID }) {
                        archive.sessions[i].corrections.append(request.correction)
                        archive.sessions[i].revision += 1
                        Self.queue(.workout(archive.sessions[i]), in: &archive)
                    } else { rejection = "Correction could not be applied because the Watch record changed. Refresh and try again." }
                    archive.processedRequests[event.id] = rejection ?? ""
                }
            case .requestHistory:
                guard isWatch else { throw TrainingError.invalidState }
                let rotation = Self.establishRotation(in: &archive)
                Self.queue(.rotation(rotation), in: &archive)
                for session in archive.sessions { Self.queue(.workout(session), in: &archive) }
                Self.queue(.planBackup(archive.plan), in: &archive)
            case .planBackup(let plan):
                guard !isWatch else { throw TrainingError.invalidState }
                if archive.plan == .seed { archive.plan = plan }
                else if plan.revision > archive.plan.revision {
                    rejection = "Watch has a newer routine than this iPhone. Export both devices before reconciling the routine."
                    archive.syncIssues.append(rejection!)
                }
            case .rotation(let state):
                guard !isWatch else { throw TrainingError.invalidState }
                try archive.adoptRotation(state)
            case .receipt: break
            }
            if !archive.outbox.contains(where: { if case .receipt(let id, _) = $0.payload { return id == event.id }; return false }) {
                Self.queue(.receipt(event.id, rejection), in: &archive)
            }
        }
    }
    func exportData() throws -> Data {
        guard storageReady else { throw TrainingError.invalidArchive }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }
    func restore(_ data: Data) throws {
        guard !isWatch, activeSession == nil else { throw TrainingError.activeSession }
        let backup = try JSONDecoder().decode(TrainingArchive.self, from: data)
        try Self.validate(backup)
        if storageReady {
            try commit { try Self.mergeBackup(backup, into: &$0) }
        } else {
            // Validate the entire replacement before touching the unreadable source.
            var replacement = TrainingArchive()
            try Self.mergeBackup(backup, into: &replacement)
            try Self.validate(replacement)
            // Preserve checkpoint and transactions before selecting a fresh
            // generation. Earlier data is never replayed over the recovery.
            let preserved = try journal.preserveOriginal()
            try journal.replace(with: replacement, preservedURL: preserved)
            archive = replacement
            preservedArchiveURL = preserved
            storageReady = true
            didCommit?()
        }
        errorMessage = nil
    }
    private static func mergeBackup(_ backup: TrainingArchive, into archive: inout TrainingArchive) throws {
        // Merge records without rolling back local revisions or replaying exported transfers.
        archive.deletedSessionIDs = (archive.deletedSessionIDs ?? []).union(backup.deletedSessionIDs ?? [])
        let deleted = archive.deletedSessionIDs ?? []
        archive.sessions.removeAll { deleted.contains($0.id) }
        for session in backup.sessions {
            if archive.deletedSessionIDs?.contains(session.id) == true { continue }
            guard session.endedAt != nil else { throw TrainingError.activeSession }
            if let i = archive.sessions.firstIndex(where: { $0.id == session.id }) {
                if session.revision == archive.sessions[i].revision && session != archive.sessions[i] { throw TrainingError.conflict }
                if session.revision > archive.sessions[i].revision { archive.sessions[i] = session }
            } else { archive.sessions.append(session) }
        }
        if archive.plan == .seed {
            var plan = backup.plan
            plan.revision = max(archive.plan.revision, plan.revision) + 1
            archive.plan = plan
            Self.queue(.plan(plan), in: &archive)
        }
        if let state = backup.rotation { try archive.adoptRotation(state) }
        try archive.reconcileRotationFromHistory()
    }
    func exportPreservedArchive() throws -> Data {
        guard let preservedArchiveURL else { throw TrainingError.invalidArchive }
        return try journal.exportPreserved(preservedArchiveURL)
    }
    static func validate(_ archive: TrainingArchive) throws {
        try validateHeader(archive)
        for session in archive.sessions { try validateSession(session) }
        for event in archive.outbox { try validateEvent(event) }
    }
    private static func validateChanges(from previous: TrainingArchive, to next: TrainingArchive) throws {
        try validateHeader(next)
        let sessions = Dictionary(uniqueKeysWithValues: previous.sessions.map { ($0.id, $0) })
        for session in next.sessions where sessions[session.id] != session { try validateSession(session) }
        let events = Dictionary(uniqueKeysWithValues: previous.outbox.map { ($0.id, $0) })
        for event in next.outbox where events[event.id] != event { try validateEvent(event) }
    }
    private static func validateHeader(_ archive: TrainingArchive) throws {
        guard archive.schemaVersion == 1, (1...6).contains(archive.nextDay), archive.rotationRevision >= 0, archive.rotationRevision < Int.max,
              Set(archive.sessions.map(\.id)).count == archive.sessions.count,
              Set(archive.outbox.map(\.id)).count == archive.outbox.count else { throw TrainingError.invalidArchive }
        try archive.plan.validate()
        if let state = archive.rotation {
            try state.validate()
            guard state.revision == archive.rotationRevision, state.nextDay == archive.nextDay else { throw TrainingError.invalidArchive }
        }
    }
    private static func validateEvent(_ event: SyncEvent) throws {
            switch event.payload {
            case .workout(let session), .restoreWorkout(let session): try validateSession(session)
            case .plan(let plan), .planBackup(let plan): try plan.validate()
            case .rotation(let state): try state.validate()
            case .correction(let request):
                try request.correction.load.validate()
                guard (0...100).contains(request.correction.reps) else { throw TrainingError.invalidArchive }
            case .receipt, .requestHistory: break
            }
    }
    private static func validateSession(_ session: StrengthSession) throws {
        guard (1...6).contains(session.day), session.revision >= 0, session.revision < Int.max,
              (0...session.routine.count).contains(session.exerciseIndex),
              (0...100).contains(session.draftReps),
              Set(session.sets.map(\.id)).count == session.sets.count,
              Set(session.corrections.map(\.id)).count == session.corrections.count,
              session.endedAt == nil || session.endedAt! >= session.startedAt,
              !session.completed || session.endedAt != nil,
              session.healthState != .saved || session.healthUUID != nil,
              session.nextDayAfterCompletion == nil || (session.completed && (1...6).contains(session.nextDayAfterCompletion!)) else { throw TrainingError.invalidArchive }
        try TrainingPlan(exercises: session.routine).validate()
        if let state = session.rotationAfterCompletion {
            try state.validate()
            guard session.cycleID != nil, session.completed, state.nextDay == session.nextDayAfterCompletion else { throw TrainingError.invalidArchive }
        }
        for (exerciseID, draft) in session.exerciseDrafts ?? [:] {
            guard session.routine.contains(where: { $0.id == exerciseID }), (0...100).contains(draft.reps) else { throw TrainingError.invalidArchive }
            try draft.load.validate()
        }
        try session.draftLoad.validate()
        for set in session.sets {
            try set.load.validate()
            guard (0...100).contains(set.reps), set.ordinal > 0, session.routine.contains(where: { $0.id == set.exerciseID }) else { throw TrainingError.invalidArchive }
        }
        for correction in session.corrections {
            try correction.load.validate()
            guard session.sets.contains(where: { $0.id == correction.setID }), (0...100).contains(correction.reps) else { throw TrainingError.invalidArchive }
        }
    }
}
