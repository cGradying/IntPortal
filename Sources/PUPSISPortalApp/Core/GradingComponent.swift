import Foundation

/// One weighted piece of a subject's grade — "Midterm Exam, 30%", "Lab
/// Reports, 25%" — as printed in a real syllabus's grading-system section.
/// `score` is nil until the student types in what they actually got back;
/// everything here stays achievable without it (weights alone still tell you
/// what's worth the most).
struct GradingComponent: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    /// Percent of the subject's final grade, 0–100. Components across one
    /// subject are expected to sum to 100 but this isn't enforced — a
    /// syllabus mid-extraction, or one the student is still filling in by
    /// hand, is allowed to be incomplete.
    var weight: Double
    /// The student's own score on this component, percent 0–100. Never
    /// extracted by the AI — a syllabus prints what a component is worth,
    /// never what the student scored on it.
    var score: Double?

    init(id: UUID = UUID(), name: String, weight: Double, score: Double? = nil) {
        self.id = id
        self.name = name
        self.weight = weight
        self.score = score
    }
}

/// Pure weighted-grade math over one subject's `GradingComponent` list — no
/// store, no view, so it's testable the same way `GradesParser.gpa(of:)` is.
enum GradingCalculator {
    /// The running weighted score from components that already have a
    /// `score` — components still awaiting a score contribute nothing yet,
    /// deliberately not zero-filled (that would understate progress, not
    /// warn about it).
    static func currentWeightedScore(_ components: [GradingComponent]) -> Double {
        components.reduce(0) { $0 + ($1.score ?? 0) * $1.weight / 100 }
    }

    /// The average score needed across every component that's still
    /// unscored to land the subject at `target` percent overall. `nil` when
    /// every component already has a score — there's nothing left to solve
    /// for, same reasoning as `GradesParser.neededAverage`'s "already fully
    /// posted" case.
    static func neededAverage(_ components: [GradingComponent], target: Double) -> Double? {
        let remainingWeight = components.filter { $0.score == nil }.reduce(0) { $0 + $1.weight }
        guard remainingWeight > 0 else { return nil }

        let knownWeighted = components.compactMap { component -> Double? in
            guard let score = component.score else { return nil }
            return score * component.weight / 100
        }.reduce(0, +)

        return (target - knownWeighted) / remainingWeight * 100
    }
}
