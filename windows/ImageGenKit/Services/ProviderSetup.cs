using System.Diagnostics;
using ImageGenKit.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace ImageGenKit.Services;

/// Setting up a provider (key, terminal login, adding it to the list): shared by Settings and the welcome tour.
public static class ProviderSetup
{
    public static async Task Run(Func<Task> action)
    {
        try { await action(); }
        catch (Exception ex) { App.Window?.ShowError("Something went wrong", ex.Message); }
    }

    public static async Task SetConfig(Dictionary<string, object?> set, IEnumerable<string>? unset = null)
    {
        var state = await Backend.Shared.PostAsync("/api/config", new { set, unset = unset?.ToList() ?? [] });
        Store.Shared.Apply(state);
        Store.Shared.NotifyChanged();
    }

    public static void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch (Exception ex) { Log.Write("url: " + ex.Message); }
    }

    /// Grok Build and Codex log in (or install) in a terminal; the dialog checks again when it's closed.
    public static async Task Terminal(ProviderRow p, XamlRoot root, bool login = false)
    {
        string tool = p.Type == "codex-cli" ? "codex" : "grok";
        bool install = !login && p.Status.Contains("install", StringComparison.OrdinalIgnoreCase);
        await Backend.Shared.PostAsync("/api/terminal", new { action = $"{(install ? "install" : "login")}-{tool}" });
        var dialog = new ContentDialog
        {
            Title = install ? $"Installing {(tool == "codex" ? "Codex" : "Grok Build")}" : "Log in",
            Content = install ? "Follow the steps in the terminal window. Then log in." : "Log in in the terminal window, then come back.",
            PrimaryButtonText = "Check Now", CloseButtonText = "Close", DefaultButton = ContentDialogButton.Primary, XamlRoot = root,
        };
        await dialog.ShowAsync();
        await Store.Shared.ReloadStateAsync(); // the terminal says "click Check now"; closing checks too
    }

    public static async Task KeyDialog(ProviderRow p, XamlRoot root)
    {
        var box = new PasswordBox { PlaceholderText = "Paste the API key", Width = 380 };
        var steps = Ui.Column(6);
        int n = 1;
        foreach (var step in p.Raw.Arr("steps"))
        {
            var t = Ui.Muted($"{n++}. {step.Str("text")}", 13);
            t.TextWrapping = TextWrapping.Wrap;
            t.TextTrimming = TextTrimming.None;
            steps.Children.Add(t);
        }
        var content = Ui.Column(14, steps, box);
        if (p.KeyUrl is { } url)
        {
            var link = new HyperlinkButton { Content = "Get a key", Padding = new Thickness(0) };
            link.Click += (_, _) => OpenUrl(url);
            content.Children.Add(link);
        }
        content.Children.Add(Ui.Faint("Saved in the Windows Credential Manager. Never shared with anyone but the provider.", 12));
        var dialog = new ContentDialog
        {
            Title = $"{p.Label} API key", Content = content, PrimaryButtonText = "Save", CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary, XamlRoot = root,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary || box.Password.Trim().Length == 0) return;
        await Run(async () =>
        {
            await Backend.Shared.PostAsync("/api/key", new { provider = p.Name, key = box.Password.Trim() });
            await Store.Shared.ReloadStateAsync();
        });
    }

    /// Puts the provider in the list and walks through what it still needs: a key, a login, or (local) a model.
    public static async Task Connect(ProviderRow p, XamlRoot root, Action? openLocal)
    {
        await Run(async () =>
        {
            var enabled = Store.Shared.Enabled;
            if (!enabled.Contains(p.Name)) await SetConfig(new() { ["order"] = enabled.Append(p.Name).ToList() });
            if (p.IsLocal) openLocal?.Invoke();
            else if (p.NeedsKey && !p.Ready) await KeyDialog(p, root);
            else if (!p.Ready) await Terminal(p, root);
        });
    }

    /// Every provider that isn't in the list yet, to pick one.
    public static async Task AddProviderDialog(XamlRoot root, Action? openLocal, Func<ProviderRow, bool>? filter = null)
    {
        var s = Store.Shared;
        var enabled = s.Enabled;
        var list = Ui.Column(8);
        ContentDialog? dialog = null;
        foreach (var p in s.Providers.Where(p => !enabled.Contains(p.Name) && (filter?.Invoke(p) ?? true))
                     .OrderBy(p => p.IsLocal ? 0 : p.IsSubscription ? 1 : 2))
        {
            var text = Ui.Column(2, Ui.Text(p.Label, 14, bold: true));
            if (p.Tagline is { } t) { var tl = Ui.Muted(t, 12); tl.TextWrapping = TextWrapping.Wrap; tl.TextTrimming = TextTrimming.None; text.Children.Add(tl); }
            if (p.PriceHint is { } h) text.Children.Add(Ui.Faint(h, 12));
            var row = Ui.Columns((Ui.Badge(ProviderStyle.Glyph(p.Name, p.Type), ProviderStyle.ColorOf(p.Name, ProviderStyle.IsDark), 34), Ui.Auto), (text, Ui.Star()));
            var button = new Button { Content = row, HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch, Padding = new Thickness(12, 10, 12, 10) };
            button.Click += async (_, _) =>
            {
                dialog?.Hide();
                await Connect(p, root, openLocal);
            };
            list.Children.Add(button);
        }
        if (list.Children.Count == 0) list.Children.Add(Ui.Muted("Every provider is added already."));
        dialog = new ContentDialog
        {
            Title = "Add a provider", Content = new ScrollViewer { Content = list, MaxHeight = 460, Padding = new Thickness(0, 0, 12, 0) },
            CloseButtonText = "Cancel", XamlRoot = root,
        };
        await dialog.ShowAsync();
    }
}
