import SwiftUI
import Combine
import WatchKit

@MainActor
final class WatchServices: ObservableObject {
    static let shared = WatchServices()
    let records: TrainingStore
    let workout: WorkoutManager
    let sync: DeviceSync
    private init() {
        let store = TrainingStore(isWatch: true)
        records = store
        workout = WorkoutManager(records: store)
        sync = DeviceSync(store: store)
    }
}

final class WorkoutRecoveryDelegate: NSObject, WKApplicationDelegate {
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        Task { @MainActor in
            for task in backgroundTasks {
                if let transfer = task as? WKWatchConnectivityRefreshBackgroundTask {
                    WatchServices.shared.sync.beginBackgroundDelivery(transfer)
                } else if let snapshot = task as? WKSnapshotRefreshBackgroundTask {
                    snapshot.setTaskCompleted(restoredDefaultState: true, estimatedSnapshotExpiration: .distantFuture, userInfo: nil)
                } else { task.setTaskCompletedWithSnapshot(false) }
            }
        }
    }
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in await WatchServices.shared.workout.recover() }
    }
}

@main
struct fitness_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WorkoutRecoveryDelegate.self) var delegate
    @StateObject private var services = WatchServices.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView(records: services.records, workout: services.workout, sync: services.sync)
                .preferredColorScheme(.dark)
                .task { if !ContentView.isVisualPreview { await services.workout.recover() } }
                .task(id: scenePhase) {
                    guard scenePhase == .active, !ContentView.isVisualPreview else { return }
                    while !Task.isCancelled {
                        // Authorization is obtained by starting the workout, never by this timer.
                        if services.workout.active || services.workout.activitySummary != nil {
                            services.workout.refreshActivity()
                        }
                        do { try await Task.sleep(for: .seconds(5)) }
                        catch { return }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && !ContentView.isVisualPreview { services.sync.retry() }
                }
        }
    }
}
