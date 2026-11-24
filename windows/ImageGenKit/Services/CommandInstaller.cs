using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace ImageGenKit.Services;

/// Installs the `imagegenkit` command for AI agents (Claude Code, Codex) the way install.ps1 does, but with the Python
/// that ships with the app: files in %USERPROFILE%\.local\share\imagegenkit, launchers in %USERPROFILE%\.local\bin
/// (imagegenkit.cmd for PowerShell and cmd, a sh script for Git Bash), and that folder on the user's PATH.
public static class CommandInstaller
{
    static readonly string Home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    public static readonly string Share = Path.Combine(Home, ".local", "share", "imagegenkit");
    public static readonly string Bin = Path.Combine(Home, ".local", "bin");

    static readonly string[] Files =
        ["imagegenkit.py", "imagegenkit_app.py", "app/index.html", "app/app.js", "app/app.css", "app/icon.svg", "app/icon.ico",
         "local.json", "providers.json", "SKILL.md"];

    public static bool Installed => File.Exists(Path.Combine(Bin, "imagegenkit.cmd")) && File.Exists(Path.Combine(Share, "imagegenkit.py"));

    public static string? InstalledVersion => VersionIn(Path.Combine(Share, "imagegenkit.py"));
    public static string? BundledVersion => VersionIn(Path.Combine(Backend.CliDir, "imagegenkit.py"));

    static string? VersionIn(string script)
    {
        try
        {
            foreach (var line in File.ReadLines(script))
                if (line.StartsWith("VERSION = \"")) return line.Split('"')[1];
        }
        catch { }
        return null;
    }

    public static bool Outdated => Installed && InstalledVersion != BundledVersion;

    public static void Install()
    {
        var python = Backend.FindPython() ?? throw new InvalidOperationException("Python is missing.");
        foreach (var rel in Files)
        {
            var src = Path.Combine(Backend.CliDir, rel.Replace('/', Path.DirectorySeparatorChar));
            if (!File.Exists(src)) continue;
            var dest = Path.Combine(Share, rel.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
            File.Copy(src, dest + ".new", true);
            File.Move(dest + ".new", dest, true);
        }
        Directory.CreateDirectory(Bin);
        var script = Path.Combine(Share, "imagegenkit.py");
        File.WriteAllText(Path.Combine(Bin, "imagegenkit.cmd"), $"@\"{python}\" \"{script}\" %*\r\n");
        string Posix(string p) => p.Length > 1 && p[1] == ':' ? "/" + char.ToLowerInvariant(p[0]) + p[2..].Replace('\\', '/') : p.Replace('\\', '/');
        File.WriteAllText(Path.Combine(Bin, "imagegenkit"), $"#!/bin/sh\nexec \"{Posix(python)}\" \"$HOME/.local/share/imagegenkit/imagegenkit.py\" \"$@\"\n");
        AddToPath(Bin);
    }

    static void AddToPath(string dir)
    {
        using var env = Registry.CurrentUser.OpenSubKey("Environment", writable: true);
        if (env is null) return;
        var path = env.GetValue("Path", "", RegistryValueOptions.DoNotExpandEnvironmentNames) as string ?? "";
        if (path.Split(';').Any(p => string.Equals(p.TrimEnd('\\'), dir.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))) return;
        env.SetValue("Path", string.IsNullOrEmpty(path) ? dir : path.TrimEnd(';') + ";" + dir, RegistryValueKind.ExpandString);
        SendMessageTimeout(new IntPtr(0xffff), 0x001A, IntPtr.Zero, "Environment", 2, 3000, out _); // tell new terminals
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, string lParam, uint flags, uint timeout, out IntPtr result);
}
