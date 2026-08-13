namespace PUPSISPortal.Core.Tests;

/// <summary>
/// The line-based Markdown block splitter.
/// </summary>
public class MarkdownTests
{
    [Fact]
    public void TestHeadingLevels()
    {
        var result = Markdown.Parse("# Title");
        Assert.Single(result);
        Assert.Equal(MarkdownBlock.Heading(1, "Title"), result[0]);

        result = Markdown.Parse("### Deep");
        Assert.Single(result);
        Assert.Equal(MarkdownBlock.Heading(3, "Deep"), result[0]);
    }

    /// <summary>
    /// Seven hashes isn't a heading, and a hash with no space is just text.
    /// </summary>
    [Fact]
    public void TestNonHeadings()
    {
        var result = Markdown.Parse("####### too many");
        Assert.Single(result);
        Assert.Equal(MarkdownBlock.Paragraph("####### too many"), result[0]);

        result = Markdown.Parse("#nospace");
        Assert.Single(result);
        Assert.Equal(MarkdownBlock.Paragraph("#nospace"), result[0]);
    }

    [Fact]
    public void TestBullets()
    {
        var result = Markdown.Parse("- milk");
        Assert.Single(result);
        Assert.Equal(MarkdownBlock.Bullet("milk"), result[0]);

        result = Markdown.Parse("* eggs");
        Assert.Single(result);
        Assert.Equal(MarkdownBlock.Bullet("eggs"), result[0]);
    }

    [Fact]
    public void TestCheckboxes()
    {
        var result = Markdown.Parse("- [ ] todo");
        Assert.Single(result);
        Assert.Equal(MarkdownBlock.Checkbox(false, "todo"), result[0]);

        result = Markdown.Parse("- [x] done");
        Assert.Single(result);
        Assert.Equal(MarkdownBlock.Checkbox(true, "done"), result[0]);

        result = Markdown.Parse("- [X] done");
        Assert.Single(result);
        Assert.Equal(MarkdownBlock.Checkbox(true, "done"), result[0]);
    }

    [Fact]
    public void TestBlankLinesAndParagraphs()
    {
        var result = Markdown.Parse("hello\n\nworld");
        Assert.Equal(3, result.Count);
        Assert.Equal(MarkdownBlock.Paragraph("hello"), result[0]);
        Assert.Equal(MarkdownBlock.Blank, result[1]);
        Assert.Equal(MarkdownBlock.Paragraph("world"), result[2]);
    }

    [Fact]
    public void TestMixedDocument()
    {
        var doc = "# Chem\n- [ ] lab report\n- read ch. 4\nnote: **bold** stays inline";
        var result = Markdown.Parse(doc);

        Assert.Equal(4, result.Count);
        Assert.Equal(MarkdownBlock.Heading(1, "Chem"), result[0]);
        Assert.Equal(MarkdownBlock.Checkbox(false, "lab report"), result[1]);
        Assert.Equal(MarkdownBlock.Bullet("read ch. 4"), result[2]);
        Assert.Equal(MarkdownBlock.Paragraph("note: **bold** stays inline"), result[3]);
    }
}
