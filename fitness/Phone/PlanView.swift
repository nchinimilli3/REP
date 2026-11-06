import SwiftUI

struct PlanView: View {
    @ObservedObject var records: TrainingStore
    @State private var creating = false
    @State private var restSettings = false
    var body: some View {
        List {
            if records.isPreview { Section { Text("Sample plan").font(.caption.weight(.medium)).foregroundStyle(.secondary) } }
            Section("Your routines") {
                ForEach(records.archive.plan.availableRoutines) { routine in
                    NavigationLink { RoutineDetailView(records: records, routineID: routine.id) } label: {
                        RoutineLibraryRow(routine: routine)
                    }
                }
                Button("New Routine", systemImage: "plus") { creating = true }.frame(minHeight: 44)
            }
            Section {
                Button { restSettings = true } label: {
                    HStack {
                        Label("Default rest", systemImage: "timer").foregroundStyle(.primary)
                        Spacer()
                        Text("\(Int(records.archive.plan.defaultRestSeconds)) sec").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
            let archived = records.archive.plan.routines.filter(\.archived)
            if !archived.isEmpty {
                Section("Archived routines") {
                    ForEach(archived) { routine in
                        HStack {
                            RoutineLibraryRow(routine: routine)
                            Button("Restore") { records.perform {
                                var plan = records.archive.plan
                                var restored = routine; restored.archived = false
                                plan.saveRoutine(restored); try records.savePlan(plan)
                            } }
                        }
                    }
                }
            }
            Section {
                Text("Plan edits apply to future workouts after sync. Completed workouts keep their original details.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Plan")
        .sheet(isPresented: $creating) { RoutineEditor(records: records) }
        .sheet(isPresented: $restSettings) { RestSettings(records: records) }
    }
}

struct RoutineLibraryRow: View {
    let routine: WorkoutRoutine
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: routine.symbol).resizable().scaledToFit()
                .frame(width: 36, height: 36).foregroundStyle(routine.identityColor)
                .frame(width: 56, height: 64)
                .background(routine.identityColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text(routine.name).font(.headline).foregroundStyle(.primary)
                Text("\(routine.exercises.count) exercises · \(routine.exercises.reduce(0) { $0 + $1.sets }) sets")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 8)
    }
}

struct RoutineDetailView: View {
    @ObservedObject var records: TrainingStore
    let routineID: String
    @State private var editMode = EditMode.inactive
    @State private var editing: Exercise?
    @State private var adding = false
    @State private var renaming = false
    @State private var archiving = false
    @Environment(\.dismiss) private var dismiss
    private var routine: WorkoutRoutine? { records.archive.plan.routine(id: routineID) }
    var body: some View {
        List {
            if let routine {
                Section {
                    ForEach(routine.exercises) { exercise in
                        Button { editing = exercise } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(exercise.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                                Text("\(exercise.sets) × \(exercise.reps) · \(exercise.load.label) · \(Int(exercise.restSeconds)) sec rest")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 7).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                    .onDelete { offsets in update { value in value.exercises.remove(atOffsets: offsets) } }
                    .onMove { offsets, destination in update { $0.exercises.move(fromOffsets: offsets, toOffset: destination) } }
                    Button("Add Exercise", systemImage: "plus") { adding = true }.frame(minHeight: 44)
                } footer: { Text("Reuse an exercise to keep its history. Targets belong to this routine. Keep at least one exercise, or archive the routine.") }
                if let abs = records.archive.plan.exercises.first(where: { $0.id == "abs" }) {
                    Section("Optional finisher") {
                        Button { editing = abs } label: {
                            Label("Optional Abs finisher", systemImage: "figure.core.training").foregroundStyle(REPStyle.abs)
                        }.frame(minHeight: 44)
                    }
                }
            }
        }
        .navigationTitle(routine?.name ?? "Routine").navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if editMode == .active { Button("Done") { editMode = .inactive } }
                else {
                    Menu {
                        Button("Edit Exercises", systemImage: "arrow.up.arrow.down") { editMode = .active }
                        Button("Rename", systemImage: "pencil") { renaming = true }
                        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate() }
                        Button("Archive", systemImage: "archivebox", role: .destructive) { archiving = true }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Routine actions")
                }
            }
        }
        .sheet(item: $editing) { exercise in
            ExerciseEditor(records: records, exercise: exercise, adding: false, planRevision: records.archive.plan.revision,
                           routineID: exercise.id == "abs" ? nil : routineID)
        }
        .sheet(isPresented: $adding) {
            ExerciseLibraryPicker(records: records, excluding: Set(routine?.exercises.map(\.id) ?? [])) { exercise in
                update { $0.exercises.append(exercise) }
            }
        }
        .sheet(isPresented: $renaming) { if let routine { RoutineEditor(records: records, existing: routine) } }
        .confirmationDialog("Archive this routine?", isPresented: $archiving, titleVisibility: .visible) {
            Button("Archive Routine", role: .destructive) { update { $0.archived = true }; if records.errorMessage == nil { dismiss() } }
            Button("Cancel", role: .cancel) { }
        } message: { Text("It will leave Today and Watch after sync. Completed workouts and exercise history stay available. You can restore it in Plan.") }
    }
    private func update(_ change: (inout WorkoutRoutine) -> Void) {
        records.perform {
            guard var value = routine else { throw TrainingError.invalidPlan }
            change(&value)
            var plan = records.archive.plan; plan.saveRoutine(value); try records.savePlan(plan)
        }
    }
    private func duplicate() {
        records.perform {
            guard var value = routine else { throw TrainingError.invalidPlan }
            value.id = UUID().uuidString; value.name += " Copy"; value.legacySplit = nil
            var plan = records.archive.plan; plan.saveRoutine(value); try records.savePlan(plan)
        }
    }
}

struct RoutineEditor: View {
    @ObservedObject var records: TrainingStore
    private let originalID: String?
    private let originalSplit: Split?
    private let revision: Int
    @State private var name: String
    @State private var color: RoutineColor
    @State private var exercises: [Exercise]
    @State private var adding = false
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss
    init(records: TrainingStore, existing: WorkoutRoutine? = nil) {
        self.records = records; originalID = existing?.id; originalSplit = existing?.legacySplit
        revision = records.archive.plan.revision
        _name = State(initialValue: existing?.name ?? "")
        _color = State(initialValue: existing?.color ?? .blue)
        _exercises = State(initialValue: existing?.exercises ?? [])
    }
    private var preview: WorkoutRoutine {
        .init(id: originalID ?? "preview", name: name.isEmpty ? "Your routine" : name, color: color,
              legacySplit: originalSplit, exercises: exercises)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { RoutineLibraryRow(routine: preview) } footer: { Text("The same artwork and color appear on iPhone and Apple Watch.") }
                Section {
                    TextField("Routine name", text: $name).textInputAutocapitalization(.words)
                    Picker("Color", selection: $color) { ForEach(RoutineColor.allCases) { Text($0.title).tag($0) } }
                }
                Section("Exercises") {
                    ForEach(exercises) { exercise in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name)
                            Text("\(exercise.sets) × \(exercise.reps) · \(exercise.load.label)").font(.caption).foregroundStyle(.secondary)
                        }
                    }.onDelete { exercises.remove(atOffsets: $0) }
                    Button("Add Exercises", systemImage: "plus") { adding = true }
                    if exercises.isEmpty { Text("Add at least one exercise before saving.").font(.caption).foregroundStyle(.secondary) }
                }
                if let issue { Section { Text(issue).foregroundStyle(.red).font(.caption) } }
            }
            .navigationTitle(originalID == nil ? "New Routine" : "Edit Routine").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            guard records.archive.plan.revision == revision else { throw TrainingError.conflict }
                            var value = preview; value.id = originalID ?? UUID().uuidString
                            value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            for i in value.exercises.indices { value.exercises[i].preferredRoutineColor = color }
                            var plan = records.archive.plan; plan.saveRoutine(value); try records.savePlan(plan); dismiss()
                        } catch { issue = error.localizedDescription }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || exercises.isEmpty || name.count > 80)
                }
            }
            .sheet(isPresented: $adding) {
                ExerciseLibraryPicker(records: records, excluding: Set(exercises.map(\.id))) { exercises.append($0) }
            }
        }.tint(color.swiftUI)
    }
}

struct ExerciseLibraryPicker: View {
    @ObservedObject var records: TrainingStore
    let excluding: Set<String>
    let onSelect: (Exercise) -> Void
    @State private var search = ""
    @State private var creating = false
    @Environment(\.dismiss) private var dismiss
    private var choices: [Exercise] {
        records.archive.plan.exercises.filter { $0.id != "abs" && !excluding.contains($0.id) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section { Button("Create New Exercise", systemImage: "plus") { creating = true } }
                Section("Exercise library") {
                    ForEach(choices) { exercise in
                        Button { onSelect(exercise); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name).foregroundStyle(.primary)
                                Text(exercise.load.kind.title).font(.caption).foregroundStyle(.secondary)
                            }.frame(minHeight: 44)
                        }
                    }
                }
            }.searchable(text: $search).navigationTitle("Add Exercise").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .sheet(isPresented: $creating) {
                    ExerciseEditor(records: records,
                        exercise: Exercise(id: UUID().uuidString, name: "", split: nil, load: .init(kind: .unknown, pounds: nil),
                                           restSeconds: records.archive.plan.defaultRestSeconds),
                        adding: true, planRevision: records.archive.plan.revision,
                        onSave: { exercise in onSelect(exercise); dismiss() })
                }
        }
    }
}

private struct RestSettings: View {
    @ObservedObject var records: TrainingStore
    @State private var seconds: Double
    @State private var confirming = false
    @Environment(\.dismiss) private var dismiss
    init(records: TrainingStore) { self.records = records; _seconds = State(initialValue: records.archive.plan.defaultRestSeconds) }
    var body: some View {
        NavigationStack {
            Form {
                Section { Stepper("\(Int(seconds)) seconds", value: $seconds, in: 0...1800, step: 15) }
                Section {
                    Button("Update existing exercises…") { confirming = true }
                } footer: { Text("The default applies to new exercises. Existing exercises keep their own rest unless you update them.") }
            }.navigationTitle("Default Rest").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save(existing: false) } }
                }
                .confirmationDialog("Update existing exercises?", isPresented: $confirming, titleVisibility: .visible) {
                    Button("Set All Rest to \(Int(seconds)) Seconds") { save(existing: true) }
                    Button("Cancel", role: .cancel) { }
                } message: { Text("Changes rest for every planned exercise in every routine, including Abs. Active and completed workouts keep their original rest.") }
        }
    }
    private func save(existing: Bool) {
        records.perform {
            var plan = records.archive.plan; plan.defaultRestSeconds = seconds
            if existing {
                for i in plan.exercises.indices { plan.exercises[i].restSeconds = seconds }
                if var routines = plan.routineLibrary {
                    for i in routines.indices { for j in routines[i].exercises.indices { routines[i].exercises[j].restSeconds = seconds } }
                    plan.routineLibrary = routines
                }
            }
            try records.savePlan(plan)
        }
        if records.errorMessage == nil { dismiss() }
    }
}

struct ExerciseEditor: View {
    @ObservedObject var records: TrainingStore
    let adding: Bool
    let planRevision: Int
    let routineID: String?
    let onSave: ((Exercise) throws -> Void)?
    @State private var exercise: Exercise
    @State private var validationError: String?
    @Environment(\.dismiss) private var dismiss
    init(records: TrainingStore, exercise: Exercise, adding: Bool, planRevision: Int,
         routineID: String? = nil, onSave: ((Exercise) throws -> Void)? = nil) {
        self.records = records; self.adding = adding; self.planRevision = planRevision
        self.routineID = routineID; self.onSave = onSave
        _exercise = State(initialValue: exercise)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Exercise name", text: $exercise.name)
                    if exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Enter an exercise name.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    LoadFields(load: $exercise.load)
                    if exercise.load.kind == .unknown {
                        Text("The starting load can stay unspecified until you choose it.").font(.caption).foregroundStyle(.secondary)
                    } else if (try? exercise.load.validate()) == nil {
                        Text("Enter a valid load, or choose Not specified.").font(.caption).foregroundStyle(.red)
                    }
                } header: { Text("Starting load") }
                Section("Targets") {
                    Stepper("\(exercise.sets) sets", value: $exercise.sets, in: 1...20)
                    Stepper("\(exercise.reps) reps", value: $exercise.reps, in: 0...100)
                    Stepper("\(Int(exercise.restSeconds)) sec rest", value: $exercise.restSeconds, in: 0...1800, step: 15)
                }
                Section("Additional options") {
                    HStack {
                        Text("Weight increment (lb)")
                        TextField("Increment", value: $exercise.increment, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    TextField("Notes", text: $exercise.notes, axis: .vertical)
                }
            }.navigationTitle(adding ? "New Exercise" : "Edit Exercise").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }
                        .fontWeight(.semibold).disabled(exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (try? exercise.load.validate()) == nil) }
                }
                .alert("Check Exercise", isPresented: Binding(get: { validationError != nil }, set: { if !$0 { validationError = nil } })) {
                    Button("OK") { validationError = nil }
                } message: { Text(validationError ?? "") }
        }.tint(exercise.identityColor)
    }
    private func save() {
        do {
            if let onSave { try onSave(exercise); dismiss(); return }
            guard planRevision == records.archive.plan.revision else { throw TrainingError.conflict }
            var plan = records.archive.plan
            let old = routineID.flatMap { id in plan.routine(id: id)?.exercises.first { $0.id == exercise.id } }
                ?? plan.exercises.first { $0.id == exercise.id }
            if old?.load != exercise.load { exercise.preferenceUpdatedAt = .now }
            if let routineID, var routine = plan.routine(id: routineID), let index = routine.exercises.firstIndex(where: { $0.id == exercise.id }) {
                routine.exercises[index] = exercise; plan.saveRoutine(routine)
                if old == nil { plan.exercises.append(exercise) }
            } else if adding { plan.exercises.append(exercise) }
            else if let index = plan.exercises.firstIndex(where: { $0.id == exercise.id }) {
                plan.exercises[index] = exercise
                if var routines = plan.routineLibrary {
                    for i in routines.indices where routines[i].legacySplit == exercise.split {
                        if let j = routines[i].exercises.firstIndex(where: { $0.id == exercise.id }) { routines[i].exercises[j] = exercise }
                    }
                    plan.routineLibrary = routines
                }
            } else { throw TrainingError.conflict }
            try records.savePlan(plan); dismiss()
        } catch { validationError = error.localizedDescription }
    }
}
