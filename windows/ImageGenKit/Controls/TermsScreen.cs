using ImageGenKit.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Media.Imaging;

namespace ImageGenKit.Controls;

/// Full-window terms of use at first launch, before the tour: the key points in plain words, links to the full terms
/// and the privacy policy, and one "Agree and Continue" button. No skip; the app can't be used without agreeing.
public sealed class TermsScreen : Grid
{
    public TermsScreen(Action agreed)
    {
        Background = Ui.Res<Brush>("SolidBackgroundFillColorBaseBrush");

        var column = new StackPanel { Spacing = 0, MaxWidth = 600, Margin = new Thickness(32, 28, 32, 32), HorizontalAlignment = HorizontalAlignment.Center };
        column.ChildrenTransitions = new TransitionCollection { new EntranceThemeTransition { FromVerticalOffset = 24, IsStaggeringEnabled = true } };

        var icon = new Image { Source = new BitmapImage(new Uri("ms-appx:///Assets/AppIcon.png")), Width = 64, Height = 64, HorizontalAlignment = HorizontalAlignment.Left };
        column.Children.Add(icon);

        var title = Ui.Text("Welcome to ImageGenKit", 28, bold: true);
        title.Margin = new Thickness(0, 18, 0, 0);
        column.Children.Add(title);
        var lead = Ui.Muted("Before you start, please read and accept the terms of use.", 15);
        lead.Margin = new Thickness(0, 6, 0, 22);
        lead.TextWrapping = TextWrapping.Wrap;
        column.Children.Add(lead);

        var points = Ui.Column(18);
        points.Children.Add(Point("\uE753", 0x2A78D6, "Images come from your providers",
            "AI services you set up yourself, or open models on this PC. Their terms and prices apply; costs shown here are estimates."));
        points.Children.Add(Point("\uEA18", 0xEB6834, "You're responsible for what you make",
            "Nothing illegal, no nude or sexual images of real people without their consent, nothing involving minors. Respect other people's rights."));
        points.Children.Add(Point("\uE8EC", 0x8E5CD9, "AI images are marked",
            "Images made on this PC carry an AI mark. Don't remove it, and say an image is AI-made wherever the law requires it."));
        points.Children.Add(Point("\uE72E", 0x34A853, "Your data stays on this PC",
            "Keys, prompts and images stay here; prompts go only to the provider you pick. AI results can be wrong, so check them."));
        column.Children.Add(Ui.Card(points, 22));

        var links = Ui.Row(4, Link("Read the Terms of Use", Terms.Url), Ui.Faint("·", 13), Link("Privacy Policy", Terms.PrivacyUrl));
        links.Margin = new Thickness(0, 16, 0, 0);
        column.Children.Add(links);

        var agree = new Button
        {
            Content = "Agree and Continue", Style = Ui.Res<Style>("AccentButtonStyle"), MinWidth = 220, Height = 40,
            Margin = new Thickness(0, 20, 0, 0), HorizontalAlignment = HorizontalAlignment.Left,
        };
        agree.Click += (_, _) =>
        {
            Terms.Accept();
            agreed();
        };
        column.Children.Add(agree);

        var fine = Ui.Faint($"Terms of Use, version {Terms.Version}. ImageGenKit is free and open source, made by STRICS IT GmbH, Austria.", 12);
        fine.Margin = new Thickness(0, 14, 0, 0);
        fine.TextWrapping = TextWrapping.Wrap;
        fine.TextTrimming = TextTrimming.None;
        column.Children.Add(fine);

        Children.Add(new ScrollViewer { Content = column, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        Loaded += (_, _) => agree.Focus(FocusState.Programmatic);
    }

    static UIElement Point(string glyph, uint color, string title, string text)
    {
        var body = Ui.Muted(text, 13);
        body.TextWrapping = TextWrapping.Wrap;
        body.TextTrimming = TextTrimming.None;
        var words = Ui.Column(3, Ui.Text(title, 14, bold: true), body);
        var badge = Ui.Badge(glyph, Ui.Hex(color), 36);
        badge.VerticalAlignment = VerticalAlignment.Top;
        return Ui.Columns((badge, Ui.Auto), (words, Ui.Star()));
    }

    static HyperlinkButton Link(string text, string url)
    {
        var b = new HyperlinkButton { Content = text, Padding = new Thickness(0), FontSize = 13 };
        b.Click += (_, _) => ProviderSetup.OpenUrl(url);
        return b;
    }
}
