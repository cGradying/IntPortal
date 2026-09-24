import XCTest
@testable import PUPSISPortal

/// Spec 11 upgrades 1, 2, 3, 4, 6, 7 — the pure `Core/Study/` models. Every
/// assertion below is a literal expected value: these types have no UI to
/// eyeball, so the test is the only evidence they're right.
final class StudyTests: XCTestCase {
    // MARK: Fixtures

    private func card(
        front: String = "Q", back: String = "A", subject: String = "COMP 001",
        due: Date = Date(), stability: Double = 0, reps: Int = 0, lapses: Int = 0
    ) -> QuizCard {
        QuizCard(
            front: front, back: back, subject: subject, citation: "test",
            fsrs: FSRSState(due: due, stability: stability, difficulty: 0, reps: reps, lapses: lapses, lastReviewed: nil)
        )
    }

    private func deck(name: String = "Deck", sourceQuery: String = "topic", cards: [QuizCard]) -> QuizDeck {
        QuizDeck(name: name, sourceKind: .vaultTopic, sourceQuery: sourceQuery, cards: cards)
    }

    private func utc() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ calendar: Calendar, y: Int, m: Int, d: Int, h: Int = 9, min: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = h; comps.minute = min
        return calendar.date(from: comps)!
    }

    // MARK: Mastery (spec upgrade 3)

    /// Lane 2: a new deck reads 0%, not `1 − due/total` (which would read
    /// 0% too here by coincidence, but for the wrong reason — see the
    /// "grown" case below for why the old formula actually broke).
    func testMasteryOfNewDeckIsZero() {
        let cards = [card(reps: 0), card(reps: 0)]
        XCTAssertEqual(Mastery.of(cards: cards), 0)
    }

    /// Lane 3: two Good reviews a week apart is exactly the "reps ≥ 2,
    /// stability ≥ 7 days, last rating ≠ Again" bar — the card counts as
    /// mastered.
    func testMasteryAfterTwoGoodReviewsAWeekApart() {
        let now = Date()
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let masteredCard = card(due: now.addingTimeInterval(86_400), stability: 8, reps: 2)
        let freshCard = card(due: now)
        let reviews = [
            QuizReviewRecord(cardID: masteredCard.id, subject: "COMP 001", rating: .good, date: weekAgo),
            QuizReviewRecord(cardID: masteredCard.id, subject: "COMP 001", rating: .good, date: now),
        ]
        XCTAssertEqual(Mastery.of(cards: [masteredCard, freshCard], reviews: reviews), 0.5)
    }

    /// The formula's third clause on its own: high reps and stability don't
    /// save a card whose most recent review actually failed.
    func testMasteryExcludesACardWhoseLastRatingWasAgain() {
        let now = Date()
        let lapsedCard = card(stability: 10, reps: 3)
        let reviews = [QuizReviewRecord(cardID: lapsedCard.id, subject: "COMP 001", rating: .again, date: now)]
        XCTAssertEqual(Mastery.of(cards: [lapsedCard], reviews: reviews), 0)
    }

    // MARK: DueForecast (spec upgrade 4)

    /// Lane 4: buckets are computed with calendar day arithmetic, so a DST
    /// fallback inside the 7-day window (Nov 1 2026 in America/New_York, a
    /// 25-hour day) doesn't shift a card into the wrong bucket the way
    /// `+86400` seconds would.
    func testDueForecastNext7SurvivesDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = date(calendar, y: 2026, m: 10, d: 28)
        let cards = (0..<7).map { offset in
            card(due: calendar.date(byAdding: .day, value: offset, to: start)!)
        }
        XCTAssertEqual(DueForecast.next7(cards: cards, from: start, calendar: calendar), [1, 1, 1, 1, 1, 1, 1])
    }

    /// Today's bucket also catches anything already overdue — "due" already
    /// means "due today or earlier" everywhere else this data is read
    /// (`QuizDeck.dueCards`), so the forecast shouldn't disagree.
    func testDueForecastBucketsOverdueCardsIntoToday() {
        let calendar = utc()
        let today = date(calendar, y: 2026, m: 6, d: 1)
        let overdue = calendar.date(byAdding: .day, value: -3, to: today)!
        let cards = [card(due: overdue), card(due: today)]
        XCTAssertEqual(DueForecast.next7(cards: cards, from: today, calendar: calendar)[0], 2)
    }

    // MARK: GapSuggestion (spec upgrade 1)

    /// Lane 5: two decks tie on due count; the one with the nearer linked
    /// exam wins.
    func testGapSuggestionTieBreaksOnNearerExam() {
        let calendar = utc()
        let now = date(calendar, y: 2026, m: 9, d: 20)
        let nearDeck = deck(name: "Near", cards: [card(due: now), card(due: now), card(due: now)])
        let farDeck = deck(name: "Far", cards: [card(due: now), card(due: now), card(due: now)])
        let gaps = [StudyGap(start: 540, end: 600)]
        let exams: [UUID: Date] = [
            nearDeck.id: date(calendar, y: 2026, m: 9, d: 22),
            farDeck.id: date(calendar, y: 2026, m: 10, d: 5),
        ]
        let suggestion = GapSuggestion.make(
            gaps: gaps, decks: [farDeck, nearDeck], now: now, examDates: exams, calendar: calendar
        )
        XCTAssertEqual(suggestion?.deck.id, nearDeck.id)
    }

    /// Lane 6: a 10-minute gap caps the estimate even though the due count
    /// alone would ask for 12.
    func testGapSuggestionCapsMinutesAtGapRemaining() {
        let calendar = utc()
        let now = date(calendar, y: 2026, m: 9, d: 20)
        let bigDeck = deck(cards: (0..<6).map { _ in card(due: now) })
        let gaps = [StudyGap(start: 540, end: 550)]
        let suggestion = GapSuggestion.make(gaps: gaps, decks: [bigDeck], now: now, calendar: calendar)
        XCTAssertEqual(suggestion?.dueCount, 6)
        XCTAssertEqual(suggestion?.minutes, 10)
        XCTAssertEqual(suggestion?.mode, .flashcard)
    }

    // MARK: ExamLink (spec upgrade 2)

    /// Lane 7: same subject isn't enough — no lecture before the exam
    /// shares a topic word with the deck, so nothing links.
    func testExamLinkFindsNoDeckWithoutASharedTopicToken() {
        let calendar = utc()
        let exam = SyllabusItem(
            subjectCode: "COMP 001", topic: "Midterm", date: date(calendar, y: 2026, m: 9, d: 27),
            type: .exam, source: .manual
        )
        let lecture = SyllabusItem(
            subjectCode: "COMP 001", topic: "Boolean algebra", date: date(calendar, y: 2026, m: 9, d: 10),
            type: .lecture, source: .manual
        )
        let unrelatedDeck = deck(
            name: "Sorting algorithms", sourceQuery: "sorting algorithms", cards: [card(subject: "COMP 001")]
        )
        XCTAssertEqual(ExamLink.decks(for: exam, in: [unrelatedDeck], lectures: [lecture]), [])
    }

    /// A deck links when its subject matches and its name shares a topic
    /// word with a lecture that came before the exam. A same-named deck on
    /// a different subject, and a same-topic lecture *after* the exam,
    /// don't count.
    func testExamLinkFindsADeckSharingATopicTokenWithAPriorLecture() {
        let calendar = utc()
        let exam = SyllabusItem(
            subjectCode: "COMP 001", topic: "Midterm", date: date(calendar, y: 2026, m: 9, d: 27),
            type: .exam, source: .manual
        )
        let priorLecture = SyllabusItem(
            subjectCode: "COMP 001", topic: "Number systems", date: date(calendar, y: 2026, m: 9, d: 10),
            type: .lecture, source: .manual
        )
        let lectureAfterExam = SyllabusItem(
            subjectCode: "COMP 001", topic: "Number systems", date: date(calendar, y: 2026, m: 10, d: 1),
            type: .lecture, source: .manual
        )
        let matchingDeck = deck(
            name: "Number systems", sourceQuery: "number systems", cards: [card(subject: "COMP 001")]
        )
        let wrongSubjectDeck = deck(
            name: "Number systems", sourceQuery: "number systems", cards: [card(subject: "MATH 001")]
        )
        let linked = ExamLink.decks(
            for: exam, in: [matchingDeck, wrongSubjectDeck], lectures: [priorLecture, lectureAfterExam]
        )
        XCTAssertEqual(linked, [matchingDeck])
    }

    // MARK: StudyMap (spec upgrade 6)

    /// Lane 8: tower height climbs as the exam nears, and caps rather than
    /// growing without bound for an overdue exam.
    func testStudyMapTowerHeightRisesMonotonicallyAndCaps() {
        let days = stride(from: 10, through: -3, by: -1).map { $0 }
        let heights = days.map(StudyMap.towerHeight(daysAway:))
        for i in 1..<heights.count {
            XCTAssertGreaterThanOrEqual(heights[i], heights[i - 1])
        }
        XCTAssertEqual(heights.last, StudyMap.maxTowerHeight)
        XCTAssertLessThanOrEqual(heights.max() ?? 0, StudyMap.maxTowerHeight)
    }

    /// Tile count and the lecture-topics-fallback-to-deck-names rule.
    func testStudyMapFallsBackToDeckNamesWithoutLectureTopics() {
        let withLectures = StudyMap.Subject(
            code: "COMP 001", lectureTopics: ["Boolean algebra", "Number systems"], deckNames: ["Ignored"],
            mastery: ["Number systems": 0.8], examDaysAway: ["Number systems": 4]
        )
        let withoutLectures = StudyMap.Subject(
            code: "MATH 001", lectureTopics: [], deckNames: ["Derivatives", "Integrals"],
            mastery: [:], examDaysAway: [:]
        )
        let tiles = StudyMap.layout(subjects: [withLectures, withoutLectures])

        XCTAssertEqual(tiles.count, 4)
        XCTAssertEqual(tiles.map(\.topic), ["Boolean algebra", "Number systems", "Derivatives", "Integrals"])

        let numberSystems = tiles.first { $0.topic == "Number systems" }
        XCTAssertEqual(numberSystems?.goldPip, true)
        XCTAssertEqual(numberSystems?.towerHeight ?? 0, 1.9, accuracy: 0.0001)

        let derivatives = tiles.first { $0.topic == "Derivatives" }
        XCTAssertEqual(derivatives?.goldPip, false)
        XCTAssertNil(derivatives?.towerHeight)
    }

    // MARK: WeakList (spec upgrade 7)

    /// Lane 9: top 3 by Again count in the last 30 days, oldest excluded.
    func testWeakListOrdersByAgainCountInTheLast30Days() {
        let calendar = utc()
        let now = date(calendar, y: 2026, m: 9, d: 24)
        let tooOld = calendar.date(byAdding: .day, value: -40, to: now)!

        let worst = card(front: "Worst")
        let middle = card(front: "Middle")
        let mild = card(front: "Mild")
        let ignoredOld = card(front: "Old")
        let weakDeck = deck(cards: [worst, middle, mild, ignoredOld])

        func again(_ target: QuizCard, _ date: Date) -> QuizReviewRecord {
            QuizReviewRecord(cardID: target.id, subject: "COMP 001", rating: .again, date: date)
        }
        let reviews: [UUID: [QuizReviewRecord]] = [
            weakDeck.id: [
                again(worst, now), again(worst, now), again(worst, now),
                again(middle, now), again(middle, now),
                again(mild, now),
                again(ignoredOld, tooOld),
            ]
        ]

        let top = WeakList.top3(decks: [weakDeck], reviews: reviews, now: now, calendar: calendar)
        XCTAssertEqual(top.map(\.cardFront), ["Worst", "Middle", "Mild"])
        XCTAssertEqual(top.map(\.againCount), [3, 2, 1])
        XCTAssertEqual(top.map(\.deckName), [weakDeck.name, weakDeck.name, weakDeck.name])
    }

    // MARK: Performance

    /// `StudyMap.layout` + `DueForecast.next7` over 2,000 cards, 10 runs.
    /// Budget is 10ms/run; asserted against 50ms since CI hardware varies —
    /// the real measured number is printed for the report either way.
    func testStudyMapAndDueForecastStayFastAt2000Cards() {
        let calendar = utc()
        let now = date(calendar, y: 2026, m: 9, d: 24)
        let cards = (0..<2000).map { i in card(due: calendar.date(byAdding: .hour, value: i, to: now)!) }
        let subject = StudyMap.Subject(
            code: "COMP 001", lectureTopics: (0..<2000).map { "Topic \($0)" }, deckNames: [],
            mastery: [:], examDaysAway: [:]
        )

        var durations: [Double] = []
        for _ in 0..<10 {
            let start = Date()
            _ = StudyMap.layout(subjects: [subject])
            _ = DueForecast.next7(cards: cards, from: now, calendar: calendar)
            durations.append(Date().timeIntervalSince(start))
        }
        let average = durations.reduce(0, +) / Double(durations.count)
        let worst = durations.max() ?? 0
        print("StudyMap.layout + DueForecast.next7 @ 2,000 cards: avg \(average * 1000)ms, worst \(worst * 1000)ms over 10 runs")
        XCTAssertLessThan(average, 0.05)
    }
}
