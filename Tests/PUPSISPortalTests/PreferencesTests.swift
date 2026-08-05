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

    private let tuesday = ClassSession(subjectCode: "COMP 20073", description: "Data Structures",
                                       faculty: "SANTOS, JUAN", day: .tuesday,
                                       start: 14 * 60, end: 16 * 60)
    private let friday = ClassSession(subjectCode: "COMP 20073", description: "Data Structures",
                                      faculty: "SANTOS, JUAN", day: .friday,
                                      start: 13 * 60 + 30, end: 16 * 60 + 30)

    func testStatusDefaultsToInPerson() {
        XCTAssertEqual(Preferences(defaults: defaults).status(for: tuesday), .regular)
    }

    func testStatusSurvivesRelaunch() {
        Preferences(defaults: defaults).setStatus(.online, for: tuesday)

        XCTAssertEqual(Preferences(defaults: defaults).status(for: tuesday), .online)
    }

    /// Status is per meeting, not per subject — same course, two days, one of
    /// them online. Keying this by subject code would be the obvious bug.
    func testStatusIsScopedToOneMeetingNotTheWholeSubject() {
        let prefs = Preferences(defaults: defaults)

        prefs.setStatus(.vacant, for: tuesday)

        XCTAssertEqual(prefs.status(for: tuesday), .vacant)
        XCTAssertEqual(prefs.status(for: friday), .regular)
    }

    /// Going back to the default should drop the key, not store `.regular`.
    func testResettingToInPersonClearsTheEntry() {
        let prefs = Preferences(defaults: defaults)

        prefs.setStatus(.vacant, for: tuesday)
        prefs.setStatus(.regular, for: tuesday)

        XCTAssertTrue(prefs.sessionStatuses.isEmpty)
        XCTAssertEqual(prefs.status(for: tuesday), .regular)
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

    /// One subject's override must not leak onto another.
    func testOverridesAreScopedToOneSubject() {
        let prefs = Preferences(defaults: defaults)
        let otherBefore = prefs.color(for: "GEED 005", in: .pupMaroon)

        prefs.setColor(Color(red: 1, green: 0, blue: 0), for: "COMP 20073")

        XCTAssertEqual(prefs.color(for: "GEED 005", in: .pupMaroon).hex, otherBefore.hex)
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
