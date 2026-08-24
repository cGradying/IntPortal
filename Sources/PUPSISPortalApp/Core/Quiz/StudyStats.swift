import Foundation

/// The streak rule (from grilling): studying is reviewing at least one card
/// on a calendar day, not clearing everything due. Pure date logic, no store
/// access, so it's testable without `QuizStore`.
enum StudyStats {
    /// Advances `stats` for a review happening at `now`. Same calendar day
    /// as `lastStudied` → streak unchanged (already counted today). The very
    /// next calendar day → streak increments. Any bigger gap → streak resets
    /// to 1. `calendar` is injectable so tests don't depend on the machine's
    /// timezone/locale.
    static func advance(_ stats: QuizStats, reviewedAt now: Date, calendar: Calendar = .current) -> QuizStats {
        var stats = stats
        // `QuizStats` is a value type — `return stats` copies its current
        // value immediately, so mutating the local `stats` after that (a
        // `defer`, say) would land on a copy nothing reads. Every path below
        // sets `lastStudied` itself, before returning.

        guard let last = stats.lastStudied else {
            stats.streak = 1
            stats.lastStudied = now
            return stats
        }
        if calendar.isDate(last, inSameDayAs: now) {
            stats.lastStudied = now
            return stats
        }
        let lastDay = calendar.startOfDay(for: last)
        let today = calendar.startOfDay(for: now)
        let daysBetween = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        stats.streak = daysBetween == 1 ? stats.streak + 1 : 1
        stats.lastStudied = now
        return stats
    }
}
