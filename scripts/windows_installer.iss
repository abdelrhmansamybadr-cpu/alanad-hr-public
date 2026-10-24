; Inno Setup script: packs the Al Anad HR Windows app into a normal Setup .exe.
;
; 1) Build the app:   cd mobile_app && flutter build windows --release
; 2) Compile:         "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" scripts\windows_installer.iss
;    Output:          dist-installer\AlAnad-HR-Setup-<version>.exe
; Bump AppVersion together with `version:` in mobile_app/pubspec.yaml.

#define AppName "Al Anad HR"
#define AppVersion "1.2.0"
#define AppExe "hr_mobile_app.exe"
#define BuildDir "..\mobile_app\build\windows\x64\runner\Release"

[Setup]
; Fixed id so a newer Setup upgrades the installed app instead of installing a second copy.
AppId={{6B1F2C58-4D0E-4F7A-9C35-A1A4D0C3E7B2}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Al Anad
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
SetupIconFile=..\mobile_app\windows\runner\resources\app_icon.ico
OutputDir=..\dist-installer
OutputBaseFilename=AlAnad-HR-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Installs for the current user without admin rights; the user can still choose "all users".
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
