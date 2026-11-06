import Foundation

/// A checkpoint plus ordered atomic transaction files. Every transaction includes
/// its record changes AND outbox changes, so publishing a set never depends on sync.
@MainActor
final class TrainingJournal {
    private struct Checkpoint: Codable {
        var formatVersion = 1
        let generation: UUID
        let appliedSequence: Int
        let archive: TrainingArchive
        let preservedOriginalName: String?
    }
    private struct Transaction: Codable {
        var formatVersion = 1
        let sequence: Int
        let metadata: TrainingArchive
        let sessions: [StrengthSession]
        let removedSessions: [UUID]
        let sessionOrder: [UUID]?
        let events: [SyncEvent]
        let removedEvents: [UUID]
        let eventOrder: [UUID]?

        init(sequence: Int, before: TrainingArchive, after: TrainingArchive) {
            self.sequence = sequence
            var metadata = after
            metadata.sessions = []
            metadata.outbox = []
            self.metadata = metadata
            let oldSessions = Dictionary(uniqueKeysWithValues: before.sessions.map { ($0.id, $0) })
            let sessionIDs = Set(after.sessions.map(\.id))
            sessions = after.sessions.filter { oldSessions[$0.id] != $0 }
            removedSessions = before.sessions.map(\.id).filter { !sessionIDs.contains($0) }
            sessionOrder = before.sessions.map(\.id) == after.sessions.map(\.id) ? nil : after.sessions.map(\.id)
            let oldEvents = Dictionary(uniqueKeysWithValues: before.outbox.map { ($0.id, $0) })
            let eventIDs = Set(after.outbox.map(\.id))
            events = after.outbox.filter { oldEvents[$0.id] != $0 }
            removedEvents = before.outbox.map(\.id).filter { !eventIDs.contains($0) }
            eventOrder = before.outbox.map(\.id) == after.outbox.map(\.id) ? nil : after.outbox.map(\.id)
        }
        func applying(to before: TrainingArchive) throws -> TrainingArchive {
            guard formatVersion == 1, sequence > 0, metadata.sessions.isEmpty, metadata.outbox.isEmpty else { throw TrainingError.invalidArchive }
            var result = metadata
            result.sessions = try Self.merge(before.sessions, changes: sessions, removals: removedSessions, order: sessionOrder)
            result.outbox = try Self.merge(before.outbox, changes: events, removals: removedEvents, order: eventOrder)
            return result
        }
        private static func merge<Value: Identifiable>(_ previous: [Value], changes: [Value], removals: [UUID], order: [UUID]?) throws -> [Value] where Value.ID == UUID {
            guard Set(changes.map(\.id)).count == changes.count else { throw TrainingError.invalidArchive }
            let deleted = Set(removals)
            var values = previous.filter { !deleted.contains($0.id) }
            for value in changes {
                if let i = values.firstIndex(where: { $0.id == value.id }) { values[i] = value }
                else { values.append(value) }
            }
            if let order {
                guard Set(order).count == order.count, Set(order) == Set(values.map(\.id)) else { throw TrainingError.invalidArchive }
                let byID = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
                values = try order.map { id in
                    guard let value = byID[id] else { throw TrainingError.invalidArchive }
                    return value
                }
            }
            return values
        }
    }
    private let fileURL: URL
    private var generation: UUID?
    private var sequence = 0
    private var checkpointSequence = 0
    private var preservedOriginalName: String?
    var pendingTransactionCount: Int { sequence - checkpointSequence }
    var preservedOriginalURL: URL? {
        guard let preservedOriginalName, preservedOriginalName == URL(fileURLWithPath: preservedOriginalName).lastPathComponent,
              preservedOriginalName.hasPrefix("training-unreadable-") else { return nil }
        let url = fileURL.deletingLastPathComponent().appendingPathComponent(preservedOriginalName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    private var journalRoot: URL { fileURL.appendingPathExtension("transactions") }
    private func directory(for generation: UUID) -> URL { journalRoot.appendingPathComponent(generation.uuidString, isDirectory: true) }

    init(fileURL: URL) { self.fileURL = fileURL }
    func load() throws -> TrainingArchive {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            guard !FileManager.default.fileExists(atPath: journalRoot.path) else { throw TrainingError.invalidArchive }
            return TrainingArchive()
        }
        let data = try Data(contentsOf: fileURL)
        guard let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data) else {
            // The previous release stored a plain archive. Migration happens on
            // the next successful commit, preserving every record and event ID.
            return try JSONDecoder().decode(TrainingArchive.self, from: data)
        }
        guard checkpoint.formatVersion == 1, checkpoint.appliedSequence >= 0 else { throw TrainingError.invalidArchive }
        var archive = checkpoint.archive
        var lastSequence = checkpoint.appliedSequence
        let folder = directory(for: checkpoint.generation)
        if FileManager.default.fileExists(atPath: folder.path) {
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            for url in files {
                guard let index = Int(url.deletingPathExtension().lastPathComponent), index > 0 else { throw TrainingError.invalidArchive }
                if index <= checkpoint.appliedSequence { continue }
                guard lastSequence < Int.max, index == lastSequence + 1 else { throw TrainingError.invalidArchive }
                let transaction = try JSONDecoder().decode(Transaction.self, from: Data(contentsOf: url))
                guard transaction.sequence == index else { throw TrainingError.invalidArchive }
                archive = try transaction.applying(to: archive)
                lastSequence = index
            }
        }
        generation = checkpoint.generation
        sequence = lastSequence
        checkpointSequence = checkpoint.appliedSequence
        preservedOriginalName = checkpoint.preservedOriginalName
        return archive
    }
    func append(before: TrainingArchive, after: TrainingArchive) throws {
        if generation == nil {
            let fresh = UUID()
            try write(Checkpoint(generation: fresh, appliedSequence: 0, archive: before, preservedOriginalName: preservedOriginalName), to: fileURL)
            generation = fresh
        }
        guard let generation, sequence < Int.max else { throw TrainingError.invalidArchive }
        let next = sequence + 1
        let transaction = Transaction(sequence: next, before: before, after: after)
        let digits = String(next)
        let name = String(repeating: "0", count: max(0, 20 - digits.count)) + digits + ".json"
        let url = directory(for: generation).appendingPathComponent(name)
        try write(transaction, to: url)
        sequence = next
    }
    func replace(with archive: TrainingArchive, preservedURL: URL?) throws {
        let fresh = UUID()
        let name = preservedURL?.lastPathComponent
        try write(Checkpoint(generation: fresh, appliedSequence: 0, archive: archive, preservedOriginalName: name), to: fileURL)
        generation = fresh
        sequence = 0
        checkpointSequence = 0
        preservedOriginalName = name
        // Earlier generations remain intact for recovery; they cannot be replayed
        // against this checkpoint because their generation IDs differ.
    }
    func compact(_ archive: TrainingArchive) throws {
        guard let generation else { return }
        try write(Checkpoint(generation: generation, appliedSequence: sequence, archive: archive, preservedOriginalName: preservedOriginalName), to: fileURL)
        checkpointSequence = sequence
        let folder = directory(for: generation)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "json" {
            if let index = Int(file.deletingPathExtension().lastPathComponent), index <= sequence {
                // Once the checkpoint is durable, obsolete transactions are optional.
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    func preserveOriginal() throws -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let preserved = fileURL.deletingLastPathComponent().appendingPathComponent("training-unreadable-\(UUID()).json")
        try FileManager.default.copyItem(at: fileURL, to: preserved)
        if FileManager.default.fileExists(atPath: journalRoot.path) {
            try FileManager.default.copyItem(at: journalRoot, to: preserved.appendingPathExtension("transactions"))
        }
        return preserved
    }
    func exportPreserved(_ url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        let folder = url.appendingPathExtension("transactions")
        guard FileManager.default.fileExists(atPath: folder.path) else { return data }
        struct RecoveryBundle: Codable {
            let format: String
            let original: Data
            let transactions: [String: Data]
        }
        var transactions: [String: Data] = [:]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { throw TrainingError.invalidArchive }
        for case let file as URL in enumerator where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            let relative = String(file.path.dropFirst(folder.path.count + 1))
            transactions[relative] = try Data(contentsOf: file)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(RecoveryBundle(format: "REP preserved unreadable store", original: data, transactions: transactions))
    }
    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
        #if os(iOS) || os(watchOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
}
