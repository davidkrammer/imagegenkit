# Screenshots of the Windows app with demo data (GitHub Actions or any Windows PC).
#   powershell -ExecutionPolicy Bypass -File windows\tools\screenshots.ps1 -App out\ImageGenKit\ImageGenKit.exe -Out shots
param(
    [Parameter(Mandatory = $true)][string]$App,
    [string]$Out = 'shots',
    [switch]$WebApp
)
$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = Resolve-Path $Out

Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class Shot {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT r, int size);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
        public int dmPositionX, dmPositionY; public int dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }
    [DllImport("user32.dll")] static extern int EnumDisplaySettings(string name, int mode, ref DEVMODE dm);
    [DllImport("user32.dll")] static extern int ChangeDisplaySettings(ref DEVMODE dm, int flags);

    public static string SetResolution(int w, int h) {
        var dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        EnumDisplaySettings(null, -1, ref dm);
        dm.dmPelsWidth = w; dm.dmPelsHeight = h; dm.dmFields = 0x80000 | 0x100000;
        return "ChangeDisplaySettings: " + ChangeDisplaySettings(ref dm, 0);
    }

    public static void Front(IntPtr h) {
        ShowWindow(h, 9);
        SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002); // topmost, keep size and position
        SetForegroundWindow(h);
    }

    public static int[] Bounds(IntPtr h) {
        RECT r;
        if (DwmGetWindowAttribute(h, 9, out r, Marshal.SizeOf(typeof(RECT))) != 0) GetWindowRect(h, out r);
        return new[] { r.Left, r.Top, (r.Right - r.Left) / 2 * 2, (r.Bottom - r.Top) / 2 * 2 };
    }

    public static string Save(IntPtr h, string path) {
        RECT r;
        if (DwmGetWindowAttribute(h, 9, out r, Marshal.SizeOf(typeof(RECT))) != 0) GetWindowRect(h, out r);
        int w = r.Right - r.Left, ht = r.Bottom - r.Top;
        using (var bmp = new Bitmap(w, ht)) {
            using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(r.Left, r.Top, 0, 0, new Size(w, ht));
            bmp.Save(path, ImageFormat.Png);
        }
        return w + "x" + ht;
    }
}
'@

Write-Host ([Shot]::SetResolution(1920, 1080))
Start-Sleep 2
Write-Host "Screen: $([System.Windows.Forms.Screen]::PrimaryScreen.Bounds)"

# Demo profile (only demo images and made-up prompts)
$demoProfile = Join-Path $env:RUNNER_TEMP 'igk-demo'
if (-not $env:RUNNER_TEMP) { $demoProfile = Join-Path $env:TEMP 'igk-demo' }
Remove-Item -Recurse -Force $demoProfile -ErrorAction SilentlyContinue
$py = (Get-Command python).Source
& $py (Join-Path $repo 'windows\demo\make_demo.py') $demoProfile

# The demo profile has accepted the terms and seen the tour; a fresh one (no prefs) shows the terms screen first.
function Write-Prefs([string]$roaming) {
    New-Item -ItemType Directory -Force (Join-Path $roaming 'ImageGenKit') | Out-Null
    '{ "termsVersion": 1, "tourVersion": 1 }' | Set-Content -Encoding utf8 (Join-Path $roaming 'ImageGenKit\prefs.json')
}
Write-Prefs (Join-Path $demoProfile 'AppData\Roaming')
$freshRoaming = Join-Path $demoProfile 'AppData\Fresh'
New-Item -ItemType Directory -Force $freshRoaming | Out-Null
$emptyProfile = "$demoProfile-empty"
Remove-Item -Recurse -Force $emptyProfile -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $emptyProfile | Out-Null
Write-Prefs (Join-Path $emptyProfile 'AppData\Roaming')

function Start-App([string]$exe, [string[]]$arguments, [string]$cwd, [string]$roaming = '', [string]$userProfile = '') {
    if (-not $userProfile) { $userProfile = $demoProfile }
    if (-not $roaming) { $roaming = Join-Path $userProfile 'AppData\Roaming' }
    $psi = New-Object System.Diagnostics.ProcessStartInfo $exe
    $psi.Arguments = ($arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $cwd
    $psi.EnvironmentVariables['USERPROFILE'] = $userProfile
    $psi.EnvironmentVariables['HOME'] = $userProfile
    $psi.EnvironmentVariables['APPDATA'] = $roaming
    $psi.EnvironmentVariables['OPENAI_API_KEY'] = 'sk-demo'
    $psi.EnvironmentVariables['GEMINI_API_KEY'] = 'demo'
    $psi.EnvironmentVariables['IMAGEGENKIT_NO_UPDATE'] = '1'
    return [System.Diagnostics.Process]::Start($psi)
}

function Wait-Window($proc, [int]$seconds = 40) {
    for ($i = 0; $i -lt $seconds * 2; $i++) {
        $proc.Refresh()
        if ($proc.MainWindowHandle -ne [IntPtr]::Zero) { return $proc.MainWindowHandle }
        if ($proc.HasExited) { throw "the app exited with code $($proc.ExitCode)" }
        Start-Sleep -Milliseconds 500
    }
    throw 'no window'
}

$shots = @(
    @{ Name = '01-overview-light'; Args = @('--page', 'overview', '--theme', 'light') },
    @{ Name = '02-overview-dark'; Args = @('--page', 'overview', '--theme', 'dark') },
    @{ Name = '03-gallery-light'; Args = @('--page', 'gallery', '--theme', 'light', '--select-latest') },
    @{ Name = '04-history-dark'; Args = @('--page', 'history', '--theme', 'dark', '--select-latest') },
    @{ Name = '05-generate-light'; Args = @('--page', 'generate', '--theme', 'light', '--prompt', 'A sage green ceramic mug on a light oak table, soft morning light') },
    @{ Name = '06-generate-dark'; Args = @('--page', 'generate', '--theme', 'dark') },
    @{ Name = '07-settings-providers-light'; Args = @('--page', 'settings', '--theme', 'light', '--settings-section', 'providers') },
    @{ Name = '08-settings-local-dark'; Args = @('--page', 'settings', '--theme', 'dark', '--settings-section', 'local') },
    @{ Name = '09-settings-use-light'; Args = @('--page', 'settings', '--theme', 'light', '--settings-section', 'use') },
    @{ Name = '10-settings-limits-dark'; Args = @('--page', 'settings', '--theme', 'dark', '--settings-section', 'limits') },
    @{ Name = '11-settings-agents-light'; Args = @('--page', 'settings', '--theme', 'light', '--settings-section', 'agents') },
    @{ Name = '12-terms-light'; Args = @('--page', 'overview', '--theme', 'light'); Roaming = $freshRoaming },
    @{ Name = '13-terms-dark'; Args = @('--page', 'overview', '--theme', 'dark'); Roaming = $freshRoaming },
    @{ Name = '14-tour-welcome-light'; Args = @('--page', 'overview', '--theme', 'light', '--tour', '0') },
    @{ Name = '15-tour-demo-light'; Args = @('--page', 'overview', '--theme', 'light', '--tour', '1', '--tour-showme'); Wait = 15 },
    @{ Name = '16-tour-gallery-dark'; Args = @('--page', 'overview', '--theme', 'dark', '--tour', '2') },
    @{ Name = '17-tour-provider-light'; Args = @('--page', 'overview', '--theme', 'light', '--tour', '3') },
    @{ Name = '18-tour-agents-dark'; Args = @('--page', 'overview', '--theme', 'dark', '--tour', '4'); Wait = 12 },
    @{ Name = '19-tour-done-light'; Args = @('--page', 'overview', '--theme', 'light', '--tour', '5') },
    @{ Name = '20-overview-empty-light'; Args = @('--page', 'overview', '--theme', 'light'); Profile = $emptyProfile }
)

$exe = (Resolve-Path $App).Path
$failed = 0
foreach ($s in $shots) {
    $p = Start-App $exe ($s.Args + @('--size', '1360x880')) (Split-Path $exe) $s.Roaming $s.Profile
    try {
        $h = Wait-Window $p
        Start-Sleep $(if ($s.Wait) { $s.Wait } else { 9 })   # backend start, data, images
        [Shot]::Front($h)
        Start-Sleep 2
        $size = [Shot]::Save($h, (Join-Path $Out "$($s.Name).png"))
        Write-Host "$($s.Name): $size"
    } catch {
        Write-Host "$($s.Name) FAILED: $_"
        $failed++
    } finally {
        if (-not $p.HasExited) { $p.Kill() }
        Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt $p.StartTime } | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep 1
    }
}

# A short video of the tour's hands-on demo ("Show me"), when ffmpeg is there
$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($ffmpeg) {
    $p = Start-App $exe @('--page', 'overview', '--theme', 'light', '--tour', '1', '--tour-showme', '--size', '1360x880') (Split-Path $exe)
    try {
        $h = Wait-Window $p
        [Shot]::Front($h)
        $b = [Shot]::Bounds($h)
        & $ffmpeg.Source -y -loglevel error -f gdigrab -framerate 24 -offset_x $b[0] -offset_y $b[1] -video_size "$($b[2])x$($b[3])" -i desktop `
            -t 16 -vf 'scale=1280:-2' -c:v libx264 -crf 24 -pix_fmt yuv420p (Join-Path $Out 'tour-demo.mp4')
        Write-Host "video: $LASTEXITCODE"
    } catch { Write-Host "video FAILED: $_" }
    finally {
        if (-not $p.HasExited) { $p.Kill() }
        Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt $p.StartTime } | Stop-Process -Force -ErrorAction SilentlyContinue
    }
} else { Write-Host 'no ffmpeg: no video' }

if ($WebApp) {
    # The web version from the port (imagegenkit app), for comparison
    $web = Start-App $py @((Join-Path $repo 'cli\imagegenkit.py'), 'app', '--port', '8811') $repo
    Start-Sleep 12
    $edge = Get-Process msedge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
    if ($edge) {
        [Shot]::Front($edge.MainWindowHandle)
        Start-Sleep 3
        Write-Host "web: $([Shot]::Save($edge.MainWindowHandle, (Join-Path $Out '00-web-version.png')))"
        $edge | Stop-Process -Force
    } else { Write-Host 'web version: no Edge window' }
    if (-not $web.HasExited) { $web.Kill() }
}

$log = Join-Path $env:LOCALAPPDATA 'ImageGenKit\app.log'
if (Test-Path $log) { Copy-Item $log (Join-Path $Out 'app.log') }
if ($failed) { throw "$failed screenshot(s) failed" }
