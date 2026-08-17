import SwiftUI
import XCTest
@testable import PUPSISPortal

/// Each test gets its own defaults suite — never `.standard`, which holds the
/// user's real settings.
@MainActor
final class PreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "PreferencesTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaultsToMatchingTheSystem() {
        XCTAssertEqual(Preferences(defaults: defaults).theme, .auto)
    }

    func testThemeSurvivesRelaunch() {
        Preferences(defaults: defaults).theme = .astraMoon

        XCTAssertEqual(Preferences(defaults: defaults).theme, .astraMoon)
    }

    /// The whole point of the override: it has to beat the seeded default.
    func testCustomColorWinsOverThePaletteDefault() throws {
        let prefs = Preferences(defaults: defaults)
        let seeded = prefs.color(for: "COMP 20073", in: .pupMaroon)

        prefs.setColor(Color(red: 0, green: 0.5, blue: 1), for: "COMP 20073")
        let chosen = prefs.color(for: "COMP 20073", in: .pupMaroon)

        XCTAssertNotEqual(chosen.hex, seeded.hex)
        XCTAssertEqual(chosen.hex, "#0080FF")
    }

    func testCustomColorSurvivesRelaunch() {
        Preferences(defaults: defaults).setColor(Color(red: 1, green: 0, blue: 0), for: "COMP 20073")

        let reloaded = Preferences(defaults: defaults)
        XCTAssertTrue(reloaded.hasCustomColor(for: "COMP 20073"))
        XCTAssertEqual(reloaded.color(for: "COMP 20073", in: .pupMaroon).hex, "#FF0000")
    }

    func testResetFallsBackToTheSeededDefault() {
        let prefs = Preferences(defaults: defaults)
        let seeded = prefs.color(for: "COMP 20073", in: .pupMaroon)

        prefs.setColor(Color(red: 1, green: 0, blue: 0), for: "COMP 20073")
        prefs.resetColor(for: "COMP 20073")

        XCTAssertFalse(prefs.hasCustomColor(for: "COMP 20073"))
        XCTAssertEqual(prefs.color(for: "COMP 20073", in: .pupMaroon).hex, seeded.hex)
    }

    // MARK: Online strip colour (per subject)

    func testStripColorDefaultsToThePaletteStrip() {
        XCTAssertEqual(
            Preferences(defaults: defaults).stripColor(for: "COMP 20073", in: .pupMaroon).hex,
            Palette.pupMaroon.onlineStrip.hex
        )
    }

    func testCustomStripColorWinsAndSurvivesRelaunch() {
        Preferences(defaults: defaults).setStripColor(Color(red: 0, green: 0.5, blue: 1), for: "COMP 20073")

        let reloaded = Preferences(defaults: defaults)
        XCTAssertTrue(reloaded.hasCustomStripColor(for: "COMP 20073"))
        XCTAssertEqual(reloaded.stripColor(for: "COMP 20073", in: .pupMaroon).hex, "#0080FF")
    }

    func testResettingAStripColorFallsBackToThePaletteStrip() {
        let prefs = Preferences(defaults: defaults)

        prefs.setStripColor(Color(red: 1, green: 0, blue: 0), for: "COMP 20073")
        prefs.resetStripColor(for: "COMP 20073")

        XCTAssertFalse(prefs.hasCustomStripColor(for: "COMP 20073"))
        XCTAssertEqual(prefs.stripColor(for: "COMP 20073", in: .pupMaroon).hex, Palette.pupMaroon.onlineStrip.hex)
    }

    /// One subject's strip must not leak onto another, and must not touch its
    /// fill colour — separate namespaces.
    func testStripColorIsScopedAndSeparateFromTheFill() {
        let prefs = Preferences(defaults: defaults)
        let otherStrip = prefs.stripColor(for: "GEED 005", in: .pupMaroon)
        let ownFill = prefs.color(for: "COMP 20073", in: .pupMaroon)

        prefs.setStripColor(Color(red: 1, green: 0, blue: 0), for: "COMP 20073")

        XCTAssertEqual(prefs.stripColor(for: "GEED 005", in: .pupMaroon).hex, otherStrip.hex)
        XCTAssertEqual(prefs.color(for: "COMP 20073", in: .pupMaroon).hex, ownFill.hex)
        XCTAssertFalse(prefs.hasCustomColor(for: "COMP 20073"))
    }

    private let tuesday = ClassSession(subjectCode: "COMP 20073", description: "Data Structures",
                                       faculty: "SANTOS, JUAN", day: .tuesday,
                                       start: 14 * 60, end: 16 * 60)
    private let friday = ClassSession(subjectCode: "COMP 20073", description: "Data Structures",
                                      faculty: "SANTOS, JUAN", day: .friday,
                                      start: 13 * 60 + 30, end: 16 * 60 + 30)

    private let week1 = Date(timeIntervalSince1970: 1_754_006_400) // a Monday
    private let week2 = Date(timeIntervalSince1970: 1_754_611_200) // the next Monday

    func testStatusDefaultsToInPerson() {
        XCTAssertEqual(Preferences(defaults: defaults).status(for: tuesday, on: week1), .regular)
    }

    func testAWeekStatusSurvivesRelaunch() {
        Preferences(defaults: defaults).setStatus(.online, for: tuesday, on: week1)

        XCTAssertEqual(Preferences(defaults: defaults).status(for: tuesday, on: week1), .online)
    }

    /// The whole point of the fix: a status set in one week must not appear in
    /// another. Keying by session alone was the bug.
    func testAWeekStatusDoesNotLeakIntoOtherWeeks() {
        let prefs = Preferences(defaults: defaults)

        prefs.setStatus(.online, for: tuesday, on: week1)

        XCTAssertEqual(prefs.status(for: tuesday, on: week1), .online)
        XCTAssertEqual(prefs.status(for: tuesday, on: week2), .regular)
    }

    /// The term default applies to every week that has no exception of its own.
    func testTermStatusAppliesToEveryWeekWithoutAnException() {
        let prefs = Preferences(defaults: defaults)

        prefs.setTermStatus(.online, for: tuesday)

        XCTAssertEqual(prefs.status(for: tuesday, on: week1), .online)
        XCTAssertEqual(prefs.status(for: tuesday, on: week2), .online)
    }

    /// A one-week exception wins over the term default, and only for its week.
    func testAWeekExceptionOverridesTheTermDefault() {
        let prefs = Preferences(defaults: defaults)

        prefs.setTermStatus(.online, for: tuesday)
        prefs.setStatus(.vacant, for: tuesday, on: week1)

        XCTAssertEqual(prefs.status(for: tuesday, on: week1), .vacant)
        XCTAssertEqual(prefs.status(for: tuesday, on: week2), .online)
    }

    /// A week status equal to the term default isn't a real exception, so it
    /// shouldn't be stored.
    func testAWeekStatusMatchingTheTermDefaultStoresNothing() {
        let prefs = Preferences(defaults: defaults)

        prefs.setTermStatus(.online, for: tuesday)
        prefs.setStatus(.online, for: tuesday, on: week1)

        XCTAssertTrue(prefs.occurrenceStatuses.isEmpty)
    }

    /// Status is per meeting, not per subject — same course, two days, one of
    /// them online. Keying this by subject code would be the obvious bug.
    func testStatusIsScopedToOneMeetingNotTheWholeSubject() {
        let prefs = Preferences(defaults: defaults)

        prefs.setStatus(.vacant, for: tuesday, on: week1)

        XCTAssertEqual(prefs.status(for: tuesday, on: week1), .vacant)
        XCTAssertEqual(prefs.status(for: friday, on: week1), .regular)
    }

    /// Marks made before status went per-week were keyed by session alone, under
    /// the `sessionStatuses` key. They must load as term defaults, not vanish.
    func testLegacyStatusesLoadAsTermDefaults() throws {
        let legacy = try JSONEncoder().encode(["\(tuesday.id)": SessionStatus.online])
        defaults.set(legacy, forKey: "sessionStatuses")

        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.termStatus(for: tuesday), .online)
        XCTAssertEqual(prefs.status(for: tuesday, on: week1), .online)
    }

    /// Reminders and next-class honour term-vacant only — a one-week vacancy
    /// can't be dropped from a weekly-recurring trigger.
    func testVacantSessionIDsReflectTermVacantNotAOneWeekVacant() {
        let prefs = Preferences(defaults: defaults)

        prefs.setStatus(.vacant, for: tuesday, on: week1)
        XCTAssertTrue(prefs.vacantSessionIDs.isEmpty)

        prefs.setTermStatus(.vacant, for: tuesday)
        XCTAssertEqual(prefs.vacantSessionIDs, [tuesday.id])
    }

    // MARK: Time overrides (this week / every week)

    func testTimeDefaultsToTheScrapedSchedule() {
        let (start, end) = Preferences(defaults: defaults).time(for: tuesday, on: week1)
        XCTAssertEqual(start, tuesday.start)
        XCTAssertEqual(end, tuesday.end)
        XCTAssertFalse(Preferences(defaults: defaults).isTimeOverridden(tuesday, on: week1))
    }

    /// This week only — the exact "prof moved it just this once" case.
    func testAWeekTimeDoesNotLeakIntoOtherWeeks() {
        let prefs = Preferences(defaults: defaults)

        prefs.setTime(TimeOverride(start: 13 * 60 + 30, end: 15 * 60 + 30), for: tuesday, on: week1)

        XCTAssertEqual(prefs.time(for: tuesday, on: week1).start, 13 * 60 + 30)
        XCTAssertTrue(prefs.isTimeOverridden(tuesday, on: week1))
        XCTAssertEqual(prefs.time(for: tuesday, on: week2).start, tuesday.start, "a different week is untouched")
        XCTAssertFalse(prefs.isTimeOverridden(tuesday, on: week2))
    }

    /// Every week — the recurring move.
    func testATermTimeAppliesToEveryWeek() {
        let prefs = Preferences(defaults: defaults)

        prefs.setTermTime(TimeOverride(start: 13 * 60 + 30, end: 15 * 60 + 30), for: tuesday)

        XCTAssertEqual(prefs.time(for: tuesday, on: week1).start, 13 * 60 + 30)
        XCTAssertEqual(prefs.time(for: tuesday, on: week2).start, 13 * 60 + 30)
    }

    /// A week exception still wins over a term-wide move — one further
    /// one-off week on top of an already-permanently-moved class.
    func testAWeekExceptionOverridesTheTermTime() {
        let prefs = Preferences(defaults: defaults)

        prefs.setTermTime(TimeOverride(start: 13 * 60 + 30, end: 15 * 60 + 30), for: tuesday)
        prefs.setTime(TimeOverride(start: 15 * 60, end: 17 * 60), for: tuesday, on: week1)

        XCTAssertEqual(prefs.time(for: tuesday, on: week1).start, 15 * 60)
        XCTAssertEqual(prefs.time(for: tuesday, on: week2).start, 13 * 60 + 30)
    }

    func testClearingATimeOverrideDropsTheKey() {
        let prefs = Preferences(defaults: defaults)

        prefs.setTime(TimeOverride(start: 13 * 60 + 30, end: 15 * 60 + 30), for: tuesday, on: week1)
        prefs.setTime(nil, for: tuesday, on: week1)

        XCTAssertTrue(prefs.occurrenceTimes.isEmpty)
        XCTAssertFalse(prefs.isTimeOverridden(tuesday, on: week1))
    }

    /// Time is scoped per meeting, not per subject — same course, two days,
    /// only one of them moved.
    func testTimeIsScopedToOneMeetingNotTheWholeSubject() {
        let prefs = Preferences(defaults: defaults)

        prefs.setTime(TimeOverride(start: 15 * 60, end: 17 * 60), for: tuesday, on: week1)

        XCTAssertEqual(prefs.time(for: tuesday, on: week1).start, 15 * 60)
        XCTAssertEqual(prefs.time(for: friday, on: week1).start, friday.start)
    }

    func testTimeOverridesSurviveRelaunch() {
        Preferences(defaults: defaults).setTime(
            TimeOverride(start: 13 * 60 + 30, end: 15 * 60 + 30), for: tuesday, on: week1)

        let reloaded = Preferences(defaults: defaults).time(for: tuesday, on: week1)
        XCTAssertEqual(reloaded.start, 13 * 60 + 30)
        XCTAssertEqual(reloaded.end, 15 * 60 + 30)
    }

    /// The trap the whole feature has to avoid: `ClassSession.id` is derived
    /// from start/end (`Models.swift:94`). Applying a time override must never
    /// change the id it's stored under, or the lookup can never find itself
    /// again on the next render.
    func testApplyingATimeOverrideDoesNotChangeTheSessionsID() {
        let prefs = Preferences(defaults: defaults)
        let idBefore = tuesday.id

        prefs.setTime(TimeOverride(start: 13 * 60 + 30, end: 15 * 60 + 30), for: tuesday, on: week1)

        XCTAssertEqual(tuesday.id, idBefore, "the session itself must never be mutated")
        XCTAssertEqual(prefs.time(for: tuesday, on: week1).start, 13 * 60 + 30, "and the override must still resolve")
    }

    func testTermEndDefaultsToAboutASemesterOut() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Manila"))
        let from = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 5)))

        let end = Preferences.defaultTermEnd(from: from, calendar: calendar)

        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: end).month, 12)
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: end).day, 5)
    }

    func testTermEndSurvivesRelaunch() {
        let chosen = Date(timeIntervalSince1970: 1_767_225_600)
        Preferences(defaults: defaults).termEndDate = chosen

        XCTAssertEqual(
            Preferences(defaults: defaults).termEndDate.timeIntervalSince1970,
            chosen.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    /// EventKit has no per-event colour, so this is ours to keep — and it's
    /// keyed by run, so recolouring one day of a connected run recolours all
    /// of it rather than breaking the bar in half.
    func testEventColoursAreKeyedByRunAndSurviveRelaunch() {
        let run = "event-Study-840-960"
        Preferences(defaults: defaults).setEventColor(Color(red: 0, green: 1, blue: 0), for: run)

        let reloaded = Preferences(defaults: defaults)
        XCTAssertTrue(reloaded.hasCustomEventColor(for: run))
        XCTAssertEqual(reloaded.color(forEvent: run, in: .pupMaroon).hex, "#00FF00")
    }

    func testResettingAnEventColourFallsBackToTheSeededDefault() {
        let prefs = Preferences(defaults: defaults)
        let run = "event-Study-840-960"
        let seeded = prefs.color(forEvent: run, in: .pupMaroon)

        prefs.setEventColor(Color(red: 1, green: 0, blue: 0), for: run)
        prefs.resetEventColor(for: run)

        XCTAssertEqual(prefs.color(forEvent: run, in: .pupMaroon).hex, seeded.hex)
    }

    /// Subject colours and event colours are separate namespaces — a class and
    /// an event with the same name must not share a swatch.
    func testEventColoursDoNotLeakIntoSubjectColours() {
        let prefs = Preferences(defaults: defaults)
        let before = prefs.color(for: "COMP 20073", in: .pupMaroon)

        prefs.setEventColor(Color(red: 1, green: 0, blue: 0), for: "COMP 20073")

        XCTAssertEqual(prefs.color(for: "COMP 20073", in: .pupMaroon).hex, before.hex)
        XCTAssertFalse(prefs.hasCustomColor(for: "COMP 20073"))
    }

    /// One subject's override must not leak onto another.
    func testOverridesAreScopedToOneSubject() {
        let prefs = Preferences(defaults: defaults)
        let otherBefore = prefs.color(for: "GEED 005", in: .pupMaroon)

        prefs.setColor(Color(red: 1, green: 0, blue: 0), for: "COMP 20073")

        XCTAssertEqual(prefs.color(for: "GEED 005", in: .pupMaroon).hex, otherBefore.hex)
    }

    // MARK: Class description + online link

    func testClassInfoDefaultsToEmpty() {
        XCTAssertEqual(Preferences(defaults: defaults).info(for: tuesday), ClassInfo())
    }

    /// The default scope: setting one meeting's info must not touch another
    /// meeting of the same subject.
    func testPerMeetingInfoDoesNotLeakToAnotherMeetingOfTheSameSubject() {
        let prefs = Preferences(defaults: defaults)

        prefs.setInfo(ClassInfo(note: "Bring calculator", link: "https://zoom.us/tue"), for: tuesday)

        XCTAssertEqual(prefs.info(for: tuesday).link, "https://zoom.us/tue")
        XCTAssertEqual(prefs.info(for: friday), ClassInfo())
        XCTAssertFalse(prefs.hasPerma(for: tuesday))
    }

    /// The perma toggle: a subject-wide link covers every meeting of that
    /// subject, exactly like a teacher's one permanent Zoom room.
    func testPermaInfoAppliesToEveryMeetingOfTheSubject() {
        let prefs = Preferences(defaults: defaults)

        prefs.setPerma(true, for: tuesday)
        prefs.setInfo(ClassInfo(link: "https://zoom.us/perma"), for: tuesday)

        XCTAssertEqual(prefs.info(for: tuesday).link, "https://zoom.us/perma")
        XCTAssertEqual(prefs.info(for: friday).link, "https://zoom.us/perma")
        XCTAssertTrue(prefs.hasPerma(for: tuesday))
        XCTAssertTrue(prefs.hasPerma(for: friday), "perma is a subject-wide flag, not per meeting")
    }

    /// Turning perma on before typing anything must still stick — this is the
    /// real click-then-type order the popover toggle drives, and it's exactly
    /// what content-presence-as-flag would silently drop (an empty `ClassInfo`
    /// is indistinguishable from "never toggled").
    func testTogglingPermaOnBeforeTypingAnythingStillPersists() {
        let prefs = Preferences(defaults: defaults)

        prefs.setPerma(true, for: tuesday)

        XCTAssertTrue(prefs.hasPerma(for: tuesday))
        XCTAssertTrue(prefs.hasPerma(for: friday))

        prefs.setInfo(ClassInfo(link: "https://zoom.us/perma"), for: tuesday)
        XCTAssertEqual(prefs.info(for: friday).link, "https://zoom.us/perma")
    }

    /// The binding pattern the popover actually uses — read the current value,
    /// change one field, write the whole struct back — must not clobber the
    /// field it didn't touch, whichever scope currently applies.
    func testEditingOneFieldPreservesTheOtherViaReadModifyWrite() {
        let prefs = Preferences(defaults: defaults)

        prefs.setInfo(ClassInfo(link: "https://zoom.us/tue"), for: tuesday)
        var updated = prefs.info(for: tuesday)
        updated.note = "Bring calculator"
        prefs.setInfo(updated, for: tuesday)

        XCTAssertEqual(prefs.info(for: tuesday).link, "https://zoom.us/tue")
        XCTAssertEqual(prefs.info(for: tuesday).note, "Bring calculator")
    }

    /// Turning the toggle off for one meeting demotes the shared link away
    /// from every meeting of the subject — "every block" is what's turning off.
    func testTurningPermaOffRemovesItFromEveryMeetingOfTheSubject() {
        let prefs = Preferences(defaults: defaults)

        prefs.setPerma(true, for: tuesday)
        prefs.setInfo(ClassInfo(link: "https://zoom.us/perma"), for: tuesday)
        prefs.setPerma(false, for: tuesday)

        XCTAssertEqual(prefs.info(for: tuesday).link, "https://zoom.us/perma", "value moves down to just this meeting")
        XCTAssertEqual(prefs.info(for: friday), ClassInfo())
        XCTAssertFalse(prefs.hasPerma(for: friday))
    }

    /// Flipping the toggle moves the value between scopes rather than leaving
    /// a stale copy behind in the one it left.
    func testTogglingPermaMovesTheValueRatherThanDuplicatingIt() {
        let prefs = Preferences(defaults: defaults)

        prefs.setInfo(ClassInfo(note: "x"), for: tuesday)
        prefs.setPerma(true, for: tuesday)

        XCTAssertEqual(prefs.classInfo[tuesday.id], nil, "per-meeting entry must be cleared once promoted")
        XCTAssertEqual(prefs.classInfo[tuesday.subjectCode]?.note, "x")
    }

    /// Clearing both fields back to empty drops the key rather than persisting
    /// a no-op override — matches every other reset-to-default in this file.
    func testClearingInfoBackToEmptyDropsTheKey() {
        let prefs = Preferences(defaults: defaults)

        prefs.setInfo(ClassInfo(note: "x"), for: tuesday)
        prefs.setInfo(ClassInfo(), for: tuesday)

        XCTAssertTrue(prefs.classInfo.isEmpty)
    }

    func testClassInfoSurvivesRelaunch() {
        Preferences(defaults: defaults).setInfo(
            ClassInfo(note: "Chapter 4", link: "https://meet.google.com/abc"), for: tuesday)

        let reloaded = Preferences(defaults: defaults).info(for: tuesday)
        XCTAssertEqual(reloaded.note, "Chapter 4")
        XCTAssertEqual(reloaded.link, "https://meet.google.com/abc")
    }

    // MARK: RAG tuning (Settings ▸ Misc)

    func testRAGSettingsDefaultToTheShippedValues() {
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.ragChunkSize, Preferences.ragDefaultChunkSize)
        XCTAssertEqual(prefs.ragSimilarityFloor, Preferences.ragDefaultSimilarityFloor)
        XCTAssertEqual(prefs.ragContextBudget, Preferences.ragDefaultContextBudget)
        XCTAssertEqual(prefs.ragAnswerTemperature, Preferences.ragDefaultAnswerTemperature)
        XCTAssertEqual(prefs.ragEmbedModel, Preferences.ragDefaultEmbedModel)
    }

    func testRAGSettingsSurviveRelaunch() {
        let prefs = Preferences(defaults: defaults)
        prefs.ragChunkSize = 500
        prefs.ragSimilarityFloor = 0.5
        prefs.ragContextBudget = 8000
        prefs.ragAnswerTemperature = 0.7
        prefs.ragEmbedModel = "mxbai-embed-large"

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.ragChunkSize, 500)
        XCTAssertEqual(reloaded.ragSimilarityFloor, 0.5)
        XCTAssertEqual(reloaded.ragContextBudget, 8000)
        XCTAssertEqual(reloaded.ragAnswerTemperature, 0.7)
        XCTAssertEqual(reloaded.ragEmbedModel, "mxbai-embed-large")
    }

    // MARK: Assistant panel size

    func testAssistantPanelSizeDefaultsToTheShippedValues() {
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.assistantPanelWidth, Preferences.assistantPanelDefaultWidth)
        XCTAssertEqual(prefs.assistantPanelHeight, Preferences.assistantPanelDefaultHeight)
    }

    func testAssistantPanelSizeSurvivesRelaunch() {
        let prefs = Preferences(defaults: defaults)
        prefs.setAssistantPanelSize(CGSize(width: 500, height: 600))

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.assistantPanelWidth, 500)
        XCTAssertEqual(reloaded.assistantPanelHeight, 600)
    }

    /// A corrupt default, a stray drag bug, or just a small display shouldn't
    /// be able to produce a panel outside the usable range.
    func testAssistantPanelSizeClampsAtBothEnds() {
        let prefs = Preferences(defaults: defaults)

        prefs.setAssistantPanelSize(CGSize(width: 10, height: 10))
        XCTAssertEqual(prefs.assistantPanelWidth, Preferences.assistantPanelWidthRange.lowerBound)
        XCTAssertEqual(prefs.assistantPanelHeight, Preferences.assistantPanelHeightRange.lowerBound)

        prefs.setAssistantPanelSize(CGSize(width: 5000, height: 5000))
        XCTAssertEqual(prefs.assistantPanelWidth, Preferences.assistantPanelWidthRange.upperBound)
        XCTAssertEqual(prefs.assistantPanelHeight, Preferences.assistantPanelHeightRange.upperBound)
    }

    func testResetAssistantPanelSizeRestoresTheDefaults() {
        let prefs = Preferences(defaults: defaults)
        prefs.setAssistantPanelSize(CGSize(width: 700, height: 800))
        prefs.resetAssistantPanelSize()
        XCTAssertEqual(prefs.assistantPanelWidth, Preferences.assistantPanelDefaultWidth)
        XCTAssertEqual(prefs.assistantPanelHeight, Preferences.assistantPanelDefaultHeight)
    }
}

/// Reduce Motion is an accessibility setting, not a preference to soften —
/// every animation has to actually stop, not just get shorter.
final class MotionTests: XCTestCase {
    func testEveryAnimationIsRemovedWhenMotionIsReduced() {
        XCTAssertNil(Motion.arrival(reduced: true))
        XCTAssertNil(Motion.hover(reduced: true))
        XCTAssertNil(Motion.drift(reduced: true))
        XCTAssertNil(Motion.selection(reduced: true))
        XCTAssertNil(Motion.drag(reduced: true))
        XCTAssertNil(Motion.island(reduced: true))
    }

    func testAnimationsExistWhenMotionIsAllowed() {
        XCTAssertNotNil(Motion.arrival(reduced: false))
        XCTAssertNotNil(Motion.hover(reduced: false))
        XCTAssertNotNil(Motion.drift(reduced: false))
        XCTAssertNotNil(Motion.island(reduced: false))
    }

    func testStaggerCollapsesToZeroWhenMotionIsReduced() {
        XCTAssertEqual(Motion.stagger(0, reduced: true), 0)
        XCTAssertEqual(Motion.stagger(40, reduced: true), 0)
    }

    /// A packed day must not finish arriving noticeably after a quiet one.
    func testStaggerIsCappedForBusyDays() {
        XCTAssertEqual(Motion.stagger(0, reduced: false), 0)
        XCTAssertLessThan(Motion.stagger(2, reduced: false), Motion.stagger(6, reduced: false))
        XCTAssertEqual(Motion.stagger(200, reduced: false), 0.3)
    }
}

final class PaletteTests: XCTestCase {
    func testAutoFollowsTheSystemAppearance() {
        XCTAssertEqual(ThemeChoice.auto.palette(for: .light), .pupMaroon)
        XCTAssertEqual(ThemeChoice.auto.palette(for: .dark), .astraMoon)
    }

    /// An explicit pick has to ignore the system, or the picker does nothing.
    func testExplicitChoiceIgnoresTheSystemAppearance() {
        XCTAssertEqual(ThemeChoice.pupMaroon.palette(for: .dark), .pupMaroon)
        XCTAssertEqual(ThemeChoice.astraMoon.palette(for: .light), .astraMoon)
    }

    /// Native controls follow this; `auto` must stay nil or it pins the app to
    /// one appearance forever.
    func testForcedColorSchemeMatchesTheChoice() {
        XCTAssertNil(ThemeChoice.auto.colorScheme)
        XCTAssertEqual(ThemeChoice.pupMaroon.colorScheme, .light)
        XCTAssertEqual(ThemeChoice.astraMoon.colorScheme, .dark)
    }

    /// Deterministic, not `Hashable` — Swift reseeds that per process, which
    /// would repaint every subject on each launch.
    func testSubjectColorIsStableForTheSameCode() {
        XCTAssertEqual(
            Palette.pupMaroon.color(for: "COMP 20073").hex,
            Palette.pupMaroon.color(for: "COMP 20073").hex
        )
    }

    func testHexRoundTrips() {
        XCTAssertEqual(Color(hex: "#1E7A4C")?.hex, "#1E7A4C")
        XCTAssertEqual(Color(hex: "1E7A4C")?.hex, "#1E7A4C")
        XCTAssertNil(Color(hex: "nope"))
        XCTAssertNil(Color(hex: "#12345"))
    }
}
