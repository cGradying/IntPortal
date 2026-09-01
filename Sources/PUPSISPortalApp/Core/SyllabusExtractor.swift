import Foundation

/// Where a syllabus generation run's items come from.
enum SyllabusSource {
    /// Imported/pasted syllabus text — chunked, one request per chunk, same
    /// as `CardGenerator`'s `.material`.
    case material(text: String, label: String)
    /// No source text: ask the model for a plausible term outline. One
    /// request, no chunking.
    case fromScratch(description: String)
}

/// Extracts `SyllabusItem`s from a `SyllabusSource` via the same schema-
/// constrained `LlamaCppClient.chat` path `CardGenerator` uses for quiz
/// cards — chunked material, one request per chunk, partial results kept on
/// failure, `AssistantEngine.escapingRawControlCharacters` before decoding.
///
/// Deliberately its own type rather than a mode of `CardGenerator`: the
/// output shape (syllabus items, not flashcards) and the date-mapping step
/// (week number → real date, computed here, never by the model — see
/// `AssistantScheduleSnapshot` for why dates are never the model's job) are
/// different enough that sharing one generic generator would cost more
/// indirection than the ~150 lines this duplicates.
@MainActor
enum SyllabusExtractor {
    struct Result {
        var items: [SyllabusItem]
        var failedChunks: Int
        var totalChunks: Int
        /// True when `.material` source text had more chunks than
        /// `maxChunksPerRun` and the rest was left unused.
        var truncatedMaterial: Bool = false
        /// The subject's grading-system breakdown, if the source text
        /// printed one — empty for `.fromScratch` (a generated outline has
        /// no real grading weights to report) and for real syllabi that
        /// simply don't include one.
        var gradingComponents: [GradingComponent] = []
    }

    /// Same ceiling as `CardGenerator.maxChunksPerRun` for the same reason —
    /// keeps a huge paste/import from becoming dozens of sequential
    /// 180s-timeout calls.
    static let maxChunksPerRun = 12

    static func run(
        source: SyllabusSource,
        subjectCode: String,
        termStart: Date,
        model: String,
        client: LlamaCppClient,
        chunkSize: Int,
        onProgress: (Int, Int) -> Void = { _, _ in },
        isCancelled: () -> Bool = { false },
        ensureServerRunning: (() async -> Bool)? = nil
    ) async -> Result {
        let (chunks, truncatedMaterial) = resolveChunks(source: source, chunkSize: chunkSize)
        guard !chunks.isEmpty else {
            return Result(items: [], failedChunks: 0, totalChunks: 0, truncatedMaterial: truncatedMaterial)
        }
        let serverReady = await (ensureServerRunning ?? { await LlamaRuntime.ensureChatServer(modelID: model) })()
        guard serverReady else {
            return Result(items: [], failedChunks: chunks.count, totalChunks: chunks.count, truncatedMaterial: truncatedMaterial)
        }

        var allItems: [SyllabusItem] = []
        var seenKeys: Set<String> = []
        var gradingComponents: [GradingComponent] = []
        var failed = 0

        for (index, chunk) in chunks.enumerated() {
            if isCancelled() { break }
            onProgress(index, chunks.count)
            guard let generated = await generateItemsWithRetry(
                from: chunk, subjectCode: subjectCode, termStart: termStart,
                source: chunk.source, model: model, client: client
            ) else {
                failed += 1
                continue
            }
            for item in generated.items where !seenKeys.contains(dedupeKey(item)) {
                seenKeys.insert(dedupeKey(item))
                allItems.append(item)
            }
            // A grading breakdown lives in exactly one section of a real
            // syllabus — the first chunk that finds one wins, later chunks'
            // (usually empty, occasionally a hallucinated re-statement) are
            // ignored rather than merged into duplicates.
            if gradingComponents.isEmpty, !generated.gradingComponents.isEmpty {
                gradingComponents = generated.gradingComponents
            }
        }
        onProgress(chunks.count, chunks.count)
        return Result(
            items: allItems, failedChunks: failed, totalChunks: chunks.count,
            truncatedMaterial: truncatedMaterial, gradingComponents: gradingComponents
        )
    }

    /// `(week, topic)` normalized the same way `CardGenerator` dedupes on
    /// `normalizedFront` — a chunk boundary landing mid-week can otherwise
    /// surface the same topic twice from adjacent chunks.
    private static func dedupeKey(_ item: SyllabusItem) -> String {
        "\(item.week.map(String.init) ?? "-")|\(item.topic.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    // MARK: - Chunking

    /// One chunk of source text plus which `SyllabusItemSource` an item
    /// extracted from it should carry.
    private struct Chunk {
        let name: String
        let text: String
        let source: SyllabusItemSource
    }

    private static func resolveChunks(source: SyllabusSource, chunkSize: Int) -> (chunks: [Chunk], truncatedMaterial: Bool) {
        switch source {
        case .material(let text, let label):
            let all = NoteRetrieval.chunks(of: text, key: "syllabus-material", name: label, maxChars: chunkSize)
                .map { Chunk(name: $0.name, text: $0.text, source: .imported) }
            guard all.count > maxChunksPerRun else { return (all, false) }
            return (Array(all.prefix(maxChunksPerRun)), true)
        case .fromScratch(let description):
            return ([Chunk(name: description, text: description, source: .generated)], false)
        }
    }

    // MARK: - Generation

    private struct Generated {
        var items: [SyllabusItem]
        var gradingComponents: [GradingComponent]
    }

    /// One attempt; on a decode failure — most often a truncated reply — one
    /// retry with a smaller output budget. Only a *second* failure counts the
    /// chunk as failed.
    private static func generateItemsWithRetry(
        from chunk: Chunk, subjectCode: String, termStart: Date, source: SyllabusItemSource,
        model: String, client: LlamaCppClient
    ) async -> Generated? {
        if let generated = try? await generateItems(
            from: chunk, subjectCode: subjectCode, termStart: termStart, source: source,
            model: model, client: client, numPredict: numPredict(forChars: chunk.text.count)
        ) {
            return generated
        }
        return try? await generateItems(
            from: chunk, subjectCode: subjectCode, termStart: termStart, source: source,
            model: model, client: client, numPredict: numPredict(forChars: chunk.text.count) / 2
        )
    }

    private struct GeneratedItem: Decodable {
        let week: Int?
        let topic: String
        let date: String?
        let type: String?
    }

    private struct GeneratedComponent: Decodable {
        let name: String
        let weight: Double
    }

    private struct GeneratedSyllabus: Decodable {
        let items: [GeneratedItem]
        let gradingComponents: [GeneratedComponent]?
    }

    private static func generateItems(
        from chunk: Chunk, subjectCode: String, termStart: Date, source: SyllabusItemSource,
        model: String, client: LlamaCppClient, numPredict: Int
    ) async throws -> Generated {
        let raw = try await client.chat(
            model: model,
            messages: [
                .init(role: .system, content: instruction(fromScratch: source == .generated)),
                .init(role: .user, content: "Subject: \(subjectCode)\nSource (\(chunk.name)):\n\(chunk.text)"),
            ],
            schema: schema,
            numPredict: numPredict
        ).content
        // Same reasoning as CardGenerator/AssistantEngine: sanitize before
        // decoding, since a literal newline inside a JSON string can make
        // JSONDecoder silently drop just that field rather than throw.
        let sanitized = AssistantEngine.escapingRawControlCharacters(in: raw)
        guard let data = sanitized.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(GeneratedSyllabus.self, from: data)
        else {
            throw LlamaCppClient.ClientError.empty
        }
        let items = decoded.items.compactMap { generated -> SyllabusItem? in
            let topic = generated.topic.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !topic.isEmpty else { return nil }
            return SyllabusItem(
                subjectCode: subjectCode,
                week: generated.week,
                topic: topic,
                date: resolvedDate(generated: generated, termStart: termStart),
                type: generated.type.flatMap(SyllabusItemType.init(rawValue:)) ?? .lecture,
                source: source
            )
        }
        // Never trusted from a from-scratch run — those weights would be
        // entirely invented, unlike the topics (which are already clearly
        // labeled generated); a fabricated grading breakdown is worse than
        // none.
        let components: [GradingComponent] = source == .generated ? [] : (decoded.gradingComponents ?? []).compactMap { generated in
            let name = generated.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, generated.weight > 0 else { return nil }
            return GradingComponent(name: name, weight: generated.weight)
        }
        return Generated(items: items, gradingComponents: components)
    }

    /// The model never computes a date — same rule `AssistantEngine`'s system
    /// prompt already enforces for the assistant tool path. A `date` string
    /// is only trusted when the source text literally printed one (parsed
    /// here, not by the model); otherwise `week` maps onto the real calendar
    /// via the user-supplied `termStart`.
    private static func resolvedDate(generated: GeneratedItem, termStart: Date) -> Date? {
        if let raw = generated.date, let parsed = parseLiteralDate(raw) {
            return parsed
        }
        guard let week = generated.week, week >= 1 else { return nil }
        return Calendar.current.date(byAdding: .day, value: 7 * (week - 1), to: termStart)
    }

    /// Local-time zone, not UTC — a `YYYY-MM-DD` from a syllabus means "that
    /// calendar day where the student is," same as `termStart`/`Calendar.current`
    /// everywhere else in this file, not midnight UTC.
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = .current
        return f
    }()

    private static func parseLiteralDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return isoFormatter.date(from: trimmed)
    }

    // MARK: - Prompt / schema

    /// Sized for a chunk's worth of syllabus items — one week's worth of
    /// topics per chunk is typically small, so this is deliberately looser
    /// than `CardGenerator`'s per-card budget rather than tuned per item
    /// count (a syllabus chunk's item count varies far more than a
    /// flashcard run's fixed target).
    private static func numPredict(forChars charCount: Int) -> Int {
        min(max(charCount, 400), 3200)
    }

    private static func instruction(fromScratch: Bool) -> String {
        if fromScratch {
            return """
            You are drafting a plausible study-guide outline for a college course, from only its subject code and a short description — not a real syllabus. This is clearly a generated guide, not the actual course syllabus.
            Produce a reasonable weekly topic sequence for a typical term (aim for 12–18 weeks). Use week for each entry; never invent a real calendar date.
            Include a handful of quiz/exam/project milestones spaced through the term, typed correctly (lecture/quiz/exam/project).
            Reply with JSON only, matching the given schema.
            """
        }
        return """
        You are structuring a real course syllabus into a list of dated/weekly items, from the source text below.
        For each week's topic, quiz, exam, or project deadline, emit one item. Keep topic text close to the source rather than paraphrasing it.
        Use week when the source organizes by week number. Only fill date when the source text literally prints a real calendar date near that item — write it as YYYY-MM-DD. Never invent or compute a date yourself.
        type must be one of: lecture, quiz, exam, project.
        If this chunk contains the grading system / grade breakdown (e.g. "Midterm Exam — 30%, Quizzes — 20%, Final Project — 25%, Attendance — 25%"), also emit it in gradingComponents — name and weight (a number 0–100) for each, copied from the source, never invented. Leave gradingComponents empty if this chunk doesn't contain one.
        Reply with JSON only, matching the given schema.
        """
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "items": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "week": ["type": ["integer", "null"]],
                        "topic": ["type": "string"],
                        "date": ["type": ["string", "null"]],
                        "type": ["type": "string", "enum": ["lecture", "quiz", "exam", "project"]],
                    ],
                    "required": ["topic", "type"],
                ],
            ],
            "gradingComponents": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "weight": ["type": "number"],
                    ],
                    "required": ["name", "weight"],
                ],
            ],
        ],
        "required": ["items"],
    ]
}
