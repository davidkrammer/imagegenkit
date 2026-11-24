using System.Text.Json;
using System.Text.Json.Nodes;

namespace ImageGenKit.Services;

/// The app's own small settings (accepted terms, seen tour) in %APPDATA%\ImageGenKit\prefs.json.
/// Read through the APPDATA variable, so a demo profile (screenshots) gets its own.
public static class AppPrefs
{
    static readonly string File = Path.Combine(
        Environment.GetEnvironmentVariable("APPDATA") is { Length: > 0 } appData ? appData : Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "ImageGenKit", "prefs.json");

    static JsonObject? data;

    static JsonObject Data
    {
        get
        {
            if (data is not null) return data;
            try { data = JsonNode.Parse(System.IO.File.ReadAllText(File)) as JsonObject; }
            catch (Exception) { }
            return data ??= new JsonObject();
        }
    }

    public static int Int(string key) => Data[key] is JsonValue v && v.TryGetValue(out int n) ? n : 0;

    public static string? Str(string key) => Data[key] is JsonValue v && v.TryGetValue(out string? s) ? s : null;

    public static void Set(string key, JsonNode? value)
    {
        Data[key] = value;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(File)!);
            System.IO.File.WriteAllText(File, Data.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception ex) { Log.Write("prefs: " + ex.Message); }
    }
}

/// The terms of use, accepted once before the app can be used. Raise `Version` (and the version on the website)
/// when they change in a way that matters: the consent screen then shows again.
public static class Terms
{
    public const int Version = 1;
    public const string Url = "https://strics.at/imagegenkit/terms";
    public const string PrivacyUrl = "https://strics.at/privacy";

    public static bool Accepted => AppPrefs.Int("termsVersion") >= Version;

    public static void Accept()
    {
        AppPrefs.Set("termsVersion", Version);
        AppPrefs.Set("termsAcceptedAt", DateTimeOffset.Now.ToString("o"));
    }
}
