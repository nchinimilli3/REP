import SwiftUI

struct CycleProgressView: View {
    let progress: CurrentCycleProgress
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if progress.cycleID == nil {
                Text("Cycle progress will appear when the Watch sends its rotation.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(progress.completedCount) of 3 workout types recorded").font(.subheadline).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(progress.days) { day in
                    VStack(spacing: 4) {
                        ZStack {
                            let color = Split.at(day: day.day).color
                            Circle().fill(day.completed ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.15)))
                            Circle().stroke(day.isNext ? color : .clear, lineWidth: 3)
                            Image(systemName: day.completed ? "checkmark" : "figure.strengthtraining.traditional")
                                .font(.title2.weight(.semibold)).foregroundStyle(day.completed ? .white : color)
                        }.frame(width: 60, height: 60)
                        Text(Split.at(day: day.day).title).font(.footnote.weight(.semibold)).multilineTextAlignment(.center)
                        if day.completed {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
                        } else { Text(day.isNext ? "Next" : "—").font(.caption2) }
                        if day.includesAbs { Text("Abs").font(.caption2).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.accessibilityDescription)
                }
            }
            Text("Checkmarks represent completed workouts assigned to this cycle. Skipped positions stay open.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}
