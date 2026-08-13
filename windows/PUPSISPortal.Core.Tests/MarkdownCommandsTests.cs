namespace PUPSISPortal.Core.Tests;

/// <summary>
/// The pure selection transforms behind the notes toolbar.
/// </summary>
public class MarkdownCommandsTests
{
    [Fact]
    public void TestWrapSelection()
    {
        var r = MarkdownCommands.Wrap("read chapter", 5, 7, "**");
        Assert.Equal("read **chapter**", r.Text);
        // Inner text stays selected.
        Assert.Equal(7, r.Start);
        Assert.Equal(7, r.Length);
    }

    [Fact]
    public void TestWrapEmptyDropsCursorBetweenMarkers()
    {
        var r = MarkdownCommands.Wrap("", 0, 0, "*");
        Assert.Equal("**", r.Text);
        Assert.Equal(1, r.Start);
        Assert.Equal(0, r.Length);
    }

    [Fact]
    public void TestToggleChecklistAddsThenRemoves()
    {
        var text = "buy milk\nwash car";
        var all = new { Start = 0, Length = text.Length };

        var added = MarkdownCommands.ToggleChecklist(text, all.Start, all.Length);
        Assert.Equal("- [ ] buy milk\n- [ ] wash car", added.Text);

        var cleared = MarkdownCommands.ToggleChecklist(added.Text, added.Start, added.Length);
        Assert.Equal("buy milk\nwash car", cleared.Text);
    }

    [Fact]
    public void TestToggleNumberedIncrements()
    {
        var text = "one\ntwo\nthree";
        var all = new { Start = 0, Length = text.Length };
        var r = MarkdownCommands.ToggleNumbered(text, all.Start, all.Length);
        Assert.Equal("1. one\n2. two\n3. three", r.Text);
    }

    [Fact]
    public void TestCycleHeadingRoundTrip()
    {
        var r = MarkdownCommands.CycleHeading("Title", 0, 0);
        Assert.Equal("# Title", r.Text);

        r = MarkdownCommands.CycleHeading(r.Text, 0, 0);
        Assert.Equal("## Title", r.Text);

        // Past H6 it clears back to plain text.
        r = MarkdownCommands.CycleHeading("###### Title", 0, 0);
        Assert.Equal("Title", r.Text);
    }

    [Fact]
    public void TestToggleCheckboxFlipsBothWays()
    {
        Assert.Equal("- [x] task", MarkdownCommands.ToggleCheckbox("- [ ] task"));
        Assert.Equal("- [ ] task", MarkdownCommands.ToggleCheckbox("- [x] task"));
        Assert.Equal("  - [ ] indented", MarkdownCommands.ToggleCheckbox("  - [X] indented"));
    }

    /// <summary>
    /// Detection underpins the source round-trip: collapsing these to attachments
    /// and reconstructing must reproduce the exact input, so notes never corrupt.
    /// </summary>
    [Fact]
    public void TestMathDetectionRoundTrips()
    {
        var text = "Energy $E=mc^2$ and a block:\n$$\\int_0^1 x\\,dx$$\nprice $5 and $10 stays text.";
        var matches = MarkdownCommands.MathMatches(text);

        // Two math spans; the currency "$5 and $10" is not one of them.
        Assert.Equal(2, matches.Count);

        Assert.Equal("E=mc^2", matches[0].Latex);
        Assert.False(matches[0].Display);

        Assert.Equal("\\int_0^1 x\\,dx", matches[1].Latex);
        Assert.True(matches[1].Display);

        // Reconstruct source from the matches — must equal the original.
        var out_ = "";
        var cursor = 0;
        foreach (var m in matches)
        {
            out_ += text.Substring(cursor, m.Start - cursor);
            out_ += m.Display ? $"$${m.Latex}$$" : $"${m.Latex}$";
            cursor = m.Start + m.Length;
        }
        out_ += text.Substring(cursor);

        Assert.Equal(text, out_);
    }

    [Fact]
    public void TestColorWrapsSelection()
    {
        var r = MarkdownCommands.Color("hi", 0, 2, "e5484d");
        Assert.Equal("{#e5484d:hi}", r.Text);
        Assert.Equal(9, r.Start);
        Assert.Equal(2, r.Length);
    }

    [Fact]
    public void TestColorEmptyDropsCursorInside()
    {
        var r = MarkdownCommands.Color("", 0, 0, "2f9e44");
        Assert.Equal("{#2f9e44:}", r.Text);
        Assert.Equal(9, r.Start);
        Assert.Equal(0, r.Length);
    }

    [Fact]
    public void TestLinkPlacesCursorOnPlaceholder()
    {
        var r = MarkdownCommands.Link("docs", 0, 4);
        Assert.Equal("[docs](url)", r.Text);
        Assert.Equal(7, r.Start);
        Assert.Equal(3, r.Length);
    }
}
