import Foundation

extension TrainingStore {
    /// User-confirmed on October 16: Abs currently uses 3 lb of added weight.
    /// Only an untouched unspecified default is initialized. Existing choices
    /// and immutable workout snapshots retain their original values.
    @discardableResult
    func applyConfirmedAbsPreference() throws -> Bool {
        guard !isWatch, let index = archive.plan.exercises.firstIndex(where: { $0.id == "abs" }),
              archive.plan.exercises[index].load.kind == .unknown,
              archive.plan.exercises[index].preferenceUpdatedAt == .distantPast else { return false }
        var plan = archive.plan
        plan.exercises[index] = plan.exercises[index].withConfirmedDefaults
        plan.exercises[index].preferenceUpdatedAt = .now
        try savePlan(plan)
        return true
    }
}


extension TrainingStore {
    /// October 30 routine changes apply only to future workouts, via phone-owned plan sync.
    /// A new machine identity prevents recalling or charting pulldown loads as extensions.
    @discardableResult
    func applyConfirmedRoutinePreferences() throws -> Bool {
        guard !isWatch else { return false }
        var plan = archive.plan
        var changed = false
        if let index = plan.exercises.firstIndex(where: {
            $0.id == "pulldown" && $0.name == "Lat Pulldown"
        }), !plan.exercises.contains(where: { $0.id == "back-extension" }) {
            var replacement = plan.exercises[index]
            replacement.id = "back-extension"
            replacement.name = "Back Extension Machine"
            replacement.load = TrainingLoad(kind: .unknown, pounds: nil)
            replacement.notes = ""
            replacement.preferenceUpdatedAt = .now
            plan.exercises[index] = replacement
            changed = true
        }
        if let index = plan.exercises.firstIndex(where: {
            $0.id == "abs" && $0.name == "Hanging Ab Crunch / Hanging Ab Machine"
        }) {
            plan.exercises[index].name = "Abs"
            if plan.exercises[index].notes.isEmpty {
                plan.exercises[index].notes = "Weighted mat routine. Log your added weight, sets and reps."
            }
            changed = true
        }
        guard changed else { return false }
        try savePlan(plan)
        return true
    }
}
