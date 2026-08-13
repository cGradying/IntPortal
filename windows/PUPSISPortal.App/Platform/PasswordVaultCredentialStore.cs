using System.Text.Json;
using Windows.Security.Credentials;
using PUPSISPortal.Core;

namespace PUPSISPortal.App.Platform;

/// <summary>
/// Credentials in the Windows Credential Manager via <c>PasswordVault</c> — the
/// Windows counterpart of the macOS Keychain store. Resource name is kept
/// distinct from PUPSIS's so both apps can coexist.
///
/// PasswordVault stores a resource/username/password triple, so the full
/// <see cref="Credentials"/> record is packed as JSON into the password field.
/// Never written to disk, a log, or a commit.
/// </summary>
public static class PasswordVaultCredentialStore
{
    private const string Resource = "ph.edu.pup.sis8.portal";
    private const string UserName = "student";

    public static void Save(Credentials credentials)
    {
        Delete();
        var json = JsonSerializer.Serialize(credentials);
        new PasswordVault().Add(new PasswordCredential(Resource, UserName, json));
    }

    public static Credentials? Load()
    {
        try
        {
            var cred = new PasswordVault().Retrieve(Resource, UserName);
            cred.RetrievePassword();
            return JsonSerializer.Deserialize<Credentials>(cred.Password);
        }
        catch
        {
            return null; // nothing stored, or the entry was removed
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
            // FindAllByResource throws when nothing matches — that's fine.
        }
    }
}
