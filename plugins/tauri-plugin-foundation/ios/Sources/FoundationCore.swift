// The part of the plugin that does not need Tauri, so harness/main.swift can
// compile and run it on a simulator without building the whole app.
import Foundation
#if canImport(FoundationModels)
import FoundationModels

struct FMFailure: Error {
  let code: String
  let message: String
}

/// Case name of an error enum, e.g. "exceededContextWindowSize" (iOS 26) or
/// "contextSizeExceeded" (iOS 27). The spike sniffs the name; a real provider
/// would switch over both enums.
func fmErrorCode(_ error: Error) -> String {
  if error is CancellationError { return "cancelled" }
  let d = String(describing: error)
  return String(d.prefix { $0 != "(" && $0 != " " })
}

@available(iOS 26.0, *)
enum FMCore {
  /// "available" or the unavailable reason.
  static func availability() -> String {
    switch SystemLanguageModel.default.availability {
    case .available: return "available"
    case .unavailable(.deviceNotEligible): return "deviceNotEligible"
    case .unavailable(.appleIntelligenceNotEnabled): return "appleIntelligenceNotEnabled"
    case .unavailable(.modelNotReady): return "modelNotReady"
    case .unavailable: return "unknown"
    }
  }

  static func supports(_ id: String) -> Bool { SystemLanguageModel.default.supportsLocale(Locale(identifier: id)) }

  // MARK: JSON Schema -> DynamicGenerationSchema (object / string / enum / array, plus number, integer, boolean)

  /// `lengthPattern` turns minLength/maxLength into a regex guide, the only
  /// length control GenerationGuide has (no maxLength guide exists).
  static func dynamic(_ j: [String: Any], name: String, lengthPattern: Bool = false) throws -> DynamicGenerationSchema {
    let desc = j["description"] as? String
    if let e = j["enum"] as? [Any] {
      let values = e.compactMap { $0 as? String }
      guard values.count == e.count, !values.isEmpty else { throw FMFailure(code: "badSchema", message: "enum must be non-empty strings at \(name)") }
      return DynamicGenerationSchema(name: name, description: desc, anyOf: values)
    }
    switch j["type"] as? String {
    case "object":
      let props = j["properties"] as? [String: Any] ?? [:]
      let required = Set(j["required"] as? [String] ?? [])
      // Key order of a JSON object is lost in a dictionary; the schema's own order matters to a small model, so the caller may pass "propertyOrder".
      let order = (j["propertyOrder"] as? [String]) ?? props.keys.sorted()
      let list = try order.compactMap { key -> DynamicGenerationSchema.Property? in
        guard let sub = props[key] as? [String: Any] else { return nil }
        return .init(name: key, description: sub["description"] as? String, schema: try dynamic(sub, name: "\(name).\(key)", lengthPattern: lengthPattern), isOptional: !required.contains(key))
      }
      return DynamicGenerationSchema(name: name, description: desc, properties: list)
    case "array":
      let items = j["items"] as? [String: Any] ?? ["type": "string"]
      return DynamicGenerationSchema(arrayOf: try dynamic(items, name: "\(name)[]", lengthPattern: lengthPattern), minimumElements: j["minItems"] as? Int, maximumElements: j["maxItems"] as? Int)
    case "string":
      if lengthPattern, j["minLength"] != nil || j["maxLength"] != nil {
        let lo = j["minLength"] as? Int ?? 0, hi = j["maxLength"] as? Int
        let re = try Regex("[\\s\\S]{\(lo),\(hi.map(String.init) ?? "")}")
        return DynamicGenerationSchema(type: String.self, guides: [.pattern(re)])
      }
      return DynamicGenerationSchema(type: String.self)
    case "integer": return DynamicGenerationSchema(type: Int.self)
    case "number": return DynamicGenerationSchema(type: Double.self)
    case "boolean": return DynamicGenerationSchema(type: Bool.self)
    default: throw FMFailure(code: "badSchema", message: "unsupported type at \(name)")
    }
  }

  static func schema(json: String, lengthPattern: Bool = false) throws -> GenerationSchema {
    guard let d = json.data(using: .utf8), let o = try JSONSerialization.jsonObject(with: d) as? [String: Any] else {
      throw FMFailure(code: "badSchema", message: "schema is not a JSON object")
    }
    return try GenerationSchema(root: try dynamic(o, name: "Root", lengthPattern: lengthPattern), dependencies: [])
  }

  // MARK: generate

  struct Output {
    var text: String          // plain text, or the final JSON string for a schema
    var snapshots: Int
    var firstSnapshotMs: Double?
    var totalMs: Double
  }

  /// Streams one answer on a fresh session. `onSnapshot` gets the whole text
  /// so far (not a delta): plain text, or the JSON string of the partial
  /// object. Throws CancellationError if the task is cancelled.
  static func generate(
    prompt: String, instructions: String?, schema: GenerationSchema?, maxTokens: Int?,
    onSnapshot: (String) -> Void
  ) async throws -> Output {
    let session = LanguageModelSession(instructions: instructions)
    let opts = GenerationOptions(maximumResponseTokens: maxTokens)
    let t0 = Date()
    var out = Output(text: "", snapshots: 0, firstSnapshotMs: nil, totalMs: 0)
    func note(_ s: String) {
      if out.firstSnapshotMs == nil { out.firstSnapshotMs = Date().timeIntervalSince(t0) * 1000 }
      out.snapshots += 1
      out.text = s
      onSnapshot(s)
    }
    if let schema {
      for try await snap in session.streamResponse(to: prompt, schema: schema, options: opts) { note(snap.rawContent.jsonString) }
    } else {
      for try await snap in session.streamResponse(to: prompt, options: opts) { note(snap.content) }
    }
    out.totalMs = Date().timeIntervalSince(t0) * 1000
    return out
  }
}
#endif

#if canImport(FoundationModels)
/// Turns whole-text snapshots into the new suffix. Plain text and the
/// `reply` value of an object are prefix-stable; the object's jsonString is
/// not (it closes the string and brace each time), so a schema stream is
/// followed through one named string property.
struct Streamer {
  private(set) var sent = ""
  let property: String?

  mutating func delta(_ snapshot: String) -> String? {
    var text = snapshot
    if let property {
      guard let d = snapshot.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let v = o[property] as? String else { return nil }
      text = v
    }
    guard text.hasPrefix(sent) else { sent = text; return nil } // never seen in the spike runs
    let d = String(text.dropFirst(sent.count))
    sent = text
    return d.isEmpty ? nil : d
  }
}
#endif
