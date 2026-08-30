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
    /// Note names `search_notes`/`ask_notes` actually drew this reply from —
    /// empty for everything else. Lets the panel show a "from your notes"
    /// chip instead of the source burying itself in the reply text.
    var sources: [String] = []
}

/// What actually happened when an action ran.
struct AssistantToolResult: Equatable {
    let action: AssistantAction
    let ok: Bool
    /// Human-readable outcome — shown in the confirm-row UI and fed back to
    /// the model verbatim in auto mode, so it doubles as the model's evidence
    /// that a step succeeded or why it didn't.
    let message: String
    /// Note names this result was drawn from (`search_notes`/`ask_notes`
    /// only) — kept structured rather than folded into `message` so the UI
    /// can render it as its own chip instead of parsing text back out.
    var sources: [String] = []
}

/// One full turn's outcome. In `.propose`/`.confirm`, `actions` are proposals
/// and `results` is empty — nothing ran. In `.auto`, `actions` is whatever the
/// *last* round proposed (normally empty, since a non-empty round keeps the
/// loop going) and `results` covers everything executed across every round.
struct AssistantOutcome: Equatable {
    let reply: String
    let actions: [AssistantAction]
    let results: [AssistantToolResult]
    /// The model's reasoning for its *final* round, shown in the assistant
    /// panel behind a disclosure rather than folded into `reply` — empty
    /// when thinking was off, or the model didn't return any.
    var thinking: String = ""
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
    /// the `response_format` constraint didn't actually prevent, or the model
    /// returned nothing. Carries a truncated snippet, not the full payload —
    /// this can end up in a user-facing error line.
    case malformedReply(String)
    /// `.auto` mode hit `AssistantEngine.maxIterations` rounds of nonempty
    /// actions without the model producing a final empty-actions reply. Should
    /// not happen in practice — the loop always returns on its last iteration
    /// regardless — this exists so the function has no silent unreachable path.
    case iterationsExhausted
    /// The `.chat`-role `llama-server` couldn't be started — no model
    /// downloaded yet in Settings ▸ AI, or (on the plain, non-`-with-AI`
    /// build) `llama-server` itself isn't installed.
    case serverUnavailable
    /// Confirmed live: at `Preferences.aiContextSizeRange`'s own minimum
    /// (2048), the tool catalog + rules text alone can already eat nearly
    /// the whole window before any note/conversation/reply room is left —
    /// the request would otherwise just fail against the real server with a
    /// generic HTTP/timeout error that reads as "the assistant is broken"
    /// rather than "raise Context size in Settings". Caught here, before
    /// ever making the request, so the failure is actually explainable.
    case contextTooSmall(needed: Int, configured: Int)

    var errorDescription: String? {
        switch self {
        case .malformedReply(let raw):
            "The assistant's reply wasn't valid JSON: \(raw.prefix(200))"
        case .iterationsExhausted:
            "The assistant took too many steps without finishing."
        case .serverUnavailable:
            "Couldn't start the local model server. Is a model downloaded in Settings ▸ AI? If you installed the plain (non-AI-bundled) build, it also needs `llama-server` — `brew install llama.cpp`."
        case .contextTooSmall(let needed, let configured):
            "Context size (\(configured) tokens) is too small for the assistant's own tools and instructions (needs at least ~\(needed)). Raise Context size in Settings ▸ AI."
        }
    }
}

/// Drives one user turn through the local model: builds the prompt (tool
/// catalog + screen context + conversation), asks the local `llama-server`
/// for a schema-constrained reply, decodes it, and — only in `.auto` —
/// executes actions and loops with their results until the model stops
/// proposing more or the iteration cap is hit.
///
/// **Why a JSON schema instead of a native `tools` parameter:** tool-calling
/// support varies a lot across small local models and degrades badly under
/// ~3B parameters. A `response_format` schema works on any model that can
/// follow instructions at all, and fails in a way this engine can catch
/// (`.malformedReply`) rather than silently misbehaving.
final class AssistantEngine {
    static let maxIterations = 4
    /// Confirmed live: `history` (the full `AssistantSession.transcript`)
    /// was sent in full every turn, uncapped — a long-running conversation
    /// grows the prompt forever regardless of `aiContextSize`, so even the
    /// largest window (32768) eventually overflows, and every turn well
    /// before that costs latency for context the model doesn't need anymore.
    /// 20 turns (10 exchanges) is generous for a study-assistant chat; older
    /// turns are simply dropped, not summarized — there's no cheap way to
    /// summarize without another model call, and losing detail from ten
    /// exchanges ago is an acceptable trade against every turn silently
    /// getting slower and closer to overflowing.
    static let maxHistoryTurns = 20

    private let client: LlamaCppClient
    private let model: String
    private let executor: AssistantExecutor
    /// Defaults to resolving `model` through `LlamaRuntime` — override in
    /// tests to skip the real process-management path entirely.
    private let ensureServerRunning: () async -> Bool

    init(
        client: LlamaCppClient = LlamaCppClient(), model: String, executor: AssistantExecutor,
        ensureServerRunning: (() async -> Bool)? = nil
    ) {
        self.ensureServerRunning = ensureServerRunning ?? { await LlamaRuntime.ensureChatServer(modelID: model) }
        self.client = client
        self.model = model
        self.executor = executor
    }

    func respond(
        to userMessage: String,
        history: [AssistantTurn] = [],
        context: AssistantContext,
        permission: AssistantPermission,
        think: AssistantThinking = .off
    ) async throws -> AssistantOutcome {
        guard await ensureServerRunning() else { throw AssistantEngineError.serverUnavailable }

        // At least a little room past the fixed catalog/rules overhead for
        // an actual note/conversation/reply — not just "doesn't divide by
        // zero". See AssistantEngineError.contextTooSmall's own doc comment.
        let minimumViableTokens = AssistantContext.promptOverheadTokens + 300
        guard context.tokenBudget >= minimumViableTokens else {
            throw AssistantEngineError.contextTooSmall(needed: minimumViableTokens, configured: context.tokenBudget)
        }

        var messages: [LlamaCppClient.ChatMessage] = [
            LlamaCppClient.ChatMessage(role: .system, content: Self.systemPrompt(context: context)),
        ]
        messages += history.suffix(Self.maxHistoryTurns).map {
            LlamaCppClient.ChatMessage(role: $0.role == .user ? .user : .assistant, content: $0.content)
        }
        messages.append(LlamaCppClient.ChatMessage(role: .user, content: userMessage))

        // propose/confirm never execute anything themselves — the UI decides,
        // action by action, whether to call the executor at all. One request,
        // no loop.
        guard permission == .auto else {
            let raw = try await client.chat(model: model, messages: messages, schema: Self.responseSchema(), think: think)
            let parsed = try Self.decodeOrThrow(raw.content)
            return AssistantOutcome(reply: parsed.reply, actions: parsed.actions, results: [], thinking: raw.thinking)
        }

        var allResults: [AssistantToolResult] = []
        for iteration in 1...Self.maxIterations {
            let raw = try await client.chat(model: model, messages: messages, schema: Self.responseSchema(), think: think)
            let parsed = try Self.decodeOrThrow(raw.content)

            // Nothing left to do, or out of rounds: this is the final answer.
            if parsed.actions.isEmpty || iteration == Self.maxIterations {
                return AssistantOutcome(reply: parsed.reply, actions: parsed.actions, results: allResults, thinking: raw.thinking)
            }

            var results: [AssistantToolResult] = []
            for action in parsed.actions {
                results.append(await executor.execute(action))
            }
            allResults += results

            messages.append(LlamaCppClient.ChatMessage(role: .assistant, content: raw.content))
            messages.append(LlamaCppClient.ChatMessage(role: .user, content: Self.toolResultsMessage(results)))
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
        - There is no tool to delete or rename a note or event. A calendar \
        event can be moved to a new date/time with move_event, but nothing \
        can be deleted or renamed — if asked, say you can't.
        - A class's status (vacant/online/regular) and time are exceptions \
        on top of its real SIS schedule, not edits to the class itself — \
        set_class_status/set_class_time are always safe to use and always \
        reversible by setting the status back to regular.
        - There is no tool to change a grade, ever. If asked, say plainly that \
        you can't and grades stay read-only — never say you updated one.
        - Never claim in your reply that something was added, changed, or \
        removed unless the matching tool is actually in your actions list this \
        turn. A description of what you're about to do is not the same as \
        having done it.
        - If nothing needs doing, return an empty actions array.
        - Never compute a date yourself — resolve "tomorrow"/"next Friday"/etc. \
        by looking it up in the date reference table below. Convert a clock \
        time to minutes from midnight by multiplying the hour by 60 and \
        adding the minutes (e.g. 6:00 PM = 18:00 = 1080).
        - A new event with no end time given defaults to one hour after the \
        start — end must always be greater than start, never equal to it. \
        Say the assumed duration in your reply so the student can correct it.
        - If you're missing something else you need to add or move an event \
        — which date is meant, or which meeting when a subject meets more \
        than once that day — ask the student in your reply instead of \
        guessing. Leave actions empty until you actually know.
        - Structuring a pasted/imported syllabus: call add_syllabus_item once \
        per item you can identify — several times in the same turn is normal \
        and expected for a whole syllabus, not just one call. Keep topic text \
        close to the source rather than paraphrasing it. Use week when the \
        source organizes by week number; use date only when a real calendar \
        date is actually given or unambiguous from context — don't invent one.
        - Generating a syllabus from scratch (no source text given): base it \
        on the subject's real class days from the schedule context below and \
        the term's start/end dates, spacing weekly topics across the actual \
        term length — clearly say in your reply that this is a generated \
        guide, not the real course syllabus.
        - There is no tool to delete or rename a syllabus item, same as \
        notes/events. set_syllabus_item_status only ever toggles done vs \
        automatic — it never edits the topic, date, or type.
        - Reply with JSON only, matching the given schema. No prose outside it.
        """

        if let instructions {
            prompt += "\n\nThe student's own instructions for you:\n\(instructions)"
        }

        prompt += "\n\n\(context.rendered)"
        return prompt
    }

    /// Each action's `args` is validated per-tool via `AssistantTool.argsSchema`'s
    /// `oneOf` — this catalog was originally kept generic because sub-3B
    /// models followed a schema this tight badly; Granite is why it's worth
    /// tightening. Argument correctness is still also the executor's job
    /// (`AssistantAction.string(_:)`/`int(_:)`) — a stricter schema narrows
    /// what a model *sends*, it doesn't replace validating what arrives.
    static func responseSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "reply": ["type": "string"],
                "actions": [
                    "type": "array",
                    "items": AssistantTool.argsSchema,
                ],
            ],
            "required": ["reply", "actions"],
        ]
    }
}
