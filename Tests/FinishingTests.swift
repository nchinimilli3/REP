import Foundation

@MainActor
extension TrainingCoreTests {
    static func runFinishing(root: URL) throws {
        func store(_ name: String, watch: Bool = true) -> TrainingStore {
            TrainingStore(fileURL: root.appendingPathComponent("finishing-\(name).json"), isWatch: watch)
        }
        func complete(_ records: TrainingStore, day: Int, advance: Int?) throws -> UUID {
            let id = try records.begin(day: day)
            try records.finalizeLocal(id, completed: true, advanceFromDay: advance)
            return id
        }
        try run("Freely chosen and repeated workouts persist and sync without advancing a schedule") {
            let watch = store("freeChoice")
            let phone = store("freeChoicePhone", watch: false)
            let order = [3, 3, 1, 2, 1]
            let originalNext = watch.archive.nextDay
            for day in order {
                let id = try complete(watch, day: day, advance: nil)
                let session = watch.session(id)!
                try expect(session.completed && session.day == day, "Chosen workout was not preserved")
                try expect(session.nextDayAfterCompletion == nil && session.rotationAfterCompletion == nil, "Completion scheduled another workout")
                try phone.receive(.init(id: UUID(), payload: .workout(session)))
            }
            let reopened = store("freeChoice")
            try expect(reopened.archive.sessions.map(\.day) == order, "Free choices lost after restart")
            try expect(reopened.archive.nextDay == originalNext, "Completion advanced legacy scheduling")
            try expect(phone.archive.sessions.map(\.day) == order, "Free choices lost during sync")
        }
        try run("Start failure after startActivity ends the session without saving") {
            try expect(WorkoutStartCleanup.after(sessionCreated: true, activityStarted: true, collectionStarted: false) == .discardAndEnd, "Running session left open")
            try expect(WorkoutStartCleanup.after(sessionCreated: true, activityStarted: false, collectionStarted: false) == .discard, "Unstarted session not discarded")
            try expect(WorkoutStartCleanup.after(sessionCreated: true, activityStarted: true, collectionStarted: true) == .none, "Collected workout discarded")
            try expect(WorkoutStartCleanup.after(sessionCreated: false, activityStarted: false, collectionStarted: false) == .none, "Cleanup without session")
            let records = store("start-failure")
            let id = try records.begin(day: 1)
            try records.setHealth(id, state: .recovery, error: "Start interrupted")
            try expect(records.session(id)?.healthState == .recovery && records.archive.sessions.count == 1, "Failed start lost or duplicated the local log")
        }
        try run("Cycle membership is persisted and marks actual completed positions") {
            let records = store("cycle")
            let id = try complete(records, day: 1, advance: 1)
            let progress = CurrentCycleProgress(archive: records.archive)
            try expect(progress.completedCount == 1 && progress.days[0].sessionID == id, "Actual completion missing")
            try expect(progress.days[1].isNext && !progress.days[1].completed, "Upcoming work was fabricated")
            try expect(CurrentCycleProgress(archive: store("cycle").archive).days[0].sessionID == id, "Cycle lost after restart")
        }
        try run("Third workout type creates a fresh cycle without discarding previous records") {
            let records = store("wrap")
            let first = try complete(records, day: 1, advance: 1)
            let originalCycle = records.session(first)!.cycleID
            for day in 2...3 { _ = try complete(records, day: day, advance: day) }
            try expect(records.archive.rotation?.cycleID != originalCycle && records.archive.nextDay == 1, "Wrap did not start a new cycle")
            try expect(CurrentCycleProgress(archive: records.archive).completedCount == 0, "Previous cycle checkmarks leaked")
            try expect(records.archive.sessions.count == 3, "Wrapping deleted history")
        }
        try run("Overrides never fill unperformed days or count a non-advancing session") {
            let records = store("override")
            _ = try complete(records, day: 2, advance: 1)
            let progress = CurrentCycleProgress(archive: records.archive)
            try expect(progress.days[1].completed && !progress.days[0].completed, "Override fabricated the scheduled workout")
            _ = try complete(records, day: 2, advance: nil)
            try expect(CurrentCycleProgress(archive: records.archive).completedCount == 1, "Non-advancing workout filled a cycle position")
            try expect(records.archive.nextDay == 2, "Kept rotation advanced")
        }
        try run("A rotation arriving before its workout cannot create a completion badge") {
            let watch = store("rotationSender")
            let phone = store("rotationReceiver", watch: false)
            let id = try complete(watch, day: 1, advance: 1)
            let state = watch.archive.rotation!
            try phone.receive(.init(id: UUID(), payload: .rotation(state)))
            try expect(phone.archive.nextDay == 2 && CurrentCycleProgress(archive: phone.archive).completedCount == 0, "Rotation invented a received workout")
            try phone.receive(.init(id: UUID(), payload: .workout(watch.session(id)!)))
            try expect(CurrentCycleProgress(archive: phone.archive).completedCount == 1, "Received session not reflected")
        }
        try run("Stale and conflicting rotation snapshots cannot roll back the phone") {
            let records = store("rotationOrder", watch: false)
            let first = RotationState(revision: 1, nextDay: 2, cycleID: UUID())
            let second = try first.advancing(from: 2)
            try records.receive(.init(id: UUID(), payload: .rotation(second)))
            try records.receive(.init(id: UUID(), payload: .rotation(first)))
            try expect(records.archive.rotation == second, "Out-of-order rotation rolled back")
            let conflict = RotationState(revision: second.revision, nextDay: 6, cycleID: second.cycleID)
            try rejects { try records.receive(.init(id: UUID(), payload: .rotation(conflict))) }
            try expect(records.archive.rotation == second, "Conflicting rotation was published")
        }
        try run("Legacy backups keep next-day intent without invented cycle membership") {
            let watch = store("legacySender")
            _ = try complete(watch, day: 1, advance: 1)
            var json = try JSONSerialization.jsonObject(with: watch.exportData()) as! [String: Any]
            json.removeValue(forKey: "rotation")
            json["outbox"] = []
            var sessions = json["sessions"] as! [[String: Any]]
            for i in sessions.indices { sessions[i].removeValue(forKey: "cycleID"); sessions[i].removeValue(forKey: "rotationAfterCompletion") }
            json["sessions"] = sessions
            let phone = store("legacyReceiver", watch: false)
            try phone.restore(JSONSerialization.data(withJSONObject: json))
            try expect(phone.archive.nextDay == 2 && phone.archive.sessions.count == 1, "Legacy intent/history lost")
            try expect(CurrentCycleProgress(archive: phone.archive).cycleID == nil && CurrentCycleProgress(archive: phone.archive).completedCount == 0, "Guessed historical cycle IDs")
        }
        try run("Valid backup repairs unreadable phone storage while preserving exact original bytes") {
            let source = store("recoverySource")
            let id = try complete(source, day: 3, advance: 3)
            let url = root.appendingPathComponent("recovery-corrupt.json")
            let original = Data("unreadable original bytes".utf8)
            try original.write(to: url)
            let phone = TrainingStore(fileURL: url, isWatch: false)
            try expect(!phone.storageReady, "Unreadable file did not block recording")
            try phone.restore(source.exportData())
            try expect(phone.storageReady && phone.session(id) == source.session(id), "Backup did not recover storage")
            try expect(tryResult { try phone.exportPreservedArchive() == original }, "Original recovery bytes changed")
            try expect(TrainingStore(fileURL: url, isWatch: false).session(id) == source.session(id), "Recovered records not durable")
            let oldEvents = Set(source.archive.outbox.map(\.id))
            try expect(oldEvents.isDisjoint(with: Set(phone.archive.outbox.map(\.id))), "Exported transfers were replayed")
        }
        try run("Rejected recovery backup leaves unreadable storage untouched") {
            let url = root.appendingPathComponent("recovery-rejected.json")
            let original = Data("preserve me".utf8)
            try original.write(to: url)
            let phone = TrainingStore(fileURL: url, isWatch: false)
            var invalid = TrainingArchive()
            invalid.schemaVersion = 999
            try rejects { try phone.restore(JSONEncoder().encode(invalid)) }
            try expect(!phone.storageReady && phone.preservedArchiveURL == nil, "Rejected backup changed recovery state")
            try expect(tryResult { try Data(contentsOf: url) == original }, "Rejected backup overwrote original")
        }
        try run("Semantically invalid local files never publish invalid records") {
            let url = root.appendingPathComponent("recovery-invalid-fields.json")
            var invalid = TrainingArchive()
            invalid.nextDay = 0
            try JSONEncoder().encode(invalid).write(to: url)
            let records = TrainingStore(fileURL: url, isWatch: false)
            try expect(!records.storageReady && records.archive.nextDay == 1, "Invalid values leaked into UI state")
        }
        try run("Failed recovery write leaves storage blocked and preserves its source") {
            let url = root.appendingPathComponent("recovery-directory.json", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let records = TrainingStore(fileURL: url, isWatch: false)
            try rejects { try records.restore(JSONEncoder().encode(TrainingArchive())) }
            var isDirectory: ObjCBool = false
            try expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue, "Failed write removed source")
            try expect(!records.storageReady && records.archive.sessions.isEmpty, "Failed recovery published replacement")
        }
        try run("Sync batching stays bounded and prioritizes peer receipts") {
            let records = (0..<30).map { _ in SyncEvent(id: UUID(), payload: .requestHistory) }
            let receipt = SyncEvent(id: UUID(), payload: .receipt(UUID(), nil))
            let batch = SyncSchedule.nextBatch(outbox: records + [receipt], attempted: [], outstanding: [])
            try expect(batch.count == 8 && batch.first?.id == receipt.id, "Batch was unbounded or receipts starved")
            let outstanding = Set(records.prefix(7).map(\.id))
            let one = SyncSchedule.nextBatch(outbox: records + [receipt], attempted: [], outstanding: outstanding)
            try expect(one.count == 1 && one.first?.id == receipt.id, "Outstanding transfers ignored")
            try expect(SyncSchedule.nextBatch(outbox: records, attempted: [], outstanding: Set(records.prefix(8).map(\.id))).isEmpty, "Exceeded transfer cap")
            try expect(SyncSchedule.nextBatch(outbox: records, attempted: Set(records.map(\.id)), outstanding: []).isEmpty, "Retried events without an explicit retry")
        }
        func transactionFiles(_ url: URL) throws -> [URL] {
            let folder = url.appendingPathExtension("transactions")
            guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
            return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
        }
        try run("Checkpoint and journal jointly recover a completed set and its durable outbox") {
            let url = root.appendingPathComponent("journal-replay.json")
            let records = TrainingStore(fileURL: url, isWatch: true)
            let id = try records.begin(day: 2)
            try records.setHealth(id, state: .recording)
            _ = try records.logSet(id, token: records.session(id)!.pendingSetID)
            let reopened = TrainingStore(fileURL: url, isWatch: true)
            try expect(reopened.archive == records.archive, "Journal changed record/outbox identity")
            let count = try transactionFiles(url).count
            try expect(count >= 3, "Changes were not journaled")
        }
        try run("Plain-archive migration preserves all old observations and event identities") {
            let source = store("migrationSource")
            let id = try complete(source, day: 1, advance: 1)
            let url = root.appendingPathComponent("legacy-migration.json")
            try source.exportData().write(to: url)
            let migrated = TrainingStore(fileURL: url, isWatch: true)
            let previous = migrated.archive
            _ = try migrated.begin(day: 2)
            let reopened = TrainingStore(fileURL: url, isWatch: true)
            try expect(reopened.session(id) == previous.sessions.first, "Migration changed old records")
            try expect(reopened.archive.sessions.count == 2 && reopened.storageReady, "Migration did not replay the new transaction")
        }
        try run("Unreadable transaction blocks partial history and recovery preserves the full source") {
            let url = root.appendingPathComponent("journal-corrupt.json")
            let source = TrainingStore(fileURL: url, isWatch: true)
            let id = try complete(source, day: 1, advance: 1)
            let backup = try source.exportData()
            let files = try transactionFiles(url)
            try Data("broken transaction".utf8).write(to: files.last!)
            let blocked = TrainingStore(fileURL: url, isWatch: false)
            try expect(!blocked.storageReady && blocked.archive.sessions.isEmpty, "Partially replayed records leaked into UI")
            try blocked.restore(backup)
            try expect(blocked.session(id) == source.session(id), "Recovery lost original set IDs")
            let bundle = try JSONSerialization.jsonObject(with: blocked.exportPreservedArchive()) as! [String: Any]
            try expect(bundle["format"] as? String == "REP preserved unreadable store", "Journal recovery export omitted its source files")
            let reopened = TrainingStore(fileURL: url, isWatch: false)
            try expect(reopened.storageReady && reopened.preservedArchiveURL != nil, "Recovery receipt did not survive restart")
            try expect(tryResult { try reopened.exportPreservedArchive() == blocked.exportPreservedArchive() }, "Original recovery export changed after reopening")
        }
        try run("A gap in journal sequence blocks storage instead of silently losing changes") {
            let url = root.appendingPathComponent("journal-gap.json")
            let records = TrainingStore(fileURL: url, isWatch: true)
            let id = try records.begin(day: 1)
            try records.setHealth(id, state: .recording)
            try records.editDraft(id, load: records.session(id)!.draftLoad, reps: 8)
            let files = try transactionFiles(url)
            try FileManager.default.removeItem(at: files[1])
            try expect(!TrainingStore(fileURL: url, isWatch: true).storageReady, "Journal gap was ignored")
        }
        try run("Compaction retains complete records and accepts the next transaction after restart") {
            let url = root.appendingPathComponent("journal-compaction.json")
            let disk = TrainingJournal(fileURL: url)
            var first = try disk.load()
            first.nextDay = 2
            try disk.append(before: TrainingArchive(), after: first)
            var second = first
            second.nextDay = 3
            try disk.append(before: first, after: second)
            try disk.compact(second)
            try expect(disk.pendingTransactionCount == 0, "Compaction did not advance the checkpoint")
            let restarted = TrainingJournal(fileURL: url)
            let loaded = try restarted.load()
            try expect(loaded == second, "Checkpoint lost state")
            var third = second
            third.nextDay = 4
            try restarted.append(before: second, after: third)
            let replayed = try TrainingJournal(fileURL: url).load()
            try expect(replayed == third, "Post-compaction transaction sequence broke")
        }
        try run("Workout end compacts a long journal without changing the canonical archive") {
            let url = root.appendingPathComponent("journal-end-compaction.json")
            let records = TrainingStore(fileURL: url, isWatch: true)
            let id = try records.begin(day: 2)
            for index in 0..<128 { try records.editDraft(id, load: records.session(id)!.draftLoad, reps: index % 20 + 1) }
            try records.finalizeLocal(id, completed: true, advanceFromDay: 2)
            let reopened = TrainingStore(fileURL: url, isWatch: true)
            try expect(reopened.archive == records.archive, "End checkpoint mutated canonical data")
            let files = try transactionFiles(url)
            try expect(files.isEmpty, "Obsolete transactions were not compacted")
        }
        try run("320-session desktop fixture retains history during a new local commit") {
            var fixture = TrainingArchive()
            let seed = TrainingPlan.seed
            for index in 0..<320 {
                let day = index % 6 + 1
                let date = Date.now.addingTimeInterval(Double(index - 321) * 86400)
                let routine = seed.routine(day: day)
                var session = StrengthSession(id: UUID(), day: day, startedAt: date, routine: routine, draftLoad: routine[0].load, draftReps: 10)
                for exercise in routine {
                    for ordinal in 1...exercise.sets {
                        session.sets.append(.init(id: UUID(), exerciseID: exercise.id, exerciseName: exercise.name, ordinal: ordinal, load: exercise.load, reps: 10, completedAt: date.addingTimeInterval(Double(ordinal))))
                    }
                }
                session.endedAt = date.addingTimeInterval(3600)
                session.completed = true
                session.nextDayAfterCompletion = day % 6 + 1
                fixture.sessions.append(session)
            }
            fixture.nextDay = 3
            let url = root.appendingPathComponent("large-history.json")
            try JSONEncoder().encode(fixture).write(to: url)
            let start = Date()
            let records = TrainingStore(fileURL: url, isWatch: true)
            let loadSeconds = Date().timeIntervalSince(start)
            let id = try records.begin(day: 3)
            try records.setHealth(id, state: .recording)
            let token = records.session(id)!.pendingSetID
            let commitStart = Date()
            _ = try records.logSet(id, token: token)
            let commitSeconds = Date().timeIntervalSince(commitStart)
            try expect(records.archive.sessions.count == 321 && records.archive.sessions[0] == fixture.sessions[0], "Large-history commit lost original records")
            let bytes = try Data(contentsOf: url).count
            let files = try transactionFiles(url)
            let lastBytes = try Data(contentsOf: files.last!).count
            try expect(lastBytes < bytes / 5, "Set save still rewrote a full history-sized payload")
            print("PROFILE synthetic desktop fixture: 320 historical sessions, \(bytes)-byte checkpoint, \(lastBytes)-byte latest transaction, load \(String(format: "%.4f", loadSeconds))s, one-set commit \(String(format: "%.4f", commitSeconds))s. Not a Watch latency or battery measurement.")
        }
    }
}
