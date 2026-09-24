import Foundation

/// Spec 11 upgrade 6: the isometric study map — regions (subjects) of tiles
/// (topics), laid out on a grid. Actual isometric pixel projection is a
/// drawing-time concern for whatever `Canvas` renders this; this type only
/// decides which tiles exist, their grid position, and how tall their tower
/// is.
enum StudyMap {
    /// One subject's row on the map.
    struct Subject {
        var code: String
        /// Lecture topics from the syllabus, in week order. Falls back to
        /// `deckNames` for a subject the syllabus hasn't covered yet, so the
        /// map still has something to click into "Generate deck" from.
        var lectureTopics: [String]
        var deckNames: [String]
        /// Mastery (0...1) per topic/deck name; missing entries read as 0.
        var mastery: [String: Double]
        /// Days until an exam covers this topic, if any. 0 = today, negative
        /// = overdue; missing entries mean no exam covers it.
        var examDaysAway: [String: Int]
    }

    struct Tile: Equatable {
        var subject: String
        var topic: String
        var mastery: Double
        var goldPip: Bool
        var towerHeight: Double?
        var column: Int
        var row: Int
    }

    /// Mastery at or above this earns the gold pip.
    static let masteryPipThreshold = 0.7
    /// The formula's own value at day 0 — only an overdue exam would climb
    /// past it otherwise, and a tower taller than this runs off the tile.
    static let maxTowerHeight = 5.5

    static func layout(subjects: [Subject]) -> [Tile] {
        var tiles: [Tile] = []
        for (row, subject) in subjects.enumerated() {
            let topics = subject.lectureTopics.isEmpty ? subject.deckNames : subject.lectureTopics
            for (column, topic) in topics.enumerated() {
                let mastery = subject.mastery[topic] ?? 0
                tiles.append(Tile(
                    subject: subject.code,
                    topic: topic,
                    mastery: mastery,
                    goldPip: mastery >= masteryPipThreshold,
                    towerHeight: subject.examDaysAway[topic].map(towerHeight(daysAway:)),
                    column: column,
                    row: row
                ))
            }
        }
        return tiles
    }

    /// `1 + (5 − days) × 0.9` block heights: a tower starts at 1 block five
    /// days out and climbs a block a day closer, capped at
    /// `maxTowerHeight` so an overdue exam doesn't draw off the tile.
    static func towerHeight(daysAway days: Int) -> Double {
        min(maxTowerHeight, max(1, 1 + Double(5 - days) * 0.9))
    }
}
