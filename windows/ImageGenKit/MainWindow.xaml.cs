using ImageGenKit.Pages;
using ImageGenKit.Services;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.Graphics;

namespace ImageGenKit;

public sealed partial class MainWindow : Window
{
    static readonly Dictionary<string, (Type Page, string Title)> Pages = new()
    {
        ["overview"] = (typeof(OverviewPage), "Overview"),
        ["gallery"] = (typeof(GalleryPage), "Gallery"),
        ["history"] = (typeof(HistoryPage), "History"),
        ["settings"] = (typeof(SettingsPage), "Settings"),
        ["generate"] = (typeof(GeneratePage), "Generate"),
    };

    string current = "";
    bool syncingFilters;

    public MainWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        SystemBackdrop = new MicaBackdrop();
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "icon.ico"));
        AppWindow.TitleBar.PreferredHeightOption = TitleBarHeightOption.Tall;
        var o = App.Options;
        if (o.Theme is "dark" or "light")
            Root.RequestedTheme = o.Theme == "dark" ? ElementTheme.Dark : ElementTheme.Light;
        Resize(o.Width, o.Height);
        AppWindow.SetPresenter(AppWindowPresenterKind.Overlapped);
        if (AppWindow.Presenter is OverlappedPresenter op) { op.PreferredMinimumWidth = 960; op.PreferredMinimumHeight = 620; }

        RangeFilter.SelectedIndex = 1;
        ProviderFilter.Items.Add(new ComboBoxItem { Content = "All Providers", Tag = "" });
        ProviderFilter.SelectedIndex = 0;
        Store.Shared.Changed += () => DispatcherQueue.TryEnqueue(Refresh);
        Root.Loaded += async (_, _) =>
        {
            Navigate(o.Page);
            await Store.Shared.LoadAsync();
            KeepCommandCurrent();
            await Updater.Shared.CheckAsync(quiet: true);
        };
        Updater.Shared.Changed += () => DispatcherQueue.TryEnqueue(() =>
        {
            var u = Updater.Shared;
            UpdateBar.Message = u.State == Updater.Phase.Downloading ? $"Downloading ImageGenKit {u.Latest}…" : $"ImageGenKit {u.Latest} is ready to install.";
            UpdateBar.IsOpen = u.State is Updater.Phase.Available or Updater.Phase.Downloading;
            UpdateButton.IsEnabled = u.State == Updater.Phase.Available;
        });
        Closed += (_, _) => Backend.Shared.Stop();
    }

    void Resize(int width, int height)
    {
        double scale = (Content as FrameworkElement)?.XamlRoot?.RasterizationScale ?? 1.0;
        var area = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        int w = Math.Min((int)(width * scale), area.Width), h = Math.Min((int)(height * scale), area.Height);
        AppWindow.MoveAndResize(new RectInt32(area.X + (area.Width - w) / 2, area.Y + (area.Height - h) / 2, w, h));
    }

    public void Navigate(string page, object? parameter = null)
    {
        if (!Pages.ContainsKey(page)) page = "overview";
        var item = Nav.MenuItems.OfType<NavigationViewItem>().FirstOrDefault(i => (string)i.Tag == page);
        if (item is not null && !ReferenceEquals(Nav.SelectedItem, item))
        {
            Nav.SelectedItem = item; // raises SelectionChanged
            if (parameter is null) return;
        }
        if (item is null) Nav.SelectedItem = null;
        Show(page, parameter);
    }

    void Nav_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is NavigationViewItem { Tag: string tag }) Show(tag, null);
    }

    void Show(string page, object? parameter)
    {
        if (page == current && parameter is null) return;
        current = page;
        var (type, title) = Pages[page];
        HeaderTitle.Text = title;
        Filters.Visibility = page is "overview" or "gallery" or "history" ? Visibility.Visible : Visibility.Collapsed;
        SearchBox.Visibility = page is "gallery" or "history" ? Visibility.Visible : Visibility.Collapsed;
        ContentFrame.Navigate(type, parameter, new EntranceNavigationTransitionInfo());
        UpdateSubtitle();
    }

    async void UpdateButton_Click(object sender, RoutedEventArgs e) => await Updater.Shared.InstallAsync();

    /// Once per launch: bring the imagegenkit command for agents up to the version in this app (only when installed).
    static void KeepCommandCurrent()
    {
        try { if (CommandInstaller.Outdated) Task.Run(CommandInstaller.Install); }
        catch (Exception ex) { Log.Write("command update: " + ex.Message); }
    }

    public void OpenGenerate(string? reference = null) => Navigate("generate", reference ?? "");

    void GenerateButton_Click(object sender, RoutedEventArgs e) => OpenGenerate();

    void Refresh()
    {
        var s = Store.Shared;
        int ready = s.ReadyCount;
        ReadyText.Text = !s.Loaded ? "Loading…" : ready == 0 ? "No provider set up" : ready == 1 ? "1 provider ready" : $"{ready} providers ready";
        ReadyDot.Fill = new SolidColorBrush(ready > 0 ? ColorHelper.FromArgb(255, 52, 199, 89) : ColorHelper.FromArgb(255, 255, 159, 10));

        syncingFilters = true;
        var selected = (ProviderFilter.SelectedItem as ComboBoxItem)?.Tag as string ?? "";
        while (ProviderFilter.Items.Count > 1) ProviderFilter.Items.RemoveAt(1);
        foreach (var id in s.Log.Select(e => e.Provider).Distinct().OrderBy(s.Label))
            ProviderFilter.Items.Add(new ComboBoxItem { Content = s.Label(id), Tag = id });
        ProviderFilter.SelectedItem = ProviderFilter.Items.OfType<ComboBoxItem>().FirstOrDefault(i => (string)i.Tag == selected) ?? ProviderFilter.Items[0];
        syncingFilters = false;

        ErrorBar.Message = s.Error ?? "";
        ErrorBar.Title = s.Error is null ? "" : "Couldn't load your images";
        ErrorBar.IsOpen = s.Error is not null;
        UpdateSubtitle();
        (ContentFrame.Content as IRefreshable)?.Refresh();
    }

    public void UpdateSubtitle()
    {
        var s = Store.Shared;
        HeaderSub.Text = current switch
        {
            "gallery" => s.Loaded ? $"{Format.Count(s.Filtered(true).Sum(e => e.ImageCount))} images" : "",
            "history" => s.Loaded ? $"{Format.Count(s.Filtered(true).Count())} runs" : "",
            _ => "",
        };
        HeaderSub.Visibility = HeaderSub.Text.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    void Filter_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (syncingFilters || ProviderFilter is null || RangeFilter is null) return;
        Store.Shared.ProviderFilter = (ProviderFilter.SelectedItem as ComboBoxItem)?.Tag as string ?? "";
        Store.Shared.RangeDays = int.TryParse((RangeFilter.SelectedItem as ComboBoxItem)?.Tag as string, out var d) ? d : 30;
        UpdateSubtitle();
        (ContentFrame.Content as IRefreshable)?.Refresh();
    }

    void SearchBox_TextChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args)
    {
        Store.Shared.Search = sender.Text;
        UpdateSubtitle();
        (ContentFrame.Content as IRefreshable)?.Refresh();
    }

    public void ShowError(string title, string message)
    {
        ErrorBar.Title = title;
        ErrorBar.Message = message;
        ErrorBar.IsOpen = true;
    }
}

/// Pages that redraw when the data or the filters change.
public interface IRefreshable
{
    void Refresh();
}
