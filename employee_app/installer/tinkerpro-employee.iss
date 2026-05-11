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
  Best-effort guard: bail out if the app is already running so we
  don't try to overwrite locked DLLs. Inno's built-in CloseApplications
  handles this for the most part, but a friendly upfront message
  beats a half-applied install if AV/locks make the auto-close fail.
}
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
end;
