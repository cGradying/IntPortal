namespace PUPSISPortal.App.Platform;

/// <summary>
/// Where pasted/dropped note images live on disk — the Windows counterpart of
/// the macOS <c>NoteImages</c> enum in WebNoteEditor.swift. Same LocalAppData
/// root as the JSON stores, own subfolder; served back to the editor over a
/// WebView2 virtual host mapping (<see cref="Views.NotesView"/>) rather than a
/// custom URL scheme.
/// </summary>
public static class NoteImageStore
{
    public static readonly string Directory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "PUPSISPortal", "note-images");

    /// <summary>
    /// Decodes base64 and writes it as a new file; returns the file name (not a
    /// full URL — the caller prefixes the virtual host) or null on I/O failure.
    /// </summary>
    public static string? Save(string base64, string ext)
    {
        byte[] data;
        try { data = Convert.FromBase64String(base64); }
        catch { return null; }

        System.IO.Directory.CreateDirectory(Directory);
        var letters = new string(ext.Where(char.IsLetter).ToArray()).ToLowerInvariant();
        var name = $"{Guid.NewGuid():N}.{(letters.Length == 0 ? "png" : letters)}";
        try
        {
            File.WriteAllBytes(Path.Combine(Directory, name), data);
            return name;
        }
        catch
        {
            return null;
        }
    }
}
