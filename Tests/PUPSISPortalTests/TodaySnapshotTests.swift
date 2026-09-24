import SwiftUI
import XCTest
@testable import PUPSISPortal

/// `TodayScreen` at fixed times, so a class in session, a free gap with a due
/// deck, an empty day and a syllabus exam 4 days out are each pinned to a
/// known clock rather than "whatever `Date()` is when the test runs."
@MainActor
final class TodaySnapshotTests: XCTestCase {
    /// A Wednesday. `Weekday.on` reads it from `.current`, same as every
    /// other fixed-date test in this suite (`AssistantScheduleSnapshotTests`).
    private static func wednesday(hour: Int, minute: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 9, day: 23, hour: hour, minute: minute)
        )!
    }

    /// COMP 002 meets 9:00–10:30, COMP 001 meets 11:00–12:30 — a 30-minute
    /// gap between them, long enough for a "Study in this gap" row.
    private static let sessions: [ClassSession] = [
        ClassSession(subjectCode: "COMP 002", description: "Computer Programming 1", faculty: "Prof. Sample", day: .wednesday, start: 540, end: 630),
        ClassSession(subjectCode: "COMP 001", description: "Introduction to Computing", faculty: "Prof. Sample", day: .wednesday, start: 660, end: 750),
    ]

    private func preferences() -> Preferences {
        let name = "TodaySnapshotTests-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return Preferences(defaults: suite)
    }

    /// A fresh on-disk store per test, in a throwaway temp directory — never
    /// the real Application Support.
    private func quizzes(dueCards: Int = 0) -> QuizStore {
        let store = QuizStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        guard dueCards > 0 else { return store }
        var deck = QuizDeck(name: "Number systems", sourceKind: .vaultTopic, sourceQuery: "Number systems")
        deck.cards = (0..<dueCards).map { i in
            QuizCard(front: "Q\(i)", back: "A\(i)", subject: "COMP 002", citation: "", fsrs: .new(now: .distantPast))
        }
        store.addDeck(deck)
        return store
    }

    private func syllabus(examInDays: Int? = nil, from now: Date) -> SyllabusStore {
        let store = SyllabusStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json"))
        if let examInDays {
            let date = Calendar.current.date(byAdding: .day, value: examInDays, to: Calendar.current.startOfDay(for: now))!
            store.addItem(SyllabusItem(subjectCode: "COMP 001", topic: "Midterm exam", date: date, type: .exam, source: .manual))
        }
        return store
    }

    private func screen(
        now: Date, sessions: [ClassSession] = TodaySnapshotTests.sessions,
        quizzes: QuizStore? = nil, syllabus: SyllabusStore? = nil
    ) -> some View {
        TodayScreen(
            preferences: preferences(), calendar: CalendarBridge(),
            quizzes: quizzes ?? self.quizzes(), syllabus: syllabus ?? self.syllabus(from: now),
            sessions: sessions, grades: nil, now: now, scrolls: false
        )
        // `.top`, not the frame default `.center` — TodayScreen has no
        // `maxHeight: .infinity` of its own (like `NotebookScreen`, it
        // leaves the window's own ground wash to fill the rest), so a
        // shorter day would otherwise render vertically centered in this
        // fixed test frame instead of pinned to the header the way the real
        // shell lays it out.
        .frame(width: 900, height: 760, alignment: .top)
    }

    func testDuringAClass() throws {
        let now = Self.wednesday(hour: 9, minute: 30) // inside COMP 002, 9:00–10:30
        let light = try Snapshot.render(screen(now: now), name: "today-in-session-light", palette: .registrar, scheme: .light)
        try Snapshot.render(screen(now: now), name: "today-in-session-dark", palette: .registrarNight, scheme: .dark)
        XCTAssertGreaterThan(light.size.height, 200)
    }

    func testFreeGapWithDueDeck() throws {
        let now = Self.wednesday(hour: 10, minute: 45) // inside the 10:30–11:00 gap
        let image = try Snapshot.render(
            screen(now: now, quizzes: quizzes(dueCards: 6)), name: "today-gap-due-deck", palette: .registrar, scheme: .light
        )
        XCTAssertGreaterThan(image.size.height, 200)
    }

    func testEmptyDay() throws {
        let now = Self.wednesday(hour: 9, minute: 0)
        let image = try Snapshot.render(screen(now: now, sessions: []), name: "today-empty-day", palette: .registrar, scheme: .light)
        XCTAssertGreaterThan(image.size.height, 200)
    }

    func testExamFourDaysOut() throws {
        let now = Self.wednesday(hour: 9, minute: 0)
        let image = try Snapshot.render(
            screen(now: now, syllabus: syllabus(examInDays: 4, from: now)), name: "today-exam-due-soon", palette: .registrar, scheme: .light
        )
        XCTAssertGreaterThan(image.size.height, 200)
    }

    /// UI scale 140 — the rail is a fixed 280pt column, so this is the one
    /// most likely to clip as text grows. Rendered for a human to read
    /// against the prototype, the same way `ShellSnapshotTests` checks scale.
    func testUIScale140() throws {
        let now = Self.wednesday(hour: 9, minute: 30)
        try Snapshot.render(
            screen(now: now, syllabus: syllabus(examInDays: 4, from: now)),
            name: "today-scale-140", palette: .registrar, scheme: .light, scale: 1.4
        )
    }
}
