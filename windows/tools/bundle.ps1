# Puts the imagegenkit command (cli\), the catalogs, the skill and an embedded Python (python\) next to ImageGenKit.exe,
# so the app needs nothing else installed.
#   pwsh windows\tools\bundle.ps1 -Dir out\ImageGenKit
param([Parameter(Mandatory = $true)][string]$Dir)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$Dir = (Resolve-Path $Dir).Path

$cli = Join-Path $Dir 'cli'
New-Item -ItemType Directory -Force (Join-Path $cli 'app') | Out-Null
foreach ($f in 'imagegenkit.py', 'imagegenkit_app.py') { Copy-Item (Join-Path $repo "cli\$f") $cli -Force }
Copy-Item (Join-Path $repo 'cli\app\*') (Join-Path $cli 'app') -Force
Copy-Item (Join-Path $repo 'catalog\local.json') $cli -Force
Copy-Item (Join-Path $repo 'catalog\providers.json') $cli -Force
Copy-Item (Join-Path $repo 'skill\SKILL.md') $cli -Force

# Python 3.14 embeddable package from python.org, pinned by its SHA-256
$version = '3.14.10'
$sha256 = '90905e64a840557d8c1bc4f5b74db3d7ee85e3ffb217611cac1c7813acea4159'
$zip = Join-Path $env:TEMP "python-$version-embed-amd64.zip"
Invoke-WebRequest -UseBasicParsing "https://www.python.org/ftp/python/$version/python-$version-embed-amd64.zip" -OutFile $zip
$got = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
if ($got -ne $sha256) { throw "Python download checksum mismatch: $got" }
$py = Join-Path $Dir 'python'
Remove-Item -Recurse -Force $py -ErrorAction SilentlyContinue
Expand-Archive $zip $py
Remove-Item $zip
& (Join-Path $py 'python.exe') -c "import ssl, ctypes, http.server, json, zipfile, sys; print('bundled python', sys.version.split()[0], ssl.OPENSSL_VERSION)"
if ($LASTEXITCODE) { throw 'the bundled python does not start' }
& (Join-Path $py 'python.exe') (Join-Path $cli 'imagegenkit.py') --version
