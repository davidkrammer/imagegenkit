using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;

namespace ImageGenKit.Controls;

/// Small builders for the pages (cards, text, badges, pills, bars), so every page uses the same pieces.
public static class Ui
{
    public static T Res<T>(string key) => (T)Application.Current.Resources[key];

    public static Style GetStyle(string key) => Res<Style>(key);

    public static Border Card(UIElement child, double padding = -1)
    {
        var b = new Border { Style = GetStyle("CardStyle"), Child = child };
        if (padding >= 0) b.Padding = new Thickness(padding);
        return b;
    }

    public static TextBlock Text(string text, double size = 14, bool bold = false, double opacity = 1)
    {
        var t = new TextBlock { Text = text, FontSize = size, TextTrimming = TextTrimming.CharacterEllipsis, Opacity = opacity };
        if (bold) t.FontWeight = FontWeights.SemiBold;
        return t;
    }

    public static TextBlock Muted(string text, double size = 13)
    {
        var t = Text(text, size);
        t.Style = GetStyle("MutedTextStyle");
        t.FontSize = size;
        return t;
    }

    public static TextBlock Faint(string text, double size = 12)
    {
        var t = Text(text, size);
        t.Style = GetStyle("FaintTextStyle");
        t.FontSize = size;
        return t;
    }

    public static StackPanel Row(double spacing, params UIElement[] children)
    {
        var s = new StackPanel { Orientation = Orientation.Horizontal, Spacing = spacing };
        foreach (var c in children) s.Children.Add(c);
        return s;
    }

    public static StackPanel Column(double spacing, params UIElement[] children)
    {
        var s = new StackPanel { Spacing = spacing };
        foreach (var c in children) s.Children.Add(c);
        return s;
    }

    public static FontIcon Icon(string glyph, double size = 16) => new() { Glyph = glyph, FontSize = size };

    /// An icon in a tinted rounded square (the Mac app's IconBadge).
    public static Border Badge(string glyph, Color color, double size = 34)
    {
        var icon = Icon(glyph, size * 0.45);
        icon.Foreground = new SolidColorBrush(color);
        return new Border
        {
            Width = size, Height = size, CornerRadius = new CornerRadius(size * 0.28),
            Background = new SolidColorBrush(Color.FromArgb(38, color.R, color.G, color.B)),
            Child = icon,
        };
    }

    public static Border BadgeText(string text, Color color, double size = 34)
    {
        var t = Text(text, size * 0.45, bold: true);
        t.Foreground = new SolidColorBrush(color);
        t.HorizontalAlignment = HorizontalAlignment.Center;
        t.VerticalAlignment = VerticalAlignment.Center;
        return new Border
        {
            Width = size, Height = size, CornerRadius = new CornerRadius(size * 0.28),
            Background = new SolidColorBrush(Color.FromArgb(38, color.R, color.G, color.B)),
            Child = t,
        };
    }

    public static Border Pill(string text, Color? dot = null)
    {
        var content = Row(6);
        if (dot is { } c) content.Children.Add(new Ellipse { Width = 7, Height = 7, Fill = new SolidColorBrush(c), VerticalAlignment = VerticalAlignment.Center });
        var t = Text(text, 12);
        t.Style = GetStyle("MutedTextStyle");
        t.FontSize = 12;
        content.Children.Add(t);
        return new Border { Style = GetStyle("PillStyle"), Child = content, VerticalAlignment = VerticalAlignment.Center };
    }

    public static Ellipse Dot(Color c, double size = 8) =>
        new() { Width = size, Height = size, Fill = new SolidColorBrush(c), VerticalAlignment = VerticalAlignment.Center };

    /// A rounded progress track filled to `fraction`.
    public static Grid Bar(double fraction, Brush fill, double height = 6)
    {
        fraction = Math.Clamp(fraction, 0, 1);
        var g = new Grid { Height = height };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(fraction, 0.0001), GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(1 - fraction, 0.0001), GridUnitType.Star) });
        var track = new Border { Style = GetStyle("TrackStyle") };
        Grid.SetColumnSpan(track, 2);
        g.Children.Add(track);
        if (fraction > 0) g.Children.Add(new Border { Background = fill, CornerRadius = new CornerRadius(height / 2), MinWidth = height });
        return g;
    }

    public static Image Picture(string? path, int decodeWidth, Stretch stretch = Stretch.UniformToFill)
    {
        var img = new Image { Stretch = stretch };
        if (path is not null)
        {
            try { img.Source = new BitmapImage(new Uri(path)) { DecodePixelWidth = decodeWidth, DecodePixelType = DecodePixelType.Logical }; }
            catch (Exception) { }
        }
        return img;
    }

    /// A picture clipped to rounded corners (an Image can't round itself).
    public static Border Tile(string? path, double width, double height, int decodeWidth, double radius = 10)
    {
        return new Border
        {
            Style = GetStyle("TileStyle"),
            Width = width, Height = height, CornerRadius = new CornerRadius(radius),
            Child = Picture(path, decodeWidth),
        };
    }

    public static Grid Columns(params (UIElement Element, GridLength Width)[] cells)
    {
        var g = new Grid { ColumnSpacing = 16 };
        for (int i = 0; i < cells.Length; i++)
        {
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = cells[i].Width });
            Grid.SetColumn((FrameworkElement)cells[i].Element, i);
            g.Children.Add(cells[i].Element);
        }
        return g;
    }

    public static GridLength Star(double v = 1) => new(v, GridUnitType.Star);
    public static GridLength Auto => GridLength.Auto;
    public static GridLength Px(double v) => new(v);

    public static Button IconButton(string glyph, string tip, RoutedEventHandler click)
    {
        var b = new Button { Content = Icon(glyph, 14), Padding = new Thickness(10, 7, 10, 7) };
        ToolTipService.SetToolTip(b, tip);
        b.Click += click;
        return b;
    }

    public static Button LabelButton(string glyph, string label, RoutedEventHandler click, bool accent = false)
    {
        var b = new Button { Content = Row(8, Icon(glyph, 14), Text(label)) };
        if (accent) b.Style = Res<Style>("AccentButtonStyle");
        b.Click += click;
        return b;
    }

    public static Color Hex(uint rgb, byte alpha = 255) => Color.FromArgb(alpha, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);
}
