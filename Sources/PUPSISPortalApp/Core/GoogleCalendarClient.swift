import Foundation

/// A Google calendar the user can export into.
struct GoogleCalendar: Identifiable, Equatable {
    let id: String
    let summary: String
}

/// One event as Google's Calendar API wants it. Encodable so the export body is
/// built purely (and unit-tested) before it ever hits the network.
struct GoogleEvent: Encodable, Equatable {
    struct DateTime: Encodable, Equatable {
        let dateTime: String
        let timeZone: String
    }
    struct Extended: Encodable, Equatable {
        let `private`: [String: String]
    }
    let summary: String
    let location: String?
    let description: String?
    let start: DateTime
    let end: DateTime
    let recurrence: [String]
    let extendedProperties: Extended
}

/// Writes classes straight to Google Calendar over the REST API — the reliable
/// path when Google-via-Apple-Calendar (CalDAV) won't take recurring writes.
///
/// Mirrors `CalendarBridge.exportClasses`: it clears its own previous export
/// first (events tagged `pupsisportal=1` in `extendedProperties.private`) so a
/// re-export replaces rather than stacks, and leaves the user's other events
/// alone. Term status only, like the `.ics` export — a single repeating event
/// can't carry a one-week exception.
@MainActor
final class GoogleCalendarClient {
    /// The tag on every event this app writes, so a re-export removes only ours.
    static let tagKey = "pupsisportal"
    static let tagValue = "1"

    private let auth: GoogleAuth

    init(auth: GoogleAuth) {
        self.auth = auth
    }

    enum ClientError: LocalizedError {
        case http(String)
        var errorDescription: String? {
            switch self { case .http(let m): m }
        }
    }

    // MARK: Calendars

    func listCalendars() async throws -> [GoogleCalendar] {
        struct List: Decodable {
            let items: [Item]
            struct Item: Decodable { let id: String; let summary: String; let accessRole: String }
        }
        let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
        let data = try await get(url)
        let list = try JSONDecoder().decode(List.self, from: data)
        // Only calendars the user can write to are useful as export targets.
        return list.items
            .filter { $0.accessRole == "owner" || $0.accessRole == "writer" }
            .map { GoogleCalendar(id: $0.id, summary: $0.summary) }
    }

    // MARK: Export

    /// Returns a short summary of what was written, so a silent no-op is
    /// impossible to mistake for success.
    @discardableResult
    func exportClasses(
        _ sessions: [ClassSession],
        weekStart: Date,
        until termEnd: Date,
        toCalendarID calendarID: String,
        status: (ClassSession) -> SessionStatus,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) async throws -> String {
        let removed = try await clearExported(calendarID: calendarID)

        var written = 0
        for session in sessions {
            guard let event = Self.event(
                for: session, status: status(session),
                weekStart: weekStart, until: termEnd,
                calendar: calendar, timeZone: timeZone
            ) else { continue }
            try await insert(event, calendarID: calendarID)
            written += 1
        }

        let replaced = removed > 0 ? ", replacing \(removed)" : ""
        return "Exported \(written) class\(written == 1 ? "" : "es") to Google\(replaced)."
    }

    /// The event body for a class in its term status, or nil when it shouldn't be
    /// written (vacant). Pure, so the summary/RRULE/tag are unit-tested without
    /// the network. Reuses `CalendarBridge.ClassExport.plan` so Google and the
    /// EventKit/.ics exports agree on skip/online rules.
    static func event(
        for session: ClassSession,
        status: SessionStatus,
        weekStart: Date,
        until termEnd: Date,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> GoogleEvent? {
        guard case let .event(titleSuffix, location) = CalendarBridge.ClassExport.plan(for: status) else {
            return nil
        }

        let midnight = session.day.date(inWeekStarting: weekStart, calendar: calendar)
        guard let start = calendar.date(byAdding: .minute, value: session.start, to: midnight),
              let end = calendar.date(byAdding: .minute, value: session.end, to: midnight)
        else { return nil }

        let last = ClassRecurrence.lastMoment(of: termEnd, calendar: calendar)
        // Start carries a timezone, so RFC-5545 wants the RRULE UNTIL in UTC.
        let rule = "RRULE:\(ClassRecurrence.rrule(day: session.day, until: ClassRecurrence.utc(last)))"

        let iso = ISO8601DateFormatter()
        iso.timeZone = timeZone
        iso.formatOptions = [.withInternetDateTime]
        let tz = timeZone.identifier

        return GoogleEvent(
            summary: session.subjectCode + (titleSuffix ?? ""),
            location: location,
            description: session.faculty.isEmpty ? session.description : "\(session.description)\n\(session.faculty)",
            start: .init(dateTime: iso.string(from: start), timeZone: tz),
            end: .init(dateTime: iso.string(from: end), timeZone: tz),
            recurrence: [rule],
            extendedProperties: .init(private: [tagKey: tagValue])
        )
    }

    // MARK: Detail

    private func clearExported(calendarID: String) async throws -> Int {
        struct List: Decodable {
            let items: [Item]
            struct Item: Decodable { let id: String }
        }
        var comps = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encode(calendarID))/events")!
        comps.queryItems = [
            .init(name: "privateExtendedProperty", value: "\(Self.tagKey)=\(Self.tagValue)"),
            .init(name: "maxResults", value: "2500"),
            // Recurring events return as the master here, so deleting it drops the
            // whole series in one call.
            .init(name: "singleEvents", value: "false"),
        ]
        let data = try await get(comps.url!)
        let list = try JSONDecoder().decode(List.self, from: data)

        for item in list.items {
            let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encode(calendarID))/events/\(encode(item.id))")!
            try await delete(url)
        }
        return list.items.count
    }

    private func insert(_ event: GoogleEvent, calendarID: String) async throws {
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encode(calendarID))/events")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(event)
        _ = try await send(request)
    }

    // MARK: HTTP

    private func get(_ url: URL) async throws -> Data {
        try await send(URLRequest(url: url))
    }

    private func delete(_ url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        let token = try await auth.validAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.http("No response from Google.") }
        // A delete of an already-gone event is fine.
        guard (200..<300).contains(http.statusCode) || http.statusCode == 410 else {
            throw ClientError.http(Self.googleError(data, status: http.statusCode))
        }
        return data
    }

    private func encode(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? component
    }

    private static func googleError(_ data: Data, status: Int) -> String {
        struct E: Decodable { struct Err: Decodable { let message: String }; let error: Err? }
        if let e = try? JSONDecoder().decode(E.self, from: data), let m = e.error?.message {
            return "Google: \(m)"
        }
        return "Google request failed (\(status))."
    }
}
