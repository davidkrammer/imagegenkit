using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace ImageGenKit.Services;

public sealed class BackendException(string message) : Exception(message);

/// The imagegenkit backend (cli/imagegenkit_app.py): a local server on 127.0.0.1 with a per-launch token, started
/// hidden with the Python that ships with the app. Every action goes through the same `imagegenkit` command that
/// agents use, so settings, the log and limits are shared. The server is tied to this process (a job object), so it
/// never outlives the app.
public sealed class Backend
{
    public static Backend Shared { get; } = new();

    readonly HttpClient http = new() { Timeout = TimeSpan.FromMinutes(10) };
    Process? proc;
    string baseUrl = "";
    Task? starting;

    public static string AppDir => AppContext.BaseDirectory;

    /// cli/ next to the app (imagegenkit.py, imagegenkit_app.py, catalogs); IMAGEGENKIT_CLI_DIR for development.
    public static string CliDir
    {
        get
        {
            var env = Environment.GetEnvironmentVariable("IMAGEGENKIT_CLI_DIR");
            return !string.IsNullOrEmpty(env) ? env : Path.Combine(AppDir, "cli");
        }
    }

    /// The Python shipped in python\ next to the app, else IMAGEGENKIT_PYTHON, else one on PATH (not the Store stub).
    public static string? FindPython()
    {
        var bundled = Path.Combine(AppDir, "python", "python.exe");
        if (File.Exists(bundled)) return bundled;
        var env = Environment.GetEnvironmentVariable("IMAGEGENKIT_PYTHON");
        if (!string.IsNullOrEmpty(env) && File.Exists(env)) return env;
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';'))
        {
            if (string.IsNullOrWhiteSpace(dir) || dir.Contains("WindowsApps", StringComparison.OrdinalIgnoreCase)) continue;
            var p = Path.Combine(dir.Trim(), "python.exe");
            if (File.Exists(p)) return p;
        }
        return null;
    }

    public Task EnsureStartedAsync() => starting ??= StartAsync();

    async Task StartAsync()
    {
        var python = FindPython() ?? throw new BackendException("Python is missing. Reinstall ImageGenKit.");
        var script = Path.Combine(CliDir, "imagegenkit_app.py");
        if (!File.Exists(script)) throw new BackendException($"{script} is missing. Reinstall ImageGenKit.");
        int port = FreePort();
        var psi = new ProcessStartInfo(python)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
            WorkingDirectory = CliDir,
        };
        foreach (var a in new[] { script, "--no-window", "--stay", "--port", port.ToString() }) psi.ArgumentList.Add(a);
        psi.Environment["PYTHONUTF8"] = "1";
        psi.Environment["PYTHONIOENCODING"] = "utf-8";
        psi.Environment["PYTHONUNBUFFERED"] = "1";
        psi.Environment["IMAGEGENKIT_HOST_APP"] = "windows";
        proc = Process.Start(psi) ?? throw new BackendException("The ImageGenKit backend didn't start.");
        JobObject.Attach(proc);
        var errors = new StringBuilder();
        proc.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is null) return;
            lock (errors) errors.AppendLine(e.Data);
            Log.Write("backend: " + e.Data);
        };
        proc.BeginErrorReadLine();

        var read = Task.Run(async () =>
        {
            while (await proc.StandardOutput.ReadLineAsync() is { } line)
            {
                int t = line.IndexOf("?t=", StringComparison.Ordinal);
                if (line.Contains("http://127.0.0.1:") && t > 0) return line[(t + 3)..].Trim();
            }
            return null;
        });
        if (await Task.WhenAny(read, Task.Delay(TimeSpan.FromSeconds(40))) != read || read.Result is null)
        {
            string detail;
            lock (errors) detail = errors.ToString().Trim();
            throw new BackendException("The ImageGenKit backend didn't start." + (detail.Length > 0 ? "\n" + Last(detail, 600) : ""));
        }
        baseUrl = $"http://127.0.0.1:{port}";
        http.DefaultRequestHeaders.Remove("X-IGK-Token");
        http.DefaultRequestHeaders.Add("X-IGK-Token", read.Result);
        _ = Task.Run(async () => { while (await proc.StandardOutput.ReadLineAsync() is not null) { } });
    }

    public async Task<JsonElement> GetAsync(string path)
    {
        await EnsureStartedAsync();
        using var r = await http.GetAsync(baseUrl + path);
        return await ReadAsync(r);
    }

    public async Task<JsonElement> PostAsync(string path, object? body = null)
    {
        await EnsureStartedAsync();
        using var content = new StringContent(JsonSerializer.Serialize(body ?? new { }), Encoding.UTF8, "application/json");
        using var r = await http.PostAsync(baseUrl + path, content);
        return await ReadAsync(r);
    }

    /// Copies a file into the app's uploads folder (the backend only uses references it knows) and returns its path.
    public async Task<string> UploadAsync(string file)
    {
        await EnsureStartedAsync();
        using var content = new ByteArrayContent(await File.ReadAllBytesAsync(file));
        using var req = new HttpRequestMessage(HttpMethod.Post, baseUrl + "/api/upload") { Content = content };
        req.Headers.Add("X-Filename", Uri.EscapeDataString(Path.GetFileName(file)));
        using var r = await http.SendAsync(req);
        var j = await ReadAsync(r);
        return j.Str("path");
    }

    static async Task<JsonElement> ReadAsync(HttpResponseMessage r)
    {
        var s = await r.Content.ReadAsStringAsync();
        JsonElement root;
        try
        {
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(s) ? "{}" : s);
            root = doc.RootElement.Clone();
        }
        catch (JsonException)
        {
            throw new BackendException($"Unexpected answer (HTTP {(int)r.StatusCode}).");
        }
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("error", out var e))
            throw new BackendException(e.ValueKind == JsonValueKind.String ? e.GetString()! : e.ToString());
        if (!r.IsSuccessStatusCode) throw new BackendException($"HTTP {(int)r.StatusCode}");
        return root;
    }

    public void Stop()
    {
        try
        {
            if (proc is { HasExited: false })
            {
                using var c = new CancellationTokenSource(800);
                try { http.PostAsync(baseUrl + "/api/quit", new StringContent("{}"), c.Token).Wait(900); } catch { }
                if (!proc.HasExited) proc.Kill(true);
            }
        }
        catch (Exception ex) { Log.Write("stop: " + ex.Message); }
    }

    static int FreePort()
    {
        var l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        int port = ((IPEndPoint)l.LocalEndpoint).Port;
        l.Stop();
        return port;
    }

    static string Last(string s, int n) => s.Length <= n ? s : s[^n..];
}

/// Puts child processes in a job that is closed (and its processes ended) when this app exits, even after a crash.
static class JobObject
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr attributes, string? name);
    [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint length);
    [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    [StructLayout(LayoutKind.Sequential)]
    struct BasicLimits
    {
        public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass, SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct IoCounters { public ulong A, B, C, D, E, F; }

    [StructLayout(LayoutKind.Sequential)]
    struct ExtendedLimits
    {
        public BasicLimits Basic;
        public IoCounters Io;
        public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
    }

    static IntPtr job;

    public static void Attach(Process p)
    {
        try
        {
            if (job == IntPtr.Zero)
            {
                job = CreateJobObject(IntPtr.Zero, null);
                var info = new ExtendedLimits { Basic = new BasicLimits { LimitFlags = 0x2000 } }; // KILL_ON_JOB_CLOSE
                int len = Marshal.SizeOf<ExtendedLimits>();
                var ptr = Marshal.AllocHGlobal(len);
                Marshal.StructureToPtr(info, ptr, false);
                SetInformationJobObject(job, 9, ptr, (uint)len); // JobObjectExtendedLimitInformation
                Marshal.FreeHGlobal(ptr);
            }
            AssignProcessToJobObject(job, p.Handle);
        }
        catch (Exception ex) { Log.Write("job object: " + ex.Message); }
    }
}

public static class Log
{
    static readonly string File = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ImageGenKit", "app.log");
    static readonly object Gate = new();

    public static void Write(string message)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(File)!);
                System.IO.File.AppendAllText(File, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {message}{Environment.NewLine}");
            }
        }
        catch { }
    }
}
