import SwiftUI
import Charts

private struct WorkoutDay: Identifiable {
    let date: Date
    let sessions: [StrengthSession]
    var id: Date { date }
}

struct ProgressViewScreen: View {
    @ObservedObject var records: TrainingStore
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @State private var selectedDay: WorkoutDay?
    private var completed: [StrengthSession] { records.history.filter(\.completed) }
    private var exercises: [Exercise] {
        var result = records.archive.plan.exercises
        for exercise in records.visibleSessions.flatMap(\.routine) where !result.contains(where: { $0.id == exercise.id }) {
            result.append(exercise)
        }
        return result
    }
    private var monthWorkouts: [StrengthSession] {
        let interval = Calendar.current.dateInterval(of: .month, for: month)!
        return completed.filter { interval.contains($0.startedAt) }
    }
    private var bestMonth: Int {
        Dictionary(grouping: completed) { Calendar.current.dateInterval(of: .month, for: $0.startedAt)!.start }
            .values.map(\.count).max() ?? 0
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if records.isPreview { SampleDataBanner() }
                WorkoutCalendar(sessions: records.history, month: $month) { date, sessions in
                    selectedDay = WorkoutDay(date: date, sessions: sessions)
                }.phoneCard()
                achievement.phoneCard()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Exercise progress").font(.headline)
                    VStack(spacing: 0) {
                        ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                            if index > 0 { Divider() }
                            NavigationLink { ExerciseProgressView(records: records, exercise: exercise) } label: {
                                HStack {
                                    ExerciseProgressRow(exercise: exercise, sessions: completed)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }.padding(.vertical, 6).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }.phoneCard()
                if !records.history.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Workout history").font(.headline)
                        VStack(spacing: 0) {
                            ForEach(Array(records.history.enumerated()), id: \.element.id) { index, session in
                                if index > 0 { Divider() }
                                NavigationLink { SessionDetail(records: records, id: session.id) } label: {
                                    HStack {
                                        VisualWorkoutRow(session: session)
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }.phoneCard()
                }
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Progress")
        .sheet(item: $selectedDay) { selection in
            NavigationStack {
                Group {
                    if selection.sessions.count == 1, let session = selection.sessions.first {
                        SessionDetail(records: records, id: session.id)
                    } else {
                        List(selection.sessions) { session in
                            NavigationLink { SessionDetail(records: records, id: session.id) } label: {
                                VisualWorkoutRow(session: session)
                            }
                        }.navigationTitle(selection.date.formatted(.dateTime.month(.abbreviated).day()))
                    }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { selectedDay = nil } } }
            }.preferredColorScheme(.dark)
        }
    }
    private var achievement: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(monthWorkouts.count > 1 && monthWorkouts.count == bestMonth ? "Your most active month" : "Your work is adding up", systemImage: "medal.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(REPStyle.accent)
            if !monthWorkouts.isEmpty {
                Text("\(monthWorkouts.count) workouts").font(.system(.title, design: .rounded).weight(.semibold))
                Text("Completed in \(month.formatted(.dateTime.month(.wide).year()))")
                    .font(.subheadline).foregroundStyle(.secondary)
                if monthWorkouts.count == bestMonth && bestMonth > 1 {
                    Text("Most completed workouts in any recorded calendar month, including ties.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if !completed.isEmpty {
                Text("\(completed.count) workouts recorded").font(.title2.weight(.semibold))
                Text("Your completed work is always here to revisit.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Every session starts something.").font(.title2.weight(.semibold))
                Text("Your first completed workout will appear here.").font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 8)
    }

}

struct WorkoutCalendar: View {
    let sessions: [StrengthSession]
    @Binding var month: Date
    var selectDay: (Date, [StrengthSession]) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swipeStart: Date?
    private let calendar = Calendar.current
    private var start: Date { calendar.dateInterval(of: .month, for: month)!.start }
    private var days: [Date] {
        (calendar.range(of: .day, in: .month, for: month) ?? 1..<29)
            .compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
    }
    private var offset: Int { (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7 }
    private func changeMonth(_ amount: Int) {
        guard let next = calendar.date(byAdding: .month, value: amount, to: start) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { month = next }
    }
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { changeMonth(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }.accessibilityLabel("Previous month")
                Button { changeMonth(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }.accessibilityLabel("Next month")
            }.buttonStyle(.plain)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
                        .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
                ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 44) }
                ForEach(days, id: \.self) { date in
                    let workouts = sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
                    Button { selectDay(date, workouts) } label: {
                        VStack(spacing: 4) {
                            Text("\(calendar.component(.day, from: date))")
                                .font(.subheadline.weight(workouts.isEmpty ? .regular : .semibold))
                                .foregroundStyle(calendar.isDateInToday(date) ? .primary : .secondary)
                            HStack(spacing: 3) {
                                ForEach(Array(workouts.prefix(3))) { session in
                                    Circle().fill(session.identityColor).frame(width: 5, height: 5)
                                }
                            }.frame(height: 5)
                        }.frame(maxWidth: .infinity, minHeight: 44)
                            .background(calendar.isDateInToday(date) ? Color.primary.opacity(0.08) : .clear,
                                        in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).disabled(workouts.isEmpty)
                        .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)), \(workouts.count) workouts")
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { calendarLegend }
                VStack(alignment: .leading, spacing: 5) { calendarLegend }
            }.font(.caption2).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 30)
            .onChanged { value in
                if swipeStart == nil && abs(value.translation.width) > abs(value.translation.height) * 1.5 { swipeStart = start }
            }
            .onEnded { value in
                guard let origin = swipeStart else { return }
                swipeStart = nil
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5,
                      let next = calendar.date(byAdding: .month, value: value.translation.width < 0 ? 1 : -1, to: origin) else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { month = next }
            })
    }
    private var legendSessions: [StrengthSession] {
        var seen = Set<String>()
        return sessions.filter { session in
            let key = (session.routineID ?? Split.at(day: session.day).rawValue) + (session.routineColor?.rawValue ?? "legacy")
            return seen.insert(key).inserted
        }
    }
    @ViewBuilder private var calendarLegend: some View {
        if legendSessions.isEmpty {
            ForEach(Split.workoutTypes) { split in
                HStack(spacing: 4) {
                    Circle().fill(split.color).frame(width: 5, height: 5)
                    Text(split.title).foregroundStyle(.secondary)
                }
            }
        } else {
            ForEach(legendSessions) { session in
                HStack(spacing: 4) {
                    Circle().fill(session.identityColor).frame(width: 5, height: 5)
                    Text(session.title).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ExerciseProgressRow: View {
    let exercise: Exercise
    let sessions: [StrengthSession]
    private var points: [SessionLoadPoint] {
        TrainingProgress.sessionLoadPoints(exerciseID: exercise.id, comparisonKey: exercise.load.comparisonKey, sessions: sessions)
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: exercise.id == "abs" ? "figure.core.training" : "dumbbell.fill")
                .foregroundStyle(exercise.identityColor).frame(width: 34, height: 40)
                .background(exercise.identityColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name).font(.body.weight(.medium))
                if let point = points.last {
                    Text("\(point.load.repNumber) lb × \(point.reps) · latest session").font(.caption).foregroundStyle(.secondary)
                } else { Text("See your recorded sets").font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(.vertical, 4)
    }
}

struct VisualWorkoutRow: View {
    let session: StrengthSession
    private var preview: String {
        let names = session.routine.filter { session.count(for: $0.id) > 0 }.map(\.name)
        let text = names.prefix(2).joined(separator: " · ")
        return names.count > 2 ? text + " +\(names.count - 2)" : text
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: session.artworkSymbol).font(.title3)
                    .foregroundStyle(session.identityColor).frame(width: 42, height: 48)
                    .background(session.identityColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title).font(.headline)
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("\(session.effectiveSets.count) sets").font(.subheadline.weight(.medium)).monospacedDigit()
            }
            if !preview.isEmpty { Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            if !session.completed { Text(session.endedAt == nil ? "In progress" : "Incomplete workout").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 6)
    }
}

private enum ProgressRange: String, CaseIterable, Identifiable {
    case month = "1M", quarter = "3M", all = "All"
    var id: String { rawValue }
    var start: Date? {
        switch self {
        case .month: return Calendar.current.date(byAdding: .month, value: -1, to: .now)
        case .quarter: return Calendar.current.date(byAdding: .month, value: -3, to: .now)
        case .all: return nil
        }
    }
}

struct ExerciseProgressView: View {
    @ObservedObject var records: TrainingStore
    let exercise: Exercise
    @State private var comparisonKey = ""
    @State private var range = ProgressRange.all
    @State private var selectedDate: Date?
    @State private var editing = false
    @State private var choosingRoutine = false
    @State private var editingRoutineID: String?
    @State private var celebrate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var routineContexts: [WorkoutRoutine] {
        records.archive.plan.availableRoutines.filter { $0.exercises.contains(where: { $0.id == exercise.id }) }
    }
    private var nextSetting: Exercise? {
        routineContexts.first?.exercises.first { $0.id == exercise.id }
            ?? records.archive.plan.exercises.first { $0.id == exercise.id }
    }
    private var routineNames: String {
        let names = records.archive.plan.routines.filter { $0.exercises.contains(where: { $0.id == exercise.id }) }.map(\.name)
        return names.isEmpty ? (exercise.id == "abs" ? "Optional finisher" : exercise.split?.title ?? "Exercise") : names.joined(separator: " · ")
    }
    private var keys: [String] {
        Array(Set(records.history.filter(\.completed).flatMap(\.effectiveSets)
            .filter { $0.original.exerciseID == exercise.id }.map { $0.load.comparisonKey })).sorted()
    }
    private var selectedKey: String {
        comparisonKey.isEmpty ? (keys.contains(exercise.load.comparisonKey) ? exercise.load.comparisonKey : keys.first ?? exercise.load.comparisonKey) : comparisonKey
    }
    private var assistance: Bool { selectedKey.hasPrefix("assistance:") }
    private var smith: Bool { selectedKey.hasPrefix("smith:") }
    private var basis: String { assistance ? "Assistance (lb)" : smith ? "Plates per side (lb)" : "Load (lb)" }
    private var points: [SessionLoadPoint] {
        TrainingProgress.sessionLoadPoints(exerciseID: exercise.id, comparisonKey: selectedKey, sessions: records.visibleSessions)
    }
    private var chartPoints: [SessionLoadPoint] { points.filter { range.start == nil || $0.date >= range.start! } }
    private var selected: SessionLoadPoint? {
        guard let selectedDate else { return chartPoints.last }
        return chartPoints.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private var best: SessionLoadPoint? {
        points.sorted {
            if $0.load == $1.load { return $0.reps > $1.reps }
            return assistance ? $0.load < $1.load : $0.load > $1.load
        }.first
    }
    private var sessions: [StrengthSession] {
        records.history.filter { $0.effectiveSets.contains { $0.original.exerciseID == exercise.id } }
    }
    private var yDomain: ClosedRange<Double> {
        let low = chartPoints.map(\.load).min() ?? 0
        let high = chartPoints.map(\.load).max() ?? 1
        let pad = max(5, (high - low) * 0.2)
        return max(0, low - pad)...(high + pad)
    }
    private var xDomain: ClosedRange<Date> {
        let first = chartPoints.first?.date ?? .now
        let last = chartPoints.last?.date ?? .now
        return first.addingTimeInterval(-86400)...last.addingTimeInterval(86400)
    }
    var body: some View {
        List {
            Section {
                if records.isPreview { Text("Sample history").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                Label(routineNames, systemImage: exercise.id == "abs" ? "figure.core.training" : "dumbbell.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(exercise.identityColor)
                if let latest = points.last {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(points.count == 1 ? "First session recorded" : "Latest recorded session")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("\(latest.load.repNumber) lb × \(latest.reps)")
                            .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        Text(latest.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                        if points.count > 1, let first = points.first {
                            Text("First session: \(first.load.repNumber) lb × \(first.reps)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 5)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your progress starts here").font(.headline)
                        Text(sessions.isEmpty ? "Complete this exercise on your Apple Watch to see your sets here." : "Your sets are recorded below. Comparable weighted sets will add a chart here.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
                if keys.count > 1 {
                    Picker("Load type", selection: Binding(get: { selectedKey }, set: { comparisonKey = $0; selectedDate = nil })) {
                        ForEach(keys, id: \.self) { key in Text(loadTypeLabel(key)).tag(key) }
                    }
                }
            }
            if !points.isEmpty {
                Section {
                    Picker("Chart range", selection: $range) {
                        ForEach(ProgressRange.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    if chartPoints.isEmpty {
                        Text("No sessions in this range. Choose All to revisit your earlier work.")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
                    } else {
                        chart
                        if let selected {
                            HStack {
                                Text(selected.date.formatted(date: .abbreviated, time: .omitted))
                                Spacer()
                                Text("\(selected.load.repNumber) lb × \(selected.reps)").fontWeight(.semibold)
                            }.font(.caption).monospacedDigit()
                        }
                        Text(assistance ? "Each dot: lowest assistance in that session, with its actual reps. Less assistance can mean progress." : smith ? "Each dot: highest plates per side in that session, with its actual reps. Different bar settings stay separate." : "Each dot: highest completed load in that session, with its actual reps.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Working load") }
                if let best {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "medal.fill").foregroundStyle(exercise.identityColor)
                                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : celebrate)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(assistance ? "Lowest recorded assistance" : "Highest recorded load").font(.subheadline.weight(.semibold))
                                Text("\(best.load.repNumber) lb × \(best.reps)").font(.title2.weight(.semibold))
                                Text(best.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                                Text("All recorded sessions · same load type. Reps and technique may differ.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 6)
                    }
                }
            }
            if !sessions.isEmpty {
                Section("Session history") {
                    ForEach(sessions) { session in
                        NavigationLink { SessionDetail(records: records, id: session.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.medium))
                                Text(setSummary(session)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                if !session.completed { Text("Incomplete workout").font(.caption).foregroundStyle(.secondary) }
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
            if let planned = nextSetting {
                Section {
                    Button {
                        if routineContexts.count > 1 { choosingRoutine = true }
                        else { editingRoutineID = routineContexts.first?.id; editing = true }
                    } label: {
                        HStack {
                            Text("Next-session setting").foregroundStyle(.primary)
                            Spacer()
                            Text(routineContexts.count > 1 ? "Choose routine" : records.recalledLoad(planned).label).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                        }.font(.subheadline).frame(minHeight: 44)
                    }.buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(exercise.name).navigationBarTitleDisplayMode(.inline)
        .contentMargins(.top, 12, for: .scrollContent)
        .onChange(of: best?.setID) { old, new in if old != nil && new != nil { celebrate.toggle() } }
        .onChange(of: range) { _, _ in selectedDate = nil }
        .confirmationDialog("Edit targets in which routine?", isPresented: $choosingRoutine, titleVisibility: .visible) {
            ForEach(routineContexts) { routine in
                Button(routine.name) { editingRoutineID = routine.id; editing = true }
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $editing) {
            if let planned = editingRoutineID.flatMap({ id in records.archive.plan.routine(id: id)?.exercises.first { $0.id == exercise.id } }) ?? nextSetting {
                ExerciseEditor(records: records, exercise: planned, adding: false,
                               planRevision: records.archive.plan.revision, routineID: editingRoutineID)
            }
        }
    }
    private var chart: some View {
        Chart {
            ForEach(chartPoints) { point in
                if chartPoints.count > 1 {
                    LineMark(x: .value("Date", point.date), y: .value(basis, point.load))
                        .foregroundStyle(exercise.identityColor).lineStyle(StrokeStyle(lineWidth: 2))
                }
                PointMark(x: .value("Date", point.date), y: .value(basis, point.load))
                    .foregroundStyle(exercise.identityColor).symbolSize(selected?.id == point.id ? 60 : 28)
                    .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue("\(point.load.repNumber) pounds, \(point.reps) reps")
            }
            if let selected, selectedDate != nil {
                RuleMark(x: .value("Selected session", selected.date)).foregroundStyle(.secondary.opacity(0.3))
            }
        }
        .frame(height: 190).padding(.vertical, 8)
        .chartYScale(domain: yDomain).chartXScale(domain: xDomain)
        .chartYAxis { AxisMarks(position: .leading) }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
        } }
        .chartYAxisLabel(basis)
        .chartXSelection(value: $selectedDate)
    }
    private func setSummary(_ session: StrengthSession) -> String {
        session.effectiveSets.filter { $0.original.exerciseID == exercise.id }
            .map { "\($0.load.label) × \($0.reps)" }.joined(separator: " · ")
    }
    private func loadTypeLabel(_ key: String) -> String {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        let title = LoadKind(rawValue: parts[0])?.title ?? "Recorded load"
        guard parts[0] == "smith" else { return title }
        return title + (parts.last == "bar-excluded" ? " · bar excluded" : " · bar \(parts.last ?? "") lb")
    }
}
