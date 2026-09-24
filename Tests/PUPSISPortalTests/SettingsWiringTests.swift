import XCTest
@testable import PUPSISPortal

/// Guards against a Settings control that writes a `Preferences` key nothing
/// in the app ever reads — the exact shape of bug the 2026-09-24 audit found
/// with the old Dynamic Island keys (removed, then partly reinstated as
/// `showIsland`/`islandExpandOnHover`/`launchDestination`). Every stored key
/// must have at least one reader outside the Settings screen itself, or be
/// explicitly allowlisted below with why not.
final class SettingsWiringTests: XCTestCase {
    /// Every `Preferences.Key` static let, paired with the Swift property
    /// that actually reads/writes it — usually the same identifier; one
    /// legacy key, `sessionStatuses` → `termStatuses`, doesn't match.
    /// `Preferences.Key` is `private`, so this list is hand-kept rather than
    /// reflected (an enum's static lets aren't something `Mirror` walks
    /// anyway) — 53 entries, stable enough that a drift here is itself worth
    /// catching in review.
    private static let keys: [(key: String, property: String)] = [
        ("theme", "theme"), ("fontChoice", "fontChoice"), ("subjectColors", "subjectColors"),
        ("sessionStatuses", "termStatuses"), ("occurrenceStatuses", "occurrenceStatuses"),
        ("onlineStripColors", "onlineStripColors"), ("termTimes", "termTimes"),
        ("occurrenceTimes", "occurrenceTimes"), ("classInfo", "classInfo"),
        ("campusOverride", "campusOverride"), ("learnedCampusCodes", "learnedCampusCodes"),
        ("permaSubjects", "permaSubjects"), ("subjectTasks", "subjectTasks"),
        ("eventColors", "eventColors"), ("visibleCalendarIDs", "visibleCalendarIDs"),
        ("exportCalendarID", "exportCalendarID"), ("onlineExportCalendarID", "onlineExportCalendarID"),
        ("termEndDate", "termEndDate"), ("termStartDate", "termStartDate"),
        ("notificationsEnabled", "notificationsEnabled"), ("notificationLeadMinutes", "notificationLeadMinutes"),
        ("programTotalUnits", "programTotalUnits"), ("googleClientID", "googleClientID"),
        ("googleCalendarID", "googleCalendarID"), ("trafficLightsAutoHide", "trafficLightsAutoHide"),
        ("forceReducedMotion", "forceReducedMotion"), ("playPortalIntro", "playPortalIntro"),
        ("showIsland", "showIsland"), ("islandExpandOnHover", "islandExpandOnHover"),
        ("launchDestination", "launchDestination"), ("aiEnabled", "aiEnabled"), ("aiModel", "aiModel"),
        ("aiProvider", "aiProvider"), ("aiProviderModel", "aiProviderModel"), ("aiPermission", "aiPermission"),
        ("aiRevealAnimation", "aiRevealAnimation"), ("aiThinking", "aiThinking"), ("aiContextSize", "aiContextSize"),
        ("aiTemperature", "aiTemperature"), ("aiOutputTokenBudget", "aiOutputTokenBudget"),
        ("aiKVCacheQuantized", "aiKVCacheQuantized"), ("aiUseGPU", "aiUseGPU"), ("ragChunkSize", "ragChunkSize"),
        ("ragSimilarityFloor", "ragSimilarityFloor"), ("ragContextBudget", "ragContextBudget"),
        ("ragAnswerTemperature", "ragAnswerTemperature"), ("assistantPanelWidth", "assistantPanelWidth"),
        ("assistantPanelHeight", "assistantPanelHeight"), ("notebookSidebarWidth", "notebookSidebarWidth"),
        ("notebookSidebarOnLeft", "notebookSidebarOnLeft"), ("noteReadingWidth", "noteReadingWidth"),
        ("scheduleSidebarWidth", "scheduleSidebarWidth"), ("uiScale", "uiScale"),
    ]

    /// Keys whose only "reader" a plain grep for `.property` ever finds is
    /// inside `Views/Settings/` or `Core/Preferences.swift` — each genuinely
    /// wired, just one level removed from the raw stored property (through a
    /// helper method, a decoupled static reader, or — for the two island
    /// prefs — not yet, on purpose).
    private static let allowlist: [String: String] = [
        "termStatuses": "read only through Preferences.status(for:on:)/termStatus(for:) — Blocks.swift, Notifier.swift, AgendaView.swift etc. call those, never the raw dict",
        "onlineStripColors": "read only through Preferences.stripColor(for:in:) — Blocks.swift calls that, never the raw dict",
        "permaSubjects": "read only through Preferences.hasPerma(for:)/info(for:) — Blocks.swift calls those, never the raw set",
        "eventColors": "read only through Preferences.color(forEvent:in:) — Blocks.swift, CalendarView.swift, WeekPrintView.swift call that, never the raw dict",
        "googleCalendarID": "consumed only by SchedulePane's own Google export action — no other screen needs a Google calendar id",
        "aiProviderModel": "read only through Preferences.resolvedAIClient() — ModelCatalog.swift, AssistantFloating.swift call that, never the raw string",
        "aiTemperature": "read only through the decoupled Preferences.storedTemperature(defaults:) — AssistantEngine.swift calls that static, never the instance property (same decoupling as aiContextSize/aiOutputTokenBudget)",
        "aiUseGPU": "read only through the decoupled Preferences.storedUseGPU(defaults:) — LlamaRuntime.swift calls that static, never the instance property",
        "showIsland": "not wired yet (spec 12) — the IS slice reads this to show/hide the island",
        "islandExpandOnHover": "not wired yet (spec 12) — the IS slice reads this for the island's hover behaviour",
    ]

    /// `#filePath` gives this file's own absolute path
    /// (`<repo>/Tests/PUPSISPortalTests/SettingsWiringTests.swift`); three
    /// levels up is the repo root.
    private static let sourcesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/PUPSISPortalApp")

    /// True when some `.swift` file under `Sources/PUPSISPortalApp`, other
    /// than `Views/Settings/*` and `Core/Preferences.swift`, mentions
    /// `.property` — a plain substring search, not a real symbol resolver,
    /// per the brief's own "simplest honest approach". It can over-match (a
    /// doc comment mentioning the name), never under-match a real caller.
    private func hasReaderOutsideSettings(_ property: String) -> Bool {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: Self.sourcesRoot, includingPropertiesForKeys: nil) else { return false }
        let needle = ".\(property)"
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let path = url.path
            guard !path.contains("/Views/Settings/"), !path.hasSuffix("/Core/Preferences.swift") else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if text.contains(needle) { return true }
        }
        return false
    }

    func testEveryStoredKeyIsReadSomewhereOutsideSettings() {
        for (key, property) in Self.keys {
            if Self.allowlist[property] != nil { continue }
            XCTAssertTrue(
                hasReaderOutsideSettings(property),
                """
                Preferences.\(property) (key "\(key)") has no reader outside Views/Settings/. \
                Either wire it up somewhere real, or add it to SettingsWiringTests.allowlist with why not.
                """
            )
        }
    }

    /// Every allowlist reason is real prose, and every allowlisted name is
    /// still one of the keys above — an entry left behind after a rename or
    /// removal would silently stop covering anything.
    func testAllowlistEntriesAreCurrentAndExplained() {
        let properties = Set(Self.keys.map(\.property))
        for (allowed, reason) in Self.allowlist {
            XCTAssertTrue(properties.contains(allowed), "\"\(allowed)\" is allowlisted but isn't in the key list above — stale entry?")
            XCTAssertFalse(reason.trimmingCharacters(in: .whitespaces).isEmpty, "\"\(allowed)\" needs a real reason")
        }
    }

    /// Sanity check on the harness itself: a key this test knows for a fact
    /// has no reader anywhere (made up, never declared) must fail, so a
    /// change to `hasReaderOutsideSettings` that quietly stops matching
    /// anything doesn't turn this whole suite into a no-op.
    func testHarnessActuallyDetectsAnUnwiredProperty() {
        XCTAssertFalse(hasReaderOutsideSettings("thisPropertyDoesNotExistAnywhereInTheApp"))
        XCTAssertTrue(hasReaderOutsideSettings("aiModel"))
    }
}
