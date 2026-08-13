using System.Text.Json.Serialization;

namespace PUPSISPortal.Core;

/// <summary>
/// What's actually happening with a class meeting. The SIS doesn't say — it
/// only lists the room-and-time it was enrolled as — so this is the user
/// telling the app something it can't scrape.
/// </summary>
[JsonConverter(typeof(JsonStringEnumConverter))]
public enum SessionStatus
{
    Regular,
    Online,
    Vacant,
}

public static class SessionStatusExtensions
{
    public static string Label(this SessionStatus status) => status switch
    {
        SessionStatus.Regular => "In Person",
        SessionStatus.Online => "Online",
        SessionStatus.Vacant => "Vacant",
        _ => "",
    };

    public static string Symbol(this SessionStatus status) => status switch
    {
        SessionStatus.Regular => "building.2",
        SessionStatus.Online => "video.fill",
        SessionStatus.Vacant => "calendar.badge.minus",
        _ => "",
    };
}
