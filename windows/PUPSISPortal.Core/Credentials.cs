namespace PUPSISPortal.Core;

/// <summary>
/// Student login credentials for the SIS.
/// </summary>
public record Credentials
{
    public required string StudentNumber { get; set; }
    public required int BirthMonth { get; set; }
    public required int BirthDay { get; set; }
    public required int BirthYear { get; set; }
    public required string Password { get; set; }
}
