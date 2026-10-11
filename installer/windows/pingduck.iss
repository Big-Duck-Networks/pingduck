; PingDuck for Windows: the desktop app (Flutter) and the PingDuck Agent
; service (Rust) in one installer, like Fing Desktop.
;
; Build (from the repo root, after `flutter build windows --release` in
; pingduck_app and `cargo build --release -p pingduck-agent` in agent):
;   ISCC.exe /DAppVersion=1.0.0 installer\windows\pingduck.iss
; Output: installer\windows\Output\PingDuckSetup.exe
;
; The installer registers the PingDuckAgent service and opens the Windows
; Firewall for the phone (TCP 44480, UDP 1900, private networks), both via
; `pingduck-agent.exe install`.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName "PingDuck"
#define Repo "..\.."
#define Img(Name) "branding\" + Name + "-100.png,branding\" + Name + "-125.png,branding\" + Name + "-150.png,branding\" + Name + "-175.png,branding\" + Name + "-200.png,branding\" + Name + "-250.png"

[Setup]
AppId={{BDB67565-E91B-403E-9D0F-BEBFC488D224}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Big Duck Networks
AppPublisherURL=https://pingduck.app
AppSupportURL=https://pingduck.app/faq
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Fing's flow: Welcome, options, install, done. Pick a folder with /DIR=.
DisableWelcomePage=no
DisableDirPage=yes
DisableReadyPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputBaseFilename=PingDuckSetup
SetupIconFile={#Repo}\pingduck_app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\PingDuck.exe
Compression=lzma2/max
SolidCompression=yes
; Brand: the carbon panel from make_wizard_images.py, white pages (carbon in
; dark mode, which follows Windows).
WizardStyle=modern dynamic windows11 hidebevels
WizardBackColor=white
WizardBackColorDynamicDark=#111827
WizardImageFile={#Img("wizard")}
WizardSmallImageFile={#Img("wizard-small")}
WizardImageFileDynamicDark={#Img("wizard")}
WizardSmallImageFileDynamicDark={#Img("wizard-small")}
WizardImageBackColor=#111827
WizardImageBackColorDynamicDark=#111827
WizardSmallImageBackColor=white
WizardSmallImageBackColorDynamicDark=#111827
CloseApplications=force
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
SetupWindowTitle=Install %1
WelcomeLabel1=Welcome to PingDuck
WelcomeLabel2=PingDuck finds every device on your network and keeps watching it.%n%nThis installs the PingDuck app and the PingDuck Agent, which keeps monitoring from the tray, even with the window closed.
ClickNext=
WizardSelectTasks=Options
SelectTasksDesc=How should PingDuck start?
SelectTasksLabel2=Choose how PingDuck starts, then click Install.
InstallingLabel=Setting up PingDuck on this PC. This takes a minute.
FinishedHeadingLabel=PingDuck is ready
FinishedLabelNoIcons=Sign in to get your data in sync, then choose Monitor this network under Account › This PC.
FinishedLabel=Sign in to get your data in sync, then choose Monitor this network under Account › This PC.
ClickFinish=
UninstalledAll=PingDuck was removed from this PC.

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"
Name: "startup"; Description: "Start PingDuck with Windows (in the tray)"; GroupDescription: "Startup:"

[Files]
Source: "{#Repo}\pingduck_app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#Repo}\agent\target\release\pingduck-agent.exe"; DestDir: "{app}"; Flags: ignoreversion
; Vendor names for the agent's scans (it looks beside its exe).
Source: "{#Repo}\core\data\oui.csv"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\PingDuck.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\PingDuck.exe"; Tasks: desktopicon

[Registry]
; Same value the app's "Start PingDuck with Windows" switch writes.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "PingDuck"; ValueData: """{app}\PingDuck.exe"" --minimized"; Tasks: startup; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "PingDuck"; Flags: uninsdeletevalue dontcreatekey

[Run]
Filename: "{app}\pingduck-agent.exe"; Parameters: "install"; StatusMsg: "Starting the PingDuck Agent service..."; Flags: runhidden waituntilterminated
Filename: "{app}\PingDuck.exe"; Description: "Open PingDuck"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/IM PingDuck.exe /F"; Flags: runhidden; RunOnceId: "KillApp"

[Code]
var
  PurgeData: Boolean;

function RunHidden(const Exe, Params: String): Integer;
var
  Code: Integer;
begin
  if not Exec(Exe, Params, '', SW_HIDE, ewWaitUntilTerminated, Code) then
    Code := -1;
  Result := Code;
end;

// With no Ready page, Options is the last page before installing.
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpSelectTasks then
    WizardForm.NextButton.Caption := SetupMessage(msgButtonInstall);
end;

// Upgrades: stop the running app and service so their files can be replaced.
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  RunHidden(ExpandConstant('{sys}\taskkill.exe'), '/IM PingDuck.exe /F');
  RunHidden(ExpandConstant('{sys}\sc.exe'), 'stop PingDuckAgent');
  Sleep(1500);
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  PurgeData := MsgBox('Also remove this PC''s PingDuck pairing and logs?' + #13#10 +
    'Choose No to keep them for a reinstall.', mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Params: String;
begin
  // Before the files go: the agent removes its own service and firewall rules.
  if CurUninstallStep = usUninstall then
  begin
    Params := 'uninstall';
    if PurgeData then
      Params := Params + ' --purge';
    RunHidden(ExpandConstant('{app}\pingduck-agent.exe'), Params);
  end;
end;
