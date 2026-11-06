import SwiftUI
import Charts
import HealthKit
import HealthKitUI
import UniformTypeIdentifiers

extension Split {
    var color: Color { identityColor }
}

struct PhoneRootView: View {
    @ObservedObject var records: TrainingStore
    @ObservedObject var sync: DeviceSync
    @ObservedObject var health: HealthHistory
    @ObservedObject var laptop: LaptopSync
    @State private var backup = BackupDocument(data: Data())
    @State private var exporting = false
    @State private var importing = false
    @State private var backupFilename = "REP-backup"
    @State private var showingLaptop = false
    @State private var selectedTab = 0
    @State private var progressPath: [String] = []
    @State private var previewConfigured = false
    @State private var selectedWorkoutID = Split.back.rawValue
    @State private var editingExercise: Exercise?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if records.storageReady { appTabs }
            else { NavigationStack { storageRecovery.toolbar { backupMenu } } }
        }
        .tint(REPStyle.accent)
        .alert("REP.", isPresented: Binding(get: { records.errorMessage != nil }, set: { if !$0 { records.errorMessage = nil } })) {
            Button("OK") { records.errorMessage = nil }
        } message: { Text(records.errorMessage ?? "") }
        .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: backupFilename) { result in
            if case .failure(let error) = result { records.errorMessage = error.localizedDescription }
        }
        .sheet(item: $editingExercise) { exercise in
            ExerciseEditor(records: records, exercise: exercise, adding: false,
                           planRevision: records.archive.plan.revision, routineID: exercise.id == "abs" ? nil : selectedWorkoutID)
        }
        .sheet(isPresented: $showingLaptop) { NavigationStack { LaptopSyncView(laptop: laptop) } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            records.perform {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                try records.restore(Data(contentsOf: url))
            }
        }
    }
    private var appTabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { today.toolbar { backupMenu } }
                .tabItem { Label("Today", systemImage: "sun.max") }.tag(0)
            NavigationStack(path: $progressPath) {
                ProgressViewScreen(records: records).toolbar { backupMenu }
                    .navigationDestination(for: String.self) { key in
                        if let exercise = records.archive.plan.exercises.first(where: { $0.id == key }) {
                            ExerciseProgressView(records: records, exercise: exercise)
                        }
                    }
            }.tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }.tag(1)
            NavigationStack { PlanView(records: records) }
                .tabItem { Label("Plan", systemImage: "list.bullet.clipboard") }.tag(2)
        }
        .onAppear {
            restoreWorkoutChoice()
            guard records.isPreview, !previewConfigured else { return }
            previewConfigured = true
            #if targetEnvironment(simulator)
            let screen = ProcessInfo.processInfo.environment["REP_PHONE_SCREEN"]
            if screen == "progress" || screen == "exercise" { selectedTab = 1 }
            if screen == "exercise" { progressPath = [ProcessInfo.processInfo.environment["REP_PHONE_EXERCISE"] ?? "pullup"] }
            if screen == "plan" { selectedTab = 2 }
            #endif
        }
    }
    private var choiceKey: String { records.isPreview ? "rep.phone.demo.workoutChoice" : "rep.phone.workoutChoice" }
    private var selectedRoutine: WorkoutRoutine? {
        records.archive.plan.availableRoutines.first { $0.id == selectedWorkoutID } ?? records.archive.plan.availableRoutines.first
    }
    private var workoutBinding: Binding<String> {
        Binding(get: { selectedRoutine?.id ?? "" }, set: { value in
            selectedWorkoutID = value
            UserDefaults.standard.set(value, forKey: choiceKey)
            UserDefaults.standard.set(Calendar.current.startOfDay(for: .now).timeIntervalSince1970,
                                      forKey: choiceKey + ".manualDay")
        })
    }
    private func restoreWorkoutChoice() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: choiceKey) ?? Split.back.rawValue
        let manualToday = defaults.double(forKey: choiceKey + ".manualDay") == Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        let suggested = TrainingProgress.suggestedWorkout(sessions: records.visibleSessions)?.rawValue
        let candidate = manualToday ? saved : suggested ?? saved
        selectedWorkoutID = records.archive.plan.availableRoutines.contains(where: { $0.id == candidate })
            ? candidate : records.archive.plan.availableRoutines.first?.id ?? ""
        defaults.set(selectedWorkoutID, forKey: choiceKey)
    }
    private var storageRecovery: some View {
        VStack(spacing: 20) {
            ContentUnavailableView("Local records need recovery", systemImage: "externaldrive.badge.exclamationmark", description: Text("Your existing file is preserved. Choose a REP. backup to validate and restore it. A copy of the unreadable original will be kept on this device."))
            Button("Restore a Backup", systemImage: "square.and.arrow.down") { importing = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }.padding().navigationTitle("REP.")
    }
    private var backupMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if records.isPreview {
                    Text("Sample data · no Health or device sync")
                } else {
                Button("Export Training Backup", systemImage: "square.and.arrow.up") {
                    records.perform {
                        backup = BackupDocument(data: try records.exportData())
                        backupFilename = "REP-backup-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))"
                        exporting = true
                    }
                }.disabled(!records.storageReady)
                if records.preservedArchiveURL != nil {
                    Button("Export Preserved Original", systemImage: "doc.badge.ellipsis") {
                        records.perform {
                            backup = BackupDocument(data: try records.exportPreservedArchive())
                            backupFilename = "REP-preserved-original"
                            exporting = true
                        }
                    }
                }
                Button("Restore / Merge Backup", systemImage: "square.and.arrow.down") { importing = true }
                Button("Restore iPhone History to Watch", systemImage: "applewatch") {
                    records.perform { try records.restoreWatchHistory() }
                }.disabled(!records.storageReady)
                Section(records.archive.syncIssues.last.map { "\(sync.status) · \($0)" } ?? sync.status) {
                    Button("Retry Device Sync", systemImage: "arrow.triangle.2.circlepath") { sync.retry() }.disabled(!records.storageReady)
                }
                Section(laptop.status) {
                    Button("Laptop Sync", systemImage: "laptopcomputer") { showingLaptop = true }
                }
                }
            } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Backup and sync")
        }
    }
    private var finishedToday: StrengthSession? {
        records.history.first { $0.completed && $0.endedAt.map { Calendar.current.isDateInToday($0) } == true }
    }
    private var receivedActive: StrengthSession? { records.history.first { $0.endedAt == nil } }
    private var today: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if records.isPreview { SampleDataBanner() }
                if let active = receivedActive {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Workout on Watch", systemImage: "applewatch").font(.subheadline.weight(.semibold)).foregroundStyle(active.identityColor)
                        NavigationLink { SessionDetail(records: records, id: active.id) } label: { VisualWorkoutRow(session: active) }.buttonStyle(.plain)
                        Text("Last received: \(active.healthState.title). \(active.effectiveSets.count) sets recorded. Live status may be delayed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.phoneCard()
                } else if let finished = finishedToday {
                    recap(finished, heading: "Completed today")
                }
                if let selected = selectedRoutine {
                    VStack(alignment: .leading, spacing: 12) {
                        if finishedToday != nil { Text("Choose another workout").font(.headline) }
                        Menu {
                            Picker("Workout", selection: workoutBinding) {
                                ForEach(records.archive.plan.availableRoutines) { Text($0.name).tag($0.id) }
                            }
                        } label: {
                            HStack {
                                RoutineLibraryRow(routine: selected)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("Choose workout. \(selected.name) selected")
                        Label("Start on your Apple Watch", systemImage: "applewatch")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.phoneCard()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Planned sets & loads").font(.headline)
                        VStack(spacing: 0) {
                            ForEach(Array(selected.exercises.enumerated()), id: \.element.id) { index, exercise in
                                if index > 0 { Divider() }
                                Button { editingExercise = exercise } label: {
                                    PhoneRoutineRow(records: records, exercise: exercise)
                                }.buttonStyle(.plain)
                            }
                        }
                    }.phoneCard()
                    if let abs = records.archive.plan.exercises.first(where: { $0.id == "abs" }) {
                        Button { editingExercise = abs } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "figure.core.training").foregroundStyle(REPStyle.abs)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Optional Abs").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                    Text("\(abs.sets) × \(abs.reps) · \(abs.withConfirmedDefaults.load.label)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.frame(minHeight: 44)
                        }.buttonStyle(.plain).phoneCard()
                    }
                } else {
                    Button("Create a routine in Plan", systemImage: "plus") { selectedTab = 2 }
                        .buttonStyle(.borderedProminent)
                }
                if receivedActive == nil && finishedToday == nil, let latest = records.history.first {
                    recap(latest, heading: "Latest workout")
                }
                TodayActivityCard(health: health, sample: records.isPreview)
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { if !records.isPreview { sync.retry(); await health.refresh() } }
        .navigationTitle("Today")
        .onChange(of: records.history.first(where: \.completed)?.id) { _, _ in restoreWorkoutChoice() }
        .onChange(of: records.archive.plan.revision) { _, _ in restoreWorkoutChoice() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in restoreWorkoutChoice() }
    }
    private func recap(_ session: StrengthSession, heading: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading).font(.headline)
            NavigationLink { SessionDetail(records: records, id: session.id) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    VisualWorkoutRow(session: session)
                    if let elapsed = session.elapsed { Text(Duration.seconds(elapsed).formatted(.time(pattern: .hourMinuteSecond)))
                        .font(.subheadline).foregroundStyle(.secondary) }
                    Text("View workout").font(.subheadline.weight(.medium)).foregroundStyle(session.identityColor)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !records.isPreview && (session.healthState == .recovery || session.healthState == .notFound) {
                Label("Health save needs attention", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            }
        }.phoneCard()
    }

}

/// Health-app style card: colored symbol + title header over grouped content.
struct HealthCard<Content: View>: View {
    let title: String, systemImage: String, color: Color
    @ViewBuilder let content: Content
    init(_ title: String, systemImage: String, color: Color, @ViewBuilder content: () -> Content) {
        self.title = title; self.systemImage = systemImage; self.color = color; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: REPStyle.row) {
            Label(title, systemImage: systemImage).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: REPStyle.cardRadius, style: .continuous))
    }
}

struct CardLinkRow<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        HStack { content; Spacer(); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
            .foregroundStyle(.primary).contentShape(Rectangle())
    }
}

struct RingStat: View {
    let title: String, value: Double, goal: Double, unit: String, color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.subheadline)
            Text("\(Int(value))/\(Int(goal)) ").font(.system(.title3, design: .rounded).bold()) + Text(unit).font(.system(.footnote, design: .rounded).bold())
        }.foregroundStyle(color)
    }
}

/// Apple's own ring renderer fed the real HKActivitySummary; nothing is drawn when Health has no data.
struct ActivityRings: UIViewRepresentable {
    let summary: HKActivitySummary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    class Coordinator { var values: [Double] = []; var animated: Bool? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> HKActivityRingView { HKActivityRingView() }
    func updateUIView(_ view: HKActivityRingView, context: Context) {
        let values = [summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                      summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                      summary.appleExerciseTime.doubleValue(for: .minute()),
                      summary.appleExerciseTimeGoal.doubleValue(for: .minute()),
                      summary.appleStandHours.doubleValue(for: .count()),
                      summary.appleStandHoursGoal.doubleValue(for: .count())]
        let animated = !reduceMotion
        guard context.coordinator.values != values || context.coordinator.animated != animated else { return }
        context.coordinator.values = values
        context.coordinator.animated = animated
        view.setActivitySummary(summary, animated: animated)
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw TrainingError.invalidArchive }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SessionRow: View {
    let session: StrengthSession
    var body: some View {
        VStack(alignment: .leading, spacing: REPStyle.detail) {
            Text(session.title).font(.headline).foregroundStyle(session.identityColor)
            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
            Text("\(session.effectiveSets.count) sets · \(session.completed ? "Completed" : session.endedAt == nil ? "In progress / interrupted" : "Incomplete")").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct HistoryView: View {
    @ObservedObject var records: TrainingStore
    @ObservedObject var health: HealthHistory
    private var imported: [HKWorkout] {
        let associated = Set(records.archive.sessions.compactMap(\.healthUUID))
        return health.workouts.filter { !associated.contains($0.uuid) }
    }
    var body: some View {
        List {
            Section("REP. strength logs") {
                ForEach(records.history) { session in
                    NavigationLink { SessionDetail(records: records, id: session.id) } label: { SessionRow(session: session) }
                }
                if records.history.isEmpty { Text("No synchronized strength logs yet.").foregroundStyle(.secondary) }
            }
            if !records.isPreview {
            Section("Available Apple Health summaries") {
                ForEach(imported, id: \.uuid) { workout in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(workout.workoutActivityType == .walking ? "Indoor Walking" : "Strength Training").font(.headline)
                        Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                        Text("\(Int(workout.duration / 60)) min · \(workout.sourceRevision.source.name)").foregroundStyle(.secondary)
                        if let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                            Text("\(Int(energy)) active kcal").font(.caption)
                        }
                        Text("Apple Health summary").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(health.status).font(.caption).foregroundStyle(.secondary)
                Button("Refresh Apple Health") { Task { await health.refresh() } }.disabled(health.busy)
            }
            }
        }.navigationTitle("History")
    }
}

struct SessionDetail: View {
    @ObservedObject var records: TrainingStore
    let id: UUID
    @State private var editing: LoggedSet?
    @StateObject private var healthCheck = HealthHistory()
    @State private var checkedHealth = false
    @State private var confirmingDeletion = false
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            if let session = records.session(id) {
                Section {
                    SessionRow(session: session)
                    LabeledContent("Sets", value: "\(session.effectiveSets.count) / \(session.plannedSets) planned")
                    LabeledContent("Repetitions", value: "\(session.effectiveSets.reduce(0) { $0 + $1.reps })")
                    if let elapsed = session.elapsed { LabeledContent("Duration", value: Duration.seconds(elapsed).formatted(.time(pattern: .hourMinuteSecond))) }
                    if let energy = session.activeEnergy { LabeledContent("Active energy", value: "\(Int(energy)) kcal") }
                    Label(records.isPreview ? "Sample data on this simulator" : "Saved locally on this iPhone", systemImage: "internaldrive")
                    if records.isPreview { Text("Sample workout").foregroundStyle(.secondary) }
                    else { Text(session.healthState.title) }
                    if let message = session.healthError { Text(message).font(.caption) }
                    if let uuid = session.healthUUID {
                        Text("Health UUID: \(uuid)").font(.caption2).textSelection(.enabled)
                        Button("Check Linked Health Workout") { checkedHealth = true; Task { await healthCheck.checkAssociation(uuid) } }.disabled(healthCheck.busy)
                    }
                    if checkedHealth { Text(healthCheck.busy ? "Checking Apple Health…" : healthCheck.status).font(.caption).foregroundStyle(.secondary) }
                    if records.hasPendingCorrection(id) { Label("Correction queued for Watch confirmation", systemImage: "clock").font(.caption) }
                    if let issue = records.archive.syncIssues.last {
                        Text("Latest device sync issue: \(issue)").font(.caption).foregroundStyle(.orange)
                    }
                }
                ForEach(session.routine) { exercise in
                    Section(exercise.name) {
                        ForEach(session.effectiveSets.filter { $0.original.exerciseID == exercise.id }) { set in
                            Button { editing = set } label: {
                                VStack(alignment: .leading, spacing: REPStyle.detail) {
                                    Text("Set \(set.original.ordinal) · \(set.reps) reps").foregroundStyle(.primary)
                                    Text(set.load.label).foregroundStyle(.secondary)
                                    if let plates = set.load.addedPlates {
                                        Text("\(plates.repNumber) lb total plates\(set.load.smithBarPounds.map { " + \($0.repNumber) lb configured bar" } ?? "; bar excluded")").font(.caption)
                                    }
                                }
                            }.disabled(session.endedAt == nil || records.hasPendingCorrection(id))
                        }
                        if session.skipped.contains(exercise.id) { Text("Remaining sets skipped").foregroundStyle(.secondary) }
                    }
                }
                Section {
                    Button(role: .destructive) { confirmingDeletion = true } label: {
                        HStack {
                            Label(deleting ? "Deleting…" : "Delete Workout", systemImage: "trash")
                            if deleting { Spacer(); ProgressView() }
                        }.frame(minHeight: 44)
                    }
                    .disabled(deleting || session.endedAt == nil || session.healthState == .recording || session.healthState == .saving)
                } footer: {
                    Text(session.endedAt == nil ? "End this workout on Apple Watch before deleting it." : records.isPreview ? "Removes this sample workout only." : "Deletes this REP log and its linked Apple Health workout. This cannot be undone.")
                }
                Section {
                    DisclosureGroup("About corrections") {
                        Text("Changes sync through your Watch. Original sets are preserved.")
                    }.font(.footnote).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("Workout")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete Workout", systemImage: "trash", role: .destructive) { confirmingDeletion = true }
                        .disabled(deleting || records.session(id)?.endedAt == nil || records.session(id)?.healthState == .saving || records.session(id)?.healthState == .recording)
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Workout actions")
            }
        }
        .confirmationDialog(records.isPreview ? "Delete sample workout?" : "Delete workout from REP and Apple Health?",
                            isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) { Task { await deleteWorkout() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(records.isPreview ? "This changes sample history only." : "The linked Health workout and this iPhone's REP log will be removed. The original Watch log is retained. This cannot be undone.")
        }
        .sheet(item: $editing) { set in
            if let session = records.session(id) {
                SetCorrectionEditor(records: records, session: session, set: set)
            }
        }
    }
    @MainActor private func deleteWorkout() async {
        guard !deleting, let session = records.session(id) else { return }
        deleting = true
        defer { deleting = false }
        var healthDeleted = false
        do {
            guard session.endedAt != nil else { throw TrainingError.activeSession }
            if !records.isPreview {
                if let uuid = session.healthUUID {
                    try await healthCheck.deleteWorkout(uuid)
                    healthDeleted = true
                } else if session.healthState != .notStarted {
                    throw WorkoutDeletionError.unresolved
                }
            }
            try records.deleteFromPhone(id)
            dismiss()
        } catch {
            records.errorMessage = healthDeleted
                ? "Apple Health deleted the workout, but the REP log could not be removed: \(error.localizedDescription)"
                : error.localizedDescription
        }
    }

}

struct SetCorrectionEditor: View {
    @ObservedObject var records: TrainingStore
    let session: StrengthSession
    let set: LoggedSet
    @State private var load: TrainingLoad
    @State private var reps: Int
    @State private var validationError: String?
    @Environment(\.dismiss) private var dismiss
    init(records: TrainingStore, session: StrengthSession, set: LoggedSet) {
        self.records = records; self.session = session; self.set = set
        _load = State(initialValue: set.load); _reps = State(initialValue: set.reps)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(set.original.exerciseName) {
                    LoadFields(load: $load)
                    Stepper("\(reps) reps", value: $reps, in: 0...100)
                }
                Text("This corrects only this set. It does not change the Health workout or future weights.").font(.caption)
            }.navigationTitle("Correct Set")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Queue Correction") {
                        do { try records.requestCorrection(session: session, set: set, load: load, reps: reps); dismiss() }
                        catch { validationError = error.localizedDescription }
                    }
                }
            }
            .alert("Check Set", isPresented: Binding(get: { validationError != nil }, set: { if !$0 { validationError = nil } })) {
                Button("OK") { validationError = nil }
            } message: { Text(validationError ?? "") }
        }
    }
}

struct LoadFields: View {
    @Binding var load: TrainingLoad
    var body: some View {
        Picker("Load type", selection: $load.kind) { ForEach(LoadKind.allCases) { Text($0.title).tag($0) } }
            .onChange(of: load.kind) { _, kind in
                if kind == .bodyweight || kind == .unknown { load.pounds = nil }

                if kind != .smith { load.smithBarPounds = nil }
            }
        if load.kind != .unknown && load.kind != .bodyweight {
            HStack {
                Text(load.kind == .smith ? "Plates per side (lb)" : load.kind == .assistance ? "Assistance (lb)" : load.kind == .addedBodyweight ? "Added weight (lb)" : "Resistance (lb)")
                TextField("Pounds", value: $load.pounds, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
        }
        if load.kind == .smith {
            Toggle("Include known effective bar", isOn: Binding(get: { load.smithBarPounds != nil }, set: { load.smithBarPounds = $0 ? 0 : nil }))
            if load.smithBarPounds != nil {
                TextField("Effective bar (lb)", value: $load.smithBarPounds, format: .number).keyboardType(.decimalPad)
            }
            Text("Leave an unknown bar excluded.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
