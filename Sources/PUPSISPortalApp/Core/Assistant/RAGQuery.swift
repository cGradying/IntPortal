import Foundation

/// The RAG pipeline itself: rank the vault's RAG-included notes against a
/// query (embeddings via the `.embed`-role `llama-server`, falling back to
/// term matching when that's unavailable), then ask the `.chat`-role server
/// for one synthesized answer. Shared by two entry points — `ask_notes`/
/// `search_notes` (the model decides when to call these, and small models
/// are unreliable at that — confirmed live) and the `/rag "prompt"` slash
/// command (deterministic, always runs, no tool-picking involved). Same
/// retrieval, same answer model, two ways in — extracted here so neither
/// reimplements it.
///
/// Every tunable is a plain init parameter defaulted to the shipped value,
/// not a `Preferences` dependency — keeps this a pure, easily-testable
/// pipeline. `RealAssistantExecutor`/`AssistantCommandRunner` read
/// `preferences.rag*` and pass them through when building their default
/// instance; Settings ▸ Misc is what actually edits those preferences.
@MainActor
struct RAGQuery {
    private let notesStore: NotesStore
    private let client: LlamaCppClient
    private let ensureChatServerRunning: () async -> Bool
    private let ensureEmbedServerRunning: () async -> Bool
    private let chunkSize: Int
    private let similarityFloor: Double
    private let contextBudget: Int
    private let answerTemperature: Double
    private let answerModel: String

    init(
        notes: NotesStore,
        client: LlamaCppClient = LlamaCppClient(),
        /// Defaults to resolving `answerModel` through `LlamaRuntime` —
        /// override in tests to skip the real process-management path
        /// entirely.
        ensureChatServerRunning: (() async -> Bool)? = nil,
        ensureEmbedServerRunning: @escaping () async -> Bool = { await LlamaRuntime.ensureEmbedServer() },
        chunkSize: Int = 700,
        similarityFloor: Double = 0.35,
        contextBudget: Int = 4000,
        answerTemperature: Double = 0.2,
        /// The catalog model id that answers (`Preferences.aiModel`) —
        /// resolved to a local `llama-server` process, not passed in any
        /// request body (see `LlamaCppClient`'s own doc comment on why
        /// `model` request fields are vestigial there).
        answerModel: String = ""
    ) {
        self.notesStore = notes
        self.client = client
        self.ensureChatServerRunning = ensureChatServerRunning ?? { await LlamaRuntime.ensureChatServer(modelID: answerModel) }
        self.ensureEmbedServerRunning = ensureEmbedServerRunning
        self.chunkSize = chunkSize
        self.similarityFloor = similarityFloor
        self.contextBudget = contextBudget
        self.answerTemperature = answerTemperature
        self.answerModel = answerModel
    }

    struct Answer {
        let text: String
        let sources: [String]
    }

    enum QueryError: LocalizedError, Equatable {
        case noMatch(String)
        case serverUnavailable

        var errorDescription: String? {
            switch self {
            case .noMatch(let query):
                "No notes matched \"\(query)\", so there's nothing to answer from."
            case .serverUnavailable:
                "Couldn't start the local model server. Is a model downloaded in Settings ▸ AI, and is llama.cpp installed? (`brew install llama.cpp`)"
            }
        }
    }

    /// Ranked snippets — what `search_notes` lists.
    func search(_ query: String) async -> [NoteChunk] {
        await rankedChunks(for: query)
    }

    /// One grounded answer — what `ask_notes` and `/rag` both produce.
    /// `.noMatch` and `.serverUnavailable` are expected, handleable outcomes
    /// (an empty vault, no model downloaded yet); anything `client` itself
    /// throws (its own `.offline`/`.http`/`.empty`) propagates as-is.
    func ask(_ query: String) async throws -> Answer {
        let hits = await rankedChunks(for: query)
        guard !hits.isEmpty else { throw QueryError.noMatch(query) }
        guard await ensureChatServerRunning() else { throw QueryError.serverUnavailable }

        // Truncates an over-budget hit to whatever room is left rather than
        // skipping it outright — a top-ranked match (a whole note pasted with
        // no blank lines, easily bigger than the budget on its own) must
        // never be silently dropped just because it doesn't fit whole. That
        // silent drop was the actual "not hitting the notes" bug: the loop
        // used to `continue` past an oversized top hit and fill the budget
        // with smaller, unrelated ones instead.
        var packed = ""
        var sourceNames: [String] = []
        for hit in hits {
            let block = "\(hit.name):\n\(hit.text)"
            let separator = packed.isEmpty ? "" : "\n\n"
            let remaining = contextBudget - packed.count - separator.count
            guard remaining > 0 else { break }
            packed += separator + (block.count <= remaining ? block : String(block.prefix(remaining)))
            if !sourceNames.contains(hit.name) { sourceNames.append(hit.name) }
        }

        let text = try await answer(notes: packed, query: query)
        return Answer(text: text, sources: sourceNames)
    }

    private static let answerSystemPrompt = "Answer the question using only the notes given. If the notes don't contain the answer, say so plainly rather than guessing."

    private func answer(notes packed: String, query: String) async throws -> String {
        let reply = try await client.chat(
            messages: [
                .init(role: .system, content: Self.answerSystemPrompt),
                .init(role: .user, content: "Notes:\n\(packed)\n\nQuestion: \(query)"),
            ],
            schema: ["type": "object", "properties": ["answer": ["type": "string"]], "required": ["answer"]],
            temperature: answerTemperature
        )
        struct Answer: Decodable { let answer: String }
        guard let data = reply.content.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Answer.self, from: data)
        else { throw LlamaCppClient.ClientError.empty }
        return decoded.answer
    }

    /// Every RAG-included note, chunked — the pool both `search`/`ask` rank
    /// over. Only notes the user has left in the RAG
    /// (`NotesStore.ragIncludedKeys`) are ever searched — the right-click
    /// "Include in AI search" toggle.
    private func ragChunks() -> [NoteChunk] {
        let included = notesStore.ragIncludedKeys()
        return notesStore.notes.compactMap { key, note -> [NoteChunk]? in
            guard included.contains(key) else { return nil }
            return NoteRetrieval.chunks(of: note.text, key: key, name: displayName(for: key), maxChars: chunkSize)
        }.flatMap { $0 }
    }

    /// Embeds the query plus every chunk in **one** batched request (so
    /// ranking costs one round trip regardless of vault size), then ranks by
    /// cosine similarity. Any failure — embed model not downloaded yet, its
    /// server unreachable — falls back to term ranking rather than surfacing
    /// an error, since this is a retrieval quality upgrade, not something the
    /// user should have to troubleshoot to keep retrieval working at all.
    private func rankedChunks(for query: String) async -> [NoteChunk] {
        let chunks = ragChunks()
        guard !chunks.isEmpty else { return [] }
        guard await ensureEmbedServerRunning() else { return NoteRetrieval.rank(query: query, in: chunks) }
        do {
            let vectors = try await client.embed(texts: [query] + chunks.map(\.text))
            guard let queryVector = vectors.first, vectors.count == chunks.count + 1 else {
                return NoteRetrieval.rank(query: query, in: chunks)
            }
            let embedded = zip(chunks, vectors.dropFirst()).map { EmbeddedChunk(chunk: $0, vector: $1) }
            return NoteRetrieval.rankByEmbedding(query: queryVector, in: embedded, minSimilarity: similarityFloor)
        } catch {
            return NoteRetrieval.rank(query: query, in: chunks)
        }
    }

    private func displayName(for key: String) -> String {
        if key.hasPrefix("class:") { return String(key.dropFirst("class:".count)) }
        if key.hasPrefix("vault:") { return notesStore.vaultName(forKey: key) ?? "the note" }
        return key
    }
}
