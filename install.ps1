# ImageGenKit installer for Windows: the `imagegenkit` command, the ImageGenKit app and the agent skill.
#   irm https://raw.githubusercontent.com/davidkrammer/imagegenkit/main/install.ps1 | iex
# or, from a checkout:  powershell -ExecutionPolicy Bypass -File install.ps1
#
# Installs to %USERPROFILE%\.local\share\imagegenkit, puts `imagegenkit` in %USERPROFILE%\.local\bin (added to your
# user PATH), adds ImageGenKit to the Start menu, and installs the skill for Claude Code and Codex if they're present.
# Needs Python 3.9+ (python.org or `winget install Python.Python.3.13`). Nothing else.

function Install-ImageGenKit {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $Raw   = if ($env:IMAGEGENKIT_RAW) { $env:IMAGEGENKIT_RAW } else { 'https://raw.githubusercontent.com/davidkrammer/imagegenkit/main' }
    $Share = Join-Path $env:USERPROFILE '.local\share\imagegenkit'
    $Bin   = Join-Path $env:USERPROFILE '.local\bin'
    $Conf  = Join-Path $env:USERPROFILE '.config\imagegenkit'
    $Local = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'cli\imagegenkit.py'))) { $PSScriptRoot } else { $null }

    # --- Python 3.9+ (the Microsoft Store "python" stub doesn't count) ---
    function Find-Python {
        $candidates = @()
        if (Get-Command py -ErrorAction SilentlyContinue) { $candidates += ,@('py', '-3') }
        foreach ($n in 'python', 'python3') {
            $c = Get-Command $n -ErrorAction SilentlyContinue
            if ($c -and $c.Source -notmatch 'WindowsApps') { $candidates += ,@($c.Source) }
        }
        foreach ($c in $candidates) {
            try {
                $args_ = @($c | Select-Object -Skip 1) + @('-c', 'import sys; print(sys.executable); sys.exit(0 if sys.version_info >= (3, 9) else 1)')
                $exe = & $c[0] @args_ 2>$null
                if ($LASTEXITCODE -eq 0 -and $exe) { return @{ Cmd = $c; Exe = ($exe | Select-Object -Last 1).Trim() } }
            } catch { }
        }
        return $null
    }
    $py = Find-Python
    if (-not $py) {
        Write-Host "imagegenkit needs Python 3.9 or newer. Install it, then run this again:" -ForegroundColor Yellow
        Write-Host "  winget install Python.Python.3.13      (or https://www.python.org/downloads/)"
        return
    }
    $pyExe  = $py.Exe
    $pywExe = Join-Path (Split-Path $pyExe) 'pythonw.exe'
    if (-not (Test-Path $pywExe)) { $pywExe = $pyExe }

    # --- files ---
    $files = [ordered]@{
        'cli/imagegenkit.py'      = 'imagegenkit.py'
        'cli/imagegenkit_app.py'  = 'imagegenkit_app.py'
        'cli/app/index.html'      = 'app\index.html'
        'cli/app/app.js'          = 'app\app.js'
        'cli/app/app.css'         = 'app\app.css'
        'cli/app/icon.svg'        = 'app\icon.svg'
        'cli/app/icon.ico'        = 'app\icon.ico'
        'catalog/local.json'      = 'local.json'
        'catalog/providers.json'  = 'providers.json'
        'skill/SKILL.md'          = 'SKILL.md'
    }
    New-Item -ItemType Directory -Force (Join-Path $Share 'app'), $Bin, $Conf | Out-Null
    foreach ($src in $files.Keys) {
        $dest = Join-Path $Share $files[$src]
        $tmp = "$dest.tmp"
        if ($Local) {
            Copy-Item (Join-Path $Local ($src -replace '/', '\')) $tmp -Force
        } else {
            try { Invoke-WebRequest -UseBasicParsing "$Raw/$src" -OutFile $tmp }
            catch { Remove-Item $tmp -ErrorAction SilentlyContinue; Write-Host "Couldn't download $Raw/$src. Check your internet connection and try again." -ForegroundColor Red; return }
        }
        Move-Item $tmp $dest -Force
    }

    # --- the command: a .cmd for PowerShell/cmd and a sh script for Git Bash (which Claude Code and Codex use) ---
    $script = Join-Path $Share 'imagegenkit.py'
    Set-Content -Encoding ascii (Join-Path $Bin 'imagegenkit.cmd') "@`"$pyExe`" `"$script`" %*"
    $shPy = $pyExe -replace '\\', '/'
    if ($shPy -match '^([A-Za-z]):(.*)$') { $shPy = '/' + $Matches[1].ToLower() + $Matches[2] }
    $sh = "#!/bin/sh`nexec `"$shPy`" `"`$HOME/.local/share/imagegenkit/imagegenkit.py`" `"`$@`"`n"
    [IO.File]::WriteAllText((Join-Path $Bin 'imagegenkit'), $sh, (New-Object Text.UTF8Encoding $false))

    # --- PATH (user) ---
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($env:IMAGEGENKIT_NO_PATH) {
        Write-Host "Not changing PATH (IMAGEGENKIT_NO_PATH)."
    } elseif (-not (($userPath -split ';') -contains $Bin)) {
        [Environment]::SetEnvironmentVariable('Path', ((@($userPath, $Bin) | Where-Object { $_ }) -join ';'), 'User')
        $env:Path = "$env:Path;$Bin"
        Write-Host "Added $Bin to your PATH (new terminals pick it up)."
    }

    # --- Start menu ---
    $programs = if ($env:IMAGEGENKIT_START_MENU) { $env:IMAGEGENKIT_START_MENU } else { [Environment]::GetFolderPath('Programs') }
    $lnk = Join-Path $programs 'ImageGenKit.lnk'
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = $pywExe
    $s.Arguments = "`"$script`" app"
    $s.WorkingDirectory = $env:USERPROFILE
    $s.IconLocation = (Join-Path $Share 'app\icon.ico')
    $s.Description = 'ImageGenKit: AI images with the accounts you already have'
    $s.Save()

    # --- agent skills ---
    foreach ($dir in (Join-Path $env:USERPROFILE '.claude'), (Join-Path $env:USERPROFILE '.codex')) {
        if (Test-Path $dir) {
            $skillDir = Join-Path $dir 'skills\imagegenkit'
            New-Item -ItemType Directory -Force $skillDir | Out-Null
            Copy-Item (Join-Path $Share 'SKILL.md') (Join-Path $skillDir 'SKILL.md') -Force
            Write-Host "Skill installed for $((Split-Path $dir -Leaf).TrimStart('.'))"
        }
    }

    # --- provider list cache (the command refreshes it once a day) ---
    $cat = Join-Path $Conf 'catalog.json'
    if (-not (Test-Path $cat)) { Copy-Item (Join-Path $Share 'providers.json') $cat }

    $ver = & $pyExe $script --version
    Write-Host "Installed $ver" -ForegroundColor Green
    Write-Host ""
    Write-Host "Open ImageGenKit from the Start menu (or run: imagegenkit app) to connect a provider."
    Write-Host "Or from a terminal:  imagegenkit set-key openai"
}

Install-ImageGenKit
