using System.Diagnostics;
using ImageGenKit.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;

namespace ImageGenKit.Controls;

/// The details of one run (the Mac app's inspector): picture, prompt, tags and actions.
public static class Inspector
{
    public static UIElement Build(LogItem e, int index, Action<int> select)
    {
        var s = Store.Shared;
        var body = Ui.Column(16);
        body.Padding = new Thickness(20, 4, 24, 28);

        string? picture = e.Picture(index, preferThumb: false);
        var hero = new Border
        {
            Style = Ui.GetStyle("TileStyle"), CornerRadius = new CornerRadius(12), Height = 300,
            Child = picture is null ? Center(Ui.Faint("File deleted", 13)) : Ui.Picture(picture, 760, Stretch.Uniform),
        };
        body.Children.Add(hero);

        if (e.ImageCount > 1)
        {
            var strip = Ui.Row(8);
            for (int i = 0; i < e.ImageCount; i++)
            {
                int k = i;
                var tile = Ui.Tile(e.Picture(i), 54, 54, 108, 8);
                if (i == index) { tile.BorderThickness = new Thickness(2); tile.BorderBrush = (Brush)Application.Current.Resources["TextFillColorPrimaryBrush"]; }
                var b = new Button { Content = tile, Padding = new Thickness(0), Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent), BorderThickness = new Thickness(0) };
                b.Click += (_, _) => select(k);
                strip.Children.Add(b);
            }
            body.Children.Add(strip);
        }

        var prompt = Ui.Text(e.Prompt, 16, bold: true);
        prompt.TextWrapping = TextWrapping.Wrap;
        prompt.TextTrimming = TextTrimming.None;
        prompt.IsTextSelectionEnabled = true;
        prompt.MaxLines = 8;
        body.Children.Add(prompt);

        var tags = new VariableSizedWrap();
        tags.Add(Ui.Pill(s.Label(e.Provider), ProviderStyle.ColorOf(e.Provider, ProviderStyle.IsDark)));
        if (e.Model.Length > 0) tags.Add(Ui.Pill(e.Model));
        if (e.Size.Length > 0 && e.Size != "auto") tags.Add(Ui.Pill(e.Size));
        if (e.Raw.Param("quality") is { } q && q != "auto") tags.Add(Ui.Pill(char.ToUpperInvariant(q[0]) + q[1..]));
        tags.Add(Ui.Pill(e.CostLabel));
        if (e.Seconds > 0) tags.Add(Ui.Pill(Format.Seconds(e.Seconds)));
        body.Children.Add(tags.Panel);

        string? file = picture is not null && e.Outputs.Count > index && File.Exists(e.Outputs[index]) ? e.Outputs[index] : null;
        var actions = Ui.Row(8);
        var use = Ui.LabelButton("", "Use as Reference", (_, _) => App.Window?.OpenGenerate(file ?? picture), accent: true);
        use.IsEnabled = picture is not null;
        actions.Children.Add(use);
        actions.Children.Add(Ui.IconButton("", "Open", (_, _) => Open(file)));
        actions.Children.Add(Ui.IconButton("", "Show in File Explorer", (_, _) => Reveal(file)));
        actions.Children.Add(Ui.IconButton("", "Copy Path", (_, _) => CopyPath(file)));
        foreach (var b in actions.Children.OfType<Button>().Skip(1)) b.IsEnabled = file is not null;
        body.Children.Add(actions);

        var facts = Ui.Column(12,
            Fact("", "Date", e.Date.ToString("MMM d, yyyy 'at' HH:mm")),
            Fact("", "Project", e.Project),
            Fact("", "Made by", e.Who));
        body.Children.Add(Ui.Card(facts, 16));
        return new ScrollViewer { Content = body, HorizontalScrollMode = ScrollMode.Disabled, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
    }

    static UIElement Fact(string glyph, string label, string value) =>
        Ui.Row(12, Ui.Badge(glyph, Ui.Hex(0x8E8E93), 30), Ui.Column(1, Ui.Faint(label, 11), Ui.Text(value, 14)));

    static UIElement Center(FrameworkElement e)
    {
        e.HorizontalAlignment = HorizontalAlignment.Center;
        e.VerticalAlignment = VerticalAlignment.Center;
        return e;
    }

    public static void Open(string? path)
    {
        if (path is null) return;
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); } catch (Exception ex) { Log.Write("open: " + ex.Message); }
    }

    public static void Reveal(string? path)
    {
        if (path is null) return;
        try { Process.Start("explorer.exe", $"/select,\"{path}\""); } catch (Exception ex) { Log.Write("reveal: " + ex.Message); }
    }

    public static void CopyPath(string? path)
    {
        if (path is null) return;
        var data = new DataPackage();
        data.SetText(path);
        Clipboard.SetContent(data);
    }

    /// Tags that wrap onto the next line.
    sealed class VariableSizedWrap
    {
        public readonly StackPanel Panel = new() { Spacing = 6 };
        StackPanel line = new() { Orientation = Orientation.Horizontal, Spacing = 6 };
        int count;

        public VariableSizedWrap() => Panel.Children.Add(line);

        public void Add(UIElement e)
        {
            if (count == 4) { line = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 }; Panel.Children.Add(line); count = 0; }
            line.Children.Add(e);
            count++;
        }
    }
}
