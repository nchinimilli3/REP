import Foundation
import HealthKit
import Combine

@MainActor
final class HealthHistory: ObservableObject {
    @Published private(set) var workouts: [HKWorkout] = []
    @Published private(set) var activity: HKActivitySummary?
    @Published private(set) var steps: Double?
    @Published var status = "Connect Apple Health to view available workout summaries."
    @Published var busy = false
    private let health = HKHealthStore()
    private var activityBusy = false
    private(set) var requestedAccess = false
    func refresh() async {
        guard !busy, HKHealthStore.isHealthDataAvailable() else { return }
        busy = true
        defer { busy = false }
        do {
            try await health.requestAuthorization(toShare: [], read: [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKObjectType.activitySummaryType(), HKQuantityType(.stepCount)])
            requestedAccess = true
            let type = HKObjectType.workoutType()
            let allowed = NSCompoundPredicate(orPredicateWithSubpredicates: [
                HKQuery.predicateForWorkouts(with: .traditionalStrengthTraining),
                NSCompoundPredicate(andPredicateWithSubpredicates: [HKQuery.predicateForWorkouts(with: .walking), HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyIndoorWorkout, allowedValues: [true])])
            ])
            workouts = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: type, predicate: allowed, limit: 200,
                                          sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: (samples as? [HKWorkout]) ?? []) }
                }
                health.execute(query)
            }
            await refreshActivity()
            status = "Latest available Health records (up to 200). Missing data may reflect limited access."
        } catch { status = "Health data unavailable: \(error.localizedDescription)" }
    }
    /// Refresh rings independently; don't reload 200 workouts or prompt every five seconds.
    func refreshActivity() async {
        guard requestedAccess, !activityBusy, HKHealthStore.isHealthDataAvailable() else { return }
        activityBusy = true
        defer { activityBusy = false }
        var day = Calendar.current.dateComponents([.era, .year, .month, .day], from: .now)
        day.calendar = .current
        do {
            activity = try await withCheckedThrowingContinuation { continuation in
                let query = HKActivitySummaryQuery(predicate: HKQuery.predicateForActivitySummary(with: day)) { _, summaries, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: summaries?.first) }
                }
                health.execute(query)
            }
        } catch { status = "Activity unavailable: \(error.localizedDescription)" }
        await refreshSteps()
    }
    private func refreshSteps() async {
        let now = Date.now
        let type = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: now),
                                                     end: now, options: .strictStartDate)
        do {
            steps = try await withCheckedThrowingContinuation { continuation in
                let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                              options: .cumulativeSum) { _, result, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: .count())) }
                }
                health.execute(query)
            }
        } catch { steps = nil }
    }
    func checkAssociation(_ uuid: UUID) async {
        guard !busy, HKHealthStore.isHealthDataAvailable() else { return }
        busy = true
        defer { busy = false }
        do {
            try await health.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
            let found: Bool = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: .workoutType(), predicate: HKQuery.predicateForObject(with: uuid), limit: 1, sortDescriptors: nil) { _, samples, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: samples?.isEmpty == false) }
                }
                health.execute(query)
            }
            status = found ? "Linked Health workout is currently readable." : "Linked workout is not readable. It may be deleted or access may be limited. Your REP. sets are retained; no replacement workout was created."
        } catch { status = "Health association could not be checked: \(error.localizedDescription)" }
    }

    /// Delete only the exact linked workout. A zero count is not proof of deletion.
    func deleteWorkout(_ uuid: UUID) async throws {
        guard !busy, HKHealthStore.isHealthDataAvailable() else {
            throw WorkoutDeletionError.unavailable
        }
        busy = true
        defer { busy = false }
        let type = HKObjectType.workoutType()
        try await health.requestAuthorization(toShare: [type], read: [type])
        guard health.authorizationStatus(for: type) == .sharingAuthorized else {
            throw WorkoutDeletionError.permission
        }
        let count = try await health.deleteObjects(of: type, predicate: HKQuery.predicateForObject(with: uuid))
        guard count == 1 else { throw WorkoutDeletionError.notConfirmed }
        workouts.removeAll { $0.uuid == uuid }
    }

}


enum WorkoutDeletionError: LocalizedError {
    case unavailable, permission, notConfirmed, unresolved
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Health is unavailable or busy. Try again shortly."
        case .permission: return "Allow REP to manage workouts in Apple Health, then try again."
        case .notConfirmed: return "Apple Health did not confirm deletion. The workout may be unavailable or owned by another source. Your REP log was kept. Review the workout in Apple Health."
        case .unresolved: return "This workout's Health save is unresolved. Finish or review it on Apple Watch before deleting the log."
        }
    }
}
