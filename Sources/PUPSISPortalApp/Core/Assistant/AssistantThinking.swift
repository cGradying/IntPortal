import Foundation

/// How hard the assistant's model reasons before answering — Granite 4.2's
/// built-in thinking mode, gated by Ollama's top-level `think` request field
/// (confirmed live: `options.think`, the shape the model's own README shows,
/// is a no-op on the server — see `OllamaClient.chatRequestBody`). Same shape
/// as `AssistantPermission`: a picker enum, not a raw string, so the UI and
/// the transport can never disagree about what levels exist.
enum AssistantThinking: String, Codable, CaseIterable, Identifiable {
    case off
    case low
    case medium
    case max

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .medium: "Medium"
        case .max: "Max"
        }
    }

    /// What `OllamaClient.chatRequestBody` sends as the `"think"` field.
    /// `nil` for `.off` — omitting the field entirely, not sending `false`,
    /// is what a model with no thinking mode at all (any non-Granite pick)
    /// needs to see nothing unexpected in its request.
    var apiValue: String? {
        switch self {
        case .off: nil
        case .low: "low"
        case .medium: "medium"
        case .max: "high"
        }
    }

    var explanation: String {
        switch self {
        case .off: "Answers immediately, no reasoning pass."
        case .low: "A light reasoning pass before answering."
        case .medium: "More thorough reasoning — slower."
        case .max: "Full reasoning depth — slowest, most careful."
        }
    }
}
