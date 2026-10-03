import Foundation
import SwiftRs
import Tauri
import UIKit
import WebKit
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Shared with the widget extension through the app group.
let appGroup = "group.ph.intportal.app"

struct NextClass: Codable {
  let code: String
  let title: String
  /// Unix milliseconds.
  let start: Double
  let end: Double
  let online: Bool
}

struct GlanceFile: Codable {
  let next: NextClass?
  let line: String
  let updated: Double
}

class UpdateArgs: Decodable {
  let next: NextClass?
  let line: String
}

class GlancePlugin: Plugin {
  @objc public func update(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(UpdateArgs.self)
    let file = GlanceFile(next: args.next, line: args.line, updated: Date().timeIntervalSince1970 * 1000)
    if let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
      let data = try? JSONEncoder().encode(file)
    {
      try? data.write(to: dir.appendingPathComponent("glance.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    WidgetCenter.shared.reloadAllTimelines()
    if #available(iOS 16.2, *) {
      ClassActivity.sync(args.next)
    }
    invoke.resolve()
  }
}

#if canImport(ActivityKit)
@available(iOS 16.2, *)
enum ClassActivity {
  /// From an hour before class until it ends, one activity for the next
  /// class; otherwise none.
  static func sync(_ next: NextClass?) {
    let now = Date()
    let wanted: ClassActivityAttributes.ContentState? = next.flatMap { n in
      let start = Date(timeIntervalSince1970: n.start / 1000)
      let end = Date(timeIntervalSince1970: n.end / 1000)
      guard end > now, start.timeIntervalSince(now) <= 3600 else { return nil }
      return .init(code: n.code, title: n.title, start: start, end: end, online: n.online)
    }
    let running = Activity<ClassActivityAttributes>.activities
    Task {
      guard let state = wanted else {
        for a in running { await a.end(nil, dismissalPolicy: .immediate) }
        return
      }
      let content = ActivityContent(state: state, staleDate: state.end)
      if let current = running.first(where: { $0.content.state.start == state.start && $0.content.state.code == state.code }) {
        await current.update(content)
        for a in running where a.id != current.id { await a.end(nil, dismissalPolicy: .immediate) }
      } else {
        for a in running { await a.end(nil, dismissalPolicy: .immediate) }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? Activity.request(attributes: ClassActivityAttributes(), content: content)
      }
    }
  }
}
#endif

@_cdecl("init_plugin_glance")
func initPlugin() -> Plugin {
  return GlancePlugin()
}
