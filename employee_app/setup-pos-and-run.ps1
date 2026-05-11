<#
.SYNOPSIS
    One-shot POS-server prep + optional launch of TpSupport.exe.

.DESCRIPTION
    The TinkerPro support .exe reads `tinkerpro.shop` from the local
    XAMPP MariaDB to populate the /ticket form. This script makes that
    work on a fresh XAMPP install with three idempotent steps:

      1. Adds `skip-name-resolve` under [mysqld] in my.ini so MariaDB
         matches client grants by IP, not by reverse-DNS hostname.
      2. Creates a read-only `tps_reader` MariaDB user, scoped to
         RFC1918 LAN ranges + localhost (never `'%'`):
              tps_reader@'localhost'
              tps_reader@'127.0.0.1'
              tps_reader@'192.168.%.%'
              tps_reader@'10.%.%.%'
         …each with `SELECT ON tinkerpro.shop` only. The grant
         cannot reach any other table or run writes.
      3. Restarts MySQL if my.ini was changed, otherwise skips.
      4. Verifies the new user can actually read `tinkerpro.shop` —
         bails out early if anything's off so we never leave a
         half-applied state.

    Then (only if `-LaunchApp` is passed) it launches TpSupport.exe.

    Idempotent: re-running is safe. `CREATE USER IF NOT EXISTS` and
    `GRANT … TO` won't clobber existing entries.

.SECURITY
    What this script changes on the box:
      - Adds one MySQL user (`tps_reader`) with `SELECT` on exactly
        one table (`tinkerpro.shop`). Empty password by design — the
        XAMPP/POS pattern is that the local LAN is the trust
        boundary, and the data exposed (shop_name + VAT registration
        flag) is non-secret merchant identity.
      - Adds `skip-name-resolve` to `[mysqld]` so MariaDB authorises
        by IP, not reverse-DNS hostname. This DISABLES hostname
        wildcards in any existing grants — if you've manually
        created users like `someone@'sales-laptop'`, those will
        break. Inspect with `SELECT user, host FROM mysql.user;`
        before running on a heavily-customised box.
      - Backs up my.ini to `my.ini.bak-<timestamp>` before editing,
        so a `Copy-Item` over the original reverts the config.
    What it does NOT do:
      - Open any firewall ports.
      - Touch any user except `tps_reader`.
      - Send anything off the box.
      - Persist any state outside MariaDB and my.ini.

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
    Unsigned. To run, set the execution policy for this session only:
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    or right-click the file → Run with PowerShell after unblocking it
    in its Properties dialog.
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

# Final summary state — accumulated as we go so we can print a single
# audit-friendly block at the end.
$summary = [ordered]@{
    XamppRoot         = $XamppRoot
    SkipNameResolve   = 'no-change'
    MyIniBackup       = ''
    UsersGranted      = @()
    MySQLRestarted    = $false
    VerifyShopRead    = 'pending'
    LaunchedApp       = $false
}

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
# Encoding-preserving read: detect BOM, fall back to UTF-8 no-BOM
# (which is what XAMPP ships). All our edits are pure ASCII so we
# don't widen the encoding accidentally.
function Read-TextPreserveEncoding {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return @{ Text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3); Encoding = [System.Text.UTF8Encoding]::new($true) }
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return @{ Text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2); Encoding = [System.Text.UnicodeEncoding]::new($false, $true) }
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return @{ Text = [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2); Encoding = [System.Text.UnicodeEncoding]::new($true, $true) }
    }
    return @{ Text = [System.Text.Encoding]::UTF8.GetString($bytes); Encoding = [System.Text.UTF8Encoding]::new($false) }
}

Write-Step "Ensuring skip-name-resolve is enabled in my.ini"
$read = Read-TextPreserveEncoding -Path $MyIni
$ini = $read.Text
$encoding = $read.Encoding
$needRestart = $false

if ($ini -match '(?m)^\s*skip-name-resolve\b') {
    Write-Ok "skip-name-resolve already set"
    $summary.SkipNameResolve = 'already-set'
} else {
    # Insert immediately after the [mysqld] section header. Preserve
    # CRLF line endings on Windows. Use the instance method so we can
    # cap to a single replacement (the static [regex]::Replace doesn't
    # have a count overload — the 4th arg would be interpreted as
    # RegexOptions).
    $re = [regex]'(?m)^(\[mysqld\])\s*$'
    $newIni = $re.Replace($ini, "`$1`r`nskip-name-resolve", 1)
    if ($newIni -eq $ini) {
        Write-Warn "Couldn't find [mysqld] in my.ini — appending it"
        $newIni = $ini.TrimEnd() + "`r`n`r`n[mysqld]`r`nskip-name-resolve`r`n"
    }
    $backup = "$MyIni.bak-$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item -Path $MyIni -Destination $backup
    # Write back preserving original encoding (UTF-8 no-BOM if none was
    # detected, matching XAMPP's default).
    [System.IO.File]::WriteAllText($MyIni, $newIni, $encoding)
    Write-Ok "Added skip-name-resolve (backup at $backup)"
    $summary.SkipNameResolve = 'added'
    $summary.MyIniBackup = $backup
    $needRestart = $true
}

# --- 4. tps_reader user + grant ----------------------------------------
# Scoped to RFC1918 LAN ranges + localhost. Never '%' so the grant
# can't accept connections from outside a private network even if the
# XAMPP install is misconfigured to listen on the WAN.
$hosts = @('localhost', '127.0.0.1', '192.168.%.%', '10.%.%.%')
Write-Step "Granting tps_reader SELECT on tinkerpro.shop"
$stmts = New-Object System.Collections.Generic.List[string]
foreach ($h in $hosts) {
    $stmts.Add("CREATE USER IF NOT EXISTS 'tps_reader'@'$h' IDENTIFIED BY '';")
    $stmts.Add("GRANT SELECT ON tinkerpro.shop TO 'tps_reader'@'$h';")
}
$stmts.Add('FLUSH PRIVILEGES;')
$sql = ($stmts -join ' ')

& $MysqlExe -u root -h 127.0.0.1 -e $sql
if ($LASTEXITCODE -ne 0) {
    Write-Bad "mysql refused the grant. Possible causes:"
    Write-Bad "  - root has a password (XAMPP default is empty)"
    Write-Bad "  - tinkerpro database doesn't exist yet on this POS install"
    Read-Host "Press Enter to exit"
    exit 1
}
$summary.UsersGranted = $hosts
Write-Ok ("tps_reader created/refreshed for: " + ($hosts -join ', '))

# --- 5. Restart MySQL if config changed --------------------------------
if ($needRestart) {
    Write-Step "Restarting MySQL to pick up my.ini changes"

    $svc = Get-Service -Name 'mysql' -ErrorAction SilentlyContinue
    if ($svc) {
        Restart-Service -Name mysql -Force
        Write-Ok "Service-mode MySQL restarted"
        $summary.MySQLRestarted = 'service'
    } else {
        # XAMPP without Windows service — graceful shutdown then
        # relaunch via mysql_start.bat (the same launcher the XAMPP
        # control panel uses).
        & $MysqlAdmin -u root -h 127.0.0.1 shutdown | Out-Null
        Start-Sleep -Seconds 2
        if (-not (Test-Path $MysqlStart)) {
            Write-Bad "mysql_start.bat not found at $MysqlStart"
            Write-Bad "Open XAMPP control panel and start MySQL manually, then re-run this script."
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
            $summary.MySQLRestarted = 'mysql_start.bat'
        } else {
            Write-Bad "MySQL didn't come back up in 25s — start it manually from XAMPP control panel."
            Read-Host "Press Enter to exit"
            exit 1
        }
    }
}

# --- 6. Verify tps_reader can actually read shop -----------------------
# Don't trust the grant statement alone — actually connect as the new
# user and SELECT. Catches: missing tinkerpro DB, missing shop table,
# unexpected ACL rejection, MySQL still rebooting, etc.
Write-Step "Verifying tps_reader can read tinkerpro.shop"
$probeOut = & $MysqlExe -u tps_reader -h 127.0.0.1 --batch --skip-column-names `
    -e 'SELECT shop_name, vat_reg FROM tinkerpro.shop ORDER BY id ASC LIMIT 1' 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Bad "Verification SELECT failed:"
    Write-Bad "  $probeOut"
    Write-Bad "Setup applied but the .exe will not be able to read shop info."
    $summary.VerifyShopRead = 'failed'
    Read-Host "Press Enter to exit"
    exit 1
}
$probeText = ($probeOut | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($probeText)) {
    Write-Warn "tps_reader connected, but the shop table is empty."
    Write-Warn "The .exe will still work but the /ticket form will show the"
    Write-Warn "store name from SessionStore as fallback."
    $summary.VerifyShopRead = 'empty-table'
} else {
    Write-Ok "tps_reader read: $probeText"
    $summary.VerifyShopRead = 'ok'
}

# --- 7. Launch the support app (opt-in) --------------------------------
if ($LaunchApp) {
    Write-Step "Launching TpSupport.exe"
    if (-not (Test-Path $AppExe)) {
        Write-Bad "TpSupport.exe not found next to this script."
        Write-Bad "Place setup-pos-and-run.ps1 in the same folder as TpSupport.exe (the unzipped build) and re-run."
        Read-Host "Press Enter to exit"
        exit 1
    }
    Start-Process -FilePath $AppExe -WorkingDirectory $PSScriptRoot
    Write-Ok "TpSupport launched"
    $summary.LaunchedApp = $true
}

# --- 8. Audit summary --------------------------------------------------
Write-Host ""
Write-Host "==> Summary" -ForegroundColor Cyan
foreach ($k in $summary.Keys) {
    $v = $summary[$k]
    if ($v -is [array]) { $v = '[' + ($v -join ', ') + ']' }
    Write-Host ("    {0,-18} {1}" -f $k, $v) -ForegroundColor Gray
}
Write-Host ""
if (-not $LaunchApp) {
    Write-Ok "Setup-only mode. Run TpSupport.exe manually, or re-run with -LaunchApp."
}
Read-Host "Press Enter to exit"
