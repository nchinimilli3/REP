import SwiftUI
import Charts
import Network
import CryptoKit
import AppKit
import OSLog

@MainActor
final class LaptopReceiver: ObservableObject {
    private let logger = Logger(subsystem: "local.rep.laptop", category: "sync")
    @Published var status = "Starting local receiver"
    @Published var archive = TrainingArchive()
    @Published var receivedAt: Date?
    @Published var failure: String?
    private(set) var pairingText = ""
    private var repository: LaptopRepository?
    private var listener: NWListener?
    private var clients: [UUID: LaptopWire] = [:]
    let directory: URL
    init() {
        directory = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "REPDataDirectory") as? String
                        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/REP Progress").path,
                        isDirectory: true)
        do {
            let repository = try LaptopRepository(directory: directory)
            self.repository = repository
            archive = repository.ledger?.archive ?? TrainingArchive()
            receivedAt = repository.ledger?.receivedAt
            let keyURL = directory.appendingPathComponent("pairing-key")
            let key: SymmetricKey
            if FileManager.default.fileExists(atPath: keyURL.path) {
                pairingText = try String(contentsOf: keyURL, encoding: .utf8)
                key = try LaptopProtocol.key(pairingText)
            } else {
                key = SymmetricKey(size: .bits256)
                pairingText = key.withUnsafeBytes { Data($0).base64EncodedString() }
                try Data(pairingText.utf8).write(to: keyURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
            }
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: LaptopProtocol.serviceName(key), type: LaptopProtocol.service)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                switch state {
                case .ready: self?.status = "Ready · waiting for iPhone on local network"
                case .failed(let error): self?.status = "Receiver stopped: \(error.localizedDescription)"
                default: break
                }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.receive(connection, key: key) }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch { failure = error.localizedDescription; status = "Receiver unavailable; existing files preserved" }
    }
    private func receive(_ connection: NWConnection, key: SymmetricKey) {
        guard clients.count < 4 else { connection.cancel(); return }
        let id = UUID(), wire = LaptopWire(connection)
        clients[id] = wire
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in self?.close(id) }
        wire.receive { [weak self] result in
            guard let self, self.clients[id] != nil else { return }
            do {
                let snapshot = try LaptopProtocol.open(LaptopSnapshot.self, data: result.get(), key: key)
                guard let repository = self.repository else { throw TrainingError.invalidArchive }
                let receipt = try repository.accept(snapshot)
                self.archive = repository.ledger?.archive ?? self.archive
                self.receivedAt = repository.ledger?.receivedAt
                self.status = "Saved workout data locally"
                self.failure = nil
                wire.send(try LaptopProtocol.seal(receipt, key: key)) { [weak self] _ in self?.close(id) }
            } catch {
                // A malformed or unauthenticated peer never receives a success receipt.
                let reason = error.localizedDescription
                self.failure = "Transfer rejected: \(reason) Existing saved records are preserved."
                self.logger.error("Transfer rejected: \(reason, privacy: .public)")
                self.close(id)
            }
        }
    }
    private func close(_ id: UUID) { clients.removeValue(forKey: id)?.connection.cancel() }
    func copyKey() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(pairingText, forType: .string) }
}

private enum DesktopSection: String, CaseIterable, Identifiable {
    case progress = "Progress", history = "Workout History", connection = "Connection"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .progress: return "chart.xyaxis.line"
        case .history: return "clock.arrow.circlepath"
        case .connection: return "iphone.and.arrow.forward"
        }
    }
}

struct LaptopProgress: View {
    @ObservedObject var receiver: LaptopReceiver
    @State private var section: DesktopSection? = .progress
    @State private var exerciseID = ""
    @State private var basis = ""
    @State private var search = ""
    @State private var copiedKey = false
    private var completed: [StrengthSession] { receiver.archive.sessions.filter(\.completed) }
    private var exercises: [Exercise] {
        var values: [Exercise] = []
        for exercise in receiver.archive.sessions.flatMap(\.routine) where !values.contains(where: { $0.id == exercise.id }) { values.append(exercise) }
        return values.sorted { $0.name < $1.name }
    }
    private var selected: String { exercises.contains(where: { $0.id == exerciseID }) ? exerciseID : exercises.first?.id ?? "" }
    private var points: [ProgressPoint] { TrainingProgress.points(exerciseID: selected, sessions: receiver.archive.sessions) }
    private var bases: [String] { Array(Set(points.map(\.comparisonKey))).sorted() }
    private var selectedBasis: String { bases.contains(basis) ? basis : bases.first ?? "" }
    private var shown: [ProgressPoint] { points.filter { $0.comparisonKey == selectedBasis } }
    private var history: [StrengthSession] {
        receiver.archive.sessions.filter { session in
            search.isEmpty || session.title.localizedCaseInsensitiveContains(search)
                || session.effectiveSets.contains { $0.original.exerciseName.localizedCaseInsensitiveContains(search) }
        }.sorted { $0.startedAt > $1.startedAt }
    }
    private func routineColor(_ split: Split) -> Color {
        split.identityColor
    }
    private var chartColor: Color {
        exercises.first(where: { $0.id == selected })?.split.map(routineColor) ?? REPStyle.accent
    }
    private func basisTitle(_ key: String) -> String {
        let load = receiver.archive.sessions.flatMap(\.effectiveSets).first {
            $0.original.exerciseID == selected && $0.load.comparisonKey == key
        }?.load
        guard let load else { return "Recorded load" }
        if load.kind == .smith {
            return load.smithBarPounds.map { "Plates per side · \($0.repNumber) lb configured bar" } ?? "Plates per side · bar excluded"
        }
        return load.kind.title
    }
    var body: some View {
        NavigationSplitView {
            List(DesktopSection.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationTitle("REP.")
            .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 240)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Local to your Mac", systemImage: "lock.shield")
                    if let received = receiver.receivedAt {
                        Text("Received \(received.formatted(date: .abbreviated, time: .shortened))")
                    } else { Text("Waiting for your first transfer") }
                }.font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
            }
        } detail: {
            Group {
                switch section ?? .progress {
                case .progress: dashboard
                case .history: workoutHistory
                case .connection: connection
                }
            }
            .navigationTitle((section ?? .progress).rawValue)
            .toolbar {
                ToolbarItem {
                    Button { NSWorkspace.shared.open(receiver.directory) } label: {
                        Label("Open Data Folder", systemImage: "folder")
                    }.help("Open locally received training records and CSV")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let failure = receiver.failure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.08))
                }
            }
        }
        .frame(minWidth: 820, minHeight: 620)
        .tint(REPStyle.accent).preferredColorScheme(.dark)
    }
    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: REPStyle.page) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your strength, over time.").font(.largeTitle.bold())
                    Text("Completed workouts received on this Mac").foregroundStyle(.secondary)
                }
                HStack(spacing: REPStyle.row) {
                    DesktopStat(value: completed.count, title: "Workouts", symbol: "figure.strengthtraining.traditional", color: .green)
                    DesktopStat(value: completed.reduce(0) { $0 + $1.effectiveSets.count }, title: "Working sets", symbol: "square.stack.3d.up.fill", color: .cyan)
                    DesktopStat(value: completed.flatMap(\.effectiveSets).reduce(0) { $0 + $1.reps }, title: "Repetitions", symbol: "repeat", color: .pink)
                }
                if receiver.archive.sessions.isEmpty {
                    emptyState(title: "Your progress starts on Watch", symbol: "applewatch", message: "Pair your iPhone to bring your workout history here automatically.")
                    Button("Set Up Connection", systemImage: "iphone") { section = .connection }
                        .buttonStyle(.borderedProminent)
                } else {
                    routineOverview
                    loadChart
                }
            }.padding(REPStyle.page).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
    private var routineOverview: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: REPStyle.row) {
                Text("Your workout mix").font(.title3.bold())
                if completed.isEmpty {
                    Text("Finish a workout on Watch to see your routine mix.").foregroundStyle(.secondary)
                } else {
                    Chart(Split.workoutTypes) { split in
                        BarMark(x: .value("Completed workouts", completed.filter { Split.at(day: $0.day) == split }.count),
                                y: .value("Routine", split.title))
                            .foregroundStyle(routineColor(split))
                            .annotation(position: .trailing) {
                                Text("\(completed.filter { Split.at(day: $0.day) == split }.count)").font(.caption.monospacedDigit())
                            }
                    }.chartXAxis { AxisMarks(values: .stride(by: 1)) }
                        .frame(height: 140)
                        .accessibilityLabel("Completed workouts by routine")
                }
            }.padding(REPStyle.row).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var loadChart: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: REPStyle.section) {
                Text("Exercise progress").font(.title3.bold())
                Picker("Exercise", selection: Binding(get: { selected }, set: { exerciseID = $0; basis = "" })) {
                    ForEach(exercises) { Text($0.name).tag($0.id) }
                }
                if bases.count > 1 {
                    Picker("Compare", selection: Binding(get: { selectedBasis }, set: { basis = $0 })) {
                        ForEach(bases, id: \.self) { Text(basisTitle($0)).tag($0) }
                    }
                }
                if shown.isEmpty {
                    emptyState(title: "No comparable weighted sets yet", symbol: "chart.xyaxis.line", message: "Bodyweight and unspecified loads still appear in Workout History.")
                } else {
                    Chart(shown) { point in
                        PointMark(x: .value("Date", point.date), y: .value("Load (lb)", point.load))
                            .foregroundStyle(chartColor).symbolSize(45)
                    }.chartYAxisLabel("lb · \(basisTitle(selectedBasis))").frame(height: 240)
                        .accessibilityLabel("Recorded working loads for \(exercises.first(where: { $0.id == selected })?.name ?? "exercise")")
                    Label(selectedBasis.hasPrefix("assistance:") ? "Less assistance means more unassisted demand." : selectedBasis.hasPrefix("smith:") ? "Smith values show plates per side." : "Compare the same exercise and equipment.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("One dot per completed set. Starting estimates are excluded.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(REPStyle.row).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var workoutHistory: some View {
        List {
            if history.isEmpty {
                emptyState(title: search.isEmpty ? "No received workouts yet" : "No matching workouts", symbol: "clock.arrow.circlepath", message: search.isEmpty ? "Your received logs will appear here, including unfinished workouts." : "Try a workout type or exercise name.")
            }
            ForEach(history) { session in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: REPStyle.compact) {
                        Label("Stored on this Mac", systemImage: "desktopcomputer")
                        Text(session.healthState.title).foregroundStyle(.secondary)
                        HStack(spacing: 20) {
                            if let elapsed = session.elapsed {
                                Label(Duration.seconds(elapsed).formatted(.time(pattern: .hourMinuteSecond)), systemImage: "timer")
                                    .foregroundStyle(.yellow)
                            }
                            if let energy = session.activeEnergy {
                                Label("\(Int(energy)) active cal", systemImage: "flame.fill")
                                    .foregroundStyle(.pink)
                            }
                        }.font(.headline.monospacedDigit())
                        ForEach(session.effectiveSets) { set in
                            HStack(alignment: .top) {
                                Text(set.original.exerciseName).frame(maxWidth: .infinity, alignment: .leading)
                                Text("Set \(set.original.ordinal) · \(set.reps) reps").monospacedDigit()
                                Text(set.load.label).foregroundStyle(.secondary).frame(minWidth: 140, alignment: .trailing)
                            }.padding(.vertical, REPStyle.detail)
                        }
                        if session.effectiveSets.isEmpty { Text("No completed sets in this log.").foregroundStyle(.secondary) }
                    }.padding(.vertical, REPStyle.row).textSelection(.enabled)
                } label: {
                    HStack(spacing: REPStyle.row) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.title2).foregroundStyle(routineColor(Split.at(day: session.day)))
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: REPStyle.detail) {
                            Text(session.title).font(.headline)
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: REPStyle.detail) {
                            Text("\(session.effectiveSets.count) sets · \(session.effectiveSets.reduce(0) { $0 + $1.reps }) reps").monospacedDigit()
                            Text(session.completed ? "Completed" : session.endedAt == nil ? "Unfinished" : "Ended early")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, REPStyle.compact)
                }
            }
        }.listStyle(.inset)
            .searchable(text: $search, prompt: "Workout or exercise")
    }
    private var connection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: REPStyle.page) {
                Image(systemName: "iphone.radiowaves.left.and.right").font(.system(size: 52)).foregroundStyle(REPStyle.accent).accessibilityHidden(true)
                Text("Watch → iPhone → Mac").font(.largeTitle.bold())
                Text("Local network sync").foregroundStyle(.secondary)
                GroupBox {
                    VStack(alignment: .leading, spacing: REPStyle.section) {
                        Label(receiver.status, systemImage: "network")
                        if let received = receiver.receivedAt {
                            LabeledContent("Last received", value: received.formatted(date: .abbreviated, time: .shortened))
                        }
                        Divider()
                        connectionStep("1", title: "Copy your pairing key", detail: "Keep this key private. It grants access to this receiver.")
                        Button(copiedKey ? "Pairing Key Copied" : "Copy Pairing Key", systemImage: copiedKey ? "checkmark" : "doc.on.doc") {
                            receiver.copyKey(); copiedKey = true
                        }.buttonStyle(.borderedProminent).disabled(receiver.pairingText.isEmpty)
                        connectionStep("2", title: "Pair in REP. on iPhone", detail: "Today → ⋯ → Laptop Sync. Paste the key and allow Local Network access.")
                        connectionStep("3", title: "Sync your workouts", detail: "Same Wi-Fi. REP. open on both devices.")
                    }.padding(REPStyle.row).frame(maxWidth: .infinity, alignment: .leading)
                }
                Label("Local files update after each accepted transfer. Background delivery depends on iOS.", systemImage: "lock.shield")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Open Data Folder for training.json and sets.csv.").font(.caption).foregroundStyle(.secondary)
            }.padding(REPStyle.page).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
    private func connectionStep(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: REPStyle.row) {
            Text(number).font(.headline).foregroundStyle(REPStyle.accent)
                .frame(width: 28, height: 28).background(REPStyle.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: REPStyle.detail) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
    private func emptyState(title: String, symbol: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.title3.bold())
            Text(message).foregroundStyle(.secondary)
        }.padding(.vertical, REPStyle.section).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DesktopStat: View {
    let value: Int
    let title: String
    let symbol: String
    let color: Color
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: REPStyle.compact) {
                Image(systemName: symbol).font(.title3).foregroundStyle(color).accessibilityHidden(true)
                Text(value.formatted()).font(.system(.largeTitle, design: .rounded).bold().monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(title).font(.callout).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(value) \(title)")
    }
}

@main
struct REPDesktop: App {
    @StateObject private var receiver = LaptopReceiver()
    var body: some Scene {
        WindowGroup { LaptopProgress(receiver: receiver) }
    }
}
