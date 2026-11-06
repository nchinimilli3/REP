import SwiftUI
import HealthKit

struct SampleDataBanner: View {
    var body: some View {
        Label("Sample data · Health & sync off", systemImage: "testtube.2")
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .background(.bar)
            .accessibilityLabel("Simulator sample data. Apple Health and device sync are disabled.")
    }
}

struct ProgressMetric: View {
    let value: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(.title, design: .rounded).weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct PhoneRoutineRow: View {
    @ObservedObject var records: TrainingStore
    let exercise: Exercise
    private var previous: TrainingLoad? {
        records.visibleSessions.flatMap(\.effectiveSets)
            .filter { $0.original.exerciseID == exercise.id && $0.load.comparisonKey == exercise.load.comparisonKey }
            .max { $0.original.completedAt < $1.original.completedAt }?.load
    }
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text("\(exercise.sets) sets × \(exercise.reps) reps").font(.caption).foregroundStyle(.secondary)
                if let previous {
                    Text("Last: \(previous.label)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if exercise.needsStartingWeight {
                Text("Set weight").font(.subheadline).foregroundStyle(exercise.identityColor)
            } else {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(records.recalledLoad(exercise).pounds.map { "\($0.repNumber) lb" } ?? "Bodyweight")
                        .font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
                    if exercise.load.kind == .assistance { Text("assistance").font(.caption2).foregroundStyle(.secondary) }
                    if exercise.load.kind == .smith { Text("per side").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }.padding(.vertical, 3).frame(minHeight: 52).contentShape(Rectangle())
    }
}


extension View {
    func phoneCard() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct TodayActivityCard: View {
    @ObservedObject var health: HealthHistory
    let sample: Bool
    var body: some View {
        Group {
            if health.activity != nil || health.steps != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Daily activity").font(.headline)
                    HStack(spacing: 20) {
                        if let activity = health.activity {
                            ActivityRings(summary: activity).frame(width: 92, height: 92)
                            VStack(alignment: .leading, spacing: 4) {
                                RingStat(title: "Move", value: activity.activeEnergyBurned.doubleValue(for: .kilocalorie()), goal: activity.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()), unit: "CAL", color: .pink)
                                Text("\(Int(activity.appleExerciseTime.doubleValue(for: .minute()))) min exercise · \(Int(activity.appleStandHours.doubleValue(for: .count()))) stand hours")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack {
                        Label("Steps today", systemImage: "figure.walk").foregroundStyle(.secondary)
                        Spacer()
                        Text(health.steps.map { Int($0).formatted() } ?? "Unavailable").fontWeight(.semibold).monospacedDigit()
                    }.font(.subheadline)
                }
            } else if sample {
                Label("Live activity is unavailable in sample mode.", systemImage: "heart")
                    .font(.caption).foregroundStyle(.secondary)
            } else if health.requestedAccess {
                HStack(spacing: 12) {
                    Image(systemName: "heart").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Activity unavailable").font(.subheadline.weight(.medium))
                        Text("Apple Health hasn't returned rings or steps yet.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Refresh") { Task { await health.refresh() } }.disabled(health.busy)
                }
            } else {
                Button { Task { await health.refresh() } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill").foregroundStyle(.pink)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Connect Apple Health").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text("See your daily activity alongside your training.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain).disabled(health.busy)
            }
        }.phoneCard()
    }
}
