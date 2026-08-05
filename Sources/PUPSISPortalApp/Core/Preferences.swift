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

    /// `ClassSession.id` → status. Keyed per *meeting*, not per subject: one
    /// section can be in person on Tuesday and online on Friday.
    @Published private(set) var sessionStatuses: [String: SessionStatus] {
        didSet { defaults.set(try? JSONEncoder().encode(sessionStatuses), forKey: Key.sessionStatuses) }
    }

    private let defaults: UserDefaults

    private enum Key {
        static let theme = "theme"
        static let subjectColors = "subjectColors"
        static let sessionStatuses = "sessionStatuses"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = defaults.string(forKey: Key.theme).flatMap(ThemeChoice.init(rawValue:)) ?? .auto
        subjectColors = defaults.data(forKey: Key.subjectColors)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        sessionStatuses = defaults.data(forKey: Key.sessionStatuses)
            .flatMap { try? JSONDecoder().decode([String: SessionStatus].self, from: $0) } ?? [:]
    }

    func status(for session: ClassSession) -> SessionStatus {
        sessionStatuses[session.id] ?? .regular
    }

    func setStatus(_ status: SessionStatus, for session: ClassSession) {
        // Don't store the default — an absent key and `.regular` mean the same
        // thing, and not storing it keeps the dictionary to what was changed.
        sessionStatuses[session.id] = status == .regular ? nil : status
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
}
