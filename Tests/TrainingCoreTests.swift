import Foundation

@main
@MainActor
struct TrainingCoreTests {
    static var passed = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "REPTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func rejects(_ action: () throws -> Void) throws {
        do { try action() } catch { return }
        throw NSError(domain: "REPTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected rejection"])
    }
    static func run(_ name: String, _ action: () throws -> Void) throws {
        try action(); passed += 1; print("PASS \(name)")
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("REP-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func store(_ name: String, watch: Bool = true) -> TrainingStore { TrainingStore(fileURL: root.appendingPathComponent(name + ".json"), isWatch: watch) }
        func started(_ records: TrainingStore, day: Int = 1) throws -> UUID {
            let id = try records.begin(day: day)
            try records.setHealth(id, state: .recording)
            return id
        }
        func log(_ records: TrainingStore, _ id: UUID, date: Date) throws {
            _ = try records.logSet(id, token: records.session(id)!.pendingSetID, date: date)
        }
        try run("Custom routines sync with shared exercise identity, independent targets and immutable history") {
            let phone = store("custom-phone", watch: false)
            var plan = phone.archive.plan
            var reused = plan.exercises[0]
            reused.sets = 2; reused.reps = 12; reused.restSeconds = 60
            let press = Exercise(id: "chest-press-fixture", name: "Chest Press", split: nil,
                                 load: .init(kind: .machine, pounds: 25), sets: 3, reps: 8)
            var custom = WorkoutRoutine(id: "custom-chest", name: "Chest + Arms", color: .blue,
                                        exercises: [reused, press])
            plan.saveRoutine(custom)
            try phone.savePlan(plan)
            try expect(phone.archive.plan.routine(day: 1)[0].sets == 4, "Reused exercise changed the original routine targets")
            let watch = store("custom-watch")
            let event = phone.archive.outbox.first { if case .plan = $0.payload { return true }; return false }!
            try watch.receive(event)
            let id = try watch.begin(routineID: custom.id)
            try watch.setHealth(id, state: .recording)
            try expect(watch.session(id)?.title == "Chest + Arms", "Custom title lost during sync/start")
            try expect(watch.session(id)?.plannedSets == 5, "Optional Abs counted as main work")
            try watch.selectExercise(id, exerciseID: press.id)
            try expect(watch.session(id)?.currentExercise?.id == press.id, "Custom exercise was mistaken for an optional finisher")
            try log(watch, id, date: .now)
            try watch.finalizeLocal(id, completed: true, advanceFromDay: nil)
            let snapshot = watch.session(id)!
            try expect(snapshot.sets[0].exerciseID == press.id && snapshot.routine[0].id == reused.id, "Shared exercise identity changed")
            custom.name = "Upper Body"; custom.color = .orange; custom.archived = true
            var revised = phone.archive.plan; revised.saveRoutine(custom); try phone.savePlan(revised)
            try watch.receive(.init(id: UUID(), payload: .plan(phone.archive.plan)))
            try expect(watch.session(id) == snapshot, "Plan edit rewrote completed workout")
            try rejects { _ = try watch.begin(routineID: custom.id) }
            try expect(watch.archive.plan.availableRoutines.allSatisfy { $0.id != custom.id }, "Archived routine remains in chooser")
            try expect(TrainingProgress.suggestedWorkout(sessions: [snapshot], today: .now.addingTimeInterval(86400)) == nil, "Custom routine imposed a built-in rotation")
            let reopened = store("custom-watch")
            try expect(reopened.session(id)?.routineColor == .blue && reopened.session(id)?.title == "Chest + Arms", "Custom historical appearance changed on restart")
        }
        try run("Session chart points retain actual reps, respect assistance and isolate load basis") {
            let exercise = TrainingPlan.seed.exercises[0]
            let date = Date.now.addingTimeInterval(-86400)
            var session = StrengthSession(id: UUID(), day: 1, startedAt: date, routine: [exercise], draftLoad: exercise.load, draftReps: 10)
            session.completed = true; session.endedAt = date.addingTimeInterval(1800)
            for (ordinal, load, reps) in [(1, 70.0, 12), (2, 60.0, 8), (3, 60.0, 10)] {
                session.sets.append(.init(id: UUID(), exerciseID: exercise.id, exerciseName: exercise.name,
                    ordinal: ordinal, load: .init(kind: .assistance, pounds: load), reps: reps, completedAt: date.addingTimeInterval(Double(ordinal) * 60)))
            }
            let points = TrainingProgress.sessionLoadPoints(exerciseID: exercise.id, comparisonKey: exercise.load.comparisonKey, sessions: [session])
            try expect(points.count == 1 && points[0].load == 60 && points[0].reps == 10, "Chart misrepresented a session's load/reps")
            try expect(points[0].setID == session.sets[2].id, "Chart point cannot be verified against an actual set")
            try expect(TrainingProgress.sessionLoadPoints(exerciseID: exercise.id, comparisonKey: "machine:bar-excluded", sessions: [session]).isEmpty, "Mixed incompatible load types")
            session.corrections.append(.init(id: UUID(), setID: session.sets[2].id, load: session.sets[2].load, reps: 10, voided: true, date: .now))
            let corrected = TrainingProgress.sessionLoadPoints(exerciseID: exercise.id, comparisonKey: exercise.load.comparisonKey, sessions: [session])
            try expect(corrected[0].reps == 8, "Voided set remained in the chart")
        }
        try run("Workout suggestions follow the requested order, stop after today, and ignore incomplete logs") {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let today = Date(timeIntervalSince1970: 1_800_000_000)
            let yesterday = today.addingTimeInterval(-86400)
            func fixture(day: Int, ended: Date, completed: Bool = true) -> StrengthSession {
                let routine = TrainingPlan.seed.routine(day: day)
                var session = StrengthSession(id: UUID(), day: day, startedAt: ended.addingTimeInterval(-1800),
                    routine: routine, draftLoad: routine[0].load, draftReps: 10)
                session.endedAt = ended
                session.completed = completed
                return session
            }
            for (day, next) in [(2, Split.back), (1, .legs), (3, .glutes)] {
                let session = fixture(day: day, ended: yesterday)
                try expect(TrainingProgress.suggestedWorkout(sessions: [session], today: today, calendar: calendar) == next, "Suggestion order changed")
                try expect(TrainingProgress.suggestedWorkout(sessions: [session, fixture(day: 1, ended: today)], today: today, calendar: calendar) == nil, "Suggested a schedule after today's workout")
            }
            try expect(TrainingProgress.suggestedWorkout(sessions: [], today: today, calendar: calendar) == nil, "Invented a first workout")
            let complete = fixture(day: 2, ended: yesterday)
            let incomplete = fixture(day: 1, ended: today, completed: false)
            try expect(TrainingProgress.suggestedWorkout(sessions: [complete, incomplete], today: today, calendar: calendar) == .back, "Incomplete workout advanced suggestion")
        }
        try run("Phone deletion persists and stale sync or backup cannot resurrect the log") {
            let watch = store("delete-source")
            let id = try started(watch)
            try log(watch, id, date: .now)
            try watch.finalizeLocal(id, completed: false, advanceFromDay: nil)
            try watch.setHealth(id, state: .notStarted)
            let snapshot = watch.session(id)!
            let phone = store("delete-phone", watch: false)
            try phone.receive(.init(id: UUID(), payload: .workout(snapshot)))
            let backup = try phone.exportData()
            try phone.deleteFromPhone(id)
            let reopened = store("delete-phone", watch: false)
            try expect(reopened.history.isEmpty && reopened.session(id) == nil, "Deleted log returned after restart")
            var newer = snapshot
            newer.revision += 1
            try reopened.receive(.init(id: UUID(), payload: .workout(newer)))
            try reopened.restore(backup)
            try expect(reopened.history.isEmpty, "Stale sync/backup resurrected deleted log")
            try expect(watch.session(id)?.sets == snapshot.sets, "Phone deletion mutated Watch snapshots")
            try rejects { try watch.deleteFromPhone(id) }
        }
        try run("Phone cannot delete an active or saving workout") {
            let watch = store("delete-active")
            let id = try started(watch)
            let phone = store("delete-active-phone", watch: false)
            try phone.receive(.init(id: UUID(), payload: .workout(watch.session(id)!)))
            try rejects { try phone.deleteFromPhone(id) }
            try watch.finalizeLocal(id, completed: false, advanceFromDay: nil)
            try watch.setHealth(id, state: .saving)
            try phone.receive(.init(id: UUID(), payload: .workout(watch.session(id)!)))
            try rejects { try phone.deleteFromPhone(id) }
        }
        try run("Three main workout types retain exact exercises and targets") {
            let plan = TrainingPlan.seed
            try expect((1...3).map { plan.routine(day: $0).reduce(0) { $0 + $1.sets } } == [16,12,12], "Session totals differ")
            try expect((1...3).reduce(0) { $0 + plan.routine(day: $1).reduce(0) { $0 + $1.sets * $1.reps } } == 400, "Repetitions differ")
            try expect(plan.exercises.map { $0.load.pounds } == [70,nil,35,20,35,25,65,80,10,65,nil], "Seeds changed")
        }
        try run("Typed Smith plates, assistance and unknown resistance") {
            let plan = TrainingPlan.seed
            try expect(plan.exercises[5].load.addedPlates == 50 && plan.exercises[8].load.addedPlates == 20, "Smith derivation incorrect")
            try expect(plan.exercises[5].load.smithBarPounds == nil, "Invented bar")
            try expect(plan.exercises[0].load.volumeLoad == nil && plan.exercises[10].load.volumeLoad == nil, "Invalid volume")
            try rejects { try TrainingLoad(kind: .machine, pounds: -1).validate() }
        }
        try run("Zero loads and reps survive logging, restart, sync and correction") {
            for kind in [LoadKind.machine, .smith, .assistance, .addedBodyweight] {
                let name = "zero-\(kind.rawValue)"
                let watch = store(name)
                var plan = watch.archive.plan
                plan.revision += 1
                plan.exercises[0].load = .init(kind: kind, pounds: 0)
                plan.exercises[0].reps = 0
                plan.exercises[0].sets = 1
                try plan.validate()
                try watch.receive(.init(id: UUID(), payload: .plan(plan)))
                let id = try started(watch)
                try watch.editDraft(id, load: .init(kind: kind, pounds: 0), reps: 0)
                try rejects { try watch.editDraft(id, load: .init(kind: kind, pounds: 0), reps: -1) }
                try log(watch, id, date: .now)
                try watch.finalizeLocal(id, completed: true, advanceFromDay: 1)
                let reopened = store(name)
                let snapshot = reopened.session(id)!
                try expect(snapshot.effectiveSets[0].load.pounds == 0 && snapshot.effectiveSets[0].reps == 0, "Zero values lost on restart")
                let phone = store(name + "-phone", watch: false)
                try phone.receive(.init(id: UUID(), payload: .workout(snapshot)))
                let received = phone.session(id)!
                try phone.requestCorrection(session: received, set: received.effectiveSets[0], load: .init(kind: kind, pounds: 0), reps: 0)
                let correction = phone.archive.outbox.first { if case .correction = $0.payload { return true }; return false }!
                try reopened.receive(correction)
                try expect(reopened.session(id)!.corrections.last?.reps == 0, "Zero correction rejected")
                let exercise = snapshot.routine[0]
                try expect(TrainingProgress.records(exercise: exercise, comparisonKey: exercise.load.comparisonKey, sessions: [snapshot]).isEmpty, "Zero reps created a record")
                try expect(TrainingProgress.suggestion(exercise: exercise, sessions: [snapshot]) == nil, "Zero reps suggested an increase")
            }
        }
        try run("Atomic persistence, restart, immutable load snapshots and recall") {
            let records = store("persistence")
            let id = try started(records, day: 2)
            try log(records, id, date: .now)
            let first = records.session(id)!.sets[0]
            try records.rest(id, extend: false)
            try records.editDraft(id, load: .init(kind: .machine, pounds: 40), reps: 8)
            try log(records, id, date: Date.now.addingTimeInterval(2))
            let reopened = store("persistence")
            try expect(reopened.session(id)?.sets.first == first && first.load.pounds == 35, "Earlier set mutated")
            try expect(reopened.session(id)?.effectiveSets.last?.load.pounds == 40, "Latest load lost")
            try expect(reopened.recalledLoad(reopened.archive.plan.exercises[4]).pounds == 40, "Recall failed")
            try expect(!reopened.archive.outbox.isEmpty, "Outbox lost on restart")
        }
        try run("Set token and rapid duplicate input protection") {
            let records = store("duplicate")
            let id = try started(records)
            let token = records.session(id)!.pendingSetID
            try expect(tryResult { try records.logSet(id, token: token) }, "First tap failed")
            try expect(!tryResult { try records.logSet(id, token: token) }, "Repeated token logged")
            try records.rest(id, extend: false)
            try rejects { _ = try records.logSet(id, token: records.session(id)!.pendingSetID) }
            try expect(records.session(id)!.sets.count == 1, "Duplicate set persisted")
        }
        try run("Four sets automatically advance; rest uses an absolute deadline") {
            let records = store("advance")
            let id = try started(records, day: 2)
            let date = Date.now
            for n in 0..<4 {
                try records.rest(id, extend: false)
                try log(records, id, date: date.addingTimeInterval(Double(n) * 2))
            }
            let session = records.session(id)!
            try expect(session.currentExercise?.id == "thrust" && session.draftLoad.pounds == 25, "Transition failed")
            try expect(session.remainingRest(at: session.restUntil!.addingTimeInterval(-30)) == 30, "Rest arithmetic failed")
            try expect(session.remainingRest(at: session.restUntil!.addingTimeInterval(60)) == 0, "Rest went negative")
            try expect(session.sets.count == 4, "Timer fabricated sets")
        }
        try run("Undo preserves the original snapshot and restores the exercise") {
            let records = store("undo")
            let id = try started(records)
            try log(records, id, date: .now)
            let original = records.session(id)!.sets[0]
            try records.undoLastSet(id)
            try expect(records.session(id)!.sets == [original], "Undo deleted observation")
            try expect(records.session(id)!.effectiveSets.isEmpty && records.session(id)!.corrections.count == 1, "Undo missing correction")
        }
        try run("Three-type rotation, shortened completion and rest-day stability") {
            let records = store("rotation")
            for day in 1...3 {
                let id = try started(records, day: day)
                try expect(records.archive.nextDay == day, "Start advanced rotation")
                try records.finalizeLocal(id, completed: true, advanceFromDay: day)
                try expect(records.archive.nextDay == day % 3 + 1, "Completion failed rotation")
            }
            let id = try started(records, day: 4)
            try records.finalizeLocal(id, completed: false, advanceFromDay: 4)
            try expect(records.archive.nextDay == 1, "Incomplete session advanced")
        }
        try run("Abs skip remains within one strength session") {
            let records = store("abs")
            let id = try started(records, day: 3)
            while records.session(id)!.currentExercise != nil { try records.skipExercise(id) }
            try expect(records.session(id)!.needsFinisherChoice, "Finisher was not offered")
            try records.chooseFinisher(id, include: true)
            try records.skipExercise(id)
            try expect(records.session(id)!.currentExercise == nil && records.archive.sessions.count == 1, "Abs duplicated session")
            try expect(records.session(id)!.sets.isEmpty, "Skipped work counted complete")
        }
        try run("Half-pound assistance edits persist through restart, switching and logging") {
            let records = store("half-pound-draft")
            let id = try started(records)
            try records.editDraft(id, load: .init(kind: .assistance, pounds: 70.5), reps: 10)
            let reopened = store("half-pound-draft")
            try expect(reopened.session(id)!.draftLoad == .init(kind: .assistance, pounds: 70.5), "Half-pound draft lost on restart")
            try reopened.selectExercise(id, exerciseID: "back-extension")
            try reopened.selectExercise(id, exerciseID: "pullup")
            try expect(reopened.session(id)!.draftLoad.pounds == 70.5, "Half-pound draft lost on exercise switch")
            try log(reopened, id, date: .now)
            try reopened.editDraft(id, load: .init(kind: .assistance, pounds: 71), reps: 10)
            let again = store("half-pound-draft")
            try expect(again.session(id)!.sets.first?.load.pounds == 70.5, "Half-pound snapshot changed")
            try expect(again.session(id)!.draftLoad.pounds == 71, "Subsequent half-pound edit lost")
        }
        try run("Exercise switching preserves draft edits, completed sets, rest and restart") {
            let records = store("switching")
            let id = try started(records, day: 2)
            try records.editDraft(id, load: .init(kind: .machine, pounds: 42), reps: 8)
            try records.selectExercise(id, exerciseID: "abduction")
            try log(records, id, date: .now)
            let snapshot = records.session(id)!.sets[0]
            let deadline = records.session(id)!.restUntil
            try records.selectExercise(id, exerciseID: "hamstring")
            try expect(records.session(id)!.draftLoad.pounds == 42 && records.session(id)!.draftReps == 8, "Draft edits lost")
            try expect(records.session(id)!.restUntil == deadline, "Switch bypassed rest")
            let reopened = store("switching")
            try expect(reopened.session(id) == records.session(id), "Switch was not durable")
            try reopened.rest(id, extend: false)
            try log(reopened, id, date: Date.now.addingTimeInterval(2))
            try expect(reopened.session(id)!.sets.first == snapshot, "Switch rewrote a logged set")
            try reopened.selectExercise(id, exerciseID: "abduction")
            try expect(reopened.session(id)!.count(for: "abduction") == 1 && reopened.session(id)!.draftLoad.pounds == 65, "Partial exercise did not resume")
            try reopened.selectExercise(id, exerciseID: "abs")
            try expect(reopened.session(id)!.currentExercise?.id == "abs" && reopened.session(id)!.finisherChoice == true,
                       "Explicit finisher selection did not opt in")
        }
        try run("Out-of-order completion returns to unfinished work and never repeats completed exercises") {
            let records = store("outOfOrder")
            let id = try started(records, day: 2)
            try records.selectExercise(id, exerciseID: "abduction")
            for n in 0..<4 {
                try records.rest(id, extend: false)
                try log(records, id, date: Date.now.addingTimeInterval(Double(n) * 2))
            }
            try expect(records.session(id)!.currentExercise?.id == "hamstring", "Earlier unfinished work was lost")
            try rejects { try records.selectExercise(id, exerciseID: "abduction") }
            try records.skipExercise(id)
            try records.skipExercise(id)
            try expect(records.session(id)!.needsFinisherChoice, "Finisher prompt missing")
            try records.chooseFinisher(id, include: false)
            try expect(records.session(id)!.currentExercise == nil && !records.session(id)!.needsFinisherChoice, "Declined Abs remained pending")
            try records.undoLastSet(id)
            try expect(records.session(id)!.currentExercise?.id == "abduction", "Undo failed after unordered workout")
        }
        try run("Legacy active six-day snapshots keep included Abs and immutable observations") {
            let records = store("legacy-active")
            let id = try started(records, day: 6)
            try log(records, id, date: .now)
            var snapshot = records.session(id)!
            snapshot.offersFinisher = nil
            snapshot.finisherChoice = nil
            snapshot.exerciseDrafts = nil
            let bytes = try JSONEncoder().encode(snapshot)
            let restored = try JSONDecoder().decode(StrengthSession.self, from: bytes)
            try expect(restored == snapshot && restored.day == 6 && restored.sets == snapshot.sets, "Legacy session changed")
            try expect(restored.isAvailable(restored.routine.last!) && !restored.needsFinisherChoice, "Legacy included Abs was locked")
        }
        try run("Choosing Abs early opts in durably without another session or losing rest") {
            for day in 1...3 {
                let name = "early-abs-\(day)"
                let records = store(name)
                let id = try started(records, day: day)
                let initial = records.session(id)!
                let mainID = initial.currentExercise!.id
                let abs = initial.routine.first { $0.id == "abs" }!
                try expect(initial.isSelectable(abs) && !initial.isAvailable(abs), "Explicit Abs selection was not separated from automatic eligibility")
                try log(records, id, date: .now)
                let mainSet = records.session(id)!.sets[0]
                let rest = records.session(id)!.restUntil
                try records.selectExercise(id, exerciseID: "abs")
                let reopened = store(name)
                let selected = reopened.session(id)!
                try expect(selected.currentExercise?.id == "abs" && selected.finisherChoice == true, "Early Abs choice did not persist")
                try expect(selected.plannedSets == initial.plannedSets + abs.sets && reopened.archive.sessions.count == 1, "Abs duplicated the workout or plan")
                try expect(selected.restUntil == rest && selected.sets[0] == mainSet, "Abs changed rest or historical set")
                try reopened.selectExercise(id, exerciseID: mainID)
                try expect(reopened.session(id)!.draftLoad == initial.draftLoad && reopened.session(id)!.restUntil == rest, "Returning from Abs lost the main draft/rest")
            }
        }
        try run("Explicit Abs choice can replace Not Today without reviving skipped work") {
            let records = store("reconsider-abs")
            let id = try started(records)
            while records.session(id)!.currentExercise != nil { try records.skipExercise(id) }
            try records.chooseFinisher(id, include: false)
            try records.selectExercise(id, exerciseID: "abs")
            try expect(records.session(id)!.finisherChoice == true, "Abs remained locked after explicit selection")
            try records.skipExercise(id)
            try rejects { try records.selectExercise(id, exerciseID: "abs") }
        }
        try run("Every workout type offers Abs with persisted same-session choice") {
            for day in 1...3 {
                let records = store("finisher-\(day)")
                let id = try started(records, day: day)
                let mainTotal = records.session(id)!.plannedSets
                while records.session(id)!.currentExercise != nil { try records.skipExercise(id) }
                try expect(records.session(id)!.needsFinisherChoice, "Missing finisher for workout type")
                try records.chooseFinisher(id, include: true)
                let snapshot = store("finisher-\(day)").session(id)!
                try expect(snapshot.currentExercise?.id == "abs" && snapshot.draftLoad.pounds == 3 && snapshot.plannedSets == mainTotal + 4, "Finisher choice or load lost")
                try expect(records.archive.sessions.count == 1, "Finisher created a second workout")
                try records.rest(id, extend: false)
                try log(records, id, date: .now)
                let phone = store("finisher-phone-\(day)", watch: false)
                try phone.receive(.init(id: UUID(), payload: .workout(records.session(id)!)))
                try expect(phone.session(id) == records.session(id), "Finisher state failed sync serialization")
            }
        }
        try run("Health save failure retains local detailed records") {
            let records = store("healthFailure")
            let id = try started(records)
            try log(records, id, date: .now)
            try records.finalizeLocal(id, completed: true, advanceFromDay: 1)
            try records.setHealth(id, state: .recovery, error: "Test failure")
            try expect(store("healthFailure").session(id)?.effectiveSets.count == 1, "Health error lost set")
            try expect(records.session(id)!.healthUUID == nil, "Invented save UUID")
        }
        try run("Unavailable local storage never acknowledges a set or advances state") {
            let blocked = root.appendingPathComponent("not-a-directory")
            try Data().write(to: blocked)
            let records = TrainingStore(fileURL: blocked.appendingPathComponent("data.json"), isWatch: true)
            try rejects { _ = try records.begin(day: 1) }
            try expect(records.archive.sessions.isEmpty && records.archive.outbox.isEmpty, "Failed commit leaked state")
        }
        try run("Repeated and out-of-order workout deliveries are idempotent") {
            let watch = store("sender")
            let phone = store("receiver", watch: false)
            let id = try started(watch)
            let older = SyncEvent(id: UUID(), payload: .workout(watch.session(id)!))
            try log(watch, id, date: .now)
            let newer = watch.archive.outbox.first { if case .workout = $0.payload { return true }; return false }!
            try phone.receive(newer); try phone.receive(newer); try phone.receive(older)
            try expect(phone.archive.sessions.count == 1 && phone.session(id)?.effectiveSets.count == 1, "Sync duplicated or rolled back")
            let receipt = phone.archive.outbox.first { if case .receipt(let eventID, _) = $0.payload { return eventID == newer.id }; return false }!
            try watch.receive(receipt)
            try expect(watch.archive.received[id]?.revision == watch.session(id)?.revision, "Receipt not saved")
        }
        try run("Historical correction is append-only and rejects stale revisions") {
            let watch = store("correctionWatch")
            let phone = store("correctionPhone", watch: false)
            let id = try started(watch)
            try log(watch, id, date: .now)
            try watch.finalizeLocal(id, completed: true, advanceFromDay: 1)
            let original = watch.session(id)!.sets[0]
            try phone.receive(.init(id: UUID(), payload: .workout(watch.session(id)!)))
            let session = phone.session(id)!
            try phone.requestCorrection(session: session, set: session.effectiveSets[0], load: original.load, reps: 8)
            let event = phone.archive.outbox.first { if case .correction = $0.payload { return true }; return false }!
            try watch.receive(event); try watch.receive(event)
            try expect(watch.session(id)!.corrections.count == 1 && watch.session(id)!.effectiveSets[0].reps == 8, "Correction duplicated")
            try expect(watch.session(id)!.sets[0] == original, "Original overwritten")
            let stale = CorrectionRequest(sessionID: id, expectedRevision: session.revision, correction: .init(id: UUID(), setID: original.id, load: original.load, reps: 9, voided: false, date: .now))
            try watch.receive(.init(id: UUID(), payload: .correction(stale)))
            try expect(watch.session(id)!.effectiveSets[0].reps == 8, "Stale correction won")
        }
        try run("Plan edits preserve history and active routine snapshots") {
            let records = store("planWatch")
            let id = try started(records)
            let initial = records.session(id)!.routine
            var plan = TrainingPlan.seed
            plan.revision = 1
            plan.exercises[0].load.pounds = 60
            try records.receive(.init(id: UUID(), payload: .plan(plan)))
            try expect(records.session(id)!.routine == initial, "Active plan mutated")
            let phone = store("planPhone", watch: false)
            plan.revision = 0
            try phone.savePlan(plan)
            try rejects { try phone.savePlan(TrainingPlan.seed) }
        }
        try run("Schema-versioned export/restore round trip and duplicate merge") {
            let watch = store("backupWatch")
            let id = try started(watch)
            try log(watch, id, date: .now)
            try watch.finalizeLocal(id, completed: true, advanceFromDay: 1)
            let data = try watch.exportData()
            let phone = store("backupPhone", watch: false)
            try phone.restore(data); try phone.restore(data)
            try expect(phone.session(id)?.sets == watch.session(id)?.sets && phone.archive.sessions.count == 1, "Restore corrupted history")
            var bad = try JSONDecoder().decode(TrainingArchive.self, from: data)
            bad.schemaVersion = 999
            try rejects { try phone.restore(JSONEncoder().encode(bad)) }
        }
        try run("Assistance progresses downward and seeds never create records") {
            let records = store("progression")
            let exercise = records.archive.plan.exercises[0]
            try expect(TrainingProgress.points(exerciseID: exercise.id, sessions: []).isEmpty, "Seed produced chart")
            let id = try started(records)
            for n in 0..<4 { try records.rest(id, extend: false); try log(records, id, date: Date.now.addingTimeInterval(Double(n) * 2)) }
            try records.finalizeLocal(id, completed: true, advanceFromDay: 1)
            try expect(TrainingProgress.suggestion(exercise: exercise, sessions: records.archive.sessions)?.pounds == 65, "Assistance direction incorrect")
            try expect(records.archive.plan.exercises[0].load.pounds == 70, "Suggestion changed plan silently")
        }
        try run("Receipt loss survives restart; bootstrap can resend already acknowledged history") {
            let watch = store("receiptWatch")
            let id = try started(watch)
            try log(watch, id, date: .now)
            let event = watch.archive.outbox.first { if case .workout = $0.payload { return true }; return false }!
            try watch.receive(.init(id: UUID(), payload: .receipt(event.id, nil)))
            try expect(!watch.archive.outbox.contains { $0.id == event.id }, "Ack not removed")
            try watch.receive(.init(id: UUID(), payload: .requestHistory))
            try expect(watch.archive.outbox.contains { if case .workout(let s) = $0.payload { return s.id == id }; return false }, "Bootstrap didn't resend")
            try expect(store("receiptWatch").archive.outbox == watch.archive.outbox, "Queue not durable")
        }
        try run("Corrupt existing storage is preserved and cannot be silently replaced") {
            let path = root.appendingPathComponent("corrupt.json")
            let bytes = Data("not valid JSON".utf8)
            try bytes.write(to: path)
            let records = TrainingStore(fileURL: path, isWatch: true)
            try expect(!records.storageReady, "Corruption did not block recording")
            try rejects { _ = try records.begin(day: 1) }
            try expect(tryResult { try Data(contentsOf: path) == bytes }, "Corrupt source was overwritten")
        }
        try run("New exercises always precede Abs and older plans retain the 90s default") {
            var plan = TrainingPlan.seed
            plan.exercises.append(.init(id: "new-back", name: "Different Row", split: .back, load: .init(kind: .unknown, pounds: nil)))
            try expect(plan.routine(day: 1).last?.id == "new-back" && !plan.routine(day: 1).contains { $0.split == nil }, "Finisher leaked into main routine")
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as! [String: Any]
            json.removeValue(forKey: "defaultRestSeconds")
            let restored = try JSONDecoder().decode(TrainingPlan.self, from: JSONSerialization.data(withJSONObject: json))
            try expect(restored.defaultRestSeconds == 90 && restored.exercises == plan.exercises, "Legacy plan lost data")
        }
        try run("Explicit Watch restore keeps identifiers and never replaces existing records") {
            let original = store("restoreOriginal")
            let id = try started(original)
            try log(original, id, date: .now)
            try original.finalizeLocal(id, completed: true, advanceFromDay: 1)
            let snapshot = original.session(id)!
            let fresh = store("restoreFresh")
            let event = SyncEvent(id: UUID(), payload: .restoreWorkout(snapshot))
            try fresh.receive(event); try fresh.receive(event)
            try expect(fresh.archive.sessions == [snapshot] && fresh.archive.nextDay == 2, "Restore changed identity or duplicated")
            try fresh.requestCorrection(session: snapshot, set: snapshot.effectiveSets[0], load: snapshot.draftLoad, reps: 7)
            try fresh.receive(event)
            try expect(fresh.session(id)!.effectiveSets[0].reps == 7, "Restore overwrote newer Watch correction")
            let active = store("restoreActive")
            _ = try started(active)
            try active.receive(event)
            try expect(active.archive.sessions.count == 1 && active.session(id) == nil, "Restore entered an active workout")
        }
        try run("No automatic rest after the final planned set") {
            let records = store("finalRest")
            let id = try started(records, day: 2)
            let date = Date.now
            for n in 0..<12 {
                try records.rest(id, extend: false)
                try log(records, id, date: date.addingTimeInterval(Double(n) * 2))
            }
            try expect(records.session(id)!.currentExercise == nil && records.session(id)!.restUntil == nil, "Final rest blocked completion")
            try expect(records.session(id)!.effectiveSets.count == 12, "Wrong completed set count")
        }
        try run("A custom future load dismisses a stale progression suggestion") {
            let records = store("suggestionPreference")
            let id = try started(records)
            for n in 0..<4 { try records.rest(id, extend: false); try log(records, id, date: Date.now.addingTimeInterval(Double(n) * 2)) }
            try records.finalizeLocal(id, completed: true, advanceFromDay: 1)
            var exercise = records.archive.plan.exercises[0]
            exercise.preferenceUpdatedAt = Date.now.addingTimeInterval(60)
            exercise.load.pounds = 80
            try expect(TrainingProgress.suggestion(exercise: exercise, sessions: records.archive.sessions) == nil, "Ignored newer preference")
        }
        try run("An equal-revision conflicting delivery leaves the receiver unchanged") {
            let watch = store("conflictWatch")
            let phone = store("conflictPhone", watch: false)
            let id = try started(watch)
            let snapshot = watch.session(id)!
            try phone.receive(.init(id: UUID(), payload: .workout(snapshot)))
            var divergent = snapshot
            divergent.draftReps = 9
            try rejects { try phone.receive(.init(id: UUID(), payload: .workout(divergent))) }
            try expect(phone.session(id) == snapshot, "Divergent snapshot replaced original")
        }
        try runFinishing(root: root)
        print("\(passed) core scenarios passed. These are local model/storage tests, not HealthKit or physical Watch acceptance.")
    }
    static func tryResult(_ action: () throws -> Bool) -> Bool { (try? action()) ?? false }
}
