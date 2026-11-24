using Microsoft.UI.Xaml;

namespace ImageGenKit;

public partial class App : Application
{
    public static MainWindow? Window { get; private set; }

    /// Command line for screenshots and tests: --page overview|gallery|history|generate|settings, --theme light|dark,
    /// --select-latest, --settings-section providers|use|local|limits|agents|general, --prompt "..."
    public static LaunchOptions Options { get; } = LaunchOptions.Parse(Environment.GetCommandLineArgs());

    public App()
    {
        InitializeComponent();
        if (Options.Theme is "dark" or "light")
            RequestedTheme = Options.Theme == "dark" ? ApplicationTheme.Dark : ApplicationTheme.Light;
        UnhandledException += (_, e) =>
        {
            Services.Log.Write($"unhandled: {e.Exception}");
            e.Handled = true;
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Window = new MainWindow();
        Window.Activate();
    }
}

public sealed class LaunchOptions
{
    public string Page { get; private set; } = "overview";
    public string? Theme { get; private set; }
    public bool SelectLatest { get; private set; }
    public string SettingsSection { get; private set; } = "providers";
    public string? Prompt { get; private set; }
    public int Width { get; private set; } = 1280;
    public int Height { get; private set; } = 860;

    public static LaunchOptions Parse(string[] args)
    {
        var o = new LaunchOptions();
        for (int i = 1; i < args.Length; i++)
        {
            string a = args[i], next = i + 1 < args.Length ? args[i + 1] : "";
            switch (a)
            {
                case "--page": o.Page = next.ToLowerInvariant(); i++; break;
                case "--theme": o.Theme = next.ToLowerInvariant(); i++; break;
                case "--select-latest": o.SelectLatest = true; break;
                case "--settings-section": o.SettingsSection = next.ToLowerInvariant(); i++; break;
                case "--prompt": o.Prompt = next; i++; break;
                case "--size":
                    var p = next.Split('x');
                    if (p.Length == 2 && int.TryParse(p[0], out var w) && int.TryParse(p[1], out var h)) { o.Width = w; o.Height = h; }
                    i++;
                    break;
            }
        }
        return o;
    }
}
