using CommunityToolkit.WinUI.Controls;
using ImageGenKit.Controls;
using ImageGenKit.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;

namespace ImageGenKit.Pages;

public sealed partial class OverviewPage : Page, IRefreshable
{
    bool showSpend;

    public OverviewPage()
    {
        InitializeComponent();
        Loaded += (_, _) => Refresh();
    }

    public void Refresh()
    {
        Body.Children.Clear();
        var s = Store.Shared;
        if (!s.Loaded)
        {
            Body.Children.Add(new ProgressRing { IsActive = true, Margin = new Thickness(0, 80, 0, 0) });
            return;
        }
        if (s.Log.Count == 0)
        {
            Body.Children.Add(EmptyState());
            return;
        }
        var list = s.Filtered().ToList();
        Body.Children.Add(Hero(list));
        Body.Children.Add(Stats(list));
        Body.Children.Add(Activity(list));
        Body.Children.Add(Ui.Columns((Providers(list), Ui.Star()), (Projects(list), Ui.Star())));
    }

    string RangeTitle => Store.Shared.RangeDays switch
    {
        7 => "Last 7 days", 30 => "Last 30 days", 90 => "Last 90 days", 365 => "Last 12 months", _ => "All time",
    };

    UIElement Hero(List<LogItem> list)
    {
        var s = Store.Shared;
        var top = list.GroupBy(e => e.Provider).OrderByDescending(g => g.Sum(e => e.ImageCount)).FirstOrDefault();
        int projects = list.Select(e => e.Project).Where(p => p != "Unknown").Distinct().Count();
        string sub = top is null ? "Nothing made in this time" :
            $"Mostly {s.Label(top.Key)}" + (projects > 0 ? $" · {projects} project{(projects == 1 ? "" : "s")}" : "");

        var collage = new Grid { Width = 330, Height = 120, HorizontalAlignment = HorizontalAlignment.Right };
        var pics = list.Where(e => e.ImageCount > 0).Select(e => e.Picture(0)).Where(p => p is not null).Take(4).Reverse().ToList();
        double[] angles = [-8, -3, 2, 7];
        for (int i = 0; i < pics.Count; i++)
        {
            var tile = Ui.Tile(pics[i], 92, 92, 184, 12);
            tile.BorderThickness = new Thickness(3);
            tile.BorderBrush = new SolidColorBrush(Microsoft.UI.Colors.White);
            tile.HorizontalAlignment = HorizontalAlignment.Left;
            tile.VerticalAlignment = VerticalAlignment.Center;
            tile.Margin = new Thickness(i * 74, 0, 0, 0);
            tile.RenderTransformOrigin = new Point(0.5, 0.5);
            tile.RenderTransform = new RotateTransform { Angle = angles[i % angles.Length] };
            collage.Children.Add(tile);
        }
        var text = Ui.Column(4, Ui.Text(RangeTitle, 28, bold: true), Ui.Muted(sub, 14));
        text.VerticalAlignment = VerticalAlignment.Center;
        var grid = Ui.Columns((text, Ui.Star()), (collage, Ui.Auto));
        return new Border { Style = Ui.GetStyle("HeroStyle"), Padding = new Thickness(32, 22, 28, 22), Child = grid };
    }

    UIElement Stats(List<LogItem> list)
    {
        var s = Store.Shared;
        double spend = list.Sum(e => e.Cost);
        int images = list.Sum(e => e.ImageCount);
        int paid = list.Where(e => !e.Free).Sum(e => e.ImageCount);
        int runs = list.Count;
        var timed = list.Where(e => e.Seconds > 0).ToList();
        double avg = timed.Count > 0 ? timed.Average(e => e.Seconds) : 0;

        // Change against the period before (same length), like the Mac app.
        List<LogItem> previous = [];
        if (s.RangeDays > 0)
        {
            var start = DateTime.Today.AddDays(-(s.RangeDays - 1));
            var prevStart = start.AddDays(-s.RangeDays);
            previous = s.Log.Where(e => e.Date >= prevStart && e.Date < start && (s.ProviderFilter.Length == 0 || e.Provider == s.ProviderFilter)).ToList();
        }
        string? Trend(double now, double before) =>
            previous.Count == 0 || before <= 0 ? null : $"{(now >= before ? "↗" : "↘")} {Math.Abs(Math.Round((now - before) / before * 100))}%";

        var green = Ui.Hex(0x1BAF7A);
        return Ui.Columns(
            (Stat(Ui.BadgeText("$", green), "Spend", Format.Money(spend), null, Trend(spend, previous.Sum(e => e.Cost))), Ui.Star()),
            (Stat(Ui.Badge("", Ui.Hex(0x8E8E93)), "Images", Format.Count(images), paid != images ? $"{Format.Count(paid)} paid" : null,
                Trend(images, previous.Sum(e => e.ImageCount))), Ui.Star()),
            (Stat(Ui.Badge("", Ui.Hex(0xEB6834)), "Runs", Format.Count(runs), null, Trend(runs, previous.Count)), Ui.Star()),
            (Stat(Ui.Badge("", Ui.Hex(0x2A78D6)), "Avg. time", Format.Seconds(avg), null, null), Ui.Star()));
    }

    static UIElement Stat(UIElement badge, string label, string value, string? detail, string? trend)
    {
        var head = Ui.Columns((Ui.Row(10, badge, Center(Ui.Muted(label, 14))), Ui.Star()),
                              (trend is null ? new Grid() : (UIElement)Center(Ui.Pill(trend)), Ui.Auto));
        var big = Ui.Row(8, Ui.Text(value, 32, bold: true));
        if (detail is not null)
        {
            var d = Ui.Muted(detail, 12);
            d.VerticalAlignment = VerticalAlignment.Bottom;
            d.Margin = new Thickness(0, 0, 0, 7);
            big.Children.Add(d);
        }
        return Ui.Card(Ui.Column(14, head, big));
    }

    static T Center<T>(T e) where T : FrameworkElement
    {
        e.VerticalAlignment = VerticalAlignment.Center;
        return e;
    }

    UIElement Activity(List<LogItem> list)
    {
        var s = Store.Shared;
        var chart = new ActivityChart();
        var providers = list.GroupBy(e => e.Provider).OrderByDescending(g => g.Sum(e => e.ImageCount)).Select(g => g.Key).ToList();

        var legend = Ui.Row(14);
        foreach (var p in providers.Take(5)) legend.Children.Add(Ui.Row(6, Ui.Dot(ProviderStyle.ColorOf(p, ProviderStyle.IsDark)), Center(Ui.Muted(s.Label(p), 12))));
        var segmented = new Segmented { SelectedIndex = showSpend ? 1 : 0 };
        segmented.Items.Add(new SegmentedItem { Content = "Images" });
        segmented.Items.Add(new SegmentedItem { Content = "Spend" });
        segmented.SelectionChanged += (_, _) =>
        {
            showSpend = segmented.SelectedIndex == 1;
            chart.SetData(Buckets(list, showSpend), providers, showSpend);
        };
        legend.VerticalAlignment = VerticalAlignment.Center;
        var head = Ui.Columns(
            (Ui.Row(10, Ui.Icon("", 16), Center(Ui.Text("Activity", 15, bold: true))), Ui.Star()),
            (legend, Ui.Auto), (segmented, Ui.Auto));
        chart.SetData(Buckets(list, showSpend), providers, showSpend);
        return Ui.Card(Ui.Column(14, head, chart));
    }

    List<ActivityChart.Bucket> Buckets(List<LogItem> list, bool spend)
    {
        var s = Store.Shared;
        DateTime end = DateTime.Today;
        DateTime start = s.RangeDays > 0 ? end.AddDays(-(s.RangeDays - 1)) : (list.Count > 0 ? list.Min(e => e.Date).Date : end);
        int days = (int)(end - start).TotalDays + 1;
        string unit = days <= 92 ? "day" : days <= 400 ? "week" : "month";
        DateTime Key(DateTime d) => unit switch
        {
            "day" => d.Date,
            "week" => d.Date.AddDays(-(((int)d.DayOfWeek + 6) % 7)),
            _ => new DateTime(d.Year, d.Month, 1),
        };
        var keys = new List<DateTime>();
        for (var d = Key(start); d <= end; d = unit == "day" ? d.AddDays(1) : unit == "week" ? d.AddDays(7) : d.AddMonths(1)) keys.Add(d);
        var map = keys.ToDictionary(k => k, _ => new Dictionary<string, double>());
        foreach (var e in list)
        {
            if (!map.TryGetValue(Key(e.Date), out var v)) continue;
            v[e.Provider] = v.GetValueOrDefault(e.Provider) + (spend ? e.Cost : e.ImageCount);
        }
        string Label(DateTime k) => unit == "month" ? k.ToString("MMM yy") : k.ToString("MMM d");
        return keys.Select(k => new ActivityChart.Bucket(k, Label(k), map[k])).ToList();
    }

    UIElement Providers(List<LogItem> list)
    {
        var s = Store.Shared;
        var rows = list.GroupBy(e => e.Provider)
            .Select(g => (Id: g.Key, Images: g.Sum(e => e.ImageCount), Spend: g.Sum(e => e.Cost), Label: g.First().CostLabel, Free: g.First().Free))
            .OrderByDescending(r => r.Images).Take(6).ToList();
        int top = Math.Max(1, rows.Count > 0 ? rows.Max(r => r.Images) : 1);
        return ListCard("", "Providers", rows.Select(r =>
            (s.Label(r.Id), r.Images, r.Free && r.Spend == 0 ? r.Label : Format.Money(r.Spend), (double)r.Images / top, (Brush)ProviderStyle.Brush(r.Id))));
    }

    UIElement Projects(List<LogItem> list)
    {
        var rows = list.GroupBy(e => e.Project)
            .Select(g => (Name: g.Key, Images: g.Sum(e => e.ImageCount), Spend: g.Sum(e => e.Cost)))
            .OrderByDescending(r => r.Images).Take(6).ToList();
        int top = Math.Max(1, rows.Count > 0 ? rows.Max(r => r.Images) : 1);
        var fill = (Brush)Application.Current.Resources["TextFillColorPrimaryBrush"];
        return ListCard("", "Projects", rows.Select(r => (r.Name, r.Images, Format.Money(r.Spend), (double)r.Images / top, fill)));
    }

    static UIElement ListCard(string glyph, string title, IEnumerable<(string Name, int Images, string Spend, double Fraction, Brush Fill)> rows)
    {
        var head = Ui.Columns((Ui.Row(10, Ui.Icon(glyph, 16), Center(Ui.Text(title, 15, bold: true))), Ui.Star()),
                              (Ui.Faint("Images"), Ui.Px(70)), (Ui.Faint("Spend"), Ui.Px(70)));
        ((TextBlock)head.Children[1]).TextAlignment = TextAlignment.Right;
        ((TextBlock)head.Children[2]).TextAlignment = TextAlignment.Right;
        var body = Ui.Column(14, head);
        foreach (var r in rows)
        {
            var images = Ui.Text(Format.Count(r.Images), 14);
            images.TextAlignment = TextAlignment.Right;
            var spend = Ui.Muted(r.Spend, 14);
            spend.TextAlignment = TextAlignment.Right;
            var line = Ui.Columns((Ui.Text(r.Name, 14), Ui.Star()), (images, Ui.Px(70)), (spend, Ui.Px(70)));
            body.Children.Add(Ui.Column(7, line, Ui.Bar(r.Fraction, r.Fill, 4)));
        }
        return Ui.Card(body);
    }

    UIElement EmptyState()
    {
        var button = Ui.LabelButton("", "Generate an image", (_, _) => App.Window?.OpenGenerate(), accent: true);
        button.HorizontalAlignment = HorizontalAlignment.Center;
        var col = Ui.Column(10,
            Ui.Text("No images yet", 22, bold: true),
            Ui.Muted("Connect a provider in Settings, or make your first image now.", 14),
            button);
        foreach (var c in col.Children.OfType<TextBlock>()) c.HorizontalAlignment = HorizontalAlignment.Center;
        col.Padding = new Thickness(40);
        return new Border { Style = Ui.GetStyle("HeroStyle"), Child = col, Margin = new Thickness(0, 40, 0, 0) };
    }
}
