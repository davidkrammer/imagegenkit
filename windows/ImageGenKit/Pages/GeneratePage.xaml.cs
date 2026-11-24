using System.Text.Json;
using CommunityToolkit.WinUI.Controls;
using ImageGenKit.Controls;
using ImageGenKit.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using Windows.Storage.Pickers;

namespace ImageGenKit.Pages;

public sealed partial class GeneratePage : Page, IRefreshable
{
    // Kept for the session, like the Mac app's GenerateSession.
    static string providerId = "";
    static string prompt = "";
    static readonly List<string> refs = [];
    static string aspect = GenerateSpec.Auto, size = "", quality = "auto", background = "auto", format = "png", model = "";
    static int count = 1;
    static List<string> results = [];

    TextBox? promptBox;
    StackPanel? refsRow;
    string? jobId;
    List<(string Name, bool Edit)> localModels = [];
    bool running;

    public GeneratePage()
    {
        InitializeComponent();
        Loaded += async (_, _) =>
        {
            if (App.Options.Prompt is { } p && prompt.Length == 0) prompt = p;
            Refresh();
            await LoadLocalModels();
        };
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        if (e.Parameter is string path && path.Length > 0 && !refs.Contains(path)) refs.Add(path);
    }

    List<ProviderRow> Ready
    {
        get
        {
            var s = Store.Shared;
            var order = s.Enabled;
            return s.Providers.Where(p => p.Ready).OrderBy(p => order.IndexOf(p.Name) is var i && i >= 0 ? i : 99).ToList();
        }
    }

    ProviderRow? Provider
    {
        get
        {
            var ready = Ready;
            if (ready.FirstOrDefault(p => p.Name == providerId) is { } chosen) return chosen;
            var draft = Store.Shared.State.Obj("tasks").Obj("draft").Str("provider");
            return ready.FirstOrDefault(p => p.Name == draft) ?? ready.FirstOrDefault();
        }
    }

    public void Refresh()
    {
        if (running) return;
        Body.Children.Clear();
        if (!Store.Shared.Loaded)
        {
            Body.Children.Add(new ProgressRing { IsActive = true, Margin = new Thickness(0, 60, 0, 0) });
            return;
        }
        Body.Children.Add(PromptCard());
        var p = Provider;
        if (p is null) Body.Children.Add(NoProvider());
        else Body.Children.Add(OptionsCard(p));
        Body.Children.Add(results.Count > 0 ? ResultsCard() : Stage());
        RunButton.IsEnabled = p is not null;
        if (StatusText.Text.Length == 0) SetStatus(p is null ? "" : "Ctrl+Enter to generate");
    }

    // ---------- prompt & references ----------

    UIElement PromptCard()
    {
        promptBox = new TextBox
        {
            Text = prompt, PlaceholderText = "Describe the image: subject, setting, style, light…", AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap, MinHeight = 112, FontSize = 15,
        };
        promptBox.TextChanged += (_, _) => prompt = promptBox.Text;
        refsRow = Ui.Row(10);
        RebuildRefs();
        var add = Ui.LabelButton("", "Add Reference", async (_, _) => await PickReferences());
        var hint = Ui.Faint("or drop images here", 12);
        hint.VerticalAlignment = VerticalAlignment.Center;
        var col = Ui.Column(12, promptBox, Ui.Row(12, add, hint), refsRow);
        var card = Ui.Card(col);
        card.AllowDrop = true;
        card.DragOver += (_, e) => { e.AcceptedOperation = DataPackageOperation.Copy; e.DragUIOverride.Caption = "Use as reference"; };
        card.Drop += async (_, e) =>
        {
            if (!e.DataView.Contains(StandardDataFormats.StorageItems)) return;
            var deferral = e.GetDeferral();
            try
            {
                foreach (var item in await e.DataView.GetStorageItemsAsync())
                    if (item is StorageFile f) await AddReference(f.Path);
            }
            finally { deferral.Complete(); }
        };
        return card;
    }

    void RebuildRefs()
    {
        if (refsRow is null) return;
        refsRow.Children.Clear();
        refsRow.Visibility = refs.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        foreach (var r in refs.ToList())
        {
            var tile = Ui.Tile(r, 72, 72, 144, 10);
            var remove = new Button
            {
                Content = Ui.Icon("", 10), Padding = new Thickness(5), CornerRadius = new CornerRadius(999),
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, -6, -6, 0),
            };
            ToolTipService.SetToolTip(remove, "Remove");
            remove.Click += (_, _) => { refs.Remove(r); RebuildRefs(); Refresh(); };
            var g = new Grid();
            g.Children.Add(tile);
            g.Children.Add(remove);
            refsRow.Children.Add(g);
        }
    }

    async Task PickReferences()
    {
        var picker = new FileOpenPicker { ViewMode = PickerViewMode.Thumbnail, SuggestedStartLocation = PickerLocationId.PicturesLibrary };
        foreach (var ext in new[] { ".png", ".jpg", ".jpeg", ".webp", ".heic", ".bmp", ".gif" }) picker.FileTypeFilter.Add(ext);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(App.Window!));
        var files = await picker.PickMultipleFilesAsync();
        foreach (var f in files) await AddReference(f.Path);
    }

    async Task AddReference(string path)
    {
        try
        {
            // The backend only uses images it knows: files from the log, or copies in its uploads folder.
            bool known = Store.Shared.Log.Any(e => e.Outputs.Contains(path));
            string usable = known ? path : await Backend.Shared.UploadAsync(path);
            if (!refs.Contains(usable)) refs.Add(usable);
            RebuildRefs();
            Refresh();
        }
        catch (Exception ex) { SetStatus(ex.Message, error: true); }
    }

    // ---------- options ----------

    UIElement NoProvider()
    {
        var go = Ui.LabelButton("", "Open Settings", (_, _) => App.Window?.Navigate("settings"), accent: true);
        return Ui.Card(Ui.Columns(
            (Ui.Badge("", Ui.Hex(0x8E8E93), 44), Ui.Auto),
            (Ui.Column(3, Ui.Text("No provider yet", 15, bold: true), Ui.Muted("Add a Grok, ChatGPT or API account, or a model on this PC.")), Ui.Star()),
            (go, Ui.Auto)));
    }

    UIElement OptionsCard(ProviderRow p)
    {
        var grid = new Grid { RowSpacing = 14, ColumnSpacing = 18 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(92) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        int row = 0;
        void Add(string label, UIElement control)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var l = Ui.Muted(label, 13);
            l.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetRow(l, row);
            Grid.SetRow((FrameworkElement)control, row);
            Grid.SetColumn((FrameworkElement)control, 1);
            grid.Children.Add(l);
            grid.Children.Add(control);
            row++;
        }

        // Provider chips
        var wrap = Ui.Row(8);
        foreach (var r in Ready)
        {
            var chip = new ToggleButton
            {
                IsChecked = r.Name == p.Name, CornerRadius = new CornerRadius(999), Padding = new Thickness(12, 6, 14, 6),
                Content = Ui.Row(7, Ui.Dot(ProviderStyle.ColorOf(r.Name, ProviderStyle.IsDark)), Ui.Text(r.Label, 13)),
            };
            chip.Click += (_, _) => { providerId = r.Name; Refresh(); };
            wrap.Children.Add(chip);
        }
        Add("Provider", new ScrollViewer { Content = wrap, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled, HorizontalScrollMode = ScrollMode.Auto, VerticalScrollMode = ScrollMode.Disabled });

        if (p.IsLocal)
        {
            var choices = refs.Count > 0 ? localModels.Where(m => m.Edit).ToList() : localModels;
            if (choices.Count == 0)
            {
                var none = Ui.Text(refs.Count > 0 ? "No downloaded model can edit images" : "No model downloaded", 13);
                none.Foreground = new SolidColorBrush(Ui.Hex(0xFF9F0A));
                Add("Model", none);
            }
            else
            {
                if (!choices.Any(c => c.Name == model)) model = choices[0].Name;
                var box = new ComboBox { MinWidth = 260 };
                foreach (var c in choices) box.Items.Add(c.Name);
                box.SelectedItem = model;
                box.SelectionChanged += (_, _) => model = box.SelectedItem as string ?? model;
                Add("Model", box);
            }
        }

        var aspects = GenerateSpec.Aspects(p.Type);
        if (!aspects.Contains(aspect)) aspect = GenerateSpec.Auto;
        var aspectBox = new ComboBox { MinWidth = 140 };
        foreach (var a in aspects) aspectBox.Items.Add(a);
        aspectBox.SelectedItem = aspect;
        aspectBox.SelectionChanged += (_, _) =>
        {
            aspect = aspectBox.SelectedItem as string ?? GenerateSpec.Auto;
            if (results.Count == 0 && Body.Children.Count > 0) Body.Children[^1] = Stage();
        };
        Add("Aspect", aspectBox);

        var sizes = GenerateSpec.Sizes(p.Type);
        if (sizes.Length > 0)
        {
            if (!sizes.Contains(size)) size = sizes[Math.Min(1, sizes.Length - 1)];
            Add("Size", Segments(sizes, size, v => size = v));
        }
        Add("Images", Segments(["1", "2", "3", "4"], count.ToString(), v => count = int.Parse(v)));

        var qualities = GenerateSpec.Qualities(p.Type);
        if (qualities.Length > 0)
        {
            if (!qualities.Contains(quality)) quality = "auto";
            Add("Quality", Segments(qualities, quality, v => quality = v, GenerateSpec.Cap));
        }
        var backgrounds = GenerateSpec.Backgrounds(p.Type);
        if (backgrounds.Length > 0)
        {
            if (!backgrounds.Contains(background)) background = "auto";
            Add("Background", Segments(backgrounds, background, v => background = v, GenerateSpec.Cap));
        }
        var formats = GenerateSpec.Formats(p.Type);
        if (formats.Length > 0)
        {
            if (!formats.Contains(format)) format = "png";
            Add("Format", Segments(formats, format, v => format = v, GenerateSpec.FormatLabel));
        }
        return Ui.Card(grid);
    }

    static Segmented Segments(string[] options, string current, Action<string> set, Func<string, string>? label = null)
    {
        var seg = new Segmented { HorizontalAlignment = HorizontalAlignment.Left };
        foreach (var o in options) seg.Items.Add(new SegmentedItem { Content = label?.Invoke(o) ?? o, Tag = o });
        seg.SelectedIndex = Math.Max(0, Array.IndexOf(options, current));
        seg.SelectionChanged += (_, _) => { if (seg.SelectedItem is SegmentedItem { Tag: string t }) set(t); };
        return seg;
    }

    async Task LoadLocalModels()
    {
        if (!Store.Shared.Providers.Any(p => p.IsLocal && p.Ready)) return;
        try
        {
            var data = await Backend.Shared.GetAsync("/api/local");
            localModels = data.Arr("models").Where(m => m.Bool("ready")).Select(m => (m.Str("name"), m.Bool("edit"))).ToList();
            if (Provider?.IsLocal == true) Refresh();
        }
        catch (Exception ex) { Log.Write("local models: " + ex.Message); }
    }

    // ---------- run ----------

    async void Run_Click(object sender, RoutedEventArgs e)
    {
        var p = Provider;
        if (running || p is null) return;
        if (string.IsNullOrWhiteSpace(prompt)) { SetStatus("Write a prompt first.", error: true); promptBox?.Focus(FocusState.Programmatic); return; }
        var body = new Dictionary<string, object?>
        {
            ["target"] = p.Name, ["prompt"] = prompt.Trim(), ["n"] = count, ["refs"] = refs.ToList(),
        };
        if (aspect != GenerateSpec.Auto) body["aspect"] = aspect;
        if (GenerateSpec.Sizes(p.Type).Contains(size)) body["resolution"] = size;
        if (p.IsLocal && model.Length > 0) body["model"] = model;
        if (GenerateSpec.Qualities(p.Type).Contains(quality) && quality != "auto") body["quality"] = quality;
        if (GenerateSpec.Backgrounds(p.Type).Contains(background) && background != "auto") body["background"] = background;
        if (GenerateSpec.Formats(p.Type).Contains(format) && format != "png") body["format"] = format;

        SetRunning(true);
        SetStatus("Starting…");
        try
        {
            var job = await Backend.Shared.PostAsync("/api/generate", body);
            jobId = job.Str("id");
            await Poll();
        }
        catch (Exception ex)
        {
            SetRunning(false);
            SetStatus(ex.Message, error: true);
        }
    }

    async Task Poll()
    {
        var started = DateTime.Now;
        while (jobId is not null)
        {
            JsonElement j;
            try { j = await Backend.Shared.GetAsync($"/api/jobs/{jobId}"); }
            catch (Exception ex) { SetRunning(false); SetStatus(ex.Message, error: true); return; }
            var status = j.Str("status");
            var lines = j.Strings("lines").Where(l => l is not null).Select(l => l!).ToList();
            if (status == "running")
            {
                var progress = lines.AsEnumerable().Reverse().Select(l => GenerateSpec.Progress(l, count)).FirstOrDefault(x => x is not null);
                int secs = (int)(DateTime.Now - started).TotalSeconds;
                if (progress is { } pr)
                {
                    Progress.Visibility = pr.Fraction is null ? Visibility.Collapsed : Visibility.Visible;
                    Progress.Value = (pr.Fraction ?? 0) * 100;
                    SetStatus($"{pr.Text} · {secs} s");
                }
                else SetStatus($"Generating · {secs} s");
                await Task.Delay(400);
                continue;
            }
            jobId = null;
            SetRunning(false);
            if (status == "done")
            {
                results = j.Strings("outputs").Where(o => o is not null && File.Exists(o)).Select(o => o!).ToList();
                SetStatus($"{results.Count} image{(results.Count == 1 ? "" : "s")} in {Math.Round(j.Num("seconds"))} s");
                await Store.Shared.LoadAsync();
                Refresh();
            }
            else if (status == "cancelled") SetStatus("Stopped.");
            else SetStatus(lines.LastOrDefault(l => !l.StartsWith("  ")) ?? lines.LastOrDefault() ?? "Something went wrong.", error: true);
        }
    }

    async void Cancel_Click(object sender, RoutedEventArgs e)
    {
        if (jobId is null) return;
        try { await Backend.Shared.PostAsync($"/api/jobs/{jobId}/cancel"); } catch (Exception ex) { Log.Write("cancel: " + ex.Message); }
    }

    void SetRunning(bool on)
    {
        running = on;
        Spinner.IsActive = on;
        Spinner.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        if (!on) Progress.Visibility = Visibility.Collapsed;
        CancelButton.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        RunButton.IsEnabled = !on;
        RunText.Text = on ? "Generating" : results.Count > 0 ? "Generate Again" : "Generate";
    }

    void SetStatus(string text, bool error = false)
    {
        StatusText.Text = text;
        StatusText.Foreground = error ? new SolidColorBrush(Ui.Hex(0xE34948)) : (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
    }

    // ---------- results ----------

    /// Before the first image: a frame in the chosen aspect ratio where the results will appear.
    UIElement Stage()
    {
        double w = 1, h = 1;
        var parts = aspect.Split(':');
        if (parts.Length == 2 && double.TryParse(parts[0], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var a)
            && double.TryParse(parts[1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var b) && a > 0 && b > 0)
        { w = a; h = b; }
        double height = 230, width = Math.Min(420, height * w / h);
        if (width < height * w / h) height = width * h / w;
        var inner = Ui.Column(10);
        inner.HorizontalAlignment = HorizontalAlignment.Center;
        inner.VerticalAlignment = VerticalAlignment.Center;
        var spark = new PathIcon { Data = (Geometry)Microsoft.UI.Xaml.Markup.XamlBindingHelper.ConvertValue(typeof(Geometry), "M7,0 L8.4,5.6 L14,7 L8.4,8.4 L7,14 L5.6,8.4 L0,7 L5.6,5.6 Z"), Width = 14, Height = 14, Opacity = 0.45, HorizontalAlignment = HorizontalAlignment.Center };
        inner.Children.Add(new Viewbox { Width = 28, Height = 28, Child = spark });
        var hint = Ui.Faint(aspect == GenerateSpec.Auto ? "Your images appear here" : $"{aspect} · Your images appear here", 12);
        hint.HorizontalAlignment = HorizontalAlignment.Center;
        inner.Children.Add(hint);
        var frame = new Border
        {
            Width = width, Height = height, CornerRadius = new CornerRadius(14), Style = Ui.GetStyle("TileStyle"),
            BorderThickness = new Thickness(1.5), Child = inner, HorizontalAlignment = HorizontalAlignment.Center,
        };
        var card = Ui.Card(frame);
        card.Padding = new Thickness(20, 26, 20, 26);
        return card;
    }

    UIElement ResultsCard()
    {
        var wrap = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, ItemWidth = 300, ItemHeight = 356 };
        foreach (var path in results)
        {
            var tile = Ui.Tile(path, 284, 284, 568, 12);
            var actions = Ui.Row(6,
                Ui.IconButton("", "Open", (_, _) => Inspector.Open(path)),
                Ui.IconButton("", "Show in File Explorer", (_, _) => Inspector.Reveal(path)),
                Ui.IconButton("", "Copy Path", (_, _) => Inspector.CopyPath(path)),
                Ui.LabelButton("", "Use as Reference", (_, _) => { if (!refs.Contains(path)) refs.Add(path); Refresh(); }));
            actions.Margin = new Thickness(0, 10, 0, 0);
            wrap.Children.Add(Ui.Column(0, tile, actions));
        }
        var head = Ui.Row(10, Ui.Icon("", 16), Ui.Text("Results", 15, bold: true));
        return Ui.Card(Ui.Column(14, head, wrap));
    }
}
