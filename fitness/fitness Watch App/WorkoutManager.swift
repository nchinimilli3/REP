import Combine
import HealthKit
import Foundation
import WatchKit

@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    @Published var status = "Ready"
    @Published var conflictMessage: String?
    @Published var busy = false
    @Published private(set) var isStarting = false
    @Published var active = false
    @Published var paused = false
    @Published var heartRate: Double?
    @Published private(set) var heartRateMeasuredAt: Date?
    @Published var calories: Double?
    @Published var elapsed: TimeInterval = 0
    @Published var activitySummary: HKActivitySummary?
    @Published var activityStatus = "Activity data has not refreshed"
    @Published var recordID: UUID?
    @Published private(set) var needsRecovery = false
    let records: TrainingStore
    private let health = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var finalizing = false
    private var collectionStarted = false
    private var activityQuery: HKActivitySummaryQuery?

    init(records: TrainingStore) {
        self.records = records
        let unresolved = records.activeSession ?? records.history.first { [.recording, .saving, .recovery].contains($0.healthState) }
        recordID = unresolved?.id
        needsRecovery = unresolved != nil
        super.init()
    }
    var record: StrengthSession? { recordID.flatMap(records.session) }
    var canStart: Bool { records.storageReady && records.activeSession == nil && session == nil && !busy && !needsRecovery }
    var canLog: Bool { active && !paused && !busy && collectionStarted }

    func start(routineID: String) async {
        guard canStart else { return }
        busy = true
        isStarting = true
        var startSucceeded = false
        defer {
            busy = false
            // Collection may finish before the running-state callback arrives.
            // Keep startup visible until both parts of the handoff are ready.
            isStarting = startSucceeded && !active
        }
        do {
            guard HKHealthStore.isHealthDataAvailable() else { status = "HealthKit unavailable"; return }
            let energy = HKQuantityType(.activeEnergyBurned)
            try await health.requestAuthorization(toShare: [HKObjectType.workoutType(), energy],
                                                  read: [HKQuantityType(.heartRate), energy, HKObjectType.workoutType(), HKObjectType.activitySummaryType()])
            guard health.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
                status = "Allow workout saving in Health permissions before starting."
                return
            }
            let id = try records.begin(routineID: routineID)
            recordID = id
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
            var activityStarted = false
            do {
                let newSession = try HKWorkoutSession(healthStore: health, configuration: configuration)
                let newBuilder = newSession.associatedWorkoutBuilder()
                newBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: configuration)
                newSession.delegate = self
                newBuilder.delegate = self
                session = newSession
                builder = newBuilder
                // Stable local identity allows reconciliation after uncertain finalization.
                try await newBuilder.addMetadata([HKMetadataKeyExternalUUID: id.uuidString])
                let date = Date()
                newSession.startActivity(with: date)
                activityStarted = true
                try await newBuilder.beginCollection(at: date)
                collectionStarted = true
                active = newSession.state == .running || newSession.state == .paused
                paused = newSession.state == .paused
                try records.setHealth(id, state: .recording)
                heartRate = nil
                heartRateMeasuredAt = nil
                calories = nil
                elapsed = 0
                startSucceeded = true
                status = "Recording · sets save on Watch"
                if active { WKInterfaceDevice.current().play(.start) }
                refreshActivity()
            } catch {
                // Ending a started collection is reconciled instead of blindly creating a replacement.
                status = "Start interrupted: \(error.localizedDescription)"
                try? records.setHealth(id, state: .recovery, error: status)
                let failedSession = session
                switch WorkoutStartCleanup.after(sessionCreated: failedSession != nil, activityStarted: activityStarted, collectionStarted: collectionStarted) {
                case .none: break
                case .discard:
                    builder?.discardWorkout()
                    session = nil
                    builder = nil
                case .discardAndEnd:
                    // Release handles first so the .ended delegate callback cannot call finish() and save a partial workout.
                    let failedBuilder = builder
                    session = nil
                    builder = nil
                    active = false
                    paused = false
                    failedBuilder?.discardWorkout()
                    failedSession?.end()
                }
                throw error
            }
        } catch {
            status = error.localizedDescription
            reportWorkoutConflict(error)
        }
    }
    private func reportWorkoutConflict(_ error: Error) {
        let healthError = error as NSError
        guard healthError.domain == HKErrorDomain,
              healthError.code == HKError.Code.errorAnotherWorkoutSessionStarted.rawValue else { return }
        conflictMessage = "Another app started a workout and interrupted REP. Any logged sets remain on this Watch. Stop the other workout before starting REP again."
    }
    func recover() async {
        guard session == nil, !busy,
              let record = records.activeSession ?? self.record,
              record.endedAt == nil || [.recording, .saving, .recovery].contains(record.healthState) else { return }
        let id = record.id
        busy = true
        defer { busy = false }
        recordID = id
        do {
            let recovered = try await health.recoverActiveWorkoutSession()
            guard let recovered else {
                needsRecovery = false
                try records.setHealth(id, state: .recovery, error: "No active HealthKit session was recovered.")
                status = "Sets retained locally. Review Health and finalize this interrupted log."
                return
            }
            needsRecovery = false
            session = recovered
            builder = recovered.associatedWorkoutBuilder()
            recovered.delegate = self
            builder?.delegate = self
            collectionStarted = true
            active = recovered.state == .running || recovered.state == .paused
            paused = recovered.state == .paused
            if active {
                try records.setHealth(id, state: .recording)
                if record.endedAt != nil {
                    status = "Finishing the previously requested workout end…"
                    recovered.end()
                } else { status = "Recovered workout · local sets retained" }
            } else {
                status = "Recovered session is no longer recording. Check Apple Health."
                try records.setHealth(id, state: .recovery, error: status)
            }
        } catch {
            status = "Recovery unavailable: \(error.localizedDescription). Local sets retained."
            try? records.setHealth(id, state: .recovery, error: status)
        }
    }
    func duration(at date: Date) -> TimeInterval { builder?.elapsedTime(at: date) ?? record?.elapsed ?? elapsed }
    func togglePause() {
        guard active, !busy else { return }
        if paused { session?.resume() } else { session?.pause() }
    }
    func end(completed: Bool, advanceFromDay: Int?) {
        guard !busy, let id = recordID, record?.endedAt == nil else { return }
        do {
            // This local commit must succeed before ending the Health session.
            try records.finalizeLocal(id, completed: completed, advanceFromDay: advanceFromDay)
            if let session, active {
                busy = true
                status = "Ending workout…"
                session.end()
            } else {
                status = "Local log finalized. Health save remains unverified."
                active = false
            }
        } catch { records.errorMessage = error.localizedDescription }
    }
    private func finish(at date: Date) async {
        guard let builder, let id = recordID, !finalizing else { return }
        finalizing = true
        active = false
        busy = true
        defer { busy = false }
        do {
            if records.session(id)?.endedAt == nil {
                // A competing workout/system interruption does not count as completion.
                try records.finalizeLocal(id, completed: false, advanceFromDay: nil, date: date)
            }
            try records.setHealth(id, state: .saving, elapsed: builder.elapsedTime, energy: calories)
            try await builder.endCollection(at: date)
            guard let saved = try await builder.finishWorkout() else { throw TrainingError.invalidState }
            try records.setHealth(id, state: .saved, uuid: saved.uuid, elapsed: saved.duration,
                                  energy: saved.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()))
            status = "Saved to Apple Health · local sets retained"
            session = nil
            self.builder = nil
            finalizing = false
            collectionStarted = false
            paused = false
            refreshActivity()
        } catch {
            status = "Health save needs review: \(error.localizedDescription). Local log retained."
            WKInterfaceDevice.current().play(.failure)
            try? records.setHealth(id, state: .recovery, error: status)
            // Never retry finishWorkout blindly after an ambiguous response.
        }
    }
    func reconcile(_ record: StrengthSession) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [record.id.uuidString])
        do {
            let matches: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 2, sortDescriptors: nil) { _, samples, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: (samples as? [HKWorkout]) ?? []) }
                }
                health.execute(query)
            }
            if matches.count == 1, let workout = matches.first {
                try records.setHealth(record.id, state: .saved, uuid: workout.uuid, elapsed: workout.duration,
                                      energy: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()))
                // The saved workout proves finalization; release any stale in-memory handles.
                if record.id == recordID && !active { session = nil; builder = nil; finalizing = false; needsRecovery = false }
                status = "Existing Apple Health workout linked; no new workout created."
            } else {
                let message = matches.isEmpty ? "No readable matching workout. Permission may be limited or the record may be absent. No replacement was created." : "Multiple matching workouts found. Review Apple Health; no new workout created."
                try records.setHealth(record.id, state: matches.isEmpty ? .notFound : .recovery, error: message)
                status = message
            }
        } catch { status = error.localizedDescription }
    }
    func releaseEndedSession() {
        guard !busy, !active, record?.endedAt != nil, session == nil || session?.state == .ended else { return }
        // Release only an ended session. This never recreates or retries the old workout.
        session = nil
        builder = nil
        finalizing = false
        collectionStarted = false
        status = "Ready. Previous local log retained; unresolved Health status is unchanged."
    }
    /// Keep old readings from looking live when the sensor stops delivering data.
    func liveHeartRate(at date: Date) -> Double? {
        guard active, !paused, let heartRate, heartRate.isFinite, heartRate > 0,
              let measuredAt = heartRateMeasuredAt,
              date.timeIntervalSince(measuredAt) <= 30 else { return nil }
        return heartRate
    }
    func refreshActivity() {
        guard HKHealthStore.isHealthDataAvailable(), activityQuery == nil else { return }
        let calendar = Calendar.current
        var components = calendar.dateComponents([.era, .year, .month, .day], from: .now)
        components.calendar = calendar
        let query = HKActivitySummaryQuery(predicate: HKQuery.predicateForActivitySummary(with: components)) { _, summaries, error in
            Task { @MainActor in
                self.activityQuery = nil
                self.activitySummary = summaries?.first
                self.activityStatus = error?.localizedDescription ?? (summaries?.isEmpty == false ? "Apple Activity · latest available summary" : "Activity unavailable or access limited")
            }
        }
        activityQuery = query
        health.execute(query)
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            // Delegate tasks can run after a newer transition. Read current state
            // so an older prepared callback cannot briefly expose recovery.
            let currentState = workoutSession.state
            self.paused = currentState == .paused
            self.active = currentState == .running || currentState == .paused
            if (self.collectionStarted && self.active) || currentState == .ended {
                self.isStarting = false
            }
            // Acknowledge confirmed HealthKit transitions, not control taps.
            // Initial start is acknowledged only after collection and local persistence succeed.
            if toState != fromState {
                if toState == .paused || toState == .ended {
                    WKInterfaceDevice.current().play(.stop)
                } else if toState == .running && fromState == .paused {
                    WKInterfaceDevice.current().play(.start)
                }
            }
            if toState == .ended { await self.finish(at: date) }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            self.isStarting = false
            self.status = "Workout interrupted: \(error.localizedDescription). Local sets retained."
            self.reportWorkoutConflict(error)
            WKInterfaceDevice.current().play(.failure)
            self.active = false
            self.busy = false
            if let id = self.recordID { try? self.records.setHealth(id, state: .recovery, error: self.status) }
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartStatistics = workoutBuilder.statistics(for: HKQuantityType(.heartRate))
        let heart = heartStatistics?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let measuredAt = heartStatistics?.mostRecentQuantityDateInterval()?.end
        let energy = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let elapsed = workoutBuilder.elapsedTime
        Task { @MainActor in
            guard self.builder === workoutBuilder else { return }
            self.heartRate = heart
            self.heartRateMeasuredAt = measuredAt
            self.calories = energy
            self.elapsed = elapsed
        }
    }
}
