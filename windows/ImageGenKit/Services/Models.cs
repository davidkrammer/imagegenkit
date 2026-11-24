using System.Globalization;
using System.Text.Json;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace ImageGenKit.Services;

public static class Json
{
    public static string Str(this JsonElement e, string key, string fallback = "") =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() ?? fallback : fallback;

    public static double Num(this JsonElement e, string key, double fallback = 0)
    {
        if (e.ValueKind != JsonValueKind.Object || !e.TryGetProperty(key, out var v)) return fallback;
        return v.ValueKind == JsonValueKind.Number ? v.GetDouble() : fallback;
    }

    public static bool Bool(this JsonElement e, string key, bool fallback = false) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(key, out var v) && v.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? v.GetBoolean() : fallback;

    public static JsonElement Obj(this JsonElement e, string key) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(key, out var v) ? v : default;

    public static IEnumerable<JsonElement> Arr(this JsonElement e, string key) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.Array
            ? v.EnumerateArray() : Enumerable.Empty<JsonElement>();

    public static List<string?> Strings(this JsonElement e, string key) =>
        e.Arr(key).Select(x => x.ValueKind == JsonValueKind.String ? x.GetString() : null).ToList();

    /// A parameter value as text ("1024x1024", 42, true).
    public static string? Param(this JsonElement e, string key)
    {
        var p = e.Obj("params");
        if (p.ValueKind != JsonValueKind.Object || !p.TryGetProperty(key, out var v)) return null;
        return v.ValueKind switch
        {
            JsonValueKind.String => v.GetString(),
            JsonValueKind.Number => v.GetRawText(),
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            _ => null,
        };
    }
}

/// One run from ~/.config/imagegenkit/log.jsonl (as the backend serves it, with its estimated cost).
public sealed class LogItem
{
    public int Id { get; init; }
    public DateTime Date { get; init; }
    public string Provider { get; init; } = "";
    public string Type { get; init; } = "";
    public string Model { get; init; } = "";
    public string Task { get; init; } = "";
    public string Prompt { get; init; } = "";
    public string Project { get; init; } = "";
    public string Who { get; init; } = "";
    public List<string> Outputs { get; init; } = [];
    public List<string?> Thumbs { get; init; } = [];
    public List<string> Refs { get; init; } = [];
    public List<bool> Exists { get; init; } = [];
    public double Cost { get; init; }
    public double Seconds { get; init; }
    public string Size { get; init; } = "";
    public JsonElement Raw { get; init; }

    public bool IsLocal => Type == "local";
    public bool IsSubscription => Type is "grok-build" or "codex-cli" || Provider == "grok";
    public bool Free => IsLocal || IsSubscription;
    public int ImageCount => Outputs.Count;
    public string KindLabel => Refs.Count > 0 ? "Edit" : "Generate";
    public string CostLabel => IsLocal ? "Free" : IsSubscription ? "Plan" : Format.Money(Cost);

    /// The best picture to show for output i: the file if it still exists, else its 512 px thumbnail.
    public string? Picture(int i, bool preferThumb = true)
    {
        string? thumb = i < Thumbs.Count ? Thumbs[i] : null;
        string? output = i < Outputs.Count ? Outputs[i] : null;
        bool outputThere = output is not null && (i < Exists.Count ? Exists[i] : File.Exists(output));
        if (preferThumb && thumb is not null && File.Exists(thumb)) return thumb;
        if (outputThere) return output;
        return thumb is not null && File.Exists(thumb) ? thumb : null;
    }

    public static LogItem From(JsonElement e)
    {
        DateTime.TryParse(e.Str("ts"), CultureInfo.InvariantCulture, DateTimeStyles.AssumeLocal, out var ts);
        var cwd = e.Str("cwd");
        var caller = e.Obj("caller");
        string who = caller.ValueKind == JsonValueKind.Object ? caller.Str("agent") : "";
        who = who switch { "claude" => "Claude Code", "codex" => "Codex", "" => "You", _ => who };
        var size = e.Param("size") ?? e.Param("aspect") ?? "auto";
        return new LogItem
        {
            Id = (int)e.Num("_id"),
            Date = ts,
            Provider = e.Str("provider"),
            Type = e.Str("type", e.Str("provider")),
            Model = e.Str("model"),
            Task = e.Str("task"),
            Prompt = e.Str("prompt"),
            Project = string.IsNullOrEmpty(cwd) ? "Unknown" : ProjectName(cwd),
            Who = who,
            Outputs = e.Strings("outputs").Where(s => s is not null).Select(s => s!).ToList(),
            Thumbs = e.Strings("thumbs"),
            Refs = e.Strings("refs").Where(s => s is not null).Select(s => s!).ToList(),
            Exists = e.Arr("exists").Select(x => x.ValueKind == JsonValueKind.True).ToList(),
            Cost = e.Num("cost"),
            Seconds = e.Num("seconds"),
            Size = size == "null" ? "auto" : size.Replace("x", "×"),
            Raw = e,
        };
    }

    static string ProjectName(string cwd)
    {
        var trimmed = cwd.TrimEnd('/', '\\');
        var name = trimmed.Split('/', '\\').LastOrDefault() ?? "";
        if (name is "scratchpad" or "tmp" or "Temp" || name.Length == 36 && name.Count(c => c == '-') == 4) return "Unknown";
        return string.IsNullOrEmpty(name) ? "Unknown" : name;
    }
}

/// A provider row from /api/state.
public sealed class ProviderRow
{
    public string Name { get; init; } = "";
    public string Label { get; init; } = "";
    public string Type { get; init; } = "";
    public bool Builtin { get; init; }
    public bool NeedsKey { get; init; }
    public bool Ready { get; init; }
    public string Status { get; init; } = "";
    public string? Tagline { get; init; }
    public string? PriceHint { get; init; }
    public string? KeyUrl { get; init; }
    public bool? Tested { get; init; }
    public bool Transparent { get; init; }
    public bool Edits { get; init; }
    public List<string> Models { get; init; } = [];
    public string? Model { get; init; }
    public JsonElement Raw { get; init; }

    public bool IsLocal => Type == "local";
    public bool IsSubscription => Type is "grok-build" or "codex-cli";

    public static ProviderRow From(JsonElement e) => new()
    {
        Name = e.Str("name"),
        Label = e.Str("label"),
        Type = e.Str("type"),
        Builtin = e.Bool("builtin"),
        NeedsKey = e.Bool("needs_key"),
        Ready = e.Bool("ready"),
        Status = e.Str("status"),
        Tagline = e.Str("tagline") is { Length: > 0 } t ? t : null,
        PriceHint = e.Str("price_hint") is { Length: > 0 } p ? p : null,
        KeyUrl = e.Str("key_url") is { Length: > 0 } k ? k : null,
        Tested = e.Obj("tested").ValueKind is JsonValueKind.True or JsonValueKind.False ? e.Bool("tested") : null,
        Transparent = e.Bool("transparent"),
        Edits = e.Bool("edits", true),
        Models = e.Strings("models").Where(s => s is not null).Select(s => s!).ToList(),
        Model = e.Str("model") is { Length: > 0 } m ? m : null,
        Raw = e,
    };
}

/// Fixed series colors per provider (the Mac app's palette), never by rank.
public static class ProviderStyle
{
    static readonly (uint Light, uint Dark)[] Slots =
    [
        (0x2A78D6, 0x3987E5), (0xEB6834, 0xD95926), (0x1BAF7A, 0x199E70), (0xEDA100, 0xC98500),
        (0xE87BA4, 0xD55181), (0x008300, 0x008300), (0x6250D6, 0x9085E9), (0xE34948, 0xE66767),
    ];

    public static List<string> CustomOrder { get; set; } = [];

    public static Color ColorOf(string id, bool dark)
    {
        int? index = id switch
        {
            "openai" => 0, "grok" => 1, "gemini" => 2, "xai" => 3, "codex" => 5, "local" => 6,
            _ => CustomOrder.IndexOf(id) is var i and >= 0 ? new[] { 4, 7 }[i % 2] : null,
        };
        if (index is null) return dark ? Color.FromArgb(255, 142, 142, 147) : Color.FromArgb(255, 99, 99, 102);
        uint rgb = dark ? Slots[index.Value].Dark : Slots[index.Value].Light;
        return Color.FromArgb(255, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);
    }

    public static SolidColorBrush Brush(string id) => new(ColorOf(id, IsDark));

    public static bool IsDark => App.Window?.Content is FrameworkElement f ? f.ActualTheme == ElementTheme.Dark
        : Application.Current.RequestedTheme == ApplicationTheme.Dark;

    /// Segoe Fluent Icons glyph per provider.
    public static string Glyph(string id, string type) => (type, id) switch
    {
        ("grok-build", _) or (_, "grok") => "",      // lightning
        ("codex-cli", _) or (_, "codex") => "",      // chat
        ("openai", _) => "",                          // star
        ("gemini", _) => "",                          // diamond-ish
        ("xai", _) => "",
        ("local", _) => "",                           // laptop
        _ => "",                                      // network
    };

    public static string Label(string id, IReadOnlyDictionary<string, string> labels) =>
        labels.TryGetValue(id, out var l) && !string.IsNullOrEmpty(l) ? l : id switch
        {
            "openai" => "OpenAI", "grok" => "Grok", "xai" => "xAI API", "gemini" => "Gemini", "codex" => "Codex",
            "local" => "On this PC",
            _ => id.Length > 0 ? char.ToUpperInvariant(id[0]) + id[1..] : id,
        };
}

public static class Format
{
    public static string Money(double usd) =>
        usd <= 0 ? "$0.00" : usd < 0.01 ? "< $0.01" : usd.ToString(usd < 100 ? "$0.00" : "$#,0", CultureInfo.InvariantCulture);

    public static string Count(int n) => n.ToString("#,0", CultureInfo.CurrentCulture);

    public static string Seconds(double s) => s < 1 ? "—" : s < 90 ? $"{Math.Round(s)} s" : $"{Math.Round(s / 60, 1)} min";

    public static string Day(DateTime d)
    {
        var today = DateTime.Today;
        if (d.Date == today) return "Today";
        if (d.Date == today.AddDays(-1)) return "Yesterday";
        return d.ToString(d.Year == today.Year ? "dddd, MMM d" : "MMM d, yyyy", CultureInfo.CurrentCulture);
    }

    public static string DateTimeShort(DateTime d) =>
        d.Date == DateTime.Today ? $"Today at {d:HH:mm}" : d.ToString("MMM d 'at' HH:mm", CultureInfo.CurrentCulture);

    public static string Bytes(double n) => n >= 1e9 ? $"{n / 1e9:0.0} GB" : $"{Math.Round(n / 1e6)} MB";

    public static string Compact(double n) => n >= 1e6 ? $"{n / 1e6:0.0}M" : n >= 1e3 ? $"{Math.Round(n / 1e3)}K" : $"{n}";
}
