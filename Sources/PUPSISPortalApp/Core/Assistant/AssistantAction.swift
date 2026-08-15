import Foundation

/// A JSON value with no fixed shape — `AssistantAction.args` can be a string,
/// a number, or absent per tool, and Swift's `Decodable` needs a concrete type
/// to decode into. Only the primitives the tool catalog actually uses; no
/// nested objects/arrays, because no tool argument needs one.
enum AssistantJSON: Decodable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else { self = .null }
    }

    /// The value as a string when it's meaningfully one — a model asked for a
    /// string argument occasionally still sends a bare number (a date, a
    /// minute count), so this reads through that rather than failing on it.
    var stringValue: String? {
        switch self {
        case .string(let s): s
        case .int(let i): String(i)
        case .double(let d): String(d)
        case .bool(let b): String(b)
        case .null: nil
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let i): i
        case .double(let d): Int(d)
        case .string(let s): Int(s)
        default: nil
        }
    }
}

/// One tool call the model asked for. `tool` is deliberately a plain `String`,
/// not the `AssistantTool` enum-constrained by the schema — a model can still
/// emit a name outside the enum, and decoding that as an *unknown* tool
/// (handled explicitly downstream) beats a decode failure that throws the
/// whole reply away.
struct AssistantAction: Decodable, Equatable {
    let tool: String
    let args: [String: AssistantJSON]

    /// `args` may be entirely absent for a zero-argument tool like `read_grades`.
    enum CodingKeys: String, CodingKey { case tool, args }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tool = try container.decode(String.self, forKey: .tool)
        args = try container.decodeIfPresent([String: AssistantJSON].self, forKey: .args) ?? [:]
    }

    init(tool: String, args: [String: AssistantJSON] = [:]) {
        self.tool = tool
        self.args = args
    }

    /// `args[key]` as a string, `nil` when absent, missing, or genuinely empty
    /// after trimming — the last case is what lets the blank-note guard work
    /// off this accessor rather than a second string check at every call site.
    func string(_ key: String) -> String? {
        guard let raw = args[key]?.stringValue else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func int(_ key: String) -> Int? { args[key]?.intValue }
}

/// The model's whole turn: what to say, plus what (if anything) to do.
/// `actions` defaults to empty on decode so a reply with no tool calls doesn't
/// need the model to remember to emit `"actions": []` explicitly.
struct AssistantReply: Decodable, Equatable {
    let reply: String
    let actions: [AssistantAction]

    enum CodingKeys: String, CodingKey { case reply, actions }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reply = try container.decode(String.self, forKey: .reply)
        actions = try container.decodeIfPresent([AssistantAction].self, forKey: .actions) ?? []
    }

    init(reply: String, actions: [AssistantAction] = []) {
        self.reply = reply
        self.actions = actions
    }

    /// Parses a model's raw JSON output. Failures are the caller's to handle —
    /// see `AssistantEngine`, which turns this into a typed outcome rather
    /// than letting a malformed turn crash the conversation.
    static func decode(_ json: String) throws -> AssistantReply {
        try JSONDecoder().decode(AssistantReply.self, from: Data(json.utf8))
    }
}
