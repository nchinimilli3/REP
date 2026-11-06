import Foundation
import Testing
@testable import fitness_Watch_App

struct fitness_Watch_AppTests {
    @Test func routinePreservesOriginalPrescription() {
        let totals = (1...3).map { TrainingPlan.seed.routine(day: $0).reduce(0) { $0 + $1.sets } }
        #expect(totals == [16, 12, 12])
        #expect(TrainingPlan.seed.exercises.first { $0.id == "thrust" }?.load.addedPlates == 50)
        #expect(TrainingPlan.seed.exercises.first { $0.id == "abs" }?.load.pounds == nil)
    }
    @Test @MainActor func failedHealthSaveDoesNotLoseCompletedSet() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("records.json")
        let records = TrainingStore(fileURL: file, isWatch: true)
        let id = try records.begin(day: 2)
        try records.setHealth(id, state: .recording)
        let token = try #require(records.session(id)?.pendingSetID)
        #expect(try records.logSet(id, token: token))
        #expect(try !records.logSet(id, token: token))
        try records.setHealth(id, state: .recovery, error: "Fixture save failure")
        let restored = TrainingStore(fileURL: file, isWatch: true)
        #expect(restored.session(id)?.effectiveSets.count == 1)
        #expect(restored.session(id)?.healthUUID == nil)
        #expect(restored.session(id)?.healthState == .recovery)
    }
}
