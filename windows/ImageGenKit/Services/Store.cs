using System.Text.Json;

namespace ImageGenKit.Services;

/// What the app shows: backend state, the log, and the filters in the title bar. Pages redraw on Changed.
public sealed class Store
{
    public static Store Shared { get; } = new();

    public JsonElement State { get; private set; }
    public List<LogItem> Log { get; private set; } = [];
    public List<ProviderRow> Providers { get; private set; } = [];
    public Dictionary<string, string> Labels { get; private set; } = [];
    public bool Loaded { get; private set; }
    public string? Error { get; private set; }

    public string ProviderFilter { get; set; } = "";
    public int RangeDays { get; set; } = 30;
    public string Search { get; set; } = "";
    public LogItem? Selected { get; set; }

    public event Action? Changed;

    public string Device => State.Str("device", "this PC") is var d && d.Length > 0 ? d : "this PC";
    public int ReadyCount => Providers.Count(p => p.Ready && Enabled.Contains(p.Name));

    /// Providers the user uses, in order (config "order"), else every ready one.
    public List<string> Enabled
    {
        get
        {
            var order = State.Strings("order").Where(s => s is not null).Select(s => s!).ToList();
            return order.Count > 0 ? order.Where(o => Providers.Any(p => p.Name == o)).ToList()
                : Providers.Where(p => p.Ready).Select(p => p.Name).ToList();
        }
    }

    public async Task LoadAsync()
    {
        try
        {
            var stateTask = Backend.Shared.GetAsync("/api/state");
            var logTask = Backend.Shared.GetAsync("/api/log?limit=0");
            await Task.WhenAll(stateTask, logTask);
            Apply(stateTask.Result);
            Log = logTask.Result.ValueKind == JsonValueKind.Array
                ? logTask.Result.EnumerateArray().Select(LogItem.From).OrderByDescending(e => e.Date).ToList() : [];
            Error = null;
        }
        catch (Exception ex)
        {
            Error = ex.Message;
            Services.Log.Write("load: " + ex);
        }
        Loaded = true;
        Changed?.Invoke();
    }

    public void Apply(JsonElement state)
    {
        State = state;
        Providers = state.Arr("providers").Select(ProviderRow.From).ToList();
        Labels = Providers.ToDictionary(p => p.Name, p => p.Label);
        ProviderStyle.CustomOrder = Providers.Where(p => !p.Builtin && !p.IsLocal).Select(p => p.Name).ToList();
    }

    public async Task ReloadStateAsync()
    {
        try { Apply(await Backend.Shared.GetAsync("/api/state")); } catch (Exception ex) { Error = ex.Message; }
        Changed?.Invoke();
    }

    public string Label(string id) => ProviderStyle.Label(id, Labels);

    /// Runs in the time range and provider filter (and the search, when given).
    public IEnumerable<LogItem> Filtered(bool search = false)
    {
        var since = RangeDays > 0 ? DateTime.Today.AddDays(-(RangeDays - 1)) : DateTime.MinValue;
        var q = Search.Trim();
        return Log.Where(e => e.Date >= since
                              && (ProviderFilter.Length == 0 || e.Provider == ProviderFilter)
                              && (!search || q.Length == 0 || e.Prompt.Contains(q, StringComparison.CurrentCultureIgnoreCase)
                                  || e.Model.Contains(q, StringComparison.CurrentCultureIgnoreCase)));
    }

    public void NotifyChanged() => Changed?.Invoke();
}
