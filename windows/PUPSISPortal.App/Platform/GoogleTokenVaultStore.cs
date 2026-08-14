using Windows.Security.Credentials;

namespace PUPSISPortal.App.Platform;

/// <summary>
/// The Google OAuth refresh token, in the Windows Credential Manager — the
/// counterpart of macOS's GoogleTokenStore (Keychain). Own resource name, same
/// service prefix as <see cref="PasswordVaultCredentialStore"/> so both live
/// side by side and each can be cleared independently.
///
/// The refresh token is the sensitive part — it mints access tokens — so it
/// never touches disk, a log, or a settings file. The client ID isn't secret
/// and lives in <see cref="PUPSISPortal.Core.Preferences"/>.
/// </summary>
public static class GoogleTokenVaultStore
{
    private const string Resource = "ph.edu.pup.sis8.portal.google";
    private const string UserName = "google-refresh";

    public static void Save(string refreshToken)
    {
        Delete();
        new PasswordVault().Add(new PasswordCredential(Resource, UserName, refreshToken));
    }

    public static string? Load()
    {
        try
        {
            var cred = new PasswordVault().Retrieve(Resource, UserName);
            cred.RetrievePassword();
            return cred.Password;
        }
        catch
        {
            return null;
        }
    }

    public static void Delete()
    {
        try
        {
            var vault = new PasswordVault();
            foreach (var c in vault.FindAllByResource(Resource))
                vault.Remove(c);
        }
        catch
        {
            // Nothing stored — fine.
        }
    }
}
