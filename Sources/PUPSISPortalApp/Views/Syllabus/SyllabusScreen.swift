import SwiftUI

/// The Syllabus destination. Owns the "generate quiz from this lecture"
/// action because it is the one mount with `GenerationCenter` and
/// `NotesStore` in reach.
struct SyllabusScreen: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: Preferences

    var body: some View {
        ScrollView {
            SyllabusView(
                syllabus: appState.syllabus, preferences: preferences,
                subjectCodes: ClassSession.subjectCodes(in: appState.portal.sessions),
                aiModel: preferences.aiModel, calendar: appState.calendar,
                onGenerateQuiz: generateQuiz
            )
        }
    }

    /// Same `RAGQuery`/`GenerationCenter.start` call `GenerateSheet` makes for
    /// a vault-topic deck, then opens Quizzes so the job shows in its banner.
    private func generateQuiz(from item: SyllabusItem) {
        let topic = item.topic
        let client = Preferences.localAIClient(modelID: preferences.aiModel)
        appState.generation.start(
            label: topic, source: .vaultTopic(topic), model: preferences.aiModel,
            client: client,
            ragQuery: RAGQuery(notes: appState.notes, client: client, answerModel: preferences.aiModel),
            chunkSize: preferences.ragChunkSize,
            target: .new(name: topic, sourceKind: .vaultTopic, sourceQuery: topic)
        )
        appState.open(.quizzes)
    }
}
