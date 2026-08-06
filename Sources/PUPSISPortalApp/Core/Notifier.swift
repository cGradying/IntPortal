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
    func sync(_ sessions: [ClassSession], _ preferences: Preferences) {
        reschedule(
            sessions,
            leadMinutes: preferences.notificationLeadMinutes,
            skipping: preferences.vacantSessionIDs,
            enabled: preferences.notificationsEnabled
        )
    }

    /// Rebuilds every pending reminder. Called on any change to the schedule,
    /// the vacant markers, or the two notification preferences.
    func reschedule(
        _ sessions: [ClassSession],
        leadMinutes: Int,
        skipping vacant: Set<String>,
        enabled: Bool
    ) {
        guard let center else { return }
        center.removeAllPendingNotificationRequests()

        guard enabled, authorization == .authorized else { return }

        for session in sessions where !vacant.contains(session.id) {
            guard let trigger = Self.trigger(for: session, leadMinutes: leadMinutes) else { continue }
            center.add(UNNotificationRequest(
                identifier: session.id,
                content: content(for: session, leadMinutes: leadMinutes),
                trigger: trigger
            ))
        }
    }

    /// Subject code and time only. Faculty names never leave the grid — the
    /// same rule that keeps them out of logs and fixtures.
    private func content(for session: ClassSession, leadMinutes: Int) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = session.subjectCode
        content.body = leadMinutes == 0
            ? "\(session.description) starts now."
            : "\(session.description) starts at \(ClassSession.format(session.start))."
        content.sound = .default
        return content
    }

    private nonisolated static func trigger(
        for session: ClassSession,
        leadMinutes: Int
    ) -> UNCalendarNotificationTrigger? {
        let fire = fireTime(for: session, leadMinutes: leadMinutes)

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
    nonisolated static func fireTime(for session: ClassSession, leadMinutes: Int) -> (day: Weekday, minutes: Int) {
        var day = session.day
        var minutes = session.start - leadMinutes

        if minutes < 0 {
            minutes += 24 * 60
            day = Weekday(rawValue: day.rawValue == 1 ? 7 : day.rawValue - 1) ?? day
        }

        return (day, minutes)
    }
}
