using ImageGenKit.Controls;
using ImageGenKit.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Data;
using Microsoft.UI.Xaml.Media.Imaging;

namespace ImageGenKit.Pages;

public sealed class GalleryTile
{
    public required LogItem Entry { get; init; }
    public required int Index { get; init; }
    public BitmapImage? Image { get; init; }
    public string Tip => Entry.Prompt.Length > 140 ? Entry.Prompt[..140] + "…" : Entry.Prompt;
}

public sealed class DayGroup : List<GalleryTile>
{
    public required string Title { get; init; }
    public string CountText => Format.Count(base.Count);
}

public sealed partial class GalleryPage : Page, IRefreshable
{
    (LogItem Entry, int Index)? selected;

    public GalleryPage()
    {
        InitializeComponent();
        Loaded += (_, _) => Refresh();
    }

    public void Refresh()
    {
        var s = Store.Shared;
        var groups = s.Filtered(search: true)
            .Where(e => e.ImageCount > 0)
            .GroupBy(e => e.Date.Date)
            .OrderByDescending(g => g.Key)
            .Select(g =>
            {
                var day = new DayGroup { Title = Format.Day(g.Key) };
                foreach (var e in g.OrderByDescending(e => e.Date))
                    for (int i = 0; i < e.ImageCount; i++)
                    {
                        var path = e.Picture(i);
                        if (path is null) continue;
                        day.Add(new GalleryTile { Entry = e, Index = i, Image = Bitmap(path) });
                    }
                return day;
            })
            .Where(d => d.Count > 0)
            .ToList();
        Tiles.ItemsSource = new CollectionViewSource { IsSourceGrouped = true, Source = groups }.View;
        bool empty = groups.Count == 0 && s.Loaded;
        Empty.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        EmptyHint.Text = s.Log.Count == 0 ? "Images you or your agents make show up here." : "Try another time range or provider.";

        if (selected is null && App.Options.SelectLatest && groups.Count > 0 && groups[0].Count > 0)
            selected = (groups[0][0].Entry, groups[0][0].Index);
        ShowInspector();
    }

    static BitmapImage? Bitmap(string path)
    {
        try { return new BitmapImage(new Uri(path)) { DecodePixelWidth = 300, DecodePixelType = DecodePixelType.Physical }; }
        catch (Exception) { return null; }
    }

    void Tiles_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is GalleryTile t)
        {
            selected = (t.Entry, t.Index);
            ShowInspector();
        }
    }

    void ShowInspector()
    {
        if (selected is not { } sel)
        {
            InspectorColumn.Width = new GridLength(0);
            InspectorHost.Child = null;
            return;
        }
        InspectorColumn.Width = new GridLength(400);
        var close = Ui.IconButton("", "Close", (_, _) => { selected = null; ShowInspector(); });
        close.HorizontalAlignment = HorizontalAlignment.Right;
        close.Margin = new Thickness(0, 12, 16, 4);
        var panel = new Grid();
        panel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        panel.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        panel.Children.Add(close);
        var content = (FrameworkElement)Inspector.Build(sel.Entry, sel.Index, i => { selected = (sel.Entry, i); ShowInspector(); });
        Grid.SetRow(content, 1);
        panel.Children.Add(content);
        InspectorHost.Child = panel;
    }
}
