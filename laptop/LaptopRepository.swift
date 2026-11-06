import Foundation

/// Durable ledger is authoritative; JSON/CSV are regenerated views for analysis.
@MainActor
final class LaptopRepository {
    struct Ledger: Codable {
        let sender: UUID
        let sequence: Int
        let fingerprint: String
        let receivedAt: Date
        let archive: TrainingArchive
    }
    let directory: URL
    private(set) var ledger: Ledger?
    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("sync-state.json")
        if FileManager.default.fileExists(atPath: url.path) {
            ledger = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: url))
            try TrainingStore.validate(ledger!.archive)
            try publish(ledger!.archive)
        }
    }
    func accept(_ snapshot: LaptopSnapshot) throws -> LaptopReceipt {
        guard snapshot.version == 1, snapshot.sequence > 0 else { throw TrainingError.invalidArchive }
        try TrainingStore.validate(snapshot.archive)
        let fingerprint = try LaptopProtocol.fingerprint(snapshot.archive)
        if let old = ledger {
            guard old.sender == snapshot.sender else {
                throw LaptopError.message("This laptop is paired with a different iPhone installation. Preserve its backup before replacing pairing.")
            }
            guard snapshot.sequence >= old.sequence else {
                try rejectConflict(snapshot, message: "The iPhone transfer sequence is older than this Mac's saved receipt.")
            }
            if snapshot.sequence == old.sequence {
                guard fingerprint == old.fingerprint else {
                    try rejectConflict(snapshot, message: "The iPhone reused a transfer sequence with different records.")
                }
                try publish(old.archive)
                return LaptopReceipt(sender: snapshot.sender, sequence: snapshot.sequence, fingerprint: fingerprint)
            }
        }
        var archive = snapshot.archive
        if let old = ledger {
            // Preserve workouts missing from a restored phone; never discard a newer revision.
            for prior in old.archive.sessions {
                if let i = archive.sessions.firstIndex(where: { $0.id == prior.id }) {
                    if prior.revision == archive.sessions[i].revision, prior != archive.sessions[i] {
                        try rejectConflict(snapshot, message: "A workout has different contents on iPhone and Mac at the same revision. Both copies are preserved for review.")
                    }
                    if prior.revision > archive.sessions[i].revision { archive.sessions[i] = prior }
                } else { archive.sessions.append(prior) }
            }
        }
        try TrainingStore.validate(archive)
        let next = Ledger(sender: snapshot.sender, sequence: snapshot.sequence, fingerprint: fingerprint, receivedAt: .now, archive: archive)
        try write(try JSONEncoder().encode(next), name: "sync-state.json")
        ledger = next
        try publish(archive)
        return LaptopReceipt(sender: snapshot.sender, sequence: snapshot.sequence, fingerprint: fingerprint)
    }
    private func rejectConflict(_ snapshot: LaptopSnapshot, message: String) throws -> Never {
        // Authenticated, validated incoming data is preserved separately, never adopted as a successful receipt.
        try write(try JSONEncoder().encode(snapshot), name: "pending-conflict.json")
        throw LaptopError.message(message)
    }
    private func publish(_ archive: TrainingArchive) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(try encoder.encode(archive), name: "training.json")
        try write(Data(LaptopCSV.render(archive).utf8), name: "sets.csv")
    }
    private func write(_ data: Data, name: String) throws {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
