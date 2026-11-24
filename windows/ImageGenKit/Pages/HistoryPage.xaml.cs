using ImageGenKit.Controls;
using ImageGenKit.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;

namespace ImageGenKit.Pages;

public sealed class HistoryRow
{
    public required LogItem Entry { get; init; }
    public BitmapImage? Thumb { get; init; }
    public string Date => Format.DateTimeShort(Entry.Date);
    public string Provider => Store.Shared.Label(Entry.Provider);
    public SolidColorBrush Dot => ProviderStyle.Brush(Entry.Provider);
    public string Kind => Entry.KindLabel;
    public string Model => Entry.Model;
    public string Images => Entry.ImageCount.ToString();
    public string Size => Entry.Size;
    public string Cost => Entry.CostLabel;
    public string Time => Format.Seconds(Entry.Seconds);
}

public sealed partial class HistoryPage : Page, IRefreshable
{
    LogItem? selected;
    int selectedIndex;
    bool? compact;

    public HistoryPage()
    {
        InitializeComponent();
        Loaded += (_, _) => Refresh();
    }

    public void Refresh()
    {
        var rows = Store.Shared.Filtered(search: true).Take(1000).Select(e => new HistoryRow
        {
            Entry = e,
            Thumb = e.Picture(0) is { } p ? Bitmap(p) : null,
        }).ToList();
        Rows.ItemsSource = rows;
        Empty.Visibility = rows.Count == 0 && Store.Shared.Loaded ? Visibility.Visible : Visibility.Collapsed;
        if (selected is null && App.Options.SelectLatest && rows.Count > 0) selected = rows[0].Entry;
        ShowInspector();
    }

    /// Narrow table (the details panel is open, or the window is small): only date, provider, model and cost.
    void TableHost_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        bool narrow = e.NewSize.Width < 900;
        if (narrow == compact) return;
        compact = narrow;
        Table.MinWidth = narrow ? 540 : 880;
        WideHead.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        CompactHead.Visibility = narrow ? Visibility.Visible : Visibility.Collapsed;
        Rows.ItemTemplate = (DataTemplate)Resources[narrow ? "CompactRow" : "WideRow"];
    }

    static BitmapImage? Bitmap(string path)
    {
        try { return new BitmapImage(new Uri(path)) { DecodePixelWidth = 80, DecodePixelType = DecodePixelType.Physical }; }
        catch (Exception) { return null; }
    }

    void Rows_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is HistoryRow r)
        {
            selected = r.Entry;
            selectedIndex = 0;
            ShowInspector();
        }
    }

    void ShowInspector()
    {
        if (selected is null)
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
        var content = (FrameworkElement)Inspector.Build(selected, selectedIndex, i => { selectedIndex = i; ShowInspector(); });
        Grid.SetRow(content, 1);
        panel.Children.Add(content);
        InspectorHost.Child = panel;
    }
}
