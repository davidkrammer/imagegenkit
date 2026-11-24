using System.Diagnostics;
using System.Text.Json;
using CommunityToolkit.WinUI.Controls;
using ImageGenKit.Controls;
using ImageGenKit.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Storage.Pickers;

namespace ImageGenKit.Pages;

public sealed partial class SettingsPage : Page, IRefreshable
{
    string section = "providers";
    JsonElement local;                 // /api/local
    List<JsonElement> searchResults = [];
    string searchQuery = "";
    string? searchError;
    readonly Dictionary<string, (string JobId, double Done, double Total, string? Error)> downloads = [];
    string selectedExample = "";

    public SettingsPage()
    {
        InitializeComponent();
        section = App.Options.SettingsSection;
        Loaded += (_, _) =>
        {
            Sections.SelectedItem = Sections.Items.FirstOrDefault(i => (string)i.Tag == section) ?? Sections.Items[0];
            Refresh();
        };
    }

    protected override void OnNavigatedTo(Microsoft.UI.Xaml.Navigation.NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        if (e.Parameter is string { Length: > 0 } wanted) section = wanted; // the tour opens a section
    }

    void Sections_SelectionChanged(SelectorBar sender, SelectorBarSelectionChangedEventArgs args)
    {
        section = (string)(sender.SelectedItem?.Tag ?? "providers");
        Refresh();
        if (section == "local") _ = LoadLocal();
    }

    public void Refresh()
    {
        Body.Children.Clear();
        var s = Store.Shared;
        if (!s.Loaded) { Body.Children.Add(new ProgressRing { IsActive = true, Margin = new Thickness(0, 60, 0, 0) }); return; }
        switch (section)
        {
            case "use": UseFor(); break;
            case "local": Local(); break;
            case "limits": Limits(); break;
            case "agents": Agents(); break;
            case "general": General(); break;
            default: Providers(); break;
        }
    }

    // ---------- shared pieces ----------

    /// A sub-heading inside a section.
    void Heading(string title)
    {
        var t = Ui.Text(title, 15, bold: true);
        t.Margin = new Thickness(2, 18, 0, 6);
        Body.Children.Add(t);
    }

    /// The line under the section tabs: what this section is for, and its main button.
    void Intro(string lead, UIElement? trailing = null)
    {
        var text = Ui.Muted(lead, 13);
        text.VerticalAlignment = VerticalAlignment.Center;
        text.TextWrapping = TextWrapping.Wrap;
        text.TextTrimming = TextTrimming.None;
        var row = trailing is null ? (FrameworkElement)text : Ui.Columns((text, Ui.Star()), (trailing, Ui.Auto));
        row.Margin = new Thickness(2, 10, 0, 10);
        Body.Children.Add(row);
    }

    static SettingsCard Card(string header, string? description, IconElement? icon, object? content = null) => new()
    {
        Header = header, Description = description, HeaderIcon = icon, Content = content,
    };

    static IconElement Glyph(string glyph, Windows.UI.Color? color = null)
    {
        var i = new FontIcon { Glyph = glyph };
        if (color is { } c) i.Foreground = new SolidColorBrush(c);
        return i;
    }

    static async Task<bool> Confirm(string title, string message, string action)
    {
        var dialog = new ContentDialog
        {
            Title = title, Content = message, PrimaryButtonText = action, CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close, XamlRoot = App.Window!.Content.XamlRoot,
            PrimaryButtonStyle = DangerButton(),
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    static Style DangerButton()
    {
        var style = new Style(typeof(Button)) { BasedOn = Ui.Res<Style>("DefaultButtonStyle") };
        style.Setters.Add(new Setter(Control.BackgroundProperty, new SolidColorBrush(Ui.Hex(0xD92D20))));
        style.Setters.Add(new Setter(Control.ForegroundProperty, new SolidColorBrush(Microsoft.UI.Colors.White)));
        return style;
    }

    async Task Run(Func<Task> action)
    {
        try { await action(); }
        catch (Exception ex) { App.Window?.ShowError("Something went wrong", ex.Message); }
    }

    static Task SetConfig(Dictionary<string, object?> set, IEnumerable<string>? unset = null) => ProviderSetup.SetConfig(set, unset);

    // ---------- Providers ----------

    void Providers()
    {
        var s = Store.Shared;
        var add = Ui.LabelButton("", "Add Provider", async (_, _) => await AddProvider());
        Intro("Where your images come from. The top one is used first.", add);
        var enabled = s.Enabled;
        if (enabled.Count == 0)
        {
            var go = Ui.LabelButton("", "Add Provider", async (_, _) => await AddProvider(), accent: true);
            Body.Children.Add(Ui.Card(Ui.Columns(
                (Ui.Column(3, Ui.Text("Connect a provider", 15, bold: true), Ui.Muted("Your subscription, an API key, or free models on this PC.")), Ui.Star()),
                (go, Ui.Auto))));
            return;
        }
        for (int i = 0; i < enabled.Count; i++)
        {
            var p = s.Providers.First(x => x.Name == enabled[i]);
            Body.Children.Add(ProviderCard(p, i, enabled));
        }
    }

    SettingsCard ProviderCard(ProviderRow p, int index, List<string> enabled)
    {
        var color = ProviderStyle.ColorOf(p.Name, ProviderStyle.IsDark);
        string description = p.Ready
            ? p.IsLocal ? $"Free · {p.Status}" : p.IsSubscription ? "Subscription · Logged in" : $"API key · {p.Status}"
            : Cap(p.Status);
        var right = Ui.Row(8);
        if (p.Tested == false) right.Children.Add(Ui.Pill("Untested"));
        if (p.Ready)
        {
            var ready = Ui.Pill("Ready", Ui.Hex(0x34C759));
            ready.VerticalAlignment = VerticalAlignment.Center;
            right.Children.Add(ready);
        }
        else if (p.IsLocal) right.Children.Add(Ui.LabelButton("", "Download Model", (_, _) => Select("local"), accent: true));
        else if (p.NeedsKey) right.Children.Add(Ui.LabelButton("", "Add Key", async (_, _) => await KeyDialog(p), accent: true));
        else right.Children.Add(Ui.LabelButton("", p.Status.Contains("install", StringComparison.OrdinalIgnoreCase) ? "Install" : "Log In",
            async (_, _) => await Terminal(p), accent: true));

        var menu = new MenuFlyout();
        void Item(string text, string glyph, Func<Task> act, bool danger = false)
        {
            var item = new MenuFlyoutItem { Text = text, Icon = Glyph(glyph) };
            if (danger) { item.Foreground = new SolidColorBrush(Ui.Hex(0xD92D20)); item.Icon = Glyph(glyph, Ui.Hex(0xD92D20)); }
            item.Click += async (_, _) => await Run(act);
            menu.Items.Add(item);
        }
        Item("Test", "", () => Test(p));
        if (index > 0) Item("Move Up", "", () => Move(enabled, index, -1));
        if (index < enabled.Count - 1) Item("Move Down", "", () => Move(enabled, index, 1));
        if (p.NeedsKey) Item("Change Key…", "", () => KeyDialog(p));
        if (p.IsSubscription) Item("Log In Again", "", () => Terminal(p, login: true));
        if (p.IsLocal) Item("Manage Models…", "", () => { Select("local"); return Task.CompletedTask; });
        if (p.KeyUrl is { } url) Item(p.NeedsKey ? "Get Key Page" : "Open Website", "", () => { OpenUrl(url); return Task.CompletedTask; });
        menu.Items.Add(new MenuFlyoutSeparator());
        Item("Remove", "", () => Remove(p, enabled), danger: true);
        var more = new Button { Content = Ui.Icon("", 14), Padding = new Thickness(10, 7, 10, 7), Flyout = menu };
        ToolTipService.SetToolTip(more, "More");
        right.Children.Add(more);

        var card = Card(p.Label, description, Glyph(ProviderStyle.Glyph(p.Name, p.Type), color), right);
        if (!p.Ready && p.Status.Length > 0 && !p.Status.StartsWith("no", StringComparison.OrdinalIgnoreCase) && !p.Status.StartsWith("not", StringComparison.OrdinalIgnoreCase))
            card.Description = Cap(p.Status);
        return card;
    }

    static string Cap(string s) => s.Length == 0 ? s : char.ToUpperInvariant(s[0]) + s[1..];

    void Select(string name)
    {
        Sections.SelectedItem = Sections.Items.First(i => (string)i.Tag == name);
    }

    async Task Move(List<string> enabled, int index, int delta)
    {
        var order = enabled.ToList();
        (order[index], order[index + delta]) = (order[index + delta], order[index]);
        await SetConfig(new() { ["order"] = order });
    }

    async Task Test(ProviderRow p)
    {
        var rows = await Backend.Shared.PostAsync("/api/check", new { provider = p.Name });
        var r = rows.ValueKind == JsonValueKind.Array ? rows.EnumerateArray().FirstOrDefault() : default;
        var ok = r.Str("status") == "ok";
        await new ContentDialog
        {
            Title = ok ? $"{p.Label} works" : $"{p.Label} isn't ready",
            Content = Cap(r.Str("message", "No answer")),
            CloseButtonText = "OK", XamlRoot = XamlRoot,
        }.ShowAsync();
        await Store.Shared.ReloadStateAsync();
    }

    async Task Remove(ProviderRow p, List<string> enabled)
    {
        string message = p.NeedsKey ? $"Its API key is deleted from the Credential Manager."
            : p.IsLocal ? "It won't be used for images anymore. Downloaded models stay until you remove them."
            : "It won't be used for images anymore.";
        if (!await Confirm($"Remove {p.Label}?", message, "Remove")) return;
        await SetConfig(new() { ["order"] = enabled.Where(n => n != p.Name).ToList() });
        if (p.NeedsKey) await Backend.Shared.PostAsync("/api/key/delete", new { provider = p.Name });
        await Store.Shared.ReloadStateAsync();
    }

    Task Terminal(ProviderRow p, bool login = false) => ProviderSetup.Terminal(p, XamlRoot, login);

    Task KeyDialog(ProviderRow p) => ProviderSetup.KeyDialog(p, XamlRoot);

    Task AddProvider() => ProviderSetup.AddProviderDialog(XamlRoot, () => Select("local"));

    // ---------- Use for ----------

    void UseFor()
    {
        var s = Store.Shared;
        Intro("Which provider makes what. If it isn't ready, the next one in your list is used.");
        var tasks = s.State.Obj("tasks");
        var info = s.State.Obj("task_info");
        var enabled = s.Enabled.Select(n => s.Providers.First(p => p.Name == n)).ToList();
        foreach (var (task, glyph) in new[] { ("draft", ""), ("final", ""), ("edit", ""), ("transparent", "") })
        {
            var options = task == "transparent" ? enabled.Where(p => p.Transparent).ToList() : enabled;
            var box = new ComboBox { MinWidth = 220 };
            foreach (var p in options) box.Items.Add(new ComboBoxItem { Content = p.Label, Tag = p.Name });
            var current = tasks.Obj(task).Str("provider");
            box.SelectedItem = box.Items.OfType<ComboBoxItem>().FirstOrDefault(i => (string)i.Tag == current);
            box.PlaceholderText = options.Count == 0 ? "No provider can do this" : "Choose";
            box.SelectionChanged += async (_, _) =>
            {
                if (box.SelectedItem is ComboBoxItem { Tag: string name } && name != current)
                    await Run(() => SetConfig(new() { [$"tasks.{task}.provider"] = name }));
            };
            Body.Children.Add(Card(GenerateSpec.Cap(task), Cap(info.Str(task)), Glyph(glyph), box));
        }
    }

    // ---------- On this PC ----------

    async Task LoadLocal()
    {
        try
        {
            local = await Backend.Shared.GetAsync("/api/local");
            if (section == "local") Refresh();
        }
        catch (Exception ex) { App.Window?.ShowError("Couldn't load local models", ex.Message); }
    }

    void Local()
    {
        Intro("Free open models that run on your graphics card. Private, and they work offline.");
        if (local.ValueKind != JsonValueKind.Object)
        {
            Body.Children.Add(new ProgressRing { IsActive = true, Margin = new Thickness(0, 40, 0, 0) });
            return;
        }
        if (!local.Bool("supported"))
        {
            Body.Children.Add(Card("Needs 64-bit Windows on an x64 PC", null, Glyph("")));
            return;
        }
        // Examples dropdown
        var examples = local.Arr("catalog").ToList();
        if (selectedExample.Length == 0 || !examples.Any(e => e.Str("id") == selectedExample))
            selectedExample = examples.FirstOrDefault(e => !e.Bool("installed")).Str("id") is { Length: > 0 } first ? first : examples.FirstOrDefault().Str("id");
        var box = new ComboBox { MinWidth = 300 };
        foreach (var e in examples)
            box.Items.Add(new ComboBoxItem { Content = $"{e.Str("name")} · {(e.Bool("installed") ? "Downloaded" : Format.Bytes(e.Num("download")))}", Tag = e.Str("id") });
        box.SelectedItem = box.Items.OfType<ComboBoxItem>().FirstOrDefault(i => (string)i.Tag == selectedExample);
        box.SelectionChanged += (_, _) => { if (box.SelectedItem is ComboBoxItem { Tag: string id }) { selectedExample = id; Refresh(); } };
        var ex = examples.FirstOrDefault(e => e.Str("id") == selectedExample);
        var exRow = Ui.Row(10, box, DownloadButton(selectedExample, selectedExample, ex.Bool("installed"), "Download"));
        var exCard = Card("Pick a model", $"{ex.Str("note")} {ex.Str("license")}".Trim(), Glyph(""), exRow);
        Body.Children.Add(exCard);
        if (DownloadStatus(selectedExample) is { } st) Body.Children.Add(st);

        // Hugging Face search
        var query = new TextBox { PlaceholderText = "Search Hugging Face or paste a link", Text = searchQuery, Width = 420 };
        var search = new Button { Content = "Search" };
        async Task DoSearch()
        {
            searchQuery = query.Text.Trim();
            bool link = searchQuery.StartsWith("http") || System.Text.RegularExpressions.Regex.IsMatch(searchQuery, @"^[\w.-]+/[\w.-]+$");
            if (link) { await StartDownload(searchQuery, searchQuery); return; }
            searchError = null;
            try
            {
                var rows = await Backend.Shared.GetAsync("/api/local/search?q=" + Uri.EscapeDataString(searchQuery));
                searchResults = rows.ValueKind == JsonValueKind.Array ? rows.EnumerateArray().ToList() : [];
            }
            catch (Exception e) { searchError = e.Message; searchResults = []; }
            Refresh();
        }
        search.Click += async (_, _) => await DoSearch();
        query.KeyDown += async (_, e) => { if (e.Key == Windows.System.VirtualKey.Enter) await DoSearch(); };
        Body.Children.Add(Card("More models", "Search Hugging Face for models this PC can run, or paste a link.", Glyph(""), Ui.Row(8, query, search)));
        if (searchError is not null) Body.Children.Add(Card(searchError, null, Glyph("", Ui.Hex(0xD92D20))));
        foreach (var r in searchResults.Take(12)) Body.Children.Add(ResultCard(r));

        // Downloaded
        var models = local.Arr("models").ToList();
        if (models.Count > 0)
        {
            Heading("Downloaded");
            foreach (var m in models)
            {
                var remove = Ui.IconButton("", "Remove", async (_, _) =>
                {
                    if (!await Confirm($"Remove {m.Str("name")}?", $"Frees about {Format.Bytes(m.Num("bytes"))}. You can download it again anytime.", "Remove")) return;
                    await Run(async () =>
                    {
                        await Backend.Shared.PostAsync("/api/local/remove", new { model = m.Str("id") });
                        await Store.Shared.ReloadStateAsync();
                        await LoadLocal();
                    });
                });
                ((FontIcon)remove.Content).Foreground = new SolidColorBrush(Ui.Hex(0xD92D20));
                string family = m.Str("family");
                string desc = m.Bool("ready") ? string.Join(" · ", new[] { family == m.Str("name") ? "" : family, Format.Bytes(m.Num("bytes")) }.Where(x => x.Length > 0))
                    : "Files missing. Download it again.";
                var right = Ui.Row(8);
                if (m.Bool("edit")) right.Children.Add(Ui.Pill("Edits"));
                right.Children.Add(remove);
                Body.Children.Add(Card(m.Str("name"), desc, Glyph(""), right));
            }
        }

        // Engine and storage
        var backend = new ComboBox { MinWidth = 220 };
        backend.Items.Add(new ComboBoxItem { Content = "Graphics card (Vulkan)", Tag = "vulkan" });
        backend.Items.Add(new ComboBoxItem { Content = "Processor only (slow)", Tag = "cpu" });
        var currentBackend = Store.Shared.State.Str("local_backend", "vulkan");
        backend.SelectedItem = backend.Items.OfType<ComboBoxItem>().FirstOrDefault(i => (string)i.Tag == currentBackend);
        backend.SelectionChanged += async (_, _) =>
        {
            if (backend.SelectedItem is ComboBoxItem { Tag: string b } && b != currentBackend)
                await Run(() => SetConfig(new() { ["local_backend"] = b }));
        };
        Heading("Engine");
        Body.Children.Add(Card("Runs on", "stable-diffusion.cpp. Use the processor only if your graphics card doesn't work with Vulkan.", Glyph(""), backend));
        var folder = local.Str("dir");
        var open = Ui.LabelButton("", "Open Folder", (_, _) => { if (Directory.Exists(folder)) Process.Start("explorer.exe", $"\"{folder}\""); });
        Body.Children.Add(Card("Storage", $"{Format.Bytes(local.Num("bytes"))} used · {Format.Bytes(local.Num("free"))} free", Glyph(""), open));
    }

    SettingsCard ResultCard(JsonElement r)
    {
        var parts = new List<string> { r.Str("author"), $"↓ {Format.Compact(r.Num("downloads"))}" };
        if (r.Str("family") is { Length: > 0 } f) parts.Add(f);
        if (r.Num("size") > 0) parts.Add(Format.Bytes(r.Num("size") + r.Num("extra")));
        if (r.Str("license") is { Length: > 0 } l) parts.Add(l);
        var right = Ui.Row(8);
        if (r.Bool("edit")) right.Children.Add(Ui.Pill("Edits"));
        if (r.Bool("noncommercial")) right.Children.Add(Ui.Pill("Non-commercial"));
        string repo = r.Str("repo");
        if (!r.Bool("supported")) { var t = Ui.Faint("Not supported", 12); t.VerticalAlignment = VerticalAlignment.Center; ToolTipService.SetToolTip(t, r.Str("reason")); right.Children.Add(t); }
        else if (r.Bool("gated")) { var t = Ui.Faint("Needs login", 12); t.VerticalAlignment = VerticalAlignment.Center; right.Children.Add(t); }
        else right.Children.Add(DownloadButton(repo, repo, r.Bool("installed"), "Get"));
        var card = Card(r.Str("name"), string.Join(" · ", parts), Glyph(""), right);
        return card;
    }

    UIElement DownloadButton(string key, string spec, bool installed, string label)
    {
        if (downloads.TryGetValue(key, out var d) && d.Error is null)
        {
            var stop = new Button { Content = "Cancel" };
            stop.Click += async (_, _) => await Run(() => Backend.Shared.PostAsync($"/api/jobs/{d.JobId}/cancel"));
            return stop;
        }
        if (installed) return Ui.Pill("Downloaded", Ui.Hex(0x34C759));
        var b = new Button { Content = label, Style = Ui.Res<Style>("AccentButtonStyle") };
        b.Click += async (_, _) => await StartDownload(key, spec);
        return b;
    }

    UIElement? DownloadStatus(string key)
    {
        if (!downloads.TryGetValue(key, out var d)) return null;
        if (d.Error is { } err)
        {
            var e = Ui.Text(err, 13);
            e.Foreground = new SolidColorBrush(Ui.Hex(0xD92D20));
            e.TextWrapping = TextWrapping.Wrap;
            return Ui.Card(e, 14);
        }
        var bar = new ProgressBar { Maximum = Math.Max(1, d.Total), Value = d.Done, IsIndeterminate = d.Total <= 0 };
        return Ui.Card(Ui.Column(8, bar, Ui.Muted(d.Total > 0 ? $"{Format.Bytes(d.Done)} of {Format.Bytes(d.Total)}" : "Starting…", 12)), 14);
    }

    async Task StartDownload(string key, string spec)
    {
        try
        {
            var job = await Backend.Shared.PostAsync("/api/local/add", new { model = spec, label = spec });
            downloads[key] = (job.Str("id"), 0, 0, null);
            Refresh();
            while (true)
            {
                await Task.Delay(700);
                var j = await Backend.Shared.GetAsync($"/api/jobs/{downloads[key].JobId}");
                var ev = j.Obj("event");
                downloads[key] = (downloads[key].JobId, ev.Num("done"), ev.Num("total"), null);
                var status = j.Str("status");
                if (status != "running")
                {
                    if (status == "done") downloads.Remove(key);
                    else downloads[key] = (downloads[key].JobId, 0, 0, status == "cancelled" ? "Download stopped. Start it again to continue."
                        : j.Strings("lines").LastOrDefault(l => l is not null) ?? "Download failed.");
                    await Store.Shared.ReloadStateAsync();
                    await LoadLocal();
                    return;
                }
                if (section == "local") Refresh();
            }
        }
        catch (Exception ex)
        {
            downloads[key] = ("", 0, 0, ex.Message);
            Refresh();
        }
    }

    // ---------- Limits ----------

    void Limits()
    {
        var limits = Store.Shared.State.Obj("limits");
        var usage = Store.Shared.State.Obj("usage");
        Intro($"This month: {Format.Money(usage.Num("cost"))} and {Format.Count((int)usage.Num("images"))} images. You get a notice at 80% and 100%.");
        double cost = limits.Num("monthly_cost"), images = limits.Num("monthly_images");
        bool stop = limits.Bool("stop_paid");

        var costBox = new NumberBox { Value = cost > 0 ? cost : 20, Minimum = 1, SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact, Width = 120, IsEnabled = cost > 0 };
        var costToggle = new ToggleSwitch { IsOn = cost > 0, OnContent = "", OffContent = "" };
        costToggle.Toggled += async (_, _) => { costBox.IsEnabled = costToggle.IsOn; await SaveLimit("monthly_cost", costToggle.IsOn ? Math.Round(costBox.Value, 2) : null); };
        costBox.ValueChanged += async (_, a) => { if (costToggle.IsOn && !double.IsNaN(a.NewValue)) await SaveLimit("monthly_cost", Math.Round(a.NewValue, 2)); };
        Body.Children.Add(Card("Monthly spend", "In US dollars, estimated from each provider's prices.", Glyph("\uE8C7"), Ui.Row(12, costBox, costToggle)));

        var imgBox = new NumberBox { Value = images > 0 ? images : 500, Minimum = 1, SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact, Width = 120, IsEnabled = images > 0 };
        var imgToggle = new ToggleSwitch { IsOn = images > 0, OnContent = "", OffContent = "" };
        imgToggle.Toggled += async (_, _) => { imgBox.IsEnabled = imgToggle.IsOn; await SaveLimit("monthly_images", imgToggle.IsOn ? Math.Round(imgBox.Value) : null); };
        imgBox.ValueChanged += async (_, a) => { if (imgToggle.IsOn && !double.IsNaN(a.NewValue)) await SaveLimit("monthly_images", Math.Round(a.NewValue)); };
        Body.Children.Add(Card("Monthly images", "Every image counts, paid or not.", Glyph("\uE91B"), Ui.Row(12, imgBox, imgToggle)));

        var when = new ComboBox { MinWidth = 220 };
        when.Items.Add(new ComboBoxItem { Content = "Only warn me", Tag = "warn" });
        when.Items.Add(new ComboBoxItem { Content = "Stop paid images", Tag = "stop" });
        when.SelectedIndex = stop ? 1 : 0;
        when.SelectionChanged += async (_, _) => await Run(() => SetConfig(new() { ["limits.stop_paid"] = when.SelectedIndex == 1 }));
        Body.Children.Add(Card("When a limit is reached", $"Subscriptions and On {Store.Shared.Device} keep working.", Glyph("\uE7BA"), when));
    }

    /// Sets limits.<key> to a number, or removes it (null).
    async Task SaveLimit(string key, double? value)
    {
        if (value is { } v) await Run(() => SetConfig(new() { [$"limits.{key}"] = v }));
        else await Run(() => SetConfig(new(), new[] { $"limits.{key}" }));
    }

    // ---------- AI agents ----------

    void Agents()
    {
        Intro("Claude Code and Codex make images with the imagegenkit command, using your settings and limits.");
        bool installed = CommandInstaller.Installed;
        var cmdButton = new Button
        {
            Content = installed ? (CommandInstaller.Outdated ? "Update" : "Reinstall") : "Install",
            Style = installed && !CommandInstaller.Outdated ? Ui.Res<Style>("DefaultButtonStyle") : Ui.Res<Style>("AccentButtonStyle"),
        };
        cmdButton.Click += async (_, _) => await Run(async () => { await Task.Run(CommandInstaller.Install); Refresh(); });
        Body.Children.Add(Card("The imagegenkit command",
            installed ? $"Version {CommandInstaller.InstalledVersion} in {CommandInstaller.Bin}" : "Needed by agents. Installs into your user folder and PATH.",
            Glyph(""), cmdButton));
        foreach (var a in Store.Shared.State.Arr("agents"))
        {
            string id = a.Str("id"), label = a.Str("label");
            bool present = a.Bool("present"), has = a.Bool("installed");
            var right = Ui.Row(8);
            if (has)
            {
                right.Children.Add(Ui.Pill("Installed", Ui.Hex(0x34C759)));
                var remove = Ui.IconButton("", "Remove the skill", async (_, _) =>
                {
                    if (!await Confirm($"Remove the skill from {label}?", $"{label} won't know how to make images with ImageGenKit anymore.", "Remove")) return;
                    await Run(async () => { await Backend.Shared.PostAsync("/api/skill", new { agent = id, remove = true }); await Store.Shared.ReloadStateAsync(); });
                });
                ((FontIcon)remove.Content).Foreground = new SolidColorBrush(Ui.Hex(0xD92D20));
                right.Children.Add(remove);
            }
            else
            {
                var install = new Button { Content = "Install Skill", Style = Ui.Res<Style>("AccentButtonStyle"), IsEnabled = present };
                install.Click += async (_, _) => await Run(async () => { await Backend.Shared.PostAsync("/api/skill", new { agent = id }); await Store.Shared.ReloadStateAsync(); });
                right.Children.Add(install);
            }
            string desc = has ? $"Skill version {a.Str("version")}" : present ? "Not installed yet" : $"{label} isn't on this PC";
            Body.Children.Add(Card(label, desc, Glyph(id == "claude" ? "" : ""), right));
        }
    }

    // ---------- General ----------

    void General()
    {
        var s = Store.Shared;
        Heading("Images");
        var outDir = s.State.Str("output_dir");
        var change = Ui.LabelButton("", "Change…", async (_, _) =>
        {
            var picker = new FolderPicker { SuggestedStartLocation = PickerLocationId.PicturesLibrary };
            picker.FileTypeFilter.Add("*");
            WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(App.Window!));
            var folder = await picker.PickSingleFolderAsync();
            if (folder is not null) await Run(() => SetConfig(new() { ["output_dir"] = folder.Path }));
        });
        var open = Ui.LabelButton("", "Open", async (_, _) => await Run(() => Backend.Shared.PostAsync("/api/open", new { folder = "output" })));
        Body.Children.Add(Card("Save images to", outDir, Glyph(""), Ui.Row(8, change, open)));

        Heading("Updates");
        var u = Updater.Shared;
        UIElement action = u.State switch
        {
            Updater.Phase.Checking or Updater.Phase.Downloading => new ProgressRing { IsActive = true, Width = 20, Height = 20 },
            Updater.Phase.Available => Ui.LabelButton("\uE896", $"Update to {u.Latest}", async (_, _) => { await u.InstallAsync(); Refresh(); }, accent: true),
            _ => Ui.LabelButton("\uE72C", "Check for Updates", async (_, _) => { var t = u.CheckAsync(); Refresh(); await t; Refresh(); }),
        };
        string state = u.State switch
        {
            Updater.Phase.UpToDate => "Up to date",
            Updater.Phase.Available => $"Version {u.Latest} is available",
            Updater.Phase.Downloading => "Downloading the update…",
            Updater.Phase.Failed => u.Error ?? "Couldn't check",
            _ => "Updates come from GitHub",
        };
        Body.Children.Add(Card($"ImageGenKit {Updater.Current}", state, Glyph("\uE895"), action));
        var auto = new ToggleSwitch { IsOn = s.State.Bool("auto_update", true), OnContent = "", OffContent = "" };
        auto.Toggled += async (_, _) => await Run(() => auto.IsOn ? SetConfig(new(), new[] { "auto_update" }) : SetConfig(new() { ["auto_update"] = false }));
        Body.Children.Add(Card("Update the imagegenkit command by itself", "When you use it without the app. Checks GitHub once a day.", Glyph(""), auto));

        Heading("Help");
        var tourButton = Ui.LabelButton("\uE7BE", "Show Tour", (_, _) => App.Window?.ShowTour());
        Body.Children.Add(Card("Welcome tour", "A quick look at what ImageGenKit does, with a hands-on demo.", Glyph("\uE897"), tourButton));
        string accepted = AppPrefs.Str("termsAcceptedAt") is { } at && DateTimeOffset.TryParse(at, out var when)
            ? $"Version {Terms.Version}, accepted on {when.LocalDateTime:d}." : $"Version {Terms.Version}.";
        var legal = Ui.Row(8,
            Ui.LabelButton("\uE8A5", "Terms of Use", (_, _) => OpenUrl(Terms.Url)),
            Ui.LabelButton("\uE72E", "Privacy Policy", (_, _) => OpenUrl(Terms.PrivacyUrl)));
        Body.Children.Add(Card("Terms of use", accepted, Glyph("\uE8A5"), legal));

        Heading("About");
        var version = Updater.Current;
        var links = Ui.Row(8,
            Ui.LabelButton("", "GitHub", (_, _) => OpenUrl("https://github.com/davidkrammer/imagegenkit")),
            Ui.LabelButton("", "Donate", (_, _) => OpenUrl("https://github.com/davidkrammer/imagegenkit#support")));
        Body.Children.Add(Card($"ImageGenKit {version}", "Free and open source. Made by STRICS IT GmbH, Austria.", Glyph(""), links));
    }

    static void OpenUrl(string url) => ProviderSetup.OpenUrl(url);

}
