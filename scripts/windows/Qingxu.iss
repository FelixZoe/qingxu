#define MyAppName "清序"
#ifndef MyAppVersion
  #define MyAppVersion "0.1.1"
#endif
#define MyAppPublisher "FelixZoe"
#define MyAppURL "https://github.com/FelixZoe/qingxu"
#define MyAppSupportURL "https://github.com/FelixZoe/qingxu/issues"
#define MyAppUpdatesURL "https://github.com/FelixZoe/qingxu/releases/latest"
#define MyAppExeName "Qingxu.exe"
#define MyAppCopyright "Copyright © 2026 FelixZoe"
#define ReleaseDir SourcePath + "..\..\apps\flutter\build\windows\x64\runner\Release"
#define AppIcon SourcePath + "..\..\apps\flutter\windows\runner\resources\app_icon.ico"

; Fail the release at compile time instead of publishing an incomplete package.
#if !FileExists(ReleaseDir + "\" + MyAppExeName)
  #error "Qingxu.exe is missing. Build the Flutter Windows release before compiling the installer."
#endif
#if !FileExists(ReleaseDir + "\msvcp140.dll")
  #error "msvcp140.dll is missing from the Windows release bundle."
#endif
#if !FileExists(ReleaseDir + "\vcruntime140.dll")
  #error "vcruntime140.dll is missing from the Windows release bundle."
#endif
#if !FileExists(ReleaseDir + "\vcruntime140_1.dll")
  #error "vcruntime140_1.dll is missing from the Windows release bundle."
#endif

[Setup]
; Never change this ID: Inno Setup uses it to detect and upgrade existing installs.
AppId={{A0383C21-B04B-4D01-9556-22C52710808B}
AppName={#MyAppName}
AppVerName={#MyAppName} {#MyAppVersion}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppSupportURL}
AppUpdatesURL={#MyAppUpdatesURL}
AppContact={#MyAppSupportURL}
AppComments=简洁、离线优先、支持自托管同步的个人任务管理器
AppCopyright={#MyAppCopyright}
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} 安装程序
VersionInfoCopyright={#MyAppCopyright}
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoProductTextVersion={#MyAppVersion}
VersionInfoTextVersion={#MyAppVersion}
VersionInfoOriginalFileName=Qingxu-{#MyAppVersion}-Windows-Setup.exe

DefaultDirName={localappdata}\Programs\Qingxu
DefaultGroupName={#MyAppName}
DisableDirPage=auto
DisableProgramGroupPage=yes
AllowNoIcons=no
UsePreviousAppDir=yes
UsePreviousGroup=yes
UsePreviousLanguage=yes
UsePreviousTasks=yes

PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763

OutputDir=..\..\artifacts
OutputBaseFilename=Qingxu-{#MyAppVersion}-Windows-Setup
SetupIconFile={#AppIcon}
Compression=lzma2/max
SolidCompression=yes
LZMAUseSeparateProcess=yes

WizardStyle=modern dynamic windows11 includetitlebar
WizardSizePercent=120
DisableWelcomePage=no
DisableReadyPage=no
DisableFinishedPage=no

CloseApplications=yes
RestartApplications=no
DirExistsWarning=auto
SetupLogging=yes
Uninstallable=yes
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName},0
UninstallFilesDir={app}\uninstall

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加选项："; Flags: unchecked

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Comment: "启动{#MyAppName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Comment: "启动{#MyAppName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Description: "启动{#MyAppName}"; Flags: nowait postinstall skipifsilent
