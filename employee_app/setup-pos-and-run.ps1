<#
.SYNOPSIS
    One-shot POS-server prep + launch of TpSupport.exe.

.DESCRIPTION
    The TinkerPro support .exe reads `tinkerpro.shop` from the local
    XAMPP MariaDB to populate the /ticket form. This script makes that
    work on a fresh XAMPP install with three idempotent steps:

      1. Adds `skip-name-resolve` under [mysqld] in my.ini so MariaDB
         matches client grants by IP, not by reverse-DNS hostname.
         (Without this, a LAN client connecting from 192.168.1.x can
         get rejected as `tps_reader@'<their-hostname>'` because the
         wildcard is IP-shaped.)
      2. Creates a read-only `tps_reader@'%'` user with `SELECT ON
         tinkerpro.shop` — that's all the support .exe needs.
      3. Restarts MySQL if my.ini was changed, otherwise skips.

    Then it launches TpSupport.exe from the same folder.

    Run this once per POS server. It auto-elevates if you launched it
    without admin (needed to edit my.ini and restart MySQL).

.PARAMETER XamppRoot
    Path to the XAMPP install. Defaults to C:\xampp.

.PARAMETER LaunchApp
    Switch — if set, the script also opens TpSupport.exe after setup
    finishes. Default OFF so a tech can run setup in isolation,
    inspect the result, and only launch the app when ready. Flip this
    on (or pass -LaunchApp) once we're done iterating on the test
    flow and want a single "unzip → run → done" experience for
    customer installs.

.EXAMPLE
    PS C:\Users\you\Downloads\TpSupport> .\setup-pos-and-run.ps1
    Sets up MariaDB only; does not launch the app.

.EXAMPLE
    PS C:\Users\you\Downloads\TpSupport> .\setup-pos-and-run.ps1 -LaunchApp
    Sets up MariaDB and launches TpSupport.exe.

.NOTES
    Idempotent: re-running is safe. Inserts skip-name-resolve only if
    not already present; `CREATE USER IF NOT EXISTS` won't clobber an
    existing user.
#>

[CmdletBinding()]
param(
    [string]$XamppRoot = 'C:\xampp',
    [switch]$LaunchApp
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok  ($msg) { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    $msg" -ForegroundColor Yellow }
function Write-Bad ($msg) { Write-Host "    $msg" -ForegroundColor Red    }

# --- 0. Self-elevate ---------------------------------------------------
# Editing my.ini under Program Files / C:\xampp typically needs admin,
# and so does restarting the MySQL service. Re-launch elevated if we
# aren't already.
$me = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warn "Not running as admin — relaunching elevated…"
    $relaunchArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`"",
        '-XamppRoot', "`"$XamppRoot`""
    )
    if ($LaunchApp) { $relaunchArgs += '-LaunchApp' }
    Start-Process powershell -Verb RunAs -ArgumentList $relaunchArgs
    exit
}

# --- 1. Locate XAMPP ---------------------------------------------------
$MyIni      = Join-Path $XamppRoot 'mysql\bin\my.ini'
$MysqlExe   = Join-Path $XamppRoot 'mysql\bin\mysql.exe'
$MysqlAdmin = Join-Path $XamppRoot 'mysql\bin\mysqladmin.exe'
$MysqlStart = Join-Path $XamppRoot 'mysql_start.bat'
$AppExe     = Join-Path $PSScriptRoot 'TpSupport.exe'

Write-Step "Checking XAMPP at $XamppRoot"
foreach ($p in @($MyIni, $MysqlExe, $MysqlAdmin)) {
    if (-not (Test-Path $p)) {
        Write-Bad "Missing: $p"
        Write-Bad "Pass -XamppRoot pointing to your XAMPP folder (e.g. -XamppRoot 'D:\xampp')."
        Read-Host "Press Enter to exit"
        exit 1
    }
}
Write-Ok "XAMPP found"

# --- 2. Make sure MySQL is running -------------------------------------
function Test-MysqlUp {
    & $MysqlAdmin -u root -h 127.0.0.1 --silent ping 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

Write-Step "Checking MySQL is running"
if (-not (Test-MysqlUp)) {
    Write-Warn "MySQL is not running — start it from XAMPP control panel, then re-run this script."
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Ok "MySQL is up"

# --- 3. skip-name-resolve in my.ini ------------------------------------
Write-Step "Ensuring skip-name-resolve is enabled in my.ini"
$ini = Get-Content $MyIni -Raw
$needRestart = $false

if ($ini -match '(?m)^\s*skip-name-resolve\b') {
    Write-Ok "skip-name-resolve already set"
} else {
    # Insert immediately after the [mysqld] section header. Preserve
    # CRLF line endings on Windows.
    $newIni = [regex]::Replace(
        $ini,
        '(?m)^(\[mysqld\])\s*$',
        "`$1`r`nskip-name-resolve",
        1  # only the first match
    )
    if ($newIni -eq $ini) {
        Write-Warn "Couldn't find [mysqld] in my.ini — appending it"
        $newIni = $ini.TrimEnd() + "`r`n`r`n[mysqld]`r`nskip-name-resolve`r`n"
    }
    $backup = "$MyIni.bak-$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item -Path $MyIni -Destination $backup
    # -NoNewline avoids a stray trailing LF being added by Set-Content.
    Set-Content -Path $MyIni -Value $newIni -NoNewline -Encoding ASCII
    Write-Ok "Added skip-name-resolve (backup at $backup)"
    $needRestart = $true
}

# --- 4. tps_reader user + grant ----------------------------------------
Write-Step "Granting tps_reader@'%' SELECT on tinkerpro.shop"
# Single-line SQL keeps cross-version shell quoting predictable.
$sql = "CREATE USER IF NOT EXISTS 'tps_reader'@'%' IDENTIFIED BY ''; GRANT SELECT ON tinkerpro.shop TO 'tps_reader'@'%'; FLUSH PRIVILEGES;"
& $MysqlExe -u root -h 127.0.0.1 -e $sql
if ($LASTEXITCODE -ne 0) {
    Write-Bad "mysql refused the grant. Possible causes:"
    Write-Bad "  - root has a password (XAMPP default is empty)"
    Write-Bad "  - tinkerpro database doesn't exist yet on this POS install"
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Ok "tps_reader is ready"

# --- 5. Restart MySQL if config changed --------------------------------
if ($needRestart) {
    Write-Step "Restarting MySQL to pick up my.ini changes"

    $svc = Get-Service -Name 'mysql' -ErrorAction SilentlyContinue
    if ($svc) {
        Restart-Service -Name mysql -Force
        Write-Ok "Service-mode MySQL restarted"
    } else {
        # XAMPP without Windows service — graceful shutdown then
        # relaunch via mysql_start.bat (the same launcher the XAMPP
        # control panel uses).
        & $MysqlAdmin -u root -h 127.0.0.1 shutdown | Out-Null
        Start-Sleep -Seconds 2
        if (-not (Test-Path $MysqlStart)) {
            Write-Bad "mysql_start.bat not found at $MysqlStart"
            Write-Bad "Open XAMPP control panel and start MySQL manually, then run TpSupport.exe."
            Read-Host "Press Enter to exit"
            exit 1
        }
        Start-Process -FilePath $MysqlStart -WorkingDirectory $XamppRoot -WindowStyle Hidden
        Write-Host -NoNewline "    Waiting for MySQL"
        $deadline = (Get-Date).AddSeconds(25)
        while ((Get-Date) -lt $deadline) {
            if (Test-MysqlUp) { break }
            Start-Sleep -Milliseconds 500
            Write-Host -NoNewline "."
        }
        Write-Host ""
        if (Test-MysqlUp) {
            Write-Ok "MySQL is back up"
        } else {
            Write-Bad "MySQL didn't come back up in 25s — start it manually from XAMPP control panel."
            Read-Host "Press Enter to exit"
            exit 1
        }
    }
}

# --- 6. Launch the support app (opt-in) --------------------------------
if ($LaunchApp) {
    Write-Step "Launching TpSupport.exe"
    if (-not (Test-Path $AppExe)) {
        Write-Bad "TpSupport.exe not found next to this script."
        Write-Bad "Place setup-pos-and-run.ps1 in the same folder as TpSupport.exe (the unzipped build) and re-run."
        Read-Host "Press Enter to exit"
        exit 1
    }
    Start-Process -FilePath $AppExe -WorkingDirectory $PSScriptRoot
    Write-Ok "TpSupport launched — you can close this window."
} else {
    Write-Step "Setup complete"
    Write-Ok "Skipping app launch (testing mode). Run TpSupport.exe manually,"
    Write-Ok "or re-run this script with -LaunchApp once you're done iterating."
    Read-Host "Press Enter to exit"
}
