namespace PUPSISPortal.Core;

/// <summary>
/// A single note — free text, when it last changed, and an optional display
/// title so the notes history can label a note whose class/event isn't on today's
/// schedule. `Title` is optional so older `notes.json` files still decode.
/// </summary>
public record Note
{
    public required string Text { get; set; }
    public required DateTime Updated { get; set; }
    public string? Title { get; set; }
}
