// The Live Activity's data, compiled into both the glance plugin and the
// widget extension. ActivityKit matches the two copies by type name, so
// the definitions must stay identical.
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
