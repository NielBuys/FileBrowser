; Inno Setup script for File Browser.
; Build:  installer\build-installer.ps1   (builds the exe, then this script)
; or:     "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\FileBrowser.iss

#define AppName "File Browser"
#define AppExe "FileBrowser.exe"
#define AppVersion GetVersionNumbersString(AddBackslash(SourcePath) + "..\" + AppExe)

[Setup]
AppId={{C4DADE34-BF94-4E63-80A4-C9D4004CA0E7}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#AppVersion}
VersionInfoDescription={#AppName} Setup
; Installs for the current user without admin rights by default
; (%LOCALAPPDATA%\Programs\File Browser). The first page lets you pick
; "all users" instead, which asks for admin rights.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
SetupIconFile=..\FileBrowser.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
; Close a running File Browser before replacing the exe
CloseApplications=yes
RestartApplications=no
OutputDir=Output
OutputBaseFilename=FileBrowser-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "explorermenu"; Description: "Add ""Open in File Browser"" to the right-click menu of folders"; GroupDescription: "File Explorer:"

[Files]
Source: "..\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; Right-click a folder -> Open in File Browser
Root: HKA; Subkey: "Software\Classes\Directory\shell\FileBrowser"; ValueType: string; ValueName: ""; ValueData: "Open in File Browser"; Flags: uninsdeletekey; Tasks: explorermenu
Root: HKA; Subkey: "Software\Classes\Directory\shell\FileBrowser"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\{#AppExe}"",0"; Tasks: explorermenu
Root: HKA; Subkey: "Software\Classes\Directory\shell\FileBrowser\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: explorermenu
; Right-click the empty space inside a folder -> Open in File Browser
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\FileBrowser"; ValueType: string; ValueName: ""; ValueData: "Open in File Browser"; Flags: uninsdeletekey; Tasks: explorermenu
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\FileBrowser"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\{#AppExe}"",0"; Tasks: explorermenu
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\FileBrowser\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%V"""; Tasks: explorermenu

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

; Settings (last folder, open tabs, window size) live in
; %LOCALAPPDATA%\FileBrowser\FileBrowser.ini and are kept on uninstall,
; so a reinstall picks up where you left off.
