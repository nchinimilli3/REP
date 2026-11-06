#if !os(watchOS)
import Foundation
import CryptoKit
import Network

/// Local encrypted backup protocol. Bonjour publishes only a hash of the pairing key.
enum LaptopProtocol {
    static let service = "_repbackup._tcp"
    static let maximumFrame = 32 * 1024 * 1024
    static func key(_ text: String) throws -> SymmetricKey {
        guard let bytes = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)), bytes.count == 32 else {
            throw LaptopError.message("Paste the complete laptop pairing key.")
        }
        return SymmetricKey(data: bytes)
    }
    static func serviceName(_ key: SymmetricKey) -> String {
        key.withUnsafeBytes { "REP-" + SHA256.hash(data: Data($0)).prefix(8).map { String(format: "%02x", $0) }.joined() }
    }
    static func seal<T: Encodable>(_ value: T, key: SymmetricKey) throws -> Data {
        let bytes = try JSONEncoder().encode(value)
        guard let combined = try AES.GCM.seal(bytes, using: key).combined, combined.count <= maximumFrame else {
            throw LaptopError.message("Laptop backup exceeds the transfer limit.")
        }
        return combined
    }
    static func open<T: Decodable>(_ type: T.Type, data: Data, key: SymmetricKey) throws -> T {
        try JSONDecoder().decode(type, from: AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key))
    }
    static func fingerprint(_ archive: TrainingArchive) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(archive)).map { String(format: "%02x", $0) }.joined()
    }
}
enum LaptopError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
struct LaptopSnapshot: Codable {
    var version = 1
    let sender: UUID
    let sequence: Int
    let archive: TrainingArchive
}
struct LaptopReceipt: Codable {
    let sender: UUID
    let sequence: Int
    let fingerprint: String
}

/// One request and one authenticated receipt per connection. All callbacks use the main queue.
final class LaptopWire {
    let connection: NWConnection
    init(_ connection: NWConnection) { self.connection = connection }
    func send(_ data: Data, completion: @escaping (Error?) -> Void) {
        guard data.count > 0, data.count <= LaptopProtocol.maximumFrame else {
            completion(LaptopError.message("Invalid transfer size.")); return
        }
        let n = UInt32(data.count)
        let header = Data([UInt8((n >> 24) & 255), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)])
        connection.send(content: header + data, completion: .contentProcessed(completion))
    }
    func receive(completion: @escaping (Result<Data, Error>) -> Void) {
        read(4) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let header):
                let count = header.reduce(0) { ($0 << 8) | Int($1) }
                guard count > 0, count <= LaptopProtocol.maximumFrame else {
                    completion(.failure(LaptopError.message("Invalid transfer size."))); return
                }
                self.read(count, completion: completion)
            }
        }
    }
    private func read(_ count: Int, accumulated: Data = Data(), completion: @escaping (Result<Data, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: count - accumulated.count) { data, _, ended, error in
            let bytes = accumulated + (data ?? Data())
            if let error { completion(.failure(error)) }
            else if bytes.count == count { completion(.success(bytes)) }
            else if ended { completion(.failure(LaptopError.message("Transfer ended before all records arrived."))) }
            else { self.read(count, accumulated: bytes, completion: completion) }
        }
    }
}

/// Flat analysis view; corrected values are used, voided sets excluded, typed loads kept separate.
enum LaptopCSV {
    static func render(_ archive: TrainingArchive) -> String {
        func cell(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let date = ISO8601DateFormatter()
        var rows = ["session_id,session_started_at,session_completed,exercise_id,exercise,set_id,set_number,set_completed_at,reps,load_kind,pounds,smith_bar_pounds,comparison_key"]
        for session in archive.sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            for set in session.effectiveSets {
                // Protect spreadsheet consumers from formulas in user-editable names.
                var name = set.original.exerciseName
                if let first = name.first, "=+-@\t\r\n".contains(first) { name = "'" + name }
                let values = [session.id.uuidString, date.string(from: session.startedAt), String(session.completed),
                              set.original.exerciseID, name, set.id.uuidString, String(set.original.ordinal),
                              date.string(from: set.original.completedAt), String(set.reps), set.load.kind.rawValue,
                              set.load.pounds.map { String($0) } ?? "", set.load.smithBarPounds.map { String($0) } ?? "", set.load.comparisonKey]
                rows.append(values.map(cell).joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }
}
#endif
