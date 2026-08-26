import Foundation

/// Where the source text for a generation run comes from.
enum QuizSource {
    /// A topic the user typed — retrieved via the existing RAG pipeline,
    /// which already honors `NotesStore.ragIncludedKeys()`.
    case vaultTopic(String)
    /// Material the user supplied directly — pasted text or an imported
    /// file's extracted text, plus a label for citations and the deck's
    /// `sourceQuery`.
    case material(text: String, label: String)
}

/// Generates flashcards from a `QuizSource` via `OllamaClient.chat`'s
/// schema-constrained JSON path — the same `format`-param approach
/// `AssistantEngine` uses, including its control-character salvage fix
/// (`AssistantEngine.escapingRawControlCharacters`), because a model
/// producing multi-line back text hits the exact same literal-newline-in-a-
/// JSON-string failure the engine already found and fixed.
///
/// One chunk, one request: the model's context is the real limit on how much
/// source text a single call can use, so generation loops over chunks rather
/// than sending the whole note/material at once — this is what keeps long
/// material from being silently truncated or degenerating into padding.
@MainActor
enum CardGenerator {
    /// One generation run's outcome. Partial results are kept on failure —
    /// `stream: false`, 180s timeout, no retries anywhere in `OllamaClient`,
    /// so losing a late chunk must never cost the chunks that already
    /// succeeded.
    struct Result {
        var cards: [QuizCard]
        var failedChunks: Int
        var totalChunks: Int
        /// True when `.material` source text had more chunks than
        /// `maxChunksPerRun` and the rest was left unused — surfaced so the
        /// UI can say so instead of silently studying only part of what was
        /// pasted/imported.
        var truncatedMaterial: Bool = false
    }

    /// A `.material` run's hard chunk ceiling — `.vaultTopic` never needs
    /// this, `RAGQuery.search` already returns at most 6 ranked chunks. This
    /// is what keeps a huge paste/import from becoming dozens of sequential
    /// 180s-timeout calls that reads as a hang.
    static let maxChunksPerRun = 12

    /// Not user-facing copy — `sourceKind`/`sourceQuery` on the deck carry
    /// that; this only decides how the source text is chunked and what
    /// citation each card gets.
    static func run(
        source: QuizSource,
        model: String,
        client: OllamaClient,
        ragQuery: RAGQuery?,
        chunkSize: Int,
        targetCount: Int? = nil,
        onProgress: (Int, Int) -> Void = { _, _ in },
        isCancelled: () -> Bool = { false }
    ) async -> Result {
        let (chunks, truncatedMaterial) = await resolveChunks(source: source, ragQuery: ragQuery, chunkSize: chunkSize)
        guard !chunks.isEmpty else {
            return Result(cards: [], failedChunks: 0, totalChunks: 0, truncatedMaterial: truncatedMaterial)
        }

        var allCards: [QuizCard] = []
        var seenFronts: Set<String> = []
        var failed = 0

        for (index, chunk) in chunks.enumerated() {
            if isCancelled() { break }
            onProgress(index, chunks.count)
            guard let cards = await generateCardsWithRetry(
                from: chunk, model: model, client: client, targetCount: targetCount
            ) else {
                failed += 1
                continue
            }
            for card in cards where !seenFronts.contains(card.normalizedFront) {
                seenFronts.insert(card.normalizedFront)
                allCards.append(card)
            }
        }
        onProgress(chunks.count, chunks.count)
        return Result(cards: allCards, failedChunks: failed, totalChunks: chunks.count, truncatedMaterial: truncatedMaterial)
    }

    private static func resolveChunks(
        source: QuizSource, ragQuery: RAGQuery?, chunkSize: Int
    ) async -> (chunks: [NoteChunk], truncatedMaterial: Bool) {
        switch source {
        case .vaultTopic(let topic):
            guard let ragQuery else { return ([], false) }
            return (await ragQuery.search(topic), false)
        case .material(let text, let label):
            let all = NoteRetrieval.chunks(of: text, key: "material", name: label, maxChars: chunkSize)
            guard all.count > maxChunksPerRun else { return (all, false) }
            return (Array(all.prefix(maxChunksPerRun)), true)
        }
    }

    /// One attempt at `targetCount` (or the mode default); on a decode
    /// failure — most often a truncated reply, the model ran out of
    /// `num_predict` before closing the JSON — one retry at half the count
    /// (floor 3) with a correspondingly smaller budget. Only a *second*
    /// failure counts the chunk as failed, so "asked for too much" degrades
    /// to fewer real cards instead of none.
    private static func generateCardsWithRetry(
        from chunk: NoteChunk, model: String, client: OllamaClient, targetCount: Int?
    ) async -> [QuizCard]? {
        if let cards = try? await generateCards(from: chunk, model: model, client: client, targetCount: targetCount) {
            return cards
        }
        let retryCount = max((targetCount ?? maxCardsPerChunk) / 2, 3)
        return try? await generateCards(from: chunk, model: model, client: client, targetCount: retryCount)
    }

    private struct GeneratedCard: Decodable {
        let front: String
        let back: String
        let subject: String?
        let acceptedAnswers: [String]?
    }

    private struct GeneratedDeck: Decodable {
        let cards: [GeneratedCard]
    }

    private static func generateCards(
        from chunk: NoteChunk, model: String, client: OllamaClient, targetCount: Int?
    ) async throws -> [QuizCard] {
        let count = targetCount ?? maxCardsPerChunk
        let raw = try await client.chat(
            model: model,
            messages: [
                .init(role: .system, content: instruction(targetCount: targetCount)),
                .init(role: .user, content: "Source (\(chunk.name)):\n\(chunk.text)"),
            ],
            schema: schema(targetCount: targetCount),
            numPredict: numPredict(for: count)
        ).content
        // Same reasoning as AssistantEngine.decodeOrThrow: sanitize before
        // decoding, not after a caught failure, because a literal newline in
        // a JSON string can make JSONDecoder silently drop just that field
        // rather than throw.
        let sanitized = AssistantEngine.escapingRawControlCharacters(in: raw)
        guard let data = sanitized.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(GeneratedDeck.self, from: data)
        else {
            throw OllamaClient.ClientError.empty
        }
        return decoded.cards.compactMap { generated -> QuizCard? in
            let front = generated.front.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = generated.back.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty else { return nil }
            let accepted = (generated.acceptedAnswers ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return QuizCard(
                front: front,
                back: back,
                subject: generated.subject?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? chunk.name,
                citation: chunk.name,
                acceptedAnswers: accepted.isEmpty ? nil : accepted
            )
        }
    }

    private static let maxCardsPerChunk = 15

    /// Sized to comfortably fit `count` cards' worth of JSON — front/back/
    /// subject text, up to 2 accepted-answer alternates, plus punctuation
    /// overhead — without asking the model to ramble past what's needed.
    /// 190 tokens/card covers the "one short sentence each" the instruction
    /// asks for plus its accepted answers; 200 covers the envelope
    /// (`{"cards":[...]}` plus the model's own formatting slack).
    static func numPredict(for count: Int) -> Int {
        min(190 * count + 200, 4096)
    }

    private static func instruction(targetCount: Int?) -> String {
        let countLine = targetCount.map { "Produce exactly \($0) cards if the material supports it." }
            ?? "Produce as many cards as the material genuinely supports — don't pad with filler or restate the same fact twice."
        return """
        You are writing spaced-repetition flashcards for a student, from the study material below.
        Each card is one atomic fact or concept — a question or prompt on the front, the answer on the back.
        \(countLine)
        Never invent facts not present in the material. Keep front and back short — one sentence each, no lists.
        If there's a clearly different correct phrasing of the answer, include up to 2 in acceptedAnswers — otherwise leave it empty.
        Reply with JSON only, matching the given schema.
        """
    }

    private static func schema(targetCount: Int?) -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "cards": [
                    "type": "array",
                    "maxItems": targetCount ?? maxCardsPerChunk,
                    "items": [
                        "type": "object",
                        "properties": [
                            "front": ["type": "string"],
                            "back": ["type": "string"],
                            "subject": ["type": "string"],
                            "acceptedAnswers": ["type": "array", "items": ["type": "string"], "maxItems": 2],
                        ],
                        "required": ["front", "back"],
                    ],
                ],
            ],
            "required": ["cards"],
        ]
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
