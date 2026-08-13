namespace PUPSISPortal.Core;

/// <summary>
/// The schedule as it was last scraped, plus when that happened.
/// Used for round-trip serialization/deserialization.
/// </summary>
public record CachedSchedule
{
    public required DateTime LastUpdated { get; set; }
    public required List<ClassSession> Sessions { get; set; }
}
