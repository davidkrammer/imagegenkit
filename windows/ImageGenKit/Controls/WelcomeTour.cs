using ImageGenKit.Services;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.System;
using Shapes = Microsoft.UI.Xaml.Shapes;

namespace ImageGenKit.Controls;

public enum TourDestination { None, Generate, Gallery, Settings, LocalModels }

/// The welcome tour, built like the Mac app's (David's app-intro pattern): six steps of the same height, each with a
/// moving picture, a title, a one-line lead and 2–3 points. Step 2 is a hands-on demo on sample images (nothing is
/// sent), step 4 connects a provider right there, step 5 sets up the agents. Opens once after the terms are accepted;
/// Settings › General opens it again. Closing it in any way marks it as seen.
public sealed class WelcomeTour : Grid
{
    /// Raise to show a reworked tour once more.
    public const int Version = 1;
    public static bool Seen => AppPrefs.Int("tourVersion") >= Version;

    const double CardWidth = 660, ArtHeight = 232, TextHeight = 258, FooterHeight = 64;
    const int StepCount = 6;

    readonly Action<TourDestination> close;
    readonly bool motion;
    readonly bool showMeOnOpen;
    readonly Grid pageHost = new();
    readonly StackPanel dots = new() { Orientation = Orientation.Horizontal, Spacing = 0, VerticalAlignment = VerticalAlignment.Center };
    readonly StackPanel buttons = new() { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
    int step = -1;
    int token;      // bumps on every step change, so loops of the old step stop
    bool closed;

    public WelcomeTour(int start, bool showMe, Action<TourDestination> close)
    {
        this.close = close;
        showMeOnOpen = showMe;
        try { motion = new Windows.UI.ViewManagement.UISettings().AnimationsEnabled; } catch (Exception) { motion = true; }
        Background = Ui.Res<Brush>("SmokeFillColorDefaultBrush");

        var card = new Grid();
        card.RowDefinitions.Add(new RowDefinition { Height = new GridLength(ArtHeight + TextHeight) });
        card.RowDefinitions.Add(new RowDefinition { Height = new GridLength(FooterHeight) });
        pageHost.Clip = new RectangleGeometry { Rect = new Windows.Foundation.Rect(0, 0, CardWidth, ArtHeight + TextHeight) };
        card.Children.Add(pageHost);

        var footer = new Grid { Padding = new Thickness(24, 0, 20, 0), BorderThickness = new Thickness(0, 1, 0, 0), BorderBrush = Ui.Res<Brush>("CardStrokeBrush") };
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = Ui.Star() });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = Ui.Auto });
        footer.Children.Add(dots);
        Grid.SetColumn(buttons, 1);
        footer.Children.Add(buttons);
        Grid.SetRow(footer, 1);
        card.Children.Add(footer);

        var closeButton = Ui.IconButton("\uE711", "Close (Esc)", (_, _) => Close(TourDestination.None));
        closeButton.HorizontalAlignment = HorizontalAlignment.Right;
        closeButton.VerticalAlignment = VerticalAlignment.Top;
        closeButton.Margin = new Thickness(0, 12, 12, 0);
        closeButton.Background = Ui.Res<Brush>("CardBrush");
        card.Children.Add(closeButton);

        var frame = new Border
        {
            Width = CardWidth, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            CornerRadius = new CornerRadius(14), BorderThickness = new Thickness(1),
            BorderBrush = Ui.Res<Brush>("SurfaceStrokeColorDefaultBrush"),
            Background = Ui.Res<Brush>("SolidBackgroundFillColorBaseBrush"),
            Child = new Border { Background = Ui.Res<Brush>("CardBrush"), Child = card },
        };
        Children.Add(frame);

        PreviewKeyDown += OnKey;
        Store.Shared.Changed += StoreChanged;
        Loaded += (_, _) =>
        {
            Go(Math.Clamp(start, 0, StepCount - 1));
            if (motion) { Fade(frame, 0, 1, 220); Move(frame, "TranslateY", 18, 0, 320); }
        };
    }

    // ---------- navigation ----------

    void Go(int target)
    {
        if (target < 0 || target >= StepCount || target == step || closed) return;
        bool forward = target > step;
        step = target;
        token++;
        var page = Build(step);
        pageHost.Children.Clear();
        pageHost.Children.Add(page);
        if (motion)
        {
            Fade(page, 0, 1, 240);
            Move(page, "TranslateX", forward ? 28 : -28, 0, 320);
        }
        UpdateFooter();
    }

    void UpdateFooter()
    {
        dots.Children.Clear();
        for (int i = 0; i < StepCount; i++)
        {
            int index = i;
            var mark = new Border
            {
                Width = i == step ? 20 : 8, Height = 8, CornerRadius = new CornerRadius(4),
                Background = i == step ? Ui.Res<Brush>("AccentFillColorDefaultBrush") : Ui.Res<Brush>("ControlStrongFillColorDisabledBrush"),
            };
            var dot = new Button
            {
                Content = mark, Padding = new Thickness(4, 8, 4, 8), MinWidth = 0, MinHeight = 0,
                Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent), BorderThickness = new Thickness(0),
            };
            ToolTipService.SetToolTip(dot, $"Step {i + 1} of {StepCount}");
            dot.Click += (_, _) => Go(index);
            dots.Children.Add(dot);
        }

        buttons.Children.Clear();
        if (step == StepCount - 1)
        {
            buttons.Children.Add(Plain("Settings", () => Close(TourDestination.Settings)));
            buttons.Children.Add(Plain("Open Gallery", () => Close(TourDestination.Gallery)));
            var go = Ui.LabelButton("", "Generate your first image", (_, _) => Close(TourDestination.Generate), accent: true);
            ((StackPanel)go.Content).Children[0] = Sparkle(14);
            buttons.Children.Add(go);
            go.Loaded += (_, _) => go.Focus(FocusState.Programmatic);
        }
        else
        {
            buttons.Children.Add(Plain(step == 0 ? "Skip" : "Back", () => { if (step == 0) Close(TourDestination.None); else Go(step - 1); }));
            var next = new Button { Content = "Next", Style = Ui.Res<Style>("AccentButtonStyle"), MinWidth = 96 };
            next.Click += (_, _) => Go(step + 1);
            buttons.Children.Add(next);
            if (step != 1) next.Loaded += (_, _) => next.Focus(FocusState.Programmatic);
        }
    }

    static Button Plain(string text, Action click)
    {
        var b = new Button { Content = text, MinWidth = 80 };
        b.Click += (_, _) => click();
        return b;
    }

    void OnKey(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == VirtualKey.Escape) { Close(TourDestination.None); e.Handled = true; return; }
        if (e.Key is not (VirtualKey.Left or VirtualKey.Right)) return;
        if (FocusManager.GetFocusedElement(XamlRoot) is TextBox or PasswordBox or AutoSuggestBox) return; // typing
        Go(step + (e.Key == VirtualKey.Right ? 1 : -1));
        e.Handled = true;
    }

    void Close(TourDestination destination)
    {
        if (closed) return;
        closed = true;
        token++;
        Store.Shared.Changed -= StoreChanged;
        AppPrefs.Set("tourVersion", Version);
        close(destination);
    }

    /// Providers and agents can change while the tour is open (a login in the terminal, a key, a skill).
    void StoreChanged() => DispatcherQueue.TryEnqueue(() =>
    {
        if (closed || step is not (3 or 4)) return;
        var page = Build(step);
        pageHost.Children.Clear();
        pageHost.Children.Add(page);
    });

    // ---------- page layout ----------

    UIElement Build(int i) => i switch
    {
        0 => WelcomeStep(),
        1 => DemoStep(),
        2 => GalleryStep(),
        3 => ProviderStep(),
        4 => AgentsStep(),
        _ => DoneStep(),
    };

    /// Art panel on top, text below; every step has the same height.
    static Grid Page(UIElement art, UIElement text)
    {
        var g = new Grid();
        g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(ArtHeight) });
        g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(TextHeight) });
        g.Children.Add(new Border { Background = Ui.Res<Brush>("WellBrush"), Child = art });
        Grid.SetRow((FrameworkElement)text, 1);
        g.Children.Add(text);
        return g;
    }

    StackPanel Words(string title, string lead, UIElement? badge, params UIElement[] content)
    {
        var head = Ui.Row(10, Ui.Text(title, 22, bold: true));
        if (badge is not null) head.Children.Add(badge);
        var leadText = Ui.Muted(lead, 14);
        leadText.Margin = new Thickness(0, 4, 0, 16);
        var col = new StackPanel { Padding = new Thickness(32, 22, 32, 0) };
        col.Children.Add(head);
        col.Children.Add(leadText);
        for (int i = 0; i < content.Length; i++)
        {
            col.Children.Add(content[i]);
            Enter(content[i], i);
        }
        return col;
    }

    StackPanel Points(params string[] texts)
    {
        var col = Ui.Column(10);
        for (int i = 0; i < texts.Length; i++)
        {
            var t = Ui.Text(texts[i], 14);
            t.TextWrapping = TextWrapping.Wrap;
            t.TextTrimming = TextTrimming.None;
            t.VerticalAlignment = VerticalAlignment.Center;
            var row = Ui.Columns((Number(i + 1), Ui.Auto), (t, Ui.Star()));
            row.ColumnSpacing = 12;
            col.Children.Add(row);
            Enter(row, i);
        }
        return col;
    }

    static Border Number(int n)
    {
        var t = Ui.Text(n.ToString(), 12, bold: true);
        t.HorizontalAlignment = HorizontalAlignment.Center;
        t.VerticalAlignment = VerticalAlignment.Center;
        return new Border { Width = 24, Height = 24, CornerRadius = new CornerRadius(12), Background = Ui.Res<Brush>("WellBrush"), Child = t };
    }

    static Border Chip(string text, uint color = 0x34C759)
    {
        var t = Ui.Text(text, 12, bold: true);
        t.Foreground = new SolidColorBrush(Ui.Hex(color));
        return new Border
        {
            Background = new SolidColorBrush(Ui.Hex(color, 36)), CornerRadius = new CornerRadius(4), Padding = new Thickness(8, 3, 8, 3),
            VerticalAlignment = VerticalAlignment.Center, Child = t,
        };
    }

    static UIElement Sparkle(double size)
    {
        return new PathIcon
        {
            Width = size, Height = size, VerticalAlignment = VerticalAlignment.Center,
            Data = (Geometry)XamlBindingHelper.ConvertValue(typeof(Geometry), "M7,0 L8.4,5.6 L14,7 L8.4,8.4 L7,14 L5.6,8.4 L0,7 L5.6,5.6 Z"),
        };
    }

    static string Sample(string name) => System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "Onboarding", name + ".jpg");

    // ---------- 1 Welcome ----------

    UIElement WelcomeStep()
    {
        var row = Ui.Row(16);
        row.HorizontalAlignment = HorizontalAlignment.Center;
        row.VerticalAlignment = VerticalAlignment.Center;
        var tools = new (UIElement Icon, string Title, uint Color)[]
        {
            (Sparkle(20), "Generate", 0x1C1C1E),
            (Ui.Icon("\uE91B", 20), "Gallery", 0x2A78D6),
            (Ui.Icon("\uE9D2", 20), "Usage & costs", 0x34A853),
            (Ui.Icon("\uE756", 20), "Agents", 0xEB6834),
        };
        for (int i = 0; i < tools.Length; i++)
        {
            var (icon, title, color) = tools[i];
            if (icon is FontIcon fi && i > 0) fi.Foreground = new SolidColorBrush(Ui.Hex(color));
            var square = new Border
            {
                Width = 48, Height = 48, CornerRadius = new CornerRadius(12), HorizontalAlignment = HorizontalAlignment.Center,
                Background = i == 0 ? Ui.Res<Brush>("AccentFillColorDefaultBrush") : new SolidColorBrush(Ui.Hex(color, 34)),
                Child = icon,
            };
            if (i == 0 && icon is PathIcon pi) pi.Foreground = Ui.Res<Brush>("TextOnAccentFillColorPrimaryBrush");
            var label = Ui.Text(title, 13, bold: true);
            label.HorizontalAlignment = HorizontalAlignment.Center;
            var tile = new Border
            {
                Style = Ui.GetStyle("CardStyle"), Width = 118, Height = 120, Padding = new Thickness(10),
                Child = new StackPanel { Spacing = 12, VerticalAlignment = VerticalAlignment.Center, Children = { square, label } },
            };
            row.Children.Add(tile);
            Pop(tile, i);
            Float(tile, i);
        }
        return Page(row, Words("Welcome to ImageGenKit", "Make AI images with your own accounts, all in one place.", null,
            Points("Generate with Grok, ChatGPT, OpenAI, Gemini, or free models on this PC.",
                   "Every image lands in your Gallery, with what it cost.",
                   "Claude Code and Codex can make images for you too.")));
    }

    // ---------- 2 Try it (live demo) ----------

    static readonly (string Name, string Label, string Prompt, string[] Words)[] Samples = new (string, string, string, string[])[]
    {
        ("mug", "Green mug", "A sage green mug on a wooden table, morning light", new[] { "mug", "cup", "coffee", "tea" }),
        ("ramen", "Ramen", "A steaming bowl of ramen, moody light", new[] { "ramen", "food", "noodle", "soup", "bowl", "dinner", "egg" }),
        ("robot", "Robot sticker", "A cute robot sticker, waving", new[] { "robot", "sticker", "cute", "character", "mascot", "cartoon" }),
        ("nook", "Reading nook", "A cozy reading nook with an olive tree and a lamp", new[] { "room", "nook", "chair", "read", "book", "interior", "lamp", "plant", "cozy" }),
        ("mountain", "Mountain poster", "Minimal mountain poster at sunset", new[] { "mountain", "poster", "landscape", "sunset", "lake", "nature" }),
    };

    static readonly (string Id, string Label, string Cost)[] DemoProviders = new (string, string, string)[]
        { ("grok", "Grok", "Plan"), ("openai", "OpenAI", "$0.04"), ("local", "On this PC", "Free") };

    // demo state (rebuilt with the step)
    TextBox? demoPrompt;
    readonly List<ToggleButton> demoProviders = [];
    Button? demoGenerate, showMe;
    Border? demoResult;
    TextBlock? demoHint, demoCaption;
    readonly List<Border> demoChecks = [];
    UIElement? demoProviderRow;
    Shapes.Path? cursor;
    CompositeTransform? cursorMove;
    Grid? demoArt;
    bool demoBusy, demoDone;

    UIElement DemoStep()
    {
        demoProviders.Clear();
        demoChecks.Clear();
        demoBusy = demoDone = false;

        demoPrompt = new TextBox { PlaceholderText = "Describe an image…", Width = 372, HorizontalAlignment = HorizontalAlignment.Left };
        demoPrompt.TextChanged += (_, _) => { SetCheck(0, demoPrompt.Text.Trim().Length > 0); Hint(null); };

        var ideas = Ui.Row(6, Ui.Faint("Ideas", 12));
        foreach (var s in Samples.Take(3))
        {
            var b = new Button { Content = s.Label, FontSize = 12, Padding = new Thickness(9, 3, 9, 4) };
            b.Click += (_, _) => { if (!demoBusy) demoPrompt.Text = s.Prompt; };
            ideas.Children.Add(b);
        }
        ((TextBlock)ideas.Children[0]).VerticalAlignment = VerticalAlignment.Center;

        var providers = Ui.Row(6);
        foreach (var (id, label, _) in DemoProviders)
        {
            var t = new ToggleButton { Content = Ui.Row(7, Ui.Dot(ProviderStyle.ColorOf(id, ProviderStyle.IsDark)), Ui.Text(label, 13)), Tag = id };
            t.Click += (_, _) =>
            {
                foreach (var other in demoProviders) other.IsChecked = ReferenceEquals(other, t);
                SetCheck(1, true);
                Hint(null);
            };
            demoProviders.Add(t);
            providers.Children.Add(t);
        }
        demoProviderRow = providers;

        demoGenerate = new Button { Style = Ui.Res<Style>("AccentButtonStyle"), Content = Ui.Row(8, Sparkle(13), Ui.Text("Generate", 14)), Padding = new Thickness(16, 6, 16, 7) };
        demoGenerate.Click += async (_, _) => await DemoRun();

        var left = Ui.Column(10, demoPrompt, ideas, providers, demoGenerate);
        left.VerticalAlignment = VerticalAlignment.Center;

        demoResult = new Border
        {
            Width = 168, Height = 168, CornerRadius = new CornerRadius(12), Background = Ui.Res<Brush>("WellBrush"),
            BorderBrush = Ui.Res<Brush>("CardStrokeBrush"), BorderThickness = new Thickness(1),
            Child = Placeholder(),
        };
        demoCaption = Ui.Faint(" ", 12);
        demoCaption.HorizontalAlignment = HorizontalAlignment.Center;
        var right = Ui.Column(6, demoResult, demoCaption);
        right.VerticalAlignment = VerticalAlignment.Center;

        var art = Ui.Columns((left, Ui.Star()), (right, Ui.Auto));
        art.Padding = new Thickness(32, 0, 68, 0); // clear of the close button
        art.ColumnSpacing = 24;

        // The pointer that "Show me" moves around
        cursorMove = new CompositeTransform { TranslateX = 520, TranslateY = 260 };
        cursor = new Shapes.Path
        {
            Data = (Geometry)XamlBindingHelper.ConvertValue(typeof(Geometry), "M0,0 L0,17 L4.6,12.8 L7.6,19.5 L10.4,18.3 L7.4,11.6 L13.5,11.6 Z"),
            Fill = new SolidColorBrush(Microsoft.UI.Colors.White), Stroke = new SolidColorBrush(Microsoft.UI.Colors.Black), StrokeThickness = 1.2,
            RenderTransform = cursorMove, Opacity = 0, IsHitTestVisible = false,
            HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top,
        };
        demoArt = new Grid();
        demoArt.Children.Add(art);
        demoArt.Children.Add(cursor);

        var checks = Ui.Column(9);
        string[] steps = ["Write a prompt", "Pick a provider", "Generate"];
        for (int i = 0; i < steps.Length; i++)
        {
            var mark = Number(i + 1);
            demoChecks.Add(mark);
            var row = Ui.Row(12, mark, Ui.Text(steps[i], 14));
            ((TextBlock)row.Children[1]).VerticalAlignment = VerticalAlignment.Center;
            checks.Children.Add(row);
        }
        demoHint = Ui.Text("", 13);
        demoHint.Foreground = new SolidColorBrush(Ui.Hex(0xE8590C));
        demoHint.Margin = new Thickness(0, 2, 0, 0);
        checks.Children.Add(demoHint);

        showMe = new Button { Content = "Show me", MinWidth = 104 };
        showMe.Click += async (_, _) => await ShowMe();
        var side = Ui.Column(8, showMe);
        side.VerticalAlignment = VerticalAlignment.Top;
        var bottom = Ui.Columns((checks, Ui.Star()), (side, Ui.Auto));

        var page = Page(demoArt, Words("Try it", "A live demo on sample images. Free, nothing is sent.", Chip("Demo", 0x2A78D6), bottom));
        if (showMeOnOpen)
        {
            int t = token;
            page.Loaded += async (_, _) => { await Task.Delay(600); if (t == token) await ShowMe(); };
        }
        return page;
    }

    static UIElement Placeholder()
    {
        var icon = Sparkle(22);
        ((PathIcon)icon).Foreground = Ui.Res<Brush>("TextFillColorTertiaryBrush");
        var col = Ui.Column(8, icon, Ui.Faint("Your image", 12));
        col.HorizontalAlignment = HorizontalAlignment.Center;
        col.VerticalAlignment = VerticalAlignment.Center;
        ((FrameworkElement)col.Children[0]).HorizontalAlignment = HorizontalAlignment.Center;
        return col;
    }

    void SetCheck(int i, bool done)
    {
        if (i >= demoChecks.Count) return;
        var mark = demoChecks[i];
        if (done && mark.Tag is null)
        {
            mark.Tag = "done";
            var icon = Ui.Icon("\uE73E", 12);
            icon.Foreground = new SolidColorBrush(Microsoft.UI.Colors.White);
            mark.Child = icon;
            mark.Background = new SolidColorBrush(Ui.Hex(0x34C759));
            if (motion) Pulse(mark);
        }
        else if (!done && mark.Tag is not null)
        {
            mark.Tag = null;
            var t = Ui.Text((i + 1).ToString(), 12, bold: true);
            t.HorizontalAlignment = HorizontalAlignment.Center;
            t.VerticalAlignment = VerticalAlignment.Center;
            mark.Child = t;
            mark.Background = Ui.Res<Brush>("WellBrush");
        }
    }

    void Hint(string? text, UIElement? shake = null)
    {
        if (demoHint is null) return;
        demoHint.Text = text ?? "";
        if (text is not null && shake is not null && motion) Shake(shake);
    }

    async Task DemoRun()
    {
        if (demoBusy || demoPrompt is null || demoResult is null || demoCaption is null) return;
        if (demoDone) { ResetDemo(); return; }
        string prompt = demoPrompt.Text.Trim();
        var provider = demoProviders.FirstOrDefault(p => p.IsChecked == true);
        if (prompt.Length == 0) { Hint("Write a prompt first, or tap an idea.", demoPrompt); return; }
        if (provider is null) { Hint("Pick a provider first.", demoProviderRow); return; }

        int t = token;
        demoBusy = true;
        var ring = new ProgressRing { IsActive = true, Width = 28, Height = 28 };
        var busy = Ui.Column(10, ring, Ui.Faint("Generating…", 12));
        busy.HorizontalAlignment = HorizontalAlignment.Center;
        busy.VerticalAlignment = VerticalAlignment.Center;
        demoResult.Child = busy;
        demoCaption.Text = " ";
        await Task.Delay(1700);
        if (t != token) return;

        // Whole words ("steaming" isn't "tea"), plurals count
        var words = System.Text.RegularExpressions.Regex.Split(prompt.ToLowerInvariant(), "[^a-z]+");
        var sample = Samples.FirstOrDefault(s => s.Words.Any(k => words.Any(w => w == k || w == k + "s" || w == k + "es")));
        if (sample.Name is null) sample = Samples[4];
        var (_, label, cost) = DemoProviders.First(p => p.Id == (string)provider.Tag);
        var picture = Ui.Picture(Sample(sample.Name), 336);
        demoResult.Child = picture;
        demoCaption.Text = $"1024 × 1024 · {label} · {cost}";
        if (motion) { Fade(picture, 0, 1, 380); Pulse(demoResult, 0.94); }
        SetCheck(2, true);
        Hint(null);
        if (demoHint is not null)
        {
            demoHint.Text = "That's it. The real one works the same.";
            demoHint.Foreground = new SolidColorBrush(Ui.Hex(0x34A853));
        }
        if (showMe is not null) showMe.Content = "Play Again";
        demoBusy = false;
        demoDone = true;
    }

    void ResetDemo()
    {
        if (demoPrompt is null || demoResult is null || demoCaption is null || demoHint is null) return;
        demoDone = false;
        demoPrompt.Text = "";
        foreach (var p in demoProviders) p.IsChecked = false;
        for (int i = 0; i < 3; i++) SetCheck(i, false);
        demoResult.Child = Placeholder();
        demoCaption.Text = " ";
        demoHint.Text = "";
        demoHint.Foreground = new SolidColorBrush(Ui.Hex(0xE8590C));
        if (showMe is not null) showMe.Content = "Show me";
    }

    /// "Show me": the pointer does every step.
    async Task ShowMe()
    {
        if (demoBusy || demoPrompt is null || demoGenerate is null || cursor is null || demoArt is null) return;
        if (demoDone || demoPrompt.Text.Length > 0 || demoProviders.Any(p => p.IsChecked == true)) ResetDemo();
        int t = token;
        demoBusy = true;
        if (showMe is not null) showMe.IsEnabled = false;
        cursor.Opacity = 1;

        await PointAt(demoPrompt, 0.15);
        if (t != token) return;
        await Click();
        const string text = "A steaming bowl of ramen, moody light";
        for (int i = 1; i <= text.Length; i++)
        {
            demoPrompt.Text = text[..i];
            await Task.Delay(32);
            if (t != token) return;
        }
        await Task.Delay(250);
        var openai = demoProviders[1];
        await PointAt(openai, 0.5);
        if (t != token) return;
        await Click();
        foreach (var other in demoProviders) other.IsChecked = ReferenceEquals(other, openai);
        SetCheck(1, true);
        await Task.Delay(250);
        await PointAt(demoGenerate, 0.5);
        if (t != token) return;
        await Click();
        demoBusy = false;
        await DemoRun();
        if (t != token) return;
        if (motion) Fade(cursor, 1, 0, 400); else cursor.Opacity = 0;
        if (showMe is not null) showMe.IsEnabled = true;
    }

    async Task PointAt(FrameworkElement target, double across)
    {
        if (cursor is null || cursorMove is null || demoArt is null) return;
        var p = target.TransformToVisual(demoArt).TransformPoint(new Windows.Foundation.Point(target.ActualWidth * across, target.ActualHeight * 0.6));
        if (!motion) { cursorMove.TranslateX = p.X; cursorMove.TranslateY = p.Y; return; }
        Move(cursorMove, "TranslateX", null, p.X, 620, ease: new CubicEase { EasingMode = EasingMode.EaseInOut });
        Move(cursorMove, "TranslateY", null, p.Y, 620, ease: new CubicEase { EasingMode = EasingMode.EaseInOut });
        await Task.Delay(680);
    }

    async Task Click()
    {
        if (cursorMove is null) return;
        if (motion)
        {
            Move(cursorMove, "ScaleX", 1, 0.8, 110, autoReverse: true);
            Move(cursorMove, "ScaleY", 1, 0.8, 110, autoReverse: true);
        }
        await Task.Delay(240);
    }

    // ---------- 3 Gallery & costs ----------

    UIElement GalleryStep()
    {
        var row = Ui.Row(12);
        row.HorizontalAlignment = HorizontalAlignment.Center;
        row.VerticalAlignment = VerticalAlignment.Center;
        var items = new (string Name, string Price, string Provider)[]
        {
            ("mug", "Plan", "grok"), ("nook", "$0.04", "openai"), ("mountain", "Free", "local"), ("robot", "$0.07", "gemini"), ("ramen", "Plan", "codex"),
        };
        for (int i = 0; i < items.Length; i++)
        {
            var (name, price, provider) = items[i];
            var tile = Ui.Tile(Sample(name), 100, 100, 200, 10);
            var tag = Ui.Pill(price, ProviderStyle.ColorOf(provider, ProviderStyle.IsDark));
            tag.HorizontalAlignment = HorizontalAlignment.Center;
            var col = Ui.Column(8, tile, tag);
            row.Children.Add(col);
            Pop(col, i, 110);
        }
        var total = Ui.Pill("This week: 5 images · $0.11");
        total.HorizontalAlignment = HorizontalAlignment.Center;
        var art = Ui.Column(16, row, total);
        art.VerticalAlignment = VerticalAlignment.Center;
        Pop(total, 6, 110);

        return Page(art, Words("Gallery & costs", "Every image is saved with its prompt and price.", null,
            Points("Subscriptions (Grok, ChatGPT): no extra cost per image.",
                   "API keys: you pay per image, and see each price and your monthly total.",
                   "Models on this PC are free. They need a good graphics card.")));
    }

    // ---------- 4 Connect a provider ----------

    static readonly string[] ScanOrder = ["grok", "codex", "openai", "gemini", "local"];

    UIElement ProviderStep()
    {
        var s = Store.Shared;
        var ready = s.Providers.Where(p => p.Ready).ToList();

        // Art: the providers ImageGenKit knows, the ones found light up
        var row = Ui.Row(18);
        row.HorizontalAlignment = HorizontalAlignment.Center;
        row.VerticalAlignment = VerticalAlignment.Center;
        for (int i = 0; i < ScanOrder.Length; i++)
        {
            string id = ScanOrder[i];
            var p = s.Providers.FirstOrDefault(x => x.Name == id);
            string label = id switch { "grok" => "Grok", "codex" => "ChatGPT", "openai" => "OpenAI", "gemini" => "Gemini", _ => "On this PC" };
            var badge = Ui.Badge(ProviderStyle.Glyph(id, p?.Type ?? ""), ProviderStyle.ColorOf(id, ProviderStyle.IsDark), 56);
            var holder = new Grid { Width = 64, Height = 64 };
            badge.HorizontalAlignment = HorizontalAlignment.Center;
            badge.VerticalAlignment = VerticalAlignment.Center;
            holder.Children.Add(badge);
            if (p?.Ready == true)
            {
                var check = new Border
                {
                    Width = 22, Height = 22, CornerRadius = new CornerRadius(11), Background = new SolidColorBrush(Ui.Hex(0x34C759)),
                    BorderThickness = new Thickness(2), BorderBrush = Ui.Res<Brush>("SolidBackgroundFillColorBaseBrush"),
                    HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom,
                    Child = new FontIcon { Glyph = "\uE73E", FontSize = 10, Foreground = new SolidColorBrush(Microsoft.UI.Colors.White) },
                };
                holder.Children.Add(check);
                Pop(check, i + 3);
            }
            else if (s.Loaded) badge.Opacity = 0.45;
            var name = Ui.Text(label, 12, bold: p?.Ready == true);
            name.HorizontalAlignment = HorizontalAlignment.Center;
            var col = Ui.Column(8, holder, name);
            row.Children.Add(col);
            Pop(col, i, 90);
        }
        UIElement art = row;
        if (!s.Loaded && motion)
        {
            // A soft light sweeping across while it looks
            var sweep = new Shapes.Rectangle
            {
                Width = 90, Fill = new SolidColorBrush(Ui.Hex(0xFFFFFF, 50)), HorizontalAlignment = HorizontalAlignment.Left,
                RenderTransform = new CompositeTransform(), IsHitTestVisible = false,
            };
            var g = new Grid();
            g.Children.Add(row);
            g.Children.Add(sweep);
            Move((CompositeTransform)sweep.RenderTransform, "TranslateX", -100, CardWidth, 1400, forever: true);
            art = g;
        }

        UIElement content;
        UIElement? badgeTag = null;
        if (!s.Loaded)
        {
            var ringRow = Ui.Row(10, new ProgressRing { IsActive = true, Width = 18, Height = 18 }, Ui.Muted("Looking on this PC…", 14));
            content = ringRow;
        }
        else if (ready.Count > 0)
        {
            badgeTag = Chip("Ready");
            var list = Ui.Column(8);
            foreach (var p in ready.Take(3))
            {
                var check = Ui.Icon("\uE73E", 14);
                check.Foreground = new SolidColorBrush(Ui.Hex(0x34C759));
                list.Children.Add(Ui.Row(10, check, Ui.Text(p.Label, 14, bold: true),
                    Ui.Pill(p.IsLocal ? "On this PC" : p.IsSubscription ? "Subscription" : "API key")));
            }
            if (ready.Count > 3) list.Children.Add(Ui.Faint($"+ {ready.Count - 3} more", 12));
            var connected = Ui.Text("You're connected.", 13, bold: true);
            connected.Foreground = new SolidColorBrush(Ui.Hex(0x34A853));
            connected.VerticalAlignment = VerticalAlignment.Center;
            var another = new HyperlinkButton { Content = "Add another" };
            another.Click += async (_, _) => await ProviderSetup.AddProviderDialog(XamlRoot, () => Close(TourDestination.LocalModels));
            list.Children.Add(Ui.Row(14, connected, another));
            content = list;
        }
        else
        {
            var grid = new Grid { ColumnSpacing = 10, RowSpacing = 10 };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = Ui.Star() });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = Ui.Star() });
            grid.RowDefinitions.Add(new RowDefinition());
            grid.RowDefinitions.Add(new RowDefinition());
            var choices = new (string Id, string Title, string Detail, Func<Task> Act)[]
            {
                ("codex", "I pay for ChatGPT", "Use your plan", () => ConnectById("codex")),
                ("grok", "I pay for Grok", "Use your plan", () => ConnectById("grok")),
                ("openai", "I have an API key", "OpenAI, Gemini & more", () => ProviderSetup.AddProviderDialog(XamlRoot, null, p => p.NeedsKey)),
                ("local", "Free, on this PC", "Needs a graphics card", () => { Close(TourDestination.LocalModels); return Task.CompletedTask; }),
            };
            for (int i = 0; i < choices.Length; i++)
            {
                var c = choices[i];
                var text = Ui.Column(1, Ui.Text(c.Title, 14, bold: true), Ui.Faint(c.Detail, 12));
                var b = new Button
                {
                    HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Left, Padding = new Thickness(12, 8, 12, 8),
                    Content = Ui.Row(12, Ui.Badge(ProviderStyle.Glyph(c.Id, ""), ProviderStyle.ColorOf(c.Id, ProviderStyle.IsDark), 32), text),
                };
                b.Click += async (_, _) => await c.Act();
                Grid.SetColumn(b, i % 2);
                Grid.SetRow(b, i / 2);
                grid.Children.Add(b);
            }
            content = grid;
        }
        return Page(art, Words("Connect a provider", "Where your images come from. One-time setup.", badgeTag, content));
    }

    async Task ConnectById(string id)
    {
        var p = Store.Shared.Providers.FirstOrDefault(x => x.Name == id);
        if (p is null) { await ProviderSetup.AddProviderDialog(XamlRoot, null); return; }
        await ProviderSetup.Connect(p, XamlRoot, null);
    }

    // ---------- 5 Agents ----------

    UIElement AgentsStep()
    {
        int t = token;
        // Art: a terminal where an agent makes an image
        var lines = Ui.Column(6);
        var mono = new FontFamily("Cascadia Mono, Consolas");
        TextBlock Line(string text, uint color)
        {
            var tb = new TextBlock { Text = text, FontFamily = mono, FontSize = 13, Foreground = new SolidColorBrush(Ui.Hex(color)) };
            lines.Children.Add(tb);
            return tb;
        }
        var command = Line("", 0xE5E5EA);
        var answer = Line("", 0x8E8E93);
        var saved = Line("", 0x34C759);
        var thumb = Ui.Tile(Sample("robot"), 64, 64, 128, 8);
        thumb.Opacity = 0;
        thumb.HorizontalAlignment = HorizontalAlignment.Right;
        thumb.VerticalAlignment = VerticalAlignment.Bottom;
        var dotsRow = Ui.Row(6, Ui.Dot(Ui.Hex(0xFF5F57), 10), Ui.Dot(Ui.Hex(0xFEBC2E), 10), Ui.Dot(Ui.Hex(0x28C840), 10));
        var body = new Grid();
        body.Children.Add(Ui.Column(14, dotsRow, lines));
        body.Children.Add(thumb);
        var terminal = new Border
        {
            Width = 480, Height = 168, CornerRadius = new CornerRadius(12), Padding = new Thickness(16, 12, 16, 12),
            Background = new SolidColorBrush(Ui.Hex(0x1C1C1E)), BorderBrush = new SolidColorBrush(Ui.Hex(0xFFFFFF, 24)), BorderThickness = new Thickness(1),
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Child = body,
        };
        _ = TypeTerminal(t, command, answer, saved, thumb);

        // Setup right here: the command and the skills
        var rows = Ui.Column(8);
        bool installed = CommandInstaller.Installed;
        rows.Children.Add(SetupRow("\uE756", "The imagegenkit command", installed ? Chip("Installed") : (UIElement)SetupButton("Install", async b =>
        {
            b.IsEnabled = false;
            await ProviderSetup.Run(async () => { await Task.Run(CommandInstaller.Install); });
            RefreshStep(4);
        })));
        bool allSet = installed;
        foreach (var a in Store.Shared.State.Arr("agents"))
        {
            string id = a.Str("id"), label = a.Str("label");
            bool present = a.Bool("present"), has = a.Bool("installed");
            UIElement right = has ? (UIElement)Chip("Installed")
                : !present ? (UIElement)Ui.Faint("Not on this PC", 12)
                : SetupButton("Install Skill", async b =>
                {
                    b.IsEnabled = false;
                    await ProviderSetup.Run(async () => { await Backend.Shared.PostAsync("/api/skill", new { agent = id }); await Store.Shared.ReloadStateAsync(); });
                });
            if (present && !has) allSet = false;
            rows.Children.Add(SetupRow(id == "claude" ? "\uE99A" : "\uE8BD", $"{label} skill", right));
        }
        return Page(terminal, Words("Connect your AI agents", "Let Claude Code and Codex make images for you.", allSet ? Chip("All set") : null, rows));
    }

    static UIElement SetupRow(string glyph, string title, UIElement right)
    {
        var icon = Ui.Icon(glyph, 16);
        icon.VerticalAlignment = VerticalAlignment.Center;
        var t = Ui.Text(title, 14);
        t.VerticalAlignment = VerticalAlignment.Center;
        var g = Ui.Columns((icon, Ui.Auto), (t, Ui.Star()), (right, Ui.Auto));
        g.ColumnSpacing = 12;
        g.MinHeight = 34;
        if (right is FrameworkElement f) f.VerticalAlignment = VerticalAlignment.Center;
        return g;
    }

    static Button SetupButton(string text, Func<Button, Task> act)
    {
        var b = new Button { Content = text, Style = Ui.Res<Style>("AccentButtonStyle"), MinWidth = 104 };
        b.Click += async (_, _) => await act(b);
        return b;
    }

    void RefreshStep(int which)
    {
        if (closed || step != which) return;
        var page = Build(step);
        pageHost.Children.Clear();
        pageHost.Children.Add(page);
    }

    async Task TypeTerminal(int t, TextBlock command, TextBlock answer, TextBlock saved, UIElement thumb)
    {
        const string cmd = "$ imagegenkit draft \"robot sticker for the blog\"";
        if (!motion)
        {
            command.Text = cmd;
            answer.Text = "Grok subscription · 1024 × 1024";
            saved.Text = "✓ Saved robot-sticker.png (9 s)";
            thumb.Opacity = 1;
            return;
        }
        await Task.Delay(450);
        for (int i = 1; i <= cmd.Length; i++)
        {
            if (t != token) return;
            command.Text = cmd[..i];
            await Task.Delay(28);
        }
        await Task.Delay(350);
        if (t != token) return;
        answer.Text = "Grok subscription · 1024 × 1024";
        await Task.Delay(900);
        if (t != token) return;
        saved.Text = "✓ Saved robot-sticker.png (9 s)";
        Fade(thumb, 0, 1, 350);
        Pop(thumb, 0);
    }

    // ---------- 6 Done ----------

    UIElement DoneStep()
    {
        var fan = new Grid { Width = 360, Height = 190, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        string[] names = ["nook", "ramen", "mountain"];
        double[] angles = [-9, 0, 9];
        double[] shifts = [-96, 0, 96];
        for (int i = 0; i < names.Length; i++)
        {
            var tile = Ui.Tile(Sample(names[i]), 132, 132, 264, 12);
            tile.HorizontalAlignment = HorizontalAlignment.Center;
            tile.VerticalAlignment = VerticalAlignment.Center;
            tile.BorderBrush = Ui.Res<Brush>("SolidBackgroundFillColorBaseBrush");
            tile.BorderThickness = new Thickness(3);
            tile.RenderTransformOrigin = new Windows.Foundation.Point(0.5, 0.5);
            tile.RenderTransform = new CompositeTransform { Rotation = angles[i], TranslateX = shifts[i], TranslateY = i == 1 ? -6 : 6 };
            if (i == 1) Canvas.SetZIndex(tile, 1);
            fan.Children.Add(tile);
            Pop(tile, i);
            Float(tile, i);
        }

        var ready = Store.Shared.Providers.Where(p => p.Ready && Store.Shared.Enabled.Contains(p.Name)).Select(p => p.Label).ToList();
        string first = ready.Count switch
        {
            0 => "No provider yet: add one any time in Settings.",
            1 => $"Ready: {ready[0]}.",
            _ => $"Ready: {string.Join(", ", ready.Take(ready.Count - 1))} and {ready[^1]}.",
        };
        return Page(fan, Words("You're all set", "Make your first image.", null,
            Points(first, "Press Ctrl+N to generate from anywhere in the app.", "This tour is in Settings › General.")));
    }

    // ---------- motion ----------

    void Enter(UIElement el, int index)
    {
        if (!motion) return;
        el.Opacity = 0;
        Fade(el, 0, 1, 260, 120 + 70 * index);
        Move(el, "TranslateY", 8, 0, 320, 120 + 70 * index);
    }

    void Pop(UIElement el, int index, double stagger = 80)
    {
        if (!motion) return;
        el.Opacity = 0;
        Fade(el, 0, 1, 260, 80 + stagger * index);
        var t = Transform(el);
        if (el is FrameworkElement) el.RenderTransformOrigin = new Windows.Foundation.Point(0.5, 0.5);
        Move(t, "ScaleX", 0.86, 1, 380, 80 + stagger * index, ease: new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.4 });
        Move(t, "ScaleY", 0.86, 1, 380, 80 + stagger * index, ease: new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.4 });
    }

    void Float(UIElement el, int index)
    {
        if (!motion) return;
        var t = Transform(el);
        Move(t, "TranslateY", t.TranslateY, t.TranslateY - 5, 1700, 600 + 260 * index, forever: true, autoReverse: true,
            ease: new SineEase { EasingMode = EasingMode.EaseInOut });
    }

    void Pulse(UIElement el, double scale = 1.18)
    {
        var t = Transform(el);
        el.RenderTransformOrigin = new Windows.Foundation.Point(0.5, 0.5);
        Move(t, "ScaleX", 1, scale, 130, autoReverse: true);
        Move(t, "ScaleY", 1, scale, 130, autoReverse: true);
    }

    /// A small "no" shake for a wrong try.
    static void Shake(UIElement el)
    {
        var t = Transform(el);
        var a = new DoubleAnimationUsingKeyFrames { Duration = new Duration(TimeSpan.FromMilliseconds(360)) };
        double[] xs = [0, -7, 7, -5, 5, -2, 0];
        for (int i = 0; i < xs.Length; i++)
            a.KeyFrames.Add(new LinearDoubleKeyFrame { Value = xs[i], KeyTime = KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(60 * i)) });
        Storyboard.SetTarget(a, t);
        Storyboard.SetTargetProperty(a, "TranslateX");
        var sb = new Storyboard();
        sb.Children.Add(a);
        sb.Begin();
    }

    static CompositeTransform Transform(UIElement el)
    {
        if (el.RenderTransform is CompositeTransform c) return c;
        var t = new CompositeTransform();
        el.RenderTransform = t;
        return t;
    }

    static void Fade(UIElement el, double from, double to, double ms, double delay = 0)
    {
        var a = new DoubleAnimation
        {
            From = from, To = to, Duration = new Duration(TimeSpan.FromMilliseconds(ms)), BeginTime = TimeSpan.FromMilliseconds(delay),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
        };
        Storyboard.SetTarget(a, el);
        Storyboard.SetTargetProperty(a, "Opacity");
        var sb = new Storyboard();
        sb.Children.Add(a);
        sb.Begin();
    }

    static void Move(UIElement el, string property, double? from, double to, double ms, double delay = 0) =>
        Move(Transform(el), property, from, to, ms, delay);

    static void Move(CompositeTransform t, string property, double? from, double to, double ms, double delay = 0,
        bool forever = false, bool autoReverse = false, EasingFunctionBase? ease = null)
    {
        var a = new DoubleAnimation
        {
            To = to, Duration = new Duration(TimeSpan.FromMilliseconds(ms)), BeginTime = TimeSpan.FromMilliseconds(delay),
            EasingFunction = ease ?? new CubicEase { EasingMode = EasingMode.EaseOut }, AutoReverse = autoReverse,
        };
        if (from is { } f) a.From = f;
        if (forever) a.RepeatBehavior = RepeatBehavior.Forever;
        Storyboard.SetTarget(a, t);
        Storyboard.SetTargetProperty(a, property);
        var sb = new Storyboard();
        sb.Children.Add(a);
        sb.Begin();
    }
}
