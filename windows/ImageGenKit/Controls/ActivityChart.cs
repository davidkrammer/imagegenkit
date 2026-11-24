using ImageGenKit.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace ImageGenKit.Controls;

/// Stacked bars per day (or week / month for long ranges), one segment per provider in fixed colors.
public sealed class ActivityChart : Grid
{
    public sealed record Bucket(DateTime Start, string Label, Dictionary<string, double> Values);

    readonly Canvas canvas = new();
    List<Bucket> buckets = [];
    List<string> order = [];
    bool money;

    public ActivityChart()
    {
        Height = 230;
        Children.Add(canvas);
        SizeChanged += (_, _) => Draw();
    }

    public void SetData(List<Bucket> data, List<string> providerOrder, bool isMoney)
    {
        buckets = data;
        order = providerOrder;
        money = isMoney;
        Draw();
    }

    void Draw()
    {
        canvas.Children.Clear();
        double w = ActualWidth, h = ActualHeight;
        if (w < 50 || buckets.Count == 0) return;
        const double left = 40, bottom = 24, top = 8;
        double plotH = h - bottom - top, plotW = w - left;
        double max = Math.Max(buckets.Max(b => b.Values.Values.Sum()), money ? 0.01 : 1);
        double step = NiceStep(max / 3);
        double ceiling = Math.Ceiling(max / step) * step;

        for (int i = 0; i <= 3; i++)
        {
            double v = step * i;
            if (v > ceiling + 1e-9) break;
            double y = top + plotH - plotH * (v / ceiling);
            var line = new Microsoft.UI.Xaml.Shapes.Rectangle { Style = Ui.GetStyle("GridLineStyle"), Width = plotW };
            Canvas.SetLeft(line, left);
            Canvas.SetTop(line, y);
            canvas.Children.Add(line);
            var label = Ui.Faint(money ? (v == 0 ? "$0" : Format.Money(v)) : Format.Compact(v), 11);
            label.Width = left - 8;
            label.TextAlignment = TextAlignment.Right;
            Canvas.SetLeft(label, 0);
            Canvas.SetTop(label, y - 8);
            canvas.Children.Add(label);
        }

        double slot = plotW / buckets.Count;
        double barW = Math.Clamp(slot * 0.62, 3, 26);
        int labelEvery = Math.Max(1, (int)Math.Ceiling(buckets.Count / Math.Max(1, plotW / 70)));
        for (int i = 0; i < buckets.Count; i++)
        {
            var b = buckets[i];
            double x = left + slot * i + (slot - barW) / 2;
            double y = top + plotH;
            var parts = order.Where(p => b.Values.TryGetValue(p, out var v) && v > 0).ToList();
            for (int k = 0; k < parts.Count; k++)
            {
                double v = b.Values[parts[k]];
                double segH = Math.Max(2, plotH * (v / ceiling));
                y -= segH;
                bool topmost = k == parts.Count - 1;
                var seg = new Border
                {
                    Width = barW, Height = segH,
                    Background = ProviderStyle.Brush(parts[k]),
                    CornerRadius = topmost ? new CornerRadius(Math.Min(4, barW / 2), Math.Min(4, barW / 2), 0, 0) : new CornerRadius(0),
                };
                Canvas.SetLeft(seg, x);
                Canvas.SetTop(seg, y);
                canvas.Children.Add(seg);
                if (k < parts.Count - 1) y -= 1.5; // a hairline gap between providers
            }
            if (parts.Count > 0)
            {
                var hit = new Border { Width = slot, Height = plotH, Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent) };
                var lines = parts.Select(p => $"{Store.Shared.Label(p)}: {(money ? Format.Money(b.Values[p]) : Format.Count((int)b.Values[p]))}");
                ToolTipService.SetToolTip(hit, $"{b.Label}\n{string.Join("\n", lines)}");
                Canvas.SetLeft(hit, left + slot * i);
                Canvas.SetTop(hit, top);
                canvas.Children.Add(hit);
            }
            if (i % labelEvery == 0 && i + labelEvery / 2 < buckets.Count)
            {
                var t = Ui.Faint(b.Label, 11);
                t.Width = 80;
                t.TextAlignment = TextAlignment.Center;
                Canvas.SetLeft(t, left + slot * i + slot / 2 - 40);
                Canvas.SetTop(t, top + plotH + 6);
                canvas.Children.Add(t);
            }
        }
    }

    static double NiceStep(double raw)
    {
        if (raw <= 0) return 1;
        double mag = Math.Pow(10, Math.Floor(Math.Log10(raw)));
        double n = raw / mag;
        return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10) * mag;
    }
}
