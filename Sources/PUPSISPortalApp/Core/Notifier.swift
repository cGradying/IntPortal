import EventKit
import Foundation
import UserNotifications

/// Local notifications a few minutes before each class.
///
/// One weekly-repeating request per meeting, rebuilt from scratch whenever the
/// schedule or the settings change — cheaper to reason about than diffing, and
/// the whole set is well under the 64-pending-request cap.
/// ponytail: full rebuild per change; only worth diffing if the cap is ever near.
@MainActor
final class Notifier: ObservableObject {
    /// One per process, for the same reason `CalendarBridge` keeps one
    /// `EKEventStore`: `UNUserNotificationCenter.current()` *is* a singleton,
    /// and two wrappers around it would each clear the other's pending
    /// requests. Shared rather than injected so Settings and the calendar can
    /// reach it without threading it through the app's scene.
    static let shared = Notifier()

    /// `nil` until asked. Drives whether Settings shows a toggle or a "turn it
    /// on in System Settings" button.
    @Published private(set) var authorization: UNAuthorizationStatus?

    private let center: UNUserNotificationCenter?

    init() {
        // `UNUserNotificationCenter.current()` traps in a process with no bundle
        // identifier — `swift run` and the test bundle both qualify.
        center = Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func refreshAuthorization() async {
        guard let center else { return }
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Asked when the user turns notifications on, never at launch — a
    /// permission prompt before the app has shown anything is just noise.
    ///
    /// Returns whether notifications can actually fire now.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard let center else { return false }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshAuthorization()
        return granted
    }

    /// What every call site actually wants. Kept here rather than repeated at
    /// each one because Settings and the calendar both have to rebuild — the
    /// calendar isn't even alive while Settings is on screen, so it can't be
    /// the only place this happens.
    func sync(_ sessions: [ClassSession], _ preferences: Preferences, now: Date = .now) {
        reschedule(
            sessions,
            leadMinutes: preferences.notificationLeadMinutes,
            skipping: preferences.vacantSessionIDs,
            enabled: preferences.notificationsEnabled,
            time: { session, date in
                preferences.time(for: session, on: Weekday.weekStart(containing: date))
            },
            isVacantThisWeek: { session, date in
                preferences.status(for: session, on: Weekday.weekStart(containing: date)) == .vacant
            },
            now: now
        )
    }

    /// One session's reminder shape. `UNCalendarNotificationTrigger` can repeat
    /// weekly or fire once — it has no way to skip or shift a *single*
    /// occurrence of a repeating trigger, so a session whose time varies across
    /// the horizon can't stay a simple weekly trigger.
    enum Plan: Equatable {
        /// The common case: time doesn't vary week to week (no override, or a
        /// term-wide override applying uniformly) — one repeating trigger.
        case weekly(day: Weekday, start: Int)
        /// At least one week in the horizon resolves differently — one dated,
        /// non-repeating trigger per non-vacant week, each at its own time.
        case dated([Occurrence])

        struct Occurrence: Equatable {
            /// Midnight of the occurrence's day.
            let midnight: Date
            let start: Int
        }
    }

    /// Pure and `nonisolated` on purpose — no `Preferences` access, so it's
    /// testable without `UNUserNotificationCenter` or `@MainActor`. Callers
    /// supply the per-week resolution as closures over a `Date`.
    ///
    /// `ponytail: horizonWeeks` bounds a dated session to ~2 months of reminders
    /// before it needs `reschedule` to run again (which already happens on
    /// every app open/refresh) — revisit only if someone overrides most of
    /// their schedule and goes quiet on the app for longer than that.
    nonisolated static func plan(
        for session: ClassSession,
        now: Date,
        horizonWeeks: Int = 8,
        resolvedStart: (Date) -> Int,
        isVacant: (Date) -> Bool,
        calendar: Calendar = .current
    ) -> Plan {
        let thisWeek = Weekday.weekStart(containing: now, calendar: calendar)
        let weekStarts = (0..<horizonWeeks).compactMap {
            calendar.date(byAdding: .day, value: $0 * 7, to: thisWeek)
        }
        let starts = weekStarts.map(resolvedStart)

        guard let first = starts.first, starts.allSatisfy({ $0 == first }) else {
            let occurrences = zip(weekStarts, starts).compactMap { weekStart, start -> Plan.Occurrence? in
                guard !isVacant(weekStart) else { return nil }
                return Plan.Occurrence(midnight: session.day.date(inWeekStarting: weekStart, calendar: calendar), start: start)
            }
            return .dated(occurrences)
        }
        return .weekly(day: session.day, start: first)
    }

    /// Rebuilds every pending reminder. Called on any change to the schedule,
    /// the vacant markers, the two notification preferences, or a time move.
    func reschedule(
        _ sessions: [ClassSession],
        leadMinutes: Int,
        skipping vacant: Set<String>,
        enabled: Bool,
        time: (ClassSession, Date) -> (Int, Int) = { s, _ in (s.start, s.end) },
        isVacantThisWeek: (ClassSession, Date) -> Bool = { _, _ in false },
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        guard let center else { return }
        center.removeAllPendingNotificationRequests()

        guard enabled, authorization == .authorized else { return }

        for session in sessions where !vacant.contains(session.id) {
            let plan = Self.plan(
                for: session, now: now,
                resolvedStart: { time(session, $0).0 },
                isVacant: { isVacantThisWeek(session, $0) },
                calendar: calendar
            )

            switch plan {
            case .weekly(let day, let start):
                guard let trigger = Self.weeklyTrigger(day: day, start: start, leadMinutes: leadMinutes) else { continue }
                center.add(UNNotificationRequest(
                    identifier: session.id,
                    content: content(for: session, start: start, leadMinutes: leadMinutes),
                    trigger: trigger
                ))

            case .dated(let occurrences):
                for (index, occurrence) in occurrences.enumerated() {
                    guard let classStart = calendar.date(byAdding: .minute, value: occurrence.start, to: occurrence.midnight),
                          let fireDate = calendar.date(byAdding: .minute, value: -leadMinutes, to: classStart),
                          fireDate > now
                    else { continue }

                    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                    center.add(UNNotificationRequest(
                        identifier: "\(session.id)#\(index)",
                        content: content(for: session, start: occurrence.start, leadMinutes: leadMinutes),
                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    ))
                }
            }
        }
    }

    /// Subject code and time only. Faculty names never leave the grid — the
    /// same rule that keeps them out of logs and fixtures. `start` is the
    /// resolved time for this occurrence, never `session.start` directly.
    private func content(for session: ClassSession, start: Int, leadMinutes: Int) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = session.subjectCode
        content.body = leadMinutes == 0
            ? "\(session.description) starts now."
            : "\(session.description) starts at \(ClassSession.format(start))."
        content.sound = .default
        return content
    }

    private nonisolated static func weeklyTrigger(
        day: Weekday,
        start: Int,
        leadMinutes: Int
    ) -> UNCalendarNotificationTrigger? {
        let fire = fireTime(day: day, start: start, leadMinutes: leadMinutes)

        // `EKWeekday` counts from Sunday = 1, which is exactly what
        // `DateComponents.weekday` wants — reused rather than re-derived.
        let components = DateComponents(
            hour: fire.minutes / 60,
            minute: fire.minutes % 60,
            weekday: fire.day.ekWeekday.rawValue
        )
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    }

    /// When the reminder for a meeting should fire, as a weekday and
    /// minutes-from-midnight.
    ///
    /// A lead time that runs back past midnight belongs to the *previous* day —
    /// otherwise a 12:30am class with a 30-minute lead asks to fire at minute
    /// zero of a day that has no minute zero to spare, and never fires at all.
    nonisolated static func fireTime(day: Weekday, start: Int, leadMinutes: Int) -> (day: Weekday, minutes: Int) {
        var day = day
        var minutes = start - leadMinutes

        if minutes < 0 {
            minutes += 24 * 60
            day = Weekday(rawValue: day.rawValue == 1 ? 7 : day.rawValue - 1) ?? day
        }

        return (day, minutes)
    }
}
