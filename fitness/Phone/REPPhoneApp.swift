import SwiftUI

@main
struct REPPhoneApp: App {
    @StateObject private var records: TrainingStore
    @StateObject private var sync: DeviceSync
    @StateObject private var laptop: LaptopSync
    @StateObject private var health = HealthHistory()
    @Environment(\.scenePhase) private var scenePhase
    init() {
        #if targetEnvironment(simulator)
        if let request = ProcessInfo.processInfo.environment["REP_PHONE_DEMO"] {
            UserDefaults.standard.set(request == "1", forKey: "rep.simulator.demoEnabled")
        }
        let demo = UserDefaults.standard.bool(forKey: "rep.simulator.demoEnabled")
        #else
        let demo = false
        #endif
        let demoURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("REP-Demo/training.json")
        let store = TrainingStore(fileURL: demo ? demoURL : nil, isWatch: false, isPreview: demo)
        store.perform {
            try store.applyConfirmedAbsPreference()
            try store.applyConfirmedRoutinePreferences()
        }
        #if targetEnvironment(simulator)
        if demo { store.perform { try PhoneDemoData.populate(store) } }
        #endif
        _records = StateObject(wrappedValue: store)
        _sync = StateObject(wrappedValue: DeviceSync(store: store))
        _laptop = StateObject(wrappedValue: LaptopSync(store: store))
    }
    var body: some Scene {
        WindowGroup {
            PhoneRootView(records: records, sync: sync, health: health, laptop: laptop)
                .preferredColorScheme(.dark)
                .onAppear { laptop.setActive(true) }
                .task(id: scenePhase) {
                    guard scenePhase == .active, !records.isPreview else { return }
                    await health.refresh()
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(5)) }
                        catch { return }
                        await health.refreshActivity()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    laptop.setActive(phase == .active)
                    if phase == .active { sync.retry() }
                }
        }
    }
}
