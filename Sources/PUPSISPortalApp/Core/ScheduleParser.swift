import Foundation

/// Turns a scraped SIS schedule row into individual class blocks.
///
/// The schedule cell looks like:
///     "1N - BSCS 1-1N - T/F 02:00PM-04:00PM/01:30PM-04:30PM"
/// Days and time ranges are `/`-separated and paired positionally, so the
/// same day twice (`SUN/SUN`) means two blocks that day (Lec then Lab).
enum ScheduleParser {
    static func parse(_ row: [String: String]) -> [ClassSession] {
        let line = row["scheduleLine"] ?? ""
        guard let (dayField, timeField) = splitDaysAndTimes(line) else { return [] }

        let days = dayField.split(separator: "/").flatMap { tokenizeDays(String($0)) }
        let ranges = timeField.split(separator: "/").compactMap { parseRange(String($0)) }
        guard !days.isEmpty, !ranges.isEmpty else { return [] }

        let subjectCode = row["subjectCode"] ?? ""
        let description = row["description"] ?? ""
        let faculty = row["faculty"] ?? ""

        // One day with several ranges means the same day meets more than once;
        // otherwise days and ranges line up one-to-one.
        let count = days.count == 1 ? ranges.count : min(days.count, ranges.count)
        return (0..<count).map { index in
            let day = days.count == 1 ? days[0] : days[index]
            let range = ranges[min(index, ranges.count - 1)]
            return ClassSession(
                subjectCode: subjectCode,
                description: description,
                faculty: faculty,
                day: day,
                start: range.0,
                end: range.1
            )
        }
    }

    /// Pulls the trailing "<DAYS> <TIMES>" off the end of the schedule line,
    /// ignoring the section prefix (which contains digits and hyphens).
    private static func splitDaysAndTimes(_ line: String) -> (String, String)? {
        let pattern = #"([A-Z]+(?:/[A-Z]+)*)\s+((?:\d{1,2}:\d{2}[AP]M-\d{1,2}:\d{2}[AP]M)(?:/\d{1,2}:\d{2}[AP]M-\d{1,2}:\d{2}[AP]M)*)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let dayRange = Range(match.range(at: 1), in: line),
              let timeRange = Range(match.range(at: 2), in: line)
        else { return nil }
        return (String(line[dayRange]), String(line[timeRange]))
    }

    /// Handles both slash-separated codes and runs like "TTH" / "MW".
    private static func tokenizeDays(_ token: String) -> [Weekday] {
        var remainder = Substring(token)
        var days: [Weekday] = []
        outer: while !remainder.isEmpty {
            for (code, day) in Weekday.codes where remainder.hasPrefix(code) {
                days.append(day)
                remainder = remainder.dropFirst(code.count)
                continue outer
            }
            return days.isEmpty ? [] : days // unrecognized tail — keep what parsed
        }
        return days
    }

    /// "02:00PM-04:00PM" -> (840, 960) in minutes from midnight.
    private static func parseRange(_ text: String) -> (Int, Int)? {
        let parts = text.split(separator: "-")
        guard parts.count == 2,
              let start = parseTime(String(parts[0])),
              let end = parseTime(String(parts[1]))
        else { return nil }
        return (start, end)
    }

    private static func parseTime(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.count >= 6 else { return nil }
        let period = String(trimmed.suffix(2))
        let clock = trimmed.dropLast(2).split(separator: ":")
        guard period == "AM" || period == "PM",
              clock.count == 2,
              var hour = Int(clock[0]),
              let minute = Int(clock[1]),
              (1...12).contains(hour),
              (0..<60).contains(minute)
        else { return nil }
        if period == "PM" && hour != 12 { hour += 12 }
        if period == "AM" && hour == 12 { hour = 0 }
        return hour * 60 + minute
    }
}
