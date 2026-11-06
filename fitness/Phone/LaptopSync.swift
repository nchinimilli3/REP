import SwiftUI
import Combine
import Network
import UIKit
import CryptoKit
import Security

@MainActor
final class LaptopSync: ObservableObject {
    @Published var status = "Laptop not paired"
    @Published private(set) var lastSaved: Date?
    private let store: TrainingStore
    private var changes: AnyCancellable?
    private var timer: Timer?
    private var browser: NWBrowser?
    private var wire: LaptopWire?
    private var timeout: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var generation = UUID()
    private var acknowledged: String?
    private let defaults = UserDefaults.standard
    var paired: Bool { (try? LaptopPairingKey.read()) != nil }
    init(store: TrainingStore) {
        self.store = store
        lastSaved = defaults.object(forKey: "laptop.savedAt") as? Date
        if paired { status = "Waiting for laptop" }
        changes = store.$archive.dropFirst().debounce(for: .seconds(1), scheduler: DispatchQueue.main).sink { [weak self] _ in
            self?.retry()
        }
    }
    func pair(_ text: String) throws {
        _ = try LaptopProtocol.key(text)
        stop()
        try LaptopPairingKey.save(text.trimmingCharacters(in: .whitespacesAndNewlines))
        // Keep the sender and monotonic sequence when reconnecting to an existing laptop.
        acknowledged = nil
        retry()
    }
    func unpair() {
        stop()
        do { try LaptopPairingKey.remove() } catch { status = error.localizedDescription; return }
        acknowledged = nil; lastSaved = nil; defaults.removeObject(forKey: "laptop.savedAt")
        status = "Laptop not paired"
    }
    func setActive(_ active: Bool) {
        guard !store.isPreview else { return }
        timer?.invalidate(); timer = nil
        if active {
            retry()
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.retry() }
            }
        }
    }
    func retry() {
        guard !store.isPreview, paired, store.storageReady, browser == nil, wire == nil else { return }
        do {
            let fingerprint = try LaptopProtocol.fingerprint(store.archive)
            guard fingerprint != acknowledged else { return }
            let key = try LaptopProtocol.key(try LaptopPairingKey.read() ?? "")
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "REP laptop backup") { [weak self] in
                Task { @MainActor in self?.finish("Laptop backup pending; retrying when REP. can run") }
            }
            let attempt = UUID(); generation = attempt
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .wifi
            let browse = NWBrowser(for: .bonjour(type: LaptopProtocol.service, domain: nil), using: parameters)
            browser = browse
            status = "Looking for paired laptop on Wi-Fi"
            browse.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in
                guard let self, self.generation == attempt, self.wire == nil else { return }
                if let result = results.first(where: {
                    if case .service(let name, _, _, _) = $0.endpoint { return name == LaptopProtocol.serviceName(key) }; return false
                }) { self.connect(result.endpoint, key: key, attempt: attempt) }
                }
            }
            browse.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                if case .failed = state, self?.generation == attempt { self?.finish("Laptop discovery unavailable; check Local Network permission") }
                }
            }
            browse.start(queue: .main)
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, self?.generation == attempt else { return }
                self?.finish("Laptop backup pending; laptop must be awake on the same network")
            }
        } catch { finish("Laptop backup pending: \(error.localizedDescription)") }
    }
    private func connect(_ endpoint: NWEndpoint, key: SymmetricKey, attempt: UUID) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let channel = LaptopWire(connection); wire = channel
        browser?.cancel(); browser = nil
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
            guard let self, self.generation == attempt else { return }
            switch state {
            case .ready:
                do {
                    let sender = self.defaults.string(forKey: "laptop.sender").flatMap(UUID.init(uuidString:)) ?? UUID()
                    self.defaults.set(sender.uuidString, forKey: "laptop.sender")
                    let previous = self.defaults.integer(forKey: "laptop.sequence")
                    guard previous < Int.max else { throw LaptopError.message("Pairing sequence exhausted.") }
                    let sequence = previous + 1
                    self.defaults.set(sequence, forKey: "laptop.sequence")
                    let archive = self.store.archive
                    let fingerprint = try LaptopProtocol.fingerprint(archive)
                    let payload = try LaptopProtocol.seal(LaptopSnapshot(sender: sender, sequence: sequence, archive: archive), key: key)
                    self.status = "Saving records on laptop"
                    channel.send(payload) { error in
                        guard self.generation == attempt else { return }
                        if let error { self.finish("Laptop backup pending: \(error.localizedDescription)"); return }
                        channel.receive { result in
                            guard self.generation == attempt else { return }
                            do {
                                let receipt = try LaptopProtocol.open(LaptopReceipt.self, data: result.get(), key: key)
                                guard receipt.sender == sender, receipt.sequence == sequence, receipt.fingerprint == fingerprint else {
                                    throw LaptopError.message("Laptop receipt did not match these records.")
                                }
                                self.acknowledged = fingerprint
                                self.lastSaved = .now; self.defaults.set(Date.now, forKey: "laptop.savedAt")
                                self.finish("Records saved on laptop")
                                // A Watch update may have arrived while the snapshot was in flight.
                                self.retry()
                            } catch { self.finish("Laptop backup pending: \(error.localizedDescription)") }
                        }
                    }
                } catch { self.finish("Laptop backup pending: \(error.localizedDescription)") }
            case .failed(let error): self.finish("Laptop backup pending: \(error.localizedDescription)")
            default: break
            }
            }
        }
        connection.start(queue: .main)
    }
    private func finish(_ message: String) { stop(); status = message }
    private func stop() {
        generation = UUID()
        timeout?.cancel(); timeout = nil
        browser?.cancel(); browser = nil
        wire?.connection.cancel(); wire = nil
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
}

struct LaptopSyncView: View {
    @ObservedObject var laptop: LaptopSync
    @State private var pairingKey = ""
    @State private var error: String?
    var body: some View {
        Form {
            Section("Automatic local backup") {
                Text("Your iPhone discovers your paired Mac on the same Wi-Fi. Records stay on your devices.")
                Text(laptop.status).foregroundStyle(.secondary)
                if let saved = laptop.lastSaved { LabeledContent("Last laptop receipt", value: saved.formatted()) }
                Text("The Mac receiver must be running and awake. iOS controls background timing; opening REP. retries pending records automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(laptop.paired ? "Replace pairing" : "Pair once") {
                Text("Open REP. Laptop on your Mac and copy its pairing key here.")
                SecureField("Laptop pairing key", text: $pairingKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Pair Laptop") {
                    do { try laptop.pair(pairingKey); pairingKey = ""; error = nil }
                    catch { self.error = error.localizedDescription }
                }.disabled(pairingKey.isEmpty)
                if let error { Text(error).foregroundStyle(.red) }
            }
            if laptop.paired {
                Section {
                    Button("Retry Now") { laptop.retry() }
                    Button("Disconnect Laptop", role: .destructive) { laptop.unpair() }
                }
            }
        }.navigationTitle("Laptop Sync")
    }
}

/// Pairing secret stays in this installation's Keychain, available for background delivery after unlock.
private enum LaptopPairingKey {
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "nehachinimilli.fitness.laptop",
         kSecAttrAccount as String: "pairing"]
    }
    static func read() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let text = String(data: data, encoding: .utf8) else {
            throw LaptopError.message("Laptop pairing key is unavailable. Unlock iPhone and try again.")
        }
        return text
    }
    static func save(_ text: String) throws {
        let data = Data(text.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw LaptopError.message("Could not save laptop pairing key.") }
        let added = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        guard added == errSecSuccess else { throw LaptopError.message("Could not save laptop pairing key.") }
    }
    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw LaptopError.message("Could not remove laptop pairing key.") }
    }
}
