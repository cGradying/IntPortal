using Xunit;

namespace PUPSISPortal.Core.Tests;

public class UpdateCheckTests
{
    // MARK: IsNewer — pure version compare

    [Theory]
    [InlineData("1.1.2", "1.1.1", true)]   // patch bump
    [InlineData("1.2.0", "1.1.9", true)]   // minor bump beats a higher patch
    [InlineData("2.0.0", "1.9.9", true)]   // major bump
    [InlineData("1.1.1", "1.1.1", false)]  // identical
    [InlineData("1.1.0", "1.1.1", false)]  // older
    [InlineData("1.1.1", "1.1.2", false)]  // older patch
    public void IsNewer_ComparesThreePartVersions(string latest, string current, bool expected)
    {
        Assert.Equal(expected, UpdateChecker.IsNewer(latest, current));
    }

    [Fact]
    public void IsNewer_HandlesFourPartCsprojStyleVersions()
    {
        // The csproj <Version> is 4-part ("1.1.2.0"); release tags are 3-part.
        Assert.True(UpdateChecker.IsNewer("1.1.3", "1.1.2.0"));
        Assert.False(UpdateChecker.IsNewer("1.1.2", "1.1.2.0"));
    }

    [Fact]
    public void IsNewer_LeadingVIsStripped()
    {
        Assert.True(UpdateChecker.IsNewer("v1.1.2", "v1.1.1"));
    }

    [Fact]
    public void IsNewer_MissingSegmentsReadAsZero()
    {
        Assert.True(UpdateChecker.IsNewer("1.2", "1.1.9"));
        Assert.False(UpdateChecker.IsNewer("1.1", "1.1.0"));
    }

    [Fact]
    public void IsNewer_NonNumericSegmentFailsClosedRatherThanThrowing()
    {
        Assert.False(UpdateChecker.IsNewer("1.1.rc1", "1.1.0"));
    }

    // MARK: CheckAsync — injected fetch, no network

    [Fact]
    public async Task CheckAsync_ReturnsUpdateInfo_WhenLatestIsNewer()
    {
        var checker = new UpdateChecker(() => Task.FromResult(
            """{"tag_name":"v1.2.0","html_url":"https://github.com/cGradying/IntPortal/releases/tag/v1.2.0"}"""));

        var result = await checker.CheckAsync("1.1.2");

        Assert.NotNull(result);
        Assert.Equal("1.2.0", result!.Version);
        Assert.Equal("https://github.com/cGradying/IntPortal/releases/tag/v1.2.0", result.Url);
    }

    [Fact]
    public async Task CheckAsync_ReturnsNull_WhenCurrentIsUpToDate()
    {
        var checker = new UpdateChecker(() => Task.FromResult(
            """{"tag_name":"v1.1.2","html_url":"https://example.com"}"""));

        Assert.Null(await checker.CheckAsync("1.1.2"));
    }

    [Fact]
    public async Task CheckAsync_ReturnsNull_OnNetworkFailure()
    {
        var checker = new UpdateChecker(() => throw new HttpRequestException("offline"));

        Assert.Null(await checker.CheckAsync("1.1.2"));
    }

    [Fact]
    public async Task CheckAsync_ReturnsNull_OnMalformedJson()
    {
        var checker = new UpdateChecker(() => Task.FromResult("not json"));

        Assert.Null(await checker.CheckAsync("1.1.2"));
    }

    [Fact]
    public async Task CheckAsync_ReturnsNull_WhenTagNameMissing()
    {
        var checker = new UpdateChecker(() => Task.FromResult("""{"html_url":"https://example.com"}"""));

        Assert.Null(await checker.CheckAsync("1.1.2"));
    }
}
