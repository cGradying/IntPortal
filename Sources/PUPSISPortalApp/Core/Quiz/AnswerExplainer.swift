import Foundation

/// A short, on-demand explanation for a wrong answer during a binary-graded
/// study mode (identification/multiple-choice/true-false/matching) — what a
/// student actually gets out of missing a question, instead of just seeing
/// the right answer with no reasoning. Free text, not schema-constrained
/// JSON: `OllamaClient.generate`'s plain path (the same one `WebNoteEditor`'s
/// AI popup uses), since there's no structure here for `format` to buy.
///
/// Flashcard mode has no place to call this — a flip-and-self-rate has no
/// typed/selected wrong answer to explain against.
@MainActor
enum AnswerExplainer {
    /// `nil` on any failure — offline, empty reply, timeout — so the caller
    /// falls back to just showing the card's front/back, the same as before
    /// this existed. Never throws: an explanation is a nice-to-have, not
    /// something a failed call should interrupt the session over.
    static func explain(
        card: QuizCard, studentAnswered: String?, model: String, client: OllamaClient
    ) async -> String? {
        let selection = """
        Question: \(card.front)
        Correct answer: \(card.back)
        Student answered: \(studentAnswered?.isEmpty == false ? studentAnswered! : "(nothing / left it blank)")
        """
        return try? await client.generate(model: model, selection: selection, instruction: Self.instruction)
    }

    static let instruction = """
    A student just answered a quiz question wrong. In one or two short \
    sentences, explain why the correct answer is right and, if it's useful, \
    why what they said was off. Don't restate the question. Reply with the \
    explanation only — no preamble.
    """
}
