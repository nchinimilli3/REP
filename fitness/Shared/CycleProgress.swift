import Foundation

/// Only the Watch creates or advances a rotation. A new ID begins when the user
/// explicitly advances from the third workout type to the first; elapsed calendar days never do so.
struct RotationState: Codable, Equatable, Sendable {
    var revision: Int
    var nextDay: Int
    var cycleID: UUID

    func validate() throws {
        guard revision >= 0, revision < Int.max, (1...6).contains(nextDay) else { throw TrainingError.invalidArchive }
    }
    func advancing(from day: Int) throws -> RotationState {
        try validate()
        guard (1...6).contains(day) else { throw TrainingError.invalidState }
        return RotationState(revision: revision + 1, nextDay: day % 3 + 1, cycleID: day % 3 == 0 ? UUID() : cycleID)
    }
}

extension TrainingArchive {
    mutating func adoptRotation(_ incoming: RotationState) throws {
        try incoming.validate()
        if let rotation {
            if incoming.revision < rotation.revision { return }
            if incoming.revision == rotation.revision {
                guard incoming == rotation else { throw TrainingError.conflict }
                return
            }
        } else if incoming.revision < rotationRevision { return }
        rotation = incoming
        nextDay = incoming.nextDay
        rotationRevision = incoming.revision
    }
    /// Legacy histories lack cycle membership. Preserve their next-day decision,
    /// but never guess which earlier positions were completed in the current cycle.
    mutating func reconcileRotationFromHistory() throws {
        for state in sessions.compactMap(\.rotationAfterCompletion).sorted(by: { $0.revision < $1.revision }) {
            try adoptRotation(state)
        }
        if rotation == nil, let last = sessions.filter({ $0.nextDayAfterCompletion != nil })
            .max(by: { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }) {
            nextDay = last.nextDayAfterCompletion ?? nextDay
        }
    }
}

struct CycleDayProgress: Identifiable, Sendable {
    let day: Int
    let sessionID: UUID?
    let isNext: Bool
    let includesAbs: Bool
    var id: Int { day }
    var completed: Bool { sessionID != nil }
    var accessibilityDescription: String {
        "\(Split.at(day: day).title), \(completed ? "completed" : "not completed")\(isNext ? ", next suggested session" : "")\(includesAbs ? ", with Abs" : "")"
    }
}

struct CurrentCycleProgress: Sendable {
    let cycleID: UUID?
    let days: [CycleDayProgress]
    var completedCount: Int { days.filter(\.completed).count }
    init(archive: TrainingArchive) {
        let currentID = archive.rotation?.cycleID
        cycleID = currentID
        let matching = archive.sessions.filter { session in
            (session.routineID == nil || Split.allCases.contains(where: { $0.rawValue == session.routineID })) && currentID != nil && session.cycleID == currentID && session.completed && session.endedAt != nil && session.nextDayAfterCompletion != nil
        }
        days = (1...3).map { day in
            let latest = matching.filter { Split.at(day: $0.day) == Split.at(day: day) }.max { $0.startedAt < $1.startedAt }
            return CycleDayProgress(day: day, sessionID: latest?.id, isNext: Split.at(day: archive.nextDay) == Split.at(day: day),
                                    includesAbs: latest?.effectiveSets.contains { $0.original.exerciseID == "abs" } == true)
        }
    }
}

/// Keep transport resource use bounded while preserving every durable event.
/// Receipts go first so a large history cannot starve confirmation traffic.
nonisolated enum SyncSchedule {
    static let maximumOutstanding = 8
    static func nextBatch(outbox: [SyncEvent], attempted: Set<UUID>, outstanding: Set<UUID>) -> [SyncEvent] {
        let capacity = max(0, maximumOutstanding - outstanding.count)
        guard capacity > 0 else { return [] }
        let eligible = outbox.filter { !attempted.contains($0.id) && !outstanding.contains($0.id) }
        let receipts = eligible.filter { !$0.requiresReceipt }
        let records = eligible.filter(\.requiresReceipt)
        return Array((receipts + records).prefix(capacity))
    }
}
