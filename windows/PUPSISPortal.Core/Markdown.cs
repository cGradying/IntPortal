namespace PUPSISPortal.Core;

/// <summary>
/// A minimal, Obsidian-flavored Markdown block model — enough for notes: ATX
/// headings (`#`…`######`), unordered bullets (`-`/`*`), task checkboxes
/// (`- [ ]` / `- [x]`), and plain paragraphs. Inline emphasis (`**bold**`,
/// `*italic*`, `` `code` ``) is left to rendering at runtime — this only
/// splits the block structure that rendering can't handle.
///
/// Pure and line-based on purpose, so it's testable without a view.
/// </summary>
public class MarkdownBlock : IEquatable<MarkdownBlock>
{
    public enum Kind
    {
        Heading,
        Bullet,
        Checkbox,
        Paragraph,
        Blank,
    }

    public Kind Type { get; }
    public int Level { get; }
    public bool Done { get; }
    public string Text { get; }

    private MarkdownBlock(Kind type, int level = 0, bool done = false, string text = "")
    {
        Type = type;
        Level = level;
        Done = done;
        Text = text;
    }

    public static MarkdownBlock Heading(int level, string text) => new(Kind.Heading, level, false, text);
    public static MarkdownBlock Bullet(string text) => new(Kind.Bullet, 0, false, text);
    public static MarkdownBlock Checkbox(bool done, string text) => new(Kind.Checkbox, 0, done, text);
    public static MarkdownBlock Paragraph(string text) => new(Kind.Paragraph, 0, false, text);
    public static MarkdownBlock Blank => new(Kind.Blank);

    public override bool Equals(object? obj) => Equals(obj as MarkdownBlock);

    public bool Equals(MarkdownBlock? other)
    {
        if (other is null) return false;
        return Type == other.Type && Level == other.Level && Done == other.Done && Text == other.Text;
    }

    public override int GetHashCode() => HashCode.Combine(Type, Level, Done, Text);
}

/// <summary>
/// Parse Markdown text into blocks.
/// </summary>
public static class Markdown
{
    public static List<MarkdownBlock> Parse(string text)
    {
        return text.Split('\n')
            .Select(Block)
            .ToList();
    }

    private static MarkdownBlock Block(string line)
    {
        var trimmed = line.Trim();
        if (string.IsNullOrEmpty(trimmed))
            return MarkdownBlock.Blank;

        // Heading: 1–6 leading '#', then a space.
        if (trimmed[0] == '#')
        {
            var hashCount = 0;
            foreach (var c in trimmed)
            {
                if (c == '#') hashCount++;
                else break;
            }

            if (hashCount >= 1 && hashCount <= 6 && trimmed.Length > hashCount && trimmed[hashCount] == ' ')
            {
                return MarkdownBlock.Heading(hashCount, trimmed.Substring(hashCount + 1).Trim());
            }
        }

        // Bullet / checkbox: '- ' or '* '
        foreach (var marker in new[] { "- ", "* " })
        {
            if (trimmed.StartsWith(marker))
            {
                var rest = trimmed.Substring(marker.Length);
                if (rest.StartsWith("[ ] "))
                {
                    return MarkdownBlock.Checkbox(false, rest.Substring(4));
                }

                if (rest.StartsWith("[x] ", StringComparison.OrdinalIgnoreCase))
                {
                    return MarkdownBlock.Checkbox(true, rest.Substring(4));
                }

                return MarkdownBlock.Bullet(rest);
            }
        }

        return MarkdownBlock.Paragraph(trimmed);
    }
}
