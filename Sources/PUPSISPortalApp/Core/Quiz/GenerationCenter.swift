import Foundation

/// Owns generation `Task`s so they survive `GenerateSheet` being dismissed —
/// "Send to background" only means something if the work keeps running and
/// its result is still there afterward. One instance lives on `AppState`,
/// shared by every deck's generate/append/regenerate flow.
@MainActor
final class GenerationCenter: ObservableObject {
    enum Target: Equatable {
        case new(name: String, sourceKind: QuizSourceKind, sourceQuery: String)
        case append(deckID: UUID)
        case regenerate(deckID: UUID)
    }

    struct Job: Identifiable, Equatable {
        static func == (lhs: Job, rhs: Job) -> Bool { lhs.id == rhs.id }

        let id: UUID
        var label: String
        var done = 0
        var total = 0
        var target: Target
        var result: CardGenerator.Result?
        var failure: String?
        var isCancelled = false

        var finished: Bool { result != nil || failure != nil }
    }

    @Published private(set) var jobs: [Job] = []

    @discardableResult
    func start(
        label: String, source: QuizSource, model: String, client: LlamaCppClient,
        ragQuery: RAGQuery?, chunkSize: Int, target: Target
    ) -> UUID {
        let id = UUID()
        jobs.append(Job(id: id, label: label, target: target))
        Task { [weak self] in
            let result = await CardGenerator.run(
                source: source, model: model, client: client, ragQuery: ragQuery, chunkSize: chunkSize,
                onProgress: { done, total in
                    Task { @MainActor [weak self] in self?.updateProgress(id: id, done: done, total: total) }
                },
                isCancelled: { self?.jobs.first(where: { $0.id == id })?.isCancelled ?? true }
            )
            await MainActor.run { self?.complete(id: id, result: result) }
        }
        return id
    }

    func cancel(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].isCancelled = true
        jobs.remove(at: index)
    }

    /// Drops a finished job once its result has been reviewed/saved (or the
    /// user dismissed a failure) — keeps the badge list from growing forever.
    func dismiss(_ id: UUID) {
        jobs.removeAll { $0.id == id }
    }

    private func updateProgress(id: UUID, done: Int, total: Int) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].done = done
        jobs[index].total = total
    }

    private func complete(id: UUID, result: CardGenerator.Result) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].isCancelled else { return }
        if result.cards.isEmpty {
            jobs[index].failure = result.totalChunks == 0
                ? "Nothing to generate from."
                : "Generation failed for all \(result.totalChunks) chunk(s). Check the model in Settings ▸ AI is downloaded and llama.cpp is installed."
        } else {
            jobs[index].result = result
        }
    }
}
