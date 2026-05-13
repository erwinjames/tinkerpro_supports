; TinkerPro Support — Inno Setup installer script
; ----------------------------------------------------------------------
; Builds a single .exe Setup that drops the Flutter Windows release
; bundle into Program Files, registers Start Menu + (optional) Desktop
; shortcuts, lays down an uninstaller, and offers a post-install
; checkbox to launch the app immediately.
;
; Compile with:
;     iscc.exe /Qp /Ssigntool=$qsigntool.exe sign /a /fd sha256 /t http://timestamp.digicert.com $f$q tinkerpro-employee.iss
; or just:
;     iscc.exe tinkerpro-employee.iss
;
; The GitHub Actions workflow uses the simpler invocation — we don't
; sign yet, but the AppId GUID is stable so signed and unsigned
; versions of the same install upgrade cleanly when we add signing.
;
; Build-time variables (set with /D on the command line):
;   AppVersion   — semver-style, defaults to 1.0.0 if not provided
;   SourceDir    — folder containing TpSupport.exe + DLLs + data\
;                  (defaults to ..\build\windows\x64\runner\Release
;                  so local devs can run iscc from this folder).
;   OutputDir    — where the Setup .exe gets written. Defaults to .\out
;
; ----------------------------------------------------------------------

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "out"
#endif
; Password the bundled TpSupport.exe was compiled to send for the
; tps_reader DB user. Passed through to setup-pos-and-run.ps1 in the
; [Code] post-install hook so the grant it creates matches what the
; .exe will actually present. Empty preserves XAMPP's default
; no-password behavior.
#ifndef PosPass
  #define PosPass ""
#endif

#define AppName        "TinkerPro Support"
#define AppPublisher   "TinkerPro"
#define AppExeName     "TpSupport.exe"
#define AppURL         "https://tinkerpro.io"

[Setup]
; Stable GUID — never change after the first published build, even
; across version bumps. Lets Windows recognise upgrades vs. fresh
; installs.
AppId={{8B7A6E14-6F2D-4D5E-9C2A-3FAA1EE7C501}}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
VersionInfoVersion={#AppVersion}.0
DefaultDirName={autopf}\TinkerPro Support
DefaultGroupName=TinkerPro Support
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=TpSupport-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
; Allow upgrading a running app — if TpSupport.exe is open, the
; installer asks the user to close it rather than aborting outright.
CloseApplications=force
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; \
    GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "quicklaunchicon"; Description: "Create a &Quick Launch shortcut"; \
    GroupDescription: "Additional shortcuts:"; Flags: unchecked; OnlyBelowVersion: 0,6.1

[Files]
; Recursively copy everything from the Flutter release output. This
; includes TpSupport.exe, all *.dll runtime files, the data\ folder
; (flutter_assets etc), and the bundled setup-pos-and-run.ps1.
Source: "{#SourceDir}\*"; DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Configure POS server"; \
    Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup-pos-and-run.ps1"""; \
    Comment: "Run the one-shot POS-server prep script"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#AppName}"; \
    Filename: "{app}\{#AppExeName}"; Tasks: quicklaunchicon

[Run]
; Post-install: offer to launch the app. Skipped on /SILENT runs.
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; \
    Flags: nowait postinstall skipifsilent runasoriginaluser

[UninstallDelete]
; Make sure leftover Flutter shader/state caches under the install
; tree get removed so a reinstall is truly clean. App data under
; %LOCALAPPDATA% is preserved (SharedPreferences live there).
Type: filesandordirs; Name: "{app}\data"

[Code]
{
  Two-mode setup wizard:

  - "Server" mode: this PC hosts the POS MariaDB. Installer detects
    XAMPP and runs setup-pos-and-run.ps1 silently to provision the
    tps_reader user + skip-name-resolve.

  - "Terminal" mode: this PC is a cashier register. Installer asks
    for the server's LAN address and writes a hint file at
    %PROGRAMDATA%\TinkerPro\pos_target.json. The .exe reads that
    on first launch and seeds SessionStore.posManualHost — so the
    ticket form skips LAN discovery entirely and goes straight to
    the configured server with the build's tps_reader credentials.

  Default is Server (matches the single-terminal install case, which
  is the most common). On a silent install (/SILENT) the wizard pages
  aren't shown but their defaults still apply — Server-mode auto-
  detect XAMPP, no-op if absent. So existing silent installs keep
  working without changes.
}

var
  SetupModePage: TInputOptionWizardPage;
  TerminalServerPage: TInputQueryWizardPage;

procedure InitializeWizard();
begin
  SetupModePage := CreateInputOptionPage(
    wpWelcome,
    'Setup mode',
    'Is this PC the POS server or a cashier terminal?',
    'Pick "Server" if this PC hosts the TinkerPro POS database (XAMPP).' + #13#10 +
    'Pick "Terminal" if this is a cashier register that connects to a separate POS server over the LAN.',
    True, False);
  SetupModePage.Add('Server  — this PC hosts the POS database');
  SetupModePage.Add('Terminal — cashier register, connects to a server on the LAN');
  SetupModePage.SelectedValueIndex := 0;

  TerminalServerPage := CreateInputQueryPage(
    SetupModePage.ID,
    'POS server location',
    'Where is the POS database?',
    'Enter the LAN address of the POS server. Usually a 192.168.x.x address. ' +
    'This is saved on the machine so the ticket form skips LAN discovery and ' +
    'connects directly.');
  TerminalServerPage.Add('Server IP or hostname:', False);
  TerminalServerPage.Add('Port (default 3306):', False);
  TerminalServerPage.Values[1] := '3306';
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if PageID = TerminalServerPage.ID then begin
    // Only show the server-IP page when "Terminal" is selected.
    if SetupModePage.SelectedValueIndex <> 1 then Result := True;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  HostVal: String;
begin
  Result := True;
  if CurPageID = TerminalServerPage.ID then begin
    HostVal := Trim(TerminalServerPage.Values[0]);
    if HostVal = '' then begin
      MsgBox('Please enter the POS server IP or hostname.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function FindXamppRoot(): String;
var
  Drive: String;
  Drives: TArrayOfString;
  I: Integer;
begin
  Result := '';
  SetArrayLength(Drives, 4);
  Drives[0] := 'C:\xampp';
  Drives[1] := 'D:\xampp';
  Drives[2] := 'E:\xampp';
  Drives[3] := 'F:\xampp';
  for I := 0 to GetArrayLength(Drives) - 1 do begin
    Drive := Drives[I];
    if FileExists(Drive + '\mysql\bin\mysql.exe') then begin
      Result := Drive;
      Exit;
    end;
  end;
end;

procedure ConfigurePosAsServer();
var
  XamppRoot: String;
  Ps1Path: String;
  Cmd: String;
  ResultCode: Integer;
begin
  XamppRoot := FindXamppRoot();
  if XamppRoot = '' then begin
    Log('Server mode chosen but no XAMPP detected on local drives — ' +
        'skipping PS1. The cashier can re-run "Configure POS server" ' +
        'from the Start menu after installing XAMPP.');
    Exit;
  end;
  Ps1Path := ExpandConstant('{app}\setup-pos-and-run.ps1');
  if not FileExists(Ps1Path) then begin
    Log('setup-pos-and-run.ps1 missing from install — skipping.');
    Exit;
  end;
  Log('Server mode: local XAMPP at ' + XamppRoot + ' — running PS1…');
  Cmd := '-NoProfile -ExecutionPolicy Bypass -File "' + Ps1Path + '"' +
         ' -XamppRoot "' + XamppRoot + '"' +
         ' -Unattended' +
         ' -Password "{#PosPass}"';
  if not Exec('powershell.exe', Cmd, '', SW_HIDE, ewWaitUntilTerminated,
              ResultCode) then begin
    Log('Failed to launch setup-pos-and-run.ps1.');
    Exit;
  end;
  if ResultCode <> 0 then begin
    Log('POS auto-config exited with code ' + IntToStr(ResultCode));
  end else begin
    Log('POS auto-config completed successfully.');
  end;
end;

procedure WritePosTargetHint();
var
  TargetDir, TargetFile, Json: String;
  Host, Port: String;
  PortInt: Integer;
begin
  Host := Trim(TerminalServerPage.Values[0]);
  Port := Trim(TerminalServerPage.Values[1]);
  if Host = '' then begin
    Log('Terminal mode: host blank — skipping hint write.');
    Exit;
  end;
  PortInt := StrToIntDef(Port, 3306);
  if (PortInt <= 0) or (PortInt > 65535) then PortInt := 3306;

  TargetDir := ExpandConstant('{commonappdata}\TinkerPro');
  if not DirExists(TargetDir) then begin
    if not CreateDir(TargetDir) then begin
      Log('Failed to create ' + TargetDir);
      Exit;
    end;
  end;

  TargetFile := TargetDir + '\pos_target.json';
  // Minimal JSON — Flutter side parses {host: String, port: int}.
  // No quoting of the host because we trim + the cashier can only
  // enter a hostname or IP via the wizard (no embedded quotes).
  Json := '{"host":"' + Host + '","port":' + IntToStr(PortInt) + '}';
  if not SaveStringToFile(TargetFile, Json, False) then begin
    Log('Failed to write ' + TargetFile);
    Exit;
  end;
  Log('Terminal mode: wrote POS target ' + Host + ':' + IntToStr(PortInt) +
      ' to ' + TargetFile);
end;

procedure ApplyPosSetup();
var
  Mode: Integer;
begin
  Mode := SetupModePage.SelectedValueIndex;
  if Mode = 0 then begin
    ConfigurePosAsServer();
  end else begin
    WritePosTargetHint();
  end;
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    ApplyPosSetup();
  end;
end;
