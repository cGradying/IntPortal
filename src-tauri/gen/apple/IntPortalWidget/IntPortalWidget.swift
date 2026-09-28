import SwiftUI
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

private let appGroup = "group.ph.intportal.app"
private let gold = Color(red: 0.96, green: 0.70, blue: 0.15)
private let maroon = Color(red: 0.48, green: 0.07, blue: 0.16)
private let ground = Color(red: 0.10, green: 0.10, blue: 0.11)

struct NextClass: Codable {
  let code: String
  let title: String
  let start: Double
  let end: Double
  let online: Bool

  var startDate: Date { Date(timeIntervalSince1970: start / 1000) }
  var endDate: Date { Date(timeIntervalSince1970: end / 1000) }
}

struct GlanceFile: Codable {
  let next: NextClass?
  let line: String
}

struct GlanceEntry: TimelineEntry {
  let date: Date
  let next: NextClass?
  let line: String
}

/// Reads what the app last wrote; the timeline turns over when the class
/// starts and when it ends, so the widget never shows a finished class.
struct GlanceProvider: TimelineProvider {
  func read() -> GlanceFile? {
    guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
      let data = try? Data(contentsOf: dir.appendingPathComponent("glance.json"))
    else { return nil }
    return try? JSONDecoder().decode(GlanceFile.self, from: data)
  }

  func placeholder(in context: Context) -> GlanceEntry {
    GlanceEntry(date: .now, next: NextClass(code: "COMP 20073", title: "Data Structures", start: (Date.now.timeIntervalSince1970 + 1500) * 1000, end: (Date.now.timeIntervalSince1970 + 6900) * 1000, online: false), line: "")
  }

  func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
    let f = read()
    completion(GlanceEntry(date: .now, next: f?.next, line: f?.line ?? "Open IntPortal to sync"))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
    let f = read()
    let now = Date.now
    var entries = [GlanceEntry(date: now, next: f?.next, line: f?.line ?? "Open IntPortal to sync")]
    if let n = f?.next, n.endDate > now {
      if n.startDate > now { entries.append(GlanceEntry(date: n.startDate, next: n, line: f?.line ?? "")) }
      entries.append(GlanceEntry(date: n.endDate, next: nil, line: "Open IntPortal for what's next"))
    }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
  }
}

struct PortalGlyph: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 2).fill(maroon)
      .overlay(RoundedRectangle(cornerRadius: 1).fill(gold).padding(3))
      .frame(width: 12, height: 16)
  }
}

struct CountdownText: View {
  let next: NextClass
  let date: Date
  var body: some View {
    if next.startDate > date {
      Text(next.startDate, style: .relative)
    } else {
      Text("until \(next.endDate.formatted(date: .omitted, time: .shortened))")
    }
  }
}

struct NextClassView: View {
  @Environment(\.widgetFamily) var family
  let entry: GlanceEntry

  var body: some View {
    switch family {
    case .accessoryInline:
      if let n = entry.next { Text("\(n.code) · ") + Text(n.startDate, style: .time) } else { Text(entry.line) }
    case .accessoryRectangular:
      if let n = entry.next {
        VStack(alignment: .leading) {
          Text(n.code).font(.headline)
          Text(n.startDate, style: .time)
          CountdownText(next: n, date: entry.date).font(.caption)
        }
      } else {
        Text(entry.line)
      }
    default:
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          PortalGlyph()
          Text(entry.next == nil ? "IntPortal" : (entry.next!.startDate > entry.date ? "UP NEXT" : "IN CLASS"))
            .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        }
        if let n = entry.next {
          Text(n.code).font(.headline).foregroundStyle(gold)
          Text(n.title).font(.caption).lineLimit(2)
          Spacer(minLength: 0)
          CountdownText(next: n, date: entry.date).font(.title3.weight(.bold)).monospacedDigit()
          if n.online { Text("Online").font(.caption2).foregroundStyle(.secondary) }
        } else {
          Spacer(minLength: 0)
          Text(entry.line).font(.callout)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }
}

struct NextClassWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "NextClass", provider: GlanceProvider()) { entry in
      if #available(iOS 17.0, *) {
        NextClassView(entry: entry).containerBackground(ground, for: .widget).environment(\.colorScheme, .dark)
      } else {
        NextClassView(entry: entry).padding().background(ground).environment(\.colorScheme, .dark)
      }
    }
    .configurationDisplayName("Next class")
    .description("Your next class and how long until it starts.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
  }
}

#if canImport(ActivityKit)
@available(iOS 16.2, *)
struct ClassLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: ClassActivityAttributes.self) { context in
      let s = context.state
      HStack(spacing: 12) {
        PortalGlyph()
        VStack(alignment: .leading, spacing: 2) {
          Text(s.code).font(.headline).foregroundStyle(gold)
          Text(s.title).font(.caption).lineLimit(1)
        }
        Spacer()
        VStack(alignment: .trailing) {
          if s.start > .now {
            Text(timerInterval: Date.now...s.start, countsDown: true).font(.title2.weight(.bold)).monospacedDigit()
            Text("to class").font(.caption2).foregroundStyle(.secondary)
          } else {
            Text(timerInterval: s.start...s.end, countsDown: true).font(.title2.weight(.bold)).monospacedDigit()
            Text("left in class").font(.caption2).foregroundStyle(.secondary)
          }
        }
      }
      .padding()
      .activityBackgroundTint(ground)
      .activitySystemActionForegroundColor(gold)
      .environment(\.colorScheme, .dark)
    } dynamicIsland: { context in
      let s = context.state
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          HStack { PortalGlyph(); Text(s.code).font(.headline).foregroundStyle(gold) }
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(timerInterval: s.start > .now ? Date.now...s.start : s.start...s.end, countsDown: true)
            .monospacedDigit().frame(width: 70).font(.headline)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text("\(s.title)\(s.online ? " · Online" : "") · \(s.start.formatted(date: .omitted, time: .shortened))–\(s.end.formatted(date: .omitted, time: .shortened))")
            .font(.caption).lineLimit(1)
        }
      } compactLeading: {
        PortalGlyph()
      } compactTrailing: {
        Text(timerInterval: s.start > .now ? Date.now...s.start : s.start...s.end, countsDown: true)
          .monospacedDigit().frame(width: 44).font(.caption.weight(.bold)).foregroundStyle(gold)
      } minimal: {
        PortalGlyph()
      }
    }
  }
}
#endif

@main
struct IntPortalWidgets: WidgetBundle {
  var body: some Widget {
    NextClassWidget()
    if #available(iOS 16.2, *) {
      ClassLiveActivity()
    }
  }
}
