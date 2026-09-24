import XCTest
@testable import PUPSISPortal

/// Pure merge logic for `SyllabusImportSheet`'s re-import path — no store, no
/// view, so this is a plain XCTestCase like `GradesParser`'s tests.
final class SyllabusReimportTests: XCTestCase {
    private func item(week: Int? = 3, topic: String, type: SyllabusItemType = .lecture) -> SyllabusItem {
        SyllabusItem(subjectCode: "MATH01", week: week, topic: topic, type: type, source: .imported)
    }

    func testDropsItemsThatDuplicateAnExistingWeekTypeAndTopic() {
        let existing = [item(week: 3, topic: "Limits")]
        let reimported = [item(week: 3, topic: "Limits"), item(week: 4, topic: "Derivatives")]

        let toAdd = SyllabusReimport.itemsToAdd(from: reimported, existing: existing, subjectCode: "MATH01")

        XCTAssertEqual(toAdd.map(\.topic), ["Derivatives"])
    }

    /// Topic matching ignores case and surrounding whitespace — a
    /// re-extraction can reproduce the same topic with slightly different
    /// wrapping without it counting as a new item.
    func testDuplicateMatchIgnoresCaseAndWhitespace() {
        let existing = [item(week: 3, topic: "Limits")]
        let reimported = [item(week: 3, topic: "  limits  ")]

        let toAdd = SyllabusReimport.itemsToAdd(from: reimported, existing: existing, subjectCode: "MATH01")

        XCTAssertTrue(toAdd.isEmpty)
    }

    /// Same topic text but a different week or type is a genuinely different
    /// item (e.g. a recurring "Quiz" topic each week), not a duplicate.
    func testDifferentWeekOrTypeIsNotADuplicate() {
        let existing = [item(week: 3, topic: "Quiz", type: .quiz)]
        let reimported = [item(week: 4, topic: "Quiz", type: .quiz), item(week: 3, topic: "Quiz", type: .exam)]

        let toAdd = SyllabusReimport.itemsToAdd(from: reimported, existing: existing, subjectCode: "MATH01")

        XCTAssertEqual(toAdd.count, 2)
    }

    /// Every kept item gets the trimmed subject code, not whatever whitespace
    /// was left in the picker's text field.
    func testAddedItemsGetTheTrimmedSubjectCode() {
        let toAdd = SyllabusReimport.itemsToAdd(from: [item(topic: "New")], existing: [], subjectCode: "MATH01")
        XCTAssertEqual(toAdd.first?.subjectCode, "MATH01")
    }

    func testCarriesOverScoresByMatchingComponentName() {
        let existing = [
            GradingComponent(name: "Midterm", weight: 30, score: 88),
            GradingComponent(name: "Final", weight: 70, score: nil),
        ]
        let reimported = [
            GradingComponent(name: "Midterm", weight: 30),
            GradingComponent(name: "Final", weight: 70),
            GradingComponent(name: "Project", weight: 10),
        ]

        let merged = SyllabusReimport.componentsCarryingScores(from: reimported, existing: existing)

        XCTAssertEqual(merged.first { $0.name == "Midterm" }?.score, 88)
        XCTAssertNil(merged.first { $0.name == "Final" }?.score)
        XCTAssertNil(merged.first { $0.name == "Project" }?.score) // no prior component to carry from
    }

    func testScoreCarryOverIgnoresCaseAndWhitespaceInName() {
        let existing = [GradingComponent(name: "  midterm exam  ", weight: 30, score: 95)]
        let reimported = [GradingComponent(name: "Midterm Exam", weight: 30)]

        let merged = SyllabusReimport.componentsCarryingScores(from: reimported, existing: existing)

        XCTAssertEqual(merged.first?.score, 95)
    }
}
