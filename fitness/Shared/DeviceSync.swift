import Foundation
import Combine
import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif

private nonisolated final class PendingDeliveryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func begin() { lock.lock(); count += 1; lock.unlock() }
    func end() { lock.lock(); count -= 1; lock.unlock() }
    var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return count == 0 }
}

@MainActor
final class DeviceSync: NSObject, ObservableObject {
    @Published var status = "Waiting for device connection"
    private let store: TrainingStore
    private var attempted = Set<UUID>()
    private var flushing = false
    private nonisolated let pendingReceives = PendingDeliveryCounter()
    #if os(watchOS)
    private var backgroundTasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    private var contentObservation: NSKeyValueObservation?
    private var activationObservation: NSKeyValueObservation?
    #endif

    init(store: TrainingStore) {
        self.store = store
        super.init()
        guard !store.isPreview else { status = "Sample data · sync off"; return }
        store.didCommit = { [weak self] in self?.flush() }
        guard WCSession.isSupported() else { status = "Watch connectivity unavailable"; return }
        WCSession.default.delegate = self
        #if os(watchOS)
        contentObservation = WCSession.default.observe(\.hasContentPending, options: [.new]) { [weak self] _, _ in
            guard let owner = self else { return }
            Task { @MainActor in owner.completeBackgroundIfReady() }
        }
        activationObservation = WCSession.default.observe(\.activationState, options: [.new]) { [weak self] _, _ in
            guard let owner = self else { return }
            Task { @MainActor in owner.completeBackgroundIfReady() }
        }
        #endif
        WCSession.default.activate()
    }
    #if os(watchOS)
    func beginBackgroundDelivery(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        backgroundTasks.append(task)
        completeBackgroundIfReady()
    }
    #endif
    private func completeBackgroundIfReady() {
        #if os(watchOS)
        guard WCSession.default.activationState == .activated, !WCSession.default.hasContentPending, pendingReceives.isEmpty else { return }
        let completed = backgroundTasks
        backgroundTasks.removeAll()
        for task in completed { task.setTaskCompletedWithSnapshot(false) }
        #endif
    }
    func retry() {
        guard !store.isPreview else { return }
        attempted.removeAll()
        store.perform { try store.resendSnapshots() }
        flush()
    }
    func flush() {
        guard !flushing, WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        flushing = true
        defer { flushing = false }
        let existing = Set(WCSession.default.outstandingUserInfoTransfers.compactMap { transfer in
            (transfer.userInfo["eventID"] as? String).flatMap(UUID.init(uuidString:))
        })
        let batch = SyncSchedule.nextBatch(outbox: store.archive.outbox, attempted: attempted, outstanding: existing)
        for event in batch {
            do {
                let data = try JSONEncoder().encode(event)
                // Queued background transfers do not depend on isReachable.
                WCSession.default.transferUserInfo(["eventID": event.id.uuidString, "payload": data])
                attempted.insert(event.id)
            } catch { status = "Transfer encoding failed: \(error.localizedDescription)" }
        }
        status = store.archive.outbox.contains(where: \.requiresReceipt) ? "Queued · waiting for device receipt" : "No unconfirmed transfers"
    }
}

extension DeviceSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error { self.status = error.localizedDescription }
            else { self.retry() }
            self.completeBackgroundIfReady()
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["payload"] as? Data else { return }
        pendingReceives.begin()
        Task { @MainActor in
            defer { self.pendingReceives.end(); self.completeBackgroundIfReady() }
            do {
                let event = try JSONDecoder().decode(SyncEvent.self, from: data)
                try self.store.receive(event)
                self.status = "Device records received"
                self.flush()
            } catch {
                self.status = "Transfer not acknowledged: \(error.localizedDescription)"
                self.store.errorMessage = self.status
            }
        }
    }
    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard let text = userInfoTransfer.userInfo["eventID"] as? String, let id = UUID(uuidString: text) else { return }
        Task { @MainActor in
            if let error {
                self.status = "Transfer pending: \(error.localizedDescription). Retry when the devices reconnect."
                // Retain the durable event; avoid a hot retry loop on every local commit.
                self.attempted.insert(id)
            } else {
                self.store.perform { try self.store.transferFinished(id) }
                self.flush()
            }
        }
    }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
