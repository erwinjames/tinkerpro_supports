; TinkerPro Support — Desktop Console · Inno Setup installer
; ----------------------------------------------------------------------
; Wraps the Flutter Windows release bundle into a single Setup .exe:
; copies the app into Program Files, adds Start Menu + optional Desktop
; shortcuts, writes an uninstaller, and offers to launch on finish.
;
; Unlike the employee_app installer, the support console has no POS /
; MariaDB provisioning — it just talks to https://support.tinkerpro.io —
; so there is no [Code] wizard or post-install script here.
;
; Compile:  iscc.exe tinkerpro-support-desktop.iss
;
; Build-time variables (set with /D):
;   AppVersion — semver, defaults to 1.0.0
;   SourceDir  — folder with support_desktop.exe + DLLs + data\
;                (defaults to ..\build\windows\x64\runner\Release)
;   OutputDir  — where Setup .exe is written (defaults to .\out)
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

#define AppName        "TinkerPro Support Console"
#define AppPublisher   "TinkerPro"
#define AppExeName     "support_desktop.exe"
#define AppURL         "https://tinkerpro.io"

[Setup]
; Stable GUID — never change after the first published build so Windows
; recognises upgrades vs. fresh installs. (Distinct from employee_app's.)
AppId={{2C9F4D8B-71E6-4A3C-B5D2-9E1A77C4F210}}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
VersionInfoVersion={#AppVersion}.0
DefaultDirName={autopf}\TinkerPro Support Console
DefaultGroupName=TinkerPro Support Console
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=TinkerProSupport-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
; If the app is running during an upgrade, ask the user to close it.
CloseApplications=force
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; \
    GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
; Recursively copy the whole Flutter release output — the .exe alone
; won't run without its DLLs and data\flutter_assets\.
Source: "{#SourceDir}\*"; DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; \
    Flags: nowait postinstall skipifsilent runasoriginaluser

[UninstallDelete]
; Remove leftover Flutter shader/state caches under the install tree so
; a reinstall is clean. User prefs live under %APPDATA% and are kept.
Type: filesandordirs; Name: "{app}\data"
