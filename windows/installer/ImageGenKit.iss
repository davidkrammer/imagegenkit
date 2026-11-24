; ImageGenKit for Windows installer (Inno Setup 6). Per user, no admin rights needed.
;   iscc /DAppVersion=1.2.0 windows\installer\ImageGenKit.iss   (after building and bundling into out\ImageGenKit)
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6F2B3C1E-8A4D-4F5B-9C2E-1D7A3B9E4F60}
AppName=ImageGenKit
AppVersion={#AppVersion}
AppVerName=ImageGenKit {#AppVersion}
AppPublisher=STRICS IT GmbH
AppPublisherURL=https://github.com/davidkrammer/imagegenkit
AppSupportURL=https://github.com/davidkrammer/imagegenkit/issues
DefaultDirName={localappdata}\Programs\ImageGenKit
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
OutputDir=..\..\dist
OutputBaseFilename=ImageGenKit-Setup-{#AppVersion}
SetupIconFile=..\ImageGenKit\Assets\icon.ico
UninstallDisplayIcon={app}\ImageGenKit.exe
UninstallDisplayName=ImageGenKit
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "..\..\out\ImageGenKit\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\ImageGenKit"; Filename: "{app}\ImageGenKit.exe"
Name: "{userdesktop}\ImageGenKit"; Filename: "{app}\ImageGenKit.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\ImageGenKit.exe"; Description: "Open ImageGenKit"; Flags: nowait postinstall skipifsilent
; updates install silently, then open the app again
Filename: "{app}\ImageGenKit.exe"; Flags: nowait skipifnotsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
