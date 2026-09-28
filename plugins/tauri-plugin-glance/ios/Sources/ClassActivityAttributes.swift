// Keep identical to src-tauri/gen/apple/Shared/ClassActivityAttributes.swift:
// ActivityKit matches the app's and the widget's copies by type name.
#if canImport(ActivityKit)
import ActivityKit
import Foundation

@available(iOS 16.1, *)
public struct ClassActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    public var code: String
    public var title: String
    public var start: Date
    public var end: Date
    public var online: Bool

    public init(code: String, title: String, start: Date, end: Date, online: Bool) {
      self.code = code
      self.title = title
      self.start = start
      self.end = end
      self.online = online
    }
  }

  public init() {}
}
#endif
