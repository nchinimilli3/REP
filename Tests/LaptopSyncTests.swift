import Foundation
import CryptoKit
import Network

@main
struct LaptopSyncTests {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rep-laptop-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        var passed = 0
        func check(_ title: String, _ condition: @autoclosure () throws -> Bool) throws {
            guard try condition() else { throw LaptopError.message(title) }
            passed += 1; print("PASS \(title)")
        }
        func rejects(_ title: String, _ action: () throws -> Void) throws {
            var rejected = false
            do { try action() } catch { rejected = true }
            try check(title, rejected)
        }
        let store = TrainingStore(fileURL: folder.appendingPathComponent("watch/training.json"), isWatch: true)
        let id = try store.begin(day: 1)
        try store.setHealth(id, state: .recording)
        _ = try store.logSet(id, token: store.session(id)!.pendingSetID)
        try store.finalizeLocal(id, completed: true, advanceFromDay: 1)
        let archive = store.archive
        let sender = UUID()
        let snapshot = LaptopSnapshot(sender: sender, sequence: 1, archive: archive)
        let key = SymmetricKey(size: .bits256)
        let encrypted = try LaptopProtocol.seal(snapshot, key: key)
        let decoded = try LaptopProtocol.open(LaptopSnapshot.self, data: encrypted, key: key)
        try check("Encrypted snapshot round trip", decoded.archive == archive)
        try rejects("Wrong pairing key rejected") { _ = try LaptopProtocol.open(LaptopSnapshot.self, data: encrypted, key: SymmetricKey(size: .bits256)) }
        var tampered = encrypted; tampered[tampered.count - 1] ^= 1
        try rejects("Tampered payload rejected") { _ = try LaptopProtocol.open(LaptopSnapshot.self, data: tampered, key: key) }
        try rejects("Short pairing key rejected") { _ = try LaptopProtocol.key("aGVsbG8=") }
        let repository = try LaptopRepository(directory: folder.appendingPathComponent("mac"))
        let receipt = try repository.accept(snapshot)
        try check("Receipt matches persisted snapshot", receipt.fingerprint == LaptopProtocol.fingerprint(archive))
        _ = try repository.accept(snapshot)
        try check("Duplicate snapshot does not duplicate sets", repository.ledger!.archive.sessions.flatMap(\.effectiveSets).count == 1)
        try check("CSV contains typed assistance and reps", LaptopCSV.render(archive).contains("\"assistance\",\"70.0\""))
        let reopened = try LaptopRepository(directory: repository.directory)
        try check("Restart recovers committed history", reopened.ledger!.archive == archive)
        try rejects("Different sender cannot overwrite backup") { _ = try repository.accept(LaptopSnapshot(sender: UUID(), sequence: 2, archive: archive)) }
        var changed = archive
        changed.sessions[0].corrections.append(SetCorrection(id: UUID(), setID: changed.sessions[0].sets[0].id,
            load: TrainingLoad(kind: .assistance, pounds: 60), reps: 8, voided: false, date: .now))
        changed.sessions[0].revision += 1
        _ = try repository.accept(LaptopSnapshot(sender: sender, sequence: 2, archive: changed))
        try check("Corrected reps and assistance replace CSV values", LaptopCSV.render(repository.ledger!.archive).contains("\"8\",\"assistance\",\"60.0\""))
        try rejects("Old sequence rejected") { _ = try repository.accept(snapshot) }
        try rejects("Equal sequence divergent content rejected") { _ = try repository.accept(LaptopSnapshot(sender: sender, sequence: 2, archive: archive)) }
        var conflict = changed; conflict.sessions[0].draftReps = 9
        try rejects("Equal workout revision divergent content rejected") { _ = try repository.accept(LaptopSnapshot(sender: sender, sequence: 3, archive: conflict)) }
        let pending = try JSONDecoder().decode(LaptopSnapshot.self, from: Data(contentsOf: repository.directory.appendingPathComponent("pending-conflict.json")))
        try check("Conflicting phone snapshot preserved separately", pending.archive == conflict)
        try check("Conflict does not replace committed Mac archive", repository.ledger!.archive == changed)
        _ = try repository.accept(LaptopSnapshot(sender: sender, sequence: 3, archive: archive))
        try check("Older phone revision cannot replace newer laptop record", repository.ledger!.archive.sessions[0].revision == changed.sessions[0].revision)
        var missing = archive; missing.sessions = []
        _ = try repository.accept(LaptopSnapshot(sender: sender, sequence: 4, archive: missing))
        try check("Missing phone history preserves laptop record", repository.ledger!.archive.sessions.count == 1)
        var voided = changed
        voided.sessions[0].revision += 1
        voided.sessions[0].corrections.append(SetCorrection(id: UUID(), setID: changed.sessions[0].sets[0].id,
            load: TrainingLoad(kind: .assistance, pounds: 60), reps: 8, voided: true, date: .now))
        _ = try repository.accept(LaptopSnapshot(sender: sender, sequence: 5, archive: voided))
        try check("Voided set excluded from analysis", repository.ledger!.archive.sessions[0].effectiveSets.isEmpty)
        let disk = try JSONDecoder().decode(TrainingArchive.self, from: Data(contentsOf: repository.directory.appendingPathComponent("training.json")))
        try check("Published JSON matches saved merged archive", disk == repository.ledger!.archive)
        let permissions = try FileManager.default.attributesOfItem(atPath: repository.directory.appendingPathComponent("sets.csv").path)[.posixPermissions] as? NSNumber
        try check("Data files owner readable only", permissions?.intValue == 0o600)
        try await transportCheck(key: key, snapshot: snapshot)
        try check("Framed encrypted TCP request and authenticated receipt", true)
        print("\(passed) laptop sync scenarios passed. Synthetic local fixtures only; no physical sync claim.")
    }
    @MainActor static func transportCheck(key: SymmetricKey, snapshot: LaptopSnapshot) async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        var server: LaptopWire?
        var client: LaptopWire?
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var finished = false
            func finish(_ error: Error? = nil) {
                guard !finished else { return }; finished = true
                listener.cancel(); server?.connection.cancel(); client?.connection.cancel()
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
            listener.newConnectionHandler = { connection in
                let wire = LaptopWire(connection); server = wire
                connection.start(queue: .main)
                wire.receive { result in
                    do {
                        let received = try LaptopProtocol.open(LaptopSnapshot.self, data: result.get(), key: key)
                        guard received.archive == snapshot.archive else { throw TrainingError.conflict }
                        let receipt = LaptopReceipt(sender: received.sender, sequence: received.sequence,
                            fingerprint: try LaptopProtocol.fingerprint(received.archive))
                        wire.send(try LaptopProtocol.seal(receipt, key: key)) { error in if let error { finish(error) } }
                    } catch { finish(error) }
                }
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state { finish(error) }
                guard case .ready = state, let port = listener.port else { return }
                let connection = NWConnection(host: .ipv4(.loopback), port: port, using: .tcp)
                let wire = LaptopWire(connection); client = wire
                connection.stateUpdateHandler = { state in
                    if case .failed(let error) = state { finish(error) }
                    guard case .ready = state else { return }
                    do {
                        wire.send(try LaptopProtocol.seal(snapshot, key: key)) { error in
                            if let error { finish(error); return }
                            wire.receive { result in
                                do {
                                    let receipt = try LaptopProtocol.open(LaptopReceipt.self, data: result.get(), key: key)
                                    guard receipt.sender == snapshot.sender, receipt.sequence == snapshot.sequence,
                                        receipt.fingerprint == (try LaptopProtocol.fingerprint(snapshot.archive)) else { throw TrainingError.conflict }
                                    finish()
                                } catch { finish(error) }
                            }
                        }
                    } catch { finish(error) }
                }
                connection.start(queue: .main)
            }
            listener.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { finish(LaptopError.message("Loopback transfer timed out")) }
        }
    }

}
