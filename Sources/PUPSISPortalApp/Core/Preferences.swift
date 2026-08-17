import SwiftUI

/// What's actually happening with a class meeting. The SIS doesn't say — it
/// only lists the room-and-time it was enrolled as — so this is the user
/// telling the app something it can't scrape.
enum SessionStatus: String, Codable, CaseIterable, Identifiable {
    case regular
    case online
    case vacant

    var id: String { rawValue }

    var label: String {
        switch self {
        case .regular: "In Person"
        case .online: "Online"
        case .vacant: "Vacant"
        }
    }

    var symbol: String {
        switch self {
        case .regular: "building.2"
        case .online: "video.fill"
        case .vacant: "calendar.badge.minus"
        }
    }
}

/// A locally-set start/end for a class meeting, minutes from midnight —
/// the SIS time moved (a prof rescheduling), never a drag/resize, since
/// classes aren't draggable.
struct TimeOverride: Codable, Equatable {
    var start: Int
    var end: Int
}

/// A user-written description and/or online-meeting link for a class. Empty
/// fields are the "nothing set" state — never persisted, so an all-empty
/// value is equivalent to no entry at all.
struct ClassInfo: Codable, Equatable {
    var note: String = ""
    var link: String = ""
    var isEmpty: Bool { note.isEmpty && link.isEmpty }
}

/// User settings. `UserDefaults` on purpose — these are preferences, unlike
/// the schedule, which is a document and lives in `ScheduleStore`.
///
/// Not `@AppStorage`: that's a view-level property wrapper and doesn't publish
/// from inside an `ObservableObject`, which is exactly where these need to be.
@MainActor
final class Preferences: ObservableObject {
    @Published var theme: ThemeChoice {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }

    /// Subject code → hex. Absent means "use the palette's default".
    @Published private(set) var subjectColors: [String: String] {
        didSet { defaults.set(try? JSONEncoder().encode(subjectColors), forKey: Key.subjectColors) }
    }

    /// The term-wide default status per meeting, keyed by `ClassSession.id`.
    /// Per *meeting*, not per subject: one section can be in person on Tuesday
    /// and online on Friday. Persisted under the original `sessionStatuses` key,
    /// so marks made before status went per-week load here as "every week" —
    /// which is exactly how they behaved then.
    @Published private(set) var termStatuses: [String: SessionStatus] {
        didSet { defaults.set(try? JSONEncoder().encode(termStatuses), forKey: Key.sessionStatuses) }
    }

    /// This-week exceptions to the term default, keyed by `ClassSession.id` plus
    /// the week they fall in — so "this Tuesday is online" doesn't make every
    /// Tuesday online.
    @Published private(set) var occurrenceStatuses: [String: SessionStatus] {
        didSet { defaults.set(try? JSONEncoder().encode(occurrenceStatuses), forKey: Key.occurrenceStatuses) }
    }

    /// Per-subject colour of the strip drawn around an online class, keyed by
    /// subject code. Absent means "use the palette's online-strip default".
    @Published private(set) var onlineStripColors: [String: String] {
        didSet { defaults.set(try? JSONEncoder().encode(onlineStripColors), forKey: Key.onlineStripColors) }
    }

    /// The term-wide moved time per meeting, keyed by `ClassSession.id` — same
    /// shape as `termStatuses`. "The prof permanently moved it to 1:30."
    @Published private(set) var termTimes: [String: TimeOverride] {
        didSet { defaults.set(try? JSONEncoder().encode(termTimes), forKey: Key.termTimes) }
    }

    /// This-week exceptions to the moved time, keyed like `occurrenceStatuses`.
    /// "Just this week it's 1:30." Wins over `termTimes`, which wins over the
    /// scraped time — resolved by `time(for:on:)`.
    @Published private(set) var occurrenceTimes: [String: TimeOverride] {
        didSet { defaults.set(try? JSONEncoder().encode(occurrenceTimes), forKey: Key.occurrenceTimes) }
    }

    /// Description + online link a user attached to a class. Keyed by
    /// `ClassSession.id` (default: this one meeting) **or** `subjectCode` (the
    /// "apply to every X block" toggle — a teacher's one permanent link
    /// covering every meeting of the course). The two key spaces never
    /// collide, so one dictionary covers both scopes; `info(for:)` resolves
    /// per-meeting first, falling back to the subject-wide entry.
    @Published private(set) var classInfo: [String: ClassInfo] {
        didSet { defaults.set(try? JSONEncoder().encode(classInfo), forKey: Key.classInfo) }
    }

    /// Subjects whose "apply to every block" toggle is on. Deliberately
    /// separate from `classInfo`'s content: the toggle can be switched on
    /// before any text exists, and content presence alone can't carry that —
    /// an empty `ClassInfo` is indistinguishable from "never toggled".
    @Published private(set) var permaSubjects: Set<String> {
        didSet { defaults.set(Array(permaSubjects), forKey: Key.permaSubjects) }
    }

    /// Event colours, keyed by `DayBlock.groupKey` so a run of connected days
    /// recolours as one thing. EventKit has no per-event colour — events take
    /// their calendar's — so this is ours to keep.
    @Published private(set) var eventColors: [String: String] {
        didSet { defaults.set(try? JSONEncoder().encode(eventColors), forKey: Key.eventColors) }
    }

    /// Which Calendar.app calendars are drawn in the grid. Empty by default —
    /// nothing from the user's calendar appears until they ask for it.
    @Published var visibleCalendarIDs: Set<String> {
        didSet { defaults.set(Array(visibleCalendarIDs), forKey: Key.visibleCalendarIDs) }
    }

    /// Which calendar in-person classes get exported into. Empty until the user
    /// picks — there's no safe default guess for someone else's calendar.
    @Published var exportCalendarID: String {
        didSet { defaults.set(exportCalendarID, forKey: Key.exportCalendarID) }
    }

    /// Which calendar online classes go into. Empty means "same as in-person",
    /// so by default everything lands in one calendar until the user separates
    /// them.
    @Published var onlineExportCalendarID: String {
        didSet { defaults.set(onlineExportCalendarID, forKey: Key.onlineExportCalendarID) }
    }

    /// When exported classes stop repeating. The SIS doesn't publish a term
    /// end, so the user supplies it — a class repeating forever is the kind of
    /// thing you find in your calendar two years later.
    @Published var termEndDate: Date {
        didSet { defaults.set(termEndDate.timeIntervalSince1970, forKey: Key.termEndDate) }
    }

    /// Off until asked for. Turning it on is what triggers the authorization
    /// prompt, so defaulting it to true would prompt at first launch.
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    /// Minutes before a class starts. Long enough to walk somewhere.
    @Published var notificationLeadMinutes: Int {
        didSet { defaults.set(notificationLeadMinutes, forKey: Key.notificationLeadMinutes) }
    }

    /// The program's total required units, for the "units completed / total"
    /// progress on the grades trend. SIS doesn't publish it, so the user sets it
    /// once; 0 means "not set" and the progress shows completed units only.
    @Published var programTotalUnits: Int {
        didSet { defaults.set(programTotalUnits, forKey: Key.programTotalUnits) }
    }

    /// The user's own Google OAuth client ID (from their Google Cloud project).
    /// Not secret — the refresh token it obtains is, and that lives in the
    /// Keychain (`GoogleTokenStore`), never here.
    @Published var googleClientID: String {
        didSet { defaults.set(googleClientID, forKey: Key.googleClientID) }
    }

    /// Which Google calendar classes export into. Empty until the user picks.
    @Published var googleCalendarID: String {
        didSet { defaults.set(googleCalendarID, forKey: Key.googleCalendarID) }
    }

    // MARK: Dynamic island

    /// Open on the centred home launcher; off opens straight into the last screen.
    @Published var islandStartHome: Bool {
        didSet { defaults.set(islandStartHome, forKey: Key.islandStartHome) }
    }

    /// The island rests as a compact pill and expands on hover; off keeps the
    /// full bar shown at all times.
    @Published var islandExpandOnHover: Bool {
        didSet { defaults.set(islandExpandOnHover, forKey: Key.islandExpandOnHover) }
    }

    /// Auto-hide the window's traffic-light buttons, revealing them when the
    /// cursor nears the top-left corner. Off keeps them always visible.
    @Published var trafficLightsAutoHide: Bool {
        didSet { defaults.set(trafficLightsAutoHide, forKey: Key.trafficLightsAutoHide) }
    }

    // MARK: AI (beta)

    /// Drafting help in the notes editor from a model running locally via
    /// Ollama. **Off by default and staying that way** — it's an extra thing to
    /// install and not everyone's machine can run a model, so it must never be
    /// something the app assumes.
    @Published var aiEnabled: Bool {
        didSet { defaults.set(aiEnabled, forKey: Key.aiEnabled) }
    }

    /// Which local model to ask. A name, not an endpoint: the host is fixed at
    /// localhost so "your notes stay on your Mac" can't be configured away.
    ///
    /// Empty until the user picks from the models actually installed on this
    /// machine — there's no sensible stock default, since a name like
    /// `llama3.2` is a 404 on a machine that never pulled it.
    @Published var aiModel: String {
        didSet { defaults.set(aiModel, forKey: Key.aiModel) }
    }

    /// How much the assistant acts on its own — see `AssistantPermission`.
    /// Defaults to `.confirm`: the Phase 0 spike showed small local models
    /// will confidently claim to have done things they didn't, so nothing
    /// runs unseen until the user has reason to trust it more.
    @Published var aiPermission: AssistantPermission {
        didSet { defaults.set(aiPermission.rawValue, forKey: Key.aiPermission) }
    }

    /// How AI-inserted text (Replace / Insert below in the note editor) reveals
    /// itself — see `AIRevealAnimation`. `.sweep` is the default: one
    /// continuous glow traveling start-of-line to end, rather than each word
    /// pulsing on its own.
    @Published var aiRevealAnimation: AIRevealAnimation {
        didSet { defaults.set(aiRevealAnimation.rawValue, forKey: Key.aiRevealAnimation) }
    }

    // MARK: RAG tuning (Settings ▸ Misc)

    /// Defaults mirror what was hand-calibrated live against a real vault —
    /// see `RAGQuery`'s own doc comment. Exposed here rather than staying
    /// hardcoded so a future miscalibration is a slider, not a code change.
    static let ragDefaultChunkSize = 700
    static let ragDefaultSimilarityFloor = 0.35
    static let ragDefaultContextBudget = 4000
    static let ragDefaultAnswerTemperature = 0.2
    static let ragDefaultEmbedModel = "nomic-embed-text"

    /// Max characters per retrieval chunk — `NoteRetrieval.chunks(maxChars:)`.
    @Published var ragChunkSize: Int {
        didSet { defaults.set(ragChunkSize, forKey: Key.ragChunkSize) }
    }
    /// Cosine-similarity floor below which an embedding match is discarded —
    /// `NoteRetrieval.rankByEmbedding(minSimilarity:)`.
    @Published var ragSimilarityFloor: Double {
        didSet { defaults.set(ragSimilarityFloor, forKey: Key.ragSimilarityFloor) }
    }
    /// Character budget for the grounded-answer prompt — `RAGQuery.ask`'s
    /// packing loop.
    @Published var ragContextBudget: Int {
        didSet { defaults.set(ragContextBudget, forKey: Key.ragContextBudget) }
    }
    /// LFM2's answer temperature — `LlamaCppClient.complete(temperature:)`.
    @Published var ragAnswerTemperature: Double {
        didSet { defaults.set(ragAnswerTemperature, forKey: Key.ragAnswerTemperature) }
    }
    /// The Ollama model `RAGQuery` embeds with — must actually support
    /// embeddings (confirmed live: a plain chat model 404s `/api/embed`).
    @Published var ragEmbedModel: String {
        didSet { defaults.set(ragEmbedModel, forKey: Key.ragEmbedModel) }
    }

    // MARK: Assistant panel size

    /// The app's first persisted geometry. Read directly by `AssistantFloating`
    /// for its `.frame`; write only through `setAssistantPanelSize` /
    /// `resetAssistantPanelSize` so a corrupt `UserDefaults` value (or a stray
    /// drag-site bug) can never produce a panel outside the clamp range.
    static let assistantPanelDefaultWidth: Double = 360
    static let assistantPanelDefaultHeight: Double = 440
    static let assistantPanelWidthRange: ClosedRange<Double> = 320...760
    static let assistantPanelHeightRange: ClosedRange<Double> = 300...900

    @Published private(set) var assistantPanelWidth: Double {
        didSet { defaults.set(assistantPanelWidth, forKey: Key.assistantPanelWidth) }
    }
    @Published private(set) var assistantPanelHeight: Double {
        didSet { defaults.set(assistantPanelHeight, forKey: Key.assistantPanelHeight) }
    }

    func setAssistantPanelSize(_ size: CGSize) {
        assistantPanelWidth = min(max(size.width, Self.assistantPanelWidthRange.lowerBound), Self.assistantPanelWidthRange.upperBound)
        assistantPanelHeight = min(max(size.height, Self.assistantPanelHeightRange.lowerBound), Self.assistantPanelHeightRange.upperBound)
    }

    func resetAssistantPanelSize() {
        assistantPanelWidth = Self.assistantPanelDefaultWidth
        assistantPanelHeight = Self.assistantPanelDefaultHeight
    }

    static let leadOptions = [5, 10, 15, 30]

    /// Meetings marked vacant **for the whole term**, in the form `Notifier` and
    /// `NextClass` want. Term-only on purpose: a weekly-recurring reminder can't
    /// skip a single week's occurrence, so a one-week vacancy stays a visual
    /// thing and doesn't rewrite the reminder.
    var vacantSessionIDs: Set<String> {
        Set(termStatuses.filter { $0.value == .vacant }.keys)
    }

    /// Far enough out to cover a semester, close enough that it's obviously a
    /// guess worth correcting.
    static func defaultTermEnd(from date: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: 4, to: calendar.startOfDay(for: date)) ?? date
    }

    private let defaults: UserDefaults

    private enum Key {
        static let theme = "theme"
        static let subjectColors = "subjectColors"
        static let sessionStatuses = "sessionStatuses"
        static let occurrenceStatuses = "occurrenceStatuses"
        static let onlineStripColors = "onlineStripColors"
        static let termTimes = "termTimes"
        static let occurrenceTimes = "occurrenceTimes"
        static let classInfo = "classInfo"
        static let permaSubjects = "permaSubjects"
        static let visibleCalendarIDs = "visibleCalendarIDs"
        static let exportCalendarID = "exportCalendarID"
        static let onlineExportCalendarID = "onlineExportCalendarID"
        static let eventColors = "eventColors"
        static let termEndDate = "termEndDate"
        static let notificationsEnabled = "notificationsEnabled"
        static let notificationLeadMinutes = "notificationLeadMinutes"
        static let programTotalUnits = "programTotalUnits"
        static let googleClientID = "googleClientID"
        static let googleCalendarID = "googleCalendarID"
        static let islandStartHome = "islandStartHome"
        static let islandExpandOnHover = "islandExpandOnHover"
        static let trafficLightsAutoHide = "trafficLightsAutoHide"
        static let aiEnabled = "aiEnabled"
        static let aiModel = "aiModel"
        static let aiPermission = "aiPermission"
        static let aiRevealAnimation = "aiRevealAnimation"
        static let ragChunkSize = "ragChunkSize"
        static let ragSimilarityFloor = "ragSimilarityFloor"
        static let ragContextBudget = "ragContextBudget"
        static let ragAnswerTemperature = "ragAnswerTemperature"
        static let ragEmbedModel = "ragEmbedModel"
        static let assistantPanelWidth = "assistantPanelWidth"
        static let assistantPanelHeight = "assistantPanelHeight"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = defaults.string(forKey: Key.theme).flatMap(ThemeChoice.init(rawValue:)) ?? .auto
        subjectColors = defaults.data(forKey: Key.subjectColors)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        termStatuses = defaults.data(forKey: Key.sessionStatuses)
            .flatMap { try? JSONDecoder().decode([String: SessionStatus].self, from: $0) } ?? [:]
        occurrenceStatuses = defaults.data(forKey: Key.occurrenceStatuses)
            .flatMap { try? JSONDecoder().decode([String: SessionStatus].self, from: $0) } ?? [:]
        onlineStripColors = defaults.data(forKey: Key.onlineStripColors)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        termTimes = defaults.data(forKey: Key.termTimes)
            .flatMap { try? JSONDecoder().decode([String: TimeOverride].self, from: $0) } ?? [:]
        occurrenceTimes = defaults.data(forKey: Key.occurrenceTimes)
            .flatMap { try? JSONDecoder().decode([String: TimeOverride].self, from: $0) } ?? [:]
        classInfo = defaults.data(forKey: Key.classInfo)
            .flatMap { try? JSONDecoder().decode([String: ClassInfo].self, from: $0) } ?? [:]
        permaSubjects = Set(defaults.stringArray(forKey: Key.permaSubjects) ?? [])
        eventColors = defaults.data(forKey: Key.eventColors)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        visibleCalendarIDs = Set(defaults.stringArray(forKey: Key.visibleCalendarIDs) ?? [])
        exportCalendarID = defaults.string(forKey: Key.exportCalendarID) ?? ""
        onlineExportCalendarID = defaults.string(forKey: Key.onlineExportCalendarID) ?? ""
        termEndDate = (defaults.object(forKey: Key.termEndDate) as? Double)
            .map(Date.init(timeIntervalSince1970:)) ?? Self.defaultTermEnd()
        notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
        // `integer(forKey:)` returns 0 for a missing key, and 0 is a legal lead
        // ("as it starts") — so check for the key rather than trusting the zero.
        notificationLeadMinutes = (defaults.object(forKey: Key.notificationLeadMinutes) as? Int) ?? 15
        programTotalUnits = (defaults.object(forKey: Key.programTotalUnits) as? Int) ?? 0
        googleClientID = defaults.string(forKey: Key.googleClientID) ?? ""
        googleCalendarID = defaults.string(forKey: Key.googleCalendarID) ?? ""
        // Default the island prefs on; `bool(forKey:)` returns false for a
        // missing key, so check the key instead.
        islandStartHome = (defaults.object(forKey: Key.islandStartHome) as? Bool) ?? true
        islandExpandOnHover = (defaults.object(forKey: Key.islandExpandOnHover) as? Bool) ?? true
        trafficLightsAutoHide = (defaults.object(forKey: Key.trafficLightsAutoHide) as? Bool) ?? true
        aiEnabled = (defaults.object(forKey: Key.aiEnabled) as? Bool) ?? false
        aiModel = defaults.string(forKey: Key.aiModel) ?? ""
        aiPermission = defaults.string(forKey: Key.aiPermission)
            .flatMap(AssistantPermission.init(rawValue:)) ?? .confirm
        aiRevealAnimation = defaults.string(forKey: Key.aiRevealAnimation)
            .flatMap(AIRevealAnimation.init(rawValue:)) ?? .sweep
        ragChunkSize = (defaults.object(forKey: Key.ragChunkSize) as? Int) ?? Preferences.ragDefaultChunkSize
        ragSimilarityFloor = (defaults.object(forKey: Key.ragSimilarityFloor) as? Double) ?? Preferences.ragDefaultSimilarityFloor
        ragContextBudget = (defaults.object(forKey: Key.ragContextBudget) as? Int) ?? Preferences.ragDefaultContextBudget
        ragAnswerTemperature = (defaults.object(forKey: Key.ragAnswerTemperature) as? Double) ?? Preferences.ragDefaultAnswerTemperature
        ragEmbedModel = defaults.string(forKey: Key.ragEmbedModel) ?? Preferences.ragDefaultEmbedModel
        assistantPanelWidth = (defaults.object(forKey: Key.assistantPanelWidth) as? Double) ?? Preferences.assistantPanelDefaultWidth
        assistantPanelHeight = (defaults.object(forKey: Key.assistantPanelHeight) as? Double) ?? Preferences.assistantPanelDefaultHeight
    }

    /// The colour an event renders in: the user's pick, else the palette's
    /// deterministic default so two different events don't look identical.
    func color(forEvent groupKey: String, in palette: Palette) -> Color {
        eventColors[groupKey].flatMap(Color.init(hex:)) ?? palette.color(for: groupKey)
    }

    func setEventColor(_ color: Color, for groupKey: String) {
        guard let hex = color.hex else { return }
        eventColors[groupKey] = hex
    }

    func resetEventColor(for groupKey: String) {
        eventColors[groupKey] = nil
    }

    func hasCustomEventColor(for groupKey: String) -> Bool {
        eventColors[groupKey] != nil
    }

    func setCalendar(_ id: String, visible: Bool) {
        if visible {
            visibleCalendarIDs.insert(id)
        } else {
            visibleCalendarIDs.remove(id)
        }
    }

    private func occurrenceKey(_ session: ClassSession, on weekStart: Date) -> String {
        "\(session.id)@\(Int(weekStart.timeIntervalSince1970))"
    }

    /// The status a meeting shows in a given week: this week's exception if
    /// there is one, otherwise the term default, otherwise in person.
    func status(for session: ClassSession, on weekStart: Date) -> SessionStatus {
        occurrenceStatuses[occurrenceKey(session, on: weekStart)]
            ?? termStatuses[session.id]
            ?? .regular
    }

    /// The status picker sets **this week**. Stored only when it differs from
    /// the term default, so it's a genuine exception and clearing back to the
    /// default drops the key rather than pinning a redundant override.
    func setStatus(_ status: SessionStatus, for session: ClassSession, on weekStart: Date) {
        let base = termStatuses[session.id] ?? .regular
        occurrenceStatuses[occurrenceKey(session, on: weekStart)] = status == base ? nil : status
    }

    func termStatus(for session: ClassSession) -> SessionStatus {
        termStatuses[session.id] ?? .regular
    }

    /// The "every week this term" control. `.regular` clears it. Week exceptions
    /// still win over it, so a term-online class can have one vacant week.
    func setTermStatus(_ status: SessionStatus, for session: ClassSession) {
        termStatuses[session.id] = status == .regular ? nil : status
    }

    /// The time a meeting shows in a given week: this week's exception if
    /// there is one, otherwise the term-wide move, otherwise the scraped SIS
    /// time. Never reads or writes `session.start`/`.end` directly — those stay
    /// scraped, and `session.id` is derived from them (`Models.swift:94`), so
    /// mutating them would shift the very key this override is stored under.
    func time(for session: ClassSession, on weekStart: Date) -> (start: Int, end: Int) {
        let override = occurrenceTimes[occurrenceKey(session, on: weekStart)] ?? termTimes[session.id]
        return override.map { ($0.start, $0.end) } ?? (session.start, session.end)
    }

    func isTimeOverridden(_ session: ClassSession, on weekStart: Date) -> Bool {
        occurrenceTimes[occurrenceKey(session, on: weekStart)] != nil || termTimes[session.id] != nil
    }

    /// Whether the *recurring* move is set — distinct from `isTimeOverridden`,
    /// which is also true for a this-week-only exception. Drives the popover's
    /// "Every week" toggle regardless of which week is open.
    func isTermTimeOverridden(_ session: ClassSession) -> Bool {
        termTimes[session.id] != nil
    }

    /// This week only. `nil` clears it — dropping the key rather than pinning
    /// a redundant override, same convention as `setStatus`.
    func setTime(_ override: TimeOverride?, for session: ClassSession, on weekStart: Date) {
        occurrenceTimes[occurrenceKey(session, on: weekStart)] = override
    }

    /// Every week. Week exceptions still win over it, so a permanently-moved
    /// class can still have one further one-off week.
    func setTermTime(_ override: TimeOverride?, for session: ClassSession) {
        termTimes[session.id] = override
    }

    /// The colour of the strip drawn around an online class: the user's
    /// per-subject pick, else the palette's theme-aware default.
    func stripColor(for subjectCode: String, in palette: Palette) -> Color {
        onlineStripColors[subjectCode].flatMap(Color.init(hex:)) ?? palette.onlineStrip
    }

    func setStripColor(_ color: Color, for subjectCode: String) {
        guard let hex = color.hex else { return }
        onlineStripColors[subjectCode] = hex
    }

    func resetStripColor(for subjectCode: String) {
        onlineStripColors[subjectCode] = nil
    }

    func hasCustomStripColor(for subjectCode: String) -> Bool {
        onlineStripColors[subjectCode] != nil
    }

    /// The color a subject actually renders in: the user's pick if they made
    /// one, otherwise the palette's deterministic default.
    func color(for subjectCode: String, in palette: Palette) -> Color {
        subjectColors[subjectCode].flatMap(Color.init(hex:)) ?? palette.color(for: subjectCode)
    }

    func setColor(_ color: Color, for subjectCode: String) {
        guard let hex = color.hex else { return }
        subjectColors[subjectCode] = hex
    }

    func resetColor(for subjectCode: String) {
        subjectColors[subjectCode] = nil
    }

    func hasCustomColor(for subjectCode: String) -> Bool {
        subjectColors[subjectCode] != nil
    }

    /// The description/link for a meeting: the subject-wide entry while perma
    /// is on for this subject, otherwise this meeting's own entry.
    func info(for session: ClassSession) -> ClassInfo {
        let key = hasPerma(for: session) ? session.subjectCode : session.id
        return classInfo[key] ?? ClassInfo()
    }

    /// Whether this subject currently has the "every block" toggle on — a flag
    /// independent of content, so switching it on before typing anything still
    /// sticks. Drives the popover's toggle regardless of which meeting is open.
    func hasPerma(for session: ClassSession) -> Bool {
        permaSubjects.contains(session.subjectCode)
    }

    /// Writes note/link text to whichever scope this meeting currently reads
    /// from — the subject-wide entry if perma is on for this subject, this
    /// meeting's own entry otherwise. Never touches the other scope: editing
    /// text isn't the same action as promoting/demoting it, and a subject-wide
    /// entry set from one meeting must survive editing a *different* meeting.
    /// An empty `info` drops the key rather than persisting a no-op.
    func setInfo(_ info: ClassInfo, for session: ClassSession) {
        let key = hasPerma(for: session) ? session.subjectCode : session.id
        classInfo[key] = info.isEmpty ? nil : info
    }

    /// The "apply to every X block" toggle. On: flips the flag, promotes this
    /// meeting's current info to cover the whole subject, and clears its own
    /// entry so it doesn't shadow the shared one. Off: flips the flag back and
    /// demotes the subject-wide entry down to just this meeting — which does
    /// remove it from every other meeting, since "every block" is what's off.
    func setPerma(_ perma: Bool, for session: ClassSession) {
        let current = info(for: session)
        if perma {
            permaSubjects.insert(session.subjectCode)
        } else {
            permaSubjects.remove(session.subjectCode)
        }
        classInfo[session.subjectCode] = perma ? (current.isEmpty ? nil : current) : nil
        classInfo[session.id] = perma ? nil : (current.isEmpty ? nil : current)
    }
}

/// How the note editor's AI-inserted text (Replace / Insert below,
/// `notes-editor/src/editor.js`) reveals itself. Pushed to the webview by
/// `WebNoteEditor.swift`'s `PUPNotes.setAIRevealMode` — the animation itself
/// is pure CSS/JS, this enum only carries the user's pick.
enum AIRevealAnimation: String, Codable, CaseIterable, Identifiable {
    /// One continuous glow traveling start-of-line to end, escorting the
    /// words as they reveal — connected rather than each word on its own.
    case sweep
    /// Each word fades/glows in on its own — the original, kept as the
    /// alternative rather than replaced outright.
    case blink

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sweep: "Sweep"
        case .blink: "Word blink"
        }
    }
}
