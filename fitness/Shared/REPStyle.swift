import SwiftUI

/// Shared visual language. Watch keeps compact spacing and capsule actions;
/// iPhone and Mac share card spacing without replacing native lists and forms.
enum REPStyle {
    static let detail: CGFloat = 4
    static let compact: CGFloat = 8
    static let row: CGFloat = 12
    static let section: CGFloat = 16
    static let page: CGFloat = 24
    static let cardRadius: CGFloat = 20
    static let watchCardRadius: CGFloat = 26
    static let minimumTarget: CGFloat = 44
    static let accent = Color(red: 0.78, green: 0.32, blue: 1)
    static let abs = Color.cyan
}

extension Split {
    var identityColor: Color {
        switch self {
        case .back: return REPStyle.accent
        case .glutes: return Color(red: 1, green: 0.18, blue: 0.53)
        case .legs: return Color(red: 0.70, green: 1, blue: 0.08)
        }
    }
}

extension Exercise {
    var identityColor: Color { preferredRoutineColor?.swiftUI ?? split?.identityColor ?? (id == "abs" ? REPStyle.abs : REPStyle.accent) }
    var routineDescription: String? { id == "abs" ? "Weighted mat routine" : nil }
    var needsStartingWeight: Bool { id == "back-extension" && load.kind == .unknown }
}


extension RoutineColor {
    var swiftUI: Color {
        switch self {
        case .purple: return REPStyle.accent
        case .pink: return Split.glutes.identityColor
        case .lime: return Split.legs.identityColor
        case .blue: return .blue
        case .orange: return .orange
        case .teal: return .teal
        }
    }
}
extension WorkoutRoutine {
    var identityColor: Color { color.swiftUI }
    var workoutColor: Color { identityColor }
    var workoutSymbol: String { symbol }
}
extension StrengthSession {
    var identityColor: Color { routineColor?.swiftUI ?? Split.at(day: day).identityColor }
    var artworkSymbol: String { routineSymbol ?? Split.at(day: day).workoutSymbol }
}
