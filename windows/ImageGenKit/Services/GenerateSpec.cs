namespace ImageGenKit.Services;

/// Which options each provider type supports (mirrors the Mac app and cli/imagegenkit.py).
public static class GenerateSpec
{
    public const string Auto = "Auto";

    public static string[] Aspects(string type) => type switch
    {
        "openrouter" or "gemini" => [Auto, "1:1", "3:2", "2:3", "4:3", "3:4", "4:5", "5:4", "16:9", "9:16", "21:9"],
        "grok-build" => [Auto, "1:1", "16:9", "9:16", "3:2", "2:3"],
        "codex-cli" => [Auto, "1:1", "3:2", "2:3"],
        "xai" => [Auto, "1:1", "3:4", "4:3", "9:16", "16:9", "2:3", "3:2", "1:2", "2:1"],
        _ => [Auto, "1:1", "3:2", "2:3", "4:3", "3:4", "16:9", "9:16"],
    };

    public static string[] Sizes(string type) => type switch
    {
        "grok-build" or "codex-cli" => [],
        "xai" => ["1K", "2K"],
        "local" => ["0.5K", "1K", "2K"],
        _ => ["1K", "2K", "4K"],
    };

    public static string[] Qualities(string type) => type switch
    {
        "openai" or "openrouter" or "codex-cli" => ["auto", "low", "medium", "high"],
        _ => [],
    };

    public static string[] Backgrounds(string type) => type switch
    {
        "openai" => ["auto", "opaque", "transparent"],
        "codex-cli" => ["auto", "transparent"],
        _ => [],
    };

    public static string[] Formats(string type) => type switch
    {
        "openai" or "openrouter" => ["png", "jpeg", "webp"],
        "together" or "fal" or "local" => ["png", "jpeg"],
        _ => [],
    };

    public static string FormatLabel(string f) => f switch { "jpeg" => "JPEG", "webp" => "WebP", _ => f.ToUpperInvariant() };

    public static string Cap(string s) => s.Length == 0 ? s : char.ToUpperInvariant(s[0]) + s[1..];

    /// Progress of a run from the command's lines ("loading the model", "step 3/8 (image 1 of 2)", "decoding").
    public static (string Text, double? Fraction)? Progress(string line, int images)
    {
        var t = line.Trim();
        if (t == "loading the model") return ("Loading model", null);
        if (t == "decoding") return ("Finishing", 1);
        var m = System.Text.RegularExpressions.Regex.Match(t, @"^step (\d+)/(\d+)(?: \(image (\d+) of (\d+)\))?");
        if (!m.Success) return null;
        int step = int.Parse(m.Groups[1].Value), total = int.Parse(m.Groups[2].Value);
        int image = m.Groups[3].Success ? int.Parse(m.Groups[3].Value) : 1;
        int n = Math.Max(1, m.Groups[4].Success ? int.Parse(m.Groups[4].Value) : images);
        if (total <= 0) return null;
        string text = n > 1 ? $"Image {image} of {n} · Step {step} of {total}" : $"Step {step} of {total}";
        return (text, ((image - 1) * (double)total + step) / (n * (double)total));
    }
}
