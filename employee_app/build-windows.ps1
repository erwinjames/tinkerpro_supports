# build-windows.ps1
# ---------------------------------------------------------------
# Builds the TinkerPro Employee Windows .exe pointed at the ngrok
# tunnel for testing. Run from the employee_app directory on a
# Windows machine that has Flutter + Visual Studio 2022 with the
# "Desktop development with C++" workload installed.
#
# Usage:
#   .\build-windows.ps1                # default: ngrok test URL
#   .\build-windows.ps1 -Clean         # `flutter clean` first
#   .\build-windows.ps1 -Open          # open Explorer at the output
#   .\build-windows.ps1 -BaseUrl '...' # override the URL
#
# If PowerShell refuses to run unsigned scripts, allow this one once:
#   PowerShell -ExecutionPolicy Bypass -File .\build-windows.ps1
# ---------------------------------------------------------------

param(
    [string]$BaseUrl = 'https://uninterrupted-brent-lunulate.ngrok-free.dev/tinkerpro_support',
    [string]$SoketiHost = 'uninterrupted-brent-lunulate.ngrok-free.dev',
    [int]   $SoketiPort = 443,
    [bool]  $SoketiTls = $true,
    [string]$SoketiKey = 'tinkerpro-chat-key',
    [switch]$Clean,
    [switch]$Open
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$msg) {
    Write-Host ''
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Fail([string]$msg) {
    Write-Host ''
    Write-Host "ERROR: $msg" -ForegroundColor Red
    exit 1
}

# ── 0. Sanity ─────────────────────────────────────────────────
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

if (-not (Test-Path 'pubspec.yaml')) {
    Fail "pubspec.yaml not found. Run this script from the employee_app folder."
}

Write-Step 'Verifying Flutter toolchain'
try {
    $flutterVersion = flutter --version 2>&1 | Select-Object -First 1
    Write-Host "  $flutterVersion"
} catch {
    Fail "Flutter isn't on PATH. Install per https://docs.flutter.dev/get-started/install/windows"
}

Write-Step 'Verifying Windows desktop is enabled'
$devices = flutter devices 2>&1 | Out-String
if ($devices -notmatch 'windows') {
    Write-Host '  Windows desktop not enabled — enabling it now.' -ForegroundColor Yellow
    flutter config --enable-windows-desktop | Out-Null
}

# ── 1. Optional clean ─────────────────────────────────────────
if ($Clean) {
    Write-Step 'flutter clean'
    flutter clean
    if ($LASTEXITCODE -ne 0) { Fail 'flutter clean failed' }
}

# ── 2. Resolve dependencies ───────────────────────────────────
Write-Step 'flutter pub get'
flutter pub get
if ($LASTEXITCODE -ne 0) { Fail 'flutter pub get failed' }

# ── 3. Build ──────────────────────────────────────────────────
Write-Step 'flutter build windows --release'
Write-Host "  TPS_BASE_URL      = $BaseUrl"
Write-Host "  CHAT_SOKETI_HOST  = $SoketiHost"
Write-Host "  CHAT_SOKETI_PORT  = $SoketiPort"
Write-Host "  CHAT_SOKETI_TLS   = $SoketiTls"
Write-Host "  CHAT_SOKETI_KEY   = $SoketiKey"

$tlsString = if ($SoketiTls) { 'true' } else { 'false' }

flutter build windows --release `
    --dart-define="TPS_BASE_URL=$BaseUrl" `
    --dart-define="CHAT_SOKETI_HOST=$SoketiHost" `
    --dart-define="CHAT_SOKETI_PORT=$SoketiPort" `
    --dart-define="CHAT_SOKETI_TLS=$tlsString" `
    --dart-define="CHAT_SOKETI_KEY=$SoketiKey"

if ($LASTEXITCODE -ne 0) {
    Fail @"
Build failed. Common causes:
  - Visual Studio 2022 missing the 'Desktop development with C++' workload
    (open Visual Studio Installer → Modify → check that workload).
  - Flutter SDK out of date (`flutter upgrade`).
  - Stale build cache (rerun with -Clean).
"@
}

# ── 4. Verify output + summary ────────────────────────────────
$outDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$exe    = Join-Path $outDir    'TpSupport.exe'

if (-not (Test-Path $exe)) {
    Fail "Build reported success but $exe is missing. Check build/windows/ logs."
}

$exeSize  = [math]::Round(((Get-Item $exe).Length / 1MB), 1)
$dirSize  = [math]::Round((
    Get-ChildItem $outDir -Recurse | Measure-Object -Property Length -Sum
).Sum / 1MB, 1)

Write-Step 'Build complete'
Write-Host "  exe:        $exe ($exeSize MB)"
Write-Host "  bundle dir: $outDir ($dirSize MB total — ship the WHOLE folder, not just the exe)"

if ($Open) {
    Start-Process explorer.exe $outDir
}

Write-Host ''
Write-Host 'To run on this machine:' -ForegroundColor Green
Write-Host "  & '$exe'"
Write-Host ''
Write-Host 'To distribute, zip the entire Release folder:' -ForegroundColor Green
Write-Host "  Compress-Archive -Path '$outDir\*' -DestinationPath 'TpSupport-windows-x64.zip'"
Write-Host ''
