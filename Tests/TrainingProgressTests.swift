import Foundation

@main
@MainActor
struct ProgressChecks {
    static func check(_ ok: @autoclosure () -> Bool, _ message: String) {
        precondition(ok(), message)
        print("PASS \(message)")
    }
    static func main() throws {
        let exercise = TrainingPlan.seed.exercises[0]
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func fixture(_ offset: Double, load: TrainingLoad, reps: Int = 10, complete: Bool = true) -> StrengthSession {
            var session = StrengthSession(id: UUID(), day: 1, startedAt: start.addingTimeInterval(offset), routine: [exercise], draftLoad: load, draftReps: reps)
            session.sets = [.init(id: UUID(), exerciseID: exercise.id, exerciseName: exercise.name, ordinal: 1, load: load, reps: reps, completedAt: start.addingTimeInterval(offset + 1))]
            session.endedAt = start.addingTimeInterval(offset + 2)
            session.completed = complete
            return session
        }
        let first = fixture(0, load: .init(kind: .assistance, pounds: 70))
        let second = fixture(100, load: .init(kind: .assistance, pounds: 60))
        let lowReps = fixture(200, load: .init(kind: .assistance, pounds: 50), reps: 5)
        let incomplete = fixture(300, load: .init(kind: .assistance, pounds: 40), complete: false)
        let otherBasis = fixture(400, load: .init(kind: .machine, pounds: 90))
        let sessions = [otherBasis, second, incomplete, lowReps, first]
        let milestones = TrainingProgress.records(exercise: exercise, comparisonKey: exercise.load.comparisonKey, sessions: sessions)
        check(milestones.map(\.load) == [70, 60], "Assistance milestones improve downward and require qualifying reps")
        check(milestones.last?.previous == 70 && milestones.last?.sessionID == second.id, "Milestones link to the correct original session")
        let history = TrainingProgress.performances(exerciseID: exercise.id, comparisonKey: exercise.load.comparisonKey, sessions: sessions)
        check(history.map(\.reps) == [10, 10, 5] && history.allSatisfy { $0.volume == nil }, "Session comparison excludes incomplete sessions and incompatible bases; assistance has no volume")
        var corrected = second
        corrected.corrections.append(.init(id: UUID(), setID: second.sets[0].id, load: .init(kind: .assistance, pounds: 80), reps: 10, voided: false, date: start.addingTimeInterval(500)))
        check(TrainingProgress.records(exercise: exercise, comparisonKey: exercise.load.comparisonKey, sessions: [first, corrected]).map(\.load) == [70], "Corrections remove invalidated milestones")
        let smith = fixture(500, load: .init(kind: .smith, pounds: 25))
        let knownBar = fixture(600, load: .init(kind: .smith, pounds: 25, smithBarPounds: 15))
        let plates = TrainingProgress.performances(exerciseID: exercise.id, comparisonKey: smith.draftLoad.comparisonKey, sessions: [smith, knownBar])
        check(plates.count == 1 && plates[0].volume == 500, "Smith volume uses both sides without inventing or mixing bar contributions")
        let bodyweight = fixture(700, load: .init(kind: .bodyweight, pounds: nil))
        let bw = TrainingProgress.performances(exerciseID: exercise.id, comparisonKey: bodyweight.draftLoad.comparisonKey, sessions: [bodyweight])
        check(bw.first?.reps == 10 && bw.first?.workingLoad == nil && bw.first?.volume == nil, "Bodyweight keeps real sets and reps without synthetic weight")
        check(TrainingProgress.records(exercise: exercise, comparisonKey: exercise.load.comparisonKey, sessions: []).isEmpty, "Starting estimates never create milestones")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("REP-abs-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let phone = TrainingStore(fileURL: root.appendingPathComponent("phone.json"), isWatch: false)
        let watch = TrainingStore(fileURL: root.appendingPathComponent("watch.json"), isWatch: true)
        let id = try watch.begin(day: 1)
        try watch.setHealth(id, state: .recording)
        while watch.session(id)?.currentExercise != nil { try watch.skipExercise(id) }
        try watch.chooseFinisher(id, include: true)
        try watch.editDraft(id, load: .init(kind: .unknown, pounds: nil), reps: 10)
        _ = try watch.logSet(id, token: watch.session(id)!.pendingSetID)
        try watch.finalizeLocal(id, completed: true, advanceFromDay: 1)
        try phone.receive(.init(id: UUID(), payload: .workout(watch.session(id)!)))
        let original = phone.session(id)!
        let initialized = try phone.applyConfirmedAbsPreference()
        let abs = phone.archive.plan.exercises.first { $0.id == "abs" }!
        check(initialized && abs.load.kind == .addedBodyweight && abs.load.pounds == 3 && phone.session(id) == original, "Confirmed 3 lb added Abs preference preserves past unspecified sets")
        let revision = phone.archive.plan.revision
        let repeated = try phone.applyConfirmedAbsPreference()
        check(!repeated && phone.archive.plan.revision == revision, "Confirmed preference is initialized only once")
        var changed = phone.archive.plan
        let i = changed.exercises.firstIndex { $0.id == "abs" }!
        changed.exercises[i].load.pounds = 4
        changed.exercises[i].preferenceUpdatedAt = .now
        try phone.savePlan(changed)
        let reapplied = try phone.applyConfirmedAbsPreference()
        let watchApplied = try watch.applyConfirmedAbsPreference()
        check(!reapplied && !watchApplied && phone.archive.plan.exercises[i].load.pounds == 4, "Later Abs increases are retained and the iPhone owns plan changes")
        let legacyPhone = TrainingStore(fileURL: root.appendingPathComponent("legacy-phone.json"), isWatch: false)
        let legacyWatch = TrainingStore(fileURL: root.appendingPathComponent("legacy-watch.json"), isWatch: true)
        var legacyPlan = legacyPhone.archive.plan
        legacyPlan.exercises[1] = Exercise(id: "pulldown", name: "Lat Pulldown", split: .back, load: .init(kind: .machine, pounds: 40))
        let absIndex = legacyPlan.exercises.firstIndex { $0.id == "abs" }!
        legacyPlan.exercises[absIndex].name = "Hanging Ab Crunch / Hanging Ab Machine"
        legacyPlan.exercises[absIndex].load = .init(kind: .addedBodyweight, pounds: 4)
        try legacyPhone.savePlan(legacyPlan)
        try legacyWatch.receive(.init(id: UUID(), payload: .plan(legacyPhone.archive.plan)))
        let activeID = try legacyWatch.begin(day: 1)
        try legacyWatch.setHealth(activeID, state: .recording)
        try legacyWatch.selectExercise(activeID, exerciseID: "pulldown")
        _ = try legacyWatch.logSet(activeID, token: legacyWatch.session(activeID)!.pendingSetID)
        let activeBefore = legacyWatch.session(activeID)!
        try legacyPhone.receive(.init(id: UUID(), payload: .workout(activeBefore)))
        let migratedRoutine = try legacyPhone.applyConfirmedRoutinePreferences()
        check(migratedRoutine, "Legacy routine is migrated")
        let updated = legacyPhone.archive.plan
        check(updated.exercises[1].id == "back-extension" && updated.exercises[1].load.kind == .unknown && updated.exercises[1].load.pounds == nil, "Back extension never inherits pulldown identity or resistance")
        check(updated.exercises[absIndex].name == "Abs" && updated.exercises[absIndex].load.pounds == 4, "General Abs entry retains the user's edited added weight")
        try legacyWatch.receive(.init(id: UUID(), payload: .plan(updated)))
        check(legacyWatch.session(activeID) == activeBefore && legacyPhone.session(activeID) == activeBefore, "Routine sync preserves active snapshots and completed observations")
        check(legacyWatch.recalledLoad(updated.exercises[1]).kind == .unknown, "Pulldown history is excluded from back extension recall")
        let reopened = TrainingStore(fileURL: root.appendingPathComponent("legacy-phone.json"), isWatch: false)
        check(reopened.archive.plan == updated, "Updated routine survives reopening")
        let repeatedRoutine = try reopened.applyConfirmedRoutinePreferences()
        let watchRoutine = try legacyWatch.applyConfirmedRoutinePreferences()
        check(!repeatedRoutine && !watchRoutine && reopened.archive.plan.revision == updated.revision, "Routine update is idempotent and phone-owned")
        print("Progress and preference scenarios passed. Synthetic fixtures only; no HealthKit data written.")
    }
}
