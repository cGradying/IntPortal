using System.Text.Json;
using System.Text.Json.Serialization;
using System.Web;

namespace PUPSISPortal.Core;

/// <summary>
/// A Google calendar the user can export into.
/// </summary>
public class GoogleCalendar
{
    [JsonPropertyName("id")]
    public required string Id { get; set; }

    [JsonPropertyName("summary")]
    public required string Summary { get; set; }
}

/// <summary>
/// One event as Google's Calendar API wants it. Serializable so the export body is
/// built purely (and unit-tested) before it ever hits the network.
/// </summary>
public class GoogleEvent
{
    [JsonPropertyName("summary")]
    public required string Summary { get; set; }

    [JsonPropertyName("location")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Location { get; set; }

    [JsonPropertyName("description")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Description { get; set; }

    [JsonPropertyName("start")]
    public required GoogleEventDateTime Start { get; set; }

    [JsonPropertyName("end")]
    public required GoogleEventDateTime End { get; set; }

    [JsonPropertyName("recurrence")]
    public required List<string> Recurrence { get; set; }

    [JsonPropertyName("extendedProperties")]
    public required GoogleEventExtendedProperties ExtendedProperties { get; set; }
}

public class GoogleEventDateTime
{
    [JsonPropertyName("dateTime")]
    public required string DateTime { get; set; }

    [JsonPropertyName("timeZone")]
    public required string TimeZone { get; set; }
}

public class GoogleEventExtendedProperties
{
    [JsonPropertyName("private")]
    public required Dictionary<string, string> Private { get; set; }
}

/// <summary>
/// Writes classes straight to Google Calendar over the REST API — the reliable
/// path when Google-via-system-Calendar (CalDAV) won't take recurring writes.
///
/// Mirrors the calendar export: it clears its own previous export first (events
/// tagged `pupsisportal=1` in `extendedProperties.private`) so a re-export replaces
/// rather than stacks, and leaves the user's other events alone. Term status only,
/// like the `.ics` export — a single repeating event can't carry a one-week exception.
/// </summary>
public class GoogleCalendarClient
{
    /// <summary>
    /// The tag on every event this app writes, so a re-export removes only ours.
    /// </summary>
    public const string TagKey = "pupsisportal";
    public const string TagValue = "1";

    private readonly Func<Task<string>> _getAccessToken;
    private static readonly HttpClient HttpClient = new();

    public GoogleCalendarClient(Func<Task<string>> getAccessToken)
    {
        _getAccessToken = getAccessToken;
    }

    public class ClientException : Exception
    {
        public ClientException(string message) : base(message) { }
    }

    // MARK: Calendars

    public async Task<List<GoogleCalendar>> ListCalendarsAsync()
    {
        const string url = "https://www.googleapis.com/calendar/v3/users/me/calendarList";
        var data = await GetAsync(url);

        var list = JsonSerializer.Deserialize<CalendarList>(data);
        if (list?.Items == null)
            return new List<GoogleCalendar>();

        // Only calendars the user can write to are useful as export targets.
        return list.Items
            .Where(item => item.AccessRole == "owner" || item.AccessRole == "writer")
            .Select(item => new GoogleCalendar { Id = item.Id, Summary = item.Summary })
            .ToList();
    }

    // MARK: Export

    /// <summary>
    /// Returns a short summary of what was written, so a silent no-op is
    /// impossible to mistake for success.
    /// </summary>
    public async Task<string> ExportClassesAsync(
        List<ClassSession> sessions,
        DateTime weekStart,
        DateTime termEnd,
        string calendarId,
        Func<ClassSession, SessionStatus> statusResolver)
    {
        var removed = await ClearExportedAsync(calendarId);

        var written = 0;
        foreach (var session in sessions)
        {
            var googleEvent = Event(session, statusResolver(session), weekStart, termEnd);
            if (googleEvent == null)
                continue;

            await InsertAsync(googleEvent, calendarId);
            written++;
        }

        var replaced = removed > 0 ? $", replacing {removed}" : "";
        return $"Exported {written} class{(written == 1 ? "" : "es")} to Google{replaced}.";
    }

    /// <summary>
    /// The event body for a class in its term status, or null when it shouldn't be
    /// written (vacant). Pure, so the summary/RRULE/tag are unit-tested without
    /// the network. Accepts timezone for testing (defaults to system local).
    /// </summary>
    public static GoogleEvent? Event(
        ClassSession session,
        SessionStatus status,
        DateTime weekStart,
        DateTime termEnd,
        TimeZoneInfo? timeZone = null)
    {
        var plan = ClassExportPlan(status);
        if (plan is null)
            return null;

        var (titleSuffix, location) = plan.Value;

        timeZone ??= TimeZoneInfo.Local;
        var tzId = timeZone.Id;

        var midnight = session.Day.DateInWeekStarting(weekStart);
        var start = midnight.AddMinutes(session.Start);
        var end = midnight.AddMinutes(session.End);

        var last = ClassRecurrence.LastMoment(termEnd);

        // Start carries a timezone, so RFC-5545 wants the RRULE UNTIL in UTC.
        var rule = $"RRULE:{ClassRecurrence.RRule(session.Day, ClassRecurrence.Utc(last))}";

        // Format as ISO8601 without timezone indicator; the timezone is in the separate field
        var iso = start.ToString("yyyy-MM-ddTHH:mm:ss");
        var endIso = end.ToString("yyyy-MM-ddTHH:mm:ss");

        return new GoogleEvent
        {
            Summary = session.SubjectCode + (titleSuffix ?? ""),
            Location = location,
            Description = string.IsNullOrEmpty(session.Faculty)
                ? session.Description
                : $"{session.Description}\n{session.Faculty}",
            Start = new GoogleEventDateTime { DateTime = iso, TimeZone = tzId },
            End = new GoogleEventDateTime { DateTime = endIso, TimeZone = tzId },
            Recurrence = new List<string> { rule },
            ExtendedProperties = new GoogleEventExtendedProperties
            {
                Private = new Dictionary<string, string> { { TagKey, TagValue } }
            }
        };
    }

    // MARK: Detail

    private async Task<int> ClearExportedAsync(string calendarId)
    {
        var comps = $"https://www.googleapis.com/calendar/v3/calendars/{UrlEncode(calendarId)}/events?" +
                    $"privateExtendedProperty={UrlEncode($"{TagKey}={TagValue}")}&" +
                    "maxResults=2500&" +
                    "singleEvents=false";

        var data = await GetAsync(comps);
        var list = JsonSerializer.Deserialize<EventList>(data);

        var count = 0;
        if (list?.Items != null)
        {
            foreach (var item in list.Items)
            {
                var url = $"https://www.googleapis.com/calendar/v3/calendars/{UrlEncode(calendarId)}/events/{UrlEncode(item.Id)}";
                try
                {
                    await DeleteAsync(url);
                    count++;
                }
                catch
                {
                    // Ignore errors on individual deletes
                }
            }
        }

        return count;
    }

    private async Task InsertAsync(GoogleEvent googleEvent, string calendarId)
    {
        var url = $"https://www.googleapis.com/calendar/v3/calendars/{UrlEncode(calendarId)}/events";
        var json = JsonSerializer.Serialize(googleEvent);
        var content = new StringContent(json, System.Text.Encoding.UTF8, "application/json");

        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = content
        };

        await SendAsync(request);
    }

    // MARK: HTTP

    private async Task<string> GetAsync(string url)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        return await SendAsync(request);
    }

    private async Task DeleteAsync(string url)
    {
        using var request = new HttpRequestMessage(HttpMethod.Delete, url);
        await SendAsync(request);
    }

    private async Task<string> SendAsync(HttpRequestMessage request)
    {
        var token = await _getAccessToken();
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

        var response = await HttpClient.SendAsync(request);

        // A delete of an already-gone event is fine.
        if (!response.IsSuccessStatusCode && response.StatusCode != System.Net.HttpStatusCode.Gone)
        {
            var body = await response.Content.ReadAsStringAsync();
            throw new ClientException(GoogleError(body, (int)response.StatusCode));
        }

        return await response.Content.ReadAsStringAsync();
    }

    private static string UrlEncode(string component)
    {
        return HttpUtility.UrlEncode(component);
    }

    private static string GoogleError(string data, int status)
    {
        try
        {
            var errorResponse = JsonSerializer.Deserialize<GoogleErrorResponse>(data);
            if (errorResponse?.Error?.Message != null)
            {
                return $"Google: {errorResponse.Error.Message}";
            }
        }
        catch
        {
            // Ignore parsing errors
        }

        return $"Google request failed ({status}).";
    }

    // MARK: JSON Models

    private class CalendarList
    {
        [JsonPropertyName("items")]
        public List<CalendarItem>? Items { get; set; }
    }

    private class CalendarItem
    {
        [JsonPropertyName("id")]
        public required string Id { get; set; }

        [JsonPropertyName("summary")]
        public required string Summary { get; set; }

        [JsonPropertyName("accessRole")]
        public required string AccessRole { get; set; }
    }

    private class EventList
    {
        [JsonPropertyName("items")]
        public List<EventItem>? Items { get; set; }
    }

    private class EventItem
    {
        [JsonPropertyName("id")]
        public required string Id { get; set; }
    }

    private class GoogleErrorResponse
    {
        [JsonPropertyName("error")]
        public ErrorDetail? Error { get; set; }
    }

    private class ErrorDetail
    {
        [JsonPropertyName("message")]
        public string? Message { get; set; }
    }

    // MARK: Export plan helper

    private static (string? titleSuffix, string? location)? ClassExportPlan(SessionStatus sessionStatus)
    {
        return sessionStatus switch
        {
            SessionStatus.Regular => ("", null),
            SessionStatus.Online => (" (Online)", "Online"),
            SessionStatus.Vacant => null,
            _ => null,
        };
    }
}
