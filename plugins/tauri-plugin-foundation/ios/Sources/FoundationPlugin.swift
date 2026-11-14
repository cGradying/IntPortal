import Foundation
import SwiftRs
import Tauri
import UIKit
import WebKit
#if canImport(FoundationModels)
import FoundationModels
#endif

struct AvailabilityOut: Encodable {
  var available: Bool
  var reason: String
  var os: String
  var contextSize: Int?
  var enPH: Bool?
  var filPH: Bool?
}

struct GenerateOut: Encodable {
  var text: String
  var cancelled: Bool
  var snapshots: Int
  var firstSnapshotMs: Double?
  var totalMs: Double
}

class GenerateArgs: Decodable {
  let prompt: String
  let instructions: String?
  /// JSON Schema as a string (object / string / array / enum).
  let schema: String?
  let maxTokens: Int?
  /// With a schema, the string property whose growth is sent as tokens.
  let streamProperty: String?
  let onToken: Channel
}

class FoundationPlugin: Plugin {
  private let lock = NSLock()
  private var current: Task<Void, Never>?

  @objc public func availability(_ invoke: Invoke) throws {
    let os = ProcessInfo.processInfo.operatingSystemVersionString
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      let r = FMCore.availability()
      invoke.resolve(AvailabilityOut(available: r == "available", reason: r, os: os, contextSize: SystemLanguageModel.default.contextSize, enPH: FMCore.supports("en_PH"), filPH: FMCore.supports("fil_PH")))
      return
    }
    #endif
    invoke.resolve(AvailabilityOut(available: false, reason: "osTooOld", os: os))
  }

  @objc public func generate(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(GenerateArgs.self)
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      let schema: GenerationSchema?
      do { schema = try args.schema.map { try FMCore.schema(json: $0) } } catch {
        invoke.reject("badSchema: \(error)")
        return
      }
      lock.lock()
      if current != nil { lock.unlock(); invoke.reject("busy: a generation is already running"); return }
      var streamer = Streamer(property: schema == nil ? nil : (args.streamProperty ?? "reply"))
      let task = Task {
        var partial = ""
        let t0 = Date()
        do {
          let out = try await FMCore.generate(prompt: args.prompt, instructions: args.instructions, schema: schema, maxTokens: args.maxTokens) { snap in
            partial = snap
            if let d = streamer.delta(snap) { args.onToken.send(JsonValue.string(d)) }
          }
          invoke.resolve(GenerateOut(text: out.text, cancelled: false, snapshots: out.snapshots, firstSnapshotMs: out.firstSnapshotMs, totalMs: out.totalMs))
        } catch is CancellationError {
          invoke.resolve(GenerateOut(text: partial, cancelled: true, snapshots: 0, firstSnapshotMs: nil, totalMs: Date().timeIntervalSince(t0) * 1000))
        } catch {
          invoke.reject("\(fmErrorCode(error)): \(String(describing: error).prefix(300))")
        }
        self.lock.lock(); self.current = nil; self.lock.unlock()
      }
      current = task
      lock.unlock()
      return
    }
    #endif
    invoke.reject("unavailable: Foundation Models needs iOS 26")
  }

  @objc public func cancel(_ invoke: Invoke) {
    lock.lock(); let t = current; lock.unlock()
    t?.cancel()
    invoke.resolve()
  }
}

@_cdecl("init_plugin_foundation")
func initPlugin() -> Plugin {
  return FoundationPlugin()
}
