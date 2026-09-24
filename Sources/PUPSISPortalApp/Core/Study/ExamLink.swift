import Foundation

/// Spec 11 upgrade 2: which decks an exam is actually about, so the exam
/// countdown banner can name a deck and a mastery number instead of just a
/// day count.
enum ExamLink {
    /// Decks linked to `item` (an exam): every one of the deck's cards
    /// carries `item.subjectCode` as its subject, and the deck's name or
    /// `sourceQuery` shares a topic word with a lecture that happened before
    /// the exam. `lectures` is the exam's subject's own syllabus items —
    /// the syllabus is the only source of "topic" here, so a deck that never
    /// lines up with a taught lecture doesn't link even when the subject
    /// matches.
    static func decks(for item: SyllabusItem, in decks: [QuizDeck], lectures: [SyllabusItem]) -> [QuizDeck] {
        guard item.type == .exam, let examDate = item.date else { return [] }

        let priorLectureTokens: [Set<String>] = lectures
            .filter { $0.type == .lecture && $0.subjectCode == item.subjectCode }
            .compactMap { lecture in
                guard let lectureDate = lecture.date, lectureDate < examDate else { return nil }
                return tokens(in: lecture.topic)
            }

        return decks.filter { deck in
            guard !deck.cards.isEmpty, deck.cards.allSatisfy({ $0.subject == item.subjectCode }) else {
                return false
            }
            let deckTokens = tokens(in: deck.name).union(tokens(in: deck.sourceQuery))
            return priorLectureTokens.contains { !$0.isDisjoint(with: deckTokens) }
        }
    }

    // ponytail: naive token match (lowercased words, 4+ letters, no
    // stemming) — good enough to match "Number systems" to a "Numbering
    // Systems" deck, not good enough for real synonyms. Upgrade to a real
    // topic-tagging pass if this starts missing obvious links.
    private static func tokens(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 4 }
        )
    }
}
