#if targetEnvironment(simulator)
import Foundation

/// Explicit simulator fixtures in a separate archive. Never sent to Health or sync.
@MainActor
enum PhoneDemoData {
    static func populate(_ store: TrainingStore) throws {
        guard store.isPreview, store.archive.sessions.isEmpty,
              store.archive.deletedSessionIDs?.isEmpty != false else { return }
        var sample = TrainingArchive()
        sample.plan = store.archive.plan
        let calendar = Calendar.current
        for index in 0..<18 {
            let day = index % 3 + 1
            let date = calendar.date(byAdding: .day, value: -((17 - index) * 2 + 1), to: calendar.startOfDay(for: .now))!
                .addingTimeInterval(17 * 3600)
            let routine = sample.plan.routine(day: day) + sample.plan.exercises.filter { $0.split == nil }.map(\.withConfirmedDefaults)
            guard let first = routine.first else { continue }
            var session = StrengthSession(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!,
                day: day, startedAt: date, routine: routine, draftLoad: first.load, draftReps: first.reps)
            session.offersFinisher = true
            session.finisherChoice = index % 2 == 0
            session.endedAt = date.addingTimeInterval(2100 + Double(index % 4) * 180)
            session.elapsed = session.endedAt!.timeIntervalSince(date)
            session.completed = true
            // No Health UUID, calories, BPM, ring values or save success fixtures.
            for exercise in routine where exercise.split != nil || session.finisherChoice == true {
                var load = exercise.load
                if let pounds = load.pounds {
                    let step = Double(index / 3)
                    if load.kind == .assistance { load.pounds = max(40, pounds - step * 5) }
                    else if load.kind != .addedBodyweight { load.pounds = pounds + step * 2.5 }
                }
                for ordinal in 1...exercise.sets {
                    session.sets.append(.init(id: UUID(), exerciseID: exercise.id, exerciseName: exercise.name,
                        ordinal: ordinal, load: load, reps: exercise.reps,
                        completedAt: date.addingTimeInterval(Double(session.sets.count) * 100)))
                }
            }
            sample.sessions.append(session)
        }
        try store.restore(JSONEncoder().encode(sample))
    }
}
#endif
