import Foundation

/// How much the assistant is trusted to act on its own. One setting
/// (`Preferences.aiPermission`), not three separate toggles.
enum AssistantPermission: String, Codable, CaseIterable, Identifiable {
    /// Shows what it would do; the user applies it by hand. `AssistantEngine`
    /// never executes anything at this level — it just returns the proposal.
    case propose
    /// Each action is shown for Apply/Skip before it runs. The engine still
    /// returns unexecuted actions here; the UI is what calls the executor,
    /// one action at a time, only for the ones the user approves.
    case confirm
    /// The engine executes everything itself, loops on the results, and
    /// returns only the final natural-language reply plus what happened.
    case auto

    var id: String { rawValue }

    var label: String {
        switch self {
        case .propose: "Propose only"
        case .confirm: "Confirm each action"
        case .auto: "Act automatically"
        }
    }

    var explanation: String {
        switch self {
        case .propose: "Shows what it would do; you apply it yourself."
        case .confirm: "Shows each action before it runs — you approve or skip."
        case .auto: "Acts on its own, then tells you what it did. Calendar adds stay undoable (⌘Z)."
        }
    }
}

/// One prior turn, for continuing a conversation across multiple messages.
struct AssistantTurn: Equatable {
    enum Role: String { case user, assistant }
    let role: Role
    let content: String
}

/// What actually happened when an action ran.
struct AssistantToolResult: Equatable {
    let action: AssistantAction
    let ok: Bool
    /// Human-readable outcome — shown in the confirm-row UI and fed back to
    /// the model verbatim in auto mode, so it doubles as the model's evidence
    /// that a step succeeded or why it didn't.
    let message: String
}

/// One full turn's outcome. In `.propose`/`.confirm`, `actions` are proposals
/// and `results` is empty — nothing ran. In `.auto`, `actions` is whatever the
/// *last* round proposed (normally empty, since a non-empty round keeps the
/// loop going) and `results` covers everything executed across every round.
struct AssistantOutcome: Equatable {
    let reply: String
    let actions: [AssistantAction]
    let results: [AssistantToolResult]
}

/// Runs a tool call against the real stores (Phase 3) or a fake one (tests).
/// The engine never touches `NotesStore`/`EventEditor`/etc. directly — this
/// protocol is the only seam, so "what the assistant is allowed to do" stays
/// readable in one place instead of scattered through the engine.
protocol AssistantExecutor {
    func execute(_ action: AssistantAction) async -> AssistantToolResult
}

enum AssistantEngineError: LocalizedError {
    /// The model's turn didn't decode as `AssistantReply` — a schema violation
    /// Ollama's `format` constraint didn't actually prevent, or the model
    /// returned nothing. Carries a truncated snippet, not the full payload —
    /// this can end up in a user-facing error line.
    case malformedReply(String)
    /// `.auto` mode hit `AssistantEngine.maxIterations` rounds of nonempty
    /// actions without the model producing a final empty-actions reply. Should
    /// not happen in practice — the loop always returns on its last iteration
    /// regardless — this exists so the function has no silent unreachable path.
    case iterationsExhausted

    var errorDescription: String? {
        switch self {
        case .malformedReply(let raw):
            "The assistant's reply wasn't valid JSON: \(raw.prefix(200))"
        case .iterationsExhausted:
            "The assistant took too many steps without finishing."
        }
    }
}

/// Drives one user turn through the local model: builds the prompt (tool
/// catalog + screen context + conversation), asks Ollama for a schema-
/// constrained reply, decodes it, and — only in `.auto` — executes actions and
/// loops with their results until the model stops proposing more or the
/// iteration cap is hit.
///
/// **Why a JSON schema instead of Ollama's native `tools` parameter:**
/// tool-calling support varies a lot across small local models and degrades
/// badly under ~3B parameters. A `format` schema works on any model that can
/// follow instructions at all, and fails in a way this engine can catch
/// (`.malformedReply`) rather than silently misbehaving. Revisit if native
/// tools prove reliably better on the machine's larger models — the schema
/// path should stay as the fallback either way.
final class AssistantEngine {
    /// Confirmed against real installed models (`qwen2.5-coder:1.5b/3b`,
    /// `qwen3.5:4b`) during Phase 0 — see the plan file's Phase 0 spike notes.
    static let maxIterations = 4

    private let client: OllamaClient
    private let model: String
    private let executor: AssistantExecutor

    init(client: OllamaClient = OllamaClient(), model: String, executor: AssistantExecutor) {
        self.client = client
        self.model = model
        self.executor = executor
    }

    func respond(
        to userMessage: String,
        history: [AssistantTurn] = [],
        context: AssistantContext,
        permission: AssistantPermission
    ) async throws -> AssistantOutcome {
        var messages: [OllamaClient.ChatMessage] = [
            OllamaClient.ChatMessage(role: .system, content: Self.systemPrompt(context: context)),
        ]
        messages += history.map {
            OllamaClient.ChatMessage(role: $0.role == .user ? .user : .assistant, content: $0.content)
        }
        messages.append(OllamaClient.ChatMessage(role: .user, content: userMessage))

        // propose/confirm never execute anything themselves — the UI decides,
        // action by action, whether to call the executor at all. One request,
        // no loop.
        guard permission == .auto else {
            let raw = try await client.chat(model: model, messages: messages, schema: Self.responseSchema())
            let parsed = try Self.decodeOrThrow(raw)
            return AssistantOutcome(reply: parsed.reply, actions: parsed.actions, results: [])
        }

        var allResults: [AssistantToolResult] = []
        for iteration in 1...Self.maxIterations {
            let raw = try await client.chat(model: model, messages: messages, schema: Self.responseSchema())
            let parsed = try Self.decodeOrThrow(raw)

            // Nothing left to do, or out of rounds: this is the final answer.
            if parsed.actions.isEmpty || iteration == Self.maxIterations {
                return AssistantOutcome(reply: parsed.reply, actions: parsed.actions, results: allResults)
            }

            var results: [AssistantToolResult] = []
            for action in parsed.actions {
                results.append(await executor.execute(action))
            }
            allResults += results

            messages.append(OllamaClient.ChatMessage(role: .assistant, content: raw))
            messages.append(OllamaClient.ChatMessage(role: .user, content: Self.toolResultsMessage(results)))
        }
        throw AssistantEngineError.iterationsExhausted
    }

    /// Sanitizes *before* decoding, not after a caught failure — confirmed live:
    /// when a model leaves a literal newline inside a JSON string (writing
    /// multi-line code), `JSONDecoder` doesn't reliably throw on it. It can
    /// decode the reply "successfully" while silently dropping just the
    /// corrupted field — here, the code — which a try-then-salvage-on-failure
    /// pattern would never even see, since nothing failed to catch.
    /// `escapingRawControlCharacters` is a no-op on already-valid JSON, so
    /// sanitizing unconditionally costs nothing on the common path.
    private static func decodeOrThrow(_ raw: String) throws -> AssistantReply {
        guard let parsed = try? AssistantReply.decode(escapingRawControlCharacters(in: raw)) else {
            throw AssistantEngineError.malformedReply(raw)
        }
        return parsed
    }

    /// Walks the text tracking whether we're inside a JSON string literal
    /// (toggling on an unescaped `"`) and escapes any literal control
    /// character found there. Deliberately narrow: it does **not** try to fix
    /// unescaped quotes or backslashes — those are ambiguous without knowing
    /// the model's intent, and guessing wrong would corrupt otherwise-valid
    /// content rather than salvage it.
    static func escapingRawControlCharacters(in text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var inString = false
        var escaped = false

        for char in text {
            if escaped {
                result.append(char)
                escaped = false
                continue
            }
            if char == "\\" {
                result.append(char)
                escaped = true
                continue
            }
            if char == "\"" {
                inString.toggle()
                result.append(char)
                continue
            }
            if inString {
                switch char {
                case "\n": result.append("\\n")
                case "\t": result.append("\\t")
                case "\r": result.append("\\r")
                default: result.append(char)
                }
            } else {
                result.append(char)
            }
        }
        return result
    }

    static func toolResultsMessage(_ results: [AssistantToolResult]) -> String {
        let lines = results.map { "\($0.action.tool): \($0.ok ? "OK" : "FAILED") — \($0.message)" }
        return """
        Tool results:
        \(lines.joined(separator: "\n"))

        Give your final reply to the student now. If nothing more needs doing, actions must be empty.
        """
    }

    /// `instructions` defaults to `AssistantInstructions.load()` rather than
    /// being hardcoded to it, so tests can pin an exact value instead of
    /// depending on whatever file happens to exist on the machine running them.
    static func systemPrompt(context: AssistantContext, instructions: String? = AssistantInstructions.load()) -> String {
        var prompt = """
        You are a local study assistant for PUPSISPortal, running entirely on \
        the student's own machine — nothing you're told leaves it.

        Tools you can use:
        \(AssistantTool.promptCatalog)

        Rules:
        - Only use the tools listed above by their exact name. Never invent one.
        - There is no tool to delete, move, or rename a note or event — only \
        to add. If asked to remove something, say you can't.
        - There is no tool to change a grade, ever. If asked, say plainly that \
        you can't and grades stay read-only — never say you updated one.
        - Never claim in your reply that something was added, changed, or \
        removed unless the matching tool is actually in your actions list this \
        turn. A description of what you're about to do is not the same as \
        having done it.
        - If nothing needs doing, return an empty actions array.
        - Reply with JSON only, matching the given schema. No prose outside it.
        """

        if let instructions {
            prompt += "\n\nThe student's own instructions for you:\n\(instructions)"
        }

        prompt += "\n\n\(context.rendered)"
        return prompt
    }

    /// `actions[].args` stays a generic object rather than a per-tool schema:
    /// JSON Schema would need a `oneOf` keyed on `tool` to validate each
    /// tool's arguments strictly, which is a lot of schema for models this
    /// small to reliably follow. Argument correctness is instead the
    /// executor's job — see `AssistantAction.string(_:)`/`int(_:)` and each
    /// tool's own validation in Phase 3.
    static func responseSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "reply": ["type": "string"],
                "actions": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "tool": ["type": "string", "enum": AssistantTool.names],
                            "args": ["type": "object"],
                        ],
                        "required": ["tool"],
                    ],
                ],
            ],
            "required": ["reply", "actions"],
        ]
    }
}
