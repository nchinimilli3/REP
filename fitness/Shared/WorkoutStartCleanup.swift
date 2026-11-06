import Foundation

/// What to do with a HealthKit session when start fails partway through.
/// Kept free of HealthKit so the policy is testable off-device.
enum WorkoutStartCleanup: Equatable {
    /// Nothing was handed to HealthKit yet.
    case none
    /// The session never began: discard the builder and release handles.
    case discard
    /// `startActivity` ran but `beginCollection` failed: detach the delegate,
    /// discard the builder and end the session so no running session is left
    /// open and no partial workout is saved. Local sets stay in recovery.
    case discardAndEnd

    static func after(sessionCreated: Bool, activityStarted: Bool, collectionStarted: Bool) -> WorkoutStartCleanup {
        guard sessionCreated else { return .none }
        // A started collection is reconciled through recovery, never discarded.
        if collectionStarted { return .none }
        return activityStarted ? .discardAndEnd : .discard
    }
}
