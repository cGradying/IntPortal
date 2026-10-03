import EventKit
import Foundation
import SwiftRs
import Tauri
import UIKit
import WebKit

/// The calendar the app owns. Its identifier is remembered, so renaming it
/// in the Calendar app doesn't make a second one.
let ownedKey = "intportal.calendar.id"

struct DeviceEvent: Encodable {
  let title: String
  /// Unix milliseconds.
  let start: Double
  let end: Double
  let allDay: Bool
}

struct ClassEvent: Decodable {
  let title: String
  let notes: String
  let start: Double
  let end: Double
}

class RangeArgs: Decodable {
  let from: Double
  let to: Double
}

class SyncArgs: Decodable {
  let from: Double
  let to: Double
  let events: [ClassEvent]
}

class CalendarPlugin: Plugin {
  let store = EKEventStore()

  static func status() -> String {
    let s = EKEventStore.authorizationStatus(for: .event)
    if #available(iOS 17.0, *) {
      switch s {
      case .fullAccess: return "granted"
      case .writeOnly: return "write_only"
      case .notDetermined: return "not_asked"
      default: return "denied"
      }
    }
    switch s {
    case .authorized: return "granted"
    case .notDetermined: return "not_asked"
    default: return "denied"
    }
  }

  @objc public func status(_ invoke: Invoke) {
    invoke.resolve(["status": CalendarPlugin.status()])
  }

  @objc public func request(_ invoke: Invoke) {
    let done: (Bool, Error?) -> Void = { _, _ in invoke.resolve(["status": CalendarPlugin.status()]) }
    if #available(iOS 17.0, *) {
      store.requestFullAccessToEvents(completion: done)
    } else {
      store.requestAccess(to: .event, completion: done)
    }
  }

  /// The student's own events in the range, leaving out the app's calendar.
  @objc public func events(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(RangeArgs.self)
    guard CalendarPlugin.status() == "granted" else { return invoke.resolve(["events": [DeviceEvent]()]) }
    let owned = UserDefaults.standard.string(forKey: ownedKey)
    let calendars = store.calendars(for: .event).filter { $0.calendarIdentifier != owned }
    let predicate = store.predicateForEvents(
      withStart: Date(timeIntervalSince1970: args.from / 1000), end: Date(timeIntervalSince1970: args.to / 1000), calendars: calendars)
    let found = store.events(matching: predicate).map {
      DeviceEvent(
        title: $0.title ?? "", start: $0.startDate.timeIntervalSince1970 * 1000, end: $0.endDate.timeIntervalSince1970 * 1000, allDay: $0.isAllDay)
    }
    invoke.resolve(["events": found])
  }

  /// Replaces the IntPortal calendar's events in the range with these.
  @objc public func syncClasses(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(SyncArgs.self)
    guard CalendarPlugin.status() == "granted" else { return invoke.reject("Calendar access is off.") }
    let calendar = try owned()
    let predicate = store.predicateForEvents(
      withStart: Date(timeIntervalSince1970: args.from / 1000), end: Date(timeIntervalSince1970: args.to / 1000), calendars: [calendar])
    for old in store.events(matching: predicate) {
      try store.remove(old, span: .thisEvent, commit: false)
    }
    for e in args.events {
      let event = EKEvent(eventStore: store)
      event.calendar = calendar
      event.title = e.title
      event.notes = e.notes
      event.startDate = Date(timeIntervalSince1970: e.start / 1000)
      event.endDate = Date(timeIntervalSince1970: e.end / 1000)
      try store.save(event, span: .thisEvent, commit: false)
    }
    try store.commit()
    invoke.resolve(["count": args.events.count])
  }

  /// The app's own calendar, made on first use in the same account as the
  /// student's default calendar (iCloud when they use it), else on the phone.
  func owned() throws -> EKCalendar {
    if let id = UserDefaults.standard.string(forKey: ownedKey), let found = store.calendar(withIdentifier: id) {
      return found
    }
    let calendar = EKCalendar(for: .event, eventStore: store)
    calendar.title = "IntPortal"
    calendar.cgColor = UIColor(red: 0.48, green: 0.07, blue: 0.16, alpha: 1).cgColor
    calendar.source =
      store.defaultCalendarForNewEvents?.source ?? store.sources.first { $0.sourceType == .local } ?? store.sources.first
    try store.saveCalendar(calendar, commit: true)
    UserDefaults.standard.set(calendar.calendarIdentifier, forKey: ownedKey)
    return calendar
  }
}

@_cdecl("init_plugin_calendar")
func initPlugin() -> Plugin {
  return CalendarPlugin()
}
