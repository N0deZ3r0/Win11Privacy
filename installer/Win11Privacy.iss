; Установщик «Приватности Windows 11» (Inno Setup 6).
;
; Два варианта в одном мастере:
;   • обычная установка — в Program Files, ярлык в меню «Пуск», удаление через
;     «Параметры → Приложения» (там же оно и сообщает, что останется);
;   • портативная версия — просто распаковать в выбранную папку (на флешку),
;     рядом кладётся portable.txt, и все данные программы живут в этой же
;     папке; в системе ничего не регистрируется.
;
; Собирается не руками, а скриптом installer\build.ps1 — он подставляет
; версию из AppInfo.cs и рисует картинки мастера из app.png. На GitHub это
; делает сборка релиза (.github\workflows\build.yml).
;
; Без окон (для winget и развёртывания):
;   Win11Privacy-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
;   Win11Privacy-Setup.exe /VERYSILENT /PORTABLE=1 /DIR="E:\Win11Privacy"
;   unins000.exe /VERYSILENT [/PURGE=1]     — /PURGE=1 стирает и данные программы

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir ".."
#endif
#ifndef ImgDir
  #define ImgDir "obj"
#endif
#ifndef OutDir
  #define OutDir "..\dist"
#endif

#define AppExe "Win11Privacy.exe"
#define RepoUrl "https://github.com/N0deZ3r0/Win11Privacy"

[Setup]
; Тот же AppId во всех версиях: по нему новая версия ставится поверх старой,
; а winget узнаёт установленную программу (ключ удаления «{AppId}_is1»).
AppId={{D3C03EE2-3FF3-4F72-9976-D10B9424046B}
AppName={cm:AppTitle}
AppVersion={#AppVersion}
AppVerName={cm:AppTitle} {#AppVersion}
AppPublisher=N0deZ3r0
AppPublisherURL={#RepoUrl}
AppSupportURL={#RepoUrl}/issues
AppUpdatesURL={#RepoUrl}/releases
AppCopyright=© 2026 N0deZ3r0, MIT License
VersionInfoVersion={#AppVersion}
VersionInfoProductName=Windows 11 Privacy
VersionInfoDescription=Windows 11 Privacy Setup
VersionInfoCompany=N0deZ3r0

; Программа меняет системные настройки и всё равно работает только с правами
; администратора — установщик просит их сразу, в том числе для переносимой
; версии (иначе её первый запуск всё равно упрётся в UAC).
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

DefaultDirName={autopf}\Win11Privacy
DisableDirPage=no
DisableProgramGroupPage=yes
DisableWelcomePage=no
UsePreviousAppDir=yes
; Лицензия — на языке мастера (LicenseFile у каждого языка в [Languages]):
; в русском мастере — перевод, юридическую силу имеет английский текст.

; Переносимая версия не оставляет в системе ничего: ни программы удаления,
; ни записи в «Приложениях».
Uninstallable=not IsPortable
CreateUninstallRegKey=not IsPortable
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={cm:AppTitle}

; Открытая программа держит этот замок (SingleInstance.cs): установка и
; удаление попросят её закрыть, а не будут менять файл на ходу.
AppMutex=Win11Privacy-App,Global\Win11Privacy-App
CloseApplications=yes
RestartApplications=no

WizardStyle=modern dynamic
WizardSizePercent=110
; Широкую картинку (первая и последняя страницы) рисует build.ps1: тёмная, со
; значком и названием. Для тёмной темы Windows — та же картинка, заданная
; явно: иначе в тёмной теме мастер показывал встроенную «коробку с диском».
; Маленького значка в правом верхнем углу остальных страниц нет — он там
; был лишним (скрывается в InitializeWizard).
WizardImageFile={#ImgDir}\wizard-100.png,{#ImgDir}\wizard-150.png,{#ImgDir}\wizard-200.png
WizardImageFileDynamicDark={#ImgDir}\wizard-100.png,{#ImgDir}\wizard-150.png,{#ImgDir}\wizard-200.png
SetupIconFile={#SourceDir}\app.ico
ShowLanguageDialog=auto

OutputDir={#OutDir}
OutputBaseFilename=Win11Privacy-Setup
Compression=lzma2/max
SolidCompression=yes

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"; LicenseFile: "LICENSE.ru.txt"
Name: "en"; MessagesFile: "compiler:Default.isl"; LicenseFile: "{#SourceDir}\LICENSE"

[Messages]
; Предупреждение перед удалением — одно окно вместо двух: что останется в
; системе и как вернуть всё как было, пока программа ещё на месте.
ru.ConfirmUninstall=Удалить «%1»?%n%nНастройки приватности, которые применила программа, останутся в Windows. Чтобы вернуть всё как было, нажмите «Нет», откройте программу → «Изменения» → «Вернуть всё», и только потом удаляйте её.%n%nЗадачи автозащиты и слежения будут удалены вместе с программой.
en.ConfirmUninstall=Remove "%1"?%n%nThe privacy settings the program applied stay in Windows. To put everything back first, click "No", open the program → "Changes" → "Restore everything", and only then remove it.%n%nThe auto-protection and monitoring tasks are removed together with the program.

[CustomMessages]
ru.AppTitle=Приватность Windows 11
en.AppTitle=Windows 11 Privacy
ru.ModeTitle=Вариант установки
en.ModeTitle=Installation type
ru.ModeDesc=Как поставить программу на этот компьютер?
en.ModeDesc=How should the program be put on this computer?
ru.ModeCaption=Обычная установка кладёт программу в Program Files — туда пишут только администраторы, это нужно для автозащиты. Ярлык появится в меню «Пуск», а удалить программу можно будет в «Параметры → Приложения».%n%nПортативная версия просто распаковывается в выбранную папку, например на флешку. Все данные программы хранятся в той же папке, в системе ничего не регистрируется.
en.ModeCaption=A regular installation puts the program in Program Files, which only administrators can write to — auto-protection needs that. A shortcut appears in the Start menu, and the program can be removed in Settings → Apps.%n%nThe portable version is simply unpacked into a folder of your choice, for example on a USB stick. All program data is kept in that folder, and nothing is registered in the system.
ru.ModeInstall=Установить на этот компьютер (рекомендуется)
en.ModeInstall=Install on this computer (recommended)
ru.ModePortable=Портативная версия — распаковать в папку
en.ModePortable=Portable version — unpack into a folder
ru.ReadyMode=Вариант:
en.ReadyMode=Type:
ru.ReadyInstall=обычная установка
en.ReadyInstall=regular installation
ru.ReadyPortable=портативная версия (данные — в папке программы)
en.ReadyPortable=portable version (data kept in the program folder)
ru.AskPurge=Удалить и данные программы?%n%nЭто журнал изменений (по нему программа возвращает настройки «как было»), история датчиков, снимки и резервные копии в C:\ProgramData\Win11Privacy, а также настройки окна.%n%nЕсли собираетесь поставить программу снова — нажмите «Нет»: тогда вернуть настройки можно будет и потом.
en.AskPurge=Remove the program data as well?%n%nThat is the change journal (the program uses it to put settings back as they were), the sensor history, snapshots and backups in C:\ProgramData\Win11Privacy, and the window settings.%n%nIf you plan to install the program again, click "No": the settings can then still be put back later.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; Check: not IsPortable

[Files]
Source: "{#SourceDir}\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion
Source: "portable.txt"; DestDir: "{app}"; Flags: ignoreversion; Check: IsPortable

[Icons]
Name: "{autoprograms}\{cm:AppTitle}"; Filename: "{app}\{#AppExe}"; Check: not IsPortable
Name: "{autodesktop}\{cm:AppTitle}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon; Check: not IsPortable

[Run]
; runascurrentuser: запуск с правами самого установщика. По умолчанию Inno
; запускает отмеченное «Запустить» от исходного, не повышенного пользователя,
; а программе нужны права администратора — выходила ошибка CreateProcess 740.
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{cm:AppTitle}}"; Flags: nowait postinstall skipifsilent runascurrentuser

[UninstallRun]
; Задачи планировщика, которые программа ставит сама (автозащита, слежение за
; датчиками и сетью, живые уведомления). Без программы они продолжали бы
; запускать копию движка из ProgramData — удаляем их до файлов.
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""Win11Privacy Guard"" /F"; Flags: runhidden; RunOnceId: "DelGuard"
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""Win11Privacy Sensor"" /F"; Flags: runhidden; RunOnceId: "DelSensor"
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""Win11Privacy Network"" /F"; Flags: runhidden; RunOnceId: "DelNetwork"
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""Win11Privacy Watcher"" /F"; Flags: runhidden; RunOnceId: "DelWatcher"

[Code]
var
  ModePage: TInputOptionWizardPage;
  InstallDir, PortableDir: String;

function IsPortable: Boolean;
begin
  Result := (ModePage <> nil) and ModePage.Values[1];
end;

// Папку задали в командной строке (/DIR=...)? Свои ключи Inno Setup в
// {param:...} не отдаёт — смотрим командную строку сами.
function DirGiven: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(Copy(ParamStr(I), 1, 5), '/DIR=') = 0 then
      Result := True;
end;

// Без значка в правом верхнем углу страниц: заголовок и пояснение
// страницы занимают всю ширину шапки.
procedure HideSmallImage;
var
  W: Integer;
begin
  WizardForm.WizardSmallBitmapImage.Visible := False;
  W := WizardForm.MainPanel.ClientWidth - WizardForm.PageNameLabel.Left - ScaleX(24);
  WizardForm.PageNameLabel.Width := W;
  WizardForm.PageDescriptionLabel.Width := W;
end;

procedure InitializeWizard;
begin
  HideSmallImage;
  ModePage := CreateInputOptionPage(wpLicense, CustomMessage('ModeTitle'), CustomMessage('ModeDesc'),
    CustomMessage('ModeCaption'), True, False);
  ModePage.Add(CustomMessage('ModeInstall'));
  ModePage.Add(CustomMessage('ModePortable'));
  if ExpandConstant('{param:PORTABLE|0}') = '1' then
    ModePage.Values[1] := True
  else
    ModePage.Values[0] := True;

  // Папка по умолчанию у вариантов своя; ту, что задали ключом /DIR= или
  // вписали сами, не трогаем (/DIR= Inno подставляет ещё до этой функции)
  InstallDir := WizardForm.DirEdit.Text;
  PortableDir := ExpandConstant('{sd}\Win11Privacy');
  if IsPortable and not DirGiven then
    WizardForm.DirEdit.Text := PortableDir;
  Log('Mode: ' + IntToStr(Ord(IsPortable)) + ', folder: ' + WizardForm.DirEdit.Text);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = ModePage.ID) and not DirGiven then
  begin
    if IsPortable and (CompareText(WizardForm.DirEdit.Text, InstallDir) = 0) then
      WizardForm.DirEdit.Text := PortableDir
    else if (not IsPortable) and (CompareText(WizardForm.DirEdit.Text, PortableDir) = 0) then
      WizardForm.DirEdit.Text := InstallDir;
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := CustomMessage('ReadyMode') + NewLine + Space;
  if IsPortable then
    Result := Result + CustomMessage('ReadyPortable')
  else
    Result := Result + CustomMessage('ReadyInstall');
  Result := Result + NewLine + NewLine + MemoDirInfo;
  if (not IsPortable) and (MemoTasksInfo <> '') then
    Result := Result + NewLine + NewLine + MemoTasksInfo;
end;

// После удаления — спросить про данные программы. По умолчанию «Нет»: без
// журнала изменений вернуть настройки «как было» будет уже нечем.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Purge: Boolean;
begin
  if CurUninstallStep <> usPostUninstall then Exit;
  if UninstallSilent then
    Purge := ExpandConstant('{param:PURGE|0}') = '1'
  else
    Purge := MsgBox(CustomMessage('AskPurge'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
  if Purge then
  begin
    DelTree(ExpandConstant('{commonappdata}\Win11Privacy'), True, True, True);
    DelTree(ExpandConstant('{localappdata}\Win11Privacy'), True, True, True);
  end;
end;
