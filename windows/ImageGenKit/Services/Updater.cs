using System.Diagnostics;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;

namespace ImageGenKit.Services;

/// Updates from GitHub releases: the ImageGenKit-Setup-x.y.z.exe asset, checked against the SHA-256 digest GitHub
/// reports for it, installed silently; the installer opens the app again afterwards.
public sealed class Updater
{
    public static Updater Shared { get; } = new();
    const string Api = "https://api.github.com/repos/davidkrammer/imagegenkit/releases/latest";

    public enum Phase { Idle, Checking, UpToDate, Available, Downloading, Failed }

    public Phase State { get; private set; } = Phase.Idle;
    public string? Latest { get; private set; }
    public string? Error { get; private set; }
    string? assetUrl, assetDigest, releasePage;
    public event Action? Changed;

    public static string Current
    {
        get
        {
            var v = typeof(Updater).Assembly.GetName().Version;
            return v is null ? "0" : $"{v.Major}.{v.Minor}.{v.Build}";
        }
    }

    public async Task CheckAsync(bool quiet = false)
    {
        if (!quiet) Set(Phase.Checking);
        try
        {
            using var http = new HttpClient();
            http.DefaultRequestHeaders.UserAgent.ParseAdd("ImageGenKit-Windows");
            http.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
            using var doc = JsonDocument.Parse(await http.GetStringAsync(Api));
            var r = doc.RootElement;
            Latest = r.Str("tag_name").TrimStart('v', 'V');
            releasePage = r.Str("html_url");
            var asset = r.Arr("assets").FirstOrDefault(a => a.Str("name").StartsWith("ImageGenKit-Setup-") && a.Str("name").EndsWith(".exe"));
            assetUrl = asset.ValueKind == JsonValueKind.Object ? asset.Str("browser_download_url") : null;
            assetDigest = asset.ValueKind == JsonValueKind.Object ? asset.Str("digest") : null;
            Set(Compare(Latest, Current) > 0 && assetUrl is not null ? Phase.Available : quiet ? Phase.Idle : Phase.UpToDate);
        }
        catch (Exception ex)
        {
            Error = "Couldn't reach GitHub";
            Log.Write("update check: " + ex.Message);
            Set(quiet ? Phase.Idle : Phase.Failed);
        }
    }

    public async Task InstallAsync()
    {
        if (assetUrl is null) return;
        Set(Phase.Downloading);
        try
        {
            var file = Path.Combine(Path.GetTempPath(), $"ImageGenKit-Setup-{Latest}.exe");
            using (var http = new HttpClient { Timeout = TimeSpan.FromMinutes(10) })
            {
                http.DefaultRequestHeaders.UserAgent.ParseAdd("ImageGenKit-Windows");
                await File.WriteAllBytesAsync(file, await http.GetByteArrayAsync(assetUrl));
            }
            if (assetDigest is { Length: > 0 } digest && digest.StartsWith("sha256:"))
            {
                await using var fs = File.OpenRead(file);
                var hash = Convert.ToHexStringLower(await SHA256.HashDataAsync(fs));
                if (hash != digest["sha256:".Length..]) throw new InvalidOperationException("The download is damaged (checksum mismatch).");
            }
            Process.Start(new ProcessStartInfo(file, "/SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS") { UseShellExecute = true });
            App.Window?.DispatcherQueue.TryEnqueue(() => App.Window?.Close());
        }
        catch (Exception ex)
        {
            Error = ex.Message;
            Log.Write("update: " + ex);
            Set(Phase.Failed);
        }
    }

    public void OpenReleasePage()
    {
        if (releasePage is { Length: > 0 }) Process.Start(new ProcessStartInfo(releasePage) { UseShellExecute = true });
    }

    void Set(Phase p)
    {
        State = p;
        Changed?.Invoke();
    }

    public static int Compare(string a, string b)
    {
        int[] P(string v) => v.Split('.', '-').Select(x => int.TryParse(x, out var n) ? n : 0).ToArray();
        var x = P(a); var y = P(b);
        for (int i = 0; i < Math.Max(x.Length, y.Length); i++)
        {
            int l = i < x.Length ? x[i] : 0, r = i < y.Length ? y[i] : 0;
            if (l != r) return l.CompareTo(r);
        }
        return 0;
    }
}
