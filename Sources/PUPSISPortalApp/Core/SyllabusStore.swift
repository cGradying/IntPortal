import Foundation

/// What kind of syllabus entry this is — drives icon/color in the table and
/// timeline views (wayfinder tickets #13/#14), not stored logic here.
enum SyllabusItemType: String, Codable, CaseIterable, Identifiable {
    case lecture, quiz, exam, project
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lecture: "Lecture"
        case .quiz: "Quiz"
        case .exam: "Exam"
        case .project: "Project"
        }
    }
    /// SF Symbol for the Today marker (`AgendaView.syllabusMarker`) and
    /// wherever else a syllabus item needs a one-glyph icon.
    var symbol: String {
        switch self {
        case .lecture: "book"
        case .quiz: "questionmark.circle"
        case .exam: "graduationcap"
        case .project: "hammer"
        }
    }
}

/// How an item entered the syllabus — not shown prominently anywhere yet,
/// but distinguishes "the AI wrote this" from "you typed this in" for
/// whatever surface ends up caring (a future re-import shouldn't clobber a
/// manual edit, for one).
enum SyllabusItemSource: String, Codable, CaseIterable {
    case imported, generated, manual
}

/// done / ongoing / upcoming — computed by `SyllabusItem.status(now:weekOf:)`,
/// never stored. See that method for the derivation rule.
enum SyllabusStatus {
    case done, ongoing, upcoming
}

/// One entry in a subject's syllabus — a week's topic, a quiz, an exam, a
/// project deadline. Replaces `SubjectTask` (`Core/Preferences.swift`) for
/// anything the syllabus engine (wayfinder ticket #6) touches; `SubjectTask`
/// itself is untouched by this ticket, out of scope for #12 alone.
struct SyllabusItem: Codable, Identifiable, Equatable {
    let id: UUID
    var subjectCode: String
    /// Week number within the term, if the source syllabus is organized that
    /// way — optional because a generated-from-scratch or manually-added
    /// item may only have a date, no week grid to place it in.
    var week: Int?
    var topic: String
    /// Optional — an imported syllabus item may not carry a real date until
    /// the user (or a later AI pass) maps it onto the actual term calendar.
    var date: Date?
    var type: SyllabusItemType
    var source: SyllabusItemSource
    /// Links this item to a full write-up in the notes vault — nil until the
    /// user (or the AI) actually creates one. Not a `class:`/`day:` key; a
    /// `vault:<uuid>` key like any other vault file.
    var notesKey: String?
    /// Wins over the live date-derived status when non-nil: `true` marks it
    /// done regardless of date (finished early); `false` keeps it visibly
    /// not-done even past its date (fell behind) — mirrors how
    /// `Preferences.status(for:)` already overrides a class's derived
    /// in-person/vacant/online state rather than storing the live state
    /// itself.
    var completedOverride: Bool?

    init(
        id: UUID = UUID(), subjectCode: String, week: Int? = nil, topic: String,
        date: Date? = nil, type: SyllabusItemType, source: SyllabusItemSource,
        notesKey: String? = nil, completedOverride: Bool? = nil
    ) {
        self.id = id
        self.subjectCode = subjectCode
        self.week = week
        self.topic = topic
        self.date = date
        self.type = type
        self.source = source
        self.notesKey = notesKey
        self.completedOverride = completedOverride
    }

    /// Live derivation, not a stored field, so it can't drift out of sync
    /// with the calendar the way a cached status would — same reasoning
    /// `DayAgenda`/`ClassSession` already apply to "is this happening now."
    /// `weekOf` is injected (not `Weekday.weekStart` called directly) so
    /// tests don't need a real calendar week to reason about.
    func status(now: Date, weekOf: (Date) -> Date) -> SyllabusStatus {
        if let override = completedOverride {
            if override { return .done }
            guard let date else { return .upcoming }
            return weekOf(date) == weekOf(now) ? .ongoing : .upcoming
        }
        guard let date else { return .upcoming }
        // Same-week wins first: a Monday item is still "this week" — i.e.
        // ongoing — on Thursday, even though Monday itself is already in
        // the past by the strict day comparison below.
        if weekOf(date) == weekOf(now) { return .ongoing }
        return Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: now) ? .done : .upcoming
    }
}

/// The syllabus vault: every subject's items, one JSON document — same shape
/// as `NotesStore` (`~/Library/Application Support/PUPSISPortal/syllabus.json`,
/// file `0600`, injectable `@MainActor ObservableObject`) rather than
/// `Preferences`/`UserDefaults`. A syllabus holds real content (topics, a
/// generated guide's own text via `notesKey`) growing across a whole term —
/// document-shaped, not preference-shaped, unlike the flat `SubjectTask` it
/// replaces for anything the syllabus engine touches.
@MainActor
final class SyllabusStore: ObservableObject {
    @Published private(set) var items: [String: [SyllabusItem]]
    /// Each subject's grading-system breakdown, keyed by subject code — same
    /// key space as `items`, a second dictionary rather than a field on
    /// `SyllabusItem` because a grading breakdown belongs to the *subject*,
    /// not to any one week's topic.
    @Published private(set) var gradingComponents: [String: [GradingComponent]]
    private let url: URL

    private struct Document: Codable {
        var items: [String: [SyllabusItem]]
        var gradingComponents: [String: [GradingComponent]]

        /// Manual `Codable` so a `syllabus.json` written before grading
        /// components existed still loads — a missing key decodes as empty
        /// rather than failing the whole document.
        enum CodingKeys: String, CodingKey { case items, gradingComponents }

        init(items: [String: [SyllabusItem]], gradingComponents: [String: [GradingComponent]] = [:]) {
            self.items = items
            self.gradingComponents = gradingComponents
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decode([String: [SyllabusItem]].self, forKey: .items)
            gradingComponents = try container.decodeIfPresent([String: [GradingComponent]].self, forKey: .gradingComponents) ?? [:]
        }
    }

    static let defaultURL: URL = {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support
            .appendingPathComponent("PUPSISPortal", isDirectory: true)
            .appendingPathComponent("syllabus.json")
    }()

    init(url: URL = defaultURL) {
        self.url = url
        let document = Self.load(from: url)
        items = document.items
        gradingComponents = document.gradingComponents
    }

    /// A subject's items, in the order they were added — callers wanting
    /// date/week order sort themselves (the table and timeline views want
    /// different orderings, so there's no one "right" sort to bake in here).
    func items(for subjectCode: String) -> [SyllabusItem] {
        items[subjectCode] ?? []
    }

    /// Every item across every subject — `read_syllabus`/assistant tools
    /// (wayfinder ticket #15) and any cross-subject view want this flat.
    func allItems() -> [SyllabusItem] {
        items.values.flatMap { $0 }
    }

    /// Every item whose `date` falls on the same calendar day as `date` —
    /// the read path for the week-grid day header badge and the Today
    /// timeline's marker row (wayfinder ticket #13). An item with no `date`
    /// never matches here; it only shows wherever an undated list surfaces
    /// items (the table/timeline views, ticket #14).
    func items(on date: Date, calendar: Calendar = .current) -> [SyllabusItem] {
        allItems().filter { item in
            guard let itemDate = item.date else { return false }
            return calendar.isDate(itemDate, inSameDayAs: date)
        }
    }

    @discardableResult
    func addItem(_ item: SyllabusItem) -> SyllabusItem {
        items[item.subjectCode, default: []].append(item)
        persist()
        return item
    }

    /// Matched by `id` within `updated.subjectCode`'s list — if the subject
    /// code itself changed, the item is removed from its old subject's list
    /// first so it doesn't end up listed twice.
    func updateItem(_ updated: SyllabusItem) {
        for subject in items.keys where subject != updated.subjectCode {
            items[subject]?.removeAll { $0.id == updated.id }
        }
        var list = items[updated.subjectCode] ?? []
        if let index = list.firstIndex(where: { $0.id == updated.id }) {
            list[index] = updated
        } else {
            list.append(updated)
        }
        items[updated.subjectCode] = list
        persist()
    }

    func removeItem(_ id: UUID, subjectCode: String) {
        items[subjectCode]?.removeAll { $0.id == id }
        persist()
    }

    /// Settings ▸ Misc's eventual "Delete All Syllabus Data" action, same
    /// shape as `NotesStore.wipeAll` — nothing computed as "still referenced
    /// elsewhere" first, there's nothing left to keep.
    func wipeAll() {
        items = [:]
        gradingComponents = [:]
        persist()
    }

    // MARK: Grading components

    func components(for subjectCode: String) -> [GradingComponent] {
        gradingComponents[subjectCode] ?? []
    }

    /// Replaces a subject's whole breakdown — extraction always hands back
    /// the complete list for a subject, never one component at a time, so
    /// there's no separate add/remove pair to keep in sync with it.
    func setComponents(_ components: [GradingComponent], for subjectCode: String) {
        gradingComponents[subjectCode] = components
        persist()
    }

    /// The one field the student actually edits after extraction — what they
    /// scored on a component, once it's back. Everything else about a
    /// component (name, weight) came from the syllabus and stays fixed.
    func setScore(_ score: Double?, forComponent id: UUID, subjectCode: String) {
        guard var list = gradingComponents[subjectCode],
              let index = list.firstIndex(where: { $0.id == id })
        else { return }
        list[index].score = score
        gradingComponents[subjectCode] = list
        persist()
    }

    // MARK: Disk

    private func persist() {
        guard let data = try? JSONEncoder().encode(Document(items: items, gradingComponents: gradingComponents)) else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        // The user's own syllabus data — readable by them, nobody else on the machine.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func load(from url: URL) -> Document {
        guard let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(Document.self, from: data)
        else { return Document(items: [:]) }
        return document
    }
}
