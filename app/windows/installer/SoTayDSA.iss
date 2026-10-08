; Bộ cài Windows (Inno Setup). CI gọi: ISCC /DAppVersion=x.y.z /DSourceDir=<thư mục Release> SoTayDSA.iss
#ifndef AppVersion
  #define AppVersion "3.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{6C1B7E8A-3E52-4E0B-9D7A-50A7D5A1C0DE}
AppName=Sổ tay DSA C++
AppVersion={#AppVersion}
AppPublisher=quocdat16610
DefaultDirName={localappdata}\Programs\SoTayDSA
DefaultGroupName=Sổ tay DSA C++
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=SoTayDSA-Setup-{#AppVersion}
OutputDir=..\..\dist
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\SoTayDSA.exe
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
CloseApplications=force
RestartApplications=no

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Sổ tay DSA C++"; Filename: "{app}\SoTayDSA.exe"
Name: "{autodesktop}\Sổ tay DSA C++"; Filename: "{app}\SoTayDSA.exe"; Tasks: desktopicon

[Registry]
; Bấm đúp file .dsanote.json để mở bằng app
Root: HKCU; Subkey: "Software\Classes\.dsanote.json"; ValueType: string; ValueData: "SoTayDSA.Notebook"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\SoTayDSA.Notebook"; ValueType: string; ValueData: "Notebook Sổ tay DSA"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\SoTayDSA.Notebook\DefaultIcon"; ValueType: string; ValueData: "{app}\SoTayDSA.exe,0"
Root: HKCU; Subkey: "Software\Classes\SoTayDSA.Notebook\shell\open\command"; ValueType: string; ValueData: """{app}\SoTayDSA.exe"" ""%1"""

; Link chia sẻ sotaydsa://share/... mở thẳng app
Root: HKCU; Subkey: "Software\Classes\sotaydsa"; ValueType: string; ValueData: "URL:Sổ tay DSA"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\sotaydsa"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\sotaydsa\shell\open\command"; ValueType: string; ValueData: """{app}\SoTayDSA.exe"" ""%1"""

[Run]
Filename: "{app}\SoTayDSA.exe"; Description: "{cm:LaunchProgram,Sổ tay DSA C++}"; Flags: nowait postinstall skipifsilent
; Cập nhật tự động (cài im lặng): mở lại app sau khi cài xong
Filename: "{app}\SoTayDSA.exe"; Flags: nowait runasoriginaluser; Check: WizardSilent
