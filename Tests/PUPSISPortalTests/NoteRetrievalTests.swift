import XCTest
@testable import PUPSISPortal

/// Pure term-based retrieval — no store, no model. Ranking is what fixes the
/// old substring-match RAG (a natural-language question never matched a note
/// unless the exact sentence appeared verbatim).
final class NoteRetrievalTests: XCTestCase {
    func testTokensDropsStopwordsPunctuationAndSingleLetters() {
        XCTAssertEqual(
            NoteRetrieval.tokens("What does my Sapiens note say about the agricultural revolution?"),
            ["sapiens", "note", "say", "agricultural", "revolution"]
        )
    }

    func testChunksSplitsOnBlankLinesAndPacksUnderTheLimit() {
        let text = "Para one.\n\nPara two.\n\nPara three."
        let chunks = NoteRetrieval.chunks(of: text, key: "k", name: "Note", maxChars: 1000)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].text, "Para one.\n\nPara two.\n\nPara three.")
    }

    /// Each 500-char paragraph already sits near the 700 limit, so no two pack
    /// together — three paragraphs land as three separate chunks.
    func testChunksSplitsIntoMultiplePiecesPastTheCharLimit() {
        let paragraph = String(repeating: "a", count: 500)
        let text = [paragraph, paragraph, paragraph].joined(separator: "\n\n")
        let chunks = NoteRetrieval.chunks(of: text, key: "k", name: "Note", maxChars: 700)
        XCTAssertEqual(chunks.count, 3)
    }

    /// The first two 200-char paragraphs pack into one chunk (402 <= 450); the
    /// third pushes it over, starting a new one.
    func testChunksPacksSmallParagraphsTogetherUntilTheLimit() {
        let paragraph = String(repeating: "a", count: 200)
        let text = [paragraph, paragraph, paragraph].joined(separator: "\n\n")
        let chunks = NoteRetrieval.chunks(of: text, key: "k", name: "Note", maxChars: 450)
        XCTAssertEqual(chunks.count, 2)
    }

    func testEmptyTextProducesNoChunks() {
        XCTAssertEqual(NoteRetrieval.chunks(of: "   \n\n  ", key: "k", name: "Note"), [])
    }

    /// The exact failure mode this feature fixes: a natural-language question
    /// whose exact sentence never appears verbatim in the note.
    func testRankMatchesANaturalLanguageQuestionAgainstRelevantContent() {
        let chunks = [
            NoteChunk(key: "a", name: "Sapiens", text: "The agricultural revolution changed how humans lived and organized society."),
            NoteChunk(key: "b", name: "Shopping list", text: "Milk, eggs, bread, and coffee for the week."),
        ]
        let hits = NoteRetrieval.rank(query: "what does my Sapiens note say about the agricultural revolution?", in: chunks)
        XCTAssertEqual(hits.first?.key, "a")
    }

    func testRankGivesANameMatchBonus() {
        let chunks = [
            NoteChunk(key: "a", name: "Random", text: "revolution revolution revolution appears many times here."),
            NoteChunk(key: "b", name: "Sapiens", text: "a brief mention of revolution once."),
        ]
        let hits = NoteRetrieval.rank(query: "sapiens revolution", in: chunks)
        XCTAssertEqual(hits.first?.key, "b")
    }

    func testRankReturnsEmptyWhenNothingMatches() {
        let chunks = [NoteChunk(key: "a", name: "Note", text: "unrelated content entirely")]
        XCTAssertEqual(NoteRetrieval.rank(query: "xyzxyz", in: chunks), [])
    }

    func testRankRespectsTheLimit() {
        let chunks = (0..<10).map { NoteChunk(key: "\($0)", name: "Note", text: "apple apple apple") }
        XCTAssertEqual(NoteRetrieval.rank(query: "apple", in: chunks, limit: 3).count, 3)
    }

    // MARK: rankByEmbedding — cosine similarity

    func testCosineSimilarityOfIdenticalVectorsIsOne() {
        XCTAssertEqual(NoteRetrieval.cosineSimilarity([1, 0, 0], [1, 0, 0]), 1, accuracy: 0.0001)
    }

    func testCosineSimilarityOfOrthogonalVectorsIsZero() {
        XCTAssertEqual(NoteRetrieval.cosineSimilarity([1, 0], [0, 1]), 0, accuracy: 0.0001)
    }

    func testCosineSimilarityOfMismatchedLengthsIsZero() {
        XCTAssertEqual(NoteRetrieval.cosineSimilarity([1, 0], [1, 0, 0]), 0)
    }

    func testRankByEmbeddingPicksTheClosestVectorRegardlessOfWords() {
        let close = NoteChunk(key: "a", name: "Note A", text: "totally different words on purpose")
        let far = NoteChunk(key: "b", name: "Note B", text: "also totally different words")
        let embedded = [
            EmbeddedChunk(chunk: close, vector: [0.9, 0.1]),
            EmbeddedChunk(chunk: far, vector: [0, 1]),
        ]
        let hits = NoteRetrieval.rankByEmbedding(query: [1, 0], in: embedded)
        XCTAssertEqual(hits.first?.key, "a")
    }

    /// The threshold that keeps a genuinely unrelated chunk from being
    /// returned as the "best available" match — cosine similarity is
    /// continuous, so without a floor every query would return *something*.
    func testRankByEmbeddingDropsChunksBelowTheSimilarityFloor() {
        let unrelated = NoteChunk(key: "a", name: "Note", text: "irrelevant")
        let embedded = [EmbeddedChunk(chunk: unrelated, vector: [0, 1])]
        XCTAssertEqual(NoteRetrieval.rankByEmbedding(query: [1, 0], in: embedded), [])
    }

    // MARK: chunks — oversized single-paragraph splitting (the real "not
    // hitting the notes" bug: a note with no blank lines was one giant chunk)

    /// A wall of text with no blank lines at all — confirmed live on a real
    /// 17.7KB note with zero `\n\n` — must not become one oversized chunk.
    func testChunksSplitsAParagraphWithNoBlankLinesAtAll() {
        let words = (0..<500).map { "word\($0)" }
        let text = words.joined(separator: " ")
        let chunks = NoteRetrieval.chunks(of: text, key: "k", name: "Note", maxChars: 700)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.text.count, 700)
        }
    }

    func testChunksNeverSplitsMidWord() {
        let words = (0..<500).map { "word\($0)" }
        let text = words.joined(separator: " ")
        let chunks = NoteRetrieval.chunks(of: text, key: "k", name: "Note", maxChars: 700)
        // Every chunk boundary lands on a word boundary (space, or the "\n\n"
        // a merge inserts) — splitting every chunk back into words and
        // concatenating reproduces the exact original word sequence, in order.
        let reconstructed = chunks.flatMap { $0.text.components(separatedBy: CharacterSet(charactersIn: " \n")) }
            .filter { !$0.isEmpty }
        XCTAssertEqual(reconstructed, words)
    }

    /// A single "word" longer than maxChars on its own (no spaces at all) —
    /// the hard-slice fallback, so nothing ever comes out still oversized.
    func testChunksHardSlicesAWordLongerThanTheLimit() {
        let text = String(repeating: "a", count: 1500)
        let chunks = NoteRetrieval.chunks(of: text, key: "k", name: "Note", maxChars: 700)
        XCTAssertEqual(chunks.count, 3)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.text.count, 700)
        }
        XCTAssertEqual(chunks.map(\.text).joined(), text)
    }

    func testChunksLeavesShortParagraphsUntouched() {
        XCTAssertEqual(
            NoteRetrieval.chunks(of: "short note", key: "k", name: "Note", maxChars: 700),
            [NoteChunk(key: "k", name: "Note", text: "short note")]
        )
    }
}
