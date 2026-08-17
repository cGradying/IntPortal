import Foundation

/// A chunk of one note — retrieval works at paragraph granularity, not whole
/// notes, so one relevant section of a long note survives the context budget
/// instead of the whole note being dropped or the whole note being sent.
struct NoteChunk: Equatable {
    let key: String
    let name: String
    let text: String
}

/// A chunk plus its embedding vector — what `rankByEmbedding` sorts.
struct EmbeddedChunk {
    let chunk: NoteChunk
    let vector: [Double]
}

/// Term-based retrieval over the notes vault — the thing that makes
/// `search_notes`/`ask_notes` actually answer a natural-language question,
/// not just a note containing that exact sentence. Deliberately not
/// embeddings: see the doc comment on `RealAssistantExecutor.searchNotes` for
/// why. Pure and stateless, so it's testable without a store or a model.
enum NoteRetrieval {
    private static let stopwords: Set<String> = [
        "the", "a", "an", "of", "in", "on", "at", "to", "for", "and", "or", "is", "are", "was", "were",
        "do", "does", "did", "what", "which", "who", "how", "my", "me", "it", "this", "that", "about",
    ]

    /// Lowercase word tokens, stripped of punctuation, stopwords and single
    /// characters dropped — the fixes-nothing noise a substring match would
    /// otherwise choke on.
    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopwords.contains($0) }
    }

    /// Splits on blank lines, then greedily packs consecutive paragraphs up to
    /// `maxChars` so a chunk stays coherent without being the whole note.
    ///
    /// A note pasted/typed with no blank lines at all (confirmed live: a real
    /// 17.7KB note with zero `\n\n`) is otherwise exactly *one* paragraph —
    /// the packing loop below only ever *combines* paragraphs, so without the
    /// `splitOversized` pre-pass a note like that becomes one oversized chunk
    /// the size of the whole note, no matter how small `maxChars` is. That
    /// diluted the embedding signal (confirmed live: barely above the
    /// similarity floor) and, worse, made the chunk too big to fit
    /// `RAGQuery`'s answer-context budget at all — silently dropped in favor
    /// of smaller, unrelated notes. This is the actual "not hitting the
    /// notes" bug.
    static func chunks(of text: String, key: String, name: String, maxChars: Int = 700) -> [NoteChunk] {
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !paragraphs.isEmpty else { return [] }

        let pieces = paragraphs.flatMap { splitOversized($0, maxChars: maxChars) }

        var result: [NoteChunk] = []
        var current = ""
        for piece in pieces {
            let candidate = current.isEmpty ? piece : current + "\n\n" + piece
            if candidate.count > maxChars, !current.isEmpty {
                result.append(NoteChunk(key: key, name: name, text: current))
                current = piece
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { result.append(NoteChunk(key: key, name: name, text: current)) }
        return result
    }

    /// Splits one oversized paragraph into pieces that each fit `maxChars`,
    /// via plain greedy word-wrap — never mid-word. No punctuation/sentence
    /// detection: word-boundary packing is the smallest fix that's actually
    /// correct, and this only ever runs on the rare paragraph that's too big
    /// to begin with.
    private static func splitOversized(_ paragraph: String, maxChars: Int) -> [String] {
        guard paragraph.count > maxChars else { return [paragraph] }

        var pieces: [String] = []
        var current = ""
        for word in paragraph.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if candidate.count > maxChars, !current.isEmpty {
                pieces.append(current)
                current = String(word)
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { pieces.append(current) }

        // A single "word" longer than maxChars on its own (a wall of text
        // with no spaces either) — hard-slice it so nothing leaves this
        // function still over the limit.
        return pieces.flatMap { $0.count > maxChars ? hardSlice($0, maxChars: maxChars) : [$0] }
    }

    private static func hardSlice(_ text: String, maxChars: Int) -> [String] {
        var slices: [String] = []
        var remaining = Substring(text)
        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: maxChars, limitedBy: remaining.endIndex) ?? remaining.endIndex
            slices.append(String(remaining[..<end]))
            remaining = remaining[end...]
        }
        return slices
    }

    /// TF·IDF over the given chunk set, best match first. A chunk whose note
    /// name contains a query token gets a flat bonus — asking "what does my
    /// Sapiens note say" should surface the note called Sapiens even if the
    /// word itself is thin in the text.
    static func rank(query: String, in chunks: [NoteChunk], limit: Int = 6) -> [NoteChunk] {
        let queryTokens = Set(tokens(query))
        guard !queryTokens.isEmpty, !chunks.isEmpty else { return [] }

        let chunkTokens = chunks.map { tokens($0.text) }
        let documentCount = Double(chunks.count)
        var documentFrequency: [String: Int] = [:]
        for chunkTokenList in chunkTokens {
            for token in Set(chunkTokenList) { documentFrequency[token, default: 0] += 1 }
        }

        var scored: [(chunk: NoteChunk, score: Double)] = []
        for (chunk, chunkTokenList) in zip(chunks, chunkTokens) {
            var termFrequency: [String: Int] = [:]
            for token in chunkTokenList { termFrequency[token, default: 0] += 1 }

            var score = 0.0
            for term in queryTokens {
                guard let frequency = termFrequency[term] else { continue }
                let idf = log(1 + documentCount / Double(documentFrequency[term] ?? 1))
                score += idf * Double(frequency) / Double(frequency + 1)
            }
            let nameTokens = Set(tokens(chunk.name))
            if !nameTokens.isDisjoint(with: queryTokens) { score += 2 }
            scored.append((chunk, score))
        }

        let relevant = scored.filter { $0.score > 0 }
        let sortedHits = relevant.sorted { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.chunk.key < rhs.chunk.key
        }
        return sortedHits.prefix(limit).map(\.chunk)
    }

    /// Semantic ranking: cosine similarity between the query's embedding and
    /// each chunk's. Unlike `rank`, this finds a chunk that means the same
    /// thing without sharing the query's exact words — the gap plain
    /// term-matching can't close. `RealAssistantExecutor` falls back to
    /// `rank` when no embedding model is available, so this is a strict
    /// upgrade, not a replacement that can dead-end retrieval.
    ///
    /// Cosine similarity is continuous — every chunk scores *something*, so
    /// unlike `rank`'s `score > 0` filter, a floor is needed or a totally
    /// unrelated note would still come back as the "best available" match.
    ///
    /// 0.35, calibrated against real `nomic-embed-text` output on an actual
    /// vault, not guessed: genuine matches (a note actually about the asked
    /// topic, phrased completely differently from the question) scored
    /// 0.43–0.51; a wrong-note baseline scored 0.35–0.47 on the *same*
    /// queries. There is no cosine value that cleanly separates related from
    /// unrelated prose for this model — the two bands overlap — so this floor
    /// only screens out clear noise; it deliberately leans permissive (favors
    /// finding the real match over excluding an occasional unrelated one)
    /// since a false "not found" is the worse failure for this feature.
    static func rankByEmbedding(query: [Double], in chunks: [EmbeddedChunk], limit: Int = 6, minSimilarity: Double = 0.35) -> [NoteChunk] {
        let scored = chunks.map { (chunk: $0.chunk, score: cosineSimilarity(query, $0.vector)) }
        let relevant = scored.filter { $0.score >= minSimilarity }
        let sortedHits = relevant.sorted { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.chunk.key < rhs.chunk.key
        }
        return sortedHits.prefix(limit).map(\.chunk)
    }

    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in a.indices {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }
}
