using System.Text.RegularExpressions;

namespace PUPSISPortal.Core;

/// <summary>
/// Pure selection transforms behind the notes toolbar — no UI, no system text editing.
/// Each takes the full text plus the current range selection and returns the
/// new text and where the selection should land. Ranges are UTF-16, matching
/// the model's string representation. Kept pure so the cursor math is unit-testable.
/// </summary>
public static class MarkdownCommands
{
    public record Result(string Text, int Start, int Length)
    {
        public void Deconstruct(out string text, out int start, out int length)
        {
            text = Text;
            start = Start;
            length = Length;
        }
    }

    // MARK: Inline wrap (bold / italic / strike / highlight / code)

    /// <summary>
    /// Wrap the selection in `marker` on both sides. With no selection, insert the
    /// pair and drop the cursor between them so the user can type inside.
    /// </summary>
    public static Result Wrap(string text, int rangeStart, int rangeLength, string marker)
    {
        var selected = text.Substring(rangeStart, rangeLength);
        if (selected.Length == 0)
        {
            var newText = text.Substring(0, rangeStart) + marker + marker + text.Substring(rangeStart);
            return new Result(newText, rangeStart + marker.Length, 0);
        }

        var newText2 = text.Substring(0, rangeStart) + marker + selected + marker + text.Substring(rangeStart + rangeLength);
        return new Result(newText2, rangeStart + marker.Length, selected.Length);
    }

    // MARK: Line prefixes (bullet / numbered / quote / checklist)

    public static Result ToggleBullet(string text, int rangeStart, int rangeLength)
    {
        return TransformLines(text, rangeStart, rangeLength, lines =>
        {
            var all = lines.All(line => Regex.IsMatch(line, @"^\s*[-*] "));
            return lines.Select(line =>
            {
                if (all)
                {
                    return Regex.Replace(line, @"^(\s*)[-*] ", "$1");
                }
                return Regex.IsMatch(line, @"^\s*[-*] ") ? line : "- " + line;
            }).ToList();
        });
    }

    public static Result ToggleQuote(string text, int rangeStart, int rangeLength)
    {
        return TransformLines(text, rangeStart, rangeLength, lines =>
        {
            var all = lines.All(line => line.StartsWith("> "));
            return lines.Select(line =>
            {
                if (all) return line.Length > 2 ? line.Substring(2) : line;
                return line.StartsWith("> ") ? line : "> " + line;
            }).ToList();
        });
    }

    public static Result ToggleNumbered(string text, int rangeStart, int rangeLength)
    {
        return TransformLines(text, rangeStart, rangeLength, lines =>
        {
            var all = lines.All(line => Regex.IsMatch(line, @"^\s*\d+\. "));
            if (all)
            {
                return lines.Select(line => Regex.Replace(line, @"^(\s*)\d+\. ", "$1")).ToList();
            }

            return lines.Select((line, index) =>
                Regex.IsMatch(line, @"^\s*\d+\. ") ? line : $"{index + 1}. {line}"
            ).ToList();
        });
    }

    public static Result ToggleChecklist(string text, int rangeStart, int rangeLength)
    {
        return TransformLines(text, rangeStart, rangeLength, lines =>
        {
            const string mark = @"^\s*- \[[ xX]\] ";
            var all = lines.All(line => Regex.IsMatch(line, mark));
            return lines.Select(line =>
            {
                if (all)
                {
                    return Regex.Replace(line, @"^(\s*)- \[[ xX]\] ", "$1");
                }
                return Regex.IsMatch(line, mark) ? line : "- [ ] " + line;
            }).ToList();
        });
    }

    /// <summary>
    /// Flip a single checkbox line's mark. Used by the click-to-toggle handler.
    /// </summary>
    public static string ToggleCheckbox(string line)
    {
        if (line.Contains("- [ ] "))
        {
            return line.Replace("- [ ] ", "- [x] ");
        }

        foreach (var mark in new[] { "- [x] ", "- [X] " })
        {
            if (line.Contains(mark))
            {
                return line.Replace(mark, "- [ ] ");
            }
        }

        return line;
    }

    // MARK: Heading / link

    /// <summary>
    /// Cycle the current line: none → `# ` → `## ` → … → `###### ` → none.
    /// </summary>
    public static Result CycleHeading(string text, int rangeStart, int rangeLength)
    {
        var lines = text.Split('\n');
        var lineIndex = 0;
        var charCount = 0;

        // Find which line contains rangeStart
        foreach (var (line, idx) in lines.Select((l, i) => (l, i)))
        {
            if (charCount + line.Length + 1 >= rangeStart || idx == lines.Length - 1)
            {
                lineIndex = idx;
                break;
            }
            charCount += line.Length + 1; // +1 for newline
        }

        var currentLine = lines[lineIndex];
        var hasTrailingNewline = false;
        if (currentLine.EndsWith("\n"))
        {
            hasTrailingNewline = true;
            currentLine = currentLine.Substring(0, currentLine.Length - 1);
        }

        var hashes = 0;
        foreach (var c in currentLine)
        {
            if (c == '#') hashes++;
            else break;
        }

        var isHeading = hashes >= 1 && hashes <= 6 && currentLine.Length > hashes && currentLine[hashes] == ' ';
        var content = isHeading ? currentLine.Substring(hashes + 1) : currentLine;
        var level = isHeading ? hashes : 0;
        var next = level >= 6 ? 0 : level + 1;

        string newLine;
        if (next == 0)
        {
            newLine = content + (hasTrailingNewline ? "\n" : "");
        }
        else
        {
            newLine = new string('#', next) + " " + content + (hasTrailingNewline ? "\n" : "");
        }

        lines[lineIndex] = newLine;
        var newText = string.Join('\n', lines);
        var caret = charCount + (newLine.EndsWith("\n") ? newLine.Length - 1 : newLine.Length);

        return new Result(newText, caret, 0);
    }

    /// <summary>
    /// Wrap the selection in a color mark `{#RRGGBB:text}`. Empty selection drops
    /// the cursor where the text goes. `hex` is 6 hex digits, no `#`.
    /// </summary>
    public static Result Color(string text, int rangeStart, int rangeLength, string hex)
    {
        var selected = text.Substring(rangeStart, rangeLength);
        var prefix = $"{{#{hex}:";
        var newText = text.Substring(0, rangeStart) + prefix + selected + "}" + text.Substring(rangeStart + rangeLength);
        var innerLocation = rangeStart + prefix.Length;

        return new Result(newText, innerLocation, selected.Length);
    }

    /// <summary>
    /// `[selection](url)` with the cursor landing on the `url` placeholder.
    /// </summary>
    public static Result Link(string text, int rangeStart, int rangeLength)
    {
        var selected = text.Substring(rangeStart, rangeLength);
        const string placeholder = "url";
        var linkPart = $"[{selected}]({placeholder})";
        var newText = text.Substring(0, rangeStart) + linkPart + text.Substring(rangeStart + rangeLength);
        var urlLocation = rangeStart + $"[{selected}](".Length;

        return new Result(newText, urlLocation, placeholder.Length);
    }

    // MARK: Math detection (shared by styler, inline collapse, and tests)

    public class MathMatch : IEquatable<MathMatch>
    {
        public int Start { get; }
        public int Length { get; }
        public string Latex { get; }
        public bool Display { get; }

        public MathMatch(int start, int length, string latex, bool display)
        {
            Start = start;
            Length = length;
            Latex = latex;
            Display = display;
        }

        public override bool Equals(object? obj) => Equals(obj as MathMatch);
        public bool Equals(MathMatch? other)
        {
            return other is not null && Start == other.Start && Length == other.Length && Latex == other.Latex && Display == other.Display;
        }

        public override int GetHashCode() => HashCode.Combine(Start, Length, Latex, Display);
    }

    private static readonly Regex BlockMathRegex = new(@"\$\$([\s\S]+?)\$\$", RegexOptions.Compiled);
    // Non-space boundaries + not preceded by word/`$` keep currency ("$5 and $10")
    // from reading as math.
    private static readonly Regex InlineMathRegex = new(@"(?<![$\w])\$(?! )([^$\n]+?)(?<! )\$(?!\$)", RegexOptions.Compiled);

    /// <summary>
    /// All `$$…$$` / `$…$` spans in `text`, in document order, non-overlapping
    /// (block wins). Used to render/collapse math and to reconstruct source.
    /// </summary>
    public static List<MathMatch> MathMatches(string text)
    {
        var matches = new List<MathMatch>();

        // Find all block math first
        foreach (Match match in BlockMathRegex.Matches(text))
        {
            var latex = match.Groups[1].Value;
            matches.Add(new MathMatch(match.Index, match.Length, latex, display: true));
        }

        // Find all inline math
        foreach (Match match in InlineMathRegex.Matches(text))
        {
            var latex = match.Groups[1].Value;
            // Skip if it overlaps with a block match
            if (matches.Any(m => !(match.Index + match.Length <= m.Start || match.Index >= m.Start + m.Length)))
                continue;

            matches.Add(new MathMatch(match.Index, match.Length, latex, display: false));
        }

        // Sort by position
        matches.Sort((a, b) => a.Start.CompareTo(b.Start));
        return matches;
    }

    // MARK: Line helper

    /// <summary>
    /// Apply `transform` to every line the selection touches, keeping the block
    /// selected afterward. Preserves a trailing newline so the last line isn't
    /// merged into the next.
    /// </summary>
    private static Result TransformLines(string text, int rangeStart, int rangeLength,
        Func<List<string>, List<string>> transform)
    {
        // Find the start and end line
        var lines = text.Split('\n');
        var lineStart = 0;
        var currentLineIndex = 0;

        for (int i = 0; i < lines.Length; i++)
        {
            var lineEnd = lineStart + lines[i].Length;
            if (rangeStart <= lineEnd)
            {
                currentLineIndex = i;
                break;
            }
            lineStart += lines[i].Length + 1;
        }

        var blockStart = lineStart;
        var selectedLines = new List<string>();
        var totalLength = 0;

        for (int i = currentLineIndex; i < lines.Length; i++)
        {
            selectedLines.Add(lines[i]);
            totalLength += lines[i].Length + (i < lines.Length - 1 ? 1 : 0);

            if (blockStart + totalLength >= rangeStart + rangeLength)
                break;
        }

        var hadTrailingNewline = selectedLines.Count > 0 && blockStart + totalLength - 1 < text.Length &&
                                 text[blockStart + totalLength - 1] == '\n';

        if (hadTrailingNewline && selectedLines.Count > 0)
        {
            selectedLines[selectedLines.Count - 1] = selectedLines[selectedLines.Count - 1].TrimEnd('\n');
        }

        var newLines = transform(selectedLines);
        if (hadTrailingNewline)
        {
            if (newLines.Count > 0)
            {
                newLines[newLines.Count - 1] += "\n";
            }
        }

        var newBlock = string.Join('\n', newLines);
        var blockEnd = blockStart + totalLength;

        var newText = text.Substring(0, blockStart) + newBlock + text.Substring(blockEnd);
        return new Result(newText, blockStart, newBlock.Length);
    }
}
