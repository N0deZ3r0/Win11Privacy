#Requires -Version 5.1
# Файл собран из частей в папке engine/ (python tools/build_engine.py).
# Правьте части, а не этот файл: CI сверяет его со сборкой.
<#
    Win11-Privacy-Engine.ps1  (v3)
    Исполнительный модуль для Win11Privacy.exe. Может работать и сам по себе:

      -Modules telemetry,ads,cleanup        применить модули
      -Audit -Modules ...                   проверить реальное состояние (JSON)
      -Detect                               определить систему, установленные программы, статусы (JSON)
      -Monitor [-MonitorHours 24]           статистика перехваченных отправок (JSON)
      -EnableMonitor / -DisableMonitor      журнал аудита заблокированных соединений
      -InstallGuard -Modules ... / -RemoveGuard / -GuardNow
      -PurgeBuffer                          стереть неотправленную телеметрию
      -Revert                               откат всего

    Структурированные ответы печатаются строкой  ###JSON### {...}
#>

[CmdletBinding()]
param(
    [string[]]$Modules = @(),
    [switch]$DryRun,
    [switch]$NoBackup,
    [switch]$NoRestorePoint,
    [switch]$Revert,
    [string]$BackupRoot = '',
    [switch]$Detect,
    [switch]$Audit,
    [switch]$WithProof,
    [switch]$Monitor,
    [int]$MonitorHours = 24,
    [switch]$EnableMonitor,
    [switch]$DisableMonitor,
    [switch]$InstallGuard,
    [switch]$RemoveGuard,
    [switch]$Guard,
    [switch]$GuardNow,
    [switch]$PurgeBuffer,
    # --- рентген телеметрии ---
    [switch]$XrayStatus,
    [switch]$XrayEnable,
    [switch]$XrayDisable,
    [switch]$XrayScan,
    [int]$XrayHours = 24,
    [switch]$XrayBaseline,
    [switch]$XrayWipe,
    [int]$XrayMax = 20000,
    # --- машина времени ---
    [switch]$Snapshot,
    [switch]$SnapshotList,
    [string]$SnapshotDiff = '',
    # --- живые уведомления ---
    [switch]$InstallWatcher,
    [switch]$RemoveWatcher,
    [switch]$WatcherNotify,
    # --- досье: кто подглядывал и цифровой след ---
    [switch]$Spy,
    [switch]$Footprint,
    [switch]$FootprintWipe,
    [string[]]$WipeItems = @(),
    # --- слежение за датчиками: уведомление о новой программе ---
    [switch]$InstallSensorGuard,
    [switch]$RemoveSensorGuard,
    [switch]$SensorGuard,
    # --- слежение за сетью: уведомление о новой программе ---
    [switch]$InstallNetGuard,
    [switch]$RemoveNetGuard,
    [switch]$NetGuard,
    [switch]$SelfTest,
    # --- отдельные настройки внутри модулей ---
    [switch]$ListDefs,
    [string[]]$SkipItems = @(),
    # --- доступ программ к датчикам ---
    [switch]$SensorSet,
    [string]$SensorKey = '',
    [string]$SensorValue = 'Deny',
    # --- предустановленные приложения ---
    [switch]$ListApps,
    [switch]$RemoveApps,
    [string[]]$AppItems = @(),
    [switch]$AllUsers,
    # --- полный откат и все разрешения ---
    [switch]$RestoreAll,
    [switch]$ChangeLog,
    [switch]$SpyAll,
    # --- доказательство результата ---
    [switch]$Proof,
    [switch]$ProofSave,
    # --- автозагрузка ---
    [switch]$ListStartup,
    [switch]$StartupSet,
    [string[]]$StartupItems = @(),
    [string]$StartupValue = 'Off',
    # --- запрет выхода в сеть отдельной программе ---
    [switch]$BlockApp,
    [switch]$UnblockApp,
    [string]$AppPath = '',
    # --- журнал изменений и данные программы ---
    [switch]$RestoreItems,
    [string[]]$ChangeItems = @(),
    [switch]$DataInfo,
    [switch]$PurgeData,
    # --- как часто проверяет страж ---
    [switch]$GuardDaily,
    # --- уборка мусора от версий со сломанным Def ---
    [switch]$CleanJunk,
    # --- где хранить данные: рядом с exe вместо ProgramData ---
    [string]$DataRoot = '',
    # --- хронология и резервные копии ---
    [switch]$Timeline,
    [int]$TimelineDays = 30,
    [switch]$ListBackups,
    [switch]$RestoreBackup,
    [string]$BackupPath = '',
    # --- номер устройства в учётной записи Microsoft (GDID) ---
    [switch]$GdidStatus,
    # --- настройки пользователя — ещё и в другие профили и в профиль по умолчанию ---
    [switch]$AllProfiles,
    # --- проверка утечек: доходит ли соединение до серверов сбора ---
    [switch]$LeakTest,
    # --- чистка: корзину очищать только по отдельному согласию ---
    [switch]$EmptyRecycleBin,
    [switch]$GdidReissue,
    [switch]$GdidRestore,
    # --- запрос от окна: операция и её данные — со стандартного ввода (F-08) ---
    [switch]$Request
)

# --------------------------------------------------------------------------- #
#  Модули PowerShell — только системные, и это первая строка после param.
#  Движок вызывает команды из модулей (ScheduledTasks, NetSecurity, Appx...),
#  и PowerShell подгружает их по PSModulePath, где первой стоит папка
#  «Документы\WindowsPowerShell\Modules». Туда пишет любая программа
#  пользователя без прав администратора, а движок и задачи стража работают с
#  этими правами: модуль с тем же именем выполнился бы вместо системного.
#  До этой строки PowerShell не загружает ни одного модуля (проверено), а
#  здесь нет ни одной команды — только присваивание: Join-Path сам из модуля.
# --------------------------------------------------------------------------- #
$env:PSModulePath = "$PSHOME\Modules"

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# --------------------------------------------------------------------------- #
#  Ограниченный языковой режим PowerShell. На компьютерах с политикой
#  устройства (Device Guard/WDAC, AppLocker) PowerShell запускается в режиме
#  ConstrainedLanguage: почти все вызовы .NET, на которых держится движок,
#  в нём запрещены. Раньше скрипт падал посреди работы непонятной ошибкой —
#  теперь говорит прямо, что дело в политике, а не в программе.
# --------------------------------------------------------------------------- #
$script:LangMode = 'FullLanguage'
try { $script:LangMode = [string]$ExecutionContext.SessionState.LanguageMode } catch { }
if ($script:LangMode -ne 'FullLanguage') {
    Write-Host ('PowerShell на этом компьютере работает в ограниченном режиме: ' + $script:LangMode + '.')
    Write-Host 'Так его настроила политика устройства -- Device Guard (WDAC) или AppLocker. Обычно это рабочий компьютер организации.'
    Write-Host 'В таком режиме программа не может ни прочитать состояние системы, ни изменить его: запрещены сами средства, которыми она работает.'
    Write-Host ('###JSON### {"error":"languageMode","languageMode":"' + $script:LangMode + '"}')
    Write-Host '###DONE###'
    exit 3
}

# --------------------------------------------------------------------------- #
#  Окружение — из самой системы, а не из переменных среды. Переменные среды
#  повышенного процесса складываются и из HKCU\Environment, а туда пишет любая
#  программа пользователя: ProgramData, указанная на свою папку, увела бы
#  журнал отката и ключ подписи туда, где их можно подменить, а TEMP или
#  LOCALAPPDATA, указанные на системную папку, — чистку. Системная папка
#  берётся у Windows (GetSystemDirectory), ProgramData и Program Files — из
#  HKLM, папка профиля — из HKLM\...\ProfileList по SID этого процесса.
#  Пути профиля дальше строятся от неё: перенесённые через «Документы →
#  Свойства» папки программа не трогает.
# --------------------------------------------------------------------------- #
$script:SysDir   = [Environment]::SystemDirectory
$script:WinDir   = [IO.Path]::GetDirectoryName($script:SysDir)
$script:SysDrive = [IO.Path]::GetPathRoot($script:SysDir).TrimEnd('\')

function Get-MachinePath {
    param([string]$Key, [string]$Name, [string]$Default)
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
        try {
            $k = $base.OpenSubKey($Key, $false)
            if ($null -ne $k) {
                $v = ''
                try { $v = [string]$k.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } finally { $k.Close() }
                # раскрываем сами и только системные имена: %USERPROFILE% и
                # прочие пользовательские переменные здесь не годятся
                $v = $v.Replace('%SystemDrive%', $script:SysDrive).Replace('%SYSTEMDRIVE%', $script:SysDrive).Replace('%systemdrive%', $script:SysDrive)
                $v = $v.Replace('%SystemRoot%', $script:WinDir).Replace('%SYSTEMROOT%', $script:WinDir).Replace('%systemroot%', $script:WinDir)
                if ($v -and $v.IndexOf('%') -lt 0 -and [IO.Path]::IsPathRooted($v)) { return $v.TrimEnd('\') }
            }
        } finally { $base.Close() }
    } catch { }
    return $Default
}

$script:ProgramDataDir = Get-MachinePath 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' 'ProgramData' ($script:SysDrive + '\ProgramData')
$script:ProgramFilesDir = Get-MachinePath 'SOFTWARE\Microsoft\Windows\CurrentVersion' 'ProgramFilesDir' ($script:SysDrive + '\Program Files')
$script:ProgramFilesX86Dir = Get-MachinePath 'SOFTWARE\Microsoft\Windows\CurrentVersion' 'ProgramFilesDir (x86)' ($script:SysDrive + '\Program Files (x86)')
$script:UserSid = ''
# DOMAIN\имя — из маркера процесса: им ставятся задачи планировщика
$script:RunAccount = ''
try {
    $me = [Security.Principal.WindowsIdentity]::GetCurrent()
    $script:UserSid = $me.User.Value
    $script:RunAccount = $me.Name
} catch { }
# Папка профиля: $null — узнать у системы не вышло, и тогда пути профиля
# (чистка, VS Code, следы) не трогаются вовсе
$script:UserProfileDir = $null
if ($script:UserSid) {
    $script:UserProfileDir = Get-MachinePath ('SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\' + $script:UserSid) 'ProfileImagePath' $null
}

$env:SystemRoot    = $script:WinDir
$env:windir        = $script:WinDir
$env:SystemDrive   = $script:SysDrive
$env:ComSpec       = $script:SysDir + '\cmd.exe'
$env:ProgramData   = $script:ProgramDataDir
$env:ALLUSERSPROFILE = $script:ProgramDataDir
$env:ProgramFiles  = $script:ProgramFilesDir
$env:ProgramW6432  = $script:ProgramFilesDir
${env:ProgramFiles(x86)} = $script:ProgramFilesX86Dir
$env:CommonProgramFiles = $script:ProgramFilesDir + '\Common Files'
${env:CommonProgramFiles(x86)} = $script:ProgramFilesX86Dir + '\Common Files'
# Утилиты движка (reg, auditpol, ipconfig, cmdkey, schtasks) — системные
$env:PATH = ($script:SysDir + ';' + $script:WinDir + ';' + $script:SysDir + '\Wbem;' + $script:SysDir + '\WindowsPowerShell\v1.0\')
# Program Files пишут только администраторы — там модули, поставленные для всех
$env:PSModulePath = "$PSHOME\Modules;" + $script:ProgramFilesDir + '\WindowsPowerShell\Modules'
if ($script:UserProfileDir) {
    $env:USERPROFILE  = $script:UserProfileDir
    $env:APPDATA      = $script:UserProfileDir + '\AppData\Roaming'
    $env:LOCALAPPDATA = $script:UserProfileDir + '\AppData\Local'
    $env:TEMP         = $script:UserProfileDir + '\AppData\Local\Temp'
    $env:TMP          = $env:TEMP
}
# Переменные, через которые .NET и оболочка грузят в процесс чужой код:
# профайлер CLR (COR_*/CORECLR_*), стартовые перехватчики .NET, слой
# совместимости приложений. Задачи стража идут от имени администратора, чей
# HKCU\Environment обычному пользователю не переписать, но эти переменные
# убираются и у текущего процесса, и у всех, кого он запускает (reg.exe,
# auditpol, powershell задач и де-повышенных задач от имени пользователя),
# чтобы ни один из них нельзя было перехватить через унаследованную
# переменную. Профайлер, уже загруженный в сам движок, этим не выгрузить —
# но запуск движка окно задаёт с чистым окружением (EngineFile.Harden).
foreach ($bad in @('COR_ENABLE_PROFILING', 'COR_PROFILER', 'COR_PROFILER_PATH', 'COR_PROFILER_PATH_32', 'COR_PROFILER_PATH_64',
                   'CORECLR_ENABLE_PROFILING', 'CORECLR_PROFILER', 'CORECLR_PROFILER_PATH', 'CORECLR_PROFILER_PATH_32', 'CORECLR_PROFILER_PATH_64',
                   'DOTNET_STARTUP_HOOKS', 'DOTNET_ADDITIONAL_DEPS', 'DOTNET_EnableDiagnostics', '__COMPAT_LAYER')) {
    [Environment]::SetEnvironmentVariable($bad, $null, 'Process')
}

# --------------------------------------------------------------------------- #
#  Запрос от окна (F-08). Раньше окно собирало командную строку из кусков:
#  «-SensorSet -SensorKey "<имя раздела реестра>"». Имя раздела в HKCU может
#  завести любая программа пользователя, кавычка в нём закрывала значение, а
#  остаток строки PowerShell разбирал как новые ключи движка — и они
#  выполнялись с правами администратора. Путь к рабочему столу (-BackupRoot)
#  тоже читается из HKCU и уходил так же при каждом запуске.
#
#  Теперь окно запускает движок с постоянной командной строкой «-Request», а
#  что делать и с какими данными — пишет на стандартный ввод одним JSON:
#      {"v":1,"op":"SensorSet","args":{"SensorKey":"...","SensorValue":"Deny"}}
#  Здесь он разбирается строгим разборщиком (не ConvertFrom-Json и тем более
#  не как код PowerShell): только ASCII (остальное окно пишет как \uXXXX), без
#  повторов ключей, без лишних полей, с ограничением размера и вложенности.
#  Операция берётся только из белого списка, у каждой — свой список
#  аргументов, у каждого аргумента — тип и форма. Значения ставятся в
#  переменные параметров явными присваиваниями по имени из списка, а не из
#  JSON. Любая ошибка — отказ до какой-либо работы (код 64). Повторить
#  операцию из данных нельзя: значение остаётся значением, сколько бы кавычек
#  и «-Ключей» в нём ни было.
#
#  Обычные ключи командной строки остались для задач стража и ручного
#  запуска; вместе с -Request их передавать нельзя.
# --------------------------------------------------------------------------- #
$script:RequestOps = @{
    'Apply'              = @('Modules', 'SkipItems', 'EmptyRecycleBin', 'DryRun', 'NoBackup', 'NoRestorePoint', 'AllProfiles')
    'Audit'              = @('Modules', 'SkipItems', 'WithProof')
    'Revert'             = @()
    'LeakTest'           = @()
    'CleanJunk'          = @()
    'EnableMonitor'      = @()
    'DisableMonitor'     = @()
    'Monitor'            = @('MonitorHours')
    'InstallNetGuard'    = @()
    'RemoveNetGuard'     = @()
    'InstallGuard'       = @('Modules', 'SkipItems', 'GuardDaily')
    'RemoveGuard'        = @()
    'GuardNow'           = @()
    'InstallSensorGuard' = @()
    'RemoveSensorGuard'  = @()
    'InstallWatcher'     = @()
    'RemoveWatcher'      = @()
    'Snapshot'           = @()
    'SnapshotList'       = @()
    'SnapshotDiff'       = @('SnapshotDiff')
    'ListDefs'           = @()
    'Detect'             = @()
    'Spy'                = @('SpyAll')
    'Footprint'          = @()
    'FootprintWipe'      = @('WipeItems')
    'SensorSet'          = @('SensorKey', 'SensorValue')
    'BlockApp'           = @('AppPath')
    'UnblockApp'         = @('AppPath')
    'DataInfo'           = @()
    'PurgeData'          = @()
    'ListApps'           = @()
    'RemoveApps'         = @('AppItems', 'AllUsers')
    'ListStartup'        = @()
    'StartupSet'         = @('StartupItems', 'StartupValue')
    'ChangeLog'          = @()
    'RestoreItems'       = @('ChangeItems')
    'RestoreAll'         = @()
    'ListBackups'        = @()
    'RestoreBackup'      = @('BackupPath')
    'Timeline'           = @('TimelineDays')
    'GdidStatus'         = @()
    'GdidReissue'        = @()
    'GdidRestore'        = @()
    'XrayStatus'         = @()
    'XrayEnable'         = @()
    'XrayDisable'        = @()
    'XrayWipe'           = @()
    'XrayScan'           = @('XrayHours', 'XrayBaseline')
    'SelfTest'           = @()
}
# Без чего операция не имеет смысла
$script:RequestNeeds = @{ 'Apply' = 'Modules'; 'SnapshotDiff' = 'SnapshotDiff'; 'FootprintWipe' = 'WipeItems'
                          'SensorSet' = 'SensorKey'; 'BlockApp' = 'AppPath'; 'UnblockApp' = 'AppPath'
                          'RemoveApps' = 'AppItems'; 'StartupSet' = 'StartupItems'; 'RestoreItems' = 'ChangeItems'
                          'RestoreBackup' = 'BackupPath' }
# Аргументы, которые принимает любая операция: где лежат копии и данные
$script:RequestCommon = @('BackupRoot', 'DataRoot')
# Тип и форма каждого аргумента. Форма проверяется здесь, независимо от окна;
# дальше по движку значения проверяются ещё раз там, где используются.
$script:RequestArgSpec = @{
    'Modules'         = @{ t = 'list'; rx = '^[A-Za-z0-9_-]{1,64}$' }
    'SkipItems'       = @{ t = 'list'; rx = '^[a-z][a-z0-9_]{0,40}#[0-9]{1,4}$' }
    'WipeItems'       = @{ t = 'list'; rx = '^[A-Za-z0-9_-]{1,64}$' }
    'AppItems'        = @{ t = 'list'; rx = '^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$' }
    'StartupItems'    = @{ t = 'list'; rx = '^[A-Za-z0-9._]{1,8192}$' }
    'ChangeItems'     = @{ t = 'list'; rx = '^[A-Za-z0-9._]{1,8192}$' }
    'SnapshotDiff'    = @{ t = 'string'; rx = '^[A-Za-z0-9._-]{1,128}\|[A-Za-z0-9._-]{1,128}$' }
    'SensorKey'       = @{ t = 'string'; rx = '^[^\x00-\x1f\x7f"]{1,320}$' }
    'SensorValue'     = @{ t = 'string'; rx = '^(Allow|Deny)$' }
    'StartupValue'    = @{ t = 'string'; rx = '^(On|Off)$' }
    'AppPath'         = @{ t = 'path' }
    'BackupPath'      = @{ t = 'path' }
    'BackupRoot'      = @{ t = 'path' }
    'DataRoot'        = @{ t = 'path' }
    'MonitorHours'    = @{ t = 'int'; min = 1; max = 8760 }
    'TimelineDays'    = @{ t = 'int'; min = 1; max = 3650 }
    'XrayHours'       = @{ t = 'int'; min = 1; max = 8760 }
    'EmptyRecycleBin' = @{ t = 'switch' }
    'DryRun'          = @{ t = 'switch' }
    'NoBackup'        = @{ t = 'switch' }
    'NoRestorePoint'  = @{ t = 'switch' }
    'AllProfiles'     = @{ t = 'switch' }
    'WithProof'       = @{ t = 'switch' }
    'GuardDaily'      = @{ t = 'switch' }
    'SpyAll'          = @{ t = 'switch' }
    'AllUsers'        = @{ t = 'switch' }
    'XrayBaseline'    = @{ t = 'switch' }
}
$script:RequestMaxBytes = 262144

# Весь стандартный ввод — один раз, с пределом размера. Только печатный ASCII
# и переводы строк: окно всё остальное пишет escape-последовательностями.
function Read-EngineRequest {
    $in = [Console]::OpenStandardInput()
    $ms = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 8192
    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
        $ms.Write($buf, 0, $n)
        if ($ms.Length -gt $script:RequestMaxBytes) { throw 'запрос длиннее допустимого' }
    }
    $bytes = $ms.ToArray()
    # Метка UTF-8 в начале: её дописывает канал окна, если консоль Windows
    # переведена в UTF-8 (кодовая страница 65001). Сам запрос — ASCII.
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $bytes = $bytes[3..($bytes.Length - 1)]
        if ($bytes -isnot [array]) { $bytes = @($bytes) }
    }
    if ($bytes.Length -eq 0) { throw 'запрос пуст' }
    foreach ($b in $bytes) {
        if (($b -gt 0x7E) -or (($b -lt 0x20) -and ($b -ne 0x09) -and ($b -ne 0x0A) -and ($b -ne 0x0D))) { throw 'в запросе недопустимые байты' }
    }
    return [System.Text.Encoding]::ASCII.GetString($bytes)
}

# --- строгий разбор JSON: объект, массив, строка, целое, true/false -------- #
function Step-RqSpace {
    while ($script:Rq.i -lt $script:Rq.s.Length) {
        $c = $script:Rq.s[$script:Rq.i]
        if ($c -eq [char]0x20 -or $c -eq [char]0x09 -or $c -eq [char]0x0A -or $c -eq [char]0x0D) { $script:Rq.i++ } else { break }
    }
}
function Read-RqChar {
    if ($script:Rq.i -ge $script:Rq.s.Length) { throw 'запрос оборван' }
    $c = $script:Rq.s[$script:Rq.i]; $script:Rq.i++
    return $c
}
function Read-RqString {
    $sb = New-Object System.Text.StringBuilder
    while ($true) {
        $c = Read-RqChar
        if ($c -eq [char]'"') { break }
        if ([int]$c -lt 0x20) { throw 'управляющий символ внутри строки' }
        if ($c -ne [char]'\') { $null = $sb.Append($c); continue }
        $e = Read-RqChar
        switch -CaseSensitive ([string]$e) {
            '"'  { $null = $sb.Append('"') }
            '\'  { $null = $sb.Append('\') }
            '/'  { $null = $sb.Append('/') }
            'b'  { $null = $sb.Append([char]8) }
            'f'  { $null = $sb.Append([char]12) }
            'n'  { $null = $sb.Append([char]10) }
            'r'  { $null = $sb.Append([char]13) }
            't'  { $null = $sb.Append([char]9) }
            'u'  {
                $hex = ''
                for ($k = 0; $k -lt 4; $k++) { $hex += [string](Read-RqChar) }
                if ($hex -notmatch '^[0-9A-Fa-f]{4}$') { throw 'неверная escape-последовательность' }
                $null = $sb.Append([char][Convert]::ToInt32($hex, 16))
            }
            default { throw 'неверная escape-последовательность' }
        }
        if ($sb.Length -gt 65536) { throw 'слишком длинная строка' }
    }
    return $sb.ToString()
}
function Read-RqValue {
    param([int]$Depth)
    # запрос (1) → args (2) → список (3) → строка списка (4); глубже не бывает
    if ($Depth -gt 4) { throw 'слишком глубокая вложенность' }
    Step-RqSpace
    $c = Read-RqChar
    if ($c -eq [char]'{') {
        $h = @{}                                  # ключи без учёта регистра: «A» и «a» — повтор
        Step-RqSpace
        if ($script:Rq.i -lt $script:Rq.s.Length -and $script:Rq.s[$script:Rq.i] -eq [char]'}') { $script:Rq.i++; return $h }
        while ($true) {
            Step-RqSpace
            if ((Read-RqChar) -ne [char]'"') { throw 'ожидалось имя поля' }
            $key = Read-RqString
            if ($h.ContainsKey($key)) { throw ('поле повторяется: ' + $key) }
            Step-RqSpace
            if ((Read-RqChar) -ne [char]':') { throw 'ожидалось двоеточие' }
            $h[$key] = (Read-RqValue ($Depth + 1))
            if ($h.Count -gt 64) { throw 'слишком много полей' }
            Step-RqSpace
            $sep = Read-RqChar
            if ($sep -eq [char]'}') { return $h }
            if ($sep -ne [char]',') { throw 'ожидалась запятая' }
        }
    }
    if ($c -eq [char]'[') {
        $list = New-Object System.Collections.Generic.List[object]
        Step-RqSpace
        if ($script:Rq.i -lt $script:Rq.s.Length -and $script:Rq.s[$script:Rq.i] -eq [char]']') { $script:Rq.i++; return ,@($list.ToArray()) }
        while ($true) {
            $list.Add((Read-RqValue ($Depth + 1)))
            if ($list.Count -gt 4096) { throw 'слишком длинный список' }
            Step-RqSpace
            $sep = Read-RqChar
            if ($sep -eq [char]']') { return ,@($list.ToArray()) }
            if ($sep -ne [char]',') { throw 'ожидалась запятая' }
        }
    }
    if ($c -eq [char]'"') { return (Read-RqString) }
    if ($c -eq [char]'t' -or $c -eq [char]'f') {
        $word = if ($c -eq [char]'t') { 'true' } else { 'false' }
        for ($k = 1; $k -lt $word.Length; $k++) { if ((Read-RqChar) -ne $word[$k]) { throw 'неизвестное слово' } }
        return ($word -eq 'true')
    }
    if ($c -eq [char]'-' -or ($c -ge [char]'0' -and $c -le [char]'9')) {
        $num = [string]$c
        while ($script:Rq.i -lt $script:Rq.s.Length -and $script:Rq.s[$script:Rq.i] -ge [char]'0' -and $script:Rq.s[$script:Rq.i] -le [char]'9') {
            $num += [string]$script:Rq.s[$script:Rq.i]; $script:Rq.i++
        }
        if ($num -notmatch '^-?(0|[1-9][0-9]{0,8})$') { throw 'неверное число' }
        return [int]$num
    }
    throw 'неожиданный символ'
}
function ConvertFrom-EngineRequest {
    param([string]$Text)
    $script:Rq = @{ s = $Text; i = 0 }
    $v = Read-RqValue 1
    Step-RqSpace
    if ($script:Rq.i -ne $Text.Length) { throw 'лишнее после запроса' }
    if ($v -isnot [hashtable]) { throw 'запрос — не объект' }
    return $v
}

# Проверка значения по описанию аргумента; возвращает значение для параметра
function Test-RequestArg {
    param([string]$Name, $Value)
    $spec = $script:RequestArgSpec[$Name]
    switch -CaseSensitive ($spec.t) {
        'switch' {
            if ($Value -isnot [bool] -or -not $Value) { throw ($Name + ': ожидалось true') }
            return $true
        }
        'int' {
            if ($Value -isnot [int] -or $Value -lt $spec.min -or $Value -gt $spec.max) { throw ($Name + ': недопустимое число') }
            return $Value
        }
        'string' {
            if ($Value -isnot [string] -or $Value -cnotmatch $spec.rx) { throw ($Name + ': недопустимое значение') }
            return $Value
        }
        'path' {
            # полный путь: с буквой диска или сетевой \\сервер\папка (рабочий
            # стол бывает перенаправлен на сервер), без управляющих символов,
            # кавычек и знаков, запрещённых в именах файлов, без «..». Пути
            # устройств (\\?\, \\.\) не годятся: «?» и «.» вместо имени сервера
            if ($Value -isnot [string] -or $Value.Length -gt 1024 -or
                ($Value -cnotmatch '^[A-Za-z]:\\' -and $Value -cnotmatch '^\\\\[A-Za-z0-9][^\\/]*\\[^\\/]') -or
                $Value -match '[\x00-\x1f\x7f"<>|?*/]' -or
                $Value.Substring(2) -match ':' -or $Value -match '(^|\\)\.\.(\\|$)') { throw ($Name + ': недопустимый путь') }
            return $Value
        }
        'list' {
            if ($Value -isnot [object[]]) { throw ($Name + ': ожидался список') }
            foreach ($item in $Value) {
                if ($item -isnot [string] -or $item -cnotmatch $spec.rx) { throw ($Name + ': недопустимый элемент списка') }
            }
            return ,([string[]]$Value)
        }
    }
    throw ($Name + ': неизвестный тип')
}

# Операция — только явным присваиванием известного ключа
function Set-RequestOp {
    param([string]$Op)
    switch -CaseSensitive ($Op) {
        'Apply'              { }
        'Audit'              { $script:Audit = [switch]$true }
        'Revert'             { $script:Revert = [switch]$true }
        'LeakTest'           { $script:LeakTest = [switch]$true }
        'CleanJunk'          { $script:CleanJunk = [switch]$true }
        'EnableMonitor'      { $script:EnableMonitor = [switch]$true }
        'DisableMonitor'     { $script:DisableMonitor = [switch]$true }
        'Monitor'            { $script:Monitor = [switch]$true }
        'InstallNetGuard'    { $script:InstallNetGuard = [switch]$true }
        'RemoveNetGuard'     { $script:RemoveNetGuard = [switch]$true }
        'InstallGuard'       { $script:InstallGuard = [switch]$true }
        'RemoveGuard'        { $script:RemoveGuard = [switch]$true }
        'GuardNow'           { $script:GuardNow = [switch]$true }
        'InstallSensorGuard' { $script:InstallSensorGuard = [switch]$true }
        'RemoveSensorGuard'  { $script:RemoveSensorGuard = [switch]$true }
        'InstallWatcher'     { $script:InstallWatcher = [switch]$true }
        'RemoveWatcher'      { $script:RemoveWatcher = [switch]$true }
        'Snapshot'           { $script:Snapshot = [switch]$true }
        'SnapshotList'       { $script:SnapshotList = [switch]$true }
        'SnapshotDiff'       { }
        'ListDefs'           { $script:ListDefs = [switch]$true }
        'Detect'             { $script:Detect = [switch]$true }
        'Spy'                { $script:Spy = [switch]$true }
        'Footprint'          { $script:Footprint = [switch]$true }
        'FootprintWipe'      { $script:FootprintWipe = [switch]$true }
        'SensorSet'          { $script:SensorSet = [switch]$true }
        'BlockApp'           { $script:BlockApp = [switch]$true }
        'UnblockApp'         { $script:UnblockApp = [switch]$true }
        'DataInfo'           { $script:DataInfo = [switch]$true }
        'PurgeData'          { $script:PurgeData = [switch]$true }
        'ListApps'           { $script:ListApps = [switch]$true }
        'RemoveApps'         { $script:RemoveApps = [switch]$true }
        'ListStartup'        { $script:ListStartup = [switch]$true }
        'StartupSet'         { $script:StartupSet = [switch]$true }
        'ChangeLog'          { $script:ChangeLog = [switch]$true }
        'RestoreItems'       { $script:RestoreItems = [switch]$true }
        'RestoreAll'         { $script:RestoreAll = [switch]$true }
        'ListBackups'        { $script:ListBackups = [switch]$true }
        'RestoreBackup'      { $script:RestoreBackup = [switch]$true }
        'Timeline'           { $script:Timeline = [switch]$true }
        'GdidStatus'         { $script:GdidStatus = [switch]$true }
        'GdidReissue'        { $script:GdidReissue = [switch]$true }
        'GdidRestore'        { $script:GdidRestore = [switch]$true }
        'XrayStatus'         { $script:XrayStatus = [switch]$true }
        'XrayEnable'         { $script:XrayEnable = [switch]$true }
        'XrayDisable'        { $script:XrayDisable = [switch]$true }
        'XrayWipe'           { $script:XrayWipe = [switch]$true }
        'XrayScan'           { $script:XrayScan = [switch]$true }
        'SelfTest'           { $script:SelfTest = [switch]$true }
        default              { throw ('неизвестная операция: ' + $Op) }
    }
}
function Set-RequestArg {
    param([string]$Name, $Value)
    switch -CaseSensitive ($Name) {
        'Modules'         { $script:Modules = [string[]]$Value }
        'SkipItems'       { $script:SkipItems = [string[]]$Value }
        'WipeItems'       { $script:WipeItems = [string[]]$Value }
        'AppItems'        { $script:AppItems = [string[]]$Value }
        'StartupItems'    { $script:StartupItems = [string[]]$Value }
        'ChangeItems'     { $script:ChangeItems = [string[]]$Value }
        'SnapshotDiff'    { $script:SnapshotDiff = [string]$Value }
        'SensorKey'       { $script:SensorKey = [string]$Value }
        'SensorValue'     { $script:SensorValue = [string]$Value }
        'StartupValue'    { $script:StartupValue = [string]$Value }
        'AppPath'         { $script:AppPath = [string]$Value }
        'BackupPath'      { $script:BackupPath = [string]$Value }
        'BackupRoot'      { $script:BackupRoot = [string]$Value }
        'DataRoot'        { $script:DataRoot = [string]$Value }
        'MonitorHours'    { $script:MonitorHours = [int]$Value }
        'TimelineDays'    { $script:TimelineDays = [int]$Value }
        'XrayHours'       { $script:XrayHours = [int]$Value }
        'EmptyRecycleBin' { $script:EmptyRecycleBin = [switch]$true }
        'DryRun'          { $script:DryRun = [switch]$true }
        'NoBackup'        { $script:NoBackup = [switch]$true }
        'NoRestorePoint'  { $script:NoRestorePoint = [switch]$true }
        'AllProfiles'     { $script:AllProfiles = [switch]$true }
        'WithProof'       { $script:WithProof = [switch]$true }
        'GuardDaily'      { $script:GuardDaily = [switch]$true }
        'SpyAll'          { $script:SpyAll = [switch]$true }
        'AllUsers'        { $script:AllUsers = [switch]$true }
        'XrayBaseline'    { $script:XrayBaseline = [switch]$true }
        default           { throw ('неизвестный аргумент: ' + $Name) }
    }
}

# Весь запрос проверяется целиком до первого присваивания: частично
# применённого запроса не бывает
function Use-EngineRequest {
    param([hashtable]$Req)
    foreach ($k in @($Req.Keys)) { if (@('v', 'op', 'args') -cnotcontains $k) { throw ('лишнее поле запроса: ' + $k) } }
    if (-not $Req.ContainsKey('v') -or $Req['v'] -isnot [int] -or $Req['v'] -ne 1) { throw 'неизвестная версия запроса' }
    $op = $Req['op']
    if ($op -isnot [string] -or @($script:RequestOps.Keys) -cnotcontains $op) { throw 'операции нет в списке разрешённых' }
    $given = @{}
    if ($Req.ContainsKey('args')) {
        if ($Req['args'] -isnot [hashtable]) { throw 'args — не объект' }
        $given = $Req['args']
    }
    $allowed = @($script:RequestOps[$op]) + $script:RequestCommon
    $checked = New-Object System.Collections.Generic.List[object]
    foreach ($name in @($given.Keys)) {
        if ($allowed -cnotcontains $name) { throw ('аргумент не положен этой операции: ' + $name) }
        $checked.Add(@($name, (Test-RequestArg $name $given[$name])))
    }
    if ($script:RequestNeeds.ContainsKey($op)) {
        $need = $script:RequestNeeds[$op]
        if (-not $given.ContainsKey($need)) { throw ('не хватает аргумента: ' + $need) }
        $nv = $given[$need]
        if (($nv -is [object[]] -and $nv.Count -eq 0) -or ($nv -is [string] -and $nv.Length -eq 0)) { throw ('пустой аргумент: ' + $need) }
    }
    Set-RequestOp $op
    foreach ($pair in $checked) { Set-RequestArg $pair[0] $pair[1] }
    return $op
}

if ($Request) {
    $rqError = $null; $rqOp = ''
    try {
        if ($PSBoundParameters.Count -ne 1) { throw 'вместе с -Request другие ключи командной строки не принимаются' }
        if (-not [Console]::IsInputRedirected) { throw 'запрос должен прийти через стандартный ввод' }
        $rqOp = Use-EngineRequest (ConvertFrom-EngineRequest (Read-EngineRequest))
    } catch { $rqError = $_.Exception.Message }
    if ($rqError) {
        Write-Host ('[!] Запрос к движку отклонён: ' + $rqError)
        Write-Host '###JSON### {"error":"request rejected"}'
        Write-Host '###DONE###'
        exit 64
    }
    # Для проверок: какая операция на самом деле выбрана; «2» — только принять
    # запрос и выйти, ничего не делая. Окно эту переменную движку не передаёт
    # (EngineFile.Harden убирает её из окружения), её задают только тесты.
    if ($env:WIN11_ENGINE_TRACE -eq '1' -or $env:WIN11_ENGINE_TRACE -eq '2') { Write-Host ('###OP### ' + $rqOp) }
    if ($env:WIN11_ENGINE_TRACE -eq '2') { Write-Host '###DONE###'; exit 0 }
}

# --------------------------------------------------------------------------- #
#  Списки модулей приходят из интерфейса одной строкой «a,b,c»: powershell.exe
#  с ключом -File не разбивает аргументы по запятым и отдаёт массив из одного
#  элемента. Разворачиваем сами, иначе ни один модуль не совпадёт по имени.
# --------------------------------------------------------------------------- #
function Expand-List {
    param([string[]]$Items)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($i in $Items) {
        if ($null -eq $i) { continue }
        foreach ($p in ([string]$i -split ',')) {
            $t = $p.Trim()
            if ($t) { $out.Add($t) }
        }
    }
    return $out.ToArray()
}
$Modules   = Expand-List $Modules
$WipeItems = Expand-List $WipeItems
$SkipItems = Expand-List $SkipItems
$AppItems  = Expand-List $AppItems
$StartupItems = Expand-List $StartupItems
$ChangeItems  = Expand-List $ChangeItems

# =========================================================================== #
#  Константы
# =========================================================================== #
# Версия. Должна совпадать с AppInfo.Version в интерфейсе -- сборка это
# проверяет, чтобы вшитый движок и окно не рассказывали о себе разное.
$script:EngineVersion  = '2.1.0'
# Метки блока в hosts — только латиницей. Раньше они были по-русски, а hosts
# пишется в ASCII: кириллица превращалась в «?», и своего блока программа
# потом не узнавала — дописывала его заново при каждом применении, а откат
# его не убирал. По шаблону узнаются и новые метки, и прежние, уже побитые.
$script:HostsMarkStart = '# --- Win11Privacy: telemetry block (begin) ---'
$script:HostsMarkEnd   = '# --- Win11Privacy: telemetry block (end) ---'
$script:HostsMarkRegex = '^# --- Win11Privacy: .+ ---\s*$'
$script:FwGroup        = 'Win11Privacy'
# Обычно данные лежат в ProgramData. В переносимом режиме интерфейс
# передаёт -DataRoot, и всё остаётся рядом с exe — на чужом компьютере
# программа не оставляет следов.
$script:DataDir        = $(if ($DataRoot) { $DataRoot } else { Join-Path $env:ProgramData 'Win11Privacy' })
# Задачам планировщика путь к данным надо передать явно: они запускаются
# сами по себе и о переносимом режиме иначе не узнают.
# Обратная косая в конце пути (D:\) экранировала бы закрывающую кавычку в
# командной строке задачи; по правилам разбора её удваивают.
$script:DataArg        = $(if ($DataRoot) { ' -DataRoot "' + ($DataRoot -replace '\\$', '\\') + '"' } else { '' })
# Запуск из планировщика: страж, наблюдение за датчиками и сетью. Такие запуски
# идут сами, без человека, и с правами администратора.
$script:TaskRun        = [bool]($Guard -or $SensorGuard -or $NetGuard -or $WatcherNotify)
$script:PortableTaskState = $null    # можно ли задачам верить переносимой папке: $null — ещё не проверяли
# Корень в ProgramData. Здесь копия движка, которую задачи планировщика
# запускают с правами администратора, — и в переносимом режиме тоже: рядом с
# exe писать может любая программа пользователя, и подменённый скрипт молча
# выполнился бы с повышенными правами при следующем входе в систему.
$script:SafeRoot       = Join-Path $env:ProgramData 'Win11Privacy'
$script:TaskEngine     = Join-Path $script:SafeRoot 'engine.ps1'
# Задачи стража и наблюдения запускают PowerShell по полному пути: по одному
# имени Windows ищет программу и в рабочей папке задачи.
$script:PsExe          = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
# Ключ подписи журнала отката: всегда в защищённом корне, читать его могут
# только система и администраторы
$script:SignKeyFile    = Join-Path $script:SafeRoot 'journal.key'
$script:SignKey        = $null
$script:RootState      = $null        # защищён ли корень: $null — ещё не проверяли
# Владельцы, которым можно верить: система, администраторы, TrustedInstaller
$script:TrustedSids    = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
$script:JournalFailed  = $false       # журнал отката не записался — дальше ничего не меняем
$script:JournalLockTries = 6          # по 10 секунд: другой запуск может писать журнал долго
$script:JournalLockWaitMs = 10000
$script:GuardTask      = 'Win11Privacy Guard'
$script:SensorTask     = 'Win11Privacy Sensor'
$script:AuditGuid      = '{0CCE9226-69AE-11D9-BED3-505054503030}'   # Filtering Platform Connection
$script:DiagDir        = Join-Path $env:ProgramData 'Microsoft\Diagnosis'
# Все виды определений, которые пишут в реестр. Список один, потому что
# забыть про новый вид в резервной копии или уборке — тихая потеря данных.
$script:RegTypes = @('reg', 'regif', 'regpol', 'regsvc')
# Номер сборки Windows: по нему настройки, которых на этой версии нет вовсе
# (Copilot, Recall, виджеты — их не было до Windows 11), не считаются
# «не применёнными». Иначе на Windows 10 индекс был бы низким без вины
# пользователя.
$script:OsBuild = 0
try { $script:OsBuild = [int](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'CurrentBuildNumber' -ErrorAction Stop).CurrentBuildNumber } catch { }
# Сколько часов во временной папке не трогать свежие файлы: ими ещё
# пользуются запущенные программы, а чистка однажды стёрла рабочие файлы.
$script:TempKeepHours = 24
$script:Changes = 0
$script:Failures = 0
$script:Already = 0
$script:Blocked = 0
# Настройки, которые Windows не отдала при применении. Запоминаются в
# blocked.json, чтобы проверка не считала их «не применёнными» вечно:
# индекс на Home иначе никогда не дошёл бы до 100 %.
$script:BlockedIds = @{}
$script:UnblockedIds = @{}
# Журнал изменений реестра: что было до нашего вмешательства.
# Без него откат требовал ручного импорта .reg-файлов.
$script:Journal = New-Object System.Collections.Generic.List[object]
# Метка этого запуска в записях журнала и ключи записей, которые этот запуск
# положил заранее, а изменение потом не прошло: их убирает следующая запись.
$script:RunId = [guid]::NewGuid().ToString('N')
$script:JournalRetract = New-Object 'System.Collections.Generic.HashSet[string]'
$script:TelemetryDnsRegex = 'telemetry|vortex|events\.data\.microsoft|pipe\.aria|watson|settings-win\.data|ceipdata|telecommand|sqm\.|nexusrules|nexus\.officeapps|data\.microsoft\.com|activity\.windows\.com|licensing\.mp\.microsoft|browser\.events|dds\.microsoft\.com|cdpcs\.access\.microsoft|\.do\.dsp\.mp\.microsoft'

# =========================================================================== #
#  Служебные функции
# =========================================================================== #
function Write-Log { param([string]$Message = '') Write-Host $Message }
function Write-Section { param([string]$Title) Save-JournalEntries -Quiet; Write-Log ''; Write-Log ('--- ' + $Title + ' ' + ('-' * [Math]::Max(3, 60 - $Title.Length))) }
function Emit-Json { param($Object) Write-Host ('###JSON### ' + ($Object | ConvertTo-Json -Compress -Depth 8)) }
function Use-Module { param([string]$Name) return ($Modules -contains $Name) }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try { $p = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop; return $p.$Name } catch { return $null }
}

# Удаляет свою задачу планировщика (страж, слежение, уведомления). «Задачи
# нет» и «задача не удалилась» — разное: раньше любая ошибка удаления
# называлась «задачи нет», и оставшийся страж потом снова выключал то, что
# человек только что вернул. Ответ: removed, absent или failed (посчитано).
function Remove-OwnTask {
    param([string]$Name, [string]$What)
    # «нет такой задачи» (ObjectNotFound) и «планировщик не ответил» — тоже разное
    $t = $null
    try { $t = Get-ScheduledTask -TaskName $Name -ErrorAction Stop }
    catch {
        if ("$($_.CategoryInfo.Category)" -eq 'ObjectNotFound') { Write-Log ("   [-] {0}: нет" -f $What); return 'absent' }
        Write-Log ("   [!] {0}: планировщик не ответил -- {1}" -f $What, $_.Exception.Message); $script:Failures++; return 'failed'
    }
    if (-not $t) { Write-Log ("   [-] {0}: нет" -f $What); return 'absent' }
    # работающую сейчас — сначала остановить, чтобы она не доделала своё
    if ("$($t.State)" -eq 'Running') { Stop-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue }
    try { Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction Stop }
    catch { Write-Log ("   [!] {0}: не удалилось -- {1}" -f $What, $_.Exception.Message); $script:Failures++; return 'failed' }
    Write-Log ("   [+] {0}: удалено" -f $What)
    return 'removed'
}

# Выключена ли задача планировщика. State тут не годится: «Disabled» он
# показывает, только пока у задачи нет работающего экземпляра, — выключенная
# задача, которая ещё доделывает свой запуск, видна как «Running», а включённая
# — как «Ready» или «Running». Признак — Settings.Enabled; State — только
# если настроек у объекта нет.
function Test-TaskDisabled {
    param($Task)
    if ($null -eq $Task) { return $false }
    $s = $Task.Settings
    if ($null -ne $s -and $null -ne $s.Enabled) { return (-not [bool]$s.Enabled) }
    return ("$($Task.State)" -eq 'Disabled')
}

# Есть ли ключ: $true, $false или $null — неизвестно (нет доступа).
function Test-RegKeyExists {
    param([string]$Path)
    $k = $null
    try { $k = Open-RegKeyRead $Path; return ($null -ne $k) }
    catch { return $null }
    finally { if ($null -ne $k) { $k.Close() } }
}

# Самый верхний из ключей, которых нет на пути к $Path (его и всё ниже
# создаст New-Item -Force). Ключ уже есть — пустая строка. Если о ключе
# или его родителе нельзя сказать наверняка (нет доступа), он «есть»: удалять
# потом можно только то, что программа точно создала сама.
function Get-TopMissingKey {
    param([string]$Path)
    if ((Test-RegKeyExists $Path) -ne $false) { return '' }
    $top = $Path
    while ($true) {
        $parent = Split-Path -Path $top -Parent
        if (-not $parent -or $parent -eq $top -or (Test-RegKeyExists $parent) -ne $false) { break }
        $top = $parent
    }
    return $top
}

# Ключ и всё под ним без единого значения. Что-то не прочиталось — считаем,
# что не пуст: удалять можно только то, что точно пусто.
function Test-KeyTreeEmpty {
    param([string]$Path)
    try {
        $k = Get-Item -LiteralPath $Path -ErrorAction Stop
        try { if ($k.ValueCount -gt 0) { return $false } } finally { $k.Close() }
        foreach ($c in @(Get-ChildItem -LiteralPath $Path -Recurse -ErrorAction Stop)) {
            try { if ($c.ValueCount -gt 0) { return $false } } finally { $c.Close() }
        }
        return $true
    } catch { return $false }
}

# Ключ реестра на чтение — RegistryKey или $null, если ключа нет. Нет доступа
# (к нему или к ключу выше) — исключение, а не $null. Пути — как у провайдера
# PowerShell: HKLM:\…, HKCU:\…, Registry::HKEY_USERS\… и т. п.
function Open-RegKeyRead {
    param([string]$Path)
    $hive = $null; $sub = ''
    switch -Regex ($Path) {
        '^(HKLM:|Registry::HKEY_LOCAL_MACHINE)(\\(.*))?$' { $hive = [Microsoft.Win32.Registry]::LocalMachine; $sub = $Matches[3]; break }
        '^(HKCU:|Registry::HKEY_CURRENT_USER)(\\(.*))?$'  { $hive = [Microsoft.Win32.Registry]::CurrentUser; $sub = $Matches[3]; break }
        '^(HKU:|Registry::HKEY_USERS)(\\(.*))?$'          { $hive = [Microsoft.Win32.Registry]::Users; $sub = $Matches[3]; break }
        '^(HKCR:|Registry::HKEY_CLASSES_ROOT)(\\(.*))?$'  { $hive = [Microsoft.Win32.Registry]::ClassesRoot; $sub = $Matches[3]; break }
    }
    if ($null -eq $hive) { throw ("неизвестная ветка реестра: {0}" -f $Path) }
    # OpenSubKey('') — отдельный дескриптор самого куста: его можно закрыть
    return $hive.OpenSubKey("$sub".TrimEnd('\'), $false)
}

# Два прочитанных состояния значения (Get-RegRaw) — одно и то же: оба «нет»
# или оба есть, того же вида и с теми же данными.
function Test-RegSameRaw {
    param($A, $B)
    if (-not $A.exists -or -not $B.exists) { return ([bool]$A.exists -eq [bool]$B.exists) }
    return ("$($A.kind)" -eq "$($B.kind)" -and (ConvertTo-RegComparable $A.value $A.kind) -eq (ConvertTo-RegComparable $B.value $B.kind))
}

# Виды значений реестра, которые программа умеет записать и вернуть.
function Test-RegKind {
    param([string]$Kind)
    return ($Kind -in @('String', 'ExpandString', 'DWord', 'QWord', 'Binary', 'MultiString'))
}

# Значение реестра как оно лежит: вид (String, DWord, ...) и данные без
# раскрытия %переменных%. Get-ItemProperty раскрывает REG_EXPAND_SZ и вида не
# называет, а откату нужно и то и другое: «%SystemRoot%\x», возвращённое
# раскрытым, или строка, возвращённая числом, — уже не то, что было.
# ok = $false — прочитать не удалось (это не «параметра нет»).
# Ключ открывается средствами самого реестра (Open-RegKeyRead): «ключа нет»
# там — пустой ответ, «нет доступа» — исключение. Раньше сначала спрашивался
# Test-Path, а он ключ, до которого нельзя добраться, мог назвать отсутствующим,
# и в журнал легло бы «значения не было».
function Get-RegRaw {
    param([string]$Path, [string]$Name)
    $key = $null
    try {
        $key = Open-RegKeyRead $Path
        if ($null -eq $key) { return @{ ok = $true; exists = $false; kind = ''; value = $null } }
        if (@($key.GetValueNames()) -notcontains $Name) { return @{ ok = $true; exists = $false; kind = ''; value = $null } }
        return @{ ok = $true; exists = $true; kind = "$($key.GetValueKind($Name))"
                  value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
    } catch {
        # denied — Windows не даёт даже прочитать (это её решение, а не сбой)
        $ex = $_.Exception
        $denied = ($ex -is [System.UnauthorizedAccessException] -or $ex -is [System.Security.SecurityException] -or
                   $ex.InnerException -is [System.UnauthorizedAccessException] -or $ex.InnerException -is [System.Security.SecurityException])
        return @{ ok = $false; exists = $false; kind = ''; value = $null; denied = $denied
                  error = ("{0}: {1}" -f $ex.GetType().Name, $ex.Message) }
    } finally {
        # открытый ключ держит куст чужого профиля: его потом не отключить
        if ($null -ne $key) { try { $key.Close() } catch { } }
    }
}

# Запасная запись мимо провайдера PowerShell: обычный API реестра просит
# ровно те права, которые нужны, и иногда справляется там, где New-ItemProperty
# уже получил отказ. Заодно рассказывает, чем именно кончилась попытка.
function Set-RegDirect {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    try {
        $hive = $null; $sub = ''
        if ($Path -match '^HKLM:\\(.+)$')      { $hive = [Microsoft.Win32.Registry]::LocalMachine; $sub = $Matches[1] }
        elseif ($Path -match '^HKCU:\\(.+)$')  { $hive = [Microsoft.Win32.Registry]::CurrentUser;  $sub = $Matches[1] }
        elseif ($Path -match '^HKCR:\\(.+)$')  { $hive = [Microsoft.Win32.Registry]::ClassesRoot;  $sub = $Matches[1] }
        elseif ($Path -match '^HKU:\\(.+)$')   { $hive = [Microsoft.Win32.Registry]::Users;        $sub = $Matches[1] }
        else { return @{ ok = $false; error = 'неизвестный куст реестра' } }
        $key = $hive.CreateSubKey($sub, $true)
        if ($null -eq $key) { return @{ ok = $false; error = 'ключ не открылся на запись' } }
        try {
            switch ($Type) {
                'DWord'        { $key.SetValue($Name, [int]$Value,  [Microsoft.Win32.RegistryValueKind]::DWord) }
                'QWord'        { $key.SetValue($Name, [long]$Value, [Microsoft.Win32.RegistryValueKind]::QWord) }
                'Binary'       { $key.SetValue($Name, [byte[]]$Value, [Microsoft.Win32.RegistryValueKind]::Binary) }
                'ExpandString' { $key.SetValue($Name, [string]$Value, [Microsoft.Win32.RegistryValueKind]::ExpandString) }
                'MultiString'  { $key.SetValue($Name, [string[]]$Value, [Microsoft.Win32.RegistryValueKind]::MultiString) }
                default        { $key.SetValue($Name, [string]$Value, [Microsoft.Win32.RegistryValueKind]::String) }
            }
        } finally { $key.Close() }
        return @{ ok = $true }
    } catch { return @{ ok = $false; error = ("{0}: {1}" -f $_.Exception.GetType().Name, $_.Exception.Message) } }
}

# Пишет во временный параметр рядом и сразу его убирает. Так видно, закрыт
# ли ключ целиком или Windows держит только один конкретный параметр.
function Test-RegKeyWritable {
    param([string]$Path)
    $probe = '_Win11PrivacyProbe'
    $r = Set-RegDirect -Path $Path -Name $probe -Value 1 -Type 'DWord'
    if (-not $r.ok) { return $false }
    try { Remove-ItemProperty -LiteralPath $Path -Name $probe -Force -ErrorAction SilentlyContinue } catch { }
    return $true
}

# Значение реестра в виде, который можно сравнить с задуманным: DWORD больше
# 0x7FFFFFFF читается отрицательным числом, расширяемая строка — уже
# раскрытой, двоичное и многострочное — массивами.
function ConvertTo-RegComparable {
    param($Value, [string]$Type)
    if ($null -eq $Value) { return $null }
    switch ($Type) {
        'DWord' { try { $n = [decimal]"$Value"; if ($n -lt 0) { $n += [decimal]4294967296 }; return "$n" } catch { return "$Value" } }
        'QWord' { try { $n = [decimal]"$Value"; if ($n -lt 0) { $n += [decimal]::Parse('18446744073709551616') }; return "$n" } catch { return "$Value" } }
        'ExpandString' { return [Environment]::ExpandEnvironmentVariables("$Value") }
        'Binary' { return ((@($Value) | ForEach-Object { '{0:x2}' -f [byte]$_ }) -join '') }
        'MultiString' { return (@($Value) -join "`n") }
    }
    return "$Value"
}

function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord', [string]$Comment = '',
          [switch]$Policy, [string]$DefId = '')
    $label = if ($Comment) { $Comment } else { "$Path -> $Name" }
    if ($DryRun) { Write-Log "   [тест] $label"; return }

    # Если параметр уже такой, как нужно — не трогаем его: часть значений
    # панели задач Windows защищает от перезаписи даже тем же самым числом.
    # «Такой» — и по данным, и по виду: строка «1» вместо числа 1 раньше
    # считалась настроенной, хотя Windows читает такой параметр как ошибку.
    # Откату нужен прежний вид значения и данные как есть: раньше в журнал шёл
    # вид нового значения, и строка «1» возвращалась числом. Есть ли значение
    # вообще — тоже отсюда: пустое двоичное или многострочное Get-RegValue
    # отдаёт как «нет», и откат удалил бы его вместо возврата. Этот же
    # прочитанный вид решает, настроено ли уже: REG_SZ «1» на месте DWORD 1
    # раньше считался настроенным, хотя Windows читает такой параметр иначе.
    $cur = Get-RegValue $Path $Name
    $raw = Get-RegRaw $Path $Name
    if ($raw.ok -and $raw.exists -and "$($raw.kind)" -eq $Type -and
        (ConvertTo-RegComparable $raw.value $Type) -eq (ConvertTo-RegComparable $Value $Type)) { Write-Log "   [в] $label -- уже настроено"; $script:Already++; return }

    # Менять можно, только пока пишется журнал отката, — в том числе при
    # прямых вызовах (монитор, чистка), а не только из применения модулей.
    if (-not (Test-CanModify $label)) { return }
    Ensure-Backup          # копию делаем перед первым изменением, а не «всегда»
    if (-not $raw.ok -and $raw.denied -and $Policy) {
        # как и отказ в записи ниже: политику держит сама Windows
        Write-Log "   [-] $label -- Windows этой редакции не разрешает менять этот параметр"
        $script:Blocked++
        if ($DefId) { $script:BlockedIds[$DefId] = $true }
        return
    }
    if (-not $raw.ok -or ($null -ne $cur -and -not $raw.exists)) {
        # не прочиталось — «как было» записать нечем, а без него менять нельзя
        Write-Log ("   [!] {0} -- не меняется: прежнее значение не прочиталось ({1}), вернуть его было бы нечем" -f $label, $(if ($raw.error) { $raw.error } else { 'значение есть, но не читается' }))
        $script:Failures++; return
    }
    $existed = [bool]$raw.exists
    $oldValue = ''
    $oldType = $Type
    if ($existed) {
        if (-not (Test-RegKind $raw.kind)) {
            Write-Log ("   [!] {0} -- не меняется: прежнее значение вида {1}, такое откат вернуть не сумеет" -f $label, $raw.kind)
            $script:Failures++; return
        }
        $oldType = $raw.kind
        $oldValue = $raw.value
    }
    # Ключа нет — New-Item создаст и его, и недостающие ключи выше. Самый
    # верхний из них запоминается: откат уберёт его, если в нём не останется
    # ни одного значения. Раньше пустые ключи политик оставались навсегда.
    $createdKey = Get-TopMissingKey $Path
    # «Как было» — на диск раньше изменения (см. Write-AheadEntry). Если
    # изменение не пройдёт, запись отзывается: изменения ведь не было.
    # type — вид прежнего значения (им его и вернёт откат).
    $entry = @{ kind = 'reg'; path = $Path; name = $Name; type = $oldType; existed = $existed; old = $oldValue; newValue = "$Value" }
    if ($createdKey) { $entry['createdKey'] = $createdKey }
    if (-not (Write-AheadEntry $entry)) {
        Write-Log "   [!] $label -- не меняется: «как было» не легло в журнал отката"
        $script:Failures++; return
    }
    $done = $false
    $why = ''
    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        $done = $true
    } catch {
        $why = ("{0}: {1}" -f $_.Exception.GetType().Name, $_.Exception.Message)
        # Команда сообщила об ошибке, но значение могло и лечь. Раньше в этом
        # случае запись «как было» отзывалась («уже настроено»), хотя до записи
        # значение было другим — изменение было, и путь назад терялся. Теперь
        # такое значение — сделанное изменение: запись остаётся, дальше — сверка.
        $after = Get-RegRaw $Path $Name
        if ($after.ok -and $after.exists -and $after.kind -eq $Type -and (ConvertTo-RegComparable $after.value $Type) -eq (ConvertTo-RegComparable $Value $Type)) {
            Write-Log ("   [i] {0} -- команда записи сообщила об ошибке ({1}), но значение легло" -f $label, $why)
            $done = $true
        } else {
            $retry = Set-RegDirect -Path $Path -Name $Name -Value $Value -Type $Type
            if ($retry.ok) { $done = $true } else { $why += " / вторая попытка: $($retry.error)" }
        }
    }

    if ($done) {
        # «Команда прошла» — ещё не «значение такое»: читаем обратно и сверяем
        # и данные, и вид значения. Запись в журнале остаётся в любом случае:
        # значение уже не прежнее.
        $now = Get-RegRaw $Path $Name
        $want = ConvertTo-RegComparable $Value $Type
        $got = $(if ($now.ok -and $now.exists) { ConvertTo-RegComparable $now.value $Type } else { $null })
        if (-not $now.ok -or -not $now.exists -or $now.kind -ne $Type -or $got -ne $want) {
            $seen = $(if (-not $now.ok) { "не читается ($($now.error))" } elseif (-not $now.exists) { 'нет значения' } elseif ($now.kind -ne $Type) { "{0} вида {1}" -f $got, $now.kind } else { $got })
            Write-Log ("   [!] {0} -- записано, но читается другое: ожидалось {1} ({2}), сейчас {3}" -f $label, $want, $Type, $seen)
            $script:Failures++
            return
        }
        if ($Policy -and $DefId) { $script:UnblockedIds[$DefId] = $true }   # отдала — снимаем пометку
        Write-Log "   [+] $label"; $script:Changes++
        return
    }

    # Записать не вышло. Было ли изменение — решает не ответ команды, а то, что
    # лежит сейчас: прежнее значение — изменения не было, запись отзывается;
    # не прочиталось или стало чем-то третьим (запись оборвалась на середине) —
    # запись «как было» остаётся для отката, и это ошибка.
    $now = Get-RegRaw $Path $Name
    if (-not $now.ok -or -not (Test-RegSameRaw $now $raw)) {
        $state = $(if (-not $now.ok) { "не читается ({0})" -f $now.error } elseif (-not $now.exists) { 'значения нет' } else { "{0} вида {1}" -f (ConvertTo-RegComparable $now.value $now.kind), $now.kind })
        Write-Log ("   [!] {0} -- не записалось ({1}), но значение уже не прежнее: сейчас {2}. Запись «как было» оставлена для отката" -f $label, $why, $state)
        $script:Failures++
        return
    }
    Undo-AheadEntry $entry
    # ключ, который успел создать New-Item, — пустой и ничей: убираем
    if ($createdKey -and (Test-RegKeyExists $createdKey) -and (Test-KeyTreeEmpty $createdKey)) {
        Remove-Item -LiteralPath $createdKey -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($why -like '*UnauthorizedAccessException*' -or $why -like '*SecurityException*') {
        # Часть политик Windows держит сама и не отдаёт даже администратору —
        # это не поломка программы, а решение системы, и в ошибки оно не идёт.
        if ($Policy) {
            Write-Log "   [-] $label -- Windows этой редакции не разрешает менять этот параметр"
            $script:Blocked++
            if ($DefId) { $script:BlockedIds[$DefId] = $true }
            return
        }
        Write-Log "   [!] $label -- Windows не отдаёт этот параметр даже администратору"
        Write-Log "       ключ: $Path -> $Name"
        Write-Log "       права администратора у программы: $(if (Test-Admin) { 'есть' } else { 'НЕТ' })"
        if (Test-RegKeyWritable $Path) {
            Write-Log "       ключ пишется, но именно этот параметр Windows защищает"
        } else {
            Write-Log "       ключ закрыт целиком: менять его может только сама система"
        }
        Write-Log "       подробности: $why"
    } else {
        Write-Log "   [!] не удалось: $label -- $why"
    }
    $script:Failures++
}

function Get-FolderSizeMB {
    param([string]$FolderPath)
    if (-not (Test-Path -LiteralPath $FolderPath)) { return 0 }
    # только файлы: у каталогов нет Length, и Measure-Object сыпал ошибкой в журнал
    $sum = (Get-ChildItem -LiteralPath $FolderPath -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    if (-not $sum) { return 0 }
    return [math]::Round($sum / 1MB, 1)
}

# Удаление дерева, которое не заходит внутрь ссылок. Remove-Item -Recurse в
# PowerShell 5.1 проходит по junction и символическим ссылкам и удаляет то,
# куда они ведут: ссылка во временной папке на «Документы» стёрла бы
# документы. Здесь ссылка удаляется сама, как запись, — её цель не трогается.
# $Stats — @{ deleted; failed; skipped; errors }: что удалено, что нет и почему.
#
# -TrustedOwnerOnly — для общих системных папок (C:\Windows\Temp,
# ProgramData\...\WER), куда может писать любой пользователь: удаляется
# только то, чей владелец доверенный ($script:ClearOwners), и только в такие
# папки движок заходит. Остальное оставляется его хозяину.
$script:ClearOwners = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-19', 'S-1-5-20',
                        'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
function Test-TrustedOwner {
    param([string]$Path)
    try { return ($script:ClearOwners -contains (Get-Acl -LiteralPath $Path -ErrorAction Stop).GetOwner([Security.Principal.SecurityIdentifier]).Value) }
    catch { return $false }
}

function Remove-TreeNoFollow {
    param([string]$Path, $Stats, [switch]$TrustedOwnerOnly)
    try { $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop } catch { return }
    try {
        # Общая системная папка: чужое не трогаем и внутрь не заходим. Ссылки
        # пропускаются целиком: Get-Acl на ссылке отвечает про её ЦЕЛЬ, и по
        # владельцу судить о самой ссылке нельзя.
        if ($TrustedOwnerOnly -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not (Test-TrustedOwner $item.FullName))) { $Stats.skipped++; return }
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            if ($item.PSIsContainer) { [IO.Directory]::Delete($item.FullName, $false) } else { [IO.File]::Delete($item.FullName) }
            $Stats.deleted++
            return
        }
        if ($item.PSIsContainer) {
            foreach ($c in @(Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue)) { Remove-TreeNoFollow $c.FullName $Stats -TrustedOwnerOnly:$TrustedOwnerOnly }
            # папка уходит, только если опустела: что внутри не удалилось, уже посчитано
            if (@(Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0) { [IO.Directory]::Delete($item.FullName, $false) }
            return
        }
        if ($item.Attributes -band [IO.FileAttributes]::ReadOnly) { $item.Attributes = $item.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly) }
        [IO.File]::Delete($item.FullName)
        $Stats.deleted++
    } catch {
        $Stats.failed++
        if ($Stats.errors.Count -lt 3) { $Stats.errors.Add(("{0}: {1}" -f $item.Name, $_.Exception.Message)) }
    }
}

# Сценарий для задачи от имени пользователя: очищает его папки тем же
# способом — ссылки удаляются как записи, внутрь них не заходит. -MinAgeHours
# оставляет свежие файлы (во временной папке ими ещё пользуются программы).
function Get-ClearUserScript {
    return @'
param([string]$InputFile, [string]$ResultFile)
$in = (Get-Content -LiteralPath $InputFile -Raw -Encoding UTF8) | ConvertFrom-Json
function Clr($p, $s, $cut) {
  try { $i = Get-Item -LiteralPath $p -Force -ErrorAction Stop } catch { return }
  try {
    if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) {
      if ($i.PSIsContainer) { [IO.Directory]::Delete($i.FullName, $false) } else { [IO.File]::Delete($i.FullName) }
      $s.deleted++; return }
    if ($i.PSIsContainer) {
      foreach ($c in @(Get-ChildItem -LiteralPath $i.FullName -Force -ErrorAction SilentlyContinue)) { Clr $c.FullName $s $cut }
      if (@(Get-ChildItem -LiteralPath $i.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0) { [IO.Directory]::Delete($i.FullName, $false) }
      return }
    if ($cut -and ($i.LastWriteTime -gt $cut -or $i.CreationTime -gt $cut)) { $s.recent++; return }
    $len = $i.Length
    if ($i.Attributes -band [IO.FileAttributes]::ReadOnly) { $i.Attributes = $i.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly) }
    [IO.File]::Delete($i.FullName); $s.deleted++; $s.bytes += $len
  } catch { $s.failed++; if ($s.errors.Count -lt 3) { $s.errors += ('{0}: {1}' -f $i.Name, $_.Exception.Message) } }
}
$out = @()
foreach ($t in @($in.targets)) {
  $s = @{ path = "$($t.path)"; state = 'done'; deleted = 0; failed = 0; recent = 0; bytes = [int64]0; errors = @() }
  $p = "$($t.path)"
  if (-not (Test-Path -LiteralPath $p -PathType Container)) { $s.state = 'missing' }
  elseif ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { $s.state = 'link' }
  else {
    $cut = $null; if ([double]$t.minAgeHours -gt 0) { $cut = (Get-Date).AddHours(-[double]$t.minAgeHours) }
    $f = "$($t.filter)"
    $items = $(if ($f) { @(Get-ChildItem -LiteralPath $p -Filter $f -File -Force -ErrorAction SilentlyContinue) } else { @(Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue) })
    foreach ($c in $items) { Clr $c.FullName $s $cut }
  }
  $out += $s
}
ConvertTo-Json -InputObject @{ targets = $out } -Depth 5 -Compress | Set-Content -LiteralPath $ResultFile -Encoding UTF8
'@
}

# Папки, которые очищать нельзя ни при каком пути: корень диска и системные корни
function Test-ClearForbidden {
    param([string]$Full)
    $f = $Full.TrimEnd('\')
    if ($f -eq ([IO.Path]::GetPathRoot($Full)).TrimEnd('\')) { return $true }
    foreach ($p in @($env:SystemRoot, "$env:SystemRoot\System32", $env:ProgramData, $env:ProgramFiles, ${env:ProgramFiles(x86)},
                     $env:USERPROFILE, [Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('Desktop'), (Split-Path $env:USERPROFILE -Parent))) {
        if ($p -and $f -eq ([IO.Path]::GetFullPath($p)).TrimEnd('\')) { return $true }
    }
    return $false
}

function Clear-FolderContents {
    param([string]$FolderPath, [string]$Label, [string]$Step = '', [switch]$TrustedOwnerOnly)
    if (-not (Test-Path -LiteralPath $FolderPath)) {
        if ($Step) { Write-Log ("   {0} {1} -- нечего чистить" -f $Step, $Label) }
        return 0.0
    }
    $full = [IO.Path]::GetFullPath($FolderPath)
    # Сама папка — ссылка (например, временную папку подменили junction на
    # «Документы») или корень, который чистить нельзя: отказ, а не удаление.
    $dirItem = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if (($dirItem -and ($dirItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) -or (Test-ClearForbidden $full)) {
        Write-Log ("   [!] {0} -- папка {1} ведёт не туда (ссылка или системная папка) -- не очищается" -f $Label, $full)
        $script:Failures++
        return 0.0
    }
    # Большую папку посчитать и вычистить — это минуты, а строка шага
    # появлялась только в конце, и чистка выглядела зависшей.
    if ($Step) { Write-Log ("   {0} {1}..." -f $Step, $Label) }
    $before = Get-FolderSizeMB $full
    if ($DryRun) { Write-Log ("   {0} [тест] {1} -- можно освободить ~{2} МБ" -f $Step, $Label, $before); return 0.0 }
    $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
    foreach ($c in @(Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue)) { Remove-TreeNoFollow $c.FullName $st -TrustedOwnerOnly:$TrustedOwnerOnly }
    $freed = [math]::Max(0, [math]::Round($before - (Get-FolderSizeMB $full), 1))
    if ($Step) { Write-Log ("   {0} {1} -- освобождено {2} МБ" -f $Step, $Label, $freed) }
    else { Write-Log ("   [+] {0} -- освобождено {1} МБ" -f $Label, $freed) }
    # Что не удалилось, называется: раньше ошибки глушились, и «освобождено»
    # выглядело полным. Занятые файлы — обычное дело, это сведения, а не сбой.
    if ($st.skipped -gt 0) { Write-Log ("       оставлено файлов и папок других пользователей: {0}" -f $st.skipped) }
    if ($st.failed -gt 0) {
        Write-Log ("       не удалено (заняты или нет доступа): {0}" -f $st.failed)
        foreach ($e in $st.errors) { Write-Log ("       {0}" -f $e) }
    }
    $script:LastClear = $st
    return [double]$freed
}

# Системная ли папка: внутри Windows или ProgramData. Такие движок чистит сам
# (с -TrustedOwnerOnly); всё прочее — папки пользователя, их чистит задача
# от его имени.
function Test-SystemClearPath {
    param([string]$Full)
    foreach ($root in @($script:WinDir, $script:ProgramDataDir)) {
        if ($root -and $Full.StartsWith($root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# Папки пользователя — одной задачей от его имени. $Targets — список
# @{ P; L; Age (часы, 0 — все); Filter (маска файлов в самой папке) }.
# Возвращает освобождённые МБ.
function Clear-UserFolders {
    param([object[]]$Targets)
    $send = @(); $total = 0.0
    foreach ($t in $Targets) {
        # папки того, кто сидит за компьютером (см. Convert-ToSessionPath)
        $full = Convert-ToSessionPath ([IO.Path]::GetFullPath($t.P))
        if (Test-ClearForbidden $full) { Write-Log ("   [!] {0} -- {1} чистить нельзя" -f $t.L, $full); $script:Failures++; continue }
        $send += @{ path = $full; label = "$($t.L)"; minAgeHours = [double]$t.Age; filter = "$($t.Filter)" }
    }
    if ($send.Count -eq 0) { return 0.0 }
    if ($DryRun) { foreach ($s in $send) { Write-Log ("   [тест] {0} -- очистит задача от вашего имени" -f $s.label) }; return 0.0 }
    $r = Invoke-AsUser 'clear' (Get-ClearUserScript) @{ targets = $send } -Minutes 15
    if (-not $r.ok) {
        Write-Log ("   [!] папки профиля не очищены: {0}" -f $r.why); $script:Failures++
        return 0.0
    }
    for ($i = 0; $i -lt $send.Count; $i++) {
        $res = @($r.result.targets)[$i]
        $lbl = $send[$i].label
        if ($null -eq $res) { Write-Log ("   [!] {0} -- итога нет" -f $lbl); $script:Failures++; continue }
        switch ("$($res.state)") {
            'missing' { Write-Log ("   [-] {0} -- нечего чистить" -f $lbl) }
            'link'    { Write-Log ("   [!] {0} -- папка оказалась ссылкой и не очищается" -f $lbl); $script:Failures++ }
            default {
                $mb = [math]::Round([double]$res.bytes / 1MB, 1); $total += $mb
                Write-Log ("   [+] {0} -- освобождено {1} МБ" -f $lbl, $mb)
                if ([int]$res.recent -gt 0) { Write-Log ("       оставлено свежих файлов (моложе {0} ч): {1}" -f $send[$i].minAgeHours, $res.recent) }
                if ([int]$res.failed -gt 0) {
                    Write-Log ("       не удалено (заняты или нет доступа): {0}" -f $res.failed)
                    foreach ($e in @($res.errors)) { if ($e) { Write-Log ("       {0}" -f $e) } }
                }
            }
        }
    }
    return [double]$total
}

# Одна папка — тем способом, который ей годится (см. Test-SystemClearPath)
function Clear-Folder {
    param([string]$FolderPath, [string]$Label, [string]$Step = '', [double]$MinAgeHours = 0)
    $full = [IO.Path]::GetFullPath($FolderPath)
    if (Test-SystemClearPath $full) { return (Clear-FolderContents $full $Label $Step -TrustedOwnerOnly) }
    if ($Step) { Write-Log ("   {0} {1}..." -f $Step, $Label) }
    return (Clear-UserFolders @(@{ P = $full; L = $Label; Age = $MinAgeHours }))
}

# Задачи по маске имени (OneDrive*, NvTm*) — только в своих папках
# планировщика. Раньше проверялось одно имя: задача с подходящим именем
# годилась в любой папке, и откат журнала прежней версии мог включить чужую.
# OneDrive и NVIDIA кладут эти задачи в корень библиотеки.
$script:TaskGlobFolders = @{ 'OneDrive*' = @('\'); 'NvTm*' = @('\') }

function Get-TaskGlobFolders {
    param([string]$Glob)
    if ($script:TaskGlobFolders -and $script:TaskGlobFolders[$Glob]) { return @($script:TaskGlobFolders[$Glob]) }
    return @('\')
}

# полный путь задачи («\папка\имя») подходит под маску и её папки
function Test-TaskGlobPath {
    param([string]$Full, [string]$Glob)
    $pp = Split-TaskPath $Full
    return (((Get-TaskGlobFolders $Glob) -contains $pp[0]) -and ($pp[1] -like $Glob))
}

# -AnyFolder — только для прежнего отката: версии до 1.11 отключали задачи по
# маске в любой папке и в журнал их не писали; вернуть их можно лишь тем же
# поиском. Маски тут — свои, из списка программы, а не данные из журнала.
function Get-TaskGlobTasks {
    param([string]$Glob, [switch]$AnyFolder)
    $folders = @(Get-TaskGlobFolders $Glob)
    return @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { ($AnyFolder -or ($folders -contains $_.TaskPath)) -and ($_.TaskName -like $Glob) })
}

function Split-TaskPath {
    param([string]$Full)
    $name = Split-Path $Full -Leaf
    $path = (Split-Path $Full -Parent)
    if (-not $path.EndsWith('\')) { $path += '\' }
    return @($path, $name)
}

# --- Защита папки данных ------------------------------------------------------ #
#  Из ProgramData\Win11Privacy журнал отката читается с правами администратора
#  (по нему пишется реестр), а копию движка оттуда запускают задачи стража.
#  Права ProgramData по умолчанию позволяют обычному пользователю создавать
#  файлы и папки во всех её подпапках, и подложенный заранее changes.json.tmp
#  или engine.ps1 остался бы его собственностью: он мог бы дописать в журнал
#  что угодно, а откат записал бы это в реестр от имени администратора.
#  Поэтому права корня задаются явно — писать могут только система и
#  администраторы, — а всё, что завёл кто-то другой, уходит в карантин.
function Get-OwnerSid {
    param([string]$Path)
    try { return (Get-Acl -LiteralPath $Path -ErrorAction Stop).GetOwner([Security.Principal.SecurityIdentifier]).Value } catch { return '' }
}

function Test-DirSecure {
    param([string]$Dir)
    try {
        if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return $false }
        if ((Get-Item -LiteralPath $Dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        $acl = Get-Acl -LiteralPath $Dir -ErrorAction Stop
        if ($script:TrustedSids -notcontains $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value) { return $false }
        if (-not $acl.AreAccessRulesProtected) { return $false }
        # запись, удаление, смена прав или владельца — в том числе общими правами
        $writeMask = 0x2 -bor 0x4 -bor 0x10 -bor 0x40 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x40000000 -bor 0x10000000
        foreach ($r in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ("$($r.AccessControlType)" -ne 'Allow') { continue }
            if ($script:TrustedSids -contains $r.IdentityReference.Value) { continue }
            if (([int64]$r.FileSystemRights -band $writeMask) -ne 0) { return $false }
        }
        return $true
    } catch { return $false }
}

# Можно ли верить файлу или папке: не ссылка, владелец — система,
# администраторы или TrustedInstaller, и никто другой не может его изменить,
# удалить, переименовать, сменить права или владельца (W11P-006).
#
# Раньше смотрелись только явные права (GetAccessRules($true, $false)):
# право на запись, доставшееся от родительской папки, проходило незамеченным.
# Теперь — все права, явные и унаследованные:
#   * к самому объекту относится всё, кроме «только для вложенного»;
#   * у папки ещё и то, что она передаст вложенному (её файлы и папки получат
#     эти права) — кроме «создатель-владелец» и «создатель-группа»: на месте
#     этих записей у вложенного окажется тот, кто его создал (сам движок);
#   * запрет вычитается, только если он явный, для «Все» (Everyone), список
#     прав в обычном порядке и запрет относится к самому объекту: такой
#     запрет проверяется раньше любого разрешения и касается любого. Запрет
#     одной группы не закрывает того, у кого право пришло через другую
#     (например, «Прошедшие проверку»), а унаследованный запрет стоит после
#     явных разрешений и их не отменяет. Для вложенного запреты не вычитаются
#     вовсе: у него могут быть свои явные разрешения, которые идут раньше.
# Права не читаются — не верим (отказ, а не «доступа нет»).
# -ExplicitOnly — только для переноса старой папки данных (Protect-DataRoot):
# там унаследованные права тут же заменяет новый корень, а после замены
# всё проверяется ещё раз полностью.
function Get-UntrustedRights {
    param($Acl, [bool]$Container, [switch]$ExplicitOnly)
    $self = [int64]0; $child = [int64]0; $deny = [int64]0
    $canonical = [bool]$Acl.AreAccessRulesCanonical
    $inh = [Security.AccessControl.InheritanceFlags]::ObjectInherit -bor [Security.AccessControl.InheritanceFlags]::ContainerInherit
    foreach ($r in $Acl.GetAccessRules($true, (-not $ExplicitOnly), [Security.Principal.SecurityIdentifier])) {
        $sid = $r.IdentityReference.Value
        $rights = [int64]$r.FileSystemRights
        $inheritOnly = [bool]($r.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly)
        # «не распространять дальше» всё равно достаётся прямым вложенным
        $toChildren = $Container -and [bool]($r.InheritanceFlags -band $inh)
        if ("$($r.AccessControlType)" -eq 'Deny') {
            if ($canonical -and -not $r.IsInherited -and -not $inheritOnly -and $sid -eq 'S-1-1-0') { $deny = $deny -bor $rights }
            continue
        }
        if ($script:TrustedSids -contains $sid) { continue }
        # «Права владельца» (OWNER RIGHTS) достаются владельцу, а он проверен
        if ($sid -eq 'S-1-3-4') { continue }
        if (-not $inheritOnly) { $self = $self -bor $rights }
        # «создатель-владелец» и «создатель-группа» у вложенного станут тем,
        # кто его создаст; остальное вложенное получит как есть
        if ($toChildren -and $sid -ne 'S-1-3-0' -and $sid -ne 'S-1-3-1') { $child = $child -bor $rights }
    }
    return (($self -band (-bnot $deny)) -bor $child)
}

function Test-ItemTrusted {
    param($Item, [switch]$ExplicitOnly)
    if ($null -eq $Item -or ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
    try { $acl = Get-Acl -LiteralPath $Item.FullName -ErrorAction Stop } catch { return $false }
    try {
        $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier])
        if ($null -eq $owner -or $script:TrustedSids -notcontains $owner.Value) { return $false }
        # запись, удаление (своё и вложенного), смена прав или владельца,
        # атрибутов — в том числе общими правами
        $writeMask = 0x2 -bor 0x4 -bor 0x10 -bor 0x40 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x40000000 -bor 0x10000000
        $open = Get-UntrustedRights $acl ([bool]$Item.PSIsContainer) -ExplicitOnly:$ExplicitOnly
        return (($open -band $writeMask) -eq 0)
    } catch { return $false }
}

# Объект и весь путь до него (W11P-006): сам он — Test-ItemTrusted, а ни одну
# папку выше чужой не может переименовать, удалить, перенастроить или
# вычистить вложенное (Test-DirChainSecure). Иначе папку с проверенными
# правами можно было бы подменить целиком, переименовав её родителя.
function Test-PathTrusted {
    param([string]$Path)
    try { $it = Get-Item -LiteralPath $Path -Force -ErrorAction Stop } catch { return $false }
    if (-not (Test-ItemTrusted $it)) { return $false }
    $parent = Split-Path -Path $it.FullName -Parent
    if (-not $parent) { return $true }
    return (Test-DirChainSecure $parent)
}

# Всё недоверенное на любой глубине. Внутрь ссылок и чужих папок не заходим:
# они уходят в карантин целиком.
# Путь внутри собирается из имён: отрезать начало полного пути нельзя — у
# временной папки бывает короткое имя 8.3, а у найденного — длинное.
function Get-UntrustedItems {
    param([string]$Dir, [string]$Rel = '', [switch]$ExplicitOnly)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($c in @(Get-ChildItem -LiteralPath $Dir -Force -ErrorAction SilentlyContinue)) {
        $r = $(if ($Rel) { Join-Path $Rel $c.Name } else { $c.Name })
        if (-not (Test-ItemTrusted $c -ExplicitOnly:$ExplicitOnly)) { $out.Add([pscustomobject]@{ Item = $c; Rel = $r }); continue }
        if ($c.PSIsContainer) { foreach ($x in @(Get-UntrustedItems $c.FullName $r -ExplicitOnly:$ExplicitOnly)) { $out.Add($x) } }
    }
    return $out.ToArray()
}

# Найденное недоверенное — в свежий карантин рядом, с тем же путём внутри.
function Move-UntrustedAside {
    param([string]$Dir, [object[]]$Untrusted)
    if (@($Untrusted).Count -eq 0) { return $true }
    $aside = New-QuarantineDir $Dir
    if (-not $aside) { Write-Log '   [!] не удалось завести папку карантина -- чужое в папке данных не тронуто'; return $false }
    foreach ($u in $Untrusted) {
        $to = Join-Path $aside $u.Rel
        $toDir = Split-Path $to -Parent
        if (-not (Test-Path -LiteralPath $toDir)) { New-Item -ItemType Directory -Path $toDir -Force | Out-Null }
        if ($u.Item.PSIsContainer) { [IO.Directory]::Move($u.Item.FullName, $to) } else { [IO.File]::Move($u.Item.FullName, $to) }
        Write-Log ("   [!] в папке данных лежал чужой файл, он отложен: {0}" -f $u.Rel)
    }
    return $true
}

# Свежая пустая папка карантина рядом с корнем: имя со случайным хвостом,
# которого заранее не угадать, и мы сами её создаём. Предсказуемый путь
# «<корень>.untrusted-<время>» обычный пользователь мог завести заранее —
# папкой или junction, — и перенос «чужого» с правами администратора ушёл бы
# по ссылке в защищённую папку. Создать не вышло или на месте оказалась
# ссылка — пустая строка, карантин не делается.
function New-QuarantineDir {
    param([string]$Dir)
    # Права карантину задаём сразу при создании — только система и
    # администраторы, наследование выключено. Раньше папка наследовала права
    # ProgramData, где обычный пользователь вправе заводить свои файлы и папки;
    # в карантин же «чужое» переносится с правами администратора. Права ставим
    # лишь под администратором: обычному процессу сменить владельца на
    # «Администраторы» система не даёт, а наяву карантин делает только
    # повышенный движок (Protect-DataRoot).
    $sec = $null
    $isAdmin = $false
    try { $isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { }
    if ($isAdmin) {
        try {
            $sec = New-Object System.Security.AccessControl.DirectorySecurity
            $sec.SetAccessRuleProtection($true, $false)
            $inh = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
            foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
                $sec.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', $inh, 'None', 'Allow')))
            }
            $sec.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
        } catch { $sec = $null }
    }
    for ($i = 0; $i -lt 20; $i++) {
        $cand = "$Dir.untrusted-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        if (Test-Path -LiteralPath $cand) { continue }
        try {
            if ($sec) { $null = [IO.Directory]::CreateDirectory($cand, $sec) }
            else { $null = [IO.Directory]::CreateDirectory($cand) }
        } catch {
            # не вышло задать права — создаём хотя бы саму папку: содержимому
            # карантина всё равно не верят, а отказ хуже слабых прав
            try { $null = [IO.Directory]::CreateDirectory($cand) } catch { continue }
        }
        if ((Get-Item -LiteralPath $cand -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            try { [IO.Directory]::Delete($cand, $true) } catch { }
            continue
        }
        return $cand
    }
    return ''
}

function Protect-DataRoot {
    param([string]$Dir)
    if (-not (Test-Admin)) { return (Test-DirSecure $Dir) }
    try {
        if (Test-Path -LiteralPath $Dir) {
            $it = Get-Item -LiteralPath $Dir -Force
            if (($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($script:TrustedSids -notcontains (Get-OwnerSid $Dir))) {
                # папку завёл не администратор — ничему внутри верить нельзя.
                # Переносим в свежесозданный карантин: Move на уже существующий
                # путь не идёт, а предсказуемый путь можно было занять заранее.
                $aside0 = New-QuarantineDir $Dir
                if (-not $aside0) { Write-Log '   [!] не удалось завести папку карантина -- папка данных не тронута'; return $false }
                # Move не умеет в существующую пустую папку — кладём внутрь неё
                [IO.Directory]::Move($Dir, (Join-Path $aside0 (Split-Path $Dir -Leaf)))
                Write-Log ("   [!] папку данных завёл не администратор -- она отложена как {0}" -f (Split-Path $aside0 -Leaf))
            }
        }
        $sec = New-Object System.Security.AccessControl.DirectorySecurity
        $sec.SetAccessRuleProtection($true, $false)
        $inh = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        foreach ($p in @(@('S-1-5-18', 'FullControl'), @('S-1-5-32-544', 'FullControl'), @('S-1-5-32-545', 'ReadAndExecute'))) {
            $sid = New-Object Security.Principal.SecurityIdentifier($p[0])
            $sec.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, $p[1], $inh, 'None', 'Allow')))
        }
        $sec.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
        # Новая папка — сразу с правами: раньше она создавалась с правами,
        # унаследованными от ProgramData, и закрывалась вторым шагом, а между
        # ними обычный пользователь успел бы завести в ней свой файл.
        if (-not (Test-Path -LiteralPath $Dir)) { $null = [IO.Directory]::CreateDirectory($Dir, $sec) }
        if (Test-DirSecure $Dir) { return $true }
        # Папка прежних версий: права наследовались от ProgramData, и обычный
        # пользователь мог завести файлы и папки на любой глубине — раньше
        # проверялось только то, что лежит прямо в корне. Всё, что создал не
        # администратор, любые ссылки и всё, что чужим явным правом открыто
        # на запись, уносим в карантин рядом — с тем же путём внутри.
        # Унаследованные от ProgramData права тут не в счёт: их сейчас же
        # заменят права нового корня.
        if (-not (Move-UntrustedAside $Dir @(Get-UntrustedItems $Dir -ExplicitOnly))) { return $false }
        [IO.Directory]::SetAccessControl($Dir, $sec)
        if (-not (Test-DirSecure $Dir)) { return $false }
        # Новые права корня разошлись по вложенному — теперь проверяем всё
        # полностью, с унаследованным (W11P-006). Обычно здесь пусто; если
        # нет — в карантин и это.
        if (-not (Move-UntrustedAside $Dir @(Get-UntrustedItems $Dir))) { return $false }
        return (Test-DirSecure $Dir)
    } catch {
        Write-Log ("   [!] не удалось защитить папку данных {0}: {1}" -f $Dir, $_.Exception.Message)
        return $false
    }
}

# Корень защищён, и путь до него (ProgramData, корень диска) не даёт чужому
# переименовать или удалить его целиком (W11P-006): иначе закрытую папку
# можно было бы отодвинуть и положить на её место свою.
function Test-SafeRootChain {
    return [bool](Test-DirChainSecure (Split-Path $script:SafeRoot -Parent))
}

function Assert-SafeRoot {
    if ($null -eq $script:RootState) {
        $chain = [bool](Test-SafeRootChain)
        if (-not $chain) { Write-Log ("   [!] папку {0} может переименовать или удалить не администратор -- защищённой папке данных там не место" -f (Split-Path $script:SafeRoot -Parent)) }
        $script:RootState = $chain -and [bool](Protect-DataRoot $script:SafeRoot)
    }
    return $script:RootState
}

# Тома без прав доступа (FAT, exFAT) и сетевые папки: закрыть папку там нечем.
function Test-AclVolume {
    param([string]$Dir)
    try {
        $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Dir))
        if ($root -like '\\*') { return $false }
        return ((New-Object IO.DriveInfo($root)).DriveFormat -in @('NTFS', 'ReFS'))
    } catch { return $false }
}

# Может ли кто-то, кроме системы и администраторов, подменить папку — то
# есть удалить или переименовать её или любую папку выше, сменить им права
# или владельца. Закрыть одну папку данных мало: если её родитель открыт на
# запись, папку можно переименовать и положить на её место свою — между
# проверкой и чтением.
function Test-DirChainSecure {
    param([string]$Dir)
    try {
        $self  = 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000   # удаление, права, владелец, общие
        $child = 0x40 -bor 0x10000000 -bor 0x40000000                                # удаление вложенного
        $cur = [IO.Path]::GetFullPath($Dir).TrimEnd('\')
        while ($cur) {
            $parent = [IO.Path]::GetDirectoryName($cur)
            $isRoot = (-not $parent)
            $node = $(if ($isRoot) { $cur.TrimEnd('\') + '\' } else { $cur })
            $it = Get-Item -LiteralPath $node -Force -ErrorAction Stop
            if (-not $isRoot -and ($it.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
            $acl = Get-Acl -LiteralPath $node -ErrorAction Stop
            if ($script:TrustedSids -notcontains $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value) { return $false }
            $mask = $(if ($isRoot) { $child } else { $self -bor $child })
            foreach ($r in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
                if ("$($r.AccessControlType)" -ne 'Allow') { continue }
                # «создатель-владелец» и прочие шаблоны для вложенного к самой папке не относятся
                if ($r.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
                if ($script:TrustedSids -contains $r.IdentityReference.Value) { continue }
                if (([int64]$r.FileSystemRights -band $mask) -ne 0) { return $false }
            }
            if ($isRoot) { break }
            $cur = $parent
        }
        return $true
    } catch { return $false }
}

# --------------------------------------------------------------------------- #
#  Личная рабочая папка для файла, который пишет системная утилита, а читает
#  движок с правами администратора (T-2: копия политики аудита, auditpol
#  /backup). Раньше, пока защищённого корня ещё не было, файл ложился во
#  временную папку пользователя: её может менять любая его программа, и
#  подменённая или недописанная копия читалась бы с правами администратора
#  (по ней — состояние монитора и «как было» в журнале отката), а сама
#  временная папка могла оказаться ссылкой (junction) — auditpol писал бы по ней.
#  Повышенный движок берёт только место, куда обычной программе не дотянуться:
#    * защищённый корень ProgramData\Win11Privacy, если он уже есть и проверен
#      вместе с путём (Test-PathTrusted). Без побочных действий: чтение
#      политики корень не заводит и не чинит (Assert-SafeRoot здесь не зовётся);
#    * иначе — системная временная папка Windows\Temp, если ни одну папку на
#      пути к ней чужой не может удалить, переименовать или перенастроить
#      (Test-DirChainSecure). Создавать в ней пользователи могут, а читать
#      её список и чужие файлы, удалять чужое — нет.
#  Там заводится новая папка со случайным именем и с правами с самого
#  создания: только система и администраторы, без наследования, владелец —
#  «Администраторы». Имя уже занято или папка после создания не прошла
#  проверку (ссылка, чужой владелец, чужие права, не пуста) — она не наша.
#  Без повышения границы прав нет (движок может то же, что любая программа
#  пользователя) — годится и обычная временная папка.
#  Ответ: путь новой пустой папки или '' — тогда файла не будет вовсе (отказ).
# --------------------------------------------------------------------------- #
function New-PrivateWorkDir {
    param([string]$Prefix)
    $leaf = $Prefix + [guid]::NewGuid().ToString('N')
    if (-not (Test-Admin)) {
        $dir = Join-Path ([IO.Path]::GetTempPath()) $leaf
        if (Test-Path -LiteralPath $dir) { return '' }
        try { $null = [IO.Directory]::CreateDirectory($dir) } catch { return '' }
        return $dir
    }
    $bases = New-Object System.Collections.Generic.List[string]
    if ($script:SafeRoot -and (Test-Path -LiteralPath $script:SafeRoot -PathType Container) -and (Test-PathTrusted $script:SafeRoot)) { $bases.Add($script:SafeRoot) }
    $sysTemp = Join-Path $env:SystemRoot 'Temp'
    if ((Test-Path -LiteralPath $sysTemp -PathType Container) -and (Test-DirChainSecure $sysTemp)) { $bases.Add($sysTemp) }
    foreach ($b in $bases.ToArray()) {
        Remove-StalePrivateDirs $b $Prefix
        $dir = Join-Path $b $leaf
        if (Test-Path -LiteralPath $dir) { continue }
        $sec = New-Object System.Security.AccessControl.DirectorySecurity
        $sec.SetAccessRuleProtection($true, $false)
        $inh = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
            $sec.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', $inh, 'None', 'Allow')))
        }
        $sec.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
        try { $null = [IO.Directory]::CreateDirectory($dir, $sec) } catch { continue }
        $ok = $false
        try {
            $it = Get-Item -LiteralPath $dir -Force -ErrorAction Stop
            $ok = (Test-ItemTrusted $it) -and (@(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop).Count -eq 0)
        } catch { $ok = $false }
        if ($ok) { return $dir }
        # Не прошла проверку. Свою (владелец доверенный) — убираем; чужую не
        # трогаем: по ссылкам Remove-TreeNoFollow не ходит, а чужое не удаляет.
        $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
        Remove-TreeNoFollow $dir $st -TrustedOwnerOnly
    }
    return ''
}

# Личные рабочие папки, оставшиеся от оборванного запуска, — через час.
# Только с доверенным владельцем и не ссылки: в Windows\Temp папку с таким
# же началом имени мог завести кто угодно.
function Remove-StalePrivateDirs {
    param([string]$Base, [string]$Prefix)
    $cut = (Get-Date).AddHours(-1)
    foreach ($d in @(Get-ChildItem -LiteralPath $Base -Directory -Force -Filter ($Prefix + '*') -ErrorAction SilentlyContinue)) {
        if ($d.LastWriteTime -gt $cut -or ($d.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
        Remove-TreeNoFollow $d.FullName $st -TrustedOwnerOnly
    }
}

# Файл из личной рабочей папки: в папке — ровно он один, это обычный файл (не
# ссылка и не папка), его владелец — система или администраторы (у
# повышенного движка), он не больше $MaxBytes и появился не раньше $Since.
# Читается один раз, открытым без права записи для других. Иначе — $null:
# такому файлу не верят, а не читают «что есть».
function Read-PrivateWorkFile {
    param([string]$Dir, [string]$Name, [datetime]$Since = [datetime]::MinValue, [int]$MaxBytes = 4194304)
    try {
        $all = @(Get-ChildItem -LiteralPath $Dir -Force -ErrorAction Stop)
        if ($all.Count -ne 1 -or $all[0].Name -cne $Name -or $all[0].PSIsContainer) { return $null }
        $it = $all[0]
        if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $null }
        if ($it.Length -gt $MaxBytes) { return $null }
        if ($it.CreationTimeUtc -lt $Since.ToUniversalTime()) { return $null }
        if ((Test-Admin) -and $script:TrustedSids -notcontains (Get-OwnerSid $it.FullName)) { return $null }
        $fs = [IO.File]::Open($it.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            $ms = New-Object System.IO.MemoryStream
            $fs.CopyTo($ms)
            return $ms.ToArray()
        } finally { $fs.Dispose() }
    } catch { return $null }
}

# Личная рабочая папка — прочь, обходом без ссылок
function Remove-PrivateWorkDir {
    param([string]$Dir)
    if (-not $Dir) { return }
    $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
    Remove-TreeNoFollow $Dir $st
}

# Переносимая папка данных лежит рядом с exe, и права ей достаются от папки
# exe. Окну этого достаточно: кто может писать в эту папку, может подменить и
# сам exe, который человек запускает. Но страж и наблюдение — задачи
# планировщика: они сами, без человека, запускают защищённую копию движка с
# правами администратора и читают эту папку. Раньше она считалась доверенной
# без проверки — подложенный журнал или ссылка на месте папки сработали бы с
# правами администратора. Задачам переносимая папка годится, только если
# подменить её нельзя: том с правами доступа, путь до неё закрыт от записи
# (как Program Files), а сама она закрыта так же, как ProgramData\Win11Privacy.
function Test-PortableTaskTrust {
    if ($null -eq $script:PortableTaskState) {
        $script:PortableTaskState = [bool]((Test-AclVolume $script:DataDir) -and
                                           (Test-DirChainSecure (Split-Path $script:DataDir -Parent)) -and
                                           (Protect-DataRoot $script:DataDir))
    }
    return $script:PortableTaskState
}

# Журнал читается и пишется только из защищённой папки.
function Test-DataTrusted {
    if ($script:DataDir -eq $script:SafeRoot) { return (Assert-SafeRoot) }
    if ($script:TaskRun) { return (Test-PortableTaskTrust) }
    return $true
}

function Ensure-DataDir {
    if (-not (Test-DataTrusted)) { throw 'папка данных программы не защищена от подмены' }
    if (-not (Test-Path -LiteralPath $script:DataDir)) { New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null }
}

# -DataRoot — только переносимая папка Win11Privacy-Data (так её называет
# окно рядом с exe, так она описана в README), по полному пути. В папку
# данных программа пишет файлы с обычными именами (profile.json), меняет её
# права, откладывает «чужое» в карантин, а по -PurgeData и при полном откате
# стирает свои файлы. -DataRoot, по ошибке указывающий на «Документы», папку
# программы или корень диска, затёр бы или стёр там чужое.
function Test-DataRootAllowed {
    param([string]$Path)
    try {
        if (-not [IO.Path]::IsPathRooted($Path)) { return $false }
        $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
        return ([IO.Path]::GetFileName($full) -ieq 'Win11Privacy-Data')
    } catch { return $false }
}

if ($DataRoot -and -not (Test-DataRootAllowed $DataRoot)) {
    Write-Log ("[!] -DataRoot ""{0}"": папкой данных может быть только папка Win11Privacy-Data, по полному пути (например, D:\Win11Privacy\Win11Privacy-Data). В другой папке программа ничего не пишет и не удаляет." -f $DataRoot)
    Write-Log '###DONE###'
    exit 1
}

# Задача планировщика данным из папки, которую можно подменить, не верит и
# ничего не делает.
if ($script:TaskRun -and -not (Test-DataTrusted)) { exit 1 }

# Копия движка для задач планировщика: всегда в защищённом корне, пишется
# рядом и подменяет прежнюю одним движением, а перед этим сверяется с
# оригиналом по SHA-256.
function Install-TaskEngine {
    if (-not (Assert-SafeRoot)) { throw 'папка ProgramData\Win11Privacy не защищена — копию движка для задач туда класть нельзя' }
    $dst = $script:TaskEngine
    if ($PSCommandPath -ne $dst) {
        $tmp = $dst + '.new'
        Copy-Item -LiteralPath $PSCommandPath -Destination $tmp -Force -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            throw 'копия движка для задач не совпала с оригиналом'
        }
        Move-Item -LiteralPath $tmp -Destination $dst -Force -ErrorAction Stop
        # прежние версии в переносимом режиме клали копию рядом с данными
        if ($script:DataDir -ne $script:SafeRoot) { Remove-Item -LiteralPath (Join-Path $script:DataDir 'engine.ps1') -Force -ErrorAction SilentlyContinue }
    }
    # Переносимую папку проверяем после того, как копия обновлена: задачи,
    # поставленные прежними версиями, запускают именно её — и теперь сами
    # откажутся работать с папкой, которую можно подменить. Новую задачу на
    # такой папке не ставим: задача, которая потом молча не работает, хуже
    # честного отказа сейчас.
    if ($script:DataDir -ne $script:SafeRoot -and -not (Test-PortableTaskTrust)) {
        throw (('переносимую папку программы ({0}) может подменить любая программа пользователя, а страж и наблюдение работают с правами администратора сами по себе. ' +
                'В переносимом режиме они ставятся, только если программа лежит в защищённой папке на диске NTFS — например, в Program Files.') -f $script:DataDir)
    }
    return $dst
}

# Файл пишется рядом и подменяет прежний одним движением: обрыв на середине
# записи (выключили питание, прервали движок) не оставит от журнала отката
# половину — а журнал единственный путь назад.
#
# Файлы данных читают и другие запуски (окно, страж), и антивирус. Замене
# одним действием мешает тот, кто держит файл открытым без права на удаление:
# раньше первая же такая встреча давала «журнал отката не записался», и
# применение останавливалось. Теперь замена ждёт и пробует снова; сами мы
# читаем с правом на удаление (Read-TextShared) и чужую замену не держим.
function Save-Json {
    param([string]$Name, $Object)
    Ensure-DataDir
    $path = Join-Path $script:DataDir $Name
    $tmp = $path + '.tmp'
    ($Object | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $tmp -Encoding UTF8 -ErrorAction Stop
    # Замена одним действием системы (ReplaceFile). Move-Item -Force делал
    # «удалить старый, переименовать новый» — между ними журнала не было
    # вовсе, и обрыв в этот миг оставлял программу без пути назад.
    Replace-FileAtomic $tmp $path
}

# Готовый файл $Tmp встаёт на место $Path одним действием системы
# (ReplaceFile: права и атрибуты прежнего файла сохраняются; файла ещё нет —
# переименование). Держит кто-то другой (антивирус, чужое чтение без права
# на удаление) — ждём и пробуем снова, до трёх секунд.
function Replace-FileAtomic {
    param([string]$Tmp, [string]$Path)
    for ($try = 1; ; $try++) {
        $busy = $false
        try {
            if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($Tmp, $Path, [NullString]::Value) }
            else { [IO.File]::Move($Tmp, $Path) }
            return
        } catch {
            # Вид ошибки — по самому исключению .NET (см. Test-IoBusy). Любая
            # ошибка ввода-вывода — повтор, как и раньше: файл на месте мог
            # появиться или пропасть между проверкой и заменой (Test-Path
            # смотрится заново).
            if (-not ($_.Exception.GetBaseException() -is [System.IO.IOException]) -or $try -ge 30) { throw }
            $busy = $true
        }
        if ($busy) { Start-Sleep -Milliseconds 100 }
    }
}

# Вид ошибки ввода-вывода — по самому исключению .NET, а не по фильтру
# catch [тип] (T-4). Windows PowerShell 5.1 в цикле с ожиданием начинал (на
# 18-м проходе, проверено) отдавать «файл занят другим процессом» —
# IOException, обёрнутую в MethodInvocationException, — ветке
# catch [DirectoryNotFoundException]: Read-TextShared отвечал «файла нет», и
# занятый журнал отката читался как отсутствующий. Любая программа
# пользователя может открыть журнал на чтение (права корня — «Пользователи:
# чтение») без совместного доступа и так подменить повышенному движку «журнал
# пуст»: откат сказал бы «возвращать нечего», а следующая запись затёрла бы
# историю «как было».
#   Test-IoMissing — файла или папки нет; Test-IoBusy — занят (повторить можно).
function Test-IoMissing {
    param($Exception)
    $ex = $Exception.GetBaseException()
    return ($ex -is [System.IO.FileNotFoundException] -or $ex -is [System.IO.DirectoryNotFoundException])
}
function Test-IoBusy {
    param($Exception)
    $ex = $Exception.GetBaseException()
    return ($ex -is [System.IO.IOException] -and -not (Test-IoMissing $Exception))
}

# Текст файла данных. Открывается с правом на чтение, запись и удаление для
# других: замена файла другим запуском (ReplaceFile) не упрётся в нас, а мы
# прочитаем либо прежний файл, либо новый — целиком. Занят без права на
# чтение (антивирус) — ждём и пробуем снова; не вышло — ошибка, а не «пусто».
# Файла нет — $null. Вид ошибки — Test-IoMissing / Test-IoBusy (T-4).
function Read-TextShared {
    param([string]$Path)
    for ($try = 1; ; $try++) {
        $busy = $false
        try {
            $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
                                         ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            try {
                $sr = New-Object System.IO.StreamReader($fs, (New-Object System.Text.UTF8Encoding $false), $true)
                return $sr.ReadToEnd()
            } finally { $fs.Dispose() }
        } catch {
            if (Test-IoMissing $_.Exception) { return $null }
            if (-not (Test-IoBusy $_.Exception) -or $try -ge 30) { throw }
            $busy = $true
        }
        if ($busy) { Start-Sleep -Milliseconds 100 }
    }
}
# --- Резервная копия и точка восстановления --------------------------------- #
#  Делаются не «на всякий случай» при каждом запуске, а ровно перед первым
#  настоящим изменением. Если всё уже настроено, на рабочем столе не появится
#  очередная пустая папка, а система не потратит минуту на точку отката.
$script:BackupDir = ''
$script:BackupTried = $false
# Копию и точку восстановления делает только ручное применение. Страж чинит
# сбитые настройки сам по расписанию — ему незачем сорить папками на рабочем
# столе и тратить минуту на точку отката при каждой мелкой правке.
$script:BackupEnabled = $false

# reg.exe напрямую, по полному пути, без cmd.exe: вывод читается, но не
# превращается в ошибки PowerShell. Ответ — код выхода и текст ошибки
# (code = -1 — не запустился или не уложился во время).
function Invoke-RegExe {
    param([string]$Arguments, [int]$TimeoutMs = 300000)
    $p = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = Join-Path $env:SystemRoot 'System32\reg.exe'
        $psi.Arguments = $Arguments
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        # Оба потока — асинхронно: синхронное чтение ждало бы конца процесса,
        # и ограничение по времени ниже не сработало бы никогда.
        $errText = $p.StandardError.ReadToEndAsync()
        $null = $p.StandardOutput.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutMs)) { try { $p.Kill() } catch { }; return @{ code = -1; error = 'reg.exe не закончил за отведённое время' } }
        return @{ code = $p.ExitCode; error = ("$($errText.Result)" -replace '\s+', ' ').Trim() }
    } catch { return @{ code = -1; error = $_.Exception.Message } }
    finally { if ($null -ne $p) { $p.Dispose() } }
}

# Подпись файла резервной копии — тем же ключом, что и журнал отката
# (HMAC-SHA256), с отдельной приставкой: подпись журнала за подпись файла не
# сойдёт. В подпись входят имя папки копии и имя файла: файл из другой копии
# или под другим именем не подойдёт. Подписываются ровно те байты, что будут
# записаны или импортированы (W11P-001): не файл по имени, который можно
# подменить между чтением и подписью, а уже прочитанное в память содержимое.
function Get-BackupBytesSig {
    param([byte[]]$Bytes, [string]$Folder, [string]$Name, [switch]$Create)
    $h = [System.Security.Cryptography.HMACSHA256]::new([byte[]](Get-SignKey -Create:$Create))
    try {
        $head = [Text.Encoding]::UTF8.GetBytes(('w11p-backup|{0}|{1}|' -f $Folder.ToLowerInvariant(), $Name.ToLowerInvariant()))
        $null = $h.TransformBlock($head, 0, $head.Length, $null, 0)
        $null = $h.TransformFinalBlock($Bytes, 0, $Bytes.Length)
        return (($h.Hash | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally { $h.Dispose() }
}

# --------------------------------------------------------------------------- #
#  Подписанный список файлов копии (backup-sig.json, версия 2). В версии 1
#  был только список «файл -> подпись»: удалив из него строку вместе с файлом,
#  можно было незаметно сократить копию. Теперь у списка своя подпись (тем же
#  ключом, с отдельной приставкой): в неё входят имя папки и все пары
#  «файл:подпись». Поле files осталось тем же — прежние версии программы
#  такую копию тоже читают.
# --------------------------------------------------------------------------- #
$script:BackupManifestName = 'backup-sig.json'
# Имена файлов копии — путь ветки, где «:», «\» и пробелы заменены на «_»
$script:BackupFileRx = '^[A-Za-z0-9_.(){}+-]{1,200}\.reg$'

function Get-BackupManifestSig {
    param([string]$Folder, [hashtable]$Files, [switch]$Create)
    $lines = @($Files.Keys | ForEach-Object { ([string]$_).ToLowerInvariant() + ':' + ([string]$Files[$_]).ToLowerInvariant() } | Sort-Object)
    $text = 'w11p-backup-manifest|' + $Folder.ToLowerInvariant() + '|' + ($lines -join "`n")
    $h = [System.Security.Cryptography.HMACSHA256]::new([byte[]](Get-SignKey -Create:$Create))
    try {
        $b = [Text.Encoding]::UTF8.GetBytes($text)
        return (($h.ComputeHash($b) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally { $h.Dispose() }
}

# Текст списка: только ASCII, ключи по порядку — его читает строгий разбор
# (ConvertFrom-EngineRequest), который отвергает повторы полей
function ConvertTo-BackupManifestText {
    param([string]$Folder, [hashtable]$Files, [string]$Sig)
    $parts = @($Files.Keys | Sort-Object | ForEach-Object { '"' + $_ + '":"' + $Files[$_] + '"' })
    return ('{"version":2,"folder":"' + $Folder + '","files":{' + ($parts -join ',') + '},"sig":"' + $Sig + '"}')
}

# Рабочие папки внутри защищённого корня, оставшиеся от оборванных запусков
# (backup-*, restore-*): удаляются через час, обходом без ссылок
function Remove-StaleWorkDirs {
    param([string]$Prefix)
    if (-not $script:SafeRoot -or -not (Test-Path -LiteralPath $script:SafeRoot)) { return }
    $cut = (Get-Date).AddHours(-1)
    foreach ($d in @(Get-ChildItem -LiteralPath $script:SafeRoot -Directory -Force -Filter ($Prefix + '*') -ErrorAction SilentlyContinue)) {
        if ($d.LastWriteTime -gt $cut) { continue }
        $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
        Remove-TreeNoFollow $d.FullName $st
    }
}

# Новая пустая рабочая папка внутри защищённого корня: имя со случайным
# хвостом, не ссылка, владелец — система или администраторы, чужим не открыта
# на запись. Не вышло — исключение: работать с копией негде.
function New-SafeWorkDir {
    param([string]$Prefix)
    if (-not (Assert-SafeRoot)) { throw 'папка ProgramData\Win11Privacy не защищена' }
    $dir = Join-Path $script:SafeRoot ($Prefix + [guid]::NewGuid().ToString('N').Substring(0, 12))
    if (Test-Path -LiteralPath $dir) { throw 'рабочая папка уже есть' }
    $null = [IO.Directory]::CreateDirectory($dir)
    $item = Get-Item -LiteralPath $dir -Force
    if (-not (Test-ItemTrusted $item)) {
        $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
        Remove-TreeNoFollow $dir $st
        throw 'рабочая папка не защищена (ссылка или чужие права)'
    }
    return $dir
}

# --------------------------------------------------------------------------- #
#  Резервная копия веток реестра (W11P-001, W11P-005). Раньше reg.exe
#  выгружал ветки прямо в папку на рабочем столе, куда пишет любая программа
#  пользователя, а подпись снималась с файла уже там: между выгрузкой и
#  подписью файл можно было подменить; к тому же движок с правами
#  администратора писал по пути, где пользователь мог подложить ссылку.
#  Теперь движок с этими правами не пишет в папки пользователя вовсе:
#    1. ветки выгружаются в рабочую папку внутри защищённого корня
#       ProgramData\Win11Privacy (пишут только система и администраторы,
#       путь до корня проверен целиком — Assert-SafeRoot);
#    2. каждый файл читается один раз в память, проверяется (Test-RegExportFile)
#       и подписывается ровно этими байтами; рядом — подписанный список;
#    3. готовая подписанная копия одним переименованием (тот же том, тот же
#       корень) становится копией в хранилище ProgramData\Win11Privacy\backups —
#       менять её могут только администраторы, обычные программы только читают.
#  Копия на рабочий стол больше не кладётся: вернуть копию можно из окна
#  («Изменения» -> «Из резервной копии»), а папку хранилища открывает пункт
#  «Открыть папку резервных копий». Копии прежних версий на рабочем столе и
#  в -BackupRoot по-прежнему видны в списке и возвращаются после проверки.
#  Оборванный запуск оставляет рабочую папку только внутри защищённого корня
#  (её уберёт следующий); в хранилище копия появляется только целиком.
# --------------------------------------------------------------------------- #
$script:BackupStoreKeep = 20

function Get-BackupStoreDir { return (Join-Path $script:SafeRoot 'backups') }

# Старые копии в хранилище: остаются самая первая (состояние до программы —
# самое ценное) и $BackupStoreKeep последних. Имя папки начинается с даты —
# порядок по имени и есть порядок по времени.
function Limit-BackupStore {
    $store = Get-BackupStoreDir
    $all = @(Get-ChildItem -LiteralPath $store -Directory -Force -Filter 'Win11Privacy-Backup-*' -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($all.Count -le ($script:BackupStoreKeep + 1)) { return }
    foreach ($old in @($all[1..($all.Count - $script:BackupStoreKeep - 1)])) {
        $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
        Remove-TreeNoFollow $old.FullName $st
    }
}

function New-RegBackup {
    param([string[]]$Keys)
    $res = @{ dir = ''; saved = 0; signed = 0; missed = @(); error = '' }
    Remove-StaleWorkDirs 'backup-'
    $leaf = 'Win11Privacy-Backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
    $stage = $null
    try {
        $stage = New-SafeWorkDir 'backup-'
        # хранилище — внутри того же защищённого корня: перенос в него — одно
        # переименование на одном томе
        $store = Get-BackupStoreDir
        if (-not (Test-Path -LiteralPath $store)) { $null = [IO.Directory]::CreateDirectory($store) }
        if (-not (Test-ItemTrusted (Get-Item -LiteralPath $store -Force))) { throw 'хранилище копий не защищено (ссылка или чужие права)' }
        $final = Join-Path $store $leaf
        if (Test-Path -LiteralPath $final) { throw 'копия с таким именем уже есть' }
        $sigs = @{}
        foreach ($k in $Keys) {
            if (-not (Test-Path -LiteralPath $k)) { continue }
            $native = $k -replace '^HKLM:\\','HKLM\' -replace '^HKCU:\\','HKCU\'
            $name = (($k -replace '[:\\ ]','_')) + '.reg'
            if ($name -cnotmatch $script:BackupFileRx -or $sigs.ContainsKey($name)) { $res.missed += ("{0} -- имя файла копии не годится или повторяется" -f $k); continue }
            $file = Join-Path $stage $name
            # Считаем только то, что выгрузилось целиком (см. Export-RegKey).
            # Недописанный файл удаляется: восстановить из него нельзя.
            $why = Export-RegKey $native $file
            if ($why) {
                Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
                $res.missed += ("{0} -- {1}" -f $k, $why)
                continue
            }
            # Один раз в память: проверяются и подписываются одни и те же байты
            # (рабочая папка закрыта для чужой записи — эти байты и остаются в файле)
            $bytes = [IO.File]::ReadAllBytes($file)
            $sigs[$name] = Get-BackupBytesSig $bytes $leaf $name -Create
            $res.saved++
        }
        if ($res.saved -eq 0) { return $res }
        $msig = Get-BackupManifestSig $leaf $sigs -Create
        [IO.File]::WriteAllBytes((Join-Path $stage $script:BackupManifestName), [Text.Encoding]::ASCII.GetBytes((ConvertTo-BackupManifestText $leaf $sigs $msig)))
        $res.signed = $sigs.Count
        # Готовая копия — в хранилище одним действием
        [IO.Directory]::Move($stage, $final)
        $stage = $null
        $res.dir = $final
        Limit-BackupStore
    } catch { $res.error = $_.Exception.Message }
    finally {
        if ($stage -and (Test-Path -LiteralPath $stage)) {
            $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
            Remove-TreeNoFollow $stage $st
        }
    }
    return $res
}

# Выгружает ветку реестра в .reg и проверяет, что выгрузилась: reg.exe
# закончил с кодом 0, а файл начинается с заголовка, который понимает импорт.
# Раньше успехом считалось само появление файла — а reg.exe, упавший на
# середине, оставляет недописанный. Пустая строка — выгрузилось, иначе — почему нет.
function Export-RegKey {
    param([string]$Key, [string]$File)
    # в пути ветки и файла кавычек не бывает; обратная косая в конце
    # экранировала бы закрывающую кавычку — её убираем
    $r = Invoke-RegExe ('export "{0}" "{1}" /y' -f $Key.TrimEnd('\'), $File)
    if ($r.code -eq -1) { return $r.error }
    if ($r.code -ne 0) { return ("reg.exe, код {0}: {1}" -f $r.code, $r.error) }
    if (-not (Test-Path -LiteralPath $File)) { return 'reg.exe закончил без ошибки, но файла нет' }
    return (Test-RegExportFile $File $Key)
}

# Выгрузка целая: UTF-16 с меткой FF FE и чётной длиной, заголовок, сразу за
# ним — сама выгруженная ветка, а в конце — пустая строка, которой reg.exe
# заканчивает каждую запись. Файл, оборванный посередине записи, не пройдёт.
# Пустая строка — целая, иначе — почему нет.
function Test-RegExportFile {
    param([string]$File, [string]$Key)
    try { $b = [IO.File]::ReadAllBytes($File) } catch { return ("файл не читается: {0}" -f $_.Exception.Message) }
    if ($b.Length -lt 4 -or $b[0] -ne 0xFF -or $b[1] -ne 0xFE -or ($b.Length % 2) -ne 0) { return 'файл не в том виде, в каком его пишет reg.exe (UTF-16)' }
    $t = [Text.Encoding]::Unicode.GetString($b, 2, $b.Length - 2)
    $full = ($Key.TrimEnd('\') -replace '^HKLM\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKCU\\', 'HKEY_CURRENT_USER\')
    $start = "Windows Registry Editor Version 5.00`r`n`r`n[" + $full + "]`r`n"
    if (-not $t.StartsWith($start, [StringComparison]::OrdinalIgnoreCase)) { return 'в начале файла нет заголовка выгрузки и самой ветки' }
    if (-not $t.EndsWith("`r`n`r`n")) { return 'файл оборван: последняя запись не закончена' }
    return ''
}

function Ensure-Backup {
    if (-not $script:BackupEnabled -or $script:BackupTried -or $DryRun) { return }
    $script:BackupTried = $true

    if (-not $NoBackup) {
        Write-Section 'Резервная копия реестра'
        $keys = @($script:Defs | Where-Object { $script:RegTypes -contains $_.T -and $Modules -contains $_.M } | ForEach-Object { $_.P } | Select-Object -Unique)
        # Выгрузка, проверка и подпись — в защищённой рабочей папке, затем
        # готовая подписанная копия — в хранилище программы (New-RegBackup)
        $bk = New-RegBackup $keys
        if ($bk.dir) {
            $script:BackupDir = $bk.dir
            Write-Log ("   [+] сохранено веток: {0} -> {1}" -f $bk.saved, $bk.dir)
            Write-Log '   [i] вернуть копию: «Изменения» -> «Из резервной копии»'
        } elseif ($bk.error) {
            Write-Log "   [!] не удалось создать резервную копию: $($bk.error)"
        } else {
            Write-Log '   [-] сохранять нечего: ни одна ветка не выгрузилась'
        }
        if ($bk.missed.Count -gt 0) {
            Write-Log ("   [-] не выгрузились ветки: {0} (обычно Windows не отдаёт их даже на чтение; почему -- в каждой строке)" -f $bk.missed.Count)
            foreach ($k in $bk.missed) { Write-Log ("       {0}" -f $k) }
        }
    }

    if (-not $NoRestorePoint) {
        Write-Section 'Точка восстановления системы'
        # Чтобы Windows не отказала «точка уже была сегодня», частота создания
        # точек на время ставится в 0. Раньше так и оставалась — системная
        # настройка менялась навсегда и мимо журнала. Теперь возвращается.
        $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $srOld = Get-RegValue $srKey 'SystemRestorePointCreationFrequency'
        try {
            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
            New-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
            Checkpoint-Computer -Description 'Win11Privacy: до изменений' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
            Write-Log '   [+] точка восстановления создана'
        } catch { Write-Log "   [!] точку восстановления создать не удалось: $($_.Exception.Message)" }
        finally {
            try {
                if ($null -ne $srOld) { New-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -Value $srOld -PropertyType DWord -Force -ErrorAction Stop | Out-Null }
                else { Remove-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -Force -ErrorAction SilentlyContinue }
            } catch { Write-Log "   [!] частота точек восстановления не вернулась: $($_.Exception.Message)"; $script:Failures++ }
        }
    }
}

# Журнал отката сбрасывается на диск по ходу работы: раньше он писался
# единственный раз в самом конце, и обрыв прогона (закрыли окно, выключили
# питание) оставлял изменения в системе, а вернуть их было нечем.
# Журнал читается и переписывается целиком, поэтому два одновременно
# работающих экземпляра затирали правки друг друга — а журнал единственный
# путь назад. Общесистемный замок делает запись неделимой.
# Не дождались замка — не пишем вовсе: раньше после 10 секунд ожидания тело
# выполнялось без замка, и два запуска снова затирали друг другу журнал.
#
# Замок — файл journal.lock в защищённом корне ProgramData\Win11Privacy,
# открытый без совместного доступа. Раньше это был именованный мьютекс
# Global\Win11Privacy-Journal, а его может создать и держать любой процесс,
# даже от имени службы без прав: пока он держал, не работали ни применение,
# ни откат (проверено на VM). У файла права только для системы и
# администраторов — ни на запись, ни на чтение, — так что занять его без прав
# администратора нельзя ни как, в том числе открыв «просто на чтение».
# Процесс завершился, не отпустив замок, — Windows закрывает файл сама.
# Замок повторно входимый: запись, которая читает журнал под замком, не ждёт
# сама себя.
$script:JournalLockDepth = 0
function Get-JournalLockPath { return (Join-Path $script:SafeRoot 'journal.lock') }

function Open-JournalLockFile {
    # -Path — другой замок того же устройства (замок операции, см. Enter-OpLock)
    param([string]$Path = '')
    $p = $(if ($Path) { $Path } else { Get-JournalLockPath })
    $dir = Split-Path $p -Parent
    if (Test-Admin) {
        # Корень заводится и проверяется до замка: корень, который успел
        # завести кто-то другой, отложен в сторону вместе с его «замком»
        if (-not (Assert-SafeRoot)) { throw 'папка ProgramData\Win11Privacy не защищена от подмены — замка журнала отката нет' }
    } elseif (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        # заводить корень без прав администратора нельзя: он был бы ничей
        throw (New-Object System.UnauthorizedAccessException 'защищённой папки программы нет, а завести её может только администратор')
    }
    # ссылка на месте замка увела бы его открытие в чужой файл
    if ((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'на месте замка журнала лежит ссылка'
    }
    if (-not (Test-Admin)) {
        # без прав администратора замок не взять: файл закрыт и на запись, и
        # на чтение (см. ниже), открытие кончится отказом в доступе
        return [IO.File]::Open($p, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    }
    # Права замка — только система и администраторы, на чтение тоже, и
    # задаются при создании файла. Унаследованные от папки данных права
    # («Пользователи: чтение») позволили бы любому процессу открыть замок на
    # чтение без совместного доступа и держать: тогда ни применение, ни откат
    # не получили бы замок — тот же отказ в работе, что был у общего мьютекса.
    $sec = New-Object System.Security.AccessControl.FileSecurity
    $sec.SetAccessRuleProtection($true, $false)
    foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
        $sec.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', 'Allow')))
    }
    $sec.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    # права открытия включают смену прав и владельца: ими исправляется замок,
    # оставшийся с широкими правами (SetAccessControl на открытом дескрипторе)
    $fs = New-Object System.IO.FileStream($p, [IO.FileMode]::OpenOrCreate,
                                          ([Security.AccessControl.FileSystemRights]'ReadData, WriteData, ReadPermissions, ChangePermissions, TakeOwnership'),
                                          [IO.FileShare]::None, 4096, [IO.FileOptions]::None, $sec)
    # замок, оставшийся с более широкими правами (создан до этой защиты),
    # исправляется, пока он у нас в руках
    if (-not (Test-KeyFileSecure $p)) {
        try { $fs.SetAccessControl($sec) } catch { $fs.Dispose(); throw }
    }
    return $fs
}

function Use-JournalLock {
    param([scriptblock]$Body)
    if ($script:JournalLockDepth -gt 0) {
        $script:JournalLockDepth++
        try { & $Body } finally { $script:JournalLockDepth-- }
        return
    }
    $fs = $null
    $until = (Get-Date).AddMilliseconds([double]$script:JournalLockTries * [double]$script:JournalLockWaitMs)
    while ($null -eq $fs) {
        $busy = $false
        try { $fs = Open-JournalLockFile }
        catch {
            # Вид ошибки — по самому исключению .NET, а не по фильтру catch
            # [тип]: в этом цикле Windows PowerShell 5.1 отдавал ошибки не той
            # ветке (T-4, см. Test-IoBusy)
            $ex = $_.Exception.GetBaseException()
            if ($ex -is [System.UnauthorizedAccessException]) {
                throw (New-Object System.UnauthorizedAccessException 'замок журнала отката открывается только с правами администратора')
            }
            if (-not ($ex -is [System.IO.IOException])) { throw }
            # занят другим запуском (или антивирус проверяет файл) — ждём
            if ((Get-Date) -ge $until) { throw 'журнал отката занят другим запуском программы' }
            $busy = $true
        }
        if ($busy) { Start-Sleep -Milliseconds 200 }
    }
    $script:JournalLockDepth = 1
    try { & $Body }
    finally {
        $script:JournalLockDepth = 0
        try { $fs.Dispose() } catch { }
    }
}

# Журнал на диске. Повреждённый файл не затирается молча новыми записями —
# раньше Load-Json возвращал пустоту, и вся история «как было» терялась при
# следующей же записи. Теперь он откладывается рядом под своим именем.
#  Журнал отката — готовая инструкция для администратора: какие значения
#  записать в реестр, какие службы, задачи и автозагрузку вернуть. В
#  переносимом режиме он лежит рядом с exe, куда может писать любая программа
#  пользователя, — и дописанная туда запись (скажем, своя программа в
#  автозагрузке всех пользователей) выполнилась бы при следующем откате с
#  правами администратора. Поэтому журнал подписывается HMAC-SHA256. Ключ
#  лежит в ProgramData\Win11Privacy, и читать его могут только система и
#  администраторы: без него подпись не подделать.
function Test-KeyFileSecure {
    param([string]$Path)
    try {
        $it = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        if ($script:TrustedSids -notcontains $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value) { return $false }
        if (-not $acl.AreAccessRulesProtected) { return $false }
        # даже читать — только своим
        foreach ($r in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ("$($r.AccessControlType)" -ne 'Allow') { continue }
            if ($script:TrustedSids -notcontains $r.IdentityReference.Value) { return $false }
        }
        return $true
    } catch { return $false }
}

# Ключ заводится (или заменяется испорченный) только при записи журнала,
# -Create. Проверка подписи ключ лишь читает: завести новый при проверке —
# значит наверняка «не сойтись» с журналом, подписанным прежним, и молча
# лишить человека отката. Без ключа журнал просто непроверяем.
function Get-SignKey {
    param([switch]$Create)
    if ($null -ne $script:SignKey) { return $script:SignKey }
    if (-not (Assert-SafeRoot)) { throw 'папка ProgramData\Win11Privacy не защищена — ключа подписи журнала нет' }
    $p = $script:SignKeyFile
    if (Test-Path -LiteralPath $p) {
        $b = $null
        if (Test-KeyFileSecure $p) { try { $b = [IO.File]::ReadAllBytes($p) } catch { $b = $null } }
        if ($null -ne $b -and $b.Length -eq 32) { $script:SignKey = $b; return $b }
        if (-not $Create) { throw 'ключ подписи журнала испорчен или открыт не только администраторам' }
        if (-not (Test-Admin)) { throw 'ключ подписи журнала недоступен' }
        # ключ мог прочитать кто-то чужой — он больше ничего не доказывает
        Move-Item -LiteralPath $p -Destination ($p + '.untrusted-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force -ErrorAction Stop
        Write-Log '   [!] ключ подписи журнала был открыт не только администраторам или повреждён -- он заменён новым'
    }
    if (-not $Create) { throw 'ключа подписи журнала нет' }
    if (-not (Test-Admin)) { throw 'ключа подписи журнала нет, а создать его можно только с правами администратора' }
    $b = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($b) } finally { $rng.Dispose() }
    # права — сразу при создании файла: между созданием и сменой прав ключ
    # успели бы прочитать
    $sec = New-Object System.Security.AccessControl.FileSecurity
    $sec.SetAccessRuleProtection($true, $false)
    foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
        $sec.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', 'Allow')))
    }
    $sec.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    $fs = [IO.File]::Create($p, 64, [IO.FileOptions]::WriteThrough, $sec)
    try { $fs.Write($b, 0, $b.Length) } finally { $fs.Dispose() }
    $script:SignKey = $b
    return $b
}

# Подпись — по тексту, который даёт разбор самого файла: у хэш-таблиц и у
# прочитанных из файла объектов поля идут в разном порядке.
function Get-JournalSig {
    param($Items, [bool]$Legacy, [switch]$ForWrite)
    $canon = ('w11p-journal|{0}|' -f [int]$Legacy) + (ConvertTo-Json -InputObject @($Items) -Depth 8 -Compress)
    $h = [System.Security.Cryptography.HMACSHA256]::new([byte[]](Get-SignKey -Create:$ForWrite))
    try { return (($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($canon)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $h.Dispose() }
}

# Запись журнала прежней версии без подписи, которой можно верить и в
# переносимой папке: она про настройку самой программы — тот же параметр
# реестра, служба, задача или переменная среды, что в её списке. Запись про
# что-то другое (автозагрузка, чужие профили, произвольный ключ реестра)
# могли дописать, и без подписи её не возвращаем.
function Test-JournalEntryKnown {
    param($Entry)
    if ($null -eq $script:KnownJournal) {
        $k = @{}; $globs = New-Object System.Collections.Generic.List[string]
        foreach ($d in @($script:Defs)) {
            if ($null -eq $d) { continue }
            if ($script:RegTypes -contains $d.T) { $k[(Get-JournalKey @{ kind = 'reg'; path = $d.P; name = $d.N })] = $true }
            elseif ($d.T -in @('svc', 'svcopt')) { $k[(Get-JournalKey @{ kind = 'svc'; name = $d.P })] = $true }
            elseif ($d.T -eq 'task') { $k[(Get-JournalKey @{ kind = 'task'; path = $d.P })] = $true }
            elseif ($d.T -eq 'taskglob') { $globs.Add("$($d.P)") }
            elseif ($d.T -eq 'env') { $k[(Get-JournalKey @{ kind = 'env'; name = $d.P })] = $true }
            elseif ($d.T -in @('vscode', 'firefox')) { $k[(Get-JournalKey @{ kind = 'appcfg'; app = $d.T; name = $d.P })] = $true }
        }
        $k[(Get-JournalKey @{ kind = 'audit'; guid = $script:AuditGuid })] = $true
        $script:KnownJournal = $k; $script:KnownTaskGlobs = $globs.ToArray()
    }
    $f = ConvertTo-Fields $Entry
    $kind = "$($f['kind'])"
    if ($kind -notin @('reg', 'svc', 'task', 'env', 'audit', 'appcfg')) { return $false }
    if ($script:KnownJournal.ContainsKey((Get-JournalKey $f))) { return $true }
    if ($kind -eq 'task') {
        # по маске — только в её папках, а не любая задача с подходящим именем
        foreach ($g in $script:KnownTaskGlobs) { if (Test-TaskGlobPath "$($f['path'])" $g) { return $true } }
    }
    return $false
}

# -ReadOnly — для показа журнала: ничего не откладывать и не писать.
# Журнал читается под тем же замком, под которым его пишут: у подмены файла
# (ReplaceFile) есть миг, когда его нет под этим именем, и чтение без замка
# в этот миг видело «журнала нет» — откат сказал бы «возвращать нечего».
# Замок повторно входимый: запись, которая читает журнал под замком, не ждёт сама себя.
function Read-JournalFile {
    param([switch]$ReadOnly)
    $box = @{ r = $null }
    try { Use-JournalLock { $box.r = Read-JournalFileUnlocked -ReadOnly:$ReadOnly } }
    catch [System.UnauthorizedAccessException] {
        # Без прав администратора замок не взять. Показать журнал можно и
        # без него: чтение ничего не меняет, а миг подмены файла другим
        # запуском Read-JournalFileUnlocked пережидает сам.
        if ($ReadOnly) { return (Read-JournalFileUnlocked -ReadOnly) }
        return @{ items = @(); legacy = $false; exists = $true; signed = $false; trusted = $false; state = 'unreadable'; updated = ''; dropped = 0 }
    }
    catch {
        if (-not $ReadOnly) { Write-Log ("   [!] журнал отката сейчас не читается ({0}) -- файл не тронут, повторите позже" -f $_.Exception.Message) }
        return @{ items = @(); legacy = $false; exists = $true; signed = $false; trusted = $false; state = 'unreadable'; updated = ''; dropped = 0 }
    }
    return $box.r
}

function Read-JournalFileUnlocked {
    param([switch]$ReadOnly)
    # state: none — журнала нет; valid — ему можно верить; legacy — можно
    # верить, но он прежнего образца (не знает служб и задач); untrusted —
    # нельзя: повреждён, подпись не сошлась или её нечем проверить. Раньше
    # отложенный недоверенный журнал выглядел просто «отсутствующим», и
    # полный откат переходил к прежнему откату «по умолчанию».
    $p = Join-Path $script:DataDir 'changes.json'
    $res = @{ items = @(); legacy = $false; exists = $false; signed = $false; trusted = $true; state = 'none'; updated = ''; dropped = 0 }
    if (-not (Test-Path -LiteralPath $p)) { return $res }
    $res.exists = $true
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    # Недоверенный журнал откладывается рядом, а не затирается: следующая
    # запись иначе пошла бы поверх, и прочитать его потом было бы нечем.
    $setAside = {
        param([string]$Prefix, [string]$Why)
        $res.trusted = $false; $res.state = 'untrusted'
        if ($ReadOnly) { return }
        $bad = Join-Path $script:DataDir ($Prefix + $stamp + '.json')
        Move-Item -LiteralPath $p -Destination $bad -Force -ErrorAction Stop
        Write-Log ("   [!] {0} По нему ничего не возвращается; файл отложен как {1}" -f $Why, (Split-Path $bad -Leaf))
        $res.exists = $false
    }
    # Не прочитался (занят другим процессом) — это не повреждение и не «пусто».
    # Раньше ошибка чтения Get-Content не прерывала разбор: журнал выглядел
    # пустым и достоверным, и откат в этот миг сказал бы «возвращать нечего».
    # Файл был, а при открытии его нет: другой запуск как раз подменяет его
    # (у ReplaceFile есть миг без файла под этим именем). Это не «журнала нет»
    # — ждём и читаем снова; раньше такой миг читался как пустой журнал.
    $txt = $null
    for ($k = 1; $k -le 20; $k++) {
        try { $txt = Read-TextShared $p }
        catch {
            $res.trusted = $false; $res.state = 'unreadable'
            if (-not $ReadOnly) { Write-Log ("   [!] журнал отката сейчас не читается ({0}) -- файл не тронут, повторите позже" -f $_.Exception.Message) }
            return $res
        }
        if ($null -ne $txt) { break }
        Start-Sleep -Milliseconds 50
    }
    if ($null -eq $txt) { $res.exists = $false; return $res }      # и правда удалён
    $j = $null
    try { if ("$txt".Trim()) { $j = $txt | ConvertFrom-Json -ErrorAction Stop } } catch { $j = $null }
    if ($null -eq $j) {
        & $setAside 'changes.broken-' 'журнал отката повреждён.'
        return $res
    }
    $items = @()
    if ($j -and $j.PSObject.Properties['items'] -and $null -ne $j.items) { $items = @($j.items) }
    # Журнал прежних версий: в нём нет служб, задач и переменных среды. Пометка
    # остаётся с ним навсегда — полный откат для них ведёт себя по-старому.
    $res.legacy = [bool](($j.PSObject.Properties['legacy'] -and $j.legacy) -or
                         (-not $j.PSObject.Properties['schema'] -and $items.Count -gt 0))
    if ($j.PSObject.Properties['updated']) { $res.updated = "$($j.updated)" }

    if ($j.PSObject.Properties['sig'] -and "$($j.sig)") {
        # Ключ здесь только читается: заводить новый при проверке — значит
        # наверняка «не сойтись» с журналом, подписанным прежним.
        $want = $null
        try { $want = Get-JournalSig $items $res.legacy } catch { $want = $null }
        if ($null -eq $want) {
            & $setAside 'changes.unverifiable-' 'подпись журнала отката проверить нечем: ключа подписи нет или он испорчен.'
            return $res
        }
        if ($want -ne "$($j.sig)") {
            & $setAside 'changes.unverified-' 'подпись журнала отката не сошлась: его правила не эта программа или он с другого компьютера.'
            return $res
        }
        $res.signed = $true; $res.items = $items
        $res.state = $(if ($res.legacy) { 'legacy' } else { 'valid' })
        return $res
    }
    # Без подписи — журнал прежней версии. В защищённой папке подменить его
    # было некому. В переносимой — могли: из него остаются только записи о
    # настройках самой программы.
    $res.state = $(if ($res.legacy) { 'legacy' } else { 'valid' })
    if ($script:DataDir -eq $script:SafeRoot) { $res.items = $items; return $res }
    $keep = @($items | Where-Object { Test-JournalEntryKnown $_ })
    $res.dropped = $items.Count - $keep.Count
    $res.items = $keep
    if ($res.dropped -gt 0 -and -not $ReadOnly) {
        Write-Log ("   [!] журнал отката прежней версии без подписи лежит в папке, которую может изменить любая программа. Из него взяты только записи о настройках программы: {0} из {1}; остальные (автозагрузка, другие профили, сторонние ключи) пропущены." -f $keep.Count, $items.Count)
    }
    return $res
}

function Write-JournalFile {
    param($Items, [bool]$Legacy)
    $arr = @($Items)
    $parsed = @()
    if ($arr.Count -gt 0) {
        # ConvertFrom-Json отдаёт массив одним объектом: @(...) вокруг вызова
        # завернул бы его ещё раз, и журнал стал бы {"value": [...], "Count": N}
        $back = ConvertFrom-Json (ConvertTo-Json -InputObject $arr -Depth 8 -Compress)
        $parsed = @($back)
    }
    $sig = Get-JournalSig $parsed $Legacy -ForWrite
    Save-Json 'changes.json' ([ordered]@{ schema = 3; legacy = $Legacy; updated = (Get-Date).ToString('s'); items = $parsed; sig = $sig })
}

# Перед применением: журнал должен писаться, иначе ни одно изменение не
# смогло бы вернуться. Проверяем заранее, пока ничего не тронуто.
function Test-JournalWritable {
    if ($DryRun) { return $true }
    try {
        if (-not (Test-DataTrusted)) { throw 'папка данных программы не защищена от подмены' }
        Use-JournalLock {
            Save-Json 'journal-check.json' @{ time = (Get-Date).ToString('s') }
            Remove-Item -LiteralPath (Join-Path $script:DataDir 'journal-check.json') -Force -ErrorAction Stop
        }
        return $true
    } catch {
        Write-Log ("   [!] журнал отката не записывается: {0}" -f $_.Exception.Message)
        return $false
    }
}

# Для отката нужна САМАЯ РАННЯЯ запись про каждый параметр — та, что помнит
# состояние до нас. Остальные повторы держать незачем: раньше журнал рос без
# предела и на каждой записи переписывался целиком.
# Записи журнала бывают двух видов: свежие -- хэш-таблицы, прочитанные из
# файла -- PSCustomObject. У хэш-таблицы PSObject.Properties перечисляет
# свойства самой таблицы, а не её ключи, поэтому читать поля надо по-разному.
function ConvertTo-Fields {
    param($Entry)
    $h = @{}
    if ($null -eq $Entry) { return $h }
    if ($Entry -is [System.Collections.IDictionary]) {
        foreach ($k in @($Entry.Keys)) { $h["$k"] = $Entry[$k] }
    } else {
        foreach ($p in $Entry.PSObject.Properties) { $h[$p.Name] = $p.Value }
    }
    return $h
}

# Ключ записи журнала: про каждый параметр важна самая ранняя запись. Записи
# других профилей (hive) различаются файлом куста — у каждого пользователя свой.
function Get-JournalKey {
    param($F)
    $k = "$($F['kind'])"
    if ($k -eq 'startup') { return "startup|$($F['id'])" }
    if ($k -eq 'hive') { return ("hive|{0}|{1}|{2}" -f "$($F['file'])", "$($F['sub'])", "$($F['name'])").ToLowerInvariant() }
    if ($k -eq 'svc')  { return ("svc|{0}" -f "$($F['name'])").ToLowerInvariant() }
    if ($k -eq 'task') { return ("task|{0}" -f "$($F['path'])").ToLowerInvariant() }
    if ($k -eq 'env')  { return ("env|{0}" -f "$($F['name'])").ToLowerInvariant() }
    if ($k -eq 'audit') { return ("audit|{0}" -f "$($F['guid'])").ToLowerInvariant() }
    # настройка сторонней программы: ключ в её файле (VS Code, Firefox)
    if ($k -eq 'appcfg') { return ("appcfg|{0}|{1}" -f "$($F['app'])", "$($F['name'])").ToLowerInvariant() }
    return ("reg|{0}|{1}" -f "$($F['path'])", "$($F['name'])").ToLowerInvariant()
}

function Compress-Journal {
    param($Items)
    $order = New-Object System.Collections.Generic.List[string]
    $first = @{}
    foreach ($e in @($Items)) {
        $f = ConvertTo-Fields $e
        if ($f.Count -eq 0) { continue }
        $key = Get-JournalKey $f
        if (-not $first.ContainsKey($key)) {
            if (-not $f.ContainsKey('count') -or [int]$f['count'] -lt 1) { $f['count'] = 1 }
            $first[$key] = $f
            $order.Add($key)
            continue
        }
        # повтор: помним только чем всё кончилось и сколько раз меняли
        $cur = $first[$key]
        $cur['count'] = [int]$cur['count'] + [int]$(if ($f.ContainsKey('count') -and [int]$f['count'] -gt 0) { $f['count'] } else { 1 })
        if ($f.ContainsKey('newValue')) { $cur['newValue'] = $f['newValue'] }
        if ($f.ContainsKey('time') -and "$($f['time'])") { $cur['lastTime'] = "$($f['time'])" }
    }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($k in $order) { $out.Add($first[$k]) }
    return $out.ToArray()
}

# Дописывает накопленный журнал «что было до нас» к changes.json. Раньше это
# делалось только в самом конце применения модулей — теперь любая команда,
# меняющая систему, может сохранить свой след для отката одной кнопкой.
# Ошибка записи больше не глотается: раньше программа сообщала об успехе,
# а «как было» на диск не попадало, и откат потом молча ничего не возвращал.
# Теперь она видна в журнале работы, а дальнейшие изменения останавливаются
# ($script:JournalFailed) — менять систему без записи для отката нельзя.
function Save-JournalEntries {
    param([switch]$Quiet)
    if ($DryRun -or ($script:Journal.Count -eq 0 -and $script:JournalRetract.Count -eq 0)) { return }
    $mine = $script:Journal.Count
    try {
        if (-not (Test-DataTrusted)) { throw 'папка данных программы не защищена от подмены' }
        Use-JournalLock {
            $prev = Read-JournalFile
            # Не прочитался (занят) — дописывать нельзя: новый файл из одних
            # свежих записей затёр бы всю историю «как было». Раньше ошибка
            # чтения выглядела пустым журналом, и так и происходило.
            if ($prev.state -eq 'unreadable') { throw 'журнал отката сейчас не читается -- дописать в него нельзя, не потеряв прежние записи' }
            $all = New-Object System.Collections.Generic.List[object]
            foreach ($e in @($prev.items)) {
                # Записи, положенные заранее этим же запуском, чьё изменение не
                # прошло: «было» там верное, но изменения не было — убираем.
                # Записи прежних запусков с тем же ключом не трогаются.
                if ($script:JournalRetract.Count -gt 0 -and "$($e.run)" -eq $script:RunId -and
                    $script:JournalRetract.Contains((Get-JournalKey (ConvertTo-Fields $e)))) { continue }
                $all.Add($e)
            }
            foreach ($e in $script:Journal) { $all.Add($e) }
            Write-JournalFile (Compress-Journal $all.ToArray()) $prev.legacy
            $script:Journal.Clear()
            $script:JournalRetract.Clear()
        }
    } catch {
        if (-not $script:JournalFailed) {
            Write-Log ("   [!] журнал отката не записался: {0}" -f $_.Exception.Message)
            Write-Log '       Дальше программа ничего не меняет: изменение без записи в журнале нельзя было бы вернуть.'
        }
        $script:JournalFailed = $true
        $script:Failures++
        return
    }
    if (-not $Quiet) { Write-Log ("Записано в журнал отката: {0}" -f $mine) }
}

# Убрать из журнала записи с этим ключом — после того как значение возвращено.
# Под замком и только из журнала, которому можно верить.
function Remove-JournalKey {
    param([string]$Key)
    Use-JournalLock {
        $jf = Read-JournalFile
        if (-not $jf.trusted) { throw 'журналу отката нельзя верить' }
        $rest = @($jf.items | Where-Object { (Get-JournalKey (ConvertTo-Fields $_)) -ne $Key })
        Write-JournalFile $rest $jf.legacy
    }
}

# Опознавательный знак записи журнала: ключ плюс когда и сколько раз её
# меняли. Запись, которую другой запуск успел дополнить (Compress-Journal
# прибавил count или lastTime), — уже другая и не считается обработанной.
function Get-JournalEntryId {
    param($Entry)
    $f = ConvertTo-Fields $Entry
    return ('{0}|{1}|{2}|{3}|{4}' -f (Get-JournalKey $f), "$($f['time'])", "$($f['lastTime'])", "$($f['count'])", "$($f['run'])")
}

# Убрать из журнала записи, с которыми откат закончил. Журнал перечитывается
# под замком: что за это время дописал другой запуск (страж, второе окно),
# остаётся. Раньше откат переписывал журнал тем, что прочитал в начале, и
# такие записи пропадали.
function Remove-JournalEntries {
    param($Handled)
    Use-JournalLock {
        $jf = Read-JournalFile
        if (-not $jf.trusted) { throw 'журналу отката нельзя верить' }
        $rest = @($jf.items | Where-Object { -not $Handled.Contains((Get-JournalEntryId $_)) })
        Write-JournalFile $rest $jf.legacy
    }
}
# --------------------------------------------------------------------------- #
#  Записи о незаконченных операциях (T-3: восстановление из резервной копии;
#  стирание номера устройства). Обе идут по шагам, и сделать их неделимыми
#  нельзя: reg.exe import пишет значения по одному и, оборвавшись, оставляет
#  уже записанное; стирание номера останавливает службы и запускает их
#  только в конце. Поэтому, как и журнал отката, такая операция сначала
#  пишет на диск, что собирается делать и на каком она шаге, и только потом
#  делает. Оборвалась — запись остаётся, и следующий запуск знает, что
#  операция не закончена (RecoveryRequired), а не считает, что всё в порядке.
#  Запись — теми же средствами, что журнал: в папке данных (Save-Json: файл
#  пишется рядом и подменяет прежний одним действием), под замком журнала,
#  подписана тем же ключом (HMAC-SHA256 со своей приставкой: подпись записи
#  за подпись журнала не сойдёт). Отдельным файлом op-<имя>.json, а не в
#  changes.json: это не «как было» для отката, а состояние операции — в
#  журнале его исполнял бы полный откат, а прежние версии программы
#  отложили бы журнал с незнакомой записью как недоверенный.
#  Пока операция идёт, её замок (файл <имя>.lock в защищённом корне — как
#  замок журнала: только система и администраторы, без совместного доступа)
#  держится открытым. Запись есть, а замок свободен — процесс, который её
#  писал, умер посередине (Windows закрывает файл сама).
# --------------------------------------------------------------------------- #
function Get-OpRecordPath { param([string]$Name) return (Join-Path $script:DataDir ('op-{0}.json' -f $Name)) }

function Get-OpRecordSig {
    param([string]$Name, $Data, [switch]$ForWrite)
    $canon = ('w11p-op|{0}|' -f $Name.ToLowerInvariant()) + (ConvertTo-Json -InputObject $Data -Depth 8 -Compress)
    $h = [System.Security.Cryptography.HMACSHA256]::new([byte[]](Get-SignKey -Create:$ForWrite))
    try { return (($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($canon)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $h.Dispose() }
}

# Записать состояние операции. Не записалось — исключение: тогда операция
# не начинается (или не идёт дальше) — без записи её обрыв никто бы не заметил.
function Write-OpRecord {
    param([string]$Name, $Data)
    if (-not (Test-DataTrusted)) { throw 'папка данных программы не защищена от подмены' }
    # подпись — по тексту, который даст разбор самого файла (как у журнала)
    $parsed = ConvertFrom-Json (ConvertTo-Json -InputObject $Data -Depth 8 -Compress)
    $sig = Get-OpRecordSig $Name $parsed -ForWrite
    Use-JournalLock { Save-Json ('op-{0}.json' -f $Name) ([ordered]@{ schema = 1; op = $Name; updated = (Get-Date).ToString('s'); data = $parsed; sig = $sig }) }
}

# Прочитать запись операции. state: none — записи нет; valid — подпись
# сошлась (data); untrusted — повреждена, подпись не сошлась или проверить
# нечем (такой записи не верят и по ней ничего не делают); unreadable —
# сейчас не читается (это не «записи нет»).
function Read-OpRecord {
    param([string]$Name)
    $p = Get-OpRecordPath $Name
    $res = @{ state = 'none'; data = $null; error = ''; path = $p }
    # Файла нет — записи нет (обычный случай; замок и проверку папки ради
    # этого не берём). «Не прочиталось» сюда не попадает: Test-Path на
    # закрытом файле отвечает «есть».
    if (-not (Test-Path -LiteralPath $p)) { return $res }
    if (-not (Test-DataTrusted)) { $res.state = 'unreadable'; $res.error = 'папка данных программы не защищена от подмены'; return $res }
    $box = @{ txt = $null }
    try { Use-JournalLock { $box.txt = Read-TextShared $p } }
    catch {
        # без прав администратора замок журнала не взять — только посмотреть;
        # любая другая ошибка — «не читается» (вид — по исключению, T-4)
        if (-not ($_.Exception.GetBaseException() -is [System.UnauthorizedAccessException])) { $res.state = 'unreadable'; $res.error = "$($_.Exception.Message)"; return $res }
        try { $box.txt = Read-TextShared $p } catch { $res.state = 'unreadable'; $res.error = "$($_.Exception.Message)"; return $res }
    }
    if ($null -eq $box.txt) { return $res }
    $j = $null
    try { $j = $box.txt | ConvertFrom-Json -ErrorAction Stop } catch { $j = $null }
    if ($null -eq $j -or "$($j.schema)" -ne '1' -or "$($j.op)" -cne $Name -or -not "$($j.sig)" -or $null -eq $j.data) {
        $res.state = 'untrusted'; $res.error = 'запись повреждена'; return $res
    }
    $want = $null
    try { $want = Get-OpRecordSig $Name $j.data } catch { $want = $null }
    if ($null -eq $want) { $res.state = 'untrusted'; $res.error = 'подпись записи проверить нечем'; return $res }
    if ($want -cne "$($j.sig)") { $res.state = 'untrusted'; $res.error = 'подпись записи не сошлась'; return $res }
    $res.state = 'valid'; $res.data = $j.data
    return $res
}

# Убрать запись операции и проверить, что её нет. Ответ: $true — нет.
function Remove-OpRecord {
    param([string]$Name)
    $p = Get-OpRecordPath $Name
    Use-JournalLock { if (Test-Path -LiteralPath $p) { [IO.File]::Delete($p) } }
    return (-not (Test-Path -LiteralPath $p))
}

# Недоверенная запись откладывается рядом под своим именем (как журнал) —
# по ней ничего не делается, но и молча она не пропадает.
function Set-OpRecordAside {
    param([string]$Name)
    $p = Get-OpRecordPath $Name
    $bad = Join-Path $script:DataDir ('op-{0}.untrusted-{1}.json' -f $Name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Use-JournalLock { if (Test-Path -LiteralPath $p) { Move-Item -LiteralPath $p -Destination $bad -Force -ErrorAction Stop } }
    return (Split-Path $bad -Leaf)
}

# Замок операции: открытый файл <имя>.lock в защищённом корне. $null —
# занят другим запуском; исключение — замка нет вовсе (корень не защищён,
# нет прав). Закрывается Dispose() — или самой Windows, если процесс умер.
function Enter-OpLock {
    param([string]$Name)
    try { return (Open-JournalLockFile -Path (Join-Path $script:SafeRoot ('{0}.lock' -f $Name))) }
    catch {
        # вид ошибки — по самому исключению .NET (T-4, см. Test-IoBusy)
        if (Test-IoBusy $_.Exception) { return $null }
        throw
    }
}

# Идёт ли операция сейчас: её замок занят. $null — не проверить.
function Test-OpRunning {
    param([string]$Name)
    try {
        $l = Enter-OpLock $Name
        if ($null -eq $l) { return $true }
        $l.Dispose(); return $false
    } catch { return $null }
}

# Файлы данных читаются только из папки, которой можно верить, — так же, как
# пишутся (Save-Json). Раньше чтение не проверяло папку: подложенный файл
# (например, profile.json — какие модули страж держит включёнными) прочитался
# бы с правами администратора.
function Load-Json {
    param([string]$Name)
    if (-not (Test-DataTrusted)) { return $null }
    $p = Join-Path $script:DataDir $Name
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try {
        $txt = Read-TextShared $p
        if (-not "$txt".Trim()) { return $null }
        return ($txt | ConvertFrom-Json -ErrorAction Stop)
    } catch { Write-Log ("   [!] файл данных {0} не читается: {1}" -f $Name, $_.Exception.Message); return $null }
}

# --- Службы, задачи и переменные среды в журнале отката --------------------- #
#  Раньше журнал помнил только реестр, а полный откат включал службы и задачи
#  «по умолчанию»: DiagTrack — автоматически, все задачи из списка — включить.
#  Задача, которую человек выключил сам задолго до программы, после отката
#  включалась. Теперь у каждой записано, какой она была до нас.
#
# Журнал раньше изменения (write-ahead) — единственный способ записи в журнал.
# Прежде запись о том, «как было», добавлялась после изменения и ложилась на
# диск пачками по десять: обрыв процесса между изменением и записью оставлял
# изменение без пути назад. Теперь «как было» сначала ложится на диск, и
# только потом меняется система. Не легло — менять нельзя ($false). Изменение
# не прошло — запись отзывается (Undo-AheadEntry): «было» в ней верное, просто
# изменения не было.
function Write-AheadEntry {
    param($Entry)
    if ($DryRun) { return $true }
    if ($script:JournalFailed) { return $false }
    $Entry['time'] = (Get-Date).ToString('s')
    $Entry['run'] = $script:RunId
    $script:Journal.Add($Entry)
    Save-JournalEntries -Quiet
    return (-not $script:JournalFailed)
}

function Undo-AheadEntry {
    param($Entry)
    if ($DryRun) { return }
    # ещё не на диске — просто убрать из очереди; уже на диске — отозвать
    # сразу же: команда может закончиться, не записав журнал ещё раз
    if ($script:Journal.Remove($Entry)) { return }
    $null = $script:JournalRetract.Add((Get-JournalKey (ConvertTo-Fields $Entry)))
    Save-JournalEntries -Quiet
}

# Менять систему можно, только пока журнал отката пишется. Раньше это
# проверялось в применении модулей, но не в прямых вызовах записи реестра.
function Test-CanModify {
    param([string]$Label)
    if ($DryRun) { return $true }
    if ($script:JournalFailed) { Write-Log ("   [!] {0} -- не меняется: журнал отката сейчас не пишется" -f $Label); $script:Failures++; return $false }
    return $true
}

function Get-SvcJournalState {
    param([string]$Name, $Svc)
    $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    $start = Get-RegValue $k 'Start'
    $delayed = Get-RegValue $k 'DelayedAutostart'
    return @{ kind = 'svc'; name = $Name
              old = $(if ($null -ne $start) { "$start" } else { '' })
              delayed = $(if ($null -ne $delayed) { "$delayed" } else { '' })
              running = [bool]($Svc -and $Svc.Status -eq 'Running')
              newValue = '4' }
}

# Политика аудита словами — для страницы «Журнал изменений»
function Get-AuditName {
    param([string]$Value)
    switch ("$Value") { '1' { return 'успех' } '2' { return 'отказ' } '3' { return 'успех и отказ' } }
    return 'выкл'
}

# Тип запуска службы словами — для страницы «Журнал изменений»
function Get-StartName {
    param([string]$Start, [string]$Delayed = '')
    switch ("$Start") {
        '0' { return 'при загрузке системы' }
        '1' { return 'системная' }
        '2' { if ("$Delayed" -eq '1') { return 'автоматически (отложенный запуск)' } return 'автоматически' }
        '3' { return 'вручную' }
        '4' { return 'отключена' }
    }
    return 'не было'
}

# Форма записи журнала перед тем, как по ней что-то делать. Подпись говорит,
# что запись не меняли, но не то, что она допустима: вид — из известных, поля
# на месте, пути реестра — только в его ветках, имена служб, задач и
# переменных — допустимого вида, GUID аудита — наш. Пустая строка — годится,
# иначе — почему нет.
function Test-JournalEntryShape {
    param($Entry)
    $f = ConvertTo-Fields $Entry
    $kind = "$($f['kind'])"
    $regPath = '^(HKLM|HKCU):\\[^\x00-\x1f]+$|^Registry::HKEY_(LOCAL_MACHINE|CURRENT_USER|USERS)\\[^\x00-\x1f]+$'
    switch ($kind) {
        'reg' {
            if ("$($f['path'])" -notmatch $regPath) { return 'путь не в ветке реестра' }
            if (-not "$($f['name'])") { return 'пустое имя параметра' }
            if ($f['existed'] -and -not (Test-RegKind "$($f['type'])")) { return 'неизвестный тип значения' }
            # созданный программой ключ — только сам путь значения или ключ выше него
            $ck = "$($f['createdKey'])"
            if ($ck -and -not ($ck -match $regPath -and ("$($f['path'])" -eq $ck -or "$($f['path'])".StartsWith($ck + '\', [StringComparison]::OrdinalIgnoreCase)))) { return 'созданный ключ не на пути значения' }
            return ''
        }
        'svc' {
            if ("$($f['name'])" -notmatch '^[A-Za-z0-9_.\-$]{1,256}$') { return 'недопустимое имя службы' }
            if ("$($f['old'])" -notmatch '^[0-4]?$') { return 'недопустимый тип запуска' }
            if ("$($f['delayed'])" -notmatch '^[01]?$') { return 'недопустимый отложенный запуск' }
            return ''
        }
        'task' {
            if ("$($f['path'])" -notmatch '^\\[^"\x00-\x1f%]+$') { return 'недопустимый путь задачи' }
            if ("$($f['old'])" -notin @('Enabled', 'Disabled')) { return 'недопустимое состояние задачи' }
            return ''
        }
        'env' {
            if ("$($f['name'])" -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,254}$') { return 'недопустимое имя переменной' }
            return ''
        }
        'audit' {
            if ("$($f['guid'])" -ne $script:AuditGuid) { return 'чужая подкатегория аудита' }
            if ("$($f['old'])" -notmatch '^[0-3]$') { return 'недопустимое значение аудита' }
            return ''
        }
        'appcfg' {
            if ("$($f['app'])" -notin @('vscode', 'firefox')) { return 'неизвестная программа' }
            # ключ настройки: буквы, цифры, точка, дефис, подчёркивание
            if ("$($f['name'])" -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$') { return 'недопустимое имя настройки' }
            # «как было» — одно значение JSON, а не произвольный текст: иначе
            # дописанная запись подставила бы в файл настроек что угодно
            if ("$($f['old'])" -and "$($f['old'])" -notmatch '^("[^"\\\x00-\x1f]*"|true|false|-?[0-9]+(\.[0-9]+)?)$') { return 'недопустимое прежнее значение' }
            return ''
        }
        'startup' {
            if (-not "$($f['id'])") { return 'пустая запись автозагрузки' }
            if ("$($f['old'])" -notin @('On', 'Off')) { return 'недопустимое состояние автозагрузки' }
            return ''
        }
        'hive' {
            # кавычка в пути разорвала бы аргумент reg.exe load; в путях Windows её не бывает
            if ("$($f['file'])" -notmatch '^[A-Za-z]:\\[^\x00-\x1f"]*\\NTUSER\.DAT$') { return 'недопустимый файл куста' }
            if ("$($f['sub'])" -match '^\\|\.\.|[\x00-\x1f]' -or -not "$($f['sub'])") { return 'недопустимый путь в кусте' }
            if (-not "$($f['name'])") { return 'пустое имя параметра' }
            if ($f['existed'] -and -not (Test-RegKind "$($f['type'])")) { return 'неизвестный тип значения' }
            return ''
        }
    }
    return 'неизвестный вид записи'
}

# Возвращает параметр реестра к тому, что было, и сверяет: «команда прошла» —
# ещё не «вернулось». Раньше успехом считался сам вызов New-ItemProperty.
# Было — значит, параметр есть, того же вида и с теми же данными; не было —
# параметра нет (ключ, в котором его нет, при этом не трогается). Повторный
# вызов ничего не портит: вернувшееся просто ещё раз сверяется.
function Restore-RegValue {
    param([string]$Path, [string]$Name, [bool]$Existed, $Old, [string]$Type)
    try {
        if ($Existed) {
            if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
            # из JSON двоичное и многострочное приходят массивами чисел и строк
            $v = $Old
            if ($Type -eq 'Binary') { $v = [byte[]]@(@($Old) | Where-Object { $null -ne $_ }) }
            elseif ($Type -eq 'MultiString') { $v = [string[]]@(@($Old) | Where-Object { $null -ne $_ }) }
            New-ItemProperty -LiteralPath $Path -Name $Name -Value $v -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        } else {
            $was = Get-RegRaw $Path $Name
            if (-not $was.ok) { return @{ ok = $false; denied = [bool]$was.denied; error = ("параметр не прочитался: {0}" -f $was.error) } }
            if ($was.exists) { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop }
        }
    } catch {
        $ex = $_.Exception
        $den = ($ex -is [System.UnauthorizedAccessException] -or $ex -is [System.Security.SecurityException] -or
                $ex.InnerException -is [System.UnauthorizedAccessException] -or $ex.InnerException -is [System.Security.SecurityException])
        return @{ ok = $false; denied = [bool]$den; error = $ex.Message }
    }
    $now = Get-RegRaw $Path $Name
    if (-not $now.ok) { return @{ ok = $false; denied = [bool]$now.denied; error = ("после возврата параметр не прочитался: {0}" -f $now.error) } }
    if (-not $Existed) {
        if ($now.exists) { return @{ ok = $false; error = 'параметр не убрался' } }
        return @{ ok = $true }
    }
    if (-not $now.exists) { return @{ ok = $false; error = 'после записи параметра нет' } }
    if ($now.kind -ne $Type) { return @{ ok = $false; error = ("вид значения {0}, а было {1}" -f $now.kind, $Type) } }
    $want = ConvertTo-RegComparable $Old $Type
    $got = ConvertTo-RegComparable $now.value $Type
    if ($got -ne $want) { return @{ ok = $false; error = ("читается «{0}», а было «{1}»" -f $got, $want) } }
    return @{ ok = $true }
}

# Убирает ключи, которые создала программа (createdKey в записях журнала),
# когда в них не осталось ни одного значения. Вызывается после того, как
# возвращены все значения: значения одного ключа лежат в разных записях, а
# ключ запомнила только первая из них. Ключ, в который за это время записал
# кто-то ещё, остаётся — это не ошибка.
function Remove-CreatedKeys {
    param([string[]]$Keys)
    foreach ($k in @($Keys | Where-Object { $_ } | Select-Object -Unique | Sort-Object { $_.Length } -Descending)) {
        if (-not (Test-Path -LiteralPath $k)) { continue }
        if (-not (Test-KeyTreeEmpty $k)) { Write-Log ("   [i] ключ {0} создала программа, но в нём есть и другие значения -- оставлен" -f $k); continue }
        try { Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction Stop; Write-Log ("   [+] убран пустой ключ, которого не было до программы: {0}" -f $k) }
        catch { Write-Log ("   [!] пустой ключ {0}, которого не было до программы, не убрался: {1}" -f $k, $_.Exception.Message); $script:Failures++ }
    }
}

# Возвращает одну запись журнала (реестр, служба, задача, переменная среды).
# Записи автозагрузки и чужих профилей возвращаются своими функциями.
function Restore-JournalEntry {
    param($e)
    try {
        switch ("$($e.kind)") {
            'svc' {
                $name = "$($e.name)"
                $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
                # «Службы больше нет» — только когда нет и её ключа в реестре.
                # Раньше так называлась любая ошибка Get-Service (например,
                # отказ в доступе): тип запуска не возвращался, а запись
                # журнала убиралась как возвращённая.
                $svcObj = $null
                try { $svcObj = Get-Service -Name $name -ErrorAction Stop } catch { }
                $viaReg = $false
                if (-not $svcObj) {
                    $kx = Test-RegKeyExists $k
                    if ($kx -eq $false) { return @{ ok = $true; missing = $true; note = 'службы больше нет' } }
                    if ($null -eq $kx) { return @{ ok = $false; denied = $true; error = 'служба не видна диспетчеру служб, а её ключ в реестре не читается' } }
                    # ключ есть, а диспетчер служб её не назвал — тип запуска пишется в реестр
                    $viaReg = $true
                }
                $start = "$($e.old)"
                $type = switch ($start) { '2' { 'Automatic' } '3' { 'Manual' } '4' { 'Disabled' } default { '' } }
                if ($type -and -not $viaReg) { Set-Service -Name $name -StartupType $type -ErrorAction Stop }
                elseif ($start -ne '') { Set-ItemProperty -LiteralPath $k -Name 'Start' -Value ([int]$start) -Type DWord -ErrorAction Stop }
                # тип запуска сверяется: «команда прошла» — ещё не «вернулось»
                if ($start -ne '' -and "$(Get-RegValue $k 'Start')" -ne $start) {
                    return @{ ok = $false; error = ("тип запуска не вернулся: сейчас {0}, нужно {1}" -f (Get-StartName "$(Get-RegValue $k 'Start')"), (Get-StartName $start)) }
                }
                # Отложенный запуск — так же: вернуть и сверить. Раньше он
                # возвращался молча (ошибка глоталась) и без сверки, а откат
                # считался полным. Не было — значит, и сейчас не должно быть
                # ненулевым (ноль и «нет» для Windows одно и то же).
                $wantD = "$($e.delayed)"
                $nowD = Get-RegRaw $k 'DelayedAutostart'
                if ($wantD -ne '') {
                    try { Set-ItemProperty -LiteralPath $k -Name 'DelayedAutostart' -Value ([int]$wantD) -Type DWord -ErrorAction Stop }
                    catch { return @{ ok = $false; error = ("тип запуска возвращён, а отложенный запуск — нет: {0}" -f $_.Exception.Message) } }
                    $nowD = Get-RegRaw $k 'DelayedAutostart'
                    if (-not $nowD.ok -or -not $nowD.exists -or "$($nowD.kind)" -ne 'DWord' -or "$([int64]$nowD.value)" -ne $wantD) {
                        return @{ ok = $false; error = ("отложенный запуск не вернулся: сейчас {0}, нужно {1}" -f $(if ($nowD.exists) { "$($nowD.value)" } else { 'нет' }), $wantD) }
                    }
                } elseif (-not $nowD.ok) {
                    return @{ ok = $false; error = ("отложенный запуск не прочитался: {0}" -f $nowD.error) }
                } elseif ($nowD.exists -and [int64]("0" + "$($nowD.value)") -ne 0) {
                    try { Remove-ItemProperty -LiteralPath $k -Name 'DelayedAutostart' -ErrorAction Stop }
                    catch { return @{ ok = $false; error = ("отложенного запуска до программы не было, а убрать его не вышло: {0}" -f $_.Exception.Message) } }
                }
                # работала до нас — запускаем снова, чтобы не ждать перезагрузки;
                # не запустилась сейчас — так и сказано (тип запуска уже верный)
                if ($e.running -and $start -ne '4') {
                    try { Start-Service -Name $name -ErrorAction Stop }
                    catch { return @{ ok = $true; note = ("тип запуска возвращён, но сейчас служба не запустилась: {0}" -f $_.Exception.Message) } }
                }
                return @{ ok = $true }
            }
            'task' {
                if ("$($e.old)" -ne 'Enabled') { return @{ ok = $true } }
                $r = Set-TaskEnabled "$($e.path)" $true
                if ($r -in @('ok', 'system')) { return @{ ok = $true } }
                # задачи больше нет — возвращать нечего, но это не «вернулось»
                if ($r -eq 'missing') { return @{ ok = $true; note = 'задачи больше нет' } }
                return @{ ok = $false; error = 'Windows не дала включить задачу' }
            }
            'env' {
                $v = $(if ($e.existed) { "$($e.old)" } else { $null })
                [Environment]::SetEnvironmentVariable("$($e.name)", $v, 'User')
                # сверка: пустое значение Windows хранит как «переменной нет»
                $now = [Environment]::GetEnvironmentVariable("$($e.name)", 'User')
                if ([string]::IsNullOrEmpty($v)) {
                    if (-not [string]::IsNullOrEmpty($now)) { return @{ ok = $false; error = 'переменная не убралась' } }
                } elseif ($now -cne $v) { return @{ ok = $false; error = ("переменная читается «{0}», а было «{1}»" -f $now, $v) } }
                return @{ ok = $true }
            }
            'audit' {
                $r = Set-AuditSetting "$($e.guid)" ([int]"$($e.old)")
                if ($r.ok) { return @{ ok = $true } }
                return @{ ok = $false; error = ("auditpol (код {0}): {1}" -f $r.code, $r.out) }
            }
            'appcfg' {
                # Возвращается ровно наш ключ: было значение — то же самое
                # слово в слово, не было — ключ убирается. Остальное в файле
                # не трогается, даже если человек поменял его после нас.
                $was = [bool]$e.existed
                $tok = "$($e.old)"
                if ("$($e.app)" -eq 'vscode') {
                    if (-not (Test-Path -LiteralPath (Get-VsCodeSettingsPath) -PathType Leaf)) { return @{ ok = $true; note = 'файла настроек больше нет' } }
                    $w = Write-VsCodeKey "$($e.name)" $(if ($was) { $tok } else { '' })
                    if (-not $w.ok) { return @{ ok = $false; error = $w.why } }
                    $now = Get-VsCodeRaw "$($e.name)"
                    if ($was) {
                        if (-not $now.exists) { return @{ ok = $false; error = 'ключ не вернулся' } }
                        if ($now.token -ne $tok) { return @{ ok = $false; error = ("читается {0}, а было {1}" -f $now.token, $tok) } }
                    } elseif ($now.exists) { return @{ ok = $false; error = 'ключ не убрался' } }
                    return @{ ok = $true }
                }
                if (-not (Get-FirefoxPoliciesPath)) { return @{ ok = $true; note = 'Firefox больше не установлен' } }
                $w = $(if ($was) { Write-FirefoxKey "$($e.name)" (ConvertFrom-JsonToken $tok) } else { Write-FirefoxKey "$($e.name)" $null -Remove })
                if (-not $w.ok) { return @{ ok = $false; error = $w.why } }
                if ($w.removedFile) { return @{ ok = $true; note = 'policies.json создала программа и он опустел -- удалён' } }
                $nowF = Get-FirefoxPolicy "$($e.name)"
                if ($was) {
                    if ($null -eq $nowF) { return @{ ok = $false; error = 'политика не вернулась' } }
                } elseif ($null -ne $nowF) { return @{ ok = $false; error = 'политика не убралась' } }
                return @{ ok = $true }
            }
            default {
                return (Restore-RegValue "$($e.path)" "$($e.name)" ([bool]$e.existed) $e.old "$($e.type)")
            }
        }
    } catch {
        # отказ в доступе — отдельно от прочих сбоев: «Windows не дала», а не «не вышло»
        $ex = $_.Exception
        $den = ($ex -is [System.UnauthorizedAccessException] -or $ex -is [System.Security.SecurityException] -or
                $ex.InnerException -is [System.UnauthorizedAccessException] -or $ex.InnerException -is [System.Security.SecurityException] -or
                "$($ex.Message)" -match 'Access is denied|Отказано в доступе')
        return @{ ok = $false; denied = [bool]$den; error = $ex.Message }
    }
}

# =========================================================================== #
#  Определение системы
# =========================================================================== #
function Get-Edition {
    $ed = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'EditionID'
    if (-not $ed) { $ed = '' }
    $kind = 'other'
    if ($ed -match '^Core') { $kind = 'home' }
    elseif ($ed -match '^Professional') { $kind = 'pro' }
    elseif ($ed -match 'Enterprise|Education|Server') { $kind = 'enterprise' }
    return @{ id = $ed; kind = $kind }
}

function Test-Exe { param([string[]]$Paths) foreach ($p in $Paths) { if ($p -and (Test-Path -LiteralPath $p)) { return $true } } return $false }

# Включена ли «Защита от подделки» Защитника. При ней политики MAPS (облачная
# защита, отправка образцов) могут лечь в реестр — проверка их увидит, — но
# Защитник их игнорирует, и отправка продолжается. То есть «применено» по
# реестру не значит «подействовало»: об этом надо сказать прямо.
function Test-TamperProtection {
    $v = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Features' 'TamperProtection'
    # 5 — включена, 4 — выключена (наблюдалось); решаем по биту 0
    return ($null -ne $v -and ([int]$v -band 1) -eq 1)
}

# --------------------------------------------------------------------------- #
#  КТО СИДИТ ЗА КОМПЬЮТЕРОМ. Пароль администратора может ввести и обычный
#  пользователь — тогда повышенный движок работает под администратором, а
#  человек за компьютером другой. Настройки HKCU и задачи стража уходили при
#  этом в профиль администратора: человек их не получал, а проверка читала
#  тот же HKCU и показывала «применено».
#  Владелец explorer.exe в этом сеансе — тот, кто вошёл в Windows.
#  @{ sid; name; profile; isMe } или $null, если определить не удалось.
#
#  Только explorer.exe ЭТОГО сеанса (того, где работает движок). Раньше брался
#  любой explorer.exe на компьютере: когда в Windows вошли двое (быстрая смена
#  пользователей), «за компьютером» мог оказаться второй — и задача от имени
#  пользователя (Invoke-AsUser), его кэш платформы устройств и его настройки
#  HKCU шли не тому человеку. У задачи от имени SYSTEM (сеанс 0) explorer нет —
#  «другого пользователя» у неё нет.
#  Не удалось спросить Windows (WMI не ответил) — $script:SessionUserError: это
#  не «за компьютером сам движок», а «неизвестно»; стирание номера тогда не
#  начинается (Get-GdidPreflight), прочее ведёт себя как раньше.
# --------------------------------------------------------------------------- #
$script:SessionUserCache = $null
$script:SessionUserError = ''
function Get-SessionUser {
    if ($null -ne $script:SessionUserCache) { return $script:SessionUserCache.v }
    $found = $null
    $script:SessionUserError = ''
    try {
        $mySession = [int][Diagnostics.Process]::GetCurrentProcess().SessionId
        foreach ($p in @(Get-CimInstance Win32_Process -Filter ("Name='explorer.exe' AND SessionId={0}" -f $mySession) -ErrorAction Stop)) {
            $o = $null
            try { $o = Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid -ErrorAction Stop } catch { }
            $sid = $(if ($o) { "$($o.Sid)" } else { '' })
            # люди: локальные и доменные (S-1-5-21-…) и Entra ID (S-1-12-1-…)
            if ($sid -notmatch '^S-1-(5-21|12-1)-[\d-]+$') { continue }
            $name = ''
            try { $name = (New-Object Security.Principal.SecurityIdentifier($sid)).Translate([Security.Principal.NTAccount]).Value } catch { }
            $prof = Get-MachinePath ('SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\' + $sid) 'ProfileImagePath' $null
            $found = @{ sid = $sid; name = $name; profile = $prof; isMe = ($sid -eq $script:UserSid) }
            if ($found.isMe) { break }     # свой сеанс важнее чужого
        }
    } catch { $found = $null; $script:SessionUserError = "$($_.Exception.Message)" }
    $script:SessionUserCache = @{ v = $found }
    return $found
}

# Повышение под другой учётной записью: за компьютером один человек, а движок
# работает от имени другого. Пусто — всё в порядке (или определить не вышло).
function Get-OtherSessionUser {
    $s = Get-SessionUser
    if ($null -eq $s -or $s.isMe) { return $null }
    return $s
}

# Задачи стража и слежения идут с RunLevel Highest — то есть с повышением, а
# оно есть только у администратора. Поэтому ставятся они на учётную запись
# самого движка, а не на обычного пользователя, который вошёл в Windows: на
# его входе повышения у них не было бы, и они молча ничего бы не делали.
# Честно сказать об этом надо там, где человек их включает.
function Write-SessionUserNote {
    $s = Get-OtherSessionUser
    if (-not $s) { return }
    Write-Log ("   [i] в Windows вошёл {0}, а программа работает от имени {1}." -f $s.name, $script:RunAccount)
    Write-Log ("       Задача ставится на {0}: повышение есть только у администратора, и она сработает, когда он войдёт в Windows." -f $script:RunAccount)
    Write-Log '       Настройки пользователя (HKCU) дойдут и до вошедшего, но следить за ними в его сеансе эта задача не будет.'
}

# Папки «пользователя» — это папки того, кто сидит за компьютером. Если движок
# работает от имени другого администратора, переменные APPDATA, TEMP и прочие
# указывают на профиль администратора, а чистить и править надо профиль вошедшего:
# именно он просил. Путь внутри профиля самого движка переносится в профиль
# вошедшего; всё остальное остаётся как есть.
function Convert-ToSessionPath {
    param([string]$Path)
    $s = Get-OtherSessionUser
    if (-not $s -or -not $s.profile -or -not $script:UserProfileDir) { return $Path }
    $own = $script:UserProfileDir.TrimEnd('\') + '\'
    if ($Path.StartsWith($own, [StringComparison]::OrdinalIgnoreCase)) {
        return ($s.profile.TrimEnd('\') + '\' + $Path.Substring($own.Length))
    }
    return $Path
}

function Detect-Apps {
    $pf   = $env:ProgramFiles
    $pf86 = ${env:ProgramFiles(x86)}
    $la   = $env:LOCALAPPDATA
    $apps = @()

    # NVIDIA
    $nvSvc  = Get-Service -Name 'NvTelemetryContainer' -ErrorAction SilentlyContinue
    $nvTask = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'NvTm*' -or $_.TaskName -like 'NvProfileUpdater*' -or $_.TaskName -like 'NvDriverUpdateCheck*' })
    $nvReg  = Test-Path 'HKLM:\SOFTWARE\NVIDIA Corporation'
    $apps += @{ id='app_nvidia'; name='NVIDIA (драйвер и GeForce)'; found=[bool]($nvSvc -or $nvTask.Count -gt 0 -or $nvReg);
                detail = "служба: $([bool]$nvSvc), задач: $($nvTask.Count)" }

    # VS Code
    $vsSettings = Join-Path $env:APPDATA 'Code\User\settings.json'
    $vsExe = Test-Exe @((Join-Path $la 'Programs\Microsoft VS Code\Code.exe'), (Join-Path $pf 'Microsoft VS Code\Code.exe'))
    $apps += @{ id='app_vscode'; name='Visual Studio Code'; found=[bool]($vsExe -or (Test-Path -LiteralPath $vsSettings)); detail=$vsSettings }

    # Chrome
    $chrome = Test-Exe @((Join-Path $pf 'Google\Chrome\Application\chrome.exe'), (Join-Path $pf86 'Google\Chrome\Application\chrome.exe'), (Join-Path $la 'Google\Chrome\Application\chrome.exe'))
    $apps += @{ id='app_chrome'; name='Google Chrome'; found=[bool]$chrome; detail='' }

    # Firefox
    $ffDir = @((Join-Path $pf 'Mozilla Firefox'), (Join-Path $pf86 'Mozilla Firefox')) | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'firefox.exe') } | Select-Object -First 1
    $apps += @{ id='app_firefox'; name='Mozilla Firefox'; found=[bool]$ffDir; detail=("$ffDir") }

    # Office
    $office = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun') -or (Test-Exe @((Join-Path $pf 'Microsoft Office\root\Office16\WINWORD.EXE'), (Join-Path $pf86 'Microsoft Office\root\Office16\WINWORD.EXE')))
    $apps += @{ id='app_office'; name='Microsoft Office'; found=[bool]$office; detail='' }

    # Средства разработки: PowerShell 7 / .NET SDK
    $pwsh = Test-Exe @((Join-Path $pf 'PowerShell\7\pwsh.exe'))
    $dotnet = Test-Exe @((Join-Path $pf 'dotnet\dotnet.exe'))
    $apps += @{ id='app_devtools'; name='PowerShell 7 / .NET SDK'; found=[bool]($pwsh -or $dotnet); detail="pwsh: $pwsh, dotnet: $dotnet" }

    # Visual Studio
    $vs = (Test-Path 'HKLM:\SOFTWARE\Microsoft\VisualStudio\Setup') -or (Test-Path (Join-Path $pf 'Microsoft Visual Studio')) -or (Test-Path (Join-Path $pf86 'Microsoft Visual Studio'))
    $apps += @{ id='app_vs'; name='Visual Studio'; found=[bool]$vs; detail='' }

    return $apps
}

# --- OEM: компоненты сбора данных производителя ---------------------------- #
$script:OemVendorRegex  = 'Huawei|Honor|Hihonor|\bHP\b|Hewlett|Lenovo|\bDell\b|ASUS|Acer|\bMSI\b|Samsung|Xiaomi|Realme'
$script:OemKeywordRegex = 'Telemetry|Analytic|Report|Usage|Experience|Feedback|Metric|Diagnos|Collect|Survey|Statistic|Insight|Tracking|SupportAssist|TouchPoint|Improvement|UEIP|Beacon'
$script:OemExcludeRegex = 'Update|Driver|Audio|Bluetooth|Camera|Display|Power|Battery|Keyboard|Touchpad|Fingerprint|Hotkey|\bFn\b|Thermal|Fan|Network|WLAN|Wifi|Print|Scan|Backup|Recovery|Security|Antivirus'

function Detect-Oem {
    $found = @()
    $manu = ''
    try { $manu = (Get-CimInstance Win32_ComputerSystem).Manufacturer } catch { }
    $model = ''
    try { $model = (Get-CimInstance Win32_ComputerSystem).Model } catch { }

    $svcs = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue
    foreach ($s in $svcs) {
        $blob = "$($s.Name) $($s.DisplayName) $($s.PathName)"
        if ($blob -match $script:OemVendorRegex -and $blob -match $script:OemKeywordRegex -and ($s.Name + ' ' + $s.DisplayName) -notmatch $script:OemExcludeRegex) {
            $found += @{ type='svc'; name=$s.Name; display=$s.DisplayName; state=$s.StartMode }
        }
    }
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue
    foreach ($t in $tasks) {
        $blob = "$($t.TaskPath) $($t.TaskName) $($t.Description)"
        if ($blob -match $script:OemVendorRegex -and $blob -match $script:OemKeywordRegex -and $t.TaskName -notmatch $script:OemExcludeRegex) {
            $found += @{ type='task'; name=($t.TaskPath + $t.TaskName); display=$t.TaskName; state=[string]$t.State }
        }
    }
    return @{ manufacturer=$manu; model=$model; items=$found }
}

# =========================================================================== #
#  Декларативные определения настроек
# =========================================================================== #
$script:Defs = New-Object System.Collections.Generic.List[object]
$script:DefSeq = @{}
# У каждой настройки есть свой номер вида telemetry#3 — по нему интерфейс
# может отключить отдельный пункт внутри модуля.
function Def {
    # ОСТОРОЖНО: имена переменных в PowerShell регистронезависимы. Счётчик
    # раньше звался $n и затирал параметр $N — в реестр вместо AllowTelemetry
    # писалось значение с именем «0». Любая локальная переменная здесь обязана
    # отличаться от имён параметров не только регистром.
    param($M, $T, $P, $N, $V, $Type = 'DWord', $C = '', $Min = 0)
    $seq = 0
    if ($script:DefSeq.ContainsKey($M)) { $seq = [int]$script:DefSeq[$M] }
    $script:DefSeq[$M] = $seq + 1
    # Повтор в одном разделе (две задачи Proxy и DmClientOnScenarioDownload
    # в списке служб) давал две одинаковые строки и считался дважды. Номер
    # всё равно занимаем: по номерам профили помнят снятые пункты, и сдвиг
    # переставил бы их на соседей.
    foreach ($x in $script:Defs) {
        if ($x.M -eq $M -and $x.T -eq $T -and "$($x.P)" -eq "$P" -and "$($x.N)" -eq "$N") { return }
    }
    $script:Defs.Add(@{ M=$M; T=$T; P=$P; N=$N; V=$V; Type=$Type; C=$C; Min=[int]$Min
                        Id=("{0}#{1}" -f $M, $seq) })
}

$dc  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
Def 'telemetry' 'reg' $dc 'AllowTelemetry' 0 'DWord' 'уровень телеметрии — минимальный'
Def 'telemetry' 'reg' $dc 'MaxTelemetryAllowed' 1 'DWord' 'потолок телеметрии'
Def 'telemetry' 'reg' $dc 'AllowDeviceNameInTelemetry' 0 'DWord' 'не отправлять имя устройства'
Def 'telemetry' 'reg' $dc 'DoNotShowFeedbackNotifications' 1 'DWord' 'не запрашивать отзывы'
Def 'telemetry' 'reg' $dc 'LimitDiagnosticLogCollection' 1 'DWord' 'не собирать диагностические логи'
Def 'telemetry' 'reg' $dc 'LimitDumpCollection' 1 'DWord' 'не собирать дампы памяти'
Def 'telemetry' 'reg' $dc 'DisableOneSettingsDownloads' 1 'DWord' 'отключить загрузку конфигураций OneSettings'
Def 'telemetry' 'reg' $dc 'AllowCommercialDataPipeline' 0 'DWord' 'отключить коммерческий канал данных'
Def 'telemetry' 'reg' $dc 'AllowUpdateComplianceProcessing' 0 'DWord' 'отключить Update Compliance'
Def 'telemetry' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 'DWord' 'без рекомендаций на основе диагностики'
Def 'telemetry' 'reg' 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0 'DWord' 'опросы Центра отзывов — выкл'
Def 'telemetry' 'reg' 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Settings\AllowExperimentation' 'value' 0 'DWord' 'эксперименты Microsoft — выкл'
# Телеметрия совместимости живёт отдельно от DiagTrack: опись программ,
# оценщик совместимости и запись действий пользователя шлют свои данные.
Def 'telemetry' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0 'DWord' 'программа улучшения качества (CEIP) — выкл'
Def 'telemetry' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'AITEnable' 0 'DWord' 'телеметрия совместимости приложений — выкл'
Def 'telemetry' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1 'DWord' 'опись установленных программ — выкл'
Def 'telemetry' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableUAR' 1 'DWord' 'запись действий пользователя (Steps Recorder) — выкл'
Def 'telemetry' 'reg' 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1 'DWord' 'персонализация по диагностике — запрет политикой'

Def 'errors' 'reg' 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1 'DWord' 'отправка отчётов об ошибках — выкл'
Def 'errors' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1 'DWord' 'то же, политикой'
Def 'errors' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'DontSendAdditionalData' 1 'DWord' 'не отправлять дополнительные данные'

$cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$cc  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
Def 'ads' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 'DWord' 'рекламный ID — выкл'
Def 'ads' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1 'DWord' 'рекламный ID заблокирован политикой'
Def 'ads' 'reg' $cdm 'SystemPaneSuggestionsEnabled' 0 'DWord' 'реклама приложений в меню Пуск'
Def 'ads' 'reg' $cdm 'SilentInstalledAppsEnabled' 0 'DWord' 'тихая установка рекламных приложений'
Def 'ads' 'reg' $cdm 'PreInstalledAppsEnabled' 0 'DWord' 'предустановка партнёрских приложений'
Def 'ads' 'reg' $cdm 'OemPreInstalledAppsEnabled' 0 'DWord' 'предустановка приложений OEM'
Def 'ads' 'reg' $cdm 'SoftLandingEnabled' 0 'DWord' 'всплывающие подсказки-реклама'
Def 'ads' 'reg' $cdm 'RotatingLockScreenOverlayEnabled' 0 'DWord' 'реклама на экране блокировки'
Def 'ads' 'reg' $cdm 'SubscribedContent-338388Enabled' 0 'DWord' 'предложения в меню Пуск'
Def 'ads' 'reg' $cdm 'SubscribedContent-338389Enabled' 0 'DWord' 'советы и подсказки Windows'
Def 'ads' 'reg' $cdm 'SubscribedContent-338393Enabled' 0 'DWord' 'предложения в Параметрах'
Def 'ads' 'reg' $cdm 'SubscribedContent-353694Enabled' 0 'DWord' 'предложения в Параметрах (2)'
Def 'ads' 'reg' $cdm 'SubscribedContent-353696Enabled' 0 'DWord' 'предложения в Параметрах (3)'
Def 'ads' 'reg' $cdm 'SubscribedContent-310093Enabled' 0 'DWord' 'приветственные экраны после обновлений'
Def 'ads' 'reg' $cdm 'ContentDeliveryAllowed' 0 'DWord' 'доставка рекламного контента'
Def 'ads' 'reg' $cc 'DisableWindowsConsumerFeatures' 1 'DWord' 'авто-установка игр и промо-приложений'
Def 'ads' 'reg' $cc 'DisableCloudOptimizedContent' 1 'DWord' 'облачный «оптимизированный» контент'
Def 'ads' 'reg' $cc 'DisableConsumerAccountStateContent' 1 'DWord' 'реклама подписок Microsoft'
Def 'ads' 'reg' $cc 'DisableSoftLanding' 1 'DWord' 'подсказки Windows'
Def 'ads' 'reg' $cc 'DisableWindowsSpotlightFeatures' 1 'DWord' 'Windows Spotlight'
Def 'ads' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0 'DWord' 'рекомендации в меню Пуск'
Def 'ads' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0 'DWord' 'реклама OneDrive в Проводнике'
Def 'ads' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0 'DWord' '«Получите больше от Windows» после обновлений — выкл'
# Найдены в каталоге политик Windows (PolicyManager): реклама и «интересное»,
# которые программа раньше не трогала. Пользовательские — в HKCU.
$ccu = 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent'
Def 'ads' 'reg' $ccu 'DisableThirdPartySuggestions' 1 'DWord' 'предложения сторонних приложений в «интересном» — выкл'
Def 'ads' 'reg' $ccu 'DisableWindowsSpotlightOnActionCenter' 1 'DWord' '«интересное» в центре уведомлений — выкл'
Def 'ads' 'reg' $ccu 'DisableWindowsSpotlightOnSettings' 1 'DWord' '«интересное» в Параметрах — выкл'
Def 'ads' 'reg' $ccu 'DisableWindowsSpotlightWindowsWelcomeExperience' 1 'DWord' 'приветственная реклама после обновлений — выкл'
Def 'ads' 'reg' $ccu 'DisableSpotlightCollectionOnDesktop' 1 'DWord' 'обои «Windows: интересное» на рабочем столе — выкл'
# Экран «Закрепите Copilot» при входе (ShellAppRuntime.exe, рекламные блоки 88000325/88000326)
Def 'ads' 'reg' $cc 'DisableCopilotPinScreen' 1 'DWord' 'экран «Закрепите Copilot» при входе — выкл'
# Реклама приложений в окне «Поделиться» (SharePickerUI.dll)
Def 'ads' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\ShareSheet' 'DisableShareAppPromotions' 1 'DWord' 'реклама приложений в окне «Поделиться» — выкл'
# Блок «Справка из интернета» в «Параметрах»: при открытии страницы приложение
# отправляет POST на www.bing.com/RelatedSearch с тем, какую страницу вы
# смотрите. Найдено записью Windows 11 с программой на максимуме.
Def 'ads' 'regpol' 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'AllowOnlineTips' 0 'DWord' 'советы из интернета в «Параметрах» (запросы к Bing) — выкл'

$sys = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
Def 'activity' 'reg' $sys 'EnableActivityFeed' 0 'DWord' 'лента активности — выкл'
Def 'activity' 'reg' $sys 'PublishUserActivities' 0 'DWord' 'не публиковать активность'
Def 'activity' 'reg' $sys 'UploadUserActivities' 0 'DWord' 'не выгружать активность в облако'
Def 'activity' 'reg' $sys 'AllowClipboardHistory' 0 'DWord' 'история буфера обмена — выкл'
Def 'activity' 'reg' $sys 'AllowCrossDeviceClipboard' 0 'DWord' 'синхронизация буфера между устройствами — выкл'
Def 'activity' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0 'DWord' 'Пуск: не отслеживать запуск программ'
Def 'activity' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SmartActionPlatform\SmartClipboard' 'Disabled' 1 'DWord' 'буфер обмена: «предлагаемые действия» — выкл'

Def 'input' 'reg' 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1 'DWord' 'не собирать набранный текст'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1 'DWord' 'не собирать рукописный ввод'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0 'DWord' 'не собирать контакты'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0 'DWord' 'персонализация ввода — отказ'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0 'DWord' 'облачное распознавание речи — выкл'
Def 'input' 'reg' 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1 'DWord' 'не отдавать сайтам список языков'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\appDiagnostics' 'Value' 'Deny' 'String' 'приложениям запрещена диагностика других приложений'
Def 'input' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC' 'PreventHandwritingDataSharing' 1 'DWord' 'не отправлять образцы рукописного ввода'
Def 'input' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports' 'PreventHandwritingErrorReports' 1 'DWord' 'не отправлять отчёты об ошибках распознавания рукописи'

$su = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
$sm = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
Def 'search' 'reg' $su 'BingSearchEnabled' 0 'DWord' 'поиск Bing в меню Пуск — выкл'
Def 'search' 'reg' $su 'CortanaConsent' 0 'DWord' 'согласие Cortana снято'
Def 'search' 'reg' $su 'DeviceHistoryEnabled' 0 'DWord' 'история поиска на устройстве — выкл'
Def 'search' 'reg' $su 'HistoryViewEnabled' 0 'DWord' 'показ истории поиска — выкл'
Def 'search' 'reg' $sm 'AllowCortana' 0 'DWord' 'Cortana — выкл'
Def 'search' 'reg' $sm 'DisableWebSearch' 1 'DWord' 'веб-поиск из Пуска — выкл'
Def 'search' 'reg' $sm 'ConnectedSearchUseWeb' 0 'DWord' 'не обращаться к вебу при поиске'
Def 'search' 'reg' $sm 'AllowSearchToUseLocation' 0 'DWord' 'поиск не использует геолокацию'
Def 'search' 'reg' $sm 'AllowCloudSearch' 0 'DWord' 'облачный поиск по OneDrive/Outlook — выкл'
Def 'search' 'reg' $sm 'EnableDynamicContentInWSB' 0 'DWord' 'рекламные подсказки в поле поиска — выкл'
Def 'search' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDeviceSearchHistoryEnabled' 0 'DWord' 'история поиска на устройстве (Параметры) — выкл'

$ai = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
Def 'copilot' 'reg' 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 'DWord' 'Windows Copilot — выкл' 22000
Def 'copilot' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 'DWord' 'Windows Copilot — выкл для всех' 22000
Def 'copilot' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0 'DWord' 'кнопка Copilot на панели задач — убрать' 22000
Def 'copilot' 'reg' $ai 'DisableAIDataAnalysis' 1 'DWord' 'Recall (снимки экрана) — выкл' 26100
Def 'copilot' 'reg' $ai 'AllowRecallEnablement' 0 'DWord' 'запрет включения Recall' 26100
Def 'copilot' 'reg' 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1 'DWord' 'Recall — выкл для пользователя' 26100
Def 'copilot' 'reg' $ai 'AllowRecallExport' 0 'DWord' 'Recall: выгрузка снимков — запрещена' 26100

# Весь ИИ Windows
Def 'ai' 'reg' $ai 'DisableClickToDo' 1 'DWord' 'Click to Do — выкл' 26100
Def 'ai' 'reg' $ai 'TurnOffSavingSnapshots' 1 'DWord' 'сохранение снимков экрана — выкл' 26100
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Notepad' 'DisableAIFeatures' 1 'DWord' 'Copilot в Блокноте — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Paint' 'DisableCocreator' 1 'DWord' 'Paint Cocreator — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Paint' 'DisableGenerativeFill' 1 'DWord' 'Paint: генеративная заливка — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Paint' 'DisableImageCreator' 1 'DWord' 'Paint Image Creator — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'CopilotPageContext' 0 'DWord' 'Edge: Copilot не читает страницы'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'CopilotCDPPageContext' 0 'DWord' 'Edge: Copilot без контекста вкладок'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'ComposeInlineEnabled' 0 'DWord' 'Edge: ИИ-подсказки при наборе — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'EdgeHistoryAISearchEnabled' 0 'DWord' 'Edge: ИИ-поиск по истории — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'EdgeEntityExtractionEnabled' 0 'DWord' 'Edge: извлечение сущностей — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'Microsoft365CopilotChatIconEnabled' 0 'DWord' 'Edge: значок Copilot — убрать'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableGraphRecentItems' 1 'DWord' 'Проводник: облачные «недавние» — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'HideRecommendedSection' 1 'DWord' 'Пуск: раздел «Рекомендуем» — скрыть' 22000
Def 'ai' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowRecommendations' 0 'DWord' 'Проводник: рекомендации в «Главной» — выкл' 22000
# Политика выключает сам Click to Do, но задача по-прежнему скачивает его
# модели ИИ. Администратору Windows её не отдаёт — отключается от SYSTEM.
Def 'ai' 'task' '\Microsoft\Windows\WindowsAI\ClickToDo\ModelCachingUpdate' '' 'Disabled' '' 'Click to Do: скачивание моделей ИИ — выкл' 26100
# ИИ-агенты работают с Windows через MCP-«коннекторы» (служба McpManagementService,
# доступ выдаёт CapabilityAccessManager). 2 — запретить (шаблон CAM_AI.admx).
Def 'ai' 'reg' $ai 'ConfigureAgentConnectors' 2 'DWord' 'ИИ-агенты: доступ к файлам и настройкам через MCP — запрещён' 26100
Def 'ai' 'reg' $ai 'DisableSettingsAgent' 1 'DWord' 'ИИ-агент в Параметрах — выкл' 26100

$e = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
Def 'edge' 'reg' $e 'MetricsReportingEnabled' 0 'DWord' 'статистика использования — выкл'
Def 'edge' 'reg' $e 'DiagnosticData' 0 'DWord' 'диагностические данные — выкл'
Def 'edge' 'reg' $e 'SendSiteInfoToImproveServices' 0 'DWord' 'не отправлять адреса сайтов'
Def 'edge' 'reg' $e 'PersonalizationReportingEnabled' 0 'DWord' 'персонализация рекламы — выкл'
Def 'edge' 'reg' $e 'UserFeedbackAllowed' 0 'DWord' 'отзывы — выкл'
Def 'edge' 'reg' $e 'EdgeShoppingAssistantEnabled' 0 'DWord' 'шопинг-ассистент — выкл'
Def 'edge' 'reg' $e 'AlternateErrorPagesEnabled' 0 'DWord' 'не отправлять ошибочные адреса'
Def 'edge' 'reg' $e 'SearchSuggestEnabled' 0 'DWord' 'подсказки поиска (отправка ввода) — выкл'
Def 'edge' 'reg' $e 'HubsSidebarEnabled' 0 'DWord' 'боковая панель Copilot — выкл'
Def 'edge' 'reg' $e 'TrackingPrevention' 2 'DWord' 'блокировка отслеживания — сбалансированная'

Def 'delivery' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0 'DWord' 'не раздавать обновления в интернет'

$loc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'
Def 'location' 'reg' $loc 'DisableLocation' 1 'DWord' 'служба геолокации — выкл'
Def 'location' 'reg' $loc 'DisableWindowsLocationProvider' 1 'DWord' 'поставщик местоположения Windows — выкл'
Def 'location' 'reg' 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String' 'доступ приложений к местоположению — запрещён'
Def 'location' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice' 'AllowFindMyDevice' 0 'DWord' '«Поиск устройства» (отправка координат) — выкл'
Def 'location' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsAccessLocation' 2 'DWord' 'приложениям запрещено местоположение (политика)'

# Разрешения приложений — политикой, а не переключателями. Переключатель в
# ConsentStore может вернуть кто угодно: Windows после обновления, установщик,
# сам человек одним щелчком. Политика AppPrivacy стоит насмерть. Сюда же входит
# доступ к сведениям учётной записи — через него приложения узнают возраст
# пользователя (Windows Age API): без этого права вызов падает с E_ACCESSDENIED.
$ap = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
Def 'apppriv' 'reg' $ap 'LetAppsAccessAccountInfo' 2 'DWord' 'сведения учётной записи и возраст (Age API) — запрещены'
Def 'apppriv' 'reg' $ap 'LetAppsAccessContacts' 2 'DWord' 'контакты — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessCalendar' 2 'DWord' 'календарь — запрещён приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessCallHistory' 2 'DWord' 'журнал звонков — запрещён приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessEmail' 2 'DWord' 'почта — запрещена приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessMessaging' 2 'DWord' 'сообщения — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessPhone' 2 'DWord' 'звонки — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessTasks' 2 'DWord' 'задачи и планы — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessNotifications' 2 'DWord' 'чтение уведомлений — запрещено приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessMotion' 2 'DWord' 'данные о движении — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessRadios' 2 'DWord' 'управление радиомодулями — запрещено приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsSyncWithDevices' 2 'DWord' 'обмен с устройствами — запрещён приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessTrustedDevices' 2 'DWord' 'доверенные устройства — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsGetDiagnosticInfo' 2 'DWord' 'диагностика других приложений — запрещена'
Def 'apppriv' 'reg' $ap 'LetAppsActivateWithVoice' 2 'DWord' 'голосовая активация приложений — запрещена'
Def 'apppriv' 'reg' $ap 'LetAppsActivateWithVoiceAboveLock' 2 'DWord' 'голосовая активация на экране блокировки — запрещена'
Def 'apppriv' 'reg' $ap 'LetAppsAccessSystemAIModels' 2 'DWord' 'встроенные ИИ-модели Windows — запрещены приложениям' 26100

# Камера, микрофон и фоновая работа — отдельно: без них приложения из магазина
# теряют эти функции. Обычных программ (браузеров, мессенджеров) не касается.
Def 'apphw' 'reg' $ap 'LetAppsAccessCamera' 2 'DWord' 'камера — запрещена приложениям из магазина'
Def 'apphw' 'reg' $ap 'LetAppsAccessMicrophone' 2 'DWord' 'микрофон — запрещён приложениям из магазина'
Def 'apphw' 'reg' $ap 'LetAppsRunInBackground' 2 'DWord' 'фоновая работа приложений из магазина — запрещена'

# Что Windows скачивает и отправляет сама, без вашего запроса. Всё — из
# официального списка Microsoft «Manage connections from Windows operating
# system components to Microsoft services», только безопасные пункты.
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1 'DWord' 'не скачивать метаданные устройств'
Def 'network' 'reg' $sys 'EnableFontProviders' 0 'DWord' 'не скачивать шрифты по требованию'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds' 'AllowBuildPreview' 0 'DWord' 'сборки Insider — запрет'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Maps' 'AutoDownloadAndUpdateMapData' 0 'DWord' 'офлайн-карты: не обновлять сами'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Maps' 'AllowUntriggeredNetworkTrafficOnSettingsPage' 0 'DWord' 'офлайн-карты: без трафика на странице настроек'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Microsoft\OneDrive' 'PreventNetworkTrafficPreUserSignIn' 1 'DWord' 'OneDrive: не выходить в сеть до входа в систему'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Speech' 'AllowSpeechModelUpdate' 0 'DWord' 'не обновлять речевые модели'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageHealth' 'AllowDiskHealthModelUpdates' 0 'DWord' 'не скачивать модели здоровья дисков'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Messaging' 'AllowMessageSync' 0 'DWord' 'не синхронизировать сообщения с облаком'
Def 'network' 'reg' 'HKCU:\SOFTWARE\Microsoft\Messaging' 'CloudServiceSyncEnabled' 0 'DWord' 'облачная синхронизация сообщений — выкл'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TCPIP\v6Transition' 'Teredo_State' 'Disabled' 'String' 'Teredo (туннель IPv6 через Microsoft) — выкл'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config' 'AutoConnectAllowedOEM' 0 'DWord' 'Wi-Fi Sense — выкл'
Def 'network' 'task' '\Microsoft\Windows\Sustainability\PowerGridForecastTask' '' 'Disabled' '' 'не скачивать прогноз нагрузки энергосети'
# Магазин умеет ставить приложения на этот ПК по команде с сайта, без
# действий за компьютером (служба PushToInstall, pti.store.microsoft.com).
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\PushToInstall' 'DisablePushToInstall' 1 'DWord' 'установка приложений на этот ПК по команде с сайта — выкл'
# «Рекомендуемое устранение неполадок»: MitigationClient получает от
# Microsoft «исправления» (troubleshooting.microsoft.com/api/Mitigation)
# и применяет их сам. UserPreference = 1 — «не запускать».
Def 'network' 'reg' 'HKLM:\SOFTWARE\Microsoft\WindowsMitigation' 'UserPreference' 1 'DWord' 'не применять «исправления», присланные Microsoft'
Def 'network' 'task' '\Microsoft\Windows\Diagnosis\RecommendedTroubleshootingScanner' '' 'Disabled' '' 'задача RecommendedTroubleshootingScanner (поиск «исправлений» Microsoft)'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\ScriptedDiagnosticsProvider\Policy' 'EnableQueryRemoteServer' 0 'DWord' 'средства устранения неполадок не обращаются к серверам Microsoft'

# Облачная синхронизация и копия. Windows 11 без вопроса выгружает в облако
# Microsoft список ваших приложений («Архивация Windows»), сети Wi-Fi, язык,
# тему, настройки пера — и даже ваши ответы на вопросы о конфиденциальности.
# Всё найдено на чистой Windows 11 25H2; задачи отключаются и включаются
# обратно без последствий для системы.
$ss = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync'
Def 'cloudsync' 'reg' $ss 'DisableSettingSync' 2 'DWord' 'синхронизация параметров между устройствами — выкл'
Def 'cloudsync' 'reg' $ss 'DisableSettingSyncUserOverride' 1 'DWord' 'синхронизацию параметров не включить обратно в Параметрах'
Def 'cloudsync' 'task' '\Microsoft\Windows\AppListBackup\Backup' '' 'Disabled' '' 'копия списка приложений в облако — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\AppListBackup\BackupNonMaintenance' '' 'Disabled' '' 'внеплановая копия списка приложений — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\CloudRestore\Backup' '' 'Disabled' '' 'архивация Windows в облако — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\ConsentUX\UnifiedConsent\UnifiedConsentSyncTask' '' 'Disabled' '' 'синхронизация ваших согласий на сбор данных — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\WlanSvc\CDSSync' '' 'Disabled' '' 'синхронизация сетей Wi-Fi между устройствами — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\International\Synchronize Language Settings' '' 'Disabled' '' 'синхронизация языковых настроек — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\Shell\ThemesSyncedImageDownload' '' 'Disabled' '' 'скачивание обоев с других ваших устройств — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\input\syncpensettings' '' 'Disabled' '' 'синхронизация настроек пера — выкл'
# Само приложение «Архивация Windows» (CloudRestoreLauncher.dll, SyncSettings.dll)
Def 'cloudsync' 'reg' $ss 'EnableWindowsBackup' 0 'DWord' 'приложение «Архивация Windows» — выкл'

Def 'widgets' 'regpol' 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 'DWord' 'виджеты и лента новостей MSN — выкл' 22000
Def 'widgets' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 0 'DWord' 'кнопка виджетов на панели задач — убрать' 22000
Def 'widgets' 'regpol' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0 'DWord' 'лента новостей и интересов — выкл (запасной ключ)'
Def 'widgets' 'regpol' 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'DisableWidgetsBoard' 1 'DWord' 'панель виджетов — выкл' 22000
Def 'widgets' 'regpol' 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'DisableWidgetsOnLockScreen' 1 'DWord' 'виджеты на экране блокировки — выкл' 22000

$dfn = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'
Def 'defender' 'reg' $dfn 'SpyNetReporting' 0 'DWord' 'Защитник: облачная отправка MAPS — выкл'
Def 'defender' 'reg' $dfn 'SubmitSamplesConsent' 2 'DWord' 'Защитник: отправка образцов файлов — никогда'
# Служба ядра Защитника (MDCoreSvc) раз в час забирает с ecs.office.com около
# 130 удалённых настроек: включение функций, проверку запросов к ИИ-агентам,
# уведомления Microsoft 365. Проверено в виртуалке: с этой политикой обращения
# к ECS пропадают. Её же DisableCoreService1DSTelemetry отправку телеметрии
# не остановил — её закрывает hosts (mobile.events.data.microsoft.com).
Def 'defender' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Features' 'DisableCoreServiceECSIntegration' 1 'DWord' 'Защитник: удалённые настройки и эксперименты (ECS) — выкл'

Def 'services' 'svc' 'DiagTrack' '' 'Disabled' '' 'служба DiagTrack (телеметрия)'
Def 'services' 'svc' 'dmwappushservice' '' 'Disabled' '' 'служба dmwappushservice (WAP push)'
foreach ($tp in @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraisal',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
    '\Microsoft\Windows\Application Experience\PcaPatchDbTask',
    '\Microsoft\Windows\Application Experience\StartupAppTask',
    '\Microsoft\Windows\Application Experience\MareBackup',
    '\Microsoft\Windows\Application Experience\AitAgent',
    '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask',
    '\Microsoft\Windows\Customer Experience Improvement Program\BthSQM',
    '\Microsoft\Windows\Customer Experience Improvement Program\Uploader',
    '\Microsoft\Windows\Device Information\Device',
    '\Microsoft\Windows\Device Information\Device User',
    '\Microsoft\Windows\DiskFootprint\Diagnostics',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver',
    '\Microsoft\Windows\Maintenance\WinSAT',
    '\Microsoft\Windows\NetTrace\GatherNetworkInfo',
    '\Microsoft\Windows\PI\Sqm-Tasks',
    '\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem',
    '\Microsoft\Windows\Windows Error Reporting\ProcessQueuedCallHomeReports',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
    '\Microsoft\Windows\Clip\License Validation',
    '\Microsoft\Windows\CloudExperienceHost\CreateObjectTask',
    '\Microsoft\Windows\Shell\FamilySafetyMonitor',
    '\Microsoft\Windows\Shell\FamilySafetyRefreshTask',
    '\Microsoft\Windows\Speech\SpeechModelDownloadTask',
    '\Microsoft\Windows\Autochk\Proxy',
    # Появились в Windows 11 24H2–25H2. Оценщик совместимости «Exp» запускает
    # compattelrunner с DoScheduledTelemetryRun — старую задачу «Appraisal»
    # движок закрывал, а эта шла мимо. FeatureConfig\UsageData* — отчёты о том,
    # какими функциями вы пользуетесь.
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp',
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReporting',
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReceiver',
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing',
    '\Microsoft\Windows\Flighting\FeatureConfig\BootstrapUsageDataReporting',
    '\Microsoft\Windows\Flighting\FeatureConfig\GovernedFeatureUsageProcessing',
    '\Microsoft\Windows\Flighting\OneSettings\RefreshCache',
    '\Microsoft\Windows\Sustainability\SustainabilityTelemetry',
    '\Microsoft\Windows\PerformanceTrace\ShowFeedbackToast',
    '\Microsoft\Windows\Maps\MapsToastTask')) {
    Def 'services' 'task' $tp '' 'Disabled' '' ('задача ' + (Split-Path $tp -Leaf))
}
# Тоже из Windows 11 24H2–25H2, нашлись на чистой системе. InventorySvc
# работает постоянно и составляет опись установленных программ и
# оборудования для оценки совместимости и телеметрии. Usage and Quality
# Insights копит на диске «факты» о том, какими функциями вы пользуетесь,
# и выгружает их через телеметрию; её задача закрыта от администратора.
Def 'services' 'svc' 'InventorySvc' '' 'Disabled' '' 'служба InventorySvc (опись программ и оборудования)' 26100
Def 'services' 'task' '\Microsoft\Windows\UsageAndQualityInsights\UsageAndQualityInsights-MaintenanceTask' '' 'Disabled' '' 'задача UsageAndQualityInsights (сбор сведений об использовании)' 26100

$od = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
Def 'onedrive' 'reg' $od 'DisableFileSyncNGSC' 1 'DWord' 'OneDrive: синхронизация файлов — выкл'
Def 'onedrive' 'reg' $od 'DisableFileSync' 1 'DWord' 'OneDrive: старая синхронизация — выкл'
Def 'onedrive' 'reg' $od 'DisableMeteredNetworkFileSync' 1 'DWord' 'OneDrive: не синхронизировать по лимитной сети'
Def 'onedrive' 'reg' 'HKCU:\Software\Microsoft\OneDrive' 'DisablePersonalSync' 1 'DWord' 'OneDrive: личная синхронизация — выкл'
Def 'onedrive' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0 'DWord' 'OneDrive: реклама в Проводнике — выкл'
Def 'onedrive' 'taskglob' 'OneDrive*' '' 'Disabled' '' 'OneDrive: задачи обновления — выкл'

# Сессии трассировки запускаются при загрузке самой Windows и пишут телеметрию
# независимо от службы DiagTrack. Start = 0 отключает сборщик.
$al = 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger'
Def 'etw' 'regif' "$al\AutoLogger-Diagtrack-Listener" 'Start' 0 'DWord' 'главный сборщик телеметрии (Diagtrack-Listener)'
Def 'etw' 'regif' "$al\Diagtrack-Listener" 'Start' 0 'DWord' 'сборщик Diagtrack (второй вариант)'
Def 'etw' 'regif' "$al\SQMLogger" 'Start' 0 'DWord' 'сборщик программы улучшения качества (SQM)'
Def 'etw' 'regif' "$al\WiFiSession" 'Start' 0 'DWord' 'трассировка сеансов Wi-Fi'
Def 'etw' 'regif' "$al\CloudExperienceHostOobe" 'Start' 0 'DWord' 'трассировка первоначальной настройки'
Def 'etw' 'regif' "$al\DiagLog" 'Start' 0 'DWord' 'диагностический журнал DiagLog'
Def 'etw' 'regif' "$al\UBPM" 'Start' 0 'DWord' 'трассировка планировщика (UBPM)'
Def 'etw' 'regif' "$al\Microsoft-Windows-AssignedAccess-Trace" 'Start' 0 'DWord' 'трассировка AssignedAccess'
Def 'etw' 'regif' "$al\AppModel" 'Start' 0 'DWord' 'трассировка запуска приложений (AppModel)'
Def 'etw' 'reg' 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener' 'Enabled' 0 'DWord' 'запрет включения сборщика телеметрии'

Def 'hosts' 'hosts' '' '' '' '' 'блок телеметрийных доменов в hosts'

# Номер устройства в учётной записи Microsoft (GDID). Его выдаёт login.live.com
# при входе, CDPSvc регистрирует компьютер в каталоге устройств Microsoft, а
# DoSvc (Delivery Optimization) сообщает номер обратно. Смена IP и VPN на него
# не влияют; DiagTrack в этой цепочке не участвует, поэтому отключённая
# телеметрия его не останавливает. Стирать номер бесполезно: он привязан к
# учётной записи и возвращается с серверов тем же самым. Остаётся не дать ему
# уходить. DoSvc диспетчер служб не отдаёт даже администратору («Отказано в
# доступе»), поэтому службы отключаются там, где диспетчер хранит их
# настройку, — в реестре: запись идёт в журнал и откатывается как обычная.
# Разбор цепочки: github.com/SmtimesIWndr/gdid-reversal и github.com/Korben00/no-gdid.
$svcRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services'
Def 'gdid' 'regsvc' "$svcRoot\CDPSvc" 'Start' 4 'DWord' 'служба CDPSvc: регистрация компьютера в каталоге устройств Microsoft — выкл'
Def 'gdid' 'regsvc' "$svcRoot\CDPUserSvc" 'Start' 4 'DWord' 'служба CDPUserSvc: то же для каждого пользователя — выкл'
Def 'gdid' 'regsvc' "$svcRoot\DoSvc" 'Start' 4 'DWord' 'служба DoSvc (Delivery Optimization): передача номера устройства — выкл'
Def 'gdid' 'gdidhosts' '' '' '' '' 'серверы каталога устройств и Delivery Optimization — в hosts'

# Запрет выдачи номера. Новый номер выдаёт login.live.com при первом же
# обращении устройства — пока сервер открыт, стёртый номер сменяется новым.
# Закрыв его, можно стереть номер насовсем. Цена — учётная запись Microsoft:
# вход в неё, Магазин, Xbox и OneDrive перестают работать, поэтому при входе
# в Windows через неё модуль не применяется. Что и где стирается — разбор
# github.com/yegors/deGDID (проверено на Windows 11 25H2, сборка 26200).
Def 'gdidlock' 'gdidlockhosts' '' '' '' '' 'сервер выдачи номера (login.live.com, account.live.com) — в hosts'
Def 'gdidlock' 'fwsvc' 'wlidsvc' '' '' '' 'исходящие службы учётных записей Microsoft (wlidsvc) — блок'
Def 'gdidlock' 'gdidwipe' '' '' '' '' 'номер устройства стёрт отовсюду, где Windows его хранит'

# Блокировка самих адресов: hosts телеметрия обходит через шифрованный DNS
# и зашитые IP, поэтому адреса блокируются правилом брандмауэра.
Def 'fwips' 'fwips' '' '' '' '' 'блокировка адресов сбора телеметрии'

# Шифрованный DNS (DoH) позволяет обойти hosts и блокировку по доменам
Def 'doh' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'DoHPolicy' 1 'DWord' 'Windows: шифрованный DNS — запретить'
Def 'doh' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DnsOverHttpsMode' 'off' 'String' 'Edge: шифрованный DNS — выкл'
Def 'doh' 'reg' 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'DnsOverHttpsMode' 'off' 'String' 'Chrome: шифрованный DNS — выкл'

# Брандмауэр: исходящие соединения служб и программ телеметрии
Def 'firewall' 'fwsvc' 'DiagTrack' '' '' '' 'исходящие DiagTrack — блок'
Def 'firewall' 'fwsvc' 'dmwappushservice' '' '' '' 'исходящие dmwappushservice — блок'
Def 'firewall' 'fwsvc' 'WerSvc' '' '' '' 'исходящие Windows Error Reporting — блок'
Def 'firewall' 'fwapp' "$env:SystemRoot\System32\CompatTelRunner.exe" '' '' '' 'исходящие CompatTelRunner — блок'
Def 'firewall' 'fwapp' "$env:SystemRoot\System32\DeviceCensus.exe" '' '' '' 'исходящие DeviceCensus — блок'
Def 'firewall' 'fwapp' "$env:SystemRoot\System32\wsqmcons.exe" '' '' '' 'исходящие wsqmcons (CEIP) — блок'

# --- Сторонние программы ---------------------------------------------------- #
Def 'app_nvidia' 'reg' 'HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2\Client' 'OptInOrOutPreference' 0 'DWord' 'NVIDIA: участие в сборе данных — отказ'
Def 'app_nvidia' 'reg' 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS' 'EnableRID44231' 0 'DWord' 'NVIDIA: телеметрия FTS (1) — выкл'
Def 'app_nvidia' 'reg' 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS' 'EnableRID64640' 0 'DWord' 'NVIDIA: телеметрия FTS (2) — выкл'
Def 'app_nvidia' 'reg' 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS' 'EnableRID66610' 0 'DWord' 'NVIDIA: телеметрия FTS (3) — выкл'
Def 'app_nvidia' 'svcopt' 'NvTelemetryContainer' '' 'Disabled' '' 'NVIDIA: служба NvTelemetryContainer'
Def 'app_nvidia' 'taskglob' 'NvTm*' '' 'Disabled' '' 'NVIDIA: задачи телеметрии NvTm*'

Def 'app_vscode' 'vscode' 'telemetry.telemetryLevel' '' 'off' '' 'VS Code: телеметрия — выкл'
Def 'app_vscode' 'vscode' 'workbench.enableExperiments' '' $false '' 'VS Code: эксперименты — выкл'
Def 'app_vscode' 'vscode' 'telemetry.feedback.enabled' '' $false '' 'VS Code: опросы — выкл'

$ch = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
Def 'app_chrome' 'reg' $ch 'MetricsReportingEnabled' 0 'DWord' 'Chrome: статистика использования — выкл'
Def 'app_chrome' 'reg' $ch 'UrlKeyedAnonymizedDataCollectionEnabled' 0 'DWord' 'Chrome: отправка адресов сайтов — выкл'
Def 'app_chrome' 'reg' $ch 'AlternateErrorPagesEnabled' 0 'DWord' 'Chrome: не отправлять ошибочные адреса'
Def 'app_chrome' 'reg' $ch 'SpellCheckServiceEnabled' 0 'DWord' 'Chrome: облачная проверка орфографии — выкл'
Def 'app_chrome' 'reg' $ch 'PrivacySandboxAdMeasurementEnabled' 0 'DWord' 'Chrome: измерение рекламы — выкл'
Def 'app_chrome' 'reg' $ch 'PrivacySandboxAdTopicsEnabled' 0 'DWord' 'Chrome: рекламные темы — выкл'
Def 'app_chrome' 'reg' $ch 'PrivacySandboxSiteEnabledAdsEnabled' 0 'DWord' 'Chrome: реклама по сайтам — выкл'
Def 'app_chrome' 'reg' $ch 'PrivacySandboxPromptEnabled' 0 'DWord' 'Chrome: окно Privacy Sandbox — выкл'

Def 'app_firefox' 'firefox' 'DisableTelemetry' '' $true '' 'Firefox: телеметрия — выкл'
Def 'app_firefox' 'firefox' 'DisableFirefoxStudies' '' $true '' 'Firefox: исследования — выкл'

$of = 'HKCU:\Software\Policies\Microsoft\office\16.0\common'
Def 'app_office' 'reg' "$of\clienttelemetry" 'SendTelemetry' 3 'DWord' 'Office: телеметрия — ни базовой, ни расширенной'
Def 'app_office' 'reg' 'HKCU:\Software\Policies\Microsoft\office\common\clienttelemetry' 'DisableTelemetry' 1 'DWord' 'Office: телеметрия клиента — выкл'
Def 'app_office' 'reg' $of 'sendcustomerdata' 0 'DWord' 'Office: данные клиента — не отправлять'
Def 'app_office' 'reg' "$of\feedback" 'enabled' 0 'DWord' 'Office: отзывы — выкл'
Def 'app_office' 'reg' "$of\feedback" 'includescreenshot' 0 'DWord' 'Office: снимки экрана в отзывах — выкл'

Def 'app_devtools' 'env' 'POWERSHELL_TELEMETRY_OPTOUT' '' '1' '' 'PowerShell 7: телеметрия — выкл'
Def 'app_devtools' 'env' 'POWERSHELL_UPDATECHECK' '' 'Off' '' 'PowerShell 7: проверка обновлений — выкл'
Def 'app_devtools' 'env' 'DOTNET_CLI_TELEMETRY_OPTOUT' '' '1' '' '.NET SDK: телеметрия — выкл'

Def 'app_vs' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\VisualStudio\SQM' 'OptIn' 0 'DWord' 'Visual Studio: программа улучшения качества — отказ'
Def 'app_vs' 'reg' 'HKCU:\Software\Microsoft\VisualStudio\Telemetry' 'TurnOffSwitch' 1 'DWord' 'Visual Studio: телеметрия — выкл'
Def 'app_vs' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\VisualStudio\Feedback' 'DisableFeedbackDialog' 1 'DWord' 'Visual Studio: окно отзывов — выкл'

$script:ModuleOrder = @('telemetry','errors','activity','input','edge','delivery','location','apppriv','network','cloudsync','ads','widgets','search','copilot','ai',
                        'defender','apphw','onedrive','services','etw','hosts','gdid','gdidlock','firewall','fwips','doh','buffer','app_nvidia','app_vscode','app_chrome','app_firefox',
                        'app_office','app_devtools','app_vs','oem','cleanup','startup')
$script:ModuleTitles = @{
    telemetry='Телеметрия и диагностика'; errors='Отчёты об ошибках'; activity='История активности и буфер обмена';
    input='Персонализация ввода, рукописный ввод, речь'; edge='Microsoft Edge'; delivery='Раздача обновлений другим ПК';
    location='Геолокация и поиск устройства'; apppriv='Разрешения приложений (запрет политикой)';
    network='Фоновые обращения Windows в сеть'; cloudsync='Облачная синхронизация и копия'; apphw='Камера, микрофон и фоновая работа приложений'; ads='Рекламный ID и реклама в интерфейсе'; widgets='Виджеты и лента новостей';
    search='Поиск: Bing, Cortana, облако'; copilot='Copilot и Recall';
    ai='ИИ-функции Windows'; defender='Защитник: облако и образцы'; etw='Сессии трассировки телеметрии'; onedrive='OneDrive: синхронизация и реклама'; services='Службы и задачи телеметрии'; hosts='Блокировка телеметрийных доменов (hosts)';
    gdid='Номер устройства в учётной записи Microsoft (GDID)'; gdidlock='Запрет выдачи номера устройства';
    firewall='Брандмауэр: блокировка служб телеметрии'; fwips='Брандмауэр: адреса сбора телеметрии'; doh='Шифрованный DNS (обход блокировки)'; buffer='Неотправленная телеметрия'; app_nvidia='NVIDIA';
    app_vscode='Visual Studio Code'; app_chrome='Google Chrome'; app_firefox='Mozilla Firefox'; app_office='Microsoft Office';
    app_devtools='PowerShell 7 / .NET SDK'; app_vs='Visual Studio'; oem='Компоненты сбора данных производителя';
    cleanup='Чистка временных файлов'; startup='Автозагрузка (отчёт)'
}

# --------------------------------------------------------------------------- #
#  Цена каждой настройки. Уровень: safe — ничего заметного не ломается,
#  limited — какая-то функция Windows перестанет работать, caution — может
#  задеть то, что вам нужно. По умолчанию уровень — как у модуля; отдельные
#  пункты уточнены ниже, вместе с тем, что именно перестанет работать.
#  Ключ — название настройки, как в Def.
# --------------------------------------------------------------------------- #
$script:ModuleRisk = @{
    location = 'limited'; apppriv = 'limited'; apphw = 'limited'; onedrive = 'limited'; services = 'limited'
    hosts = 'limited'; firewall = 'limited'; fwips = 'caution'; doh = 'limited'; defender = 'caution'
    gdid = 'limited'; gdidlock = 'caution'; oem = 'limited'; cloudsync = 'limited'
}
$script:DefRisk = @{
    'уровень телеметрии — минимальный' = 'safe'
    'служба DiagTrack (телеметрия)' = 'safe'
    'задача License Validation' = 'caution'
    'Teredo (туннель IPv6 через Microsoft) — выкл' = 'limited'
    'история буфера обмена — выкл' = 'limited'
    'не скачивать прогноз нагрузки энергосети' = 'safe'
    'Click to Do: скачивание моделей ИИ — выкл' = 'safe'
    'задача UsageAndQualityInsights (сбор сведений об использовании)' = 'safe'
    'синхронизация ваших согласий на сбор данных — выкл' = 'safe'
    'скачивание обоев с других ваших устройств — выкл' = 'safe'
    'не применять «исправления», присланные Microsoft' = 'limited'
    'средства устранения неполадок не обращаются к серверам Microsoft' = 'limited'
    'Защитник: удалённые настройки и эксперименты (ECS) — выкл' = 'limited'
    'обои «Windows: интересное» на рабочем столе — выкл' = 'limited'
    'ИИ-агенты: доступ к файлам и настройкам через MCP — запрещён' = 'limited'
    'приложение «Архивация Windows» — выкл' = 'limited'
    'облачное распознавание речи — выкл' = 'limited'
}
$script:DefNotes = @{
    'уровень телеметрии — минимальный' = 'На Home и Pro Windows всё равно оставит «обязательные данные»: полностью выключает только Enterprise и Education.'
    'история буфера обмена — выкл' = 'Win+V перестанет показывать историю скопированного.'
    'синхронизация буфера между устройствами — выкл' = 'Буфер обмена не будет общим с телефоном и другими компьютерами.'
    'облачное распознавание речи — выкл' = 'Голосовой ввод и диктовка через облако Microsoft перестанут работать.'
    'веб-поиск из Пуска — выкл' = 'Поиск в Пуске будет искать только на компьютере, без результатов из интернета.'
    'служба геолокации — выкл' = 'Карты, погода и автоматический часовой пояс не узнают, где вы.'
    '«Поиск устройства» (отправка координат) — выкл' = 'Потерянный ноутбук нельзя будет найти через «Поиск устройства».'
    'сведения учётной записи и возраст (Age API) — запрещены' = 'Приложения из Магазина не узнают ваше имя, аватар и возраст.'
    'почта — запрещена приложениям' = 'Почта из Магазина не увидит ваши письма, пока вы не разрешите её вручную.'
    'календарь — запрещён приложениям' = 'Календарь из Магазина не увидит ваши события, пока вы не разрешите его вручную.'
    'обмен с устройствами — запрещён приложениям' = 'Приложения не смогут связываться с телефоном и устройствами Bluetooth без вашего разрешения.'
    'камера — запрещена приложениям из магазина' = 'Камера перестанет работать в приложениях Магазина. В браузерах и обычных программах — работает.'
    'микрофон — запрещён приложениям из магазина' = 'Микрофон перестанет работать в приложениях Магазина. В браузерах и обычных программах — работает.'
    'фоновая работа приложений из магазина — запрещена' = 'Приложения из Магазина не будут присылать уведомления и обновляться, пока закрыты.'
    'Teredo (туннель IPv6 через Microsoft) — выкл' = 'Сетевые игры Xbox, которым нужен Teredo, могут не подключаться.'
    'OneDrive: синхронизация файлов — выкл' = 'OneDrive перестанет синхронизировать файлы. Сами файлы на диске остаются.'
    'служба dmwappushservice (WAP push)' = 'Нужна, если компьютером управляет организация (MDM). Дома не используется.'
    'задача License Validation' = 'Проверяет лицензии приложений Магазина. Если купленные приложения перестанут запускаться — снимите этот пункт.'
    'задача FamilySafetyMonitor' = 'Родительский контроль Microsoft Family перестанет работать.'
    'Защитник: облачная отправка MAPS — выкл' = 'Защитник теряет облачную проверку: новые угрозы он будет узнавать позже.'
    'Защитник: отправка образцов файлов — никогда' = 'Подозрительные файлы не уйдут на анализ в Microsoft.'
    'Windows: шифрованный DNS — запретить' = 'Ваши DNS-запросы снова видит провайдер. Зато hosts работает для всех программ.'
    'блок телеметрийных доменов в hosts' = 'Windows Update и Магазин не затрагиваются. Изредка перестают уходить отчёты об ошибках.'
    'блокировка адресов сбора телеметрии' = 'На тех же адресах иногда живут другие службы Microsoft — если что-то отвалится, снимите пункт.'
    'служба CDPSvc: регистрация компьютера в каталоге устройств Microsoft — выкл' = '«Связь с телефоном» и обмен с устройствами поблизости перестанут работать.'
    'служба DoSvc (Delivery Optimization): передача номера устройства — выкл' = 'Если Магазин перестанет скачивать приложения — снимите этот пункт.'
    'сервер выдачи номера (login.live.com, account.live.com) — в hosts' = 'Вход в учётную запись Microsoft, Магазин, Xbox и OneDrive перестанут работать.'
    'служба InventorySvc (опись программ и оборудования)' = 'Перед крупным обновлением Windows проверка совместимости будет знать о ваших программах меньше.'
    'синхронизация параметров между устройствами — выкл' = 'Тема, язык и другие настройки не переедут на новый компьютер сами — их придётся задать заново.'
    'копия списка приложений в облако — выкл' = 'На новом компьютере Windows не предложит заново поставить ваши приложения.'
    'архивация Windows в облако — выкл' = 'Копия в OneDrive перестанет обновляться сама. Если рассчитываете на неё при переезде — снимите пункт.'
    'синхронизация сетей Wi-Fi между устройствами — выкл' = 'Пароли Wi-Fi не будут переезжать на другие ваши компьютеры.'
    'установка приложений на этот ПК по команде с сайта — выкл' = 'Кнопка «Установить на устройство» на сайте Магазина перестанет работать. В самом Магазине всё ставится как обычно.'
    'не применять «исправления», присланные Microsoft' = 'Windows перестанет сама чинить известные сбои по указанию Microsoft. Средства устранения неполадок можно запускать вручную.'
    'средства устранения неполадок не обращаются к серверам Microsoft' = 'Средства устранения неполадок будут работать только с тем, что есть на компьютере.'
    'Защитник: удалённые настройки и эксперименты (ECS) — выкл' = 'Новые функции и усиления защиты Защитник будет получать только с обновлениями, а не с сервера экспериментов. Базы угроз обновляются как обычно.'
    'обои «Windows: интересное» на рабочем столе — выкл' = 'Картинки «Windows: интересное» на рабочем столе перестанут меняться сами.'
    'ИИ-агенты: доступ к файлам и настройкам через MCP — запрещён' = 'ИИ-помощники не смогут сами работать с вашими файлами и настройками Windows.'
    'приложение «Архивация Windows» — выкл' = 'Приложение «Архивация Windows» перестанет сохранять копию в OneDrive. Файлы на диске не трогаются.'
    'встроенные ИИ-модели Windows — запрещены приложениям' = 'Приложения из Магазина не смогут пользоваться ИИ-моделями Windows на компьютере.'
}

function Get-DefRisk {
    param($Def)
    if ($script:DefRisk.ContainsKey("$($Def.C)")) { return $script:DefRisk["$($Def.C)"] }
    if ($script:ModuleRisk.ContainsKey("$($Def.M)")) { return $script:ModuleRisk["$($Def.M)"] }
    return 'safe'
}

# =========================================================================== #
#  Файлы конфигурации сторонних программ
# =========================================================================== #
# Файл настроек того, кто сидит за компьютером (см. Convert-ToSessionPath)
function Get-VsCodeSettingsPath { return (Convert-ToSessionPath (Join-Path $env:APPDATA 'Code\User\settings.json')) }

function Get-VsCodeValue {
    param([string]$Key)
    $p = Get-VsCodeSettingsPath
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $txt = Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue
    if (-not $txt) { return $null }
    $rx = '"' + [regex]::Escape($Key) + '"\s*:\s*("(?<s>[^"]*)"|(?<b>true|false)|(?<n>-?[\d.]+))'
    $m = [regex]::Match($txt, $rx)
    if (-not $m.Success) { return $null }
    if ($m.Groups['s'].Success) { return $m.Groups['s'].Value }
    if ($m.Groups['b'].Success) { return ($m.Groups['b'].Value -eq 'true') }
    return $m.Groups['n'].Value
}

# Значение ключа как оно написано в файле («off», true, 14) — его и вернёт
# откат. @{ fileExists; exists; token }. Раньше откат возвращал не ключи, а
# весь файл копией, снятой при первом применении: всё, что человек поменял в
# настройках позже, пропадало (проверено на VM).
function Get-VsCodeRaw {
    param([string]$Key)
    $p = Get-VsCodeSettingsPath
    $out = @{ fileExists = $false; exists = $false; token = '' }
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $out }
    $out.fileExists = $true
    $txt = Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue
    if (-not $txt) { return $out }
    $m = [regex]::Match($txt, '"' + [regex]::Escape($Key) + '"\s*:\s*("[^"]*"|true|false|-?[\d.]+)')
    if ($m.Success) { $out.exists = $true; $out.token = $m.Groups[1].Value }
    return $out
}

# Значение для JSON: строка — в кавычках, да/нет — словом, число — как есть
function ConvertTo-JsonToken {
    param($Value)
    if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }
    if ($Value -is [string]) { return ('"' + ($Value -replace '([\\"])', '\$1') + '"') }
    return "$Value"
}

# Обратно: из записи журнала — значение того же вида, что было в файле
function ConvertFrom-JsonToken {
    param([string]$Token)
    $t = "$Token".Trim()
    if ($t -eq 'true') { return $true }
    if ($t -eq 'false') { return $false }
    if ($t.StartsWith('"')) { return ($t.Substring(1, [Math]::Max(0, $t.Length - 2)) -replace '\\([\\"])', '$1') }
    $n = 0.0
    if ([double]::TryParse($t, [ref]$n)) { if ($t -notmatch '\.') { return [int]$n }; return $n }
    return $t
}

# Сценарий для задачи от имени пользователя: правит settings.json в его
# профиле. Писать туда с правами администратора нельзя — в папку профиля
# пишет любая его программа, и подменённый ссылкой settings.json увёл бы
# запись с этими правами в чужой файл. token = '' — ключ убрать.
# removeFileIfEmpty — если после этого в файле не осталось ни одного ключа и
# файл завела сама программа, он удаляется.
function Get-VsCodeWriteScript {
    return @'
param([string]$InputFile, [string]$ResultFile)
$in = (Get-Content -LiteralPath $InputFile -Raw -Encoding UTF8) | ConvertFrom-Json
$p = "$($in.path)"
$res = @{ ok = $false; why = ''; removedFile = $false }
try {
  $dir = Split-Path $p -Parent
  foreach ($d in @($dir, $p)) {
    if ((Test-Path -LiteralPath $d) -and ((Get-Item -LiteralPath $d -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
      throw 'на пути к файлу настроек стоит ссылка'
    }
  }
  if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
  $txt = $(if (Test-Path -LiteralPath $p -PathType Leaf) { Get-Content -LiteralPath $p -Raw -ErrorAction Stop } else { '' })
  if (-not $txt -or $txt.Trim() -eq '') { $txt = "{`r`n}" }
  $key = "$($in.key)"
  if ($key -eq '') {
    # без ключа — только «удалить файл, если он пуст»; ничего не переписывается
    if ($in.removeFileIfEmpty -and (Test-Path -LiteralPath $p -PathType Leaf) -and (($txt -replace '\s', '') -eq '{}')) {
      [IO.File]::Delete($p); $res.removedFile = $true
    }
    $res.ok = $true
    ConvertTo-Json -InputObject $res -Depth 4 -Compress | Set-Content -LiteralPath $ResultFile -Encoding UTF8
    return
  }
  $rx = '(\s*)"' + [regex]::Escape($key) + '"(\s*):(\s*)("[^"]*"|true|false|-?[\d.]+)(\s*,?)'
  $tok = "$($in.token)"
  if ($tok -eq '') {
    $m = [regex]::Match($txt, $rx)
    if ($m.Success) {
      $before = $txt.Substring(0, $m.Index); $after = $txt.Substring($m.Index + $m.Length)
      # наш ключ был последним (запятой после него нет) — запятая, оставшаяся
      # на предыдущем, сделала бы файл негодным; больше ничего в файле не трогаем
      $tail = $m.Groups[5].Value
      if (-not $tail.Contains(',')) { $before = [regex]::Replace($before, ',(\s*)$', '$1'); $after = $tail + $after }
      $txt = $before + $after
    }
  } elseif ([regex]::IsMatch($txt, $rx)) {
    $txt = [regex]::Replace($txt, $rx, ('${1}"' + $key + '"${2}:${3}' + $tok.Replace('$', '$$') + '${5}'), 1)
  } else {
    $i = $txt.IndexOf('{')
    if ($i -lt 0) { $txt = "{`r`n}"; $i = 0 }
    $rest = $txt.Substring($i + 1)
    $ins = "`r`n    `"$key`": $tok,"
    if ($rest.Trim() -eq '}') { $ins = $ins.TrimEnd(',') + "`r`n" }
    $txt = $txt.Substring(0, $i + 1) + $ins + $rest
  }
  $empty = ($txt -replace '\s', '') -eq '{}'
  if ($empty -and $in.removeFileIfEmpty -and (Test-Path -LiteralPath $p -PathType Leaf)) {
    [IO.File]::Delete($p); $res.removedFile = $true
  } else {
    [IO.File]::WriteAllText($p, $txt, (New-Object System.Text.UTF8Encoding($false)))
  }
  $res.ok = $true
} catch { $res.why = "$($_.Exception.Message)" }
ConvertTo-Json -InputObject $res -Depth 4 -Compress | Set-Content -LiteralPath $ResultFile -Encoding UTF8
'@
}

# Правка settings.json: ключ ставится или убирается задачей от имени
# пользователя. $Token — готовое значение для JSON, '' — убрать ключ.
function Write-VsCodeKey {
    param([string]$Key, [string]$Token, [switch]$RemoveFileIfEmpty)
    $r = Invoke-AsUser 'vscode' (Get-VsCodeWriteScript) @{
            path = (Get-VsCodeSettingsPath); key = $Key; token = $Token
            removeFileIfEmpty = [bool]$RemoveFileIfEmpty } -Minutes 3
    if (-not $r.ok) { return @{ ok = $false; why = $r.why } }
    if (-not $r.result.ok) { return @{ ok = $false; why = "$($r.result.why)" } }
    return @{ ok = $true; why = ''; removedFile = [bool]$r.result.removedFile }
}

# После отката всех ключей: файл настроек, который завела сама программа и в
# котором ничего не осталось, удаляется. Решается один раз в конце, а не на
# каждой записи: у первой записи файл ещё полон остальных наших ключей.
function Remove-CreatedAppFile {
    param([string]$App)
    if ($App -eq 'vscode') {
        if (-not (Test-Path -LiteralPath (Get-VsCodeSettingsPath) -PathType Leaf)) { return }
        $w = Write-VsCodeKey '' '' -RemoveFileIfEmpty
        if (-not $w.ok) { Write-Log ("   [i] файл настроек VS Code, созданный программой, не проверен на пустоту: {0}" -f $w.why); return }
        if ($w.removedFile) { Write-Log '   [+] файл настроек VS Code создала программа и он опустел -- удалён' }
    }
}

function Set-VsCodeValue {
    param([string]$Key, $Value, [string]$Comment)
    if ($DryRun) { Write-Log "   [тест] $Comment"; return }
    # файл настроек не переписываем, если там уже стоит нужное
    $curVal = Get-VsCodeValue $Key
    if ($null -ne $curVal -and "$curVal".ToLower() -eq "$Value".ToLower()) {
        Write-Log "   [в] $Comment -- уже настроено"; $script:Already++; return
    }
    if (-not (Test-CanModify $Comment)) { return }
    Ensure-Backup
    # «Как было» — по ключу и в журнал, раньше самой правки: откат вернёт
    # ровно этот ключ и не тронет того, что человек поменял потом сам.
    $raw = Get-VsCodeRaw $Key
    $entry = @{ kind = 'appcfg'; app = 'vscode'; name = $Key; existed = [bool]$raw.exists
                old = "$($raw.token)"; newValue = (ConvertTo-JsonToken $Value)
                created = [bool](-not $raw.fileExists) }
    if (-not (Write-AheadEntry $entry)) {
        Write-Log "   [!] $Comment -- не меняется: «как было» не легло в журнал отката"; $script:Failures++; return
    }
    $w = Write-VsCodeKey $Key $entry.newValue
    if (-not $w.ok) {
        Undo-AheadEntry $entry
        Write-Log ("   [!] не удалось: {0} -- {1}" -f $Comment, $w.why); $script:Failures++; return
    }
    # «задача отработала» — ещё не «значение такое»: читаем обратно
    $now = Get-VsCodeRaw $Key
    if (-not $now.exists -or $now.token -ne $entry.newValue) {
        Write-Log ("   [!] {0} -- записано, но читается другое: {1}" -f $Comment, $(if ($now.exists) { $now.token } else { 'ключа нет' }))
        $script:Failures++; return
    }
    Write-Log "   [+] $Comment"; $script:Changes++
}

function Get-FirefoxPoliciesPath {
    foreach ($d in @((Join-Path $env:ProgramFiles 'Mozilla Firefox'), (Join-Path ${env:ProgramFiles(x86)} 'Mozilla Firefox'))) {
        if ($d -and (Test-Path -LiteralPath (Join-Path $d 'firefox.exe'))) { return (Join-Path $d 'distribution\policies.json') }
    }
    return $null
}

# Текст файла в UTF-8 (с меткой или без) — строго: файл в другой кодировке
# не «перекодируется» молча, а даёт ошибку. Раньше Get-Content без метки
# читал policies.json в кодировке ANSI, и при записи обратно кириллица в
# чужих политиках (адреса, названия закладок) превращалась в мусор.
function Read-Utf8Strict {
    param([string]$Path)
    $b = [IO.File]::ReadAllBytes($Path)
    $off = $(if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { 3 } else { 0 })
    return (New-Object System.Text.UTF8Encoding($false, $true)).GetString($b, $off, $b.Length - $off)
}

function Get-FirefoxPolicy {
    param([string]$Key)
    $p = Get-FirefoxPoliciesPath
    if (-not $p -or -not (Test-Path -LiteralPath $p)) { return $null }
    try { $j = Read-Utf8Strict $p | ConvertFrom-Json; return $j.policies.$Key } catch { return $null }
}

# --------------------------------------------------------------------------- #
#  Запись файла JSON одним действием (W11P-002). Раньше Set-Content писал
#  policies.json прямо на месте: оборванная запись (сбой, нехватка места,
#  выключение) оставляла файл пустым или недописанным — и с ним пропадали все
#  политики Firefox, в том числе корпоративные. Теперь:
#    1. текст проверяется разбором ещё в памяти;
#    2. пишется во временный файл с уникальным именем в той же папке (только
#       новым — CreateNew: на месте чужого файла или ссылки запись не идёт),
#       UTF-8 без метки, со сбросом на диск;
#    3. записанное читается обратно и разбирается ещё раз;
#    4. встаёт на место одним действием системы (Replace-FileAtomic:
#       ReplaceFile, если файл есть, — права и атрибуты прежнего сохраняются;
#       иначе переименование);
#    5. при любой ошибке прежний файл не тронут, временный удаляется.
# --------------------------------------------------------------------------- #
function Write-JsonFileAtomic {
    param([string]$Path, [string]$Json)
    $null = $Json | ConvertFrom-Json -ErrorAction Stop
    $dir = Split-Path $Path -Parent
    $tmp = Join-Path $dir ('.' + (Split-Path $Path -Leaf) + '.w11p-' + [guid]::NewGuid().ToString('N').Substring(0, 12) + '.tmp')
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Json)
    try {
        $fs = [IO.File]::Open($tmp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush($true) } finally { $fs.Dispose() }
        $back = Read-Utf8Strict $tmp
        if ($back -cne $Json) { throw 'записанный временный файл не совпадает с подготовленным' }
        $null = $back | ConvertFrom-Json -ErrorAction Stop
        Replace-FileAtomic $tmp $Path
        $tmp = $null
    } finally {
        if ($tmp -and (Test-Path -LiteralPath $tmp)) { try { [IO.File]::Delete($tmp) } catch { } }
    }
}

function Set-FirefoxPolicy {
    param([string]$Key, $Value, [string]$Comment)
    $p = Get-FirefoxPoliciesPath
    if (-not $p) { Write-Log "   [-] Firefox не найден"; return }
    if ($DryRun) { Write-Log "   [тест] $Comment"; return }
    $curVal = Get-FirefoxPolicy $Key
    if ($null -ne $curVal -and "$curVal".ToLower() -eq "$Value".ToLower()) {
        Write-Log "   [в] $Comment -- уже настроено"; $script:Already++; return
    }
    if (-not (Test-CanModify $Comment)) { return }
    Ensure-Backup
    # policies.json лежит в Program Files — туда пишет только администратор,
    # и записи по пути тут опасаться нечего. В журнал, как и у VS Code, идёт
    # один ключ: откат вернёт его, а не весь файл копией.
    $had = (Test-Path -LiteralPath $p -PathType Leaf)
    $prev = Get-FirefoxPolicy $Key
    $entry = @{ kind = 'appcfg'; app = 'firefox'; name = $Key; existed = [bool]($null -ne $prev)
                old = $(if ($null -ne $prev) { ConvertTo-JsonToken $prev } else { '' })
                newValue = (ConvertTo-JsonToken $Value); created = [bool](-not $had) }
    if (-not (Write-AheadEntry $entry)) {
        Write-Log "   [!] $Comment -- не меняется: «как было» не легло в журнал отката"; $script:Failures++; return
    }
    $w = Write-FirefoxKey $Key $Value
    if (-not $w.ok) {
        Undo-AheadEntry $entry
        Write-Log ("   [!] не удалось: {0} -- {1}" -f $Comment, $w.why); $script:Failures++; return
    }
    $now = Get-FirefoxPolicy $Key
    if ($null -eq $now -or "$now".ToLower() -ne "$Value".ToLower()) {
        Write-Log ("   [!] {0} -- записано, но читается другое: {1}" -f $Comment, $(if ($null -eq $now) { 'ключа нет' } else { "$now" }))
        $script:Failures++; return
    }
    Write-Log "   [+] $Comment"; $script:Changes++
}

# Ставит или убирает один ключ в policies.json. $Remove — убрать; если после
# этого в policies ничего не осталось и файл завела программа, он удаляется.
# Глубина JSON — 20: при 6 глубокие корпоративные политики обрезались.
function Write-FirefoxKey {
    param([string]$Key, $Value, [switch]$Remove)
    $p = Get-FirefoxPoliciesPath
    if (-not $p) { return @{ ok = $false; why = 'Firefox не найден' } }
    # Папка Firefox должна быть закрыта на запись для всех, кроме системы и
    # администраторов (так в Program Files по умолчанию): иначе между
    # проверками и заменой файла в ней мог бы подложить ссылку кто угодно.
    # W11P-006: проверяются и унаследованные права, и весь путь до папки —
    # её родителя тоже нельзя давать переименовать чужому.
    $ffPath = Split-Path (Split-Path $p -Parent) -Parent
    if (-not (Test-Path -LiteralPath $ffPath -PathType Container)) { return @{ ok = $false; why = 'папка Firefox не читается' } }
    if (-not (Test-PathTrusted $ffPath)) { return @{ ok = $false; why = 'папка Firefox (или папка выше) открыта на запись не только администраторам -- policies.json не трогаем' } }
    # Уже существующие distribution и policies.json — тоже только «свои»:
    # если их завела или может менять обычная программа, файл между чтением и
    # заменой подменили бы, а замена шла бы с правами администратора.
    foreach ($x in @((Split-Path $p -Parent), $p)) {
        if (-not (Test-Path -LiteralPath $x)) { continue }
        $xi = $null
        try { $xi = Get-Item -LiteralPath $x -Force -ErrorAction Stop } catch { }
        if (-not (Test-ItemTrusted $xi)) { return @{ ok = $false; why = ("{0} заведён не администратором или открыт на запись -- policies.json не трогаем" -f (Split-Path $x -Leaf)) } }
    }
    return (Update-FirefoxPoliciesFile $p $Key $Value -Remove:$Remove)
}

# Замок policies.json — общий для всех, кто его пишет: окно (движок с правами
# администратора в сеансе пользователя), страж и откат (задачи от имени
# системы в сеансе 0). Только Global\: раньше при ошибке открытия замок молча
# брался в Local\ — у каждого сеанса свой, и окно с задачей стража могли
# писать одновременно, теряя правки друг друга. Теперь не открылся — отказ.
#  * Новый замок заводится с правами только для системы, администраторов и
#    самого создателя — замок, заведённый задачей от имени системы, откроет и
#    движок окна (с правами по умолчанию системный замок администраторам
#    недоступен, и раньше это и уводило в Local\).
#  * Уже существующий замок годится, только если его владелец — система или
#    администраторы, а ждать его (то есть взять и держать), менять его права,
#    владельца или удалить могут только они же (Get-MutexSecurityProblem).
#    Замок, заранее заведённый обычной программой, не используется: она могла
#    бы держать его или отпускать, когда ей нужно.
#
#  Сама учётная запись движка «своей» считается, только когда он работает без
#  повышения (тесты, ручной запуск): тогда границы прав нет. У повышенного
#  движка тот же SID пользователя есть и у любой его обычной программы — она
#  заводила замок «своим» и проходила проверку владельца, а право
#  «полный доступ» для этого SID в новом замке давало ей взять и держать
#  настоящий замок или переписать его права (T-1). Повышенный движок ставит
#  новому замку владельцем «Администраторов»: обычная программа такого
#  владельца назначить не может (Windows отвечает «этот SID нельзя назначить
#  владельцем»).
function Get-MutexTrustedSids {
    $sids = @('S-1-5-18', 'S-1-5-32-544')
    if (-not (Test-Admin)) { try { $sids += [Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { } }
    return $sids
}

function Test-MutexOwnerTrusted {
    param([string]$Sid)
    if (-not $Sid) { return $false }
    return (@(Get-MutexTrustedSids) -contains $Sid)
}

# Права уже заведённого замка. Пустая строка — замок свой, иначе — почему нет:
# права не читаются (дескриптор открыт без READ_CONTROL — так .NET открывает
# чужой замок, к которому нет полного доступа), владелец чужой, или кто-то,
# кроме своих, может его ждать (взять и держать), менять права и владельца,
# удалить. Читать права и состояние замка — не опасно. Пустой список прав
# (NULL DACL) .NET показывает как «Все: полный доступ» — тоже отказ.
function Get-MutexSecurityProblem {
    param($Security, [string[]]$Trusted = @(Get-MutexTrustedSids))
    if ($null -eq $Security) { return 'права замка не читаются' }
    $owner = ''
    try { $owner = "$($Security.GetOwner([Security.Principal.SecurityIdentifier]).Value)" } catch { }
    if (-not $owner) { return 'владелец замка не читается' }
    if (@($Trusted) -notcontains $owner) { return ('замок заведён чужой учётной записью ({0})' -f $owner) }
    $harmless = [int64](0x20000 -bor 0x1)   # READ_CONTROL, MUTANT_QUERY_STATE
    try { $rules = @($Security.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) }
    catch { return 'права замка не читаются' }
    foreach ($r in $rules) {
        if ("$($r.AccessControlType)" -ne 'Allow') { continue }
        $sid = "$($r.IdentityReference.Value)"
        if (@($Trusted) -contains $sid) { continue }
        if (([int64][int]$r.MutexRights -band (-bnot $harmless)) -ne 0) { return ('замок открыт не только системе и администраторам ({0})' -f $sid) }
    }
    return ''
}

# Права нового замка программы: полный доступ — системе и администраторам (и
# самой учётной записи, только если движок без повышения), наследования нет.
# -Owner — владелец «Администраторы» (повышенный движок и SYSTEM).
function New-ProgramMutexSecurity {
    param([switch]$Owner)
    $sec = New-Object System.Security.AccessControl.MutexSecurity
    $sec.SetAccessRuleProtection($true, $false)
    foreach ($s in @(Get-MutexTrustedSids)) {
        $sid = New-Object Security.Principal.SecurityIdentifier($s)
        $sec.AddAccessRule((New-Object System.Security.AccessControl.MutexAccessRule($sid, [System.Security.AccessControl.MutexRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow)))
    }
    if ($Owner) { $sec.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544'))) }
    return $sec
}

# Замок программы по имени: свой новый или проверенный существующий — тот же
# дескриптор, что проверен, и ждётся (повторного открытия по имени нет: между
# проверкой и вторым открытием объект под этим именем могли бы подменить).
# Не годится — исключение, защищаемое действие не выполняется.
function Open-ProgramMutex {
    param([string]$Name)
    $created = $false
    $m = $null
    $elevated = Test-Admin
    try { $m = [System.Threading.Mutex]::new($false, $Name, [ref]$created, (New-ProgramMutexSecurity -Owner:$elevated)) }
    catch {
        # вид ошибки — по самому исключению .NET, а не по фильтру catch [тип] (T-4)
        $ex = $_.Exception.GetBaseException()
        if ($ex -is [System.UnauthorizedAccessException]) { throw ('замок {0} не открылся: нет доступа -- его заранее занял кто-то чужой' -f $Name) }
        if ($ex -is [System.Threading.WaitHandleCannotBeOpenedException]) { throw ('имя замка {0} занято объектом другого вида -- его заранее занял кто-то чужой' -f $Name) }
        # «этот SID нельзя назначить владельцем»: у учётной записи нет права
        # назначить «Администраторов» — тогда владелец остаётся по умолчанию
        # (у SYSTEM — она сама). Чужой замок под этим именем всё равно
        # проверяется ниже.
        if (-not $elevated) { throw ('замок {0} не открылся: {1}' -f $Name, $_.Exception.Message) }
        try { $m = [System.Threading.Mutex]::new($false, $Name, [ref]$created, (New-ProgramMutexSecurity)) }
        catch { throw ('замок {0} не открылся ({1}) -- его мог заранее занять кто-то чужой' -f $Name, $_.Exception.Message) }
    }
    if (-not $created) {
        $cur = $null
        try { $cur = $m.GetAccessControl() } catch { $cur = $null }
        $why = Get-MutexSecurityProblem $cur
        if ($why) { $m.Dispose(); throw ('замок {0} не годится: {1}' -f $Name, $why) }
    }
    return $m
}

function Open-FirefoxMutex {
    try { return (Open-ProgramMutex 'Global\Win11Privacy-FirefoxPolicies') }
    catch { throw ('{0} -- policies.json не пишем' -f $_.Exception.Message) }
}

# Сам ключ в файле по явному пути (его же проверяют тесты на временной папке).
# Чтение, правка и запись — под общим замком всех запусков программы
# (окно, страж, откат): два писателя одновременно теряли бы правку друг друга.
function Update-FirefoxPoliciesFile {
    param([string]$Path, [string]$Key, $Value, [switch]$Remove)
    $mtx = $null; $got = $false
    try {
        $mtx = Open-FirefoxMutex
        # «брошен» (прежний держатель умер) — замок наш; любая другая ошибка —
        # не наш. Вид — по самому исключению .NET (T-4, см. Test-IoBusy).
        try { $got = $mtx.WaitOne(30000) }
        catch { if ($_.Exception.GetBaseException() -is [System.Threading.AbandonedMutexException]) { $got = $true } else { throw } }
        if (-not $got) { return @{ ok = $false; why = 'policies.json сейчас меняет другой запуск программы' } }
        $dir = Split-Path $Path -Parent
        foreach ($d in @($dir, $Path)) {
            if ((Test-Path -LiteralPath $d) -and ((Get-Item -LiteralPath $d -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                return @{ ok = $false; why = 'на пути к policies.json стоит ссылка' }
            }
        }
        if (-not (Test-Path -LiteralPath $dir)) {
            $null = [IO.Directory]::CreateDirectory($dir)
            if ((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return @{ ok = $false; why = 'на пути к policies.json стоит ссылка' } }
        }
        # Свои временные файлы, оставшиеся от оборванной записи, — через час
        foreach ($old in @(Get-ChildItem -LiteralPath $dir -File -Force -Filter ('.' + (Split-Path $Path -Leaf) + '.w11p-*.tmp') -ErrorAction SilentlyContinue)) {
            if ($old.LastWriteTime -lt (Get-Date).AddHours(-1) -and -not ($old.Attributes -band [IO.FileAttributes]::ReparsePoint)) { try { [IO.File]::Delete($old.FullName) } catch { } }
        }
        $obj = $null
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $ff = $null
            try { $ff = Read-Utf8Strict $Path } catch { return @{ ok = $false; why = 'policies.json не в кодировке UTF-8 -- не трогаем, чтобы не испортить чужие политики' } }
            if ("$ff".Trim()) {
                try { $obj = $ff | ConvertFrom-Json -ErrorAction Stop } catch { $obj = $null }
                # Файл есть, но не разобрался (комментарий, политика, с которой
                # не справился разбор PowerShell 5.1). Не перезаписываем: иначе
                # пропали бы уже стоящие там политики, в том числе корпоративные.
                if ($null -eq $obj) { return @{ ok = $false; why = 'policies.json есть, но не разбирается как JSON -- не трогаем, чтобы не стереть чужие политики' } }
            }
        }
        if (-not $obj) { $obj = New-Object PSObject }
        if (-not ($obj.PSObject.Properties.Name -contains 'policies')) { $obj | Add-Member -NotePropertyName 'policies' -NotePropertyValue (New-Object PSObject) }
        if ($Remove) {
            if ($obj.policies.PSObject.Properties.Name -contains $Key) { $obj.policies.PSObject.Properties.Remove($Key) }
            if (@($obj.policies.PSObject.Properties).Count -eq 0 -and @($obj.PSObject.Properties).Count -eq 1) {
                if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::Delete($Path) }
                return @{ ok = $true; why = ''; removedFile = $true }
            }
        } elseif ($obj.policies.PSObject.Properties.Name -contains $Key) { $obj.policies.$Key = $Value }
        else { $obj.policies | Add-Member -NotePropertyName $Key -NotePropertyValue $Value }
        Write-JsonFileAtomic $Path ($obj | ConvertTo-Json -Depth 20)
        return @{ ok = $true; why = '' }
    } catch { return @{ ok = $false; why = $_.Exception.Message } }
    finally {
        if ($got) { try { $mtx.ReleaseMutex() } catch { } }
        if ($null -ne $mtx) { $mtx.Dispose() }
    }
}

# =========================================================================== #
#  Применение / проверка одного определения
# =========================================================================== #
# --------------------------------------------------------------------------- #
#  УБОРКА ЗА СТАРЫМИ ВЕРСИЯМИ
#  В версиях 1.1.0–1.5.0 счётчик внутри Def затирал имя параметра, и настройки
#  писались в реестр под числовыми именами: «0», «1», «2» вместо AllowTelemetry.
#  Они ничего не настраивали. Находим ровно свои: имя — число, оно совпадает с
#  номером определения по этому пути, а значение — с тем, что мы бы записали.
# --------------------------------------------------------------------------- #
function Find-JunkValues {
    $byIdx = @{}
    $paths = @{}
    foreach ($d in $script:Defs) {
        if ($script:RegTypes -notcontains $d.T) { continue }
        $paths["$($d.P)"] = $true
        $parts = "$($d.Id)" -split '#'
        if ($parts.Count -ne 2) { continue }
        $k = "$($d.P)|$([int]$parts[1])"
        if (-not $byIdx.ContainsKey($k)) { $byIdx[$k] = $d }
    }
    $junk = @()
    foreach ($path in @($paths.Keys)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $names = @()
        # без -ErrorAction Stop отказ доступа не ловится try/catch и сыплется в вывод
        try { $names = @((Get-Item -LiteralPath $path -ErrorAction Stop).GetValueNames()) } catch { continue }
        foreach ($nm in $names) {
            if ($nm -notmatch '^[0-9]{1,3}$') { continue }
            $k = "$path|$([int]$nm)"
            if (-not $byIdx.ContainsKey($k)) { continue }
            $cur = Get-RegValue $path $nm
            if ($null -eq $cur) { continue }
            if ("$cur" -ne "$($byIdx[$k].V)") { continue }      # значение чужое — не наше
            $junk += @{ path = $path; name = $nm; title = "$($byIdx[$k].C)" }
        }
    }
    return @($junk)
}

function Remove-JunkValues {
    $junkList = @(Find-JunkValues)
    if ($junkList.Count -eq 0) { return 0 }
    $gone = 0
    foreach ($j in $junkList) {
        if ($DryRun) { Write-Log ("   [тест] мусор от старой версии: {0} -> {1}" -f $j.path, $j.name); continue }
        try {
            Remove-ItemProperty -LiteralPath $j.path -Name $j.name -Force -ErrorAction Stop
            Write-Log ("   [+] убран мусорный параметр {0} ({1})" -f $j.name, $j.title)
            $gone++
        } catch { Write-Log ("   [!] не удалось убрать {0} -> {1}" -f $j.path, $j.name) }
    }
    return $gone
}

# Останавливает службу, отключённую через реестр, и её копии для каждого
# пользователя (CDPUserSvc_1a2b3): запись в реестре вступает в силу только
# после перезагрузки, а до неё служба продолжила бы работать.
function Stop-ServiceInstances {
    param([string]$Name)
    foreach ($s in @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $Name -or $_.Name -like ($Name + '_*') })) {
        if ($s.Status -ne 'Running') { continue }
        try { Stop-Service -Name $s.Name -Force -ErrorAction Stop; Write-Log ("       остановлена: {0}" -f $s.Name) }
        catch { Write-Log ("       {0} остановится после перезагрузки" -f $s.Name) }
    }
}

# Служба не отключилась. Отказ в доступе — решение Windows (часть служб она
# не отдаёт даже администратору): это «не разрешает», как у политик, и
# проверка его потом не считает «не применённым». Любая другая причина —
# ошибка, и она видна в итоге.
function Test-AccessDeniedError {
    param($Err)
    $ex = $(if ($Err -is [System.Management.Automation.ErrorRecord]) { $Err.Exception } else { $Err })
    while ($null -ne $ex) {
        if ($ex -is [System.UnauthorizedAccessException]) { return $true }
        if ($ex -is [System.ComponentModel.Win32Exception] -and $ex.NativeErrorCode -eq 5) { return $true }
        $ex = $ex.InnerException
    }
    return $false
}

function Write-SvcFailure {
    param($Def, $Err)
    $msg = "$($Err.Exception.Message)"
    if (Test-AccessDeniedError $Err) {
        Write-Log ("   [-] {0} -- Windows не даёт менять эту службу" -f $Def.C)
        $script:Blocked++
        if ($null -ne $script:BlockedIds) { $script:BlockedIds[$Def.Id] = $true }
        return
    }
    Write-Log ("   [!] {0} -- не отключилась: {1}" -f $Def.C, $msg)
    $script:Failures++
}

function Apply-Def {
    param($d)
    # журнал отката не пишется — больше ничего не меняем (причина уже в журнале работы)
    if ($script:JournalFailed -and -not $DryRun) { return }
    switch ($d.T) {
        'reg' { Set-Reg -Path $d.P -Name $d.N -Value $d.V -Type $d.Type -Comment $d.C }
        'regsvc' {
            # служба есть не на каждой редакции Windows — чего нет, то не создаём
            if (-not (Test-Path -LiteralPath $d.P)) { Write-Log ("   [-] {0} -- нет на этой системе" -f $d.C); return }
            Set-Reg -Path $d.P -Name $d.N -Value $d.V -Type $d.Type -Comment $d.C
            # останавливаем, только если отключение действительно записалось:
            # иначе служба тут же запустилась бы снова
            if (-not $DryRun -and "$($d.V)" -eq '4' -and "$(Get-RegValue $d.P $d.N)" -eq '4') { Stop-ServiceInstances (Split-Path $d.P -Leaf) }
        }
        'regpol' { Set-Reg -Path $d.P -Name $d.N -Value $d.V -Type $d.Type -Comment $d.C -Policy -DefId $d.Id }
        'regif' {
            # сессия трассировки есть не на каждой сборке Windows — чего нет, то не создаём
            if (Test-Path -LiteralPath $d.P) { Set-Reg -Path $d.P -Name $d.N -Value $d.V -Type $d.Type -Comment $d.C }
            else { Write-Log ("   [-] {0} -- нет на этой системе" -f $d.C) }
        }
        'svc' {
            if ($DryRun) { Write-Log "   [тест] $($d.C) -- отключить"; return }
            # «Службы нет» и «служба не отключилась» — разное. Раньше любая
            # ошибка называлась «недоступна» и в ошибки не шла: отказ при
            # отключении выглядел как отсутствие службы, а итог — успехом.
            $s = Get-Service -Name $d.P -ErrorAction SilentlyContinue
            if (-not $s) { Write-Log "   [-] $($d.C) -- нет на этой системе"; return }
            try {
                if ($s.StartType -eq 'Disabled' -and $s.Status -ne 'Running') {
                    Write-Log "   [в] $($d.C) -- уже настроено"; $script:Already++; return
                }
                if (-not (Test-CanModify $d.C)) { return }
                Ensure-Backup
                $was = Get-SvcJournalState $d.P $s
                if (-not (Write-AheadEntry $was)) { Write-Log "   [!] $($d.C) -- не меняется: «как было» не легло в журнал отката"; $script:Failures++; return }
                try {
                    if ($s.Status -eq 'Running') { Stop-Service -Name $d.P -Force -ErrorAction SilentlyContinue }
                    Set-Service -Name $d.P -StartupType Disabled -ErrorAction Stop
                } catch {
                    # не отключилась — работавшую запускаем обратно, запись отзываем
                    if ($was.running) { Start-Service -Name $d.P -ErrorAction SilentlyContinue }
                    Undo-AheadEntry $was
                    throw
                }
                Write-Log "   [+] $($d.C) -- остановлена и отключена"; $script:Changes++
                if ($null -ne $script:UnblockedIds) { $script:UnblockedIds[$d.Id] = $true }
            } catch { Write-SvcFailure $d $_ }
        }
        'svcopt' {
            $s = Get-Service -Name $d.P -ErrorAction SilentlyContinue
            if (-not $s) { return }
            if ($DryRun) { Write-Log "   [тест] $($d.C) -- отключить"; return }
            try {
                if ($s.StartType -eq 'Disabled' -and $s.Status -ne 'Running') {
                    Write-Log "   [в] $($d.C) -- уже настроено"; $script:Already++; return
                }
                if (-not (Test-CanModify $d.C)) { return }
                Ensure-Backup
                $was = Get-SvcJournalState $d.P $s
                if (-not (Write-AheadEntry $was)) { Write-Log "   [!] $($d.C) -- не меняется: «как было» не легло в журнал отката"; $script:Failures++; return }
                try {
                    if ($s.Status -eq 'Running') { Stop-Service -Name $d.P -Force -ErrorAction SilentlyContinue }
                    Set-Service -Name $d.P -StartupType Disabled -ErrorAction Stop
                } catch {
                    if ($was.running) { Start-Service -Name $d.P -ErrorAction SilentlyContinue }
                    Undo-AheadEntry $was
                    throw
                }
                Write-Log "   [+] $($d.C) -- отключена"; $script:Changes++
                if ($null -ne $script:UnblockedIds) { $script:UnblockedIds[$d.Id] = $true }
            } catch { Write-SvcFailure $d $_ }
        }
        'task' {
            $pp = Split-TaskPath $d.P
            if ($DryRun) { Write-Log "   [тест] $($d.C) -- отключить"; return }
            $st = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction SilentlyContinue
            if (-not $st) { Write-Log "   [-] $($d.C) -- нет на этой системе"; return }
            if (Test-TaskDisabled $st) { Write-Log "   [в] $($d.C) -- уже настроено"; $script:Already++; return }
            if (-not (Test-CanModify $d.C)) { return }
            Ensure-Backup
            $tj = @{ kind = 'task'; path = $d.P; old = 'Enabled'; newValue = 'Disabled' }
            if (-not (Write-AheadEntry $tj)) { Write-Log "   [!] $($d.C) -- не меняется: «как было» не легло в журнал отката"; $script:Failures++; return }
            switch (Set-TaskEnabled $d.P $false) {
                'ok'      { Write-Log "   [+] $($d.C) -- отключена"; $script:Changes++ }
                'system'  { Write-Log "   [+] $($d.C) -- отключена от имени системы (администратору Windows её не отдаёт)"; $script:Changes++ }
                'missing' { Undo-AheadEntry $tj; Write-Log "   [-] $($d.C) -- нет на этой системе" }
                default   { Undo-AheadEntry $tj; Write-Log "   [!] $($d.C) -- Windows не дала отключить задачу"; $script:Failures++ }
            }
        }
        'taskglob' {
            $ts = @(Get-TaskGlobTasks $d.P)
            if ($ts.Count -eq 0) { return }
            foreach ($t in $ts) {
                if ($DryRun) { Write-Log "   [тест] задача $($t.TaskName) -- отключить"; continue }
                if (Test-TaskDisabled $t) { Write-Log "   [в] задача $($t.TaskName) -- уже отключена"; $script:Already++; continue }
                if (-not (Test-CanModify ("задача " + $t.TaskName))) { break }
                Ensure-Backup
                $tj = @{ kind = 'task'; path = ($t.TaskPath + $t.TaskName); old = 'Enabled'; newValue = 'Disabled' }
                if (-not (Write-AheadEntry $tj)) { Write-Log ("   [!] задача {0} -- не меняется: «как было» не легло в журнал отката" -f $t.TaskName); $script:Failures++; break }
                # тем же путём, что и задачи по имени: со сверкой и запасным путём
                # от имени системы. Раньше неудача здесь шла как «[-]», не как ошибка.
                switch (Set-TaskEnabled ($t.TaskPath + $t.TaskName) $false) {
                    'ok'      { Write-Log "   [+] задача $($t.TaskName) -- отключена"; $script:Changes++ }
                    'system'  { Write-Log "   [+] задача $($t.TaskName) -- отключена от имени системы"; $script:Changes++ }
                    'missing' { Undo-AheadEntry $tj; Write-Log "   [-] задача $($t.TaskName) -- пропала, пока шла работа" }
                    default   { Undo-AheadEntry $tj; Write-Log "   [!] задача $($t.TaskName) -- Windows не дала отключить"; $script:Failures++ }
                }
            }
        }
        'env' {
            if ($DryRun) { Write-Log "   [тест] $($d.C)"; return }
            if ([string][Environment]::GetEnvironmentVariable($d.P, 'User') -eq [string]$d.V) {
                Write-Log "   [в] $($d.C) -- уже настроено"; $script:Already++; return
            }
            if (-not (Test-CanModify $d.C)) { return }
            Ensure-Backup
            $prevEnv = [Environment]::GetEnvironmentVariable($d.P, 'User')
            $ej = @{ kind = 'env'; name = $d.P; existed = [bool]($null -ne $prevEnv)
                     old = $(if ($null -ne $prevEnv) { [string]$prevEnv } else { '' }); newValue = [string]$d.V }
            if (-not (Write-AheadEntry $ej)) { Write-Log "   [!] $($d.C) -- не меняется: «как было» не легло в журнал отката"; $script:Failures++; return }
            try {
                [Environment]::SetEnvironmentVariable($d.P, [string]$d.V, 'User')
                Write-Log "   [+] $($d.C)"; $script:Changes++
            }
            catch { Undo-AheadEntry $ej; Write-Log "   [!] не удалось: $($d.C)"; $script:Failures++ }
        }
        'vscode'  { Set-VsCodeValue -Key $d.P -Value $d.V -Comment $d.C }
        'firefox' { Set-FirefoxPolicy -Key $d.P -Value $d.V -Comment $d.C }
        'hosts'   { Apply-Hosts }
        'gdidhosts' { Apply-Hosts -Kind 'gdid' }
        'gdidlockhosts' { Apply-Hosts -Kind 'lock' }
        'gdidwipe' {
            # Пока сервер выдачи открыт, стёртый номер сразу сменится новым —
            # это смена номера, а не запрет. Без закрытого сервера не стираем.
            # Закрыт — значит, блок цел и в нём нужный список: побитый блок
            # с одной меткой раньше тоже считался закрытым сервером.
            if (-not $DryRun -and -not (Test-HostsBlockCurrent -Kind 'lock')) {
                Write-Log ("   [-] {0} -- пропущено: сервер выдачи номера не закрыт" -f $d.C); return
            }
            $null = Invoke-GdidWipe
        }
        'fwsvc'   { Apply-FwRule -Kind 'svc' -Target $d.P -Comment $d.C }
        'fwapp'   { Apply-FwRule -Kind 'app' -Target $d.P -Comment $d.C }
        'fwips'   { Apply-FwIpBlock }
    }
}

# Стоит ли параметр реестра так, как задумано: те же данные и тот же вид.
# Раньше сравнивались только строки, и REG_SZ «1» на месте DWORD 1 шёл как
# «применено», хотя Windows такой параметр не понимает.
function Test-RegDefValue {
    param($Def)
    $raw = Get-RegRaw $Def.P $Def.N
    if (-not $raw.ok) { return @{ ok = $false; actual = ("не читается: {0}" -f $raw.error) } }
    if (-not $raw.exists) { return @{ ok = $false; actual = 'не задано' } }
    $want = $(if ($Def.Type) { "$($Def.Type)" } else { 'DWord' })
    $got = ConvertTo-RegComparable $raw.value $raw.kind
    if ("$($raw.kind)" -ne $want) { return @{ ok = $false; actual = ("{0} (вид {1}, нужен {2})" -f $got, $raw.kind, $want) } }
    return @{ ok = ($got -eq (ConvertTo-RegComparable $Def.V $want)); actual = $got }
}

# Настройки, которой на этой версии Windows не существует, не бывает
# «не применённой»: помечаем na и не считаем ни в плюс, ни в минус.
function Test-DefApplicable {
    param($d)
    $minB = 0
    try { $minB = [int]$d.Min } catch { }
    if ($minB -le 0 -or $script:OsBuild -le 0) { return $true }
    return ($script:OsBuild -ge $minB)
}

function Check-Def {
    param($d)
    $ok = $false; $actual = ''; $unverified = $false
    if (-not (Test-DefApplicable $d)) {
        return @{ module=$d.M; name=$d.C; ok=$false; na=$true
                  expected="$($d.V)"; actual='нет на этой версии Windows' }
    }
    # Запрет выдачи номера при входе через учётную запись Microsoft недоступен
    # вовсе — индекс за него не снижается, как и за то, чего нет в этой Windows.
    if ($d.M -eq 'gdidlock' -and (Get-GdidLockRefusal)) {
        return @{ module=$d.M; name=$d.C; ok=$false; na=$true
                  expected="$($d.V)"; actual=$(if ((Get-GdidLockRefusal) -eq 'msa') { 'недоступно при входе через учётную запись Microsoft' } else { 'недоступно на компьютере организации' }) }
    }
    switch ($d.T) {
        { $_ -in @('regif', 'regsvc') } {
            if (-not (Test-Path -LiteralPath $d.P)) { $ok = $true; $actual = 'нет на этой системе' }
            else { $rc = Test-RegDefValue $d; $ok = $rc.ok; $actual = $rc.actual }
        }
        'regpol' {
            # Проверяем как обычный параметр. «Windows не разрешает» — это факт,
            # известный только после неудачной записи, и подставляется он в
            # -Audit по журналу отказов; здесь догадок не строим.
            $rc = Test-RegDefValue $d; $ok = $rc.ok; $actual = $rc.actual
        }
        'reg' { $rc = Test-RegDefValue $d; $ok = $rc.ok; $actual = $rc.actual }
        'svc' {
            $s = Get-Service -Name $d.P -ErrorAction SilentlyContinue
            if (-not $s) { $ok = $true; $actual = 'нет службы' }
            else { $actual = "$($s.StartType) / $($s.Status)"; $ok = ($s.StartType -eq 'Disabled') }
        }
        'svcopt' {
            $s = Get-Service -Name $d.P -ErrorAction SilentlyContinue
            if (-not $s) { $ok = $true; $actual = 'нет службы' }
            else { $actual = "$($s.StartType)"; $ok = ($s.StartType -eq 'Disabled') }
        }
        'task' {
            $pp = Split-TaskPath $d.P
            $t = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction SilentlyContinue
            if (-not $t) { $ok = $true; $actual = 'нет задачи' }
            else { $ok = Test-TaskDisabled $t; $actual = $(if ($ok) { 'Disabled' } else { [string]$t.State }) }
        }
        'taskglob' {
            $ts = @(Get-TaskGlobTasks $d.P)
            $bad = @($ts | Where-Object { -not (Test-TaskDisabled $_) })
            $ok = ($bad.Count -eq 0); $actual = "всего $($ts.Count), активных $($bad.Count)"
        }
        'env' {
            $v = [Environment]::GetEnvironmentVariable($d.P, 'User')
            $actual = if ($v) { $v } else { 'не задано' }
            $ok = ("$v" -eq "$($d.V)")
        }
        'vscode' {
            $v = Get-VsCodeValue $d.P
            $actual = if ($null -eq $v) { 'не задано' } else { "$v" }
            $ok = ($null -ne $v) -and ("$v".ToLower() -eq "$($d.V)".ToLower())
        }
        'firefox' {
            $v = Get-FirefoxPolicy $d.P
            $actual = if ($null -eq $v) { 'не задано' } else { "$v" }
            $ok = ($null -ne $v) -and ("$v".ToLower() -eq "$($d.V)".ToLower())
        }
        { $_ -in @('hosts', 'gdidhosts', 'gdidlockhosts') } {
            $hk = $(switch ($d.T) { 'gdidhosts' { 'gdid' } 'gdidlockhosts' { 'lock' } default { 'telemetry' } })
            $ok = Test-HostsBlockCurrent -Kind $hk
            $actual = if ($ok) { 'блок установлен' } elseif (Test-HostsBlock -Kind $hk) { 'блок устарел' } else { 'нет блока' }
        }
        'gdidwipe' {
            # «Копий не нашлось» — ещё не «номера нет»: места без доступа и
            # профили, которые сейчас не вошли в Windows, не проверены. Раньше
            # проверка говорила «номера нет», не заглянув туда. Страж такой
            # ответ сбитой настройкой не считает: стирание доступа не даст.
            $sc = Get-GdidScan
            $ok = ($sc.state -eq 'NotFound')
            $actual = $(switch ($sc.state) { 'NotFound' { 'номера нет' } 'Found' { 'номер на месте' } default { 'не проверено: есть места без доступа или профили, которые сейчас не вошли в Windows' } })
            if ($sc.state -eq 'Unverified') { $unverified = $true }
        }
        'fwips' {
            $ok = Test-FwIpRule -Fresh
            $actual = if ($ok) { 'адреса заблокированы' } elseif (Test-FwIpRule) { 'адреса устарели' } else { 'нет правила' }
        }
        'fwsvc' { $ok = Test-FwRule -Kind 'svc' -Target $d.P; $actual = if ($ok) { 'правило есть' } else { 'нет правила' } }
        'fwapp' { $ok = Test-FwRule -Kind 'app' -Target $d.P; $actual = if ($ok) { 'правило есть' } else { 'нет правила' } }
    }
    $res = @{ module=$d.M; name=$d.C; ok=[bool]$ok; expected="$($d.V)"; actual=$actual }
    if ($unverified) { $res['unverified'] = $true }
    return $res
}

# --- hosts ------------------------------------------------------------------ #
$script:HostsDomains = @(
    'vortex.data.microsoft.com','vortex-win.data.microsoft.com','telecommand.telemetry.microsoft.com',
    'telemetry.microsoft.com','watson.telemetry.microsoft.com','oca.telemetry.microsoft.com',
    'sqm.telemetry.microsoft.com','df.telemetry.microsoft.com','wes.df.telemetry.microsoft.com',
    'reports.wes.df.telemetry.microsoft.com','services.wes.df.telemetry.microsoft.com','sqm.df.telemetry.microsoft.com',
    'telemetry.urs.microsoft.com','choice.microsoft.com','v10.events.data.microsoft.com','v20.events.data.microsoft.com',
    'us-v10.events.data.microsoft.com','eu-v10.events.data.microsoft.com','self.events.data.microsoft.com',
    'functional.events.data.microsoft.com','browser.pipe.aria.microsoft.com','mobile.pipe.aria.microsoft.com',
    'telemetry.appex.bing.net','nexus.officeapps.live.com','nexusrules.officeapps.live.com',
    'eu-mobile.events.data.microsoft.com','us-mobile.events.data.microsoft.com',
    'jp.events.data.microsoft.com','uk.events.data.microsoft.com',
    'in.events.data.microsoft.com','au.events.data.microsoft.com',
    'ca.events.data.microsoft.com','br.events.data.microsoft.com',
    'de.events.data.microsoft.com','fr.events.data.microsoft.com',
    'asia.events.data.microsoft.com','tb.events.data.microsoft.com',
    'v10.vortex-win.data.microsoft.com','v10c.events.data.microsoft.com',
    'events-sandbox.data.microsoft.com','events.data.microsoft.com',
    'watson.events.data.microsoft.com','umwatson.events.data.microsoft.com',
    'settings-win.data.microsoft.com','settings-sandbox.data.microsoft.com',
    'ceuswatcab01.blob.core.windows.net','ceuswatcab02.blob.core.windows.net',
    'eaus2watcab01.blob.core.windows.net','eaus2watcab02.blob.core.windows.net',
    'weus2watcab01.blob.core.windows.net','weus2watcab02.blob.core.windows.net',
    'oca.telemetry.microsoft.com.nsatc.net','sqm.telemetry.microsoft.com.nsatc.net',
    'telecommand.telemetry.microsoft.com.nsatc.net','vortex-sandbox.data.microsoft.com',
    'cs11.wpc.v0cdn.net','cs1137.wpc.gammacdn.net','modern.watson.data.microsoft.com',
    'browser.events.data.msn.com',
    # Найдены разбором чистой Windows 11 25H2 (сборка 26300): адреса прямой
    # отправки 1DS, зашитые в системные файлы и в скачанную настройку UTC.
    # mobile.events — главный из них: на него шлют Защитник (MDCoreSvc),
    # оболочка (AriaSDKWrapper.dll), Copilot, «Архивация» и «История файлов»,
    # минуя службу DiagTrack. Региональные v20 UTC выбирает по стране.
    'mobile.events.data.microsoft.com','au-mobile.events.data.microsoft.com',
    'jp-mobile.events.data.microsoft.com','uk-mobile.events.data.microsoft.com',
    'pf.events.data.microsoft.com','eu-office.events.data.microsoft.com',
    'browser.events.data.microsoft.com','nw-umwatson.events.data.microsoft.com',
    'au-v10.events.data.microsoft.com','in-v10.events.data.microsoft.com','jp-v10.events.data.microsoft.com',
    'au-v20.events.data.microsoft.com','eu-v20.events.data.microsoft.com','in-v20.events.data.microsoft.com',
    'jp-v20.events.data.microsoft.com','uk-v20.events.data.microsoft.com','us-v20.events.data.microsoft.com',
    'us4-v20.events.data.microsoft.com','us5-v20.events.data.microsoft.com',
    'au.vortex-win.data.microsoft.com','uk.vortex-win.data.microsoft.com','web.vortex.data.microsoft.com',
    'settings.data.microsoft.com','evrsettings-win.data.microsoft.com',
    'activity.windows.com',
    # licensing.mp.microsoft.com здесь больше нет: DNS ведёт его на общий
    # вход frontdoor.licensing.commerce.microsoft.com, через который идут и
    # лицензии приложений Магазина. Закрыв его, программа ломала бы платные
    # приложения, а человек не связал бы это с настройкой приватности.
    # В наблюдении за сетью это имя осталось (TelemetryDnsRegex): видно, что
    # обращение было, но блокировка его не касается.
    # Найдено записью Windows 11 с программой на максимуме: эти адреса всё ещё
    # получали данные. bat.bing.com — рекламный счётчик Bing в Магазине;
    # nelreports.net — отчёты Edge и других программ о сетевых ошибках
    # (Network Error Logging); default.exp-tas.com — раздача экспериментов
    # приложениям («Фотографии», VS Code). Без них всё работает как прежде.
    'bat.bing.com','deff.nelreports.net','aefd.nelreports.net','default.exp-tas.com')
$script:HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"

# Имена, адреса которых делят с чужими службами: по IP их блокировать нельзя
# (см. Get-TelemetryIpList). Проверено запросами DNS: watcab-узлы отвечают
# адресом общего хранилища Azure, default.exp-tas.com — края e-msedge.
$script:FwIpSharedRx = '\.blob\.core\.windows\.net$|^default\.exp-tas\.com$|^bat\.bing\.com$|\.nelreports\.net$|' +
                       '^telemetry\.appex\.bing\.net$|officeapps\.live\.com$|\.data\.msn\.com$|' +
                       '^activity\.windows\.com$|^choice\.microsoft\.com$|\.v0cdn\.net$|\.gammacdn\.net$|' +
                       '^licensing\.mp\.microsoft\.com$'

# Серверы, через которые компьютер регистрируется в каталоге устройств Microsoft
# и сообщает номер устройства. login.live.com здесь нет и быть не должно: без
# него перестанет работать вход в учётную запись Microsoft. Первые три имени
# публично не разрешаются, но Windows их спрашивает — блокировать есть что.
# cs.dds.microsoft.com — нынешний адрес каталога: остальные имена каталога
# публично не разрешаются, но Windows их спрашивает.
$script:GdidHosts = @('cs.dds.microsoft.com', 'dds.microsoft.com', 'fd.dds.microsoft.com', 'aad.cs.dds.microsoft.com',
                      'cdpcs.access.microsoft.com', 'geo.prod.do.dsp.mp.microsoft.com')

# Сервер, который выдаёт номер новому устройству. Его закрывает только запрет
# выдачи (модуль gdidlock) и только у тех, кто входит в Windows без учётной
# записи Microsoft: без него эта учётная запись не работает вовсе.
$script:GdidLockHosts = @('login.live.com', 'account.live.com')

# У блоков номера устройства свои метки: блок телеметрии и они ставятся и
# проверяются порознь. Общий шаблон $script:HostsMarkRegex узнаёт все — откат
# убирает всё, что программа дописала в hosts.
$script:HostsMarkGdidStart = '# --- Win11Privacy: device id block (begin) ---'
$script:HostsMarkGdidEnd   = '# --- Win11Privacy: device id block (end) ---'
$script:HostsMarkLockStart = '# --- Win11Privacy: device id lock (begin) ---'
$script:HostsMarkLockEnd   = '# --- Win11Privacy: device id lock (end) ---'

# Блок телеметрии — любая метка программы, кроме меток номера устройства:
# так узнаются и метки прежних версий, побитые в «?». Это «блок задуман»
# (есть метка); стоит ли он целым и с нужным списком — Test-HostsBlockCurrent.
function Test-HostsBlock {
    param([string]$Kind = 'telemetry')
    try { $lines = @(Get-Content -LiteralPath $script:HostsPath -ErrorAction Stop) } catch { return $false }
    if ($Kind -eq 'gdid') { return [bool]($lines -contains $script:HostsMarkGdidStart) }
    if ($Kind -eq 'lock') { return [bool]($lines -contains $script:HostsMarkLockStart) }
    return [bool](@(@($lines -match $script:HostsMarkRegex) | Where-Object { $_ -notlike '*device id*' }).Count -gt 0)
}

# Принадлежит ли открывающая метка блоку этого вида
function Test-HostsMarkKind {
    param([string]$Line, [string]$Kind)
    $m = Get-HostsMarkInfo $Line
    if ($null -eq $m) { return $false }
    return (Test-HostsKindMatch $m.kind $Kind)
}

# Метка программы: вид блока (gdid, lock, telemetry; devid — побитая метка
# номера устройства) и край (start, end; '' — метка прежней версии, побитая
# в «?»: начало это или конец, решает порядок). Не метка — $null.
function Get-HostsMarkInfo {
    param([string]$Line)
    if ("$Line" -notmatch $script:HostsMarkRegex) { return $null }
    $t = "$Line".TrimEnd()
    if ($t -eq $script:HostsMarkGdidStart) { return @{ kind = 'gdid'; edge = 'start' } }
    if ($t -eq $script:HostsMarkGdidEnd) { return @{ kind = 'gdid'; edge = 'end' } }
    if ($t -eq $script:HostsMarkLockStart) { return @{ kind = 'lock'; edge = 'start' } }
    if ($t -eq $script:HostsMarkLockEnd) { return @{ kind = 'lock'; edge = 'end' } }
    if ($t -like '*device id*') { return @{ kind = 'devid'; edge = '' } }
    if ($t -eq $script:HostsMarkStart) { return @{ kind = 'telemetry'; edge = 'start' } }
    if ($t -eq $script:HostsMarkEnd) { return @{ kind = 'telemetry'; edge = 'end' } }
    return @{ kind = 'telemetry'; edge = '' }
}

# Блок вида $BlockKind попадает под снятие/проверку вида $Kind (all — все)
function Test-HostsKindMatch {
    param([string]$BlockKind, [string]$Kind)
    if ($Kind -eq 'all') { return $true }
    if ($Kind -in @('gdid', 'lock')) { return ($BlockKind -eq $Kind) }
    return ($BlockKind -eq 'telemetry')
}

# Домены блока этого вида
function Get-HostsKindDomains {
    param([string]$Kind)
    switch ($Kind) {
        'gdid'  { return @($script:GdidHosts) }
        'lock'  { return @($script:GdidLockHosts) }
        'devid' { return @(@($script:GdidHosts) + @($script:GdidLockHosts)) }
    }
    return @($script:HostsDomains)
}

# Строка «0.0.0.0» отвечает только на запрос IPv4. Если у сервера есть адрес
# IPv6, Windows спросит его у DNS и соединится мимо блока — поэтому на каждое
# имя пишется и строка «::».
function Get-HostsWanted {
    param([string]$Kind = 'telemetry')
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($d in @(Get-HostsKindDomains $Kind)) { $out.Add('0.0.0.0 ' + $d); $out.Add(':: ' + $d) }
    return $out.ToArray()
}

$script:HostsMarkLineRx = '^\s*(0\.0\.0\.0|::)\s+(\S+)\s*$'

# Блоки программы в hosts. Блок — открывающая метка, его строки и
# закрывающая метка ТОГО ЖЕ вида. Раньше любая следующая метка считалась
# концом блока, а закрывающая метка, оставшаяся без пары, — началом нового:
# стёртая метка одного блока уносила при снятии строки, которые человек
# вписал сам, а порядок блоков ломался.
#   closed — у блока есть своя закрывающая метка: всё между метками в виде
#            «0.0.0.0 имя» / «:: имя» — его строки, чужие строки внутри
#            остаются на месте;
#   без неё — блоку принадлежат только идущие следом строки ЕГО доменов:
#            первая другая строка — уже не его.
# orphans — закрывающие метки без начала: их программа убирает.
function Split-HostsBlocks {
    param([string[]]$Lines)
    $src = [string[]]@($Lines)
    $blocks = New-Object System.Collections.Generic.List[object]
    $orphans = New-Object System.Collections.Generic.List[object]
    $cur = $null
    for ($i = 0; $i -lt $src.Count; $i++) {
        $m = Get-HostsMarkInfo $src[$i]
        if ($null -eq $m) { continue }
        if ($null -ne $cur) {
            if ($m.kind -eq $cur.kind -and $m.edge -ne 'start') { $cur.end = $i; $cur.closed = $true; $blocks.Add($cur); $cur = $null; continue }
            $blocks.Add($cur); $cur = $null
        }
        if ($m.edge -eq 'end') { $orphans.Add(@{ index = $i; kind = $m.kind }); continue }
        $cur = @{ kind = $m.kind; start = $i; end = -1; closed = $false }
    }
    if ($null -ne $cur) { $blocks.Add($cur) }
    foreach ($b in $blocks) {
        $own = New-Object System.Collections.Generic.List[int]
        if ($b.closed) {
            for ($i = $b.start + 1; $i -lt $b.end; $i++) {
                if ($src[$i] -match $script:HostsMarkLineRx -or $src[$i] -match '^\s*$') { $own.Add($i) }
            }
        } else {
            $known = @{}
            foreach ($d in @(Get-HostsKindDomains $b.kind)) { $known["$d".ToLowerInvariant()] = $true }
            for ($i = $b.start + 1; $i -lt $src.Count; $i++) {
                $l = $src[$i]
                if ($l -match '^\s*$') { $own.Add($i); continue }
                if ($l -match $script:HostsMarkLineRx -and $known.ContainsKey($Matches[2].ToLowerInvariant())) { $own.Add($i); continue }
                break
            }
            # пустые строки в хвосте — уже разделитель перед чужим
            while ($own.Count -gt 0 -and $src[$own[$own.Count - 1]] -match '^\s*$') { $own.RemoveAt($own.Count - 1) }
        }
        $b['own'] = $own.ToArray()
    }
    return @{ blocks = $blocks.ToArray(); orphans = $orphans.ToArray() }
}

function Get-HostsBlockLines {
    param([string]$Kind = 'telemetry')
    $out = New-Object System.Collections.Generic.List[string]
    try { $lines = Read-HostsLines } catch { return @() }
    $sp = Split-HostsBlocks $lines
    foreach ($b in @($sp.blocks)) {
        if (-not (Test-HostsKindMatch $b.kind $Kind)) { continue }
        foreach ($i in @($b.own)) { if ($lines[$i] -match $script:HostsMarkLineRx) { $out.Add($Matches[1] + ' ' + $Matches[2]) } }
    }
    return $out.ToArray()
}

# Блок стоит, цел и в нём ровно нужный список: один блок этого вида, со своей
# закрывающей меткой, без повторов и лишних строк, без осиротевших меток.
# Раньше хватало открывающей метки: блок с выкинутыми строками или без конца
# считался работающим, а второй такой же блок — тем же самым первым.
function Test-HostsBlockCurrent {
    param([string]$Kind = 'telemetry')
    try { $lines = Read-HostsLines } catch { return $false }
    $sp = Split-HostsBlocks $lines
    $mine = @(@($sp.blocks) | Where-Object { Test-HostsKindMatch $_.kind $Kind })
    if ($mine.Count -ne 1 -or -not $mine[0].closed) { return $false }
    if (@(@($sp.orphans) | Where-Object { Test-HostsKindMatch $_.kind $Kind }).Count -gt 0) { return $false }
    $have = New-Object System.Collections.Generic.List[string]
    foreach ($i in @($mine[0].own)) { if ($lines[$i] -match $script:HostsMarkLineRx) { $have.Add(($Matches[1] + ' ' + $Matches[2]).ToLowerInvariant()) } }
    $want = @(@(Get-HostsWanted -Kind $Kind) | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
    if ($have.Count -ne $want.Count) { return $false }
    $set = @{}
    foreach ($h in $have) { $set[$h] = $true }
    if ($set.Count -ne $have.Count) { return $false }          # повторы
    foreach ($w in $want) { if (-not $set.ContainsKey($w)) { return $false } }
    return $true
}

function Apply-Hosts {
    param([string]$Kind = 'telemetry')
    $wanted = @(Get-HostsWanted -Kind $Kind)
    $count = [int]($wanted.Count / 2)
    $present = Test-HostsBlock -Kind $Kind
    if ($present -and (Test-HostsBlockCurrent -Kind $Kind)) { Write-Log '   [-] блок уже присутствует'; return }
    if ($DryRun) {
        Write-Log $(if ($present) { "   [тест] блок будет обновлён до доменов: $count" } else { "   [тест] будет заблокировано доменов: $count" })
        return
    }
    try {
        if ($script:BackupDir -and (Test-Path -LiteralPath $script:BackupDir)) {
            $copy = Join-Path $script:BackupDir 'hosts.original'
            # копия нужна та, что была до программы, а не после первого блока
            if (-not (Test-Path -LiteralPath $copy)) { Copy-Item -LiteralPath $script:HostsPath -Destination $copy -Force -ErrorAction SilentlyContinue }
        }
        # Весь файл — одной подменой: прежние блоки этого вида (и побитые,
        # и повторные) убраны, новый дописан, всё чужое на месте. Раньше
        # прежний блок удалялся отдельной записью, а новый дописывался следом
        # (Add-Content): между ними блока не было вовсе, а оборванная
        # дозапись оставляла его половину.
        $cut = Get-HostsLinesWithout (Read-HostsLines) $Kind
        $block = @('') + $(switch ($Kind) { 'gdid' { $script:HostsMarkGdidStart } 'lock' { $script:HostsMarkLockStart } default { $script:HostsMarkStart } })
        $block += $wanted
        $block += $(switch ($Kind) { 'gdid' { $script:HostsMarkGdidEnd } 'lock' { $script:HostsMarkLockEnd } default { $script:HostsMarkEnd } })
        Write-HostsFile (@($cut.keep) + $block)
        ipconfig /flushdns | Out-Null
        # «Записалось» — ещё не «стоит»: hosts тут же может поправить
        # антивирус (Защитник так поступает с блоками адресов Microsoft)
        if (-not (Test-HostsBlockCurrent -Kind $Kind)) {
            Write-Log '   [!] hosts записан, но блок читается не таким, как задуман -- возможно, файл сразу изменил антивирус'
            $script:Failures++; return
        }
        if ($present) { Write-Log ("   [+] список доменов обновлён, теперь их: {0}" -f $count) }
        else { Write-Log ("   [+] заблокировано доменов: {0}" -f $count) }
        $script:Changes++
    } catch { Write-Log "   [!] не удалось изменить hosts: $($_.Exception.Message) (возможно, защищён антивирусом)"; $script:Failures++ }
}

# Kind = all убирает все блоки программы (общий откат); telemetry, gdid и
# lock — только блок своего вида, остальные остаются на месте.
# $true — блока больше нет (убран или не было), $false — hosts не переписался
# (посчитано ошибкой). Файл пишется рядом и подменяет прежний одним действием
# системы: раньше hosts переписывался на месте, и обрыв посередине оставлял
# его недописанным — вместе со строками, которые человек вписал сам.
function Remove-HostsBlock {
    param([string]$Kind = 'all', [switch]$Quiet)
    try {
        $cut = Get-HostsLinesWithout (Read-HostsLines) $Kind
        if ($cut.found -eq 0) { if (-not $Quiet) { Write-Log '   [-] блока в hosts нет' }; return $true }
        Write-HostsFile $cut.keep
        ipconfig /flushdns | Out-Null
        # переписан — ещё не «блока нет»: сверяем
        if ((Get-HostsLinesWithout (Read-HostsLines) $Kind).found -gt 0) { throw 'после записи блок в hosts остался' }
        if (-not $Quiet) { Write-Log '   [+] блок блокировки доменов удалён' }
        return $true
    } catch {
        Write-Log ("   [!] hosts не переписался ({0}) -- блок остался на месте" -f $_.Exception.Message)
        $script:Failures++
        return $false
    }
}

# Кодировка hosts — та, в которой он лежит: метка UTF-8 или UTF-16 — она,
# иначе системная ANSI (так его пишет Windows; чужие строки с нелатинскими
# буквами остаются байт в байт).
function Get-HostsEncoding {
    $b = New-Object byte[] 3
    $n = 0
    $fs = [IO.File]::Open($script:HostsPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try { $n = $fs.Read($b, 0, 3) } finally { $fs.Dispose() }
    if ($n -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return (New-Object System.Text.UTF8Encoding $true) }
    if ($n -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { return [System.Text.Encoding]::Unicode }
    return [System.Text.Encoding]::Default
}

function Read-HostsLines { return , ([string[]][IO.File]::ReadAllLines($script:HostsPath, (Get-HostsEncoding))) }

# Строки hosts без блоков программы этого вида (см. Split-HostsBlocks): метки,
# свои строки блоков и закрывающие метки без пары. Пустую строку перед блоком
# ставила сама программа. found — сколько блоков и осиротевших меток убрано.
function Get-HostsLinesWithout {
    param([string[]]$Lines, [string]$Kind)
    $src = [string[]]@($Lines)
    $sp = Split-HostsBlocks $src
    $drop = @{}
    $found = 0
    foreach ($b in @($sp.blocks)) {
        if (-not (Test-HostsKindMatch $b.kind $Kind)) { continue }
        $found++
        $drop[[int]$b.start] = $true
        if ($b.closed) { $drop[[int]$b.end] = $true }
        foreach ($i in @($b.own)) { $drop[[int]$i] = $true }
        if ($b.start -gt 0 -and $src[$b.start - 1] -eq '') { $drop[[int]($b.start - 1)] = $true }
    }
    foreach ($o in @($sp.orphans)) {
        if (-not (Test-HostsKindMatch $o.kind $Kind)) { continue }
        $found++
        $drop[[int]$o.index] = $true
    }
    $keep = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $src.Count; $i++) { if (-not $drop.ContainsKey($i)) { $keep.Add($src[$i]) } }
    return @{ keep = $keep.ToArray(); found = $found }
}

# hosts целиком: копия рядом (в той же кодировке), сверка копии строка в
# строку, затем подмена одним действием системы (ReplaceFile — права и
# атрибуты прежнего файла сохраняются). Обрыв в любой миг оставляет либо
# прежний hosts, либо новый, но не половину. Копия после себя не остаётся.
function Write-HostsFile {
    param([string[]]$Lines)
    $enc = Get-HostsEncoding
    $tmp = $script:HostsPath + '.w11p-new'
    $want = [string[]]@($Lines)
    try {
        [IO.File]::WriteAllLines($tmp, $want, $enc)
        $back = [IO.File]::ReadAllLines($tmp, $enc)
        if ($back.Count -ne $want.Count) { throw 'копия hosts не совпала с задуманной' }
        for ($i = 0; $i -lt $back.Count; $i++) { if ($back[$i] -cne $want[$i]) { throw ('копия hosts не совпала с задуманной в строке {0}' -f ($i + 1)) } }
        Replace-FileAtomic $tmp $script:HostsPath
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

# --- брандмауэр ------------------------------------------------------------- #
function Get-FwRuleName {
    param([string]$Kind, [string]$Target)
    if ($Kind -eq 'svc') { return "Win11Privacy: служба $Target" }
    # Имя правила для программы включает короткий хеш её полного пути. Раньше в
    # имени было только имя файла: у двух программ с одинаковым именем в разных
    # папках правило было одно. Блокировка второй не создавала правила («имя уже
    # есть»), но отвечала «заблокировано», а возврат одной снимал правило другой.
    $full = $Target
    try { $full = [IO.Path]::GetFullPath($Target) } catch { }
    $h = ''
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $h = (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($full.ToLowerInvariant()))[0..3] | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() }
    } catch { }
    # Хвост «#хеш», а не «[хеш]»: Get-NetFirewallRule -DisplayName понимает имя
    # как шаблон, и квадратные скобки стали бы в нём классом символов — правило
    # потом не нашлось бы ни для проверки, ни для снятия. В «#» и шестнадцатеричных
    # цифрах знаков шаблона нет.
    return ("Win11Privacy: " + (Split-Path $Target -Leaf) + $(if ($h) { " #$h" } else { '' }))
}

function Test-FwRule {
    param([string]$Kind, [string]$Target)
    $r = Get-NetFirewallRule -DisplayName (Get-FwRuleName $Kind $Target) -ErrorAction SilentlyContinue
    return [bool]($r -and $r.Enabled -eq 'True')
}

function Apply-FwRule {
    param([string]$Kind, [string]$Target, [string]$Comment)
    if ($DryRun) { Write-Log "   [тест] $Comment"; return }
    $name = Get-FwRuleName $Kind $Target
    try {
        if (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue) { Write-Log "   [-] $Comment -- уже есть"; return }
        if ($Kind -eq 'svc') {
            New-NetFirewallRule -DisplayName $name -Group $script:FwGroup -Direction Outbound -Action Block -Service $Target -Profile Any -Enabled True -ErrorAction Stop | Out-Null
        } else {
            New-NetFirewallRule -DisplayName $name -Group $script:FwGroup -Direction Outbound -Action Block -Program $Target -Profile Any -Enabled True -ErrorAction Stop | Out-Null
        }
        Write-Log "   [+] $Comment"; $script:Changes++
    } catch { Write-Log "   [!] не удалось: $Comment -- $($_.Exception.Message)"; $script:Failures++ }
}

# Адреса телеметрии: часть известна давно, часть узнаём разбором имён
# перед самой блокировкой — так список не устаревает.
$script:FwIpRuleName = 'Win11Privacy: адреса телеметрии'
$script:TelemetryIps = @(
    '13.64.90.137','13.68.31.193','13.68.82.8','13.69.109.130','13.69.239.72',
    '13.73.26.107','20.44.86.43','40.79.85.125','51.104.136.2',
    '65.52.100.7','65.52.100.9','65.52.100.11','65.55.252.43','65.55.252.63',
    '65.55.252.70','65.55.252.71','65.55.252.92','65.55.252.93',
    '66.119.144.157','168.61.24.141','168.61.146.25','168.62.187.13',
    '191.232.139.2','191.232.80.58','191.239.52.100'
)

# Имена спрашиваются все сразу, а не по одному. Части адресов из списка давно
# нет, и на каждый такой запрос Windows ждёт ответа DNS: за VPN или при
# молчащем DNS роутера — по 10–15 секунд. По очереди шаг тянулся минутами без
# единой строки в журнале и выглядел зависшим. Кто не ответил за отведённое
# время, в правило не попадёт — известные адреса выше в нём есть всегда.
# Имена спрашиваются у DNS-сервера В ОБХОД hosts. Раньше разрешение шло через
# системный резолвер, а он сначала смотрит в hosts: при стоящем блоке каждое
# имя «разрешалось» в 0.0.0.0, отсеивалось, и в правило попадали только
# зашитые адреса. Имена спрашиваются все сразу, в пуле потоков: по одному шаг
# тянулся минутами, пока мёртвые имена ждали ответа. Берутся и адреса IPv6.
function Get-TelemetryIpList {
    param([int]$TimeoutMs = 10000)
    $set = @{}
    foreach ($ip in $script:TelemetryIps) { $set[$ip] = $true }
    # Правило брандмауэра закрывает адреса для ВСЕХ программ, а часть имён
    # сбора живёт на общих узлах: ceuswatcab01.blob.core.windows.net — это
    # общий узел Azure Storage, default.exp-tas.com — общий край e-msedge,
    # nexus.officeapps.live.com — общий вход Office (проверено запросами DNS).
    # Закрыв такой адрес, программа закрыла бы вместе с ним чужие службы —
    # чьи-то файлы в облаке, обновления, лицензии. По IP эти имена не
    # блокируются; в hosts они остаются, и там блокировка точная, по имени.
    $shared = @($script:HostsDomains | Where-Object { $_ -match $script:FwIpSharedRx } | Select-Object -Unique)
    $names = @($script:HostsDomains | Where-Object { $_ -notmatch $script:FwIpSharedRx } | Select-Object -Unique)
    if ($shared.Count -gt 0) {
        Write-Log ("   имён на общих узлах (их адреса делят чужие службы) не блокируется по IP: {0} -- в hosts они закрыты" -f $shared.Count)
    }
    $pool = [runspacefactory]::CreateRunspacePool(1, 32)
    $pool.Open()
    $jobs = New-Object System.Collections.Generic.List[object]
    foreach ($nm in $names) {
        $parsed = $null
        if ([System.Net.IPAddress]::TryParse($nm, [ref]$parsed)) { if (Test-PublicIp $nm) { $set[$nm] = $true }; continue }
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        # -DnsOnly: мёртвое имя не уходит искать себя по локальной сети (LLMNR, NetBIOS)
        $null = $ps.AddScript('param($n) @(Resolve-DnsName -Name $n -Type A_AAAA -NoHostsFile -DnsOnly -QuickTimeout -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress } | ForEach-Object { [string]$_.IPAddress })').AddArgument($nm)
        $jobs.Add(@{ ps = $ps; h = $ps.BeginInvoke() })
    }
    $until = (Get-Date).AddMilliseconds($TimeoutMs)
    $answered = 0
    foreach ($j in $jobs) {
        $left = [int][math]::Max(0, ($until - (Get-Date)).TotalMilliseconds)
        if ($j.h.AsyncWaitHandle.WaitOne($left)) {
            try {
                $res = @($j.ps.EndInvoke($j.h))
                if ($res.Count -gt 0) { $answered++ }
                foreach ($a in $res) { if (Test-PublicIp "$a") { $set["$a"] = $true } }
            } catch { }
            $j.ps.Dispose()
        } else {
            # Не ответившее имя не ждём: синхронная остановка висела бы, пока
            # DNS не сдастся сам. Хвосты уйдут вместе с процессом движка.
            try { $null = $j.ps.BeginStop($null, $null) } catch { }
        }
    }
    try { $null = $pool.BeginClose($null, $null) } catch { }
    return @{ ips = @($set.Keys); answered = $answered; asked = $names.Count }
}

# Правило помнит дату обновления в описании. Адреса серверов меняются, и
# старше двух недель правило считается устаревшим — страж его обновит.
function Test-FwIpRule {
    param([switch]$Fresh)
    $r = Get-NetFirewallRule -DisplayName $script:FwIpRuleName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $r) { return $false }
    if (-not $Fresh) { return $true }
    if ("$($r.Description)" -match '(\d{4}-\d{2}-\d{2})') { try { return ([datetime]$Matches[1]) -gt (Get-Date).AddDays(-14) } catch { } }
    return $false
}

# IP-адрес в каноническом виде (IPv6 — сжатый, строчными), не адрес — $null
function ConvertTo-IpCanonical {
    param([string]$Text)
    $ip = $null
    if ([System.Net.IPAddress]::TryParse("$Text".Trim(), [ref]$ip)) { return $ip.ToString().ToLowerInvariant() }
    return $null
}

function Apply-FwIpBlock {
    if ($DryRun) { Write-Log '   [тест] будут заблокированы адреса сбора телеметрии'; return }
    try {
        Write-Log '   узнаю текущие адреса серверов сбора — не дольше 10 секунд'
        $found = Get-TelemetryIpList
        $ips = @($found.ips)
        Write-Log ("   ответили DNS имён: {0} из {1}" -f $found.answered, $found.asked)
        # каждый адрес — в каноническом виде и один раз: «2001:DB8::1» и
        # «2001:db8:0::1» — один адрес, и сверять потом надо множества
        $wantSet = @{}
        foreach ($a in $ips) { $n = ConvertTo-IpCanonical $a; if ($n) { $wantSet[$n] = $true } }
        $ips = @($wantSet.Keys | Sort-Object)
        if ($ips.Count -eq 0) { Write-Log '   [-] адреса не определились'; return }
        # Новое правило ставится рядом со старым, проверяется, и только потом
        # старое убирается. Раньше старое удалялось первым: не создалось
        # новое — не оставалось никакого, и адреса сбора открывались.
        $old = @(Get-NetFirewallRule -DisplayName $script:FwIpRuleName -ErrorAction SilentlyContinue)
        $id = 'Win11Privacy-TelemetryIp-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        New-NetFirewallRule -Name $id -DisplayName $script:FwIpRuleName -Group $script:FwGroup -Direction Outbound -Action Block `
            -RemoteAddress $ips -Profile Any -Enabled True -Description ('Win11Privacy: updated ' + (Get-Date).ToString('yyyy-MM-dd')) -ErrorAction Stop | Out-Null
        $why = ''
        $new = Get-NetFirewallRule -Name $id -ErrorAction SilentlyContinue
        if (-not $new) { $why = 'правило не появилось' }
        elseif ("$($new.Enabled)" -ne 'True' -or "$($new.Action)" -ne 'Block' -or "$($new.Direction)" -ne 'Outbound') { $why = 'правило создалось не таким, как задумано' }
        else {
            # множество адресов в правиле — ровно то, что задумано: не только
            # сколько, но и какие (раньше сверялось одно число)
            $gotSet = @{}
            foreach ($a in @((Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $new -ErrorAction Stop).RemoteAddress)) {
                $n = ConvertTo-IpCanonical $a
                $gotSet[$(if ($n) { $n } else { "?$a" })] = $true
            }
            $missing = @($wantSet.Keys | Where-Object { -not $gotSet.ContainsKey($_) } | Sort-Object)
            $extra = @($gotSet.Keys | Where-Object { -not $wantSet.ContainsKey($_) } | Sort-Object)
            if ($missing.Count -or $extra.Count) {
                $why = ("в правиле не те адреса: нет {0}, лишние {1}" -f $(if ($missing.Count) { $missing -join ', ' } else { '—' }), $(if ($extra.Count) { $extra -join ', ' } else { '—' }))
            }
        }
        if ($why) {
            Remove-NetFirewallRule -Name $id -ErrorAction SilentlyContinue
            Write-Log ("   [!] новое правило не прошло проверку ({0}) -- {1}" -f $why, $(if ($old.Count) { 'оставлено прежнее' } else { 'адреса не заблокированы' }))
            $script:Failures++; return
        }
        foreach ($o in $old) {
            try { Remove-NetFirewallRule -Name $o.Name -ErrorAction Stop }
            catch { Write-Log ("   [!] прежнее правило адресов не убралось: {0}" -f $_.Exception.Message); $script:Failures++ }
        }
        Write-Log ("   [+] заблокировано адресов: {0}" -f $ips.Count)
        Write-Log '   [-] если что-то перестанет работать — снимите этот пункт и нажмите «Откат»'
        $script:Changes++
    } catch { Write-Log "   [!] не удалось заблокировать адреса: $($_.Exception.Message)"; $script:Failures++ }
}

# Шифрованный DNS в системе и браузерах — через него hosts не работает
function Get-DohStatus {
    $win = $false
    try {
        $root = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters'
        foreach ($k in @(Get-ChildItem -LiteralPath $root -Recurse -ErrorAction SilentlyContinue)) {
            if ($k.PSChildName -match '^\d+\.' -or $k.PSPath -match 'DohInterfaceSettings') {
                $v = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).DohFlags
                if ($null -ne $v -and [int64]$v -ne 0) { $win = $true }
            }
        }
    } catch { }
    $policy = (Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'DoHPolicy')
    $edge = (Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DnsOverHttpsMode')
    $chrome = (Get-RegValue 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'DnsOverHttpsMode')
    return @{ windows = $win; policy = "$policy"; edge = "$edge"; chrome = "$chrome"
              blocked = ("$policy" -eq '1' -and "$edge" -eq 'off' -and "$chrome" -eq 'off') }
}

# --------------------------------------------------------------------------- #
#  Проверка утечек «в бою». Имя каждого известного сервера сбора разрешается
#  так, как его разрешит любая программа — с учётом hosts, — и к нему
#  пробуется соединение TCP на порт 443. Данных не уходит: соединение сразу
#  закрывается. Отвечает на вопрос, которого не задаёт проверка настроек:
#  доступны ли известные адреса сбора.
#
#  Это доступность адресов (endpointReachability), а не наблюдение за
#  трафиком (telemetryObserved): неизвестные и новые адреса, другие порты,
#  UDP и QUIC, отправка через сторонние службы этой проверке не видны. Раньше
#  «ни один сервер не отвечает» подавалось как «телеметрия не дойдёт».
#  Результат поэтому разделён: что проверено — и что не измерялось вовсе.
# --------------------------------------------------------------------------- #
function Invoke-LeakTest {
    param([int]$TimeoutMs = 8000)
    $names = @(@($script:HostsDomains) + @($script:GdidHosts) | Select-Object -Unique)
    # Имя, закрытое в hosts строками «0.0.0.0» и «::», Windows отдаёт как «нет
    # данных» — без этого списка оно попадало бы в «имя не отвечает».
    $sunk = @{}
    try {
        foreach ($l in @(Get-Content -LiteralPath $script:HostsPath -ErrorAction Stop)) {
            if ($l -match '^\s*(0\.0\.0\.0|::)\s+(\S+)') { $sunk[$Matches[2].ToLowerInvariant()] = $true }
        }
    } catch { }
    $w = 0; $io = 0
    [System.Threading.ThreadPool]::GetMinThreads([ref]$w, [ref]$io)
    if ($w -lt 64) { $null = [System.Threading.ThreadPool]::SetMinThreads(64, $io) }
    $dns = @{}
    $dnsTasks = New-Object System.Collections.Generic.List[System.Threading.Tasks.Task]
    foreach ($nm in $names) { try { $t = [System.Net.Dns]::GetHostAddressesAsync($nm); $dns[$nm] = $t; $dnsTasks.Add($t) } catch { } }
    # WaitAll бросает, если какое-то имя не существует, — это не ошибка
    if ($dnsTasks.Count -gt 0) { try { $null = [System.Threading.Tasks.Task]::WaitAll($dnsTasks.ToArray(), $TimeoutMs) } catch { } }

    $items = New-Object System.Collections.Generic.List[object]
    $conn = @{}
    $connTasks = New-Object System.Collections.Generic.List[System.Threading.Tasks.Task]
    foreach ($nm in $names) {
        $t = $dns[$nm]; $state = 'none'; $ip = ''
        if ($sunk.ContainsKey($nm.ToLowerInvariant())) { $state = 'hosts' }
        elseif ($t -and $t.Status -eq 'RanToCompletion') {
            $addrs = @($t.Result)
            $pub = @($addrs | Where-Object { Test-PublicIp $_.IPAddressToString })
            if ($addrs.Count -gt 0 -and $pub.Count -eq 0) { $state = 'hosts' }
            elseif ($pub.Count -gt 0) {
                $a = @($pub | Where-Object { "$($_.AddressFamily)" -eq 'InterNetwork' } | Select-Object -First 1)
                $a = $(if ($a.Count -gt 0) { $a[0] } else { $pub[0] })
                $ip = $a.IPAddressToString
                try {
                    $cl = New-Object System.Net.Sockets.TcpClient($a.AddressFamily)
                    $ct = $cl.ConnectAsync($a, 443)
                    $conn[$nm] = @{ client = $cl; task = $ct }; $connTasks.Add($ct)
                    $state = 'pending'
                } catch { $state = 'blocked' }
            }
        }
        $items.Add(@{ name = $nm; state = $state; ip = $ip })
    }
    if ($connTasks.Count -gt 0) { try { $null = [System.Threading.Tasks.Task]::WaitAll($connTasks.ToArray(), 4000) } catch { } }
    foreach ($it in $items) {
        if ($it.state -ne 'pending') { continue }
        $cn = $conn[$it.name]
        $it.state = $(if ("$($cn.task.Status)" -eq 'RanToCompletion' -and $cn.client.Connected) { 'open' } else { 'blocked' })
        try { $cn.client.Close() } catch { }
    }
    $count = { param($s) @($items | Where-Object { $_.state -eq $s }).Count }
    return @{ time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); doh = (Get-DohStatus)
              endpointReachability = @{
                  protocol = 'tcp'; port = 443; total = $items.Count
                  open = (& $count 'open'); blocked = (& $count 'blocked'); hosts = (& $count 'hosts'); none = (& $count 'none')
                  items = $items.ToArray()
                  # чего эта проверка не видит
                  notCovered = @('unknown-hosts', 'other-ports', 'udp-quic', 'third-party-relays') }
              # трафик не наблюдался: «никто не ответил» не значит «ничего не ушло»
              telemetryObserved = @{ measured = $false } }
}

function Remove-FwRules {
    try {
        $rules = @(Get-NetFirewallRule -Group $script:FwGroup -ErrorAction SilentlyContinue)
        if ($rules.Count -gt 0) { $rules | Remove-NetFirewallRule -ErrorAction SilentlyContinue; Write-Log "   [+] удалено правил брандмауэра: $($rules.Count)" }
        else { Write-Log '   [-] правил брандмауэра нет' }
    } catch { Write-Log "   [!] брандмауэр: $($_.Exception.Message)" }
}

# =========================================================================== #
#  НОМЕР УСТРОЙСТВА (GDID): где лежит, как сменить, как запретить выдачу
#  Номер — идентификатор «устройства» в службе учётных записей Microsoft
#  (Device PUID). Его выдаёт login.live.com, когда служба wlidsvc заводит
#  компьютеру «личность»: отдельную учётную запись устройства с ключом в
#  хранилище учётных данных. Номер привязан к этой личности, а не к железу —
#  поэтому переустановка Windows даёт новый. Копий номера в реестре несколько,
#  и пока цела личность, стёртые копии возвращаются тем же номером. Стереть
#  личность целиком — значит сменить номер: при следующем обращении Windows
#  заведёт новую и получит новый. Если сервер выдачи закрыт — не получит.
#  Разбор: github.com/SmtimesIWndr/gdid-reversal, github.com/yegors/deGDID.
# =========================================================================== #
$script:IdCrlRoots = @(
    @{ who = 'user';   path = 'HKCU:\SOFTWARE\Microsoft\IdentityCRL' },
    @{ who = 'system'; path = 'Registry::HKEY_USERS\.DEFAULT\Software\Microsoft\IdentityCRL' },
    @{ who = 'system'; path = 'Registry::HKEY_USERS\S-1-5-18\Software\Microsoft\IdentityCRL' })
$script:IdCrlNegCache = 'HKLM:\SOFTWARE\Microsoft\IdentityCRL\NegativeCache'
# Места, которые не удалось прочитать при последнем поиске копий: без них
# «копий не осталось» было бы неправдой.
$script:GdidUnreadable = New-Object System.Collections.Generic.List[string]
# Кэш платформы подключённых устройств: в нём регистрация в каталоге устройств
$script:CdpCache = Join-Path $env:LOCALAPPDATA 'ConnectedDevicesPlatform'

# Кроме своего профиля и системного — профили других пользователей, которые
# сейчас вошли в Windows: их кусты реестра подключены. Профили тех, кто сейчас
# не вошёл, не подключены — программа их не трогает и честно об этом пишет.
# Подключённые кусты реестра — одними именами, без открытия каждого
function Get-GdidHiveNames { return @([Microsoft.Win32.Registry]::Users.GetSubKeyNames()) }

# Профили людей: локальные и доменные учётные записи (S-1-5-21-…) и
# учётные записи Entra ID (S-1-12-1-…). Раньше вторые не считались вовсе.
$script:GdidUserSidRx = '^S-1-(5-21|12-1)-[\d-]+$'
$script:GdidProfileListKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'

function Get-IdCrlRoots {
    $roots = New-Object System.Collections.Generic.List[object]
    foreach ($r in $script:IdCrlRoots) { $roots.Add($r) }
    $me = ''
    try { $me = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value } catch { }
    # Список подключённых кустов не прочитался — копии номера у других
    # вошедших пользователей не искались, и это записано: опись тогда
    # Unverified, а стирание не начинается (Get-GdidPreflight). Раньше ошибка
    # глоталась, и «копий нет» говорилось, не заглянув к ним.
    $names = @()
    try { $names = @(Get-GdidHiveNames) } catch { $script:GdidUnreadable.Add('Registry::HKEY_USERS') }
    foreach ($sid in $names) {
        if ($sid -notmatch $script:GdidUserSidRx -or $sid -eq $me) { continue }
        $roots.Add(@{ who = 'other'; path = "Registry::HKEY_USERS\$sid\Software\Microsoft\IdentityCRL" })
    }
    return $roots.ToArray()
}

# Профили пользователей: какие подключены (их копии номера проверяются) и
# какие нет — тех, кто сейчас не вошёл в Windows: их куст не подключён, и
# программа его не подключает и не трогает. Ответ — не число, а опись:
#   loadedProfiles / unloadedProfiles (+ unloadedSids) — сколько каких;
#   enumerationFailed — список кустов (HKEY_USERS) или профилей (ProfileList)
#       не прочитался: сколько профилей не проверено, неизвестно. Раньше в
#       этом случае отвечалось «0», то есть «проверены все»;
#   unverified — проверены не все (есть неподключённые или список не прочитался);
#   places — что не прочиталось (для описи), errors — почему.
# state: Complete, Unloaded, EnumerationFailed.
function Get-UncheckedProfiles {
    $errs = New-Object System.Collections.Generic.List[string]
    $places = New-Object System.Collections.Generic.List[string]
    $loaded = $null
    try { $loaded = @(Get-GdidHiveNames) }
    catch { $places.Add('Registry::HKEY_USERS'); $errs.Add(("HKEY_USERS: {0}" -f $_.Exception.Message)) }
    $listed = $null
    $pl = $null
    try {
        $pl = Open-RegKeyRead $script:GdidProfileListKey
        # список профилей есть в любой Windows: его нет — прочитать не вышло
        if ($null -eq $pl) { $places.Add($script:GdidProfileListKey); $errs.Add('ProfileList: ключа нет') }
        else { $listed = @($pl.GetSubKeyNames()) }
    } catch { $places.Add($script:GdidProfileListKey); $errs.Add(("ProfileList: {0}" -f $_.Exception.Message)) }
    finally { if ($null -ne $pl) { $pl.Close() } }
    $loadedN = 0
    $unloaded = New-Object System.Collections.Generic.List[string]
    if ($null -ne $loaded -and $null -ne $listed) {
        foreach ($sid in $listed) {
            if ($sid -notmatch $script:GdidUserSidRx) { continue }
            if ($loaded -contains $sid) { $loadedN++ } else { $unloaded.Add($sid) }
        }
    }
    $failed = ($errs.Count -gt 0)
    return @{ loadedProfiles = $loadedN; unloadedProfiles = $unloaded.Count; unloadedSids = $unloaded.ToArray()
              enumerationFailed = $failed; unverified = ($failed -or $unloaded.Count -gt 0)
              places = $places.ToArray(); errors = $errs.ToArray()
              state = $(if ($failed) { 'EnumerationFailed' } elseif ($unloaded.Count -gt 0) { 'Unloaded' } else { 'Complete' }) }
}

# Ключ реестра для чтения — снимок: state ok, missing (ключа нет) или denied
# (Windows не дала открыть); имена значений и подключей и нужные значения.
# Через API реестра, а не провайдер PowerShell: Get-ChildItem открывает
# каждый подключ сам и путает «не пустили в подключ» с ошибкой перечисления.
function Read-GdidKey {
    param([string]$Path, [string[]]$Values = @())
    $k = $null
    try {
        $k = Open-RegKeyRead $Path
        if ($null -eq $k) { return @{ state = 'missing'; path = $Path; valueNames = @(); subKeys = @(); values = @{}; error = '' } }
        $vn = @($k.GetValueNames())
        $vals = @{}
        foreach ($n in @($Values)) { if ($vn -contains $n) { $vals[$n] = $k.GetValue($n) } }
        return @{ state = 'ok'; path = $Path; valueNames = $vn; subKeys = @($k.GetSubKeyNames()); values = $vals; error = '' }
    } catch {
        return @{ state = 'denied'; path = $Path; valueNames = @(); subKeys = @(); values = @{}; error = "$($_.Exception.Message)" }
    } finally { if ($null -ne $k) { $k.Close() } }
}

# Тот же ключ для записи (удаления). Нет ключа — $null; нет доступа — исключение.
function Open-GdidKeyWrite {
    param([string]$Path)
    $hive = $null; $sub = ''
    switch -Regex ($Path) {
        '^(HKLM:|Registry::HKEY_LOCAL_MACHINE)(\\(.*))?$' { $hive = [Microsoft.Win32.Registry]::LocalMachine; $sub = $Matches[3]; break }
        '^(HKCU:|Registry::HKEY_CURRENT_USER)(\\(.*))?$'  { $hive = [Microsoft.Win32.Registry]::CurrentUser; $sub = $Matches[3]; break }
        '^(HKU:|Registry::HKEY_USERS)(\\(.*))?$'          { $hive = [Microsoft.Win32.Registry]::Users; $sub = $Matches[3]; break }
    }
    if ($null -eq $hive -or -not "$sub".Trim('\')) { throw ("ключ не для записи: {0}" -f $Path) }
    return $hive.OpenSubKey("$sub".TrimEnd('\'), $true)
}

# Удалить одно значение и проверить, что его нет: removed, absent, denied
function Remove-GdidRegValue {
    param([string]$Path, [string]$Name)
    $k = $null
    try {
        $k = Open-GdidKeyWrite $Path
        if ($null -eq $k) { return 'absent' }
        if (@($k.GetValueNames()) -notcontains $Name) { return 'absent' }
        $k.DeleteValue($Name, $false)
    } catch { return 'denied' }
    finally { if ($null -ne $k) { $k.Close() } }
    # «команда прошла» — ещё не «значения нет»: сверяем
    $chk = Read-GdidKey $Path
    if ($chk.state -eq 'missing' -or ($chk.state -eq 'ok' -and @($chk.valueNames) -notcontains $Name)) { return 'removed' }
    return 'denied'
}

# Удалить один подключ и проверить, что его нет. Без -Tree удаляется только
# ключ без подключей: если внутри есть что-то ещё, ключ остаётся целым (kept)
# — удалять то, чего программа не опознала, нельзя.
# Ответ: removed, absent, denied, kept.
function Remove-GdidRegKey {
    param([string]$Parent, [string]$Name, [switch]$Tree)
    $pk = $null
    try {
        $pk = Open-GdidKeyWrite $Parent
        if ($null -eq $pk) { return 'absent' }
        if (@($pk.GetSubKeyNames()) -notcontains $Name) { return 'absent' }
        if (-not $Tree) {
            $ck = $pk.OpenSubKey($Name, $false)
            $n = $(if ($null -ne $ck) { try { $ck.SubKeyCount } finally { $ck.Close() } } else { 0 })
            if ($n -gt 0) { return 'kept' }
            $pk.DeleteSubKey($Name, $false)
        } else { $pk.DeleteSubKeyTree($Name, $false) }
    } catch {
        $ex = $_.Exception
        if ($ex -is [System.InvalidOperationException] -or $ex.InnerException -is [System.InvalidOperationException]) { return 'kept' }
        return 'denied'
    } finally { if ($null -ne $pk) { $pk.Close() } }
    $chk = Read-GdidKey ("{0}\{1}" -f $Parent.TrimEnd('\'), $Name)
    if ($chk.state -eq 'missing') { return 'removed' }
    return 'denied'
}

# Удаление одной записи с ответом: removed — было и убрано, absent — не было,
# denied — Windows не дала. Раньше всё удалялось молча, и отказ выглядел как успех.
function Remove-RegStatus {
    param([string]$Path, [string]$Name = '')
    # «Не было» — только когда Windows прямо ответила, что такого ключа нет.
    # Раньше параметр читался через Get-RegValue, а она и при отказе в доступе
    # отдаёт пустоту: закрытая запись засчитывалась как «не было», хотя номер
    # в ней оставался. Test-Path тоже не годится — на закрытый ключ он говорит
    # «есть», и дальше уже не понять, отчего не вышло.
    try { $key = Get-Item -LiteralPath $Path -ErrorAction Stop }
    catch [System.Management.Automation.ItemNotFoundException] { return 'absent' }
    catch { return 'denied' }
    try {
        if ($Name) {
            if (@($key.GetValueNames()) -notcontains $Name) { return 'absent' }
            Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop
        } else {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
    } catch { return 'denied' } finally { if ($key) { $key.Close() } }
    # «Команда прошла» — ещё не «удалено»: сверяем, что записи и правда нет
    try {
        $now = Get-Item -LiteralPath $Path -ErrorAction Stop
        try { if (-not $Name -or @($now.GetValueNames()) -contains $Name) { return 'denied' } } finally { $now.Close() }
    } catch [System.Management.Automation.ItemNotFoundException] { }
    catch { return 'denied' }
    return 'removed'
}
$script:DevicePuidRegex = '^0018[0-9A-Fa-f]{12}$'
# Учётные данные «личности» устройства — у пользователя и у самой системы
$script:GdidCredUser   = @('WindowsLive:target=virtualapp/didlogical', 'MicrosoftAccount:target=SSO_POP_Device')
$script:GdidCredSystem = @('WindowsLive:target=virtualapp/didlogical')
$script:GdidRefusal = $null

function ConvertTo-Gdid {
    param([string]$Hex)
    if ($Hex -notmatch '^[0-9A-Fa-f]{1,16}$') { return '' }
    try { return 'g:' + [Convert]::ToUInt64($Hex, 16) } catch { return '' }
}

# Тип запуска службы по реестру: число и слово. start = -1 и Missing — службы
# нет; -2 и ReadError — прочитать не удалось. Раньше оба случая давали -1:
# закрытый от чтения ключ выглядел «нет на этой системе».
function Get-SvcStartInfo {
    param([string]$Name)
    $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    $raw = Get-RegRaw $k 'Start'
    $why = ''
    if (-not $raw.ok) { $why = "$($raw.error)" }
    elseif (-not $raw.exists) {
        $kx = Test-RegKeyExists $k
        if ($kx -eq $false) { return @{ name = $Name; start = -1; state = 'Missing'; error = '' } }
        $why = $(if ($null -eq $kx) { 'ключ службы не читается' } else { 'у службы нет параметра Start' })
    } elseif ("$($raw.kind)" -ne 'DWord') { $why = ("параметр Start вида {0}" -f $raw.kind) }
    else {
        $v = [int64]$raw.value
        $state = $(switch ($v) { 0 { 'Boot' } 1 { 'System' } 2 { 'Automatic' } 3 { 'Manual' } 4 { 'Disabled' } default { '' } })
        if ($state) { return @{ name = $Name; start = [int]$v; state = $state; error = '' } }
        $why = ("непонятный тип запуска {0}" -f $v)
    }
    return @{ name = $Name; start = -2; state = 'ReadError'; error = $why }
}

function Get-SvcStart {
    param([string]$Name)
    return [int](Get-SvcStartInfo $Name).start
}

# Служба глазами диспетчера служб: работает ли и какой тип запуска он помнит.
# Службу, отключённую прямо в реестре, диспетчер до перезагрузки помнит
# прежней — и может запустить. found = $false — такой службы он не знает;
# ok = $false — не ответил.
function Get-SvcScmView {
    param([string]$Name)
    $ev = $null
    $s = Get-Service -Name $Name -ErrorAction SilentlyContinue -ErrorVariable ev
    if (-not $s) {
        $errs = @($ev | Where-Object { $_ -and "$($_.FullyQualifiedErrorId)" -notlike 'NoServiceFoundForGivenName*' })
        if ($errs.Count -eq 0) { return @{ ok = $true; found = $false; running = $false; status = ''; start = ''; error = '' } }
        return @{ ok = $false; found = $false; running = $false; status = ''; start = ''; error = "$($errs[0])" }
    }
    $s = @($s)[0]
    $run = ("$($s.Status)" -ne 'Stopped')
    try { $st = "$($s.StartType)" }
    catch { return @{ ok = $false; found = $true; running = $run; status = "$($s.Status)"; start = ''; error = $_.Exception.Message } }
    return @{ ok = $true; found = $true; running = $run; status = "$($s.Status)"; start = $st; error = '' }
}

# Служба целиком — одной записью: тип запуска по реестру (start, state —
# см. Get-SvcStartInfo) и глазами диспетчера служб (scmStart, running,
# status). Её же читают проверка передачи и снимок перед стиранием.
#   config  — Disabled, Manual, Automatic, Missing (службы нет), Unknown
#             (тип запуска не прочитался);
#   runtime — Running, Stopped, Missing, Unknown (диспетчер не ответил:
#             служба, к которой нет доступа, — «неизвестно», а не «стоит»);
#   readable — прочиталось всё, что нужно, чтобы судить о службе.
function Get-GdidSvcEntry {
    param([string]$Name)
    $i = Get-SvcStartInfo $Name
    $v = Get-SvcScmView $Name
    $i['running'] = [bool]$v.running
    $i['status'] = "$($v.status)"
    $i['scmStart'] = "$($v.start)"
    $i['scmOk'] = [bool]$v.ok
    $i['scmFound'] = [bool]$v.found
    $i['scmError'] = "$($v.error)"
    $i['config'] = $(switch ("$($i.state)") { 'Disabled' { 'Disabled' } 'Manual' { 'Manual' } { $_ -in @('Automatic', 'Boot', 'System') } { 'Automatic' } 'Missing' { 'Missing' } default { 'Unknown' } })
    $i['runtime'] = $(if (-not $v.ok) { 'Unknown' } elseif (-not $v.found) { 'Missing' } elseif ($v.running) { 'Running' } else { 'Stopped' })
    $i['readable'] = ("$($i.state)" -ne 'ReadError' -and [bool]$v.ok)
    return $i
}

# Копии CDPUserSvc у каждого вошедшего пользователя (CDPUserSvc_1a2b3) — по
# именам ключей служб, без открытия чужих (часть ключей служб закрыта).
function Get-GdidUserSvcInstances {
    $k = $null
    try {
        $k = Open-RegKeyRead 'HKLM:\SYSTEM\CurrentControlSet\Services'
        if ($null -eq $k) { return @{ ok = $false; names = @(); error = 'нет списка служб' } }
        $names = @($k.GetSubKeyNames() | Where-Object { $_ -match '^CDPUserSvc_[0-9A-Fa-f]+$' } | Sort-Object)
        return @{ ok = $true; names = $names; error = '' }
    } catch { return @{ ok = $false; names = @(); error = "$($_.Exception.Message)" } }
    finally { if ($null -ne $k) { $k.Close() } }
}

# Службы, через которые номер уходит наружу: их отключает модуль gdid
$script:GdidSvcNames = @('CDPSvc', 'CDPUserSvc', 'DoSvc')

# Идёт ли номер наружу. Одна проверка на всех: вкладка «Номер устройства» и
# «Цифровой след». Раньше обе смотрели только CDPSvc и DoSvc — CDPUserSvc и
# её копии у каждого пользователя (CDPUserSvc_1a2b3), которые модуль тоже
# отключает, не проверялись вовсе, а «службы нет» и «не прочиталось»
# сливались в одно.
#   off — отключено, и это проверено: все три службы отключены (или их нет),
#         ни одна не работает, копий CDPUserSvc с прежним типом запуска нет,
#         и диспетчер служб видит то же, что реестр;
#   pending — в реестре всё отключено, но действует ещё прежнее: служба не
#         остановилась, копия CDPUserSvc заведена до отключения (Windows
#         уберёт её при выходе пользователя) или диспетчер служб до
#         перезагрузки помнит прежний тип запуска;
#   known — прочиталось всё. Не прочиталось — off не бывает.
# state: Off, Pending, On (хоть одна служба может работать), Unknown.
function Get-GdidTransmitState {
    $problems = New-Object System.Collections.Generic.List[string]
    $look = {
        param([string]$SvcName)
        $Info = Get-GdidSvcEntry $SvcName
        if (-not $Info.scmOk) { $problems.Add(("{0}: диспетчер служб не ответил ({1})" -f $Info.name, $Info.scmError)) }
        if ($Info.state -eq 'ReadError') { $problems.Add(("{0}: тип запуска не прочитался ({1})" -f $Info.name, $Info.error)) }
        $Info
    }
    $out = New-Object System.Collections.Generic.List[object]
    $allOff = $true; $settled = $true; $on = $false
    foreach ($n in $script:GdidSvcNames) {
        $i = & $look $n
        if ($i.state -in @('Boot', 'System', 'Automatic', 'Manual')) { $on = $true }
        if ($i.state -notin @('Disabled', 'Missing')) { $allOff = $false }
        if ($i.running) { $settled = $false }
        if ($i.state -eq 'Disabled' -and $i.scmStart -and $i.scmStart -ne 'Disabled') { $settled = $false }
        if ($n -eq 'CDPUserSvc') {
            $inst = Get-GdidUserSvcInstances
            if (-not $inst.ok) { $problems.Add(("копии CDPUserSvc не перечислились: {0}" -f $inst.error)) }
            $il = New-Object System.Collections.Generic.List[object]
            foreach ($nm in @($inst.names)) {
                $ii = & $look $nm
                if ($ii.state -notin @('Disabled', 'Missing') -or $ii.running) { $settled = $false }
                if ($ii.running) { $i['running'] = $true }
                $il.Add($ii)
            }
            $i['instances'] = $il.ToArray()
        }
        $out.Add($i)
    }
    $known = ($problems.Count -eq 0)
    $off = ($known -and $allOff -and $settled)
    $state = $(if ($off) { 'Off' } elseif ($on) { 'On' } elseif (-not $known) { 'Unknown' } else { 'Pending' })
    return @{ off = $off; pending = ($state -eq 'Pending'); known = $known; state = $state
              services = $out.ToArray(); problems = $problems.ToArray() }
}

# Снимок служб перед стиранием — всех, которые стирание трогает: wlidsvc
# (её отключают на время стирания), CDPSvc, DoSvc, шаблон CDPUserSvc и его
# копии у вошедших пользователей (CDPUserSvc_1a2b3). У каждой — тип запуска
# по реестру и диспетчеру служб и работает ли она (Get-GdidSvcEntry).
# complete — прочиталось всё; без этого стирание не начинается: вернуть
# службы как были было бы не по чему. Раньше состояния собирались по
# отдельности, а ошибки Get-Service глотались — и служба, о которой ничего
# не узнали, после стирания оставалась остановленной.
function Get-GdidServiceSnapshot {
    $list = New-Object System.Collections.Generic.List[object]
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($n in @(@('wlidsvc') + @($script:GdidSvcNames))) { $list.Add((Get-GdidSvcEntry $n)) }
    $inst = Get-GdidUserSvcInstances
    if (-not $inst.ok) { $problems.Add(("копии CDPUserSvc не перечислились: {0}" -f $inst.error)) }
    foreach ($nm in @($inst.names)) {
        if (-not $nm) { continue }
        $e = Get-GdidSvcEntry $nm
        $e['instance'] = $true
        $list.Add($e)
    }
    foreach ($e in $list.ToArray()) {
        if ("$($e.state)" -eq 'ReadError') { $problems.Add(("{0}: тип запуска не прочитался ({1})" -f $e.name, $e.error)) }
        if (-not $e.scmOk) { $problems.Add(("{0}: диспетчер служб не ответил ({1})" -f $e.name, $e.scmError)) }
    }
    return @{ complete = ($problems.Count -eq 0); services = $list.ToArray(); problems = $problems.ToArray()
              time = (Get-Date).ToString('s') }
}

# Записи номера в реестре — одна опись и для поиска, и для стирания: стирание
# удаляет ровно найденное здесь, а не ветки целиком. Раньше опись пропускала
# DeviceIdentities\production\Logs, а стирание удаляло весь production вместе
# с ним и со всем, чего программа не опознала. Записи:
#   lid      — значение LID в ExtendedProperties (сам номер);
#   property — значения с именем-номером в Immersive\production\Property;
#   token    — значения DeviceId и DeviceTicket билета приложения (прочие
#              значения билета — ApplicationFlags, UserId, UserTicket — не его);
#   identity — «личность» устройства DeviceIdentities\production\<SID>\<имя>
#              со значением DeviceId; указатель на неё (ValidDeviceId в
#              разделе <SID>) — часть той же записи. Logs (история выдачи),
#              DeviceLicenseUpdateFailureCount и подключи без DeviceId — не
#              записи номера: они не считаются и не удаляются;
#   cache    — запись NegativeCache с именем «<номер>_<SID>»: весь ключ и
#              есть кэш этого номера.
# Каждое место, куда Windows не пустила, записывается само по себе в
# $script:GdidUnreadable: «не нашли» там — не то же самое, что «нет».
# $script:GdidUnknown — подключи личностей без DeviceId: оставлены как есть.
$script:GdidUnknown = New-Object System.Collections.Generic.List[string]
function Get-GdidCopies {
    $found = New-Object System.Collections.Generic.List[object]
    $script:GdidUnreadable.Clear()
    if ($null -eq $script:GdidUnknown) { $script:GdidUnknown = New-Object System.Collections.Generic.List[string] }
    $script:GdidUnknown.Clear()
    $seenSystem = $false
    $me = ''
    try { $me = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value } catch { }
    $read = {
        param([string]$KeyPath, [string[]]$Want = @())
        $k = Read-GdidKey $KeyPath $Want
        if ($k.state -eq 'denied') { $script:GdidUnreadable.Add($KeyPath) }
        $k
    }
    foreach ($r in (Get-IdCrlRoots)) {
        $rk = & $read $r.path
        if ($rk.state -ne 'ok') { continue }
        # .DEFAULT и S-1-5-18 — один и тот же куст SYSTEM: считаем его один раз
        if ($r.who -eq 'system') { if ($seenSystem) { continue }; $seenSystem = $true }
        $ep = "$($r.path)\ExtendedProperties"
        $ek = & $read $ep @('LID')
        if ($ek.state -eq 'ok' -and "$($ek.values['LID'])") {
            $found.Add(@{ who = $r.who; place = 'lid'; puid = "$($ek.values['LID'])"; path = $ep; values = @('LID'); key = $false })
        }
        $pp = "$($r.path)\Immersive\production\Property"
        $pk = & $read $pp
        foreach ($vn in @($pk.valueNames)) {
            if ($vn -match $script:DevicePuidRegex) { $found.Add(@{ who = $r.who; place = 'property'; puid = $vn; path = $pp; values = @($vn); key = $false }) }
        }
        $tp = "$($r.path)\Immersive\production\Token"
        $tl = & $read $tp
        foreach ($tn in @($tl.subKeys)) {
            $tk = & $read "$tp\$tn" @('DeviceId')
            if ($tk.state -ne 'ok') { continue }
            $tv = @(@('DeviceId', 'DeviceTicket') | Where-Object { @($tk.valueNames) -contains $_ })
            if ($tv.Count -gt 0) { $found.Add(@{ who = $r.who; place = 'token'; puid = "$($tk.values['DeviceId'])"; path = "$tp\$tn"; values = $tv; key = $false }) }
        }
        $dp = "$($r.path)\DeviceIdentities\production"
        $dl = & $read $dp
        foreach ($sn in @($dl.subKeys)) {
            if ($sn -eq 'Logs') { continue }
            # Чья личность: в кусте пользователя — его; в системном — по SID
            # раздела. Раньше любая S-1-5-21-* шла как «своя», и копии другого
            # пользователя считались копиями того, кто смотрит.
            $idWho = $(if ($r.who -ne 'system') { $r.who } elseif ($sn -notmatch $script:GdidUserSidRx) { 'system' }
                       elseif ($sn -eq $me) { 'user' } else { 'other' })
            $cp = "$dp\$sn"
            $ck = & $read $cp @('ValidDeviceId')
            if ($ck.state -ne 'ok') { continue }
            foreach ($inm in @($ck.subKeys)) {
                $ik = & $read "$cp\$inm" @('DeviceId')
                if ($ik.state -ne 'ok') { continue }
                if (@($ik.valueNames) -notcontains 'DeviceId') { $script:GdidUnknown.Add("$cp\$inm"); continue }
                $found.Add(@{ who = $idWho; place = 'identity'; puid = "$($ik.values['DeviceId'])"; path = "$cp\$inm"; values = @(); key = $true
                              parent = $cp; name = $inm; children = @($ik.subKeys).Count
                              pointer = $(if ("$($ck.values['ValidDeviceId'])" -eq $inm) { $cp } else { '' }) })
            }
        }
    }
    $nk = & $read $script:IdCrlNegCache
    foreach ($nn in @($nk.subKeys)) {
        if ($nn -match '^(0018[0-9A-Fa-f]{12})_') {
            $found.Add(@{ who = 'system'; place = 'cache'; puid = $Matches[1]; path = "$($script:IdCrlNegCache)\$nn"; values = @(); key = $true
                          parent = $script:IdCrlNegCache; name = $nn; tree = $true })
        }
    }
    return $found.ToArray()
}

# Опись копий номера с ответом, можно ли ей верить. state: Found — копии есть;
# NotFound — копий нет и проверено всё; Unverified — копий не нашлось, но часть
# мест не прочиталась, профили других пользователей не проверялись или их
# список не прочитался. «Не нашли» там, куда не пустили, — не то же самое,
# что «нет». profiles — опись профилей (Get-UncheckedProfiles).
function Get-GdidScan {
    $copies = @(Get-GdidCopies)
    $prof = Get-UncheckedProfiles
    foreach ($pl in @($prof.places)) { $script:GdidUnreadable.Add("$pl") }
    $unchecked = [int]$prof.unloadedProfiles
    $unread = @($script:GdidUnreadable | Select-Object -Unique)
    $state = $(if ($copies.Count -gt 0) { 'Found' } elseif ($unread.Count -gt 0 -or $prof.unverified) { 'Unverified' } else { 'NotFound' })
    return @{ copies = $copies; unreadable = $unread; unchecked = $unchecked; profiles = $prof; state = $state
              unknown = @($script:GdidUnknown | Select-Object -Unique) }
}

# Кусты реестра людей, о которых речь: самого движка (HKCU) и того, кто сидит
# за компьютером, если пароль администратора ввёл он (его куст подключён).
function Get-GdidUserHiveRoots {
    $roots = New-Object System.Collections.Generic.List[object]
    $roots.Add(@{ sid = "$($script:UserSid)"; root = 'HKCU:' })
    $o = Get-OtherSessionUser
    if ($o -and $o.sid -and "$($o.sid)" -ne "$($script:UserSid)") { $roots.Add(@{ sid = "$($o.sid)"; root = "Registry::HKEY_USERS\$($o.sid)" }) }
    return $roots.ToArray()
}

# Есть ли у ключа подключи: $true, $false; не прочитался — $null
function Test-GdidKeyHasChildren {
    param([string]$Path)
    $k = $null
    try { $k = Open-RegKeyRead $Path; return ($null -ne $k -and $k.SubKeyCount -gt 0) }
    catch { return $null }
    finally { if ($null -ne $k) { $k.Close() } }
}

# Учётная запись человека: чем он входит в Windows и подключена ли учётная
# запись Microsoft только к приложениям. Ответ:
#   source       — MicrosoftAccount (вход в Windows через неё), Local,
#                  ActiveDirectory (домен), AzureAD (Entra ID), Unknown;
#   signInMsa    — вход в Windows через учётную запись Microsoft. Не
#                  удалось узнать — «да»: осторожная сторона, запрет выдачи
#                  тогда не ставится;
#   connectedMsa — в профиле есть учётная запись Microsoft (Магазин, Почта,
#                  OneDrive), $null — профиль не прочитался. У локальной
#                  учётной записи это ещё не вход через неё;
#   known        — источник определился точно (по SAM или по виду SID).
# Раньше локальная учётная запись, у которой Microsoft подключена только к
# Магазину, и учётная запись без модуля LocalAccounts судились одним правилом.
function Get-GdidAccountKind {
    param([string]$Sid, [string]$Root)
    $conn = Test-GdidKeyHasChildren "$Root\SOFTWARE\Microsoft\IdentityCRL\UserExtendedProperties"
    $o = @{ sid = $Sid; source = 'Unknown'; signInMsa = $true; connectedMsa = $conn; known = $false; error = '' }
    # SID S-1-12-1-… — учётная запись Entra ID: это не учётная запись Microsoft
    if ($Sid -like 'S-1-12-1-*') { $o.source = 'AzureAD'; $o.signInMsa = $false; $o.known = $true; return $o }
    try {
        $u = Get-LocalUser -SID $Sid -ErrorAction Stop
        $src = "$($u.PrincipalSource)"
        if ($src -in @('MicrosoftAccount', 'Local', 'ActiveDirectory', 'AzureAD')) {
            $o.source = $src; $o.known = $true; $o.signInMsa = ($src -eq 'MicrosoftAccount')
            return $o
        }
        $o.error = ("источник учётной записи не назван ({0})" -f $src)
    } catch { $o.error = "$($_.Exception.Message)" }
    # Не локальная учётная запись (домен) или модуля учётных записей нет —
    # судим по профилю: есть в нём учётная запись Microsoft (или профиль не
    # прочитался) — считаем, что вход через неё.
    $o.signInMsa = ($conn -ne $false)
    return $o
}

# Учётные записи тех, о ком речь (движок и тот, кто сидит за компьютером)
function Get-GdidAccounts {
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($h in @(Get-GdidUserHiveRoots)) {
        if (-not $h.sid) { continue }
        $out.Add((Get-GdidAccountKind "$($h.sid)" "$($h.root)"))
    }
    return $out.ToArray()
}

# Учётная запись с этим SID — вход в Windows через учётную запись Microsoft
# (см. Get-GdidAccountKind)
function Test-MsaAccount {
    param([string]$Sid, [string]$Root)
    return [bool](Get-GdidAccountKind $Sid $Root).signInMsa
}

# Входит ли в Windows через учётную запись Microsoft тот, кто сидит за
# компьютером, или учётная запись самого движка. Раньше спрашивалось о
# $env:USERNAME — об учётной записи движка: если пароль администратора ввёл
# обычный пользователь, проверялся администратор, и запрет выдачи мог встать
# человеку, который входит через учётную запись Microsoft, — и сломать ему её.
function Test-MsaLogon {
    foreach ($h in @(Get-GdidUserHiveRoots)) {
        if (-not $h.sid) { continue }
        if (Test-MsaAccount $h.sid $h.root) { return $true }
    }
    return $false
}

# Другие учётные записи Microsoft на этом компьютере (кроме своей и того, кто
# сидит за ним): запрет выдачи закрывает сервер для всех, и их вход в учётную
# запись Microsoft тоже перестанет работать. Список — для предупреждения.
# Список не прочитался — $script:GdidOtherMsaError: предупреждение тогда
# говорит, что проверить не удалось (раньше это молча было «других нет»).
$script:GdidOtherMsaError = ''
function Get-OtherMsaAccounts {
    $script:GdidOtherMsaError = ''
    $skip = @(@(Get-GdidUserHiveRoots) | ForEach-Object { "$($_.sid)" })
    try { return @(Get-LocalUser -ErrorAction Stop | Where-Object { "$($_.PrincipalSource)" -eq 'MicrosoftAccount' -and $skip -notcontains "$($_.SID)" } | ForEach-Object { "$($_.Name)" }) }
    catch { $script:GdidOtherMsaError = "$($_.Exception.Message)"; return @() }
}

# Компьютер организации: там номер устройства связан с её учётной записью,
# и трогать его — сломать вход на работе. Ответ (считается один раз за запуск):
#   kind — domain (в домене), entra (Entra ID), hybrid (домен и Entra ID
#          сразу), mdm (под управлением организации), workAccount (добавлена
#          рабочая или учебная учётная запись — устройство при этом
#          организацией не управляется), unknown (проверить не удалось), '';
#   managed — устройством управляет организация (или это неизвестно);
#   workAccount — рабочая учётная запись подключена (отдельно от управления);
#   reason — то же словами, для окна и журнала работы.
# Встроенные «поставщики» Local, Deploy и Cloud Authority есть на любом
# домашнем компьютере — их не считаем. Не удалось проверить — отказ, а не
# «домашний»: раньше ошибка WMI или чтения реестра глоталась, и компьютер
# организации с неисправным WMI считался домашним.
# Рабочая учётная запись без управления тоже отказ (осторожная сторона: её
# вход привязан к регистрации устройства), но называется своим словом.
$script:GdidManagedCache = $null
$script:GdidManagementCache = $null
function Get-GdidManagement {
    if ($null -ne $script:GdidManagementCache) { return $script:GdidManagementCache }
    $script:GdidManagementCache = Get-GdidManagementNow
    return $script:GdidManagementCache
}

function Get-ManagedReason {
    if ($null -ne $script:GdidManagedCache) { return $script:GdidManagedCache }
    $script:GdidManagedCache = Get-ManagedReasonNow
    return $script:GdidManagedCache
}

function Get-ManagedReasonNow {
    $script:GdidManagementCache = Get-GdidManagementNow
    return "$($script:GdidManagementCache.reason)"
}

function Get-GdidManagementNow {
    $unknown = 'не удалось проверить, принадлежит ли компьютер организации'
    $o = @{ kind = ''; managed = $false; workAccount = $false; reason = ''; domain = $null; entra = $null; mdm = $null; errors = (New-Object System.Collections.Generic.List[string]) }
    $fail = { param([string]$Why) $o.errors.Add($Why); $o.kind = 'unknown'; $o.managed = $true; $o.reason = $unknown; $o }
    try { $o.domain = [bool](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain }
    catch { return (& $fail ("WMI: {0}" -f $_.Exception.Message)) }
    $aad = Test-GdidKeyHasChildren 'HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo'
    if ($null -eq $aad) { return (& $fail 'CloudDomainJoin\JoinInfo не читается') }
    $o.entra = [bool]$aad
    if ($o.domain -and $o.entra) { $o.kind = 'hybrid'; $o.managed = $true; $o.reason = 'компьютер в домене организации и подключён к её Entra ID'; return $o }
    if ($o.domain) { $o.kind = 'domain'; $o.managed = $true; $o.reason = 'компьютер в домене организации'; return $o }
    if ($o.entra) { $o.kind = 'entra'; $o.managed = $true; $o.reason = 'компьютер подключён к Entra ID организации'; return $o }
    # Управление организацией (MDM): запись в Enrollments от внешнего
    # поставщика в состоянии «зарегистрировано» или учётная запись OMA-DM
    $en = $null
    try {
        $en = Open-RegKeyRead 'HKLM:\SOFTWARE\Microsoft\Enrollments'
        if ($null -ne $en) {
            foreach ($sub in @($en.GetSubKeyNames())) {
                $ek = $en.OpenSubKey($sub, $false)
                if ($null -eq $ek) { continue }
                try {
                    $prov = "$($ek.GetValue('ProviderID'))"
                    if ($prov -and $prov -notin @('Local Authority', 'Deploy Authority', 'Cloud Authority') -and "$($ek.GetValue('EnrollmentState'))" -eq '1') { $o.mdm = $true }
                } finally { $ek.Close() }
            }
        }
    } catch { return (& $fail ("Enrollments: {0}" -f $_.Exception.Message)) }
    finally { if ($null -ne $en) { $en.Close() } }
    if (-not $o.mdm) {
        $om = Test-GdidKeyHasChildren 'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts'
        if ($null -eq $om) { return (& $fail 'OMADM\Accounts не читается') }
        $o.mdm = [bool]$om
    }
    if ($o.mdm) { $o.kind = 'mdm'; $o.managed = $true; $o.reason = 'компьютер под управлением организации (MDM)'; return $o }
    # Рабочая или учебная учётная запись — у того, кто сидит за компьютером,
    # и у самого движка (раньше смотрелся только HKCU движка)
    foreach ($h in @(Get-GdidUserHiveRoots)) {
        $wp = Test-GdidKeyHasChildren "$($h.root)\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin\JoinInfo"
        if ($null -eq $wp) { return (& $fail 'WorkplaceJoin\JoinInfo не читается') }
        if ($wp) { $o.workAccount = $true }
    }
    if ($o.workAccount) { $o.kind = 'workAccount'; $o.reason = 'в Windows добавлена рабочая или учебная учётная запись (компьютером организация не управляет)' }
    return $o
}


# 'msa' — вход в Windows через учётную запись Microsoft, 'managed' — компьютер
# организации, '' — запрет выдачи номера доступен. Считается один раз за запуск.
function Get-GdidLockRefusal {
    if ($null -ne $script:GdidRefusal) { return $script:GdidRefusal }
    $script:GdidRefusal = ''
    if (Test-MsaLogon) { $script:GdidRefusal = 'msa' }
    elseif (Get-ManagedReason) { $script:GdidRefusal = 'managed' }
    return $script:GdidRefusal
}

# Самая ранняя запись журнала отката о wlidsvc — её «как было» оставило
# прерванное стирание (процесс оборвался, служба осталась отключённой).
function Get-GdidWlidJournalEntry {
    $jf = Read-JournalFile -ReadOnly
    if (-not $jf.trusted) { return $null }
    foreach ($it in @($jf.items)) {
        $f = ConvertTo-Fields $it
        if ((Get-JournalKey $f) -eq 'svc|wlidsvc' -and -not (Test-JournalEntryShape $it)) { return $f }
    }
    return $null
}

# wlidsvc на время стирания отключается: её поднимает любой запрос Магазина.
# «Как было» сначала ложится в журнал отката (как у всех изменений). Раньше
# тип запуска помнил только сам движок: оборвись он посреди стирания — служба
# учётных записей Microsoft осталась бы отключённой навсегда (вход в неё,
# Магазин, Xbox), и ни возврат, ни откат о ней не знали бы.
# Ответ: ok — можно стирать; changed — потом вернуть по entry; why — почему нет.
function Disable-GdidWlid {
    $svc = Get-Service -Name wlidsvc -ErrorAction SilentlyContinue
    if (-not $svc) { return @{ ok = $true; changed = $false; entry = $null; why = 'службы учётных записей Microsoft (wlidsvc) на этой системе нет' } }
    $prev = Get-GdidWlidJournalEntry
    $entry = $prev
    if (-not $prev) {
        if ("$($svc.StartType)" -eq 'Disabled') { return @{ ok = $true; changed = $false; entry = $null; why = '' } }
        $entry = Get-SvcJournalState 'wlidsvc' $svc
        # Тип запуска не прочитался — вернуть его потом было бы нечем: тогда
        # не стираем вовсе. Раньше стирание шло дальше с включённой wlidsvc,
        # и она могла завести номер заново посреди стирания.
        if ("$($entry.old)" -notmatch '^[0-4]$') { return @{ ok = $false; changed = $false; entry = $null; why = 'тип запуска wlidsvc не прочитался -- вернуть его потом было бы нечем' } }
        if (-not (Write-AheadEntry $entry)) { return @{ ok = $false; changed = $false; entry = $null; why = 'журнал отката не пишется' } }
    }
    try { Set-Service -Name wlidsvc -StartupType Disabled -ErrorAction Stop }
    catch {
        if (-not $prev) { Undo-AheadEntry $entry; return @{ ok = $true; changed = $false; entry = $null; why = ("wlidsvc не отключилась на время стирания: {0}" -f $_.Exception.Message) } }
    }
    return @{ ok = $true; changed = $true; entry = $entry; why = '' }
}

# Тип запуска wlidsvc — по записи журнала, и запись после этого убирается
function Restore-GdidWlid {
    param($Wlid)
    if ($null -eq $Wlid -or -not $Wlid.changed -or $null -eq $Wlid.entry) { return @{ ok = $true; why = '' } }
    $e = @{ kind = 'svc'; name = 'wlidsvc'; old = "$($Wlid.entry.old)"; delayed = "$($Wlid.entry.delayed)"; running = $false }
    $r = Restore-JournalEntry $e
    if (-not $r.ok) { return @{ ok = $false; why = "$($r.error)" } }
    try { Remove-JournalKey 'svc|wlidsvc' }
    catch { Write-Log ("   [i] тип запуска wlidsvc возвращён, а запись о нём в журнале отката осталась: {0}" -f $_.Exception.Message) }
    return @{ ok = $true; why = '' }
}

# Вернуть службы как были — и проверить, что вернулись. Раньше ошибка запуска
# глоталась: служба, работавшая до стирания, могла остаться стоять, а
# стирание всё равно считалось успешным.
#   $Running  — службы, которые остановило само стирание и которые работали
#               до него (по снимку): запускаются только они. Те, что стояли
#               до стирания, не запускаются;
#   $Wlid     — ответ Disable-GdidWlid: тип запуска wlidsvc — по журналу;
#   $Snapshot — снимок до стирания (Get-GdidServiceSnapshot): с ним
#               сверяется итог. «Start-Service отработал» — ещё не «работает».
# Ответ: notBack — что не вернулось; states — каждая служба до и после.
function Restore-GdidServices {
    param([string[]]$Running, $Wlid, $Snapshot)
    $bad = New-Object System.Collections.Generic.List[string]
    $states = New-Object System.Collections.Generic.List[object]
    $w = Restore-GdidWlid $Wlid
    if (-not $w.ok) { $bad.Add('wlidsvc (тип запуска)'); Write-Log ("   [!] тип запуска wlidsvc не вернулся: {0}" -f $w.why) }
    foreach ($n in @($Running)) {
        if (-not $n) { continue }
        $why = ''
        try {
            Start-Service -Name $n -ErrorAction Stop -WarningAction SilentlyContinue
            (Get-Service -Name $n -ErrorAction Stop).WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
        } catch { $why = "$($_.Exception.Message)" }
        # «Start-Service отработал» — ещё не «работает»: сверяем сами
        $v = Get-SvcScmView $n
        # копия CDPUserSvc исчезла вместе с выходом пользователя — запускать нечего
        if ($v.ok -and -not $v.found -and $n -like 'CDPUserSvc_*') { continue }
        if (-not ($v.ok -and $v.found -and "$($v.status)" -eq 'Running')) {
            $bad.Add($n)
            if ($why) { Write-Log ("   [!] служба {0} не запустилась: {1}" -f $n, $why) }
        }
    }
    if ($null -ne $Snapshot) {
        foreach ($e in @($Snapshot.services)) {
            $after = Get-GdidSvcEntry "$($e.name)"
            # тип запуска wlidsvc, оставленной прерванным прежде стиранием, —
            # тот, что в журнале, а не «отключена» из снимка
            $wantStart = [int]$e.start
            if ("$($e.name)" -eq 'wlidsvc' -and $Wlid -and $Wlid.changed -and $Wlid.entry -and "$($Wlid.entry.old)" -match '^[0-4]$') { $wantStart = [int]"$($Wlid.entry.old)" }
            # копия CDPUserSvc пропала — пользователь вышел из Windows, и
            # Windows убрала её сама: это не «не вернулась»
            $gone = ([bool]$e.instance -and "$($after.state)" -eq 'Missing')
            $startOk = ("$($e.state)" -eq 'Missing' -or $gone -or [int]$after.start -eq $wantStart)
            $runOk = ((-not $e.running) -or $gone -or [bool]$after.running -or @($Running) -notcontains "$($e.name)")
            $states.Add(@{ name = "$($e.name)"; before = @{ start = [int]$e.start; running = [bool]$e.running; status = "$($e.status)" }
                           after = @{ start = [int]$after.start; running = [bool]$after.running; status = "$($after.status)" }
                           stopped = (@($Running) -contains "$($e.name)"); restored = ($startOk -and $runOk) })
            if (-not $startOk -and -not ("$($e.name)" -eq 'wlidsvc' -and $bad -contains 'wlidsvc (тип запуска)')) {
                $bad.Add(("{0} (тип запуска: был {1}, сейчас {2})" -f $e.name, (Get-StartName "$wantStart"), (Get-StartName "$($after.start)")))
            }
        }
    }
    return @{ notBack = $bad.ToArray(); states = $states.ToArray() }
}

function Stop-ServiceWait {
    param([string]$Name)
    # «Службы нет» — только когда диспетчер служб так и ответил. Раньше любая
    # ошибка Get-Service означала «остановлена», и стирание шло при работающей
    # службе, которая держала номер.
    $svc = $null
    try { $svc = Get-Service -Name $Name -ErrorAction Stop }
    catch { return ("$($_.FullyQualifiedErrorId)" -like 'NoServiceFoundForGivenName*') }
    if (-not $svc -or $svc.Status -eq 'Stopped') { return $true }
    for ($i = 1; $i -le 3; $i++) {
        # -WarningAction: иначе в журнал работы сыпалось «WARNING: Waiting for
        # service ... to stop» по-английски — ждём остановку мы и так сами
        try { Stop-Service -Name $Name -Force -ErrorAction Stop -WarningAction SilentlyContinue; $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(10)); return $true }
        catch { Start-Sleep -Milliseconds (500 * $i) }
    }
    return $false
}

# Короткая задача планировщика: команда от имени пользователя без повышения
# или от имени SYSTEM. Учётные данные устройства лежат в хранилище каждого из
# них, а у повышенного сеанса своё пространство — отсюда их не видно.
# Короткая задача планировщика: выполнить команду от имени системы или
# пользователя и убрать задачу. Имя у каждого запуска своё, случайное: задачу
# с заранее известным именем мог бы завести кто-то другой, и программа
# запустила бы — а потом и удалила — чужую. После регистрации задача
# сверяется (та ли команда и от чьего имени) и без этого не запускается.
function Test-OneShotTaskMine {
    # -UserSid — чья это задача, если не от имени самого движка (вошедший
    # пользователь, см. Invoke-AsUser)
    param([string]$TaskName, [string]$Exe, [string]$Arguments, [bool]$AsSystem, [string]$UserSid = '')
    $t = Get-ScheduledTask -TaskPath '\' -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t) { return $false }
    $acts = @($t.Actions)
    # пробелы по краям планировщик вправе подрезать — они ничего не меняют
    if ($acts.Count -ne 1 -or "$($acts[0].Execute)".Trim() -ne $Exe.Trim() -or "$($acts[0].Arguments)".Trim() -ne $Arguments.Trim()) { return $false }
    # Сверяем по SID: имя учётной записи системы Windows переводит
    # («СИСТЕМА» на русской), и по имени своя задача выглядела чужой.
    $sid = ConvertTo-SidValue "$($t.Principal.UserId)"
    if ($AsSystem) { return ($sid -eq 'S-1-5-18') }
    $want = $(if ($UserSid) { $UserSid } else { ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value })
    return ($sid -ne '' -and $sid -eq $want)
}

function ConvertTo-SidValue {
    param([string]$Name)
    if (-not $Name) { return '' }
    if ($Name -match '^S-1-[\d-]+$') { return $Name }
    try { return (New-Object Security.Principal.NTAccount($Name)).Translate([Security.Principal.SecurityIdentifier]).Value } catch { return '' }
}

function Invoke-OneShotTask {
    # -Minutes — сколько задаче разрешено работать; ждём её столько же и ещё
    # немного. Раньше ожидание было 30 секунд при разрешённых двух минутах.
    # -Execute/-Arguments — программа запускается напрямую, без cmd.exe. Через
    # cmd (-CmdLine) идут только постоянные строки программы, которым нужны
    # его «&&», «|», «>nul»; в них не пропускаются % (cmd раскрыл бы его как
    # переменную) и переводы строк (они разорвали бы команду).
    # -StartSeconds — сколько ждать, что задача вообще начнётся: задача от имени
    # пользователя, который сейчас не вошёл в Windows, не начнётся никогда, и
    # ждать её всё отведённое время незачем
    # -Account/-AccountSid — не от имени самого движка, а от имени другого
    # пользователя (вошедшего в Windows, когда движок работает от имени
    # администратора, чей пароль он ввёл)
    param([string]$TaskName, [string]$CmdLine, [switch]$AsSystem, [int]$Minutes = 2, [string]$Execute = '', [string]$Arguments = '',
          [int]$StartSeconds = 0, [string]$Account = '', [string]$AccountSid = '')
    $TaskName = '{0} {1}' -f $TaskName, [guid]::NewGuid().ToString('N').Substring(0, 12)
    if ($Execute) { $exe = $Execute; $arg = $Arguments }
    else {
        if ($CmdLine -match '[%\r\n]') { Write-Log '   [!] команда для короткой задачи содержит недопустимые знаки -- не запускается'; return $false }
        $exe = "$env:SystemRoot\System32\cmd.exe"; $arg = '/d /c ' + $CmdLine
    }
    $registered = $false
    try {
        $act = New-ScheduledTaskAction -Execute $exe -Argument $arg
        # учётная запись — из маркера самого процесса, а не из USERNAME
        $who = $(if ($AsSystem) { New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest }
                 else { New-ScheduledTaskPrincipal -UserId $(if ($Account) { $Account } else { $script:RunAccount }) -LogonType Interactive -RunLevel Limited })
        $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes $Minutes)
        # имя новое — задачу с ним никто завести не мог, поэтому без -Force
        Register-ScheduledTask -TaskPath '\' -TaskName $TaskName -Action $act -Principal $who -Settings $set -ErrorAction Stop | Out-Null
        $registered = $true
        if (-not (Test-OneShotTaskMine $TaskName $exe $arg ([bool]$AsSystem) $AccountSid)) { return $false }
        Start-ScheduledTask -TaskPath '\' -TaskName $TaskName -ErrorAction Stop
        # 267011 — ещё не запускалась, 267009 — выполняется
        $until = (Get-Date).AddSeconds(60 * $Minutes + 15)
        $startBy = $(if ($StartSeconds -gt 0) { (Get-Date).AddSeconds($StartSeconds) } else { $until })
        do {
            Start-Sleep -Milliseconds 400
            $res = (Get-ScheduledTaskInfo -TaskPath '\' -TaskName $TaskName -ErrorAction SilentlyContinue).LastTaskResult
            if ($res -eq 267011 -and (Get-Date) -ge $startBy) {
                Write-Log '   [!] короткая задача не начала работу: пользователь, от имени которого она идёт, сейчас не вошёл в Windows'
                return $false
            }
        } while (($res -eq 267009 -or $res -eq 267011) -and (Get-Date) -lt $until)
        # Успех — только если команда задачи завершилась с кодом 0. Раньше «да»
        # возвращалось, едва задача запустилась, и сбой команды выглядел успехом.
        return ($res -eq 0)
    } catch {
        Write-Log ("   [!] короткая задача не отработала: {0}" -f $_.Exception.Message)
        return $false
    }
    finally {
        # имя случайное и заведено нами — удаляем только его. Не дождались —
        # задачу сначала останавливаем: иначе она доработала бы уже без нас и,
        # например, дописала бы итог, который никто не прочтёт.
        if ($registered) {
            if ((Get-ScheduledTaskInfo -TaskPath '\' -TaskName $TaskName -ErrorAction SilentlyContinue).LastTaskResult -eq 267009) {
                Stop-ScheduledTask -TaskPath '\' -TaskName $TaskName -ErrorAction SilentlyContinue
            }
            Unregister-ScheduledTask -TaskPath '\' -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
            # не удалилась — так и сказано: задача от имени системы не должна
            # оставаться в планировщике незамеченной
            if (Get-ScheduledTask -TaskPath '\' -TaskName $TaskName -ErrorAction SilentlyContinue) {
                Write-Log ("   [!] короткая задача «{0}» не удалилась из планировщика -- удалите её вручную" -f $TaskName)
                $script:Failures++
            }
        }
    }
}

# --------------------------------------------------------------------------- #
#  Действия в папках самого пользователя — от его имени и без повышения.
#  Профиль (TEMP, AppData) открыт на запись любой программе этого
#  пользователя, а движок работает с правами администратора. Удаление или
#  запись там по пути с правами администратора нельзя привязать к тому, что
#  проверено: путь можно подменить между проверкой и действием. Поэтому
#  такие действия делает короткая задача от имени того же пользователя с
#  обычными правами — она может ровно то, что он может и сам.
#  Сценарий — постоянный текст движка; он и его данные кладутся в защищённую
#  папку (читать их пользователь может, менять — нет). Итог задача пишет в
#  свою временную папку, и движок берёт из него только числа и строки.
#  Ответ: ok — задача отработала и оставила итог; result — разобранный итог.
# --------------------------------------------------------------------------- #
function Invoke-AsUser {
    param([string]$Name, [string]$Script, $Data, [int]$Minutes = 5)
    if (-not (Test-Admin)) { return @{ ok = $false; result = $null; why = 'нужны права администратора' } }
    if (-not (Assert-SafeRoot)) { return @{ ok = $false; result = $null; why = 'папка ProgramData\Win11Privacy не защищена' } }
    # Чьи папки: того, кто сидит за компьютером. Если пароль администратора
    # ввёл обычный пользователь, это он, а не учётная запись движка.
    $account = $script:RunAccount; $accountSid = $script:UserSid; $profileDir = $script:UserProfileDir
    $other = Get-OtherSessionUser
    if ($other) {
        if (-not $other.name -or -not $other.profile) { return @{ ok = $false; result = $null; why = 'профиль вошедшего в Windows пользователя определить не удалось' } }
        $account = $other.name; $accountSid = $other.sid; $profileDir = $other.profile
    }
    if (-not $profileDir -or -not $account) { return @{ ok = $false; result = $null; why = 'папку профиля пользователя Windows не назвала' } }
    $id = [guid]::NewGuid().ToString('N')
    $sf = Join-Path $script:SafeRoot ('asuser-' + $id + '.ps1')
    $inf = Join-Path $script:SafeRoot ('asuser-' + $id + '.json')
    $rf = Join-Path $profileDir ('AppData\Local\Temp\w11p-asuser-' + $id + '.json')
    try {
        Set-Content -LiteralPath $sf -Value $Script -Encoding UTF8 -ErrorAction Stop
        Set-Content -LiteralPath $inf -Value (ConvertTo-Json -InputObject $Data -Depth 6 -Compress) -Encoding UTF8 -ErrorAction Stop
        $argLine = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -InputFile "{1}" -ResultFile "{2}"' -f $sf, $inf, $rf
        $null = Invoke-OneShotTask ('Win11Privacy ' + $Name) -Execute $script:PsExe -Arguments $argLine -Minutes $Minutes -StartSeconds 30 -Account $account -AccountSid $accountSid
        if (-not (Test-Path -LiteralPath $rf -PathType Leaf)) { return @{ ok = $false; result = $null; why = 'задача от имени пользователя не оставила итога' } }
        if ((Get-Item -LiteralPath $rf -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            return @{ ok = $false; result = $null; why = 'на месте итога задачи лежит ссылка' }
        }
        # Итог лежит в папке пользователя. Его должна была написать наша задача
        # от имени этого же пользователя: сверяем владельца. Чужой владелец —
        # файл подменили, итогу верить нельзя (из него всё равно берутся только
        # числа и короткие строки, но лишним это не будет).
        $rfOwner = ''
        try { $rfOwner = (Get-Acl -LiteralPath $rf -ErrorAction Stop).GetOwner([Security.Principal.SecurityIdentifier]).Value } catch { }
        if ($accountSid -and $rfOwner -and $rfOwner -ne $accountSid -and $script:TrustedSids -notcontains $rfOwner) {
            return @{ ok = $false; result = $null; why = 'итог задачи принадлежит не тому пользователю -- подмена' }
        }
        $txt = Read-TextShared $rf
        $res = $null
        try { $res = $txt | ConvertFrom-Json -ErrorAction Stop } catch { }
        if ($null -eq $res) { return @{ ok = $false; result = $null; why = 'итог задачи от имени пользователя не читается' } }
        return @{ ok = $true; result = $res; why = '' }
    } catch {
        return @{ ok = $false; result = $null; why = $_.Exception.Message }
    } finally {
        foreach ($f in @($sf, $inf)) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
        # итог лежит в папке пользователя: удаляется сама запись (File.Delete
        # не идёт по ссылке)
        try { if (Test-Path -LiteralPath $rf) { [IO.File]::Delete($rf) } } catch { }
    }
}

# Часть задач Windows закрыла от администратора: читать их можно, менять —
# только SYSTEM (UsageAndQualityInsights, модели Click to Do). Раньше такая
# задача оставалась включённой с пометкой «не найдена». Теперь, если
# администратору отказано, то же делает короткая задача от имени SYSTEM.
# Ответ: ok, system (сделано от SYSTEM), missing (задачи нет), fail.
function Set-TaskEnabled {
    param([string]$Full, [bool]$Enabled)
    $pp = Split-TaskPath $Full
    $t = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction SilentlyContinue
    if (-not $t) { return 'missing' }
    # отказ администратору — не ошибка: дальше то же сделает задача от SYSTEM
    $denied = $false
    try {
        if ($Enabled) { Enable-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop | Out-Null }
        else { Disable-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop | Out-Null }
    } catch { $denied = $true }
    if (-not $denied) {
        # «команда прошла» — ещё не «задача такая»: состояние сверяется
        $t = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction SilentlyContinue
        if ($t -and ((Test-TaskDisabled $t) -ne $Enabled)) { return 'ok' }
    }
    $flag = $(if ($Enabled) { '/enable' } else { '/disable' })
    # schtasks запускается напрямую, а не через cmd; кавычка в имени задачи
    # разорвала бы аргумент — такого имени у задачи Windows быть не может
    if ($Full -match '["\r\n]') { return 'fail' }
    $null = Invoke-OneShotTask -TaskName 'Win11Privacy Task' -Execute "$env:SystemRoot\System32\schtasks.exe" -Arguments ('/change /tn "{0}" {1}' -f $Full, $flag) -AsSystem
    $t = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction SilentlyContinue
    if ($t -and ((Test-TaskDisabled $t) -ne $Enabled)) { return 'system' }
    return 'fail'
}

# Часть команды: код 2, если список хранилища не прочитался (cmdkey /list не
# с кодом 0), 1 — если хоть одна из записей ещё в хранилище, иначе 0. Раньше
# сбой самого cmdkey давал пустой вывод, findstr ничего не находил, и это
# читалось как «записей не осталось» — ошибка доступа выглядела отсутствием.
function Get-CredCheckCmd {
    param([string[]]$Targets)
    $finds = @($Targets | ForEach-Object { '/c:"' + ($_ -replace '^.*target=', '') + '"' }) -join ' '
    return '(cmdkey /list >nul 2>&1 || exit 2) & (cmdkey /list | findstr /i ' + $finds + ' >nul && exit 1 || exit 0)'
}

# Учётные данные «личности» устройства — у кого их чистить задачей от его
# имени: у того, кто сидит за компьютером (раньше — всегда у учётной записи
# самого движка: если пароль администратора ввёл обычный пользователь, его
# учётные данные устройства оставались на месте), и у других пользователей,
# которые сейчас в Windows (их кусты подключены). Хранилище самого движка
# чистит его собственный вызов cmdkey (см. Clear-GdidUserCreds).
# session = $true — тот, кто сидит за компьютером.
function Get-GdidCredUsers {
    $out = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $o = Get-OtherSessionUser
    if ($o) { $out.Add(@{ name = "$($o.name)"; sid = "$($o.sid)"; session = $true }); $seen["$($o.sid)"] = $true }
    else { $out.Add(@{ name = "$($script:RunAccount)"; sid = "$($script:UserSid)"; session = $true }) }
    $seen["$($script:UserSid)"] = $true
    # Список подключённых кустов не прочитался — кто ещё вошёл в Windows,
    # неизвестно; стирание тогда не начинается вовсе (Get-GdidPreflight:
    # опись помечает HKEY_USERS как место без доступа). Люди — как в описи
    # ($script:GdidUserSidRx): локальные, доменные и Entra ID (S-1-12-1-…).
    # Раньше вторых здесь не было: их учётные данные устройства не чистились
    # и не назывались непроверенными.
    $names = @()
    try { $names = @(Get-GdidHiveNames) } catch { }
    foreach ($sid in $names) {
        if ($sid -notmatch $script:GdidUserSidRx -or $seen.ContainsKey($sid)) { continue }
        $seen[$sid] = $true
        $nm = ''
        try { $nm = (New-Object Security.Principal.SecurityIdentifier($sid)).Translate([Security.Principal.NTAccount]).Value } catch { }
        $out.Add(@{ name = $nm; sid = $sid; session = $false })
    }
    return $out.ToArray()
}

# Шаг «учётные данные у пользователей». state: Clean, Partial, Failed.
function Clear-GdidUserCreds {
    $fails = 0; $done = 0
    # Код cmdkey сам по себе ничего не говорит: «такой записи нет» — тоже
    # ошибка. Поэтому в конце команда проверяет, что записей действительно не
    # осталось, и только тогда завершается с кодом 0.
    $userCmd = (@($script:GdidCredUser | ForEach-Object { 'cmdkey /delete:' + $_ + ' >nul 2>&1' }) -join ' & ') + ' & ' + (Get-CredCheckCmd $script:GdidCredUser)
    # хранилище учётной записи самого движка — его собственным вызовом
    foreach ($t in $script:GdidCredUser) { $null = & cmdkey.exe "/delete:$t" 2>&1 }
    if (Get-OtherSessionUser) {
        # движок — не тот, кто сидит за компьютером: его хранилище задача ниже
        # не проверит, поэтому сверка здесь же. Список не прочитался (cmdkey
        # не с кодом 0) — это «не проверено», а не «записей нет»: раньше пустой
        # ответ ошибки читался как «убрано».
        $targets = @($script:GdidCredUser | ForEach-Object { $_ -replace '^.*target=', '' })
        $listing = @(& cmdkey.exe /list 2>&1)
        $listCode = $LASTEXITCODE
        $left = @($listing | ForEach-Object { "$_" } | Where-Object {
                      $line = $_; @($targets | Where-Object { $line.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0 })
        if ($listCode -ne 0) { Write-Log ("   [!] учётные данные устройства у {0} не проверены: список хранилища не прочитался (cmdkey, код {1})" -f $script:RunAccount, $listCode); $fails++ }
        elseif ($left.Count -gt 0) { Write-Log ("   [!] учётные данные устройства у {0} убрать не удалось" -f $script:RunAccount); $fails++ }
    }
    foreach ($u in @(Get-GdidCredUsers)) {
        if (-not $u.name) {
            Write-Log ("   [!] учётные данные устройства у пользователя {0} не проверены: имя его учётной записи не определилось" -f $u.sid)
            $fails++; continue
        }
        $ok = Invoke-OneShotTask 'Win11Privacy GDID user' $userCmd -Account $u.name -AccountSid $u.sid -StartSeconds 30
        if ($u.session) {
            if ($ok) { Write-Log '   [+] учётные данные устройства у пользователя убраны'; $done++ }
            else { Write-Log '   [!] учётные данные устройства у пользователя убрать не удалось'; $fails++ }
        } elseif ($ok) { Write-Log ("   [+] учётные данные устройства у пользователя {0} убраны" -f $u.name); $done++ }
        else { Write-Log ("   [!] учётные данные устройства у пользователя {0} убрать не удалось -- задача от его имени идёт, только пока он в Windows" -f $u.name); $fails++ }
    }
    return @{ state = $(if ($fails -eq 0) { 'Clean' } elseif ($done -gt 0) { 'Partial' } else { 'Failed' }); fails = $fails; done = $done }
}

# Шаг «реестр»: удаляется ровно то, что нашла опись (Get-GdidCopies), —
# каждое значение и каждый ключ по отдельности, и каждое удаление сверяется.
# Ветки целиком больше не удаляются: раньше уходил весь
# DeviceIdentities\production вместе с Logs и чужими значениями.
# Ответы: removed (было и убрано — проверено), absent (уже не было), denied
# (Windows не дала, или после удаления запись осталась), kept (личность с
# подключами, которых программа не знает: оставлена целой). Места, которые
# опись не прочитала, — unreadable: о них «убрано» сказать нельзя.
# state: Clean (что было — убрано), NotFound (ничего не было), Partial,
# AccessDenied (не убрано ничего, Windows не дала), Unverified (не убрано
# ничего не из-за отказа, но часть мест не прочиталась).
function Remove-GdidRegistryCopies {
    $st = @{ removed = 0; absent = 0; denied = 0; kept = 0; records = 0; unreadable = 0
             deniedAt = (New-Object System.Collections.Generic.List[string]); keptAt = (New-Object System.Collections.Generic.List[string]) }
    $note = { param($res, $where) $st[$res]++; if ($res -eq 'denied') { $st.deniedAt.Add($where) } elseif ($res -eq 'kept') { $st.keptAt.Add($where) } }
    $recs = @(Get-GdidCopies)
    $st.unreadable = @($script:GdidUnreadable | Select-Object -Unique).Count
    foreach ($rec in $recs) {
        $st.records++
        if ($rec.key) {
            $res = Remove-GdidRegKey "$($rec.parent)" "$($rec.name)" -Tree:([bool]$rec.tree)
            & $note $res "$($rec.path)"
            # указатель раздела на эту личность (ValidDeviceId) — её же
            # запись: убирается, только если указывает ровно на неё
            if ($res -eq 'removed' -and "$($rec.pointer)") {
                $pv = Read-GdidKey "$($rec.pointer)" @('ValidDeviceId')
                if ($pv.state -eq 'ok' -and "$($pv.values['ValidDeviceId'])" -eq "$($rec.name)") {
                    & $note (Remove-GdidRegValue "$($rec.pointer)" 'ValidDeviceId') "$($rec.pointer)\ValidDeviceId"
                } elseif ($pv.state -eq 'denied') { & $note 'denied' "$($rec.pointer)\ValidDeviceId" }
            }
        } else {
            foreach ($vn in @($rec.values)) { & $note (Remove-GdidRegValue "$($rec.path)" "$vn") ("{0}\{1}" -f $rec.path, $vn) }
        }
    }
    Write-Log ("   [+] записи номера в реестре: убрано {0}, не было {1}" -f $st.removed, $st.absent)
    if ($st.denied -gt 0) {
        Write-Log ("   [!] Windows не дала убрать: {0}" -f $st.denied)
        foreach ($w in @($st.deniedAt | Select-Object -Unique -First 5)) { Write-Log ("       {0}" -f ($w -replace '^Microsoft\.PowerShell\.Core\\Registry::', '')) }
    }
    if ($st.kept -gt 0) {
        Write-Log ("   [!] личности устройства с незнакомым содержимым оставлены как есть: {0}" -f $st.kept)
        foreach ($w in @($st.keptAt | Select-Object -Unique -First 3)) { Write-Log ("       {0}" -f ($w -replace '^Registry::', '')) }
    }
    $bad = $st.denied + $st.kept
    $st['state'] = $(if ($bad -eq 0 -and $st.unreadable -eq 0) { if ($st.removed -gt 0) { 'Clean' } else { 'NotFound' } }
                     elseif ($st.removed -gt 0) { 'Partial' } elseif ($st.denied -gt 0) { 'AccessDenied' } elseif ($st.kept -gt 0) { 'Partial' } else { 'Unverified' })
    return $st
}

# Шаг «кэш платформы подключённых устройств»: в нём регистрация в каталоге.
# Чистка удаляет «что сможет» и называет освобождённый объём — это ещё не
# значит, что кэш пуст, поэтому после неё проверяется, что в нём осталось.
# Папка — того, кто сидит за компьютером: чистит её задача от его имени
# (Clear-Folder), и проверяется она же. Раньше проверялась папка учётной
# записи самого движка: при повышении под другой учётной записью проверка
# смотрела не туда. others — сколько других вошедших пользователей: их кэш
# не чистится, и «стёрто отовсюду» тогда сказать нельзя.
# state: Clean, NotFound, Partial (файлы остались), Unverified (не проверить).
#
# Проверка — своим обходом (Get-GdidDirLeft): по ссылкам (junction,
# символическим) он не ходит, а сама ссылка внутри кэша считается тем, что
# осталось. Раньше проверка (Get-ChildItem -Recurse -File) ссылок не видела
# вовсе, папку без доступа считала пустой, а «папки нет» решала Test-Path —
# и при отказе в доступе тоже говорила «нет».
function Get-GdidDirLeft {
    param([string]$Dir, [int]$MaxDepth = 32)
    $out = @{ files = 0; links = 0; errors = 0; samples = (New-Object System.Collections.Generic.List[string]); errorAt = (New-Object System.Collections.Generic.List[string]) }
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push(@($Dir, 0))
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        $d = [string]$cur[0]; $depth = [int]$cur[1]
        $items = $null
        try { $items = ([IO.DirectoryInfo]$d).GetFileSystemInfos() }
        catch { $out.errors++; if ($out.errorAt.Count -lt 3) { $out.errorAt.Add(("{0}: {1}" -f $d, $_.Exception.Message)) }; continue }
        foreach ($it in @($items)) {
            if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $out.links++
                if ($out.samples.Count -lt 3) { $out.samples.Add($it.FullName) }
                continue
            }
            if ($it -is [IO.DirectoryInfo]) {
                if ($depth -ge $MaxDepth) { $out.errors++; if ($out.errorAt.Count -lt 3) { $out.errorAt.Add(("{0}: слишком глубоко" -f $it.FullName)) }; continue }
                $stack.Push(@($it.FullName, ($depth + 1)))
                continue
            }
            $out.files++
            if ($out.samples.Count -lt 3) { $out.samples.Add($it.FullName) }
        }
    }
    return $out
}

function Clear-GdidCdpCache {
    $dir = Convert-ToSessionPath $script:CdpCache
    $others = @(@(Get-GdidCredUsers) | Where-Object { -not $_.session }).Count
    if ($others -gt 0) { Write-Log ("   [i] кэш платформы подключённых устройств других пользователей, которые сейчас в Windows, не чистится: {0}" -f $others) }
    # Сама папка: «нет» — только когда Windows так и ответила; ссылка вместо
    # папки не чистится (задача от имени пользователя тоже откажется)
    $root = $null
    try { $root = Get-Item -LiteralPath $dir -Force -ErrorAction Stop }
    catch [System.Management.Automation.ItemNotFoundException] { return @{ state = 'NotFound'; left = 0; dir = $dir; others = $others } }
    catch {
        Write-Log ("   [!] папку кэша платформы подключённых устройств не удалось открыть: {0} -- очищена ли она, неизвестно" -f $_.Exception.Message)
        return @{ state = 'Unverified'; left = 0; dir = $dir; others = $others }
    }
    if ($root.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Write-Log ("   [!] на месте кэша платформы подключённых устройств лежит ссылка ({0}) -- не очищается" -f $dir)
        return @{ state = 'Partial'; left = 1; dir = $dir; others = $others }
    }
    $null = Clear-Folder $dir 'кэш платформы подключённых устройств'
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        # папки не стало — это ещё надо подтвердить тем же способом
        try { $null = Get-Item -LiteralPath $dir -Force -ErrorAction Stop }
        catch [System.Management.Automation.ItemNotFoundException] { return @{ state = 'Clean'; left = 0; dir = $dir; others = $others } }
        catch { Write-Log '   [!] кэш платформы подключённых устройств не удалось проверить (нет доступа) -- очищен ли он, неизвестно'; return @{ state = 'Unverified'; left = 0; dir = $dir; others = $others } }
    }
    $lf = Get-GdidDirLeft $dir
    $left = [int]$lf.files + [int]$lf.links
    if ($left -gt 0) {
        Write-Log ("   [!] в кэше платформы подключённых устройств осталось: файлов {0}, ссылок {1} -- Windows их не отдала" -f $lf.files, $lf.links)
        foreach ($f in @($lf.samples)) { Write-Log ("       {0}" -f $f) }
        return @{ state = 'Partial'; left = $left; dir = $dir; others = $others }
    }
    if ([int]$lf.errors -gt 0) {
        Write-Log ("   [!] кэш платформы подключённых устройств не удалось проверить целиком (папок без доступа: {0}) -- очищен ли он, неизвестно" -f $lf.errors)
        foreach ($f in @($lf.errorAt)) { Write-Log ("       {0}" -f $f) }
        return @{ state = 'Unverified'; left = 0; dir = $dir; others = $others }
    }
    return @{ state = 'Clean'; left = 0; dir = $dir; others = $others }
}

# Стирает «личность» устройства и все известные копии номера. Пока сервер
# выдачи открыт, Windows при следующем обращении получит новый номер — это
# смена. Под запретом выдачи — номера не станет вовсе.
#
# Порядок: ограничения → предварительная проверка (только чтение) →
# wlidsvc — в журнал отката и отключить → остановка служб → учётные данные у
# пользователей → у системы → реестр → кэш платформы подключённых устройств →
# проверка → службы как были → итог.
# Предварительная проверка (Get-GdidPreflight) идёт до любого изменения:
# опись копий без мест без доступа, список профилей и полный снимок служб.
# Чего-то из этого нет — не меняется ничего. Раньше стирание начиналось,
# даже если часть мест не прочиталась, а состояния служб собирались без
# проверки ошибок.
# Проверка итога — пока службы стоят: иначе поднявшаяся wlidsvc успевала
# завести новый номер. Службы возвращаются в finally — на любом пути, и при
# исключении тоже: раньше ранний отказ возвращал службы по пустому списку.
# Итог — $script:GdidWipeResult (New-GdidResult); state:
#   Clean        — копии были и стёрты, проверено всё;
#   NotFound     — копий не было, проверено всё;
#   Partial      — что-то стёрто, а что-то нет (или не вернулись службы);
#   AccessDenied — Windows не дала убрать ни одной копии;
#   Unverified   — копий не нашлось, но проверено не всё: профили тех, кто
#                  не вошёл в Windows, места без доступа, чужие кэши;
#   Failed       — не стёрто ничего: отказ, предварительная проверка не
#                  прошла или службы не остановились;
#   DryRun       — пробный запуск: стирание началось бы и могло бы дойти до
#                  проверенного итога.
# Успех ($true) — только Clean, NotFound и DryRun.
$script:GdidWipeResult = $null

# Итог операции с номером — одна форма для стирания и возврата: окно, журнал
# работы и код выхода берут его отсюда и не расходятся.
#   operation — wipe или restore; status (и прежнее имя state) — итог;
#   success   — всё прошло и проверено (тогда exitCode 0, иначе 2);
#   complete  — проверено всё, что нужно для такого ответа;
#   checked   — сколько копий нашла опись до стирания (у возврата — стадий);
#   removed   — сколько записей убрано; remaining — сколько копий осталось;
#   failed    — сколько шагов не удалось; unverified — мест без доступа;
#   uncheckedProfiles — профили вне Windows и чужие непроверенные кэши;
#   serviceStates — службы до и после; warnings, errors; timestamp.
# Пустой итог — ещё не «чисто»: начальное состояние — Failed.
function New-GdidResult {
    param([string]$Operation)
    return [ordered]@{
        operation = $Operation; status = 'Failed'; state = 'Failed'; success = $false; complete = $false
        checked = 0; removed = 0; remaining = 0; failed = 0; unverified = 0; uncheckedProfiles = 0
        serviceStates = @(); warnings = (New-Object System.Collections.Generic.List[string]); errors = (New-Object System.Collections.Generic.List[string])
        timestamp = (Get-Date).ToString('s'); exitCode = 2
        # прежние поля ответа — их читают проверки и окно
        before = 0; after = 0; denied = 0; unreadable = 0; unchecked = 0; stages = [ordered]@{}; notBack = @(); preflight = @()
    }
}

# Итог — одним вызовом: состояние, успех, полнота и код выхода вместе
function Set-GdidResultState {
    param($Result, [string]$State)
    $Result['state'] = $State; $Result['status'] = $State
    $Result['success'] = ($State -in @('Clean', 'NotFound', 'DryRun', 'Restored', 'NotModified'))
    $Result['complete'] = [bool]$Result['success']
    $Result['exitCode'] = $(if ($Result['success']) { 0 } else { 2 })
}

# Предварительная проверка стирания — только чтение, до любого изменения.
# ok — можно начинать. blockers — почему нельзя: места без доступа (копии в
# них остались бы, и Windows вернула бы номер), список профилей не прочитался
# (чьи копии на месте, неизвестно), снимок служб неполный (вернуть их потом
# было бы не по чему). warnings — то, что стиранию не мешает, но полного
# «стёрто отовсюду» не даст: профили тех, кто не вошёл в Windows, и
# незнакомые подключи личностей (они не трогаются).
function Get-GdidPreflight {
    $p = @{ ok = $false; blockers = (New-Object System.Collections.Generic.List[string]); warnings = (New-Object System.Collections.Generic.List[string])
            scan = $null; snapshot = $null }
    $scan = Get-GdidScan
    $p.scan = $scan
    if ($scan.profiles.enumerationFailed) {
        $p.blockers.Add(("список профилей пользователей не прочитался ({0}) -- чьи копии номера на месте, неизвестно" -f (@($scan.profiles.errors) -join '; ')))
    }
    $regUnread = @(@($scan.unreadable) | Where-Object { @($scan.profiles.places) -notcontains $_ })
    if ($regUnread.Count -gt 0) {
        $p.blockers.Add(("мест без доступа на чтение: {0} ({1}) -- копии номера в них остались бы, и Windows вернула бы его" -f $regUnread.Count,
                         ((@($regUnread | Select-Object -First 3) | ForEach-Object { "$_" -replace '^Registry::', '' }) -join '; ')))
    }
    if ([int]$scan.profiles.unloadedProfiles -gt 0) {
        $p.warnings.Add(("профили пользователей, которые сейчас не вошли в Windows, не проверяются: {0}" -f $scan.profiles.unloadedProfiles))
    }
    if (@($scan.unknown).Count -gt 0) {
        $p.warnings.Add(("подключи личностей устройства без DeviceId оставлены как есть: {0}" -f @($scan.unknown).Count))
    }
    $snap = Get-GdidServiceSnapshot
    $p.snapshot = $snap
    if (-not $snap.complete) { foreach ($x in @($snap.problems)) { $p.blockers.Add(("службы: {0}" -f $x)) } }
    # Кто сидит за компьютером: от этого зависит, чьи учётные данные и чей
    # кэш стираются. Windows не ответила — это «неизвестно», а не «сам движок».
    $null = Get-SessionUser
    if ($script:SessionUserError) { $p.blockers.Add(("кто сидит за компьютером, определить не удалось ({0}) -- чьи учётные данные и кэш стирать, неизвестно" -f $script:SessionUserError)) }
    $p.ok = ($p.blockers.Count -eq 0)
    return $p
}

# --------------------------------------------------------------------------- #
#  Запись о ходе стирания (Write-OpRecord 'gdid-wipe'): какие службы работали
#  до него. Стирание останавливает их и запускает только в конце; раньше этот
#  список жил только в памяти, и после обрыва (закрыли окно, выключили
#  питание) службы стояли до перезагрузки, а повторное стирание снимало их
#  уже остановленными — и в конце не запускало. Теперь:
#    * пока идёт стирание, держится замок операции (второе стирание сразу —
#      отказ), а запись лежит на диске с самого начала, до первого изменения;
#    * закончилось и службы вернулись — запись убирается; не вернулись —
#      остаётся с тем, что не вернулось;
#    * следующая смена номера берёт службы из оставшейся записи в свой
#      список «запустить в конце», «Вернуть как было» запускает их сам.
#  Сам по себе ничего не перезапускается: только по действию человека.
# --------------------------------------------------------------------------- #
$script:GdidWipeOp = 'gdid-wipe'

# Оборванное стирание глазами окна. state: none; InProgress (идёт сейчас);
# RecoveryRequired (оборвалось или службы не вернулись, и что-то из того,
# что работало до него, стоит: stopped); Settled (запись осталась, но всё,
# что работало, снова работает — например, после перезагрузки); Untrusted /
# Unreadable. wlidsvc в stopped не считается: она запускается по требованию,
# и «стоит» для неё — обычное дело (запустит её «Вернуть как было»).
function Get-GdidWipeRecovery {
    $r = Read-OpRecord $script:GdidWipeOp
    $o = [ordered]@{ state = 'none'; recoveryRequired = $false; running = @(); stopped = @(); notBack = @(); started = ''; error = "$($r.error)" }
    if ($r.state -eq 'none') { return $o }
    if ($r.state -eq 'unreadable') { $o.state = 'Unreadable'; $o.recoveryRequired = $true; return $o }
    if ($r.state -eq 'untrusted') { $o.state = 'Untrusted'; $o.recoveryRequired = $true; return $o }
    $o.running = @(@($r.data.running) | ForEach-Object { "$_" } | Where-Object { Test-GdidWipeSvcName $_ })
    $o.notBack = @(@($r.data.notBack) | ForEach-Object { "$_" } | Where-Object { $_ })
    $o.started = "$($r.data.started)"
    if ((Test-OpRunning $script:GdidWipeOp) -eq $true) { $o.state = 'InProgress'; return $o }
    $o.stopped = @($o.running | Where-Object { $_ -ne 'wlidsvc' } | Where-Object { $v = Get-SvcScmView $_; -not $v.ok -or ($v.found -and -not $v.running) })
    $o.recoveryRequired = (@($o.stopped).Count -gt 0)
    $o.state = $(if ($o.recoveryRequired) { 'RecoveryRequired' } else { 'Settled' })
    return $o
}

# Имена служб из записи — только того вида, какой пишет само стирание
function Test-GdidWipeSvcName {
    param([string]$Name)
    return ($Name -cmatch '^(wlidsvc|CDPSvc|CDPUserSvc|DoSvc|CDPUserSvc_[0-9A-Fa-f]{1,16})$')
}

# «Вернуть как было» после оборванного стирания: запустить службы, которые
# работали до него и сейчас стоят (если Windows даёт: отключённую не
# запускаем — её тип запуска возвращает журнал отката, и это его решение).
# Ответ: state — NotModified (записи не было), Restored (запущено и сверено,
# запись убрана), RestoreFailed (что-то не запустилось — запись остаётся),
# InProgress (стирание идёт сейчас); started, failed, skipped, warnings.
function Restore-GdidInterruptedWipe {
    $o = @{ state = 'NotModified'; started = @(); failed = @(); skipped = @(); error = '' }
    $lock = $null
    try {
        $lock = Enter-OpLock $script:GdidWipeOp
        if ($null -eq $lock) { $o.state = 'InProgress'; $o.error = 'стирание номера идёт сейчас'; return $o }
        $r = Read-OpRecord $script:GdidWipeOp
        if ($r.state -eq 'none') { return $o }
        if ($r.state -eq 'unreadable') { $o.state = 'RestoreFailed'; $o.error = ("запись о прошлом стирании не читается: {0}" -f $r.error); return $o }
        if ($r.state -eq 'untrusted') {
            $aside = Set-OpRecordAside $script:GdidWipeOp
            $o.error = ("запись о прошлом стирании недоверенная ({0}) -- по ней ничего не запускается, она отложена как {1}" -f $r.error, $aside)
            $o.state = 'RestoreFailed'; return $o
        }
        $started = New-Object System.Collections.Generic.List[string]
        $failed = New-Object System.Collections.Generic.List[string]
        $skipped = New-Object System.Collections.Generic.List[string]
        foreach ($n in @(@($r.data.running) | ForEach-Object { "$_" })) {
            if (-not (Test-GdidWipeSvcName $n)) { $skipped.Add($n); continue }
            $v = Get-SvcScmView $n
            if (-not $v.ok) { $failed.Add(("{0} (диспетчер служб не ответил)" -f $n)); continue }
            # копия CDPUserSvc ушла вместе с выходом пользователя — запускать нечего
            if (-not $v.found) { $skipped.Add($n); continue }
            if ($v.running) { continue }
            if ((Get-SvcStartInfo $n).state -eq 'Disabled') { $skipped.Add(("{0} (отключена)" -f $n)); continue }
            try {
                Start-Service -Name $n -ErrorAction Stop -WarningAction SilentlyContinue
                (Get-Service -Name $n -ErrorAction Stop).WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
            } catch { }
            $after = Get-SvcScmView $n
            if ($after.ok -and $after.found -and "$($after.status)" -eq 'Running') { $started.Add($n) } else { $failed.Add($n) }
        }
        $o.started = $started.ToArray(); $o.failed = $failed.ToArray(); $o.skipped = $skipped.ToArray()
        if ($failed.Count -gt 0) {
            $d = [ordered]@{ state = 'RestoreFailed'; started = "$($r.data.started)"; running = @($r.data.running | ForEach-Object { "$_" }); notBack = $failed.ToArray() }
            try { Write-OpRecord $script:GdidWipeOp $d } catch { }
            $o.state = 'RestoreFailed'
        } else {
            if (-not (Remove-OpRecord $script:GdidWipeOp)) { $o.error = 'запись о прошлом стирании не убралась' }
            $o.state = 'Restored'
        }
        return $o
    } catch { $o.state = 'RestoreFailed'; $o.error = "$($_.Exception.Message)"; return $o }
    finally { if ($null -ne $lock) { $lock.Dispose() } }
}

function Invoke-GdidWipe {
    $res = New-GdidResult 'wipe'
    $script:GdidWipeResult = $res
    $why = Get-ManagedReason
    if ($why) {
        Write-Log ("   [!] номер устройства не тронут: {0}. На таком компьютере он связан с учётной записью организации." -f $why)
        $res.stages['restrictions'] = 'refused'; $res.errors.Add("$why"); $res.failed = 1
        Set-GdidResultState $res 'Failed'
        $script:Failures++; return $false
    }
    $res.stages['restrictions'] = 'ok'

    # 0. предварительная проверка — только чтение: до неё не меняется ничего
    $pre = Get-GdidPreflight
    $before = @($pre.scan.copies)
    $res.before = $before.Count; $res.checked = $before.Count
    $res.unreadable = @($pre.scan.unreadable).Count; $res.unverified = $res.unreadable
    $res.unchecked = [int]$pre.scan.unchecked; $res.uncheckedProfiles = $res.unchecked
    $res.preflight = $pre.blockers.ToArray()
    foreach ($w in $pre.warnings.ToArray()) { $res.warnings.Add("$w") }
    $res.serviceStates = @(@($pre.snapshot.services) | ForEach-Object { @{ name = "$($_.name)"; before = @{ start = [int]$_.start; running = [bool]$_.running; status = "$($_.status)" } } })
    $res.stages['preflight'] = $(if ($pre.ok) { 'ok' } else { 'Failed' })
    $tag = $(if ($DryRun) { '[тест]' } else { '[!]' })
    if (-not $pre.ok) {
        Write-Log ("   {0} номер устройства не тронут: предварительная проверка не прошла -- ничего не изменено" -f $tag)
        foreach ($b in $pre.blockers.ToArray()) { Write-Log ("       {0}" -f $b); $res.errors.Add("$b") }
        $res.failed = 1
        # копий не нашлось, но проверить всё не вышло — «не проверено», а не «чисто»
        Set-GdidResultState $res $(if ($before.Count -eq 0) { 'Unverified' } else { 'Failed' })
        $script:Failures++; return $false
    }
    if ($DryRun) {
        Write-Log ("   [тест] копий номера устройства: {0} -- будут стёрты вместе с «личностью» устройства" -f $before.Count)
        # Пробный запуск не обещает больше, чем даст настоящий: раньше он
        # отвечал «успех» всегда, даже когда часть мест не проверялась
        $othersN = @(@(Get-GdidCredUsers) | Where-Object { -not $_.session }).Count
        $res.uncheckedProfiles = $res.unchecked + $othersN
        if ([bool]$pre.scan.profiles.unverified -or $othersN -gt 0) {
            Write-Log ("   [тест] проверено будет не всё: профилей вне Windows {0}, других вошедших пользователей {1} -- «стёрто отовсюду» стирание не скажет" -f $res.unchecked, $othersN)
            Set-GdidResultState $res 'Unverified'
            $script:Failures++; return $false
        }
        Set-GdidResultState $res 'DryRun'
        return $true
    }
    Write-Log ("   найдено копий номера: {0}" -f $before.Count)
    foreach ($w in $pre.warnings.ToArray()) { Write-Log ("   [i] {0}" -f $w) }

    # Службы, которые работали до стирания, — по снимку. Их стирание
    # останавливает (они держат номер в памяти и вернули бы его) и потом
    # запускает снова; стоявшие до стирания не запускаются.
    $snap = $pre.snapshot
    $runningBefore = @(@($snap.services) | Where-Object { $_.running -and $_.scmFound } | ForEach-Object { "$($_.name)" })

    # Замок и запись о ходе стирания — до первого изменения (см.
    # Get-GdidWipeRecovery). Не вышло — не стираем: обрыв потом оставил бы
    # службы стоять, и никто бы о них не знал.
    $opLock = $null
    $opWhy = ''
    try { $opLock = Enter-OpLock $script:GdidWipeOp; if ($null -eq $opLock) { $opWhy = 'другое стирание номера идёт сейчас' } }
    catch { $opWhy = ("замок стирания не открылся: {0}" -f $_.Exception.Message) }
    if (-not $opWhy) {
        $prevOp = Read-OpRecord $script:GdidWipeOp
        if ($prevOp.state -eq 'unreadable') { $opWhy = ("запись о прошлом стирании не читается ({0})" -f $prevOp.error) }
        elseif ($prevOp.state -eq 'untrusted') {
            try { $aside = Set-OpRecordAside $script:GdidWipeOp; Write-Log ("   [!] запись о прошлом стирании недоверенная ({0}) -- по ней ничего не запускается, она отложена как {1}" -f $prevOp.error, $aside) }
            catch { $opWhy = ("недоверенная запись о прошлом стирании не откладывается: {0}" -f $_.Exception.Message) }
        } elseif ($prevOp.state -eq 'valid') {
            # Прошлое стирание оборвалось (или службы после него не вернулись):
            # службы, что работали до него, сейчас могут стоять — в конце их
            # запускаем и мы, иначе они так и стояли бы до перезагрузки.
            $carried = @(@($prevOp.data.running) | ForEach-Object { "$_" } | Where-Object { (Test-GdidWipeSvcName $_) -and $runningBefore -notcontains $_ })
            if ($carried.Count -gt 0) {
                Write-Log ("   [i] прошлое стирание номера не закончилось; службы, что работали до него, будут запущены в конце: {0}" -f ($carried -join ', '))
                $res.warnings.Add(("прошлое стирание не закончилось: {0}" -f ($carried -join ', ')))
                foreach ($e in @($snap.services)) {
                    if ($carried -contains "$($e.name)" -and $e.scmFound) { $e['running'] = $true; $runningBefore += "$($e.name)" }
                }
            }
        }
    }
    if (-not $opWhy) {
        try { Write-OpRecord $script:GdidWipeOp ([ordered]@{ state = 'InProgress'; started = (Get-Date).ToString('s'); running = @($runningBefore); notBack = @() }) }
        catch { $opWhy = ("запись о ходе стирания не записалась: {0}" -f $_.Exception.Message) }
    }
    if ($opWhy) {
        if ($null -ne $opLock) { $opLock.Dispose() }
        Write-Log ("   [!] номер устройства не тронут: {0} -- ничего не изменено" -f $opWhy)
        $res.stages['services'] = 'refused'; $res.errors.Add($opWhy); $res.failed = 1
        Set-GdidResultState $res 'Failed'
        $script:Failures++; return $false
    }

    # что стирание пыталось остановить — возвращается всё это (из тех, что работали)
    $touched = New-Object System.Collections.Generic.List[string]
    $notBackMsg = '   [!] службы не вернулись в прежнее состояние: {0}. Перезагрузка компьютера вернёт их.'
    $wlid = $null
    $fails = 0
    $aborted = ''
    $verify = $null
    $reg = @{ removed = 0; denied = 0; kept = 0 }
    $cdp = @{ others = 0 }
    $restore = $null
    try {
        $wlid = Disable-GdidWlid
        if (-not $wlid.ok) {
            Write-Log ("   [!] номер устройства не тронут: {0} -- службу учётных записей Microsoft нельзя отключить на время стирания, не записав, как было." -f $wlid.why)
            $res.stages['services'] = 'refused'; $res.errors.Add("$($wlid.why)")
            $aborted = 'refused'
        } else {
            if ($wlid.why) { Write-Log ("   [i] {0}" -f $wlid.why) }
            $res.stages['services'] = 'saved'
            $touched.Add('wlidsvc')
            if (-not (Stop-ServiceWait 'wlidsvc')) {
                Write-Log '   [!] служба учётных записей Microsoft (wlidsvc) занята и не остановилась. Закройте Магазин и Параметры и повторите или перезагрузите компьютер. Ничего не стёрто.'
                $aborted = 'stop'
            } else {
                # Служба, которая не остановилась, держит номер в памяти и
                # записала бы его обратно посреди стирания. Тогда не стираем
                # ничего и возвращаем всё как было.
                $stuck = New-Object System.Collections.Generic.List[string]
                foreach ($n in $runningBefore) {
                    if ($n -eq 'wlidsvc') { continue }
                    $touched.Add($n)
                    if (-not (Stop-ServiceWait $n)) { $stuck.Add($n) }
                }
                if ($stuck.Count -gt 0) {
                    Write-Log ("   [!] служба не остановилась: {0}. Она держит номер устройства и вернула бы его на место. Ничего не стёрто -- повторите позже или после перезагрузки." -f ($stuck.ToArray() -join ', '))
                    $aborted = 'stop'
                }
            }
            $res.stages['stop'] = $(if ($aborted) { 'Failed' } else { 'ok' })
        }
        if (-not $aborted) {
            # 1. учётные данные «личности» устройства — у пользователей и у системы
            $cu = Clear-GdidUserCreds
            $res.stages['userCredentials'] = $cu.state
            $fails += [int]$cu.fails
            $sysCmd = (@($script:GdidCredSystem | ForEach-Object { 'cmdkey /delete:' + $_ + ' >nul 2>&1' }) -join ' & ') + ' & ' + (Get-CredCheckCmd $script:GdidCredSystem)
            if (Invoke-OneShotTask 'Win11Privacy GDID system' $sysCmd -AsSystem) { Write-Log '   [+] учётные данные устройства у системы убраны'; $res.stages['systemCredentials'] = 'Clean' }
            else { Write-Log '   [!] учётные данные устройства у системы убрать не удалось'; $fails++; $res.stages['systemCredentials'] = 'Failed' }
            # 2. копии номера в реестре — ровно найденные записи
            $reg = Remove-GdidRegistryCopies
            $res.stages['registry'] = $reg.state
            if ([int]$reg.denied -gt 0 -or [int]$reg.kept -gt 0) { $fails++ }
            # 3. кэш платформы подключённых устройств
            $cdp = Clear-GdidCdpCache
            $res.stages['cdp'] = $cdp.state
            if ($cdp.state -notin @('Clean', 'NotFound')) { $fails++ }
            # 4. проверка — пока службы стоят и вернуть номер некому
            $verify = Get-GdidScan
            $res.stages['verify'] = $verify.state
        }
    } catch {
        $aborted = 'exception'
        $res.errors.Add("$($_.Exception.Message)")
        Write-Log ("   [!] стирание прервалось: {0}" -f $_.Exception.Message)
    } finally {
        # 5. службы — как были, что бы ни случилось выше
        $back = @($touched.ToArray() | Where-Object { $runningBefore -contains $_ })
        try { $restore = Restore-GdidServices $back $wlid $snap }
        catch { $restore = @{ notBack = @(('службы (возврат прервался: {0})' -f $_.Exception.Message)); states = @() } }
        $res.notBack = @($restore.notBack)
        if (@($restore.states).Count -gt 0) { $res.serviceStates = @($restore.states) }
        $res.stages['restore'] = $(if (@($restore.notBack).Count -gt 0) { 'Failed' } else { 'ok' })
        if (@($restore.notBack).Count -gt 0) { Write-Log ($notBackMsg -f (@($restore.notBack) -join ', ')) }
        # Запись о ходе: службы вернулись — убираем; не вернулись — остаётся с
        # тем, что не вернулось («Вернуть как было» запустит их снова)
        try {
            if (@($restore.notBack).Count -eq 0) {
                if (-not (Remove-OpRecord $script:GdidWipeOp)) { Write-Log '   [i] запись о ходе стирания не убралась' }
            } else {
                Write-OpRecord $script:GdidWipeOp ([ordered]@{ state = 'RestoreFailed'; started = "$($res.timestamp)"; running = @($runningBefore); notBack = @($restore.notBack | ForEach-Object { "$_" }) })
            }
        } catch { Write-Log ("   [!] запись о ходе стирания не обновилась: {0}" -f $_.Exception.Message) }
        $opLock.Dispose()
    }
    $res.removed = [int]$reg.removed; $res.denied = [int]$reg.denied
    if (@($res.notBack).Count -gt 0) { $fails++ }
    if ($aborted -in @('refused', 'stop')) {
        $res.failed = $fails + 1
        Set-GdidResultState $res 'Failed'; $script:Failures++; return $false
    }
    if ($aborted -eq 'exception') {
        # что успело стереться до сбоя, неизвестно наверняка
        $res.failed = $fails + 1
        Set-GdidResultState $res $(if ($res.removed -gt 0) { 'Partial' } else { 'Failed' })
        Write-Log '   [!] стирание прошло не полностью -- повторите его; службы возвращены, как были'
        $script:Failures++; return $false
    }

    $after = @($verify.copies)
    $unread = @($verify.unreadable)
    $unchecked = [int]$verify.unchecked + [int]$cdp.others
    $profUnverified = [bool]$verify.profiles.unverified
    $res.after = $after.Count; $res.remaining = $after.Count
    $res.unreadable = $unread.Count; $res.unverified = $unread.Count
    $res.unchecked = $unchecked; $res.uncheckedProfiles = $unchecked
    $res.failed = $fails
    if ($after.Count -gt 0) { Write-Log ("   [!] осталось копий номера: {0} -- Windows их не отдала" -f $after.Count) }
    if ($unread.Count -gt 0) {
        # «не нашли» там, куда не пустили, — не то же самое, что «стёрто»
        Write-Log ("   [!] не удалось проверить мест: {0} (нет доступа) -- стёрто ли там, неизвестно" -f $unread.Count)
        foreach ($u in @($unread | Select-Object -First 3)) { Write-Log ("       {0}" -f ($u -replace '^Microsoft\.PowerShell\.Core\\Registry::', '')) }
    }
    if ([int]$verify.unchecked -gt 0) {
        Write-Log ("   [i] профили пользователей, которые сейчас не вошли в Windows, не проверялись: {0}. У тех из них, кто входит через учётную запись Microsoft, может остаться прежний номер." -f $verify.unchecked)
        $res.warnings.Add(("профили пользователей вне Windows не проверялись: {0} -- в них может остаться прежний номер" -f $verify.unchecked))
    }
    # Успех — только когда прошло всё: копий нет, учётные данные убраны, кэш
    # пуст, службы вернулись и проверено всё, включая список профилей.
    $state = $(if ($fails -eq 0 -and $after.Count -eq 0 -and $unread.Count -eq 0 -and $unchecked -eq 0 -and -not $profUnverified) { if ($before.Count -eq 0 -and $res.removed -eq 0) { 'NotFound' } else { 'Clean' } }
               elseif ($fails -eq 0 -and $after.Count -eq 0) { 'Unverified' }
               elseif ($after.Count -gt 0 -and $res.removed -eq 0 -and $res.denied -gt 0) { 'AccessDenied' }
               else { 'Partial' })
    Set-GdidResultState $res $state
    if ($state -eq 'Clean') { Write-Log '   [+] номер устройства стёрт отовсюду, где программа его ищет'; $script:Changes++ }
    elseif ($state -eq 'NotFound') { Write-Log '   [+] копий номера не нашлось -- проверено всё, где программа его ищет' }
    else {
        if ($state -eq 'Unverified') { Write-Log '   [!] там, где программа смогла проверить, копий номера не осталось, но проверено не всё -- см. выше' }
        elseif ($after.Count -eq 0) { Write-Log '   [!] копий номера в реестре не осталось, но стирание прошло не полностью -- см. выше' }
        if ($res.removed -gt 0) { $script:Changes++ }
        $script:Failures++
    }
    return [bool]$res.success
}

# «Вернуть как было», службы: тип запуска — из журнала отката, ровно для тех
# служб, которые меняла программа (wlidsvc — если её оставило отключённой
# прерванное стирание). result:
#   restored     — возвращён, и тип запуска сверен с журналом;
#   notChanged   — программа её не меняла (записи в журнале нет);
#   notFound     — запись есть, а службы на этой системе больше нет: возвращать
#                  некуда, запись в журнале остаётся (это не ошибка);
#   accessDenied — тип запуска не читается или Windows не дала его записать;
#   failed       — не вернулся (или журналу нельзя верить).
# Запись журнала убирается только после сверки (это делает Restore-ChangeKey).
# Раньше любой отказ — журналу нельзя верить, тип запуска не вернулся —
# назывался «программа её не меняла» и ошибкой не считался, а пропавшая
# служба — «возвращена».
function Restore-GdidServiceStarts {
    $out = New-Object System.Collections.Generic.List[object]
    $jf = Read-JournalFile -ReadOnly
    $first = @{}
    if ($jf.trusted) {
        foreach ($it in @($jf.items)) {
            $f = ConvertTo-Fields $it
            $k = Get-JournalKey $f
            if (-not $first.ContainsKey($k)) { $first[$k] = $f }
        }
    }
    foreach ($n in @($script:GdidSvcNames + 'wlidsvc')) {
        $key = $(if ($n -eq 'wlidsvc') { 'svc|wlidsvc' } else { ("reg|HKLM:\SYSTEM\CurrentControlSet\Services\{0}|Start" -f $n).ToLowerInvariant() })
        if (-not $jf.trusted) { $out.Add(@{ name = $n; result = 'failed'; error = 'журналу отката нельзя верить: подпись не сошлась или он не прочитался' }); continue }
        if (-not $first.ContainsKey($key)) { $out.Add(@{ name = $n; result = 'notChanged'; error = '' }); continue }
        $want = "$($first[$key]['old'])"
        $now = Get-SvcStartInfo $n
        if ("$($now.state)" -eq 'Missing') { $out.Add(@{ name = $n; result = 'notFound'; error = 'службы на этой системе больше нет' }); continue }
        if ("$($now.state)" -eq 'ReadError') { $out.Add(@{ name = $n; result = 'accessDenied'; error = ("тип запуска не читается: {0}" -f $now.error) }); continue }
        $r = Restore-ChangeKey $key
        if (-not $r.ok) {
            $out.Add(@{ name = $n; result = $(if ($r.denied) { 'accessDenied' } elseif ($r.missing) { 'notFound' } else { 'failed' }); error = "$($r.error)" })
            continue
        }
        if ($r.missing) { $out.Add(@{ name = $n; result = 'notFound'; error = 'службы на этой системе больше нет' }); continue }
        # сверка: тип запуска — тот, что был до программы
        $chk = Get-SvcStartInfo $n
        if ($want -match '^[0-4]$' -and "$($chk.start)" -ne $want) {
            $out.Add(@{ name = $n; result = 'failed'; error = ("после возврата тип запуска {0}, а было {1}" -f (Get-StartName "$($chk.start)"), (Get-StartName $want)) })
            continue
        }
        $out.Add(@{ name = $n; result = 'restored'; error = '' })
    }
    return $out.ToArray()
}

# Сколько блоков этого вида в hosts (вместе с осиротевшими метками);
# -1 — hosts не прочитался
function Get-GdidHostsFound {
    param([string]$Kind)
    try { return [int](Get-HostsLinesWithout (Read-HostsLines) $Kind).found } catch { return -1 }
}

# После возврата типа запуска в реестре диспетчер служб до перезагрузки
# помнит «отключена» (службы отключались прямо в реестре) — и не запустит её.
# Поэтому тип запуска передаётся и ему (Set-Service; DoSvc Windows не даёт и
# администратору), службы с автоматическим запуском запускаются, копии
# CDPUserSvc, заведённые отключёнными, получают тип запуска шаблона.
# Чего сразу не вышло, так и названо: pending — после перезагрузки или
# выхода из Windows (это не ошибка), failed — не запустилась (ошибка).
function Sync-GdidRestoredServices {
    param([string[]]$Names)
    $pending = New-Object System.Collections.Generic.List[string]
    $failed = New-Object System.Collections.Generic.List[string]
    $toScm = { param($n) switch ((Get-SvcStartInfo $n).start) { 2 { 'Automatic' } 3 { 'Manual' } default { '' } } }
    # Код ошибки Windows в исключении (по цепочке InnerException); 0 — нет кода
    $winCode = {
        param($Ex)
        for ($x = $Ex; $null -ne $x; $x = $x.InnerException) {
            if ($x -is [System.ComponentModel.Win32Exception]) { return [int]$x.NativeErrorCode }
        }
        if ("$($Ex.Message)" -match '\b1058\b') { return 1058 }
        return 0
    }
    $bring = {
        param([string]$Svc, [string]$Want, [string]$Later)
        $v = Get-SvcScmView $Svc
        if (-not $v.found) { return }
        # Тип запуска передаётся диспетчеру служб всегда. Спрашивать его, какой
        # тип запуска он помнит, бесполезно: Get-Service и sc qc отвечают по
        # реестру («автоматически»), а сам диспетчер до перезагрузки держит
        # «отключена» и не запускает службу (ошибка 1058). Раньше Set-Service
        # звался, только когда Get-Service говорил «отключена», — и после
        # перезагрузки с отключёнными службами CDPSvc не запускалась (VM,
        # 2026-11-16).
        $setOk = $true
        try { Set-Service -Name $Svc -StartupType $Want -ErrorAction Stop } catch { $setOk = $false }
        $v = Get-SvcScmView $Svc
        if ($v.start -eq 'Disabled') { $pending.Add(("{0} ({1})" -f $Svc, $Later)); return }
        if ($Want -ne 'Automatic' -or $v.running) {
            # не запускаем (вручную) — но если диспетчер не принял тип запуска
            # (DoSvc Windows не даёт менять и администратору), он может помнить
            # «отключена» до перезагрузки: так и сказано
            if (-not $setOk -and -not $v.running) { $pending.Add(("{0} ({1})" -f $Svc, $Later)) }
            return
        }
        try {
            Start-Service -Name $Svc -ErrorAction Stop -WarningAction SilentlyContinue
            (Get-Service -Name $Svc -ErrorAction Stop).WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
        } catch {
            # 1058 — диспетчер помнит «отключена», а передать ему тип запуска
            # Windows не дала: служба заработает после перезагрузки. Это не сбой.
            if (-not $setOk -and (& $winCode $_.Exception) -eq 1058) { $pending.Add(("{0} ({1})" -f $Svc, $Later)); return }
            $failed.Add(("{0}: {1}" -f $Svc, $_.Exception.Message))
        }
    }
    foreach ($n in @($Names)) {
        $want = & $toScm $n
        if (-not $want) { continue }
        if ($n -eq 'CDPUserSvc') {
            # сам шаблон не запускается — запускаются его копии у пользователей
            # и ему тип запуска — диспетчеру служб всегда (см. выше): по нему заводятся новые копии
            $v = Get-SvcScmView $n
            if ($v.found) { try { Set-Service -Name $n -StartupType $want -ErrorAction Stop } catch { } }
            foreach ($inst in @((Get-GdidUserSvcInstances).names)) { & $bring $inst $want 'после выхода из Windows и нового входа' }
            continue
        }
        & $bring $n $want 'после перезагрузки'
    }
    return @{ pending = $pending.ToArray(); failed = $failed.ToArray() }
}

# Состояние для вкладки «Номер устройства». Только чтение.
function Get-GdidStatus {
    $scan = Get-GdidScan
    $copies = @($scan.copies)
    $tx = Get-GdidTransmitState
    $userLid = Get-RegValue 'HKCU:\SOFTWARE\Microsoft\IdentityCRL\ExtendedProperties' 'LID'
    $svcs = New-Object System.Collections.Generic.List[object]
    foreach ($s in @($tx.services)) { $svcs.Add($s) }
    $svcs.Add((Get-GdidSvcEntry 'wlidsvc'))
    $nums = @($copies | ForEach-Object { "$($_.puid)" } | Where-Object { $_ -match $script:DevicePuidRegex } | Select-Object -Unique)
    # Номер для плитки: свой, а если своего нет — из любого найденного хранилища.
    # Раньше брался только свой, и рядом с «Копий на диске: 3» стояло «нет».
    # По хранилищам номера отдаются отдельно — они могут различаться.
    $ids = @()
    foreach ($who in @('user', 'system', 'other')) {
        foreach ($n in @($copies | Where-Object { $_.who -eq $who -and "$($_.puid)" -match $script:DevicePuidRegex } | ForEach-Object { "$($_.puid)" } | Select-Object -Unique)) {
            $ids += @{ who = $who; gdid = (ConvertTo-Gdid $n) }
        }
    }
    $mainGdid = $(if ("$userLid") { ConvertTo-Gdid "$userLid" } elseif ($ids.Count -gt 0) { $ids[0].gdid } else { '' })
    return @{
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        gdid = $mainGdid
        gdidFrom = $(if ("$userLid") { 'user' } elseif ($ids.Count -gt 0) { $ids[0].who } else { '' })
        ids = $ids
        copies = $copies.Count; numbers = $nums.Count
        userCopies = @($copies | Where-Object { $_.who -eq 'user' }).Count
        systemCopies = @($copies | Where-Object { $_.who -eq 'system' }).Count
        otherCopies = @($copies | Where-Object { $_.who -eq 'other' }).Count
        unreadable = @($scan.unreadable).Count
        uncheckedProfiles = [int]$scan.unchecked
        # Found, NotFound или Unverified: «копий 0» при непроверенных местах — не «нет»
        scanState = $scan.state
        # Передача — одной проверкой (Get-GdidTransmitState): Off, Pending, On, Unknown
        transmitOff = [bool]$tx.off; transmitState = $tx.state; transmitPending = [bool]$tx.pending; transmitKnown = [bool]$tx.known
        transmitProblems = $tx.problems
        # Блок считается стоящим, только если он цел и в нём ровно нужный список;
        # *Present — метка блока есть (он задуман), даже если побит или устарел
        ddsBlocked = (Test-HostsBlockCurrent -Kind 'gdid'); ddsPresent = (Test-HostsBlock -Kind 'gdid')
        locked = (Test-HostsBlockCurrent -Kind 'lock'); lockPresent = (Test-HostsBlock -Kind 'lock')
        wlidBlocked = (Test-FwRule 'svc' 'wlidsvc')
        msaLogon = (Test-MsaLogon); managed = (Get-ManagedReason)
        # вид принадлежности организации (Get-GdidManagement): domain, entra,
        # hybrid, mdm, workAccount, unknown или ''; учётные записи — по людям
        managedKind = "$((Get-GdidManagement).kind)"
        workAccount = [bool](Get-GdidManagement).workAccount
        accounts = @(Get-GdidAccounts)
        profiles = $scan.profiles
        # оборванное стирание: службы, что работали до него, могут стоять
        interruptedWipe = $(try { Get-GdidWipeRecovery } catch { [ordered]@{ state = 'Unreadable'; recoveryRequired = $true; running = @(); notBack = @(); error = "$($_.Exception.Message)" } })
        unknownIdentities = @($scan.unknown).Count
        admin = (Test-Admin)
        services = $svcs.ToArray()
    }
}

# --- аудит соединений (монитор) -------------------------------------------- #
# Монитор считается включённым, когда журнал пишет и разрешённые соединения
# (5156), и отклонённые (5157). Раньше включались только отказы, и список «кто
# отправляет», который строится по разрешённым, в живой системе был пуст.
# Значение подкатегории аудита числом: 0 — нет, 1 — успех, 2 — отказ, 3 — оба;
# -1 — прочитать не удалось. Текстовый вывод auditpol переведён на язык
# Windows («Успех и сбой», «Erfolg und Fehler»), и проверка по словам на
# немецкой Windows считала бы монитор выключенным всегда. Резервная копия
# политики (/backup) пишет то же самое числом — по нему и сверяемся.
function Get-AuditSetting {
    param([string]$Guid = $script:AuditGuid)
    # auditpol пишет копию политики в файл, а читаем мы её с правами
    # администратора (T-2). Файл — только в личной рабочей папке, куда
    # обычной программе не дотянуться (New-PrivateWorkDir): защищённый корень,
    # если он уже есть, иначе своя папка в Windows\Temp. Раньше, пока корня
    # не было, файл ложился во временную папку пользователя: там его могли
    # подменить между записью и чтением, а саму папку — заменить ссылкой.
    # Места нет — политика «не прочиталась» (-1), а не прочитана откуда попало.
    $work = New-PrivateWorkDir 'w11p-audit-'
    if (-not $work) { return -1 }
    $tmp = Join-Path $work 'audit.csv'
    try {
        $since = (Get-Date).AddSeconds(-5)
        $null = & auditpol.exe /backup /file:$tmp 2>&1
        if ($LASTEXITCODE -ne 0) { return -1 }
        # В папке — ровно этот файл, обычный, свежий, свой владелец; читается
        # один раз, без права записи для других (Read-PrivateWorkFile)
        $bytes = Read-PrivateWorkFile $work 'audit.csv' $since
        if ($null -eq $bytes -or $bytes.Length -eq 0) { return -1 }
        $enc = [Text.Encoding]::Default; $skip = 0
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $enc = [Text.Encoding]::Unicode; $skip = 2 }
        elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $enc = [Text.Encoding]::UTF8; $skip = 3 }
        $text = $enc.GetString($bytes, $skip, $bytes.Length - $skip)
        # Заголовки столбцов в копии тоже бывают переведены («GUID подкатегории»,
        # «значение параметра» — проверено на русской Windows), поэтому читаем
        # по положению: порядок столбцов у /backup постоянный. Первая строка —
        # заголовок, её пропускаем.
        $lines = @($text -split "`r?`n" | Where-Object { $_ })
        $rows = @($lines | ConvertFrom-Csv -Header 'pc', 'target', 'sub', 'guid', 'inc', 'exc', 'val' | Select-Object -Skip 1)
        # ни одного GUID на своём месте — формат не тот, не гадаем
        if (@($rows | Where-Object { "$($_.guid)" -match '^\{[0-9A-Fa-f-]{36}\}$' }).Count -eq 0) { return -1 }
        foreach ($row in $rows) {
            if ("$($row.guid)" -eq $Guid) {
                # значение подкатегории — 0…3 (пусто — 0, как и раньше); другое
                # — копия не та, не гадаем
                $v = "$($row.val)".Trim()
                if ($v -eq '') { return 0 }
                if ($v -notmatch '^[0-3]$') { return -1 }
                return [int]$v
            }
        }
        return 0      # строки нет — подкатегория не настроена, а это «нет аудита»
    } catch { return -1 }
    finally { Remove-PrivateWorkDir $work }
}

function Get-MonitorEnabled {
    $v = Get-AuditSetting
    if ($v -ge 0) { return ($v -eq 3) }
    # запасной путь — по словам, как раньше
    try {
        $out = & auditpol.exe /get /subcategory:$script:AuditGuid /r 2>$null
        $csv = $out | Where-Object { $_ -and $_ -notmatch '^Machine Name' -and $_ -notmatch '^Имя компьютера' } | Select-Object -Last 1
        if (-not $csv) { return $false }
        return (($csv -match 'Success|Успех|Успешн') -and ($csv -match 'Failure|Отказ|Сбой'))
    } catch { return $false }
}

function Set-AuditSetting {
    param([string]$Guid, [int]$Value)
    $s = $(if ($Value -band 1) { 'enable' } else { 'disable' })
    $f = $(if ($Value -band 2) { 'enable' } else { 'disable' })
    $out = & auditpol.exe /set /subcategory:$Guid /success:$s /failure:$f 2>&1
    return @{ ok = ($LASTEXITCODE -eq 0); code = $LASTEXITCODE; out = (($out | ForEach-Object { "$_" }) -join ' ').Trim() }
}

# Журнал безопасности по умолчанию — 20 МБ: с записью всех соединений он
# переписывал бы себя за часы. Под монитор он растёт до 128 МБ — через журнал
# изменений, чтобы откат вернул прежний размер.
$script:SecurityLogKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Security'
$script:SecurityLogMin = 134217728

# Раньше результат auditpol не проверялся: команда могла не сработать, а
# функция всё равно говорила «включён». Теперь проверяется и код выхода, и то,
# что политика действительно стала нужной. Прежнее значение уходит в журнал
# отката — откат вернёт ровно его, а не «выключено».
function Set-MonitorEnabled {
    param([bool]$On)
    try {
        $before = Get-AuditSetting
        if (-not $On) {
            # Выключение возвращает ту политику аудита, что была до программы,
            # если программа её меняла. Раньше ставился «нет аудита» всегда, и
            # прежняя настройка (например, «только успешные») пропадала вместе
            # с нашей. Возврат — той же функцией, что и полный откат. (Сначала
            # здесь стояла Restore-ChangeKey, но она описана в файле ниже, а
            # движок выполняется сверху вниз: на живой системе её ещё не было.)
            $jf = Read-JournalFile -ReadOnly
            $ae = $null
            if ($jf.trusted) { $ae = @($jf.items | Where-Object { "$($_.kind)" -eq 'audit' -and "$($_.guid)" -eq $script:AuditGuid }) | Select-Object -First 1 }
            if ($ae -and (Test-JournalEntryShape $ae)) { $ae = $null }   # запись не по форме — не исполняется
            if ($ae) {
                $want = [int]("0" + "$($ae.old)")
                $rk = Restore-JournalEntry $ae
                if (-not $rk.ok) { Write-Log ("   [!] прежняя политика аудита не вернулась: {0}" -f $rk.error); $script:Failures++; return $false }
                if ((Get-AuditSetting) -ne $want) {
                    Write-Log '   [!] auditpol отработал, но политика аудита не та, что была до программы -- возможно, её задаёт групповая политика организации'
                    $script:Failures++; return $false
                }
                try { Remove-JournalKey (Get-JournalKey (ConvertTo-Fields $ae)) }
                catch { Write-Log ("   [!] политика аудита возвращена, но запись о ней из журнала отката не убралась: {0}" -f $_.Exception.Message); $script:Failures++ }
                Write-Log ("   [+] журнал соединений брандмауэра: политика аудита возвращена к прежней ({0})" -f (Get-AuditName "$want"))
                return $true
            }
            if ($before -eq 3) { Write-Log '   [i] программа политику аудита не меняла (или журналу нельзя верить) -- выключаем по вашей просьбе' }
        }
        if ($On -and $before -lt 0) {
            # Какой политика была, не прочиталось — значит, и вернуть её
            # потом было бы нечем. Раньше аудит включался всё равно.
            Write-Log '   [!] не удалось прочитать нынешнюю политику аудита -- включать не будем: потом её нечем было бы вернуть'
            $script:Failures++; return $false
        }
        # «Как было» — в журнал раньше изменения, как у всех остальных
        # изменений (Write-AheadEntry). Раньше запись шла после auditpol, и
        # обрыв между ними оставлял политику изменённой без пути назад.
        $ahead = $null
        if ($On -and $before -ne 3) {
            $ahead = @{ kind = 'audit'; guid = $script:AuditGuid; old = "$before"; newValue = '3' }
            if (-not (Write-AheadEntry $ahead)) {
                Write-Log '   [!] журнал отката сейчас не пишется -- политику аудита не меняем'
                $script:Failures++; return $false
            }
        }
        $r = Set-AuditSetting $script:AuditGuid $(if ($On) { 3 } else { 0 })
        $why = ''
        if (-not $r.ok) { $why = ("   [!] auditpol не изменил политику аудита (код {0}): {1}" -f $r.code, $r.out) }
        elseif ((Get-MonitorEnabled) -ne $On) { $why = '   [!] auditpol отработал, но политика аудита осталась прежней -- возможно, её задаёт групповая политика организации' }
        if ($why) {
            # политика осталась прежней — изменения не было, запись отзывается;
            # не прочиталась или стала другой — запись остаётся для отката
            if ($ahead -and (Get-AuditSetting) -eq $before) { Undo-AheadEntry $ahead }
            Write-Log $why
            $script:Failures++
            return $false
        }
        Write-Log ("   [+] журнал соединений брандмауэра: {0}" -f $(if ($On) { 'включён' } else { 'выключен' }))
        if ($On) {
            $size = Get-RegValue $script:SecurityLogKey 'MaxSize'
            if ($null -eq $size -or [long]$size -lt $script:SecurityLogMin) {
                Set-Reg -Path $script:SecurityLogKey -Name 'MaxSize' -Value $script:SecurityLogMin -Type 'DWord' -Comment 'журнал безопасности — 128 МБ, чтобы монитор не вытеснял другие записи'
                Save-JournalEntries -Quiet
            }
        }
        return $true
    } catch { Write-Log "   [!] auditpol: $($_.Exception.Message)"; return $false }
}

# --------------------------------------------------------------------------- #
#  Новые программы в сети. Разрешённые исходящие соединения (5156) берутся из
#  журнала аудита брандмауэра, программа сравнивается со списком известных.
#  Первый час после включения — обучение: всё, что выходит в сеть, считается
#  своим, иначе первое же уведомление перечислило бы полсистемы.
# --------------------------------------------------------------------------- #
$script:NetTask = 'Win11Privacy Network'

function Get-NetAppKey {
    param([string]$Raw)
    $p = ConvertFrom-DevicePath $Raw
    if (-not $p) { $p = $Raw }
    return $p.ToLowerInvariant()
}

# Чтение журнала безопасности: «событий нет» и «журнал не читается» — разные
# вещи. Раньше любая ошибка давала пустой список, и монитор показывал «никто
# ничего не отправлял», когда на деле не мог прочитать журнал.
function Read-SecurityEvents {
    param([int[]]$Ids, [datetime]$Since, [int]$Max, [string]$LogName = 'Security')
    try {
        $ev = @(Get-WinEvent -FilterHashtable @{ LogName = $LogName; Id = $Ids; StartTime = $Since } -MaxEvents $Max -ErrorAction Stop)
        return @{ events = $ev; error = '' }
    } catch {
        if ("$($_.FullyQualifiedErrorId)" -like 'NoMatchingEventsFound*') { return @{ events = @(); error = '' } }
        return @{ events = @(); error = "$($_.Exception.Message)" }
    }
}

function Get-NetAppsSince {
    param([datetime]$Since, [int]$Max = 20000)
    $apps = @{}
    $rd = Read-SecurityEvents -Ids 5156 -Since $Since -Max $Max
    $events = @($rd.events)
    # ошибку чтения видит тот, кто вызвал: слежение, его установка, монитор
    $script:NetReadError = $rd.error
    foreach ($ev in $events) {
        try {
            $x = [xml]$ev.ToXml()
            $data = @{}
            foreach ($n in $x.Event.EventData.Data) { $data[[string]$n.Name] = [string]$n.'#text' }
            if ($data['Direction'] -ne '%%14593') { continue }              # только исходящие
            if (-not (Test-PublicIp $data['DestAddress'])) { continue }
            $raw = [string]$data['Application']
            if (-not $raw) { continue }
            $key = Get-NetAppKey $raw
            if ($apps.ContainsKey($key)) { $apps[$key].count++; continue }
            $apps[$key] = @{ key = $key; name = ($raw -split '\\')[-1]; path = (ConvertFrom-DevicePath $raw); count = 1
                             ip = $data['DestAddress']; time = $ev.TimeCreated.ToString('yyyy-MM-dd HH:mm') }
        } catch { }
    }
    return $apps
}

function Invoke-NetGuard {
    param([switch]$Quiet)
    $state = Load-Json 'net-apps.json'
    $known = @{}
    if ($state -and $state.known) { foreach ($k in @($state.known)) { $known["$k"] = $true } }
    $recent = New-Object System.Collections.Generic.List[object]
    if ($state -and $state.recent) { foreach ($r in @($state.recent)) { $recent.Add($r) } }
    $learnUntil = $(if ($state -and $state.learnUntil) { [datetime]$state.learnUntil } else { (Get-Date).AddHours(1) })
    $since = $(if ($state -and $state.last) { ([datetime]$state.last).AddMinutes(-1) } else { (Get-Date).AddMinutes(-20) })
    $now = Get-Date
    $fresh = @()
    foreach ($a in @((Get-NetAppsSince -Since $since).Values)) {
        if ($known.ContainsKey($a.key)) { continue }
        $known[$a.key] = $true
        if ($now -lt $learnUntil) { continue }                              # обучение: молча запоминаем
        $fresh += $a
        $recent.Insert(0, @{ name = $a.name; path = $a.path; time = $a.time; ip = $a.ip })
    }
    while ($recent.Count -gt 30) { $recent.RemoveAt($recent.Count - 1) }
    # Журнал не прочитался — отметку «проверено до» не двигаем, иначе эти
    # минуты выпали бы из слежения навсегда; а ошибку запоминаем для монитора.
    $err = "$script:NetReadError"
    # и при самом первом запуске: отметки ещё нет — остаётся начало окна, а не «сейчас»
    $last = $(if ($err) { if ($state -and $state.last) { "$($state.last)" } else { $since.ToString('s') } } else { $now.ToString('s') })
    Save-Json 'net-apps.json' @{ known = @($known.Keys); recent = $recent.ToArray(); learnUntil = $learnUntil.ToString('s'); last = $last
                                 readError = $err; readErrorTime = $(if ($err) { $now.ToString('yyyy-MM-dd HH:mm') } else { '' }) }
    if ($fresh.Count -gt 0 -and -not $Quiet) {
        $msg = (@($fresh | Select-Object -First 3 | ForEach-Object { $_.name }) -join ', ')
        if ($fresh.Count -gt 3) { $msg += (' и ещё ' + ($fresh.Count - 3)) }
        Show-Toast 'Новая программа вышла в сеть' ($msg + '. Запретить ей выход — на странице «Монитор».')
    }
    return $fresh
}

# Публичный ли адрес — по диапазонам, а не по началу строки. Прежние шаблоны
# считали публичными общие адреса провайдеров (100.64.0.0/10, за ними сидят
# целые районы), тестовые и зарезервированные сети (198.18.0.0/15,
# 240.0.0.0/4), многоадресные IPv6 вне ff0x, адрес IPv4 внутри IPv6
# (::ffff:10.0.0.1) — и вообще любую строку, даже не адрес. От этого зависят
# наблюдение за сетью и проверка утечек: частный адрес в отчёте — ложная тревога.
function Test-PublicIp {
    param([string]$Ip)
    if (-not $Ip) { return $false }
    $s = $Ip.Trim()
    # события журнала повторяют одни и те же адреса тысячами
    if ($null -eq $script:PublicIpSeen) { $script:PublicIpSeen = @{} }
    if ($script:PublicIpSeen.ContainsKey($s)) { return $script:PublicIpSeen[$s] }
    $res = $false
    $parsed = $null
    # TryParse принимает и «1.2.3», и «0x7f.1» — адрес IPv4 только из четырёх чисел
    if ([System.Net.IPAddress]::TryParse($s, [ref]$parsed) -and
        ($parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or $s -match '^\d{1,3}(\.\d{1,3}){3}$')) {
        $res = Test-PublicIpAddress $parsed
    }
    if ($script:PublicIpSeen.Count -lt 50000) { $script:PublicIpSeen[$s] = $res }
    return $res
}

function Test-PublicIpAddress {
    param([System.Net.IPAddress]$A)
    $addr = $A
    if ($addr.IsIPv4MappedToIPv6) { $addr = $addr.MapToIPv4() }
    if ($null -eq $script:NonPublicNets) {
        # особые сети из реестров IANA, которые в интернет не выходят
        $script:NonPublicNets = @(foreach ($n in @(
                '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16', '172.16.0.0/12',
                '192.0.0.0/24', '192.0.2.0/24', '192.88.99.0/24', '192.168.0.0/16', '198.18.0.0/15',
                '198.51.100.0/24', '203.0.113.0/24', '224.0.0.0/4', '240.0.0.0/4',
                '::/128', '::1/128', '64:ff9b:1::/48', '100::/64', '2001:db8::/32',
                'fc00::/7', 'fe80::/10', 'fec0::/10', 'ff00::/8')) {
            $p = $n.Split('/')
            @{ b = [System.Net.IPAddress]::Parse($p[0]).GetAddressBytes(); len = [int]$p[1] }
        })
    }
    $b = $addr.GetAddressBytes()
    foreach ($net in $script:NonPublicNets) {
        if ($net.b.Length -ne $b.Length) { continue }
        $full = [int][math]::Floor($net.len / 8); $rest = $net.len % 8; $in = $true
        for ($i = 0; $i -lt $full; $i++) { if ($b[$i] -ne $net.b[$i]) { $in = $false; break } }
        if ($in -and $rest -gt 0) {
            $mask = (0xFF -shl (8 - $rest)) -band 0xFF
            if (($b[$full] -band $mask) -ne ($net.b[$full] -band $mask)) { $in = $false }
        }
        if ($in) { return $false }
    }
    return $true
}

# Журнал брандмауэра называет программу путём ядра: \device\harddiskvolume4\...
# Правилу брандмауэра нужен обычный путь с буквой диска — подбираем её перебором.
function ConvertFrom-DevicePath {
    param([string]$P)
    if (-not $P) { return '' }
    if ($P -match '^[A-Za-z]:\\') { return $P }
    $m = [regex]::Match($P, '^\\device\\harddiskvolume\d+\\(.+)$', 'IgnoreCase')
    if (-not $m.Success) { return '' }
    $rest = $m.Groups[1].Value
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        try {
            if (-not $d.IsReady -or $d.DriveType -ne 'Fixed') { continue }
            $cand = Join-Path $d.Name $rest
            if (Test-Path -LiteralPath $cand) { return $cand }
        } catch { }
    }
    return ''
}

function Get-MonitorStats {
    param([int]$Hours)
    $since = (Get-Date).AddHours(-$Hours)
    $events = @()
    # 5156 — брандмауэр РАЗРЕШИЛ соединение, 5157 — заблокировал. Раньше читались
    # только 5157, поэтому «кто отправляет» показывал одни отказы, а настоящие
    # исходящие соединения в список не попадали вовсе.
    $rd = Read-SecurityEvents -Ids @(5156, 5157) -Since $since -Max 8000
    $events = @($rd.events)
    $dns = @{}
    try { Get-DnsClientCache -ErrorAction SilentlyContinue | ForEach-Object { if ($_.Data -and -not $dns.ContainsKey($_.Data)) { $dns[$_.Data] = $_.Entry } } } catch { }
    $byProc = @{}; $byDest = @{}; $total = 0; $telemetryHits = 0; $blockedTotal = 0
    foreach ($ev in $events) {
        try {
            $x = [xml]$ev.ToXml()
            $data = @{}
            foreach ($n in $x.Event.EventData.Data) { $data[[string]$n.Name] = [string]$n.'#text' }
            if ($data['Direction'] -ne '%%14593') { continue }          # только исходящие
            $ip = $data['DestAddress']
            if (-not (Test-PublicIp $ip)) { continue }
            if ($ev.Id -eq 5157) { $blockedTotal++; continue }          # отказы считаем отдельно
            $full = [string]$data['Application']
            $app = if ($full) { ($full -split '\\')[-1] } else { '?' }
            $total++
            if ($byProc.ContainsKey($app)) { $byProc[$app].count++ } else {
                $byProc[$app] = @{ name=$app; count=1; raw=$full }
            }
            $key = $ip
            if ($byDest.ContainsKey($key)) { $byDest[$key].count++ } else {
                $dom = if ($dns.ContainsKey($ip)) { $dns[$ip] } else { '' }
                $byDest[$key] = @{ ip=$ip; domain=$dom; count=1; port=$data['DestPort'] }
            }
            if ($byDest[$key].domain -match $script:TelemetryDnsRegex) { $telemetryHits++ }
        } catch { }
    }
    # путь и состояние запрета выясняем только для тех, кого покажем
    $procList = @()
    foreach ($p in @($byProc.Values | Sort-Object { $_.count } -Descending | Select-Object -First 12)) {
        $path = ConvertFrom-DevicePath ([string]$p.raw)
        $procList += @{ name = $p.name; count = $p.count; path = $path
                        blocked = [bool]($path -and (Test-FwRule 'app' $path)) }
    }
    $destList = @($byDest.Values | Sort-Object { $_.count } -Descending | Select-Object -First 25)
    # впервые вышедшие в сеть — из записей слежения за сетью
    $newList = @()
    $ns = Load-Json 'net-apps.json'
    if ($ns -and $ns.recent) {
        foreach ($r in @($ns.recent | Select-Object -First 12)) {
            $newList += @{ name = "$($r.name)"; path = "$($r.path)"; time = "$($r.time)"; ip = "$($r.ip)"
                           blocked = [bool]("$($r.path)" -and (Test-FwRule 'app' "$($r.path)")) }
        }
    }
    return @{ enabled=(Get-MonitorEnabled); hours=$Hours; since=$since.ToString('yyyy-MM-dd HH:mm'); total=$total;
              telemetryHits=$telemetryHits; events=$events.Count; blocked=$blockedTotal
              byProcess=$procList; byDest=$destList; newApps=$newList
              netGuard=[bool](Get-ScheduledTask -TaskName $script:NetTask -ErrorAction SilentlyContinue)
              readError=$rd.error
              netGuardError=$(if ($ns -and $ns.readError) { "{0} ({1})" -f $ns.readError, $ns.readErrorTime } else { '' })
              firewallRules=@(Get-NetFirewallRule -Group $script:FwGroup -ErrorAction SilentlyContinue).Count }
}

# --- DNS-кэш: свидетельства обращений -------------------------------------- #
function Get-DnsEvidence {
    $list = @()
    try {
        $seen = @{}
        foreach ($r in (Get-DnsClientCache -ErrorAction SilentlyContinue)) {
            if ($r.Entry -match $script:TelemetryDnsRegex -and -not $seen.ContainsKey($r.Entry)) {
                $seen[$r.Entry] = $true
                $blocked = ($r.Data -eq '0.0.0.0' -or $r.Data -eq '::')
                $list += @{ name=$r.Entry; data=[string]$r.Data; blocked=$blocked }
            }
        }
    } catch { }
    return $list
}

# --- буфер телеметрии ------------------------------------------------------- #
# Что считается неотправленной телеметрией: очередь событий (EventStore.db и
# его журналы; у приложений — свой в TenantStorage), старые очереди *.rbs и
# трассировки *.etl. Скачанные настройки и папки не трогаем.
# ВАЖНО: в PowerShell 5.1 -Include вместе с -LiteralPath молча не работает.
# Раньше сюда попадало всё содержимое папки, включая сами папки: удалялись
# и настройки, а Remove-Item на непустой папке задавал вопрос «удалить с
# содержимым?» и без окна (файл «Для других ПК») ждал ответа вечно.
$script:BufferFileRx = '\.(rbs|etl)$|^EventStore\.db(-wal|-shm)?$'
function Get-BufferFiles {
    param([switch]$Strict)
    $ea = $(if ($Strict) { 'Stop' } else { 'SilentlyContinue' })
    return @(Get-ChildItem -LiteralPath $script:DiagDir -Recurse -Force -File -ErrorAction $ea |
             Where-Object { $_.Name -match $script:BufferFileRx })
}

function Get-BufferInfo {
    $size = -1; $files = 0
    try {
        $items = @(Get-BufferFiles -Strict)
        $files = $items.Count
        $sum = ($items | Measure-Object -Property Length -Sum).Sum
        $size = if ($sum) { [math]::Round($sum / 1MB, 2) } else { 0 }
    } catch { $size = -1 }
    return @{ mb=$size; files=$files; path=$script:DiagDir }
}

# Раньше перед удалением программа забирала себе всю системную папку
# Diagnosis (takeown /R) и давала администраторам полный доступ ко всему
# внутри (icacls /T) — и так это и оставалось: исходные владелец и права
# папки, которой распоряжается служба телеметрии, не возвращались. Теперь
# права не трогаются вовсе. Что администратор удалить может, удаляется
# сразу; остальное удаляет короткая задача от имени системы, у которой
# доступ к этой папке и так есть. Итог проверяется: что осталось, сказано.
$script:DiagDirExpected = Join-Path $env:ProgramData 'Microsoft\Diagnosis'

# Что делает задача от имени системы: удаляет те же файлы, что
# Get-BufferFiles, и пишет итог в файл — сколько нашла, удалила, не смогла
# удалить и сколько осталось, а если папку не прочитала — почему. Код
# завершения задачи сам по себе ничего не доказывает: прежняя проверка через
# dir при ошибке доступа выглядела бы как «файлов не осталось».
function Get-BufferSystemScript {
    param([string]$Dir, [string]$ResultFile)
    $q = { param($s) "'" + ("$s" -replace "'", "''") + "'" }
    return (@(
        "`$ErrorActionPreference = 'Stop'"
        ("`$d = {0}; `$rx = {1}; `$out = {2}" -f (& $q $Dir), (& $q $script:BufferFileRx), (& $q $ResultFile))
        "`$res = @{ found = 0; deleted = 0; failed = 0; left = -1; listError = ''; errors = @() }"
        "try { `$fs = @(Get-ChildItem -LiteralPath `$d -Recurse -Force -File | Where-Object { `$_.Name -match `$rx }) } catch { `$fs = @(); `$res.listError = `"`$(`$_.Exception.Message)`" }"
        "`$res.found = `$fs.Count"
        # какие файлы не удалились и почему — только имя, без пути, и не больше десяти
        "foreach (`$f in `$fs) { try { Remove-Item -LiteralPath `$f.FullName -Force -ErrorAction Stop; `$res.deleted++ } catch { `$res.failed++; if (`$res.errors.Count -lt 10) { `$res.errors += @{ file = `$f.Name; error = `"`$(`$_.Exception.Message)`" } } } }"
        "if (-not `$res.listError) { try { `$res.left = @(Get-ChildItem -LiteralPath `$d -Recurse -Force -File | Where-Object { `$_.Name -match `$rx }).Count } catch { `$res.listError = `"`$(`$_.Exception.Message)`" } }"
        "Set-Content -LiteralPath `$out -Value (`$res | ConvertTo-Json -Compress -Depth 4) -Encoding UTF8"
        "if (`$res.left -eq 0 -and -not `$res.listError) { exit 0 } else { exit 1 }"
    ) -join "`r`n")
}

# Задача от имени системы и её итог: success — файлов не осталось; partial —
# часть удалена, часть осталась; failed — не удалила ничего, папку не
# прочитала или итога не оставила. Итог кладётся в защищённую папку
# программы: писать туда могут только система и администраторы.
function Invoke-BufferSystemPurge {
    param([string]$Dir)
    if (-not (Assert-SafeRoot)) { return @{ status = 'failed'; found = 0; deleted = 0; failed = 0; left = -1; why = 'папка ProgramData\Win11Privacy не защищена — итогу задачи там не место' } }
    # Сценарий кладётся файлом в ту же защищённую папку: подменить его до
    # запуска может только администратор, а аргументы задачи остаются короткими
    # (раньше весь сценарий шёл в них строкой на две с половиной тысячи знаков).
    $id = [guid]::NewGuid().ToString('N')
    $rf = Join-Path $script:SafeRoot ('buffer-result-' + $id + '.json')
    $sf = Join-Path $script:SafeRoot ('buffer-purge-' + $id + '.ps1')
    $res = $null
    try {
        Set-Content -LiteralPath $sf -Value (Get-BufferSystemScript $Dir $rf) -Encoding UTF8 -ErrorAction Stop
        $null = Invoke-OneShotTask 'Win11Privacy buffer' -Execute $script:PsExe -Arguments ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $sf + '"') -AsSystem -Minutes 5
        if (Test-Path -LiteralPath $rf) { $res = Get-Content -LiteralPath $rf -Raw -Encoding UTF8 | ConvertFrom-Json }
    } catch { $res = $null }
    finally { Remove-Item -LiteralPath $rf, $sf -Force -ErrorAction SilentlyContinue }
    if (-not $res) { return @{ status = 'failed'; found = 0; deleted = 0; failed = 0; left = -1; why = 'задача от имени системы не оставила итога' } }
    $left = [int]$res.left
    $st = $(if ("$($res.listError)" -or $left -lt 0) { 'failed' } elseif ($left -eq 0) { 'success' } elseif ([int]$res.deleted -gt 0) { 'partial' } else { 'failed' })
    $errs = @(@($res.errors) | Where-Object { $_ } | ForEach-Object { @{ file = "$($_.file)"; error = "$($_.error)" } })
    return @{ status = $st; found = [int]$res.found; deleted = [int]$res.deleted; failed = [int]$res.failed; left = $left; why = "$($res.listError)"; errors = $errs }
}

function Purge-Buffer {
    Write-Section 'Неотправленная телеметрия'
    # чистится только эта папка: путь сверяется, а не берётся на веру
    $dir = [IO.Path]::GetFullPath($script:DiagDir).TrimEnd('\')
    if ($dir -ne [IO.Path]::GetFullPath($script:DiagDirExpected).TrimEnd('\')) {
        Write-Log ("   [!] папка буфера не та, что ожидалась ({0}) -- ничего не удалено" -f $dir); $script:Failures++; return
    }
    $info = Get-BufferInfo
    if ($info.mb -eq 0 -and $info.files -eq 0) { Write-Log '   [-] буфер пуст'; return }
    if ($DryRun) { Write-Log ("   [тест] будет стёрто ~{0} МБ ({1} файлов)" -f $info.mb, $info.files); return }
    $svc = Get-Service -Name DiagTrack -ErrorAction SilentlyContinue
    $wasRunning = ($svc -and $svc.Status -eq 'Running')
    if ($wasRunning) { Stop-Service -Name DiagTrack -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 800 }
    # Сначала — с правами администратора. Чего он удалить не может, тех
    # файлов не перечисляем по одному как ошибки: их следом удаляет система,
    # и итог говорится один раз, ниже.
    $denied = 0
    foreach ($f in @(Get-BufferFiles)) {
        try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop } catch { $denied++ }
    }
    $sys = $null
    if ($info.mb -lt 0 -or @(Get-BufferFiles).Count -gt 0) {
        if ($denied -gt 0) { Write-Log ("   [i] файлов, которые администратору не отдали: {0} -- их удаляет задача от имени системы" -f $denied) }
        else { Write-Log '   [i] папку буфера администратору не дали даже просмотреть -- её очищает задача от имени системы' }
        $sys = Invoke-BufferSystemPurge $dir
    }
    if ($wasRunning -and $svc.StartType -ne 'Disabled') { Start-Service -Name DiagTrack -ErrorAction SilentlyContinue }
    $after = Get-BufferInfo
    if ($after.mb -ge 0 -and $info.mb -ge 0) {
        # папку видно — итог считаем сами, а не со слов задачи
        $gone = $info.files - $after.files
        if ($gone -gt 0) { Write-Log ("   [+] стёрто файлов: {0}, {1} МБ" -f $gone, [math]::Round([math]::Max(0, $info.mb - $after.mb), 2)); $script:Changes++ }
        if ($after.files -gt 0) { Write-Log ("   [!] осталось файлов: {0} -- Windows их держит; после перезагрузки можно повторить" -f $after.files); $script:Failures++ }
    } elseif ($sys) {
        switch ($sys.status) {
            'success' { Write-Log ("   [+] буфер очищен от имени системы: удалено файлов {0}, не осталось ни одного" -f $sys.deleted); $script:Changes++ }
            'partial' { Write-Log ("   [!] от имени системы удалено файлов {0}, осталось {1} -- Windows их держит" -f $sys.deleted, $sys.left); $script:Failures++ }
            default   { Write-Log ("   [!] очистить буфер от имени системы не удалось: {0}" -f $(if ($sys.why) { $sys.why } else { "удалено {0} из {1}, осталось {2}" -f $sys.deleted, $sys.found, $sys.left })); $script:Failures++ }
        }
    } else {
        Write-Log '   [!] очистить буфер не удалось или проверить это нечем (нет доступа)'; $script:Failures++
    }
    # что именно не удалилось у системы и почему — для разбора на разных сборках
    if ($sys -and @($sys.errors).Count -gt 0) {
        foreach ($e in @(@($sys.errors) | Select-Object -First 3)) { Write-Log ("       {0}: {1}" -f $e.file, $e.error) }
    }
}

# =========================================================================== #
#  Detect
# =========================================================================== #
if ($Detect) {
    $ed = Get-Edition
    $os = Get-CimInstance Win32_OperatingSystem
    $apps = Detect-Apps
    $oem = Detect-Oem
    $guardTask = Get-ScheduledTask -TaskName $script:GuardTask -ErrorAction SilentlyContinue
    $guardLast = Load-Json 'guard-last.json'
    $guardProfile = Load-Json 'profile.json'
    $result = @{
        os = $os.Caption; build = [System.Environment]::OSVersion.Version.Build; edition = $ed.id; editionKind = $ed.kind
        admin = (Test-Admin); user = $env:USERNAME
        engineVersion = $script:EngineVersion; languageMode = $script:LangMode
        apps = $apps; oem = $oem
        guardInstalled = [bool]$guardTask
        watcherInstalled = [bool](Get-ScheduledTask -TaskName 'Win11Privacy Watcher' -ErrorAction SilentlyContinue)
        sensorGuardInstalled = [bool](Get-ScheduledTask -TaskName $script:SensorTask -ErrorAction SilentlyContinue)
        netGuardInstalled = [bool](Get-ScheduledTask -TaskName $script:NetTask -ErrorAction SilentlyContinue)
        guardLast = $guardLast
        guardModules = $(if ($guardProfile) { @($guardProfile.modules) } else { @() })
        monitorEnabled = (Get-MonitorEnabled)
        firewallRules = @(Get-NetFirewallRule -Group $script:FwGroup -ErrorAction SilentlyContinue).Count
        hostsBlocked = (Test-HostsBlock)
        buffer = (Get-BufferInfo)
        diagTrack = $(try { [string](Get-Service DiagTrack -ErrorAction Stop).StartType } catch { 'нет' })
    }
    Emit-Json $result
    exit 0
}

# =========================================================================== #
#  Monitor
# =========================================================================== #
if ($Monitor) {
    if (-not (Test-Admin)) { Emit-Json @{ error='нужны права администратора' }; exit 1 }
    Emit-Json (Get-MonitorStats -Hours $MonitorHours)
    exit 0
}

# --------------------------------------------------------------------------- #
#  Запрет выхода в сеть отдельной программе. Видно, кто стучится, — и тут же
#  можно закрыть ему выход. Правило попадает в группу Win11Privacy, поэтому
#  общий откат снимает его вместе с остальными.
# --------------------------------------------------------------------------- #
if ($BlockApp -or $UnblockApp) {
    if (-not (Test-Admin)) { Emit-Json @{ error='нужны права администратора' }; Write-Log '###DONE###'; exit 1 }
    if (-not $AppPath) { Emit-Json @{ error='не указана программа' }; Write-Log '###DONE###'; exit 1 }
    Write-Section $(if ($BlockApp) { 'Запрет выхода в сеть' } else { 'Возврат доступа в сеть' })
    $leaf = Split-Path $AppPath -Leaf
    if ($BlockApp) {
        if (-not (Test-Path -LiteralPath $AppPath)) { Write-Log ("   [!] файл не найден: {0}" -f $AppPath) }
        Apply-FwRule 'app' $AppPath ("выход в сеть запрещён: " + $leaf)
    } else {
        $rule = Get-FwRuleName 'app' $AppPath
        try {
            Remove-NetFirewallRule -DisplayName $rule -ErrorAction Stop
            Write-Log ("   [+] выход в сеть разрешён обратно: {0}" -f $leaf); $script:Changes++
        } catch { Write-Log ("   [-] запрета и не было: {0}" -f $leaf) }
    }
    Emit-Json @{ path = $AppPath; blocked = (Test-FwRule 'app' $AppPath) }
    Write-Log '###DONE###'
    exit 0
}

if ($EnableMonitor) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Монитор утечек'
    foreach ($d in $script:Defs) { if ($d.M -eq 'firewall') { Apply-Def $d } }
    $ok = Set-MonitorEnabled $true
    if (-not $ok) { Write-Log 'Наблюдение за сетью не включилось -- причина выше.'; Write-Log '###DONE###'; exit 1 }
    Write-Log 'Перехваченные попытки отправки теперь считаются. Статистика — на странице «Монитор».'
    Write-Log '###DONE###'
    exit $(if ($ok) { 0 } else { 1 })
}

if ($DisableMonitor) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Монитор утечек'
    $ok = Set-MonitorEnabled $false
    if (-not $ok) { Write-Log 'Наблюдение за сетью не выключилось -- причина выше.'; Write-Log '###DONE###'; exit 1 }
    Write-Log 'Правила брандмауэра оставлены (они — часть модуля «Брандмауэр»); удалить их можно через «Откат».'
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  Guard (страж)
# =========================================================================== #
function Show-Toast {
    param([string]$Title, [string]$Message)
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        $t = [System.Security.SecurityElement]::Escape($Title); $m = [System.Security.SecurityElement]::Escape($Message)
        $xml = "<toast><visual><binding template='ToastGeneric'><text>$t</text><text>$m</text></binding></visual></toast>"
        $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $doc.LoadXml($xml)
        $toast = New-Object Windows.UI.Notifications.ToastNotification $doc
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
    } catch { }
}

function Get-RecentHotfixes {
    param([datetime]$Since)
    $list = @()
    try {
        foreach ($h in (Get-HotFix -ErrorAction SilentlyContinue)) {
            if ($h.InstalledOn -and $h.InstalledOn -ge $Since.Date) { $list += [string]$h.HotFixID }
        }
    } catch { }
    return @($list | Select-Object -Unique)
}

# =========================================================================== #
#  АВТОЗАГРУЗКА
#  Что стартует вместе с Windows: обновляторы, агенты телеметрии, помощники
#  производителя. Отключение делается ровно так же, как в диспетчере задач —
#  отметкой в StartupApproved, а не удалением записи: включить обратно можно
#  одной кнопкой, и Windows после обновления ничего не «чинит» обратно.
# =========================================================================== #
$script:StartupRuns = @(
    @{ id = 'HKLM'
       run = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
       ok  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
       scope = 'реестр, все пользователи' },
    @{ id = 'HKLM32'
       run = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run'
       ok  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
       scope = 'реестр, все пользователи' },
    @{ id = 'HKCU'
       run = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
       ok  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
       scope = 'реестр, этот пользователь' },
    @{ id = 'HKCU32'
       run = 'HKCU:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run'
       ok  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
       scope = 'реестр, этот пользователь' }
)
$script:StartupFolders = @(
    @{ id = 'user';   folder = [Environment]::GetFolderPath('Startup')
       ok = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
       scope = 'папка автозагрузки, этот пользователь' },
    @{ id = 'common'; folder = [Environment]::GetFolderPath('CommonStartup')
       ok = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
       scope = 'папка автозагрузки, все пользователи' }
)

# Кого узнаём в лицо: зачем эта запись здесь и стоит ли её гасить.
$script:StartupKnown = @(
    @{ re = 'googleupdate|google update|gupdate|chromeautolaunch'; note = 'обновлятор Google: работает постоянно и шлёт статистику' },
    @{ re = 'edgeupdate|microsoftedgeautolaunch|msedgeautolaunch';  note = 'автозапуск и обновлятор Edge' },
    @{ re = 'adobeaamupdater|adobegcinvoker|adobe arm|acrotray|creative cloud'; note = 'служба обновлений Adobe' },
    @{ re = 'nvbackend|nvidia (web helper|geforce)|nvtmmon|nvnodelauncher'; note = 'спутник драйвера NVIDIA: телеметрия и вход в аккаунт' },
    @{ re = 'onedrive'; note = 'OneDrive: синхронизация в облако' },
    @{ re = 'teams|skype'; note = 'мессенджер Microsoft: висит в фоне ради уведомлений' },
    @{ re = 'spotify|steam|epicgames|discord|telegram|whatsapp|viber'; note = 'программа сама себя запускает при входе' },
    @{ re = 'dropbox|yandex\.?disk|mail\.?ru|cloud@mail|amigo|guard\.?mail'; note = 'облако или спутник, который стартует без спроса' },
    @{ re = 'jusched|java update|itunes|applesyncnotifier|quicktime|bonjour'; note = 'проверка обновлений в фоне' },
    @{ re = 'ccleaner|driver ?booster|advanced ?systemcare|iobit|wondershare|reimage'; note = 'фоновый «оптимизатор» с рекламой платной версии' },
    @{ re = 'honor|huawei|pcmanager|lenovo|vantage|hpnotifications|hp support|dellsupport|asus|armoury|acer ?care|msi ?center'; note = 'программа производителя: собирает сведения о ноутбуке' },
    @{ re = 'teamviewer|anydesk|rustdesk|radmin'; note = 'удалённый доступ: ждёт подключения при каждом входе' },
    @{ re = 'utorrent|bittorrent|qbittorrent'; note = 'торрент-клиент стартует вместе с Windows' },
    @{ re = 'cortana|copilot|widgets'; note = 'помощник Microsoft' }
)
# Эти лучше не гасить: тачпад, звук, хоткеи и защита. Пометим и не предложим.
$script:StartupKeepRe = 'securityhealth|windowsdefender|msmpeng|syntpenh|etdctrl|elan|touchpad|hotkey|hcontrol|atkosd|onekey|smartaudio|rtkaud|rthdvcpl|realtek|waves|nahimic|igfxtray|hkcmd|iastoricon|dptf|synaptics|logi(options|tune)|kbd'

# Опознавательный код записи. Имена значений в Run бывают с пробелами и
# запятыми, поэтому в командную строку идёт base64 — но без «+», «/» и «-»,
# чтобы PowerShell не принял код за имя параметра.
function ConvertTo-StartupId {
    param([string]$Raw)
    $b = [Text.Encoding]::UTF8.GetBytes($Raw)
    return ([Convert]::ToBase64String($b)).Replace('+', '.').Replace('/', '_').TrimEnd('=')
}
function ConvertFrom-StartupId {
    param([string]$Id)
    $s = ([string]$Id).Replace('.', '+').Replace('_', '/')
    while (($s.Length % 4) -ne 0) { $s += '=' }
    try { return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s)) } catch { return '' }
}

# В StartupApproved первый байт: чётный — запись работает, нечётный — погашена.
function Test-StartupApproved {
    param([string]$Key, [string]$Name)
    $v = Get-RegValue $Key $Name
    if ($null -eq $v) { return $true }
    try {
        $bytes = [byte[]]$v
        if ($bytes.Length -lt 1) { return $true }
        return (($bytes[0] -band 1) -eq 0)
    } catch { return $true }
}

function Set-StartupApproved {
    param([string]$Key, [string]$Name, [bool]$Enabled)
    $bytes = New-Object byte[] 12
    if ($Enabled) { $bytes[0] = 2 }
    else {
        $bytes[0] = 3
        $ft = [BitConverter]::GetBytes((Get-Date).ToFileTime())
        [Array]::Copy($ft, 0, $bytes, 4, 8)
    }
    if (-not (Test-Path -LiteralPath $Key)) { New-Item -Path $Key -Force -ErrorAction Stop | Out-Null }
    New-ItemProperty -LiteralPath $Key -Name $Name -Value $bytes -PropertyType Binary -Force -ErrorAction Stop | Out-Null
}

function Get-StartupExe {
    param([string]$Cmd)
    if (-not $Cmd) { return '' }
    $c = ([string]$Cmd).Trim()
    if ($c.StartsWith('"')) {
        $i = $c.IndexOf('"', 1)
        if ($i -gt 1) { return $c.Substring(1, $i - 1) }
        return $c.Trim('"')
    }
    $m = [regex]::Match($c, '^(.+?\.(exe|com|bat|cmd|scr))(\s|$)', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    $sp = $c.IndexOf(' ')
    if ($sp -gt 0) { return $c.Substring(0, $sp) }
    return $c
}

function Get-StartupPublisher {
    param([string]$Exe)
    if (-not $Exe) { return '' }
    try {
        $p = [Environment]::ExpandEnvironmentVariables($Exe)
        if (-not (Test-Path -LiteralPath $p)) { return '' }
        $vi = [Diagnostics.FileVersionInfo]::GetVersionInfo($p)
        $c = [string]$vi.CompanyName
        return $c.Trim()
    } catch { return '' }
}

function Get-StartupNote {
    param([string]$Name, [string]$Cmd)
    $hay = ("$Name $Cmd").ToLowerInvariant()
    foreach ($k in $script:StartupKnown) { if ($hay -match $k.re) { return $k.note } }
    return ''
}
function Test-StartupKeep {
    param([string]$Name, [string]$Cmd)
    return (("$Name $Cmd").ToLowerInvariant() -match $script:StartupKeepRe)
}

function New-StartupItem {
    param([string]$Raw, [string]$Name, [string]$Cmd, [string]$Scope, [string]$Kind, [bool]$Enabled)
    $exe  = Get-StartupExe $Cmd
    $note = Get-StartupNote $Name $Cmd
    $keep = Test-StartupKeep $Name $Cmd
    return @{
        id        = (ConvertTo-StartupId $Raw)
        name      = $Name
        cmd       = $Cmd
        exe       = $exe
        source    = $Scope
        kind      = $Kind
        enabled   = [bool]$Enabled
        publisher = (Get-StartupPublisher $exe)
        note      = $note
        keep      = [bool]$keep
        advise    = [bool]($note -and -not $keep)
    }
}

function Get-StartupList {
    $list = @()

    foreach ($src in $script:StartupRuns) {
        $props = $null
        try { $props = Get-ItemProperty -LiteralPath $src.run -ErrorAction Stop } catch { }
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -in @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) { continue }
            $cmd = [string]$p.Value
            if (-not $cmd) { continue }
            $on = Test-StartupApproved $src.ok $p.Name
            $list += (New-StartupItem ('run|' + $src.id + '|' + $p.Name) $p.Name $cmd $src.scope 'run' $on)
        }
    }

    foreach ($src in $script:StartupFolders) {
        if (-not $src.folder -or -not (Test-Path -LiteralPath $src.folder)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $src.folder -File -Force -ErrorAction SilentlyContinue)) {
            if ($f.Name -eq 'desktop.ini') { continue }
            $target = $f.FullName
            if ($f.Extension -eq '.lnk') {
                try {
                    $sh = New-Object -ComObject WScript.Shell
                    $lnk = $sh.CreateShortcut($f.FullName)
                    if ($lnk.TargetPath) { $target = [string]$lnk.TargetPath }
                } catch { }
            }
            $on = Test-StartupApproved $src.ok $f.Name
            $list += (New-StartupItem ('folder|' + $src.id + '|' + $f.Name) `
                       ([IO.Path]::GetFileNameWithoutExtension($f.Name)) $target $src.scope 'folder' $on)
        }
    }

    $tasks = @()
    try { $tasks = @(Get-ScheduledTask -ErrorAction Stop) } catch { }
    foreach ($t in $tasks) {
        $full = [string]$t.TaskPath + [string]$t.TaskName
        if ($full -like '\Microsoft\*') { continue }          # системные не показываем
        if ($t.TaskName -like 'Win11Privacy*') { continue }   # свои задачи тоже
        $atLogon = $false
        try {
            foreach ($g in @($t.Triggers)) {
                $cn = ''
                try { $cn = [string]$g.CimClass.CimClassName } catch { }
                if ($cn -eq 'MSFT_TaskLogonTrigger' -or $cn -eq 'MSFT_TaskBootTrigger') { $atLogon = $true }
            }
        } catch { }
        if (-not $atLogon) { continue }
        $cmd = ''
        try {
            foreach ($a in @($t.Actions)) { if ($a.Execute) { $cmd = [string]$a.Execute; break } }
        } catch { }
        $list += (New-StartupItem ('task|' + $full) ([string]$t.TaskName) $cmd 'планировщик задач, при входе' 'task' (-not (Test-TaskDisabled $t)))
    }

    return @($list | Sort-Object @{ Expression = { -[int][bool]$_.advise } }, @{ Expression = { $_.name } })
}

# Возвращает @{ ok = ...; error = ... } — включает или гасит одну запись.
function Set-StartupState {
    param([string]$Raw, [bool]$Enabled)
    $parts = ([string]$Raw) -split '\|', 3
    if ($parts.Count -lt 2) { return @{ ok = $false; error = 'непонятная запись' } }
    try {
        if ($parts[0] -eq 'run') {
            $src = $null
            foreach ($s in $script:StartupRuns) { if ($s.id -eq $parts[1]) { $src = $s } }
            if (-not $src) { return @{ ok = $false; error = 'неизвестный раздел реестра' } }
            if ($null -eq (Get-RegValue $src.run $parts[2])) { return @{ ok = $false; error = 'записи больше нет' } }
            Set-StartupApproved $src.ok $parts[2] $Enabled
            return @{ ok = $true }
        }
        if ($parts[0] -eq 'folder') {
            $src = $null
            foreach ($s in $script:StartupFolders) { if ($s.id -eq $parts[1]) { $src = $s } }
            if (-not $src) { return @{ ok = $false; error = 'неизвестная папка автозагрузки' } }
            Set-StartupApproved $src.ok $parts[2] $Enabled
            return @{ ok = $true }
        }
        if ($parts[0] -eq 'task') {
            $full = ($Raw.Substring(5))
            $sp = Split-TaskPath $full
            if ($Enabled) { Enable-ScheduledTask  -TaskPath $sp[0] -TaskName $sp[1] -ErrorAction Stop | Out-Null }
            else          { Disable-ScheduledTask -TaskPath $sp[0] -TaskName $sp[1] -ErrorAction Stop | Out-Null }
            return @{ ok = $true }
        }
        return @{ ok = $false; error = 'непонятный вид записи' }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

function Run-Guard {
    # ($profile — встроенная переменная PowerShell, поэтому имя другое)
    $gp = Load-Json 'profile.json'
    if (-not $gp -or -not $gp.modules) { Write-Log 'Профиль стража не найден.'; return @{ error='нет профиля' } }
    $mods = @($gp.modules)
    # Запрет выдачи номера ставится со своей вкладки, а не со страницы
    # настроек: пока он стоит, страж следит и за ним.
    if ($mods -notcontains 'gdidlock' -and (Test-HostsBlock -Kind 'lock')) { $mods += 'gdidlock' }
    $skipped = @($(if ($gp.PSObject.Properties['skip']) { @($gp.skip) } else { @() }) | ForEach-Object { "$_" })
    $last = Load-Json 'guard-last.json'
    $lastTime = if ($last -and $last.time) { [datetime]$last.time } else { (Get-Date).AddDays(-30) }

    $drifted = @()
    foreach ($d in $script:Defs) {
        if ($mods -notcontains $d.M) { continue }
        if ($skipped -contains $d.Id) { continue }
        if ($d.T -in @('taskglob','svcopt')) { continue }
        $r = Check-Def $d
        if ($r.na) { continue }                      # чего нет на этой Windows — не сбито
        # «не проверено» (места без доступа, профили не в Windows) — тоже не
        # сбито: повторное стирание доступа туда не даст, а службы останавливало
        # бы при каждом запуске стража
        if ($r.unverified) { continue }
        if (-not $r.ok) { $drifted += $r }
    }
    $driftModules = @($drifted | ForEach-Object { $_.module } | Select-Object -Unique)
    # «исправлено» — сколько изменений действительно прошло, а не сколько
    # настроек перебрано: раньше считалась каждая попытка
    $changesBefore = [int]$script:Changes
    # чинить, не имея куда записать «как было», страж не берётся
    if ($driftModules.Count -gt 0 -and -not (Test-JournalWritable)) {
        Write-Log '   [!] страж ничего не чинит: журнал отката не записывается'
        $driftModules = @()
    }
    if ($driftModules.Count -gt 0) {
        $script:Modules = $driftModules
        foreach ($m in $driftModules) {
            if ($m -in @('cleanup','startup','buffer','oem')) { continue }
            if ($m -eq 'gdidlock' -and (Get-GdidLockRefusal)) { continue }
            Write-Section ($script:ModuleTitles[$m])
            foreach ($d in $script:Defs) { if ($d.M -eq $m -and $skipped -notcontains $d.Id) { Apply-Def $d } }
        }
    }
    $fixed = [int]$script:Changes - $changesBefore
    $kbs = Get-RecentHotfixes -Since $lastTime
    $newStartup = @(Find-NewStartup)
    # Номер устройства: страж замечает, что Windows его сменила, и что номер
    # снова появился под запретом выдачи. Сам номер не хранится — только хеш.
    $gNow = ConvertTo-Gdid "$(Get-RegValue 'HKCU:\SOFTWARE\Microsoft\IdentityCRL\ExtendedProperties' 'LID')"
    $gHash = ''
    if ($gNow) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $gHash = (@($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($gNow)) | ForEach-Object { $_.ToString('x2') }) -join '')
        $sha.Dispose()
    }
    $gPrev = $(if ($last -and $last.PSObject.Properties['gdidHash']) { "$($last.gdidHash)" } else { $null })
    if ($driftModules -contains 'gdidlock') {
        Show-Toast 'Номер устройства появился снова' 'Под запретом выдачи Windows снова получила номер — страж его стёр. Проверьте, не снят ли блок в hosts.'
    } elseif ($gHash -and $gPrev -and $gPrev -ne $gHash) {
        Show-Toast 'Номер устройства сменился' 'Windows получила новый номер устройства. Подробности — на вкладке «Номер устройства».'
    }
    # дневной замер телеметрии для хронологии — если запись рентгена включена
    try {
        if ((Test-XrayModule) -and (Get-XrayViewingEnabled)) {
            $xs = Invoke-XrayScan -Hours 24 -Max 4000
            if ($xs -and -not $xs.error) {
                Save-XrayDay $xs
                Save-Json 'xray-last.json' @{ time = $xs.time; perDay = $xs.perDay; mbPerDay = $xs.mbPerDay }
            }
        }
    } catch { }
    $summary = @{
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); checked = $mods; drifted = @($drifted | ForEach-Object { $_.name })
        driftModules = @($driftModules | ForEach-Object { $script:ModuleTitles[$_] }); fixed = $fixed; hotfixes = $kbs
        newStartup = @($newStartup | ForEach-Object { $_.name }); gdidHash = $gHash
    }
    Save-Json 'guard-last.json' $summary
    $line = "{0}  проверено модулей: {1}, сбито: {2}, исправлено: {3}, обновления: {4}" -f $summary.time, $mods.Count, $drifted.Count, $fixed, ($kbs -join ' ')
    try { Ensure-DataDir; Add-Content -LiteralPath (Join-Path $script:DataDir 'guard.log') -Value $line -Encoding UTF8 } catch { }
    if ($drifted.Count -gt 0) {
        $kbText = if ($kbs.Count -gt 0) { " После обновлений: " + ($kbs -join ', ') + "." } else { '' }
        Show-Toast 'Страж приватности' ("Windows вернула настроек: {0}. Исправлено.{1}" -f $drifted.Count, $kbText)
    }
    if ($newStartup.Count -gt 0) {
        $names = @($newStartup | Select-Object -First 3 | ForEach-Object { $_.name })
        $msg = ($names -join ', ')
        if ($newStartup.Count -gt 3) { $msg += (' и ещё ' + ($newStartup.Count - 3)) }
        Show-Toast 'Новая программа в автозагрузке' $msg
        Write-Log ("   [!] новых записей автозагрузки: {0} -- {1}" -f $newStartup.Count, $msg)
    }
    Write-Log $line
    return $summary
}

# --------------------------------------------------------------------------- #
#  Кто прописался в автозагрузку с прошлой проверки. Первый вызов только
#  запоминает то, что уже есть, — иначе страж отрапортует обо всей системе.
# --------------------------------------------------------------------------- #
function Find-NewStartup {
    $fresh = @()
    try {
        $now = @(Get-StartupList)
        $saved = Load-Json 'startup-known.json'
        $first = ($null -eq $saved)
        $known = @{}
        if ($saved -and $saved.items) { foreach ($k in @($saved.items)) { $known["$k"] = $true } }
        foreach ($it in $now) {
            $key = [string]$it.id
            if ($known.ContainsKey($key)) { continue }
            $known[$key] = $true
            if (-not $first -and $it.enabled) { $fresh += @{ name = [string]$it.name; source = [string]$it.source } }
        }
        $keys = @($known.Keys)
        Save-Json 'startup-known.json' @{ items = $keys; updated = (Get-Date).ToString('s') }
    } catch { }
    return $fresh
}

if ($InstallGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Страж приватности'
    Write-SessionUserNote
    try {
        Ensure-DataDir
        $engineDst = Install-TaskEngine
        $mods = @($Modules | Where-Object { $_ -notin @('cleanup','startup','buffer') })
        # Снятые внутри модуля пункты страж тоже помнит: иначе он «чинил» бы
        # то, что человек оставил нарочно, — например, DoSvc ради Магазина.
        Save-Json 'profile.json' @{ version=1; modules=$mods; skip=@($SkipItems); created=(Get-Date).ToString('s') }
        $action = New-ScheduledTaskAction -Execute $script:PsExe -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $engineDst + '" -Guard' + $script:DataArg)
        $t1 = New-ScheduledTaskTrigger -AtLogOn -User $script:RunAccount
        $t1.Delay = 'PT3M'
        # по умолчанию раз в неделю; -GuardDaily — каждый день в то же время
        $t2 = if ($GuardDaily) { New-ScheduledTaskTrigger -Daily -At 12:00 }
              else { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 12:00 }
        # Настройки сбивает обновление, а расписание могло ждать до воскресенья.
        # Третий триггер — сама установка обновления: страж приходит следом.
        $triggers = @($t1, $t2)
        try {
            $t3 = New-CimInstance -CimClass (Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler) -ClientOnly
            $t3.Enabled = $true
            $t3.Delay = 'PT5M'
            $t3.Subscription = '<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name=''Microsoft-Windows-WindowsUpdateClient''] and (EventID=19 or EventID=43)]]</Select></Query></QueryList>'
            $triggers += $t3
        } catch { }
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew
        $principal = New-ScheduledTaskPrincipal -UserId $script:RunAccount -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $script:GuardTask -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log ("   [+] страж установлен: проверка через 3 минуты после входа в систему и {0}" -f $(if ($GuardDaily) { 'каждый день в 12:00' } else { 'по воскресеньям в 12:00' }))
        if ($triggers.Count -gt 2) { Write-Log '   [+] и через 5 минут после каждого установленного обновления Windows' }
        else { Write-Log '   [-] пробуждение после обновлений недоступно на этой системе' }
        Write-Log ("   [+] отслеживается модулей: {0}" -f $mods.Count)
        Write-Log ("   [+] журнал: {0}" -f (Join-Path $script:DataDir 'guard.log'))
    } catch { Write-Log "   [!] не удалось установить стража: $($_.Exception.Message)"; $failed = $true }
    Write-Log '###DONE###'
    # Код честный: регистрация задачи могла не пройти (например, повышение под
    # другой учётной записью не даёт поставить задачу с наивысшими правами).
    # Раньше здесь всегда был 0, и окно показывало «Готово» при неудаче.
    exit $(if ($failed) { 1 } else { 0 })
}

if ($RemoveGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Страж приватности'
    $rt = Remove-OwnTask $script:GuardTask 'задача стража'
    Write-Log '###DONE###'
    if ($rt -eq 'failed') { exit 1 }
    exit 0
}


# =========================================================================== #
#  Purge buffer (отдельная команда)
# =========================================================================== #
if ($PurgeBuffer) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Purge-Buffer
    Emit-Json (Get-BufferInfo)
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  РЕНТГЕН ТЕЛЕМЕТРИИ
#  Читает реальные события диагностики, которые Windows собрала о компьютере,
#  через встроенный модуль Microsoft.DiagnosticDataViewer.
# =========================================================================== #
$script:XrayDbDir = Join-Path $env:ProgramData 'Microsoft\Diagnosis\EventTranscript'

# Правила расшифровки: имя события -> человеческая категория
$script:XrayRules = @(
    @{ rx = 'Inventory\.(Core|Application)|InventoryApplication|AppInv|InstalledApplication';
       cat = 'Список установленных программ'; what = 'Какие программы стоят на компьютере, их версии и издатели' },
    @{ rx = 'Census|SystemInfo|Hardware|Processor|Memory|Storage|Battery|Firmware|Bios|Chassis';
       cat = 'Инвентаризация железа'; what = 'Модель ноутбука, процессор, память, диски, серийные номера' },
    @{ rx = 'AppInteractivity|AppLaunch|AppUsage|Win32kTraceLogging|AppActivity|ProcessStart|FocusTime';
       cat = 'Какие программы ты запускал'; what = 'Что открывал, сколько времени провёл, как часто' },
    @{ rx = 'PnP|DeviceConfig|DeviceInventory|USB|Bluetooth|Peripheral|Driver';
       cat = 'Подключённые устройства'; what = 'Флешки, наушники, принтеры, мыши — что и когда подключал' },
    @{ rx = 'WER|Fault|AppCrash|Watson|Hang|Reliability|BugCheck|Crash';
       cat = 'Сбои и падения программ'; what = 'Какие программы падали, с какими ошибками, имена файлов' },
    @{ rx = 'Edge|Browser|WebView|Chromium|SmartScreen';
       cat = 'Браузер'; what = 'Активность в браузере, посещения, проверки сайтов' },
    @{ rx = 'Search|Cortana|Bing|Suggest';
       cat = 'Поиск'; what = 'Что искал в меню Пуск и как использовался поиск' },
    @{ rx = 'Store|AppXDeployment|Purchase|License|Xbox|Game';
       cat = 'Магазин, игры и лицензии'; what = 'Установки из магазина, покупки, игровая активность' },
    @{ rx = 'Defender|Antivirus|Antimalware|Security|Firewall|Tpm|SecureBoot';
       cat = 'Безопасность'; what = 'Состояние защиты, проверки, обнаружения' },
    @{ rx = 'Update|WindowsUpdate|SIH|WUFB|Servicing|Setup360|UpdateAgent|Delivery';
       cat = 'Обновления'; what = 'Установка обновлений, версии, ошибки установки' },
    @{ rx = 'Location|Geolocation|Position|Wifi.*Scan|Sensor';
       cat = 'Местоположение и датчики'; what = 'Где находится компьютер, окружающие сети' },
    @{ rx = 'Logon|Login|Account|AAD|MSA|Identity|User\.|Profile|Credential';
       cat = 'Учётная запись'; what = 'Входы в систему, привязка к учётной записи Microsoft' },
    @{ rx = 'Network|Dns|Tcp|Connectivity|Ndis|Wlan|Ethernet';
       cat = 'Сеть'; what = 'Сетевые подключения, качество связи' },
    @{ rx = 'Power|Sleep|Resume|Boot|Shutdown|Uptime|Kernel\.Process';
       cat = 'Питание и загрузка'; what = 'Когда включал и выключал, время работы' },
    @{ rx = 'Office|Word|Excel|Outlook|OneDrive|Teams';
       cat = 'Office и OneDrive'; what = 'Работа с документами и облаком' },
    @{ rx = 'Heartbeat|Diagtrack|Telemetry|Utc\.|SelfHost|OneSettings|Aria';
       cat = 'Служебное телеметрии'; what = 'Служебные события самой системы сбора данных' }
)

function Get-XrayCategory {
    param([string]$Name)
    foreach ($r in $script:XrayRules) { if ($Name -match $r.rx) { return $r } }
    return @{ cat = 'Прочее'; what = 'События, не попавшие в известные категории' }
}

function Test-XrayModule {
    if (Get-Command Get-DiagnosticData -ErrorAction SilentlyContinue) { return $true }
    Import-Module Microsoft.DiagnosticDataViewer -ErrorAction SilentlyContinue
    return [bool](Get-Command Get-DiagnosticData -ErrorAction SilentlyContinue)
}

function Get-XrayViewingEnabled {
    try {
        if (Get-Command Get-DiagnosticDataViewingSetting -ErrorAction SilentlyContinue) {
            $s = Get-DiagnosticDataViewingSetting
            if ($null -ne $s) {
                foreach ($p in @('DiagnosticDataViewingEnabled','Enabled','IsEnabled')) {
                    if ($s.PSObject.Properties.Name -contains $p) { return [bool]$s.$p }
                }
                return [bool]$s
            }
        }
    } catch { }
    $v = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\EventTranscript' 'EnableEventTranscript'
    return ($v -eq 1)
}

function Get-XrayDbInfo {
    $mb = 0; $found = $false
    try {
        $items = @(Get-ChildItem -LiteralPath $script:XrayDbDir -Force -ErrorAction Stop)
        if ($items.Count -gt 0) {
            $found = $true
            $sum = ($items | Measure-Object -Property Length -Sum).Sum
            if ($sum) { $mb = [math]::Round($sum / 1MB, 2) }
        }
    } catch { }
    return @{ exists = $found; mb = $mb; path = $script:XrayDbDir }
}

function Get-XrayStatusObject {
    return @{
        moduleAvailable = (Test-XrayModule)
        recording       = (Get-XrayViewingEnabled)
        db              = (Get-XrayDbInfo)
        baseline        = (Load-Json 'xray-baseline.json')
    }
}

# --- Основное сканирование ------------------------------------------------- #
# --------------------------------------------------------------------------- #
#  ЧТО ИМЕННО О ВАС УЗНАЛИ
#  Рентген уже читает настоящие события. Здесь их содержимое превращается в
#  человеческие факты: не «1420 событий инвентаризации», а «названия 47 ваших
#  программ, модель ноутбука, серийный номер диска». Правило, которое ничего
#  не нашло, просто не показывается — выдумывать нечего.
# --------------------------------------------------------------------------- #
$script:FactRules = @(
    @{ id = 'apps';    title = 'Названия установленных программ'
       what = 'Windows перечисляет, что у вас стоит: имя, издатель и версия каждой программы.'
       re = '"(?:ProgramName|AppName|PackageFullName|ProductName)"\s*:\s*"([^"]{2,90})"' },
    @{ id = 'files';   title = 'Имена запускавшихся файлов'
       what = 'В событиях видно, какие исполняемые файлы вы открывали.'
       re = '"(?:FileName|BinaryName|ImageName|ExeName)"\s*:\s*"([^"]{2,90})"' },
    @{ id = 'device';  title = 'Модель и производитель компьютера'
       what = 'Точная модель железа — по ней устройство узнаётся среди прочих.'
       re = '"(?:deviceMake|deviceModel|SystemManufacturer|SystemProductName|Model|Manufacturer)"\s*:\s*"([^"]{2,80})"' },
    @{ id = 'ids';     title = 'Идентификаторы, которыми вас метят'
       what = 'Постоянные номера устройства и учётной записи: по ним события связываются в один профиль.'
       # номер устройства в учётной записи (GDID) событие несёт полем device.id: «g:» и цифры
       re = '(?:"(?:localId|deviceId|machineId|userId|globalDeviceId|sqmId)"\s*:\s*"|"id"\s*:\s*"(?=g:\d{6}))([^"]{6,120})' },
    @{ id = 'serial';  title = 'Серийные номера железа'
       what = 'Серийный номер не меняется никогда — это самая надёжная метка устройства.'
       re = '"(?:SerialNumber|BaseBoardSerial|BiosSerial|DiskSerial)"\s*:\s*"([^"]{4,80})"' },
    @{ id = 'hw';      title = 'Начинка компьютера'
       what = 'Процессор, память, диски и видеокарта — подробная опись железа.'
       re = '"(?:ProcessorIdentifier|ProcessorManufacturer|TotalPhysicalRAM|PrimaryDiskType|GraphicsAdapter|CpuFamily)"\s*:\s*"?([^",]{2,80})"?' },
    @{ id = 'net';     title = 'Сетевые адреса и имена сетей'
       what = 'MAC-адрес и названия сетей говорят, где физически стоит компьютер.'
       re = '"(?:MacAddress|SSID|NetworkName|BSSID)"\s*:\s*"([^"]{4,80})"' },
    @{ id = 'user';    title = 'Учётная запись и язык'
       what = 'Имя пользователя, страна, часовой пояс и раскладка.'
       re = '"(?:UserName|AccountName|CountryRegion|TimeZone|Locale|UserLocale|KeyboardLayout)"\s*:\s*"([^"]{2,80})"' },
    @{ id = 'devices'; title = 'Подключённые устройства'
       what = 'Всё, что вы подключали: принтеры, флешки, наушники, телефоны.'
       re = '"(?:DeviceName|FriendlyName|DeviceInstanceId|ContainerId)"\s*:\s*"([^"]{4,90})"' },
    @{ id = 'errors';  title = 'Сбои программ с их именами'
       what = 'Имена упавших программ и модулей — заодно видно, чем вы пользуетесь.'
       re = '"(?:FaultingApplicationName|CrashingProcess|ExceptionModule)"\s*:\s*"([^"]{2,90})"' }
)

function Add-FactValue {
    param($Store, [string]$Id, [string]$Value)
    $v = $Value.Trim()
    if (-not $v) { return }
    if ($v -match '^[\{\[]') { return }               # GUID-ы и структуры пропускаем
    if ($v -match '^(?:0|1|true|false|null|unknown|n/a)$') { return }
    if (-not $Store.ContainsKey($Id)) { $Store[$Id] = @{} }
    if ($Store[$Id].Count -ge 400) { return }           # памяти ради
    if ($Store[$Id].ContainsKey($v)) { $Store[$Id][$v]++ } else { $Store[$Id][$v] = 1 }
}

function Invoke-XrayScan {
    param([int]$Hours, [int]$Max)

    if (-not (Test-XrayModule)) {
        return @{ error = 'Модуль Microsoft.DiagnosticDataViewer недоступен на этой системе.' }
    }
    if (-not (Get-XrayViewingEnabled)) {
        return @{ error = 'Запись диагностики выключена. Нажмите «Включить запись», подождите — и повторите.'; recording = $false }
    }

    $start = (Get-Date).AddHours(-$Hours)
    $events = @()
    try { $events = @(Get-DiagnosticData -StartTime $start -RecordCount $Max -ErrorAction Stop) }
    catch { return @{ error = ("Не удалось прочитать данные: " + $_.Exception.Message) } }

    if ($events.Count -eq 0) {
        return @{ error = 'Событий за выбранный период нет. Если запись включена только что — подождите час-другой.'; total = 0; recording = $true }
    }

    $cats = @{}
    $names = @{}
    $bytes = 0
    $ids = @{}
    $apps = @{}
    $samples = @{}
    $facts = @{}

    foreach ($ev in $events) {
        $n = [string]$ev.Name
        $p = [string]$ev.Payload
        $bytes += $p.Length

        $rule = Get-XrayCategory $n
        $c = $rule.cat
        if (-not $cats.ContainsKey($c)) { $cats[$c] = @{ count = 0; bytes = 0; what = $rule.what; names = @{} } }
        $cats[$c].count++
        $cats[$c].bytes += $p.Length
        if ($cats[$c].names.ContainsKey($n)) { $cats[$c].names[$n]++ } else { $cats[$c].names[$n] = 1 }

        if ($names.ContainsKey($n)) { $names[$n]++ } else { $names[$n] = 1 }

        if (-not $samples.ContainsKey($c) -and $p.Length -gt 40) {
            $txt = $p
            if ($txt.Length -gt 1800) { $txt = $txt.Substring(0, 1800) + ' …' }
            $samples[$c] = @{ name = $n; time = $ev.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'); payload = $txt }
        }

        # что именно о вас узнали — по тем же событиям
        foreach ($rule in $script:FactRules) {
            foreach ($m in [regex]::Matches($p, $rule.re)) { Add-FactValue $facts $rule.id $m.Groups[1].Value }
        }

        # идентификаторы, которыми помечены события
        foreach ($m in [regex]::Matches($p, '"(localId|deviceId|machineId|userId|sessionId|deviceClass|osVer|deviceMake|deviceModel)"\s*:\s*"([^"]{2,120})"')) {
            $k = $m.Groups[1].Value; $v = $m.Groups[2].Value
            if (-not $ids.ContainsKey($k)) { $ids[$k] = @{} }
            if (-not $ids[$k].ContainsKey($v)) { $ids[$k][$v] = 0 }
            $ids[$k][$v]++
        }
        # названия программ, попавшие в инвентаризацию
        if ($n -match 'Inventory|AppInv|AppInteractivity|AppLaunch') {
            foreach ($m in [regex]::Matches($p, '"(?:ProgramName|AppName|Name|PackageFullName|FileName)"\s*:\s*"([^"]{2,90})"')) {
                $v = $m.Groups[1].Value
                if ($v -match '^[\{\d]' ) { continue }
                if ($apps.ContainsKey($v)) { $apps[$v]++ } else { $apps[$v] = 1 }
            }
        }
    }

    $span = [math]::Max(0.05, $Hours)
    $perDay  = [math]::Round($events.Count * 24.0 / $span, 0)
    $mbTotal = $bytes / 1MB
    $mbDay   = [math]::Round($mbTotal * 24.0 / $span, 2)

    $catList = @()
    foreach ($k in ($cats.Keys | Sort-Object { -$cats[$_].count })) {
        $topNames = @($cats[$k].names.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 |
                      ForEach-Object { @{ name = $_.Key; count = $_.Value } })
        $catList += @{
            name = $k; count = $cats[$k].count
            mb = [math]::Round($cats[$k].bytes / 1MB, 3)
            what = $cats[$k].what
            share = [math]::Round(100.0 * $cats[$k].count / $events.Count, 1)
            topNames = $topNames
            sample = $(if ($samples.ContainsKey($k)) { $samples[$k] } else { $null })
        }
    }

    $idList = @()
    foreach ($k in $ids.Keys) {
        $vals = @($ids[$k].GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3 |
                  ForEach-Object { @{ value = $_.Key; count = $_.Value } })
        $idList += @{ key = $k; distinct = $ids[$k].Count; values = $vals }
    }

    $appList = @($apps.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 25 |
                 ForEach-Object { @{ name = $_.Key; count = $_.Value } })

    $factList = @()
    foreach ($rule in $script:FactRules) {
        if (-not $facts.ContainsKey($rule.id)) { continue }
        $vals = @($facts[$rule.id].GetEnumerator() | Sort-Object Value -Descending)
        if ($vals.Count -eq 0) { continue }
        $factList += @{
            id = $rule.id; title = $rule.title; what = $rule.what
            distinct = $vals.Count
            examples = @($vals | Select-Object -First 6 | ForEach-Object { [string]$_.Key })
        }
    }

    $result = @{
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); hours = $Hours; recording = $true
        total = $events.Count; distinctNames = $names.Count
        mb = [math]::Round($mbTotal, 2); perDay = $perDay; mbPerDay = $mbDay
        perYear = [math]::Round($perDay * 365, 0); mbPerYear = [math]::Round($mbDay * 365, 1)
        categories = $catList; identifiers = $idList; apps = $appList; facts = $factList
        topNames = @($names.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15 |
                     ForEach-Object { @{ name = $_.Key; count = $_.Value } })
        db = (Get-XrayDbInfo)
    }

    $base = Load-Json 'xray-baseline.json'
    if ($base -and $base.perDay) {
        $result.baselinePerDay = $base.perDay
        $result.baselineTime = $base.time
        $result.deltaPercent = $(if ([double]$base.perDay -gt 0) { [math]::Round(100.0 * (1.0 - ($perDay / [double]$base.perDay)), 1) } else { 0 })
    }
    return $result
}

if ($XrayStatus) { Emit-Json (Get-XrayStatusObject); exit 0 }

if ($XrayEnable) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Рентген: включение записи'
    if (-not (Test-XrayModule)) { Write-Log '   [!] модуль Microsoft.DiagnosticDataViewer недоступен' }
    else {
        try {
            Enable-DiagnosticDataViewing -ErrorAction Stop
            Write-Log '   [+] запись диагностики включена'
        } catch {
            Write-Log "   [!] $($_.Exception.Message)"
            Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\EventTranscript' 'EnableEventTranscript' 1 -Comment 'запись событий диагностики (резервный способ)'
        }
    }
    Write-Log ''
    Write-Log 'Windows теперь ведёт ЛОКАЛЬНУЮ копию своих диагностических событий,'
    Write-Log 'чтобы их можно было прочитать. Объём отправки при этом не растёт.'
    Write-Log 'Дайте системе поработать хотя бы час, затем нажмите «Сканировать».'
    Write-Log '###DONE###'
    exit 0
}

if ($XrayDisable) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Рентген: выключение записи'
    try { Disable-DiagnosticDataViewing -ErrorAction Stop; Write-Log '   [+] запись выключена' }
    catch { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\EventTranscript' 'EnableEventTranscript' 0 -Comment 'запись событий диагностики — выкл' }
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  ХРОНОЛОГИЯ ПРИВАТНОСТИ
#  Программа копит историю: сколько событий телеметрии уходило в день, кто
#  трогал датчики, что она сама меняла, что возвращал страж и когда приезжали
#  обновления Windows. Собранные на одной оси, эти ряды показывают то, чего не
#  видно в моменте: как система отыгрывает настройки назад после обновлений.
# =========================================================================== #
function Save-XrayDay {
    param($Scan)
    if (-not $Scan -or -not $Scan.perDay) { return }
    try {
        $hist = Load-Json 'xray-history.json'
        $days = @{}
        if ($hist -and $hist.days) {
            foreach ($d in @($hist.days)) { $days["$($d.date)"] = $d }
        }
        $today = (Get-Date).ToString('yyyy-MM-dd')
        $days[$today] = @{ date = $today; perDay = [int]$Scan.perDay; mbPerDay = "$($Scan.mbPerDay)" }
        $list = @($days.Values | Sort-Object { "$($_.date)" } | Select-Object -Last 400)
        Save-Json 'xray-history.json' @{ days = $list; updated = (Get-Date).ToString('s') }
    } catch { Write-Log ("   [-] день рентгена в хронологию не записался: {0}" -f $_.Exception.Message) }
}

function Get-GuardDays {
    $byDay = @{}
    $log = Join-Path $script:DataDir 'guard.log'
    if (-not (Test-Path -LiteralPath $log)) { return $byDay }
    try {
        foreach ($line in @(Get-Content -LiteralPath $log -Encoding UTF8 -ErrorAction Stop)) {
            $m = [regex]::Match($line, '^(\d{4}-\d{2}-\d{2}).*?сбито:\s*(\d+).*?исправлено:\s*(\d+)')
            if (-not $m.Success) { continue }
            $ds = $m.Groups[1].Value
            if (-not $byDay.ContainsKey($ds)) { $byDay[$ds] = @{ drifted = 0; fixed = 0; checks = 0 } }
            $byDay[$ds].drifted += [int]$m.Groups[2].Value
            $byDay[$ds].fixed += [int]$m.Groups[3].Value
            $byDay[$ds].checks++
        }
    } catch { }
    return $byDay
}

function Get-Timeline {
    param([int]$Days = 30)
    if ($Days -lt 7) { $Days = 7 }
    if ($Days -gt 180) { $Days = 180 }

    # рентген по дням
    $xray = @{}
    $xh = Load-Json 'xray-history.json'
    if ($xh -and $xh.days) { foreach ($d in @($xh.days)) { $xray["$($d.date)"] = [int]$d.perDay } }

    # датчики по дням
    $sensors = @{}
    $hist = Load-Json 'sensor-history.json'
    if ($hist -and $hist.events) {
        foreach ($e in @($hist.events)) {
            $ds = "$($e.time)"
            if ($ds.Length -lt 10) { continue }
            $ds = $ds.Substring(0, 10)
            if (-not $sensors.ContainsKey($ds)) { $sensors[$ds] = 0 }
            $sensors[$ds]++
        }
    }

    # что меняла сама программа
    $changes = @{}
    $j = Read-JournalFile -ReadOnly
    if ($j.items.Count -gt 0) {
        foreach ($e in @($j.items)) {
            $ds = "$($e.time)"
            if ($ds.Length -lt 10) { continue }
            $ds = $ds.Substring(0, 10)
            if (-not $changes.ContainsKey($ds)) { $changes[$ds] = 0 }
            $changes[$ds]++
        }
    }

    $guard = Get-GuardDays

    # обновления Windows
    $updates = @{}
    try {
        foreach ($h in @(Get-HotFix -ErrorAction SilentlyContinue)) {
            if (-not $h.InstalledOn) { continue }
            $ds = ([datetime]$h.InstalledOn).ToString('yyyy-MM-dd')
            if (-not $updates.ContainsKey($ds)) { $updates[$ds] = @() }
            $updates[$ds] += [string]$h.HotFixID
        }
    } catch { }

    $rows = @()
    $peak = 0
    for ($i = $Days - 1; $i -ge 0; $i--) {
        $d = (Get-Date).Date.AddDays(-$i)
        $ds = $d.ToString('yyyy-MM-dd')
        $ev = $(if ($xray.ContainsKey($ds)) { $xray[$ds] } else { 0 })
        if ($ev -gt $peak) { $peak = $ev }
        $g = $(if ($guard.ContainsKey($ds)) { $guard[$ds] } else { $null })
        $rows += @{
            date     = $ds
            label    = $d.ToString('dd.MM')
            events   = $ev
            sensors  = $(if ($sensors.ContainsKey($ds)) { $sensors[$ds] } else { 0 })
            changes  = $(if ($changes.ContainsKey($ds)) { $changes[$ds] } else { 0 })
            drifted  = $(if ($g) { [int]$g.drifted } else { 0 })
            fixed    = $(if ($g) { [int]$g.fixed } else { 0 })
            updates  = @($(if ($updates.ContainsKey($ds)) { $updates[$ds] } else { @() }))
        }
    }

    # что из этого стоит сказать словами
    $notes = @()
    for ($i = 1; $i -lt $rows.Count; $i++) {
        $prev = $rows[$i - 1]; $cur = $rows[$i]
        # ВАЖНО: словами это становится в интерфейсе — движок отдаёт числа,
        # иначе в английской версии заметки остались бы русскими
        if ($cur.updates.Count -gt 0) {
            $notes += @{ date = $cur.label; kind = 'update'; a = 0; b = 0; list = (@($cur.updates) -join ', ') }
        }
        if ($cur.drifted -gt 0) {
            $notes += @{ date = $cur.label; kind = 'drift'; a = [int]$cur.drifted; b = [int]$cur.fixed; list = '' }
        }
        if ($prev.events -gt 0 -and $cur.events -gt ($prev.events * 1.5) -and $cur.events -gt 100) {
            $notes += @{ date = $cur.label; kind = 'grow'; a = [int]$prev.events; b = [int]$cur.events; list = '' }
        }
    }

    return @{
        days = $rows; peak = $peak; count = $rows.Count
        notes = @($notes | Select-Object -Last 12)
        hasXray = [bool]($xray.Count -gt 0)
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    }
}

if ($Timeline) {
    Emit-Json (Get-Timeline -Days $TimelineDays)
    exit 0
}

if ($XrayScan) {
    $r = Invoke-XrayScan -Hours $XrayHours -Max $XrayMax
    if (-not $r.error) {
        try { Save-Json 'xray-last.json' @{ time = $r.time; perDay = $r.perDay; mbPerDay = $r.mbPerDay } }
    catch { Write-Log ("   [-] итог рентгена не сохранился: {0}" -f $_.Exception.Message) }
        Save-XrayDay $r      # дневной замер для хронологии
    }
    if ($XrayBaseline -and -not $r.error) {
        Save-Json 'xray-baseline.json' @{ time = $r.time; perDay = $r.perDay; mbPerDay = $r.mbPerDay; total = $r.total; hours = $r.hours }
        $r.savedBaseline = $true
    }
    Emit-Json $r
    exit 0
}

if ($XrayWipe) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Рентген: стирание локальной копии'
    $before = (Get-XrayDbInfo).mb
    $svc = Get-Service -Name DiagTrack -ErrorAction SilentlyContinue
    $was = ($svc -and $svc.Status -eq 'Running')
    if ($was) { Stop-Service DiagTrack -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 800 }
    $n = 0; $kept = New-Object System.Collections.Generic.List[string]
    foreach ($f in @(Get-ChildItem -LiteralPath $script:XrayDbDir -Force -ErrorAction SilentlyContinue)) {
        try { Remove-Item -LiteralPath $f.FullName -Force -Recurse -ErrorAction Stop; $n++ }
        catch { $kept.Add(("{0}: {1}" -f $f.Name, $_.Exception.Message)) }
    }
    if ($was -and $svc.StartType -ne 'Disabled') { Start-Service DiagTrack -ErrorAction SilentlyContinue }
    Write-Log ("   [+] удалено файлов: {0} (было {1} МБ)" -f $n, $before)
    # раньше неудачи здесь не считались вовсе — «удалено» писалось и тогда
    if ($kept.Count -gt 0) {
        Write-Log ("   [!] не удалось удалить: {0}" -f $kept.Count)
        foreach ($k in @($kept | Select-Object -First 3)) { Write-Log ("       {0}" -f $k) }
        $script:Failures++
    }
    Emit-Json (Get-XrayDbInfo)
    Write-Log '###DONE###'
    # 2 — дошёл до конца, но не всё прошло (окно пишет «Готово, с ошибками»); раньше всегда 0
    exit $(if ($script:Failures -gt 0) { 2 } else { 0 })
}

# --- Страж запускается после объявления рентгена: он делает дневной замер --- #
if ($Guard) {
    if (-not (Test-Admin)) { exit 1 }
    $null = Run-Guard
    exit 0
}

if ($GuardNow) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Страж: проверка сейчас'
    $s = Run-Guard
    Emit-Json $s
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  МАШИНА ВРЕМЕНИ: снимки состояния и разница
# =========================================================================== #
$script:SnapDir = Join-Path $script:DataDir 'snapshots'

function Get-SnapshotState {
    $items = @{}
    foreach ($d in $script:Defs) {
        if ($d.T -in @('taskglob')) { continue }
        $r = Check-Def $d
        $items[($d.M + '|' + $d.C)] = @{ ok = $r.ok; actual = $r.actual }
    }
    return $items
}

function New-Snapshot {
    if (-not (Test-Path -LiteralPath $script:SnapDir)) { New-Item -ItemType Directory -Path $script:SnapDir -Force | Out-Null }
    $state = Get-SnapshotState
    $ok = @($state.Values | Where-Object { $_.ok }).Count
    $obj = @{
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        build = [System.Environment]::OSVersion.Version.Build
        ok = $ok; total = $state.Count
        hotfixes = @(Get-RecentHotfixes -Since (Get-Date).AddDays(-30))
        items = $state
    }
    $file = Join-Path $script:SnapDir ('snap-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    ($obj | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $file -Encoding UTF8
    return @{ file = (Split-Path $file -Leaf); time = $obj.time; ok = $ok; total = $state.Count }
}

function Get-SnapshotList {
    $list = @()
    if (Test-Path -LiteralPath $script:SnapDir) {
        foreach ($f in (Get-ChildItem -LiteralPath $script:SnapDir -Filter 'snap-*.json' | Sort-Object Name -Descending)) {
            try {
                $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $list += @{ file = $f.Name; time = $j.time; ok = $j.ok; total = $j.total; build = $j.build; hotfixes = @($j.hotfixes) }
            } catch { }
        }
    }
    return $list
}

if ($Snapshot) {
    $s = New-Snapshot
    Write-Section 'Снимок состояния'
    Write-Log ("   [+] сохранён снимок: {0} из {1} настроек на месте" -f $s.ok, $s.total)
    Emit-Json $s
    Write-Log '###DONE###'
    exit 0
}

if ($SnapshotList) {
    # ВАЖНО: список кладём через переменную. Если писать @{ x = (Функция) }, то
    # массив из одного элемента разворачивается, ConvertTo-Json пишет объект
    # вместо списка — и интерфейс показывает «пусто» на первом же снимке.
    $snapList = @(Get-SnapshotList)
    Emit-Json @{ snapshots = $snapList; count = $snapList.Count }
    exit 0
}

if ($SnapshotDiff) {
    $parts = $SnapshotDiff -split '\|'
    if ($parts.Count -ne 2) { Emit-Json @{ error = 'нужны два снимка' }; exit 1 }
    try {
        $a = Get-Content -LiteralPath (Join-Path $script:SnapDir $parts[0]) -Raw -Encoding UTF8 | ConvertFrom-Json
        $b = Get-Content -LiteralPath (Join-Path $script:SnapDir $parts[1]) -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch { Emit-Json @{ error = 'не удалось прочитать снимки' }; exit 1 }
    $diffChanges = @()
    foreach ($p in $a.items.PSObject.Properties) {
        $k = $p.Name
        $av = $p.Value
        $bp = $b.items.PSObject.Properties[$k]
        if (-not $bp) { continue }
        $bv = $bp.Value
        if ($av.ok -ne $bv.ok) {
            $parts2 = $k -split '\|', 2
            $diffChanges += @{ module = $parts2[0]; name = $parts2[1]
                           was = $(if ($av.ok) { 'на месте' } else { 'сбито' })
                           now = $(if ($bv.ok) { 'на месте' } else { 'сбито' })
                           broke = ($av.ok -and -not $bv.ok)
                           wasValue = [string]$av.actual; nowValue = [string]$bv.actual }
        }
    }
    Emit-Json @{ from = $a.time; to = $b.time; fromOk = $a.ok; toOk = $b.ok; total = $a.total
                 hotfixes = @($b.hotfixes); changes = $diffChanges
                 broke = @($diffChanges | Where-Object { $_.broke }).Count }
    exit 0
}

# =========================================================================== #
#  ЖИВЫЕ УВЕДОМЛЕНИЯ О ПЕРЕХВАТЕ
# =========================================================================== #
$script:WatcherTask = 'Win11Privacy Watcher'

if ($InstallWatcher) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Живые уведомления'
    Write-SessionUserNote
    try {
        Ensure-DataDir
        $engineDst = Install-TaskEngine
        if (-not (Get-MonitorEnabled)) { Set-MonitorEnabled $true | Out-Null }
        foreach ($d in $script:Defs) { if ($d.M -eq 'firewall') { Apply-Def $d } }

        $action = New-ScheduledTaskAction -Execute $script:PsExe -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $engineDst + '" -WatcherNotify' + $script:DataArg)
        $cls = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
        $trigger = New-CimInstance -CimClass $cls -ClientOnly
        $trigger.Subscription = '<QueryList><Query Id="0" Path="Security"><Select Path="Security">*[System[(EventID=5157)]]</Select></Query></QueryList>'
        $trigger.Enabled = $true
        $trigger.Delay = 'PT5S'
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 3)
        $principal = New-ScheduledTaskPrincipal -UserId $script:RunAccount -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $script:WatcherTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log '   [+] уведомления включены: всплывашка при перехвате отправки телеметрии'
        Write-Log '   [+] чтобы не мешать, одно уведомление не чаще чем раз в 10 минут'
    } catch { Write-Log "   [!] не удалось: $($_.Exception.Message)"; $failed = $true }
    Write-Log '###DONE###'
    # Код честный: регистрация задачи могла не пройти (раньше здесь всегда был 0).
    exit $(if ($failed) { 1 } else { 0 })
}

if ($RemoveWatcher) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Живые уведомления'
    $rt = Remove-OwnTask $script:WatcherTask 'живые уведомления'
    Write-Log '###DONE###'
    exit $(if ($rt -eq 'failed') { 1 } else { 0 })
}

if ($WatcherNotify) {
    # антидребезг: не чаще одного уведомления в 10 минут
    Ensure-DataDir
    $stamp = Join-Path $script:DataDir 'watcher-last.txt'
    if (Test-Path -LiteralPath $stamp) {
        try {
            $last = [datetime]::ParseExact((Get-Content -LiteralPath $stamp -Raw).Trim(), 'yyyy-MM-dd HH:mm:ss', $null)
            if ((Get-Date) -lt $last.AddMinutes(10)) { exit 0 }
        } catch { }
    }
    $stats = Get-MonitorStats -Hours 1
    $tele = @($stats.byDest | Where-Object { $_.domain -match $script:TelemetryDnsRegex })
    if ($tele.Count -eq 0) { exit 0 }
    $top = $tele | Sort-Object { $_.count } -Descending | Select-Object -First 1
    $procs = @($stats.byProcess | Select-Object -First 1)
    $who = if ($procs.Count -gt 0) { $procs[0].name } else { 'системная служба' }
    Show-Toast 'Перехвачена отправка данных' ("{0} пытался отправить данные на {1} — заблокировано." -f $who, $top.domain)
    (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') | Set-Content -LiteralPath $stamp -Encoding UTF8
    exit 0
}

# =========================================================================== #
#  ДОСЬЕ, часть 1: кто включал камеру, микрофон, геолокацию
#  Windows сама ведёт журнал обращений к датчикам (ConsentStore) —
#  мы его читаем и показываем человеку. Только чтение.
# =========================================================================== #
$script:SpyCaps = @(
    @{ id='webcam';                 title='Камера' },
    @{ id='microphone';             title='Микрофон' },
    @{ id='location';               title='Местоположение' },
    @{ id='graphicsCaptureProgrammatic'; title='Снимки экрана' },
    @{ id='graphicsCaptureWithoutBorder'; title='Захват экрана без рамки' },
    @{ id='userNotificationListener'; title='Чтение уведомлений' },
    @{ id='documentsLibrary';       title='Документы' },
    @{ id='picturesLibrary';        title='Изображения' },
    @{ id='videosLibrary';          title='Видео' },
    @{ id='broadFileSystemAccess';  title='Весь диск' },
    @{ id='contacts';               title='Контакты' },
    @{ id='appointments';           title='Календарь' },
    @{ id='email';                  title='Почта' },
    @{ id='chat';                   title='Сообщения' },
    @{ id='phoneCall';              title='Звонки' },
    @{ id='phoneCallHistory';       title='Журнал звонков' },
    @{ id='userDataTasks';          title='Задачи и планы' },
    @{ id='userAccountInformation'; title='Данные учётной записи' },
    @{ id='activity';               title='Сведения об активности' },
    @{ id='bluetoothSync';          title='Обмен с устройствами' },
    @{ id='radios';                 title='Управление радиомодулями' },
    @{ id='sensors.custom';         title='Датчики устройства' },
    @{ id='humanInterfaceDevice';   title='Устройства ввода' },
    @{ id='cellularData';           title='Сотовая связь' },
    @{ id='appDiagnostics';         title='Диагностика других программ' },
    # Эти категории Windows завела позже: ИИ-модели системы, ключи доступа,
    # периферия. Раньше «Досье» их просто не показывало.
    @{ id='systemAIModels';         title='ИИ-модели Windows' },
    @{ id='passkeys';               title='Ключи доступа (passkeys)' },
    @{ id='passkeysEnumeration';    title='Перечень ключей доступа' },
    @{ id='bluetooth';              title='Bluetooth' },
    @{ id='usb';                    title='USB-устройства' },
    @{ id='serialCommunication';    title='COM-порты' },
    @{ id='wiFiDirect';             title='Wi-Fi Direct' },
    @{ id='wifiData';               title='Данные о сетях Wi-Fi' },
    @{ id='gazeInput';              title='Отслеживание взгляда' }
)

function ConvertTo-FriendlyAppName {
    param([string]$Key)
    if ($Key -match '#') {
        $p = $Key -replace '#','\'
        $leaf = Split-Path $p -Leaf
        if ($leaf) { return $leaf }
        return $Key
    }
    $i = $Key.IndexOf('_')
    if ($i -gt 0) { return $Key.Substring(0, $i) }
    return $Key
}

function Get-SpyReport {
    $caps = @(); $activeNow = 0; $week = 0
    $since7 = (Get-Date).AddDays(-7)
    foreach ($cap in $script:SpyCaps) {
        $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\' + $cap.id
        $global = Get-RegValue $root 'Value'
        $keys = @()
        if (Test-Path -LiteralPath $root) {
            foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                if ($k.PSChildName -eq 'NonPackaged') { $keys += @(Get-ChildItem -LiteralPath $k.PSPath -ErrorAction SilentlyContinue) }
                else { $keys += $k }
            }
        }
        $items = @()
        foreach ($k in $keys) {
            $start = 0L; $stop = 0L
            try {
                $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop
                if ($null -ne $p.LastUsedTimeStart) { $start = [long]$p.LastUsedTimeStart }
                if ($null -ne $p.LastUsedTimeStop)  { $stop  = [long]$p.LastUsedTimeStop }
            } catch { }
            if ($start -le 0 -and -not $SpyAll) { continue }
            $active = ($stop -le 0 -or $stop -lt $start)
            $lastTicks = [Math]::Max($start, $stop)
            $last = $null
            if ($lastTicks -gt 0) { try { $last = [DateTime]::FromFileTime($lastTicks) } catch { } }
            $never = ($null -eq $last)
            if ($never) { $last = [datetime]'1900-01-01' }
            $minutes = 0.0
            if (-not $active -and $stop -gt $start) { $minutes = [math]::Round(($stop - $start) / 600000000.0, 1) }
            if ($active -and -not $never) { $activeNow++ } else { $active = $false }
            if (-not $never -and $last -ge $since7) { $week++ }
            $rel = ($k.PSPath -replace '^.*\\ConsentStore\\', '')
            $allow = 'Allow'
            try { $vv = (Get-ItemProperty -LiteralPath $k.PSPath -Name 'Value' -ErrorAction Stop).Value; if ($vv) { $allow = "$vv" } } catch { }
            $items += @{ app = (ConvertTo-FriendlyAppName $k.PSChildName); key = $rel; value = $allow
                         last = $(if ($never) { '' } else { $last.ToString('yyyy-MM-dd HH:mm') })
                         minutes = $minutes; active = [bool]$active; never = [bool]$never
                         sort = $last.Ticks }
        }
        # один и тот же exe может числиться под несколькими ключами — оставляем самое свежее
        $seen = @{}; $dedup = @()
        foreach ($it in @($items | Sort-Object { $_.sort } -Descending)) {
            $k = $it.app.ToLowerInvariant()
            if ($seen.ContainsKey($k)) {
                if ($it.minutes -gt $dedup[$seen[$k]].minutes) { $dedup[$seen[$k]].minutes = $it.minutes }
                continue
            }
            $seen[$k] = $dedup.Count; $dedup += $it
        }
        $items = @($dedup | Select-Object -First 40)
        foreach ($it in $items) { $it.Remove('sort') }
        $caps += @{ id = $cap.id; title = $cap.title
                    global = $(if ("$global") { "$global" } else { 'Allow' })
                    count = $items.Count; items = $items }
    }
    return @{ time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); activeNow = $activeNow; week = $week; caps = $caps }
}

# --- Накопленная история обращений к датчикам ------------------------------ #
# ConsentStore хранит только последнее использование, поэтому при каждом
# сборе досье и каждой проверке слежения новые метки складываются в журнал —
# из него строится график по дням.
function Update-SensorHistory {
    param($Report)
    $hist = Load-Json 'sensor-history.json'
    $known = @{}
    $events = @()
    if ($hist -and $hist.events) {
        foreach ($e in @($hist.events)) {
            $events += $e
            $known[("{0}|{1}|{2}" -f $e.cap, $e.app, $e.time)] = $true
        }
    }
    $new = @()
    foreach ($c in @($Report.caps)) {
        foreach ($it in @($c.items)) {
            $k = "{0}|{1}|{2}" -f $c.id, $it.app, $it.last
            if ($known.ContainsKey($k)) { continue }
            $ev = @{ cap = $c.id; app = $it.app; time = $it.last; minutes = $it.minutes }
            $events += $ev; $new += $ev; $known[$k] = $true
        }
    }
    if ($new.Count -gt 0 -or -not $hist) {
        if ($events.Count -gt 2000) { $events = @($events | Sort-Object { "$($_.time)" } | Select-Object -Last 2000) }
        Save-Json 'sensor-history.json' @{ events = $events; updated = (Get-Date).ToString('s') }
    }
    return ,$new
}

function Get-SensorDays {
    $hist = Load-Json 'sensor-history.json'
    $byDay = @{}
    if ($hist -and $hist.events) {
        foreach ($e in @($hist.events)) {
            $ds = "$($e.time)"
            if ($ds.Length -lt 10) { continue }
            $ds = $ds.Substring(0, 10)
            if (-not $byDay.ContainsKey($ds)) { $byDay[$ds] = @{ cam=0; mic=0; loc=0; other=0 } }
            switch ("$($e.cap)") {
                'webcam'     { $byDay[$ds].cam++ }
                'microphone' { $byDay[$ds].mic++ }
                'location'   { $byDay[$ds].loc++ }
                default      { $byDay[$ds].other++ }
            }
        }
    }
    $days = @()
    for ($i = 13; $i -ge 0; $i--) {
        $d = (Get-Date).Date.AddDays(-$i)
        $ds = $d.ToString('yyyy-MM-dd')
        $rec = if ($byDay.ContainsKey($ds)) { $byDay[$ds] } else { @{ cam=0; mic=0; loc=0; other=0 } }
        $days += @{ date = $d.ToString('dd.MM'); cam = $rec.cam; mic = $rec.mic; loc = $rec.loc; other = $rec.other }
    }
    return $days
}

# =========================================================================== #
#  ДОСЬЕ, часть 2: цифровой след на диске
# =========================================================================== #
function Get-FileCount { param([string]$P, [string]$Filter = '*')
    if (-not (Test-Path -LiteralPath $P)) { return 0 }
    return @(Get-ChildItem -LiteralPath $P -Filter $Filter -Force -ErrorAction SilentlyContinue).Count
}

# Журналы событий, где Windows хранит следы работы с программами и доступа к
# данным. Раньше «Цифровой след» их не видел, а записей там тысячи.
$script:FootprintLogs = @(
    'Microsoft-Windows-Privacy-Auditing/Operational',
    'Microsoft-Windows-UniversalTelemetryClient/Operational',
    'Microsoft-Windows-Application-Experience/Program-Telemetry',
    'Microsoft-Windows-Application-Experience/Program-Compatibility-Assistant',
    'Microsoft-Windows-Shell-Core/Operational'
)

function Get-Footprint {
    $items = New-Object System.Collections.Generic.List[object]
    $add = { param($id, $title, $what, $value, $mb, $count, $canWipe, $warn)
        $items.Add(@{ id=$id; title=$title; what=$what; value="$value"; mb=[double]$mb; count=[int]$count; canWipe=[bool]$canWipe; warn="$warn" }) }

    # Рекламный ID
    $adOn = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled'
    $adId = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Id'
    $adVal = if ($adId) { "$adId" } elseif ($adOn -eq 0) { 'выключен, ID стёрт' } else { 'нет' }
    & $add 'adid' 'Рекламный идентификатор' 'Уникальный ID, по которому рекламные сети узнают вас во всех приложениях.' $adVal 0 $(if ($adId) { 1 } else { 0 }) $([bool]$adId) ''

    # Постоянные ID машины
    $mg  = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Cryptography' 'MachineGuid'
    $sqm = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\SQMClient' 'MachineId'
    & $add 'machineid' 'Постоянные метки компьютера' 'MachineGuid и SQM MachineId — метки, которыми помечается телеметрия. Нужны системе, стереть нельзя.' ("$mg " + "$sqm").Trim() 0 2 $false ''

    # Номер устройства в учётной записи Microsoft (GDID). Лежит открытым текстом
    # шестнадцатеричным числом; Microsoft знает его в десятичном виде с «g:».
    # Простое стирание бесполезно — работа с ним на своей вкладке.
    $gdid = ConvertTo-Gdid "$(Get-RegValue 'HKCU:\SOFTWARE\Microsoft\IdentityCRL\ExtendedProperties' 'LID')"
    # «не передаётся» — той же проверкой, что и на вкладке номера: все три
    # службы, копии CDPUserSvc у пользователей, и только когда всё прочиталось.
    # Не прочиталось (Unknown) — так и сказано, а не «передаётся».
    $gdidTx = Get-GdidTransmitState
    $gdidWarn = $(if (-not $gdid -or $gdidTx.off) { '' } elseif ("$($gdidTx.state)" -eq 'Unknown') { 'не проверено' } else { 'передаётся' })
    & $add 'gdid' 'Номер устройства в учётной записи Microsoft (GDID)' 'По этому номеру Microsoft узнаёт компьютер даже через VPN и выдаёт его по запросу властей. Не передавать, сменить или запретить выдачу — на вкладке «Номер устройства».' $(if ($gdid) { $gdid } else { '—' }) 0 $(if ($gdid) { 1 } else { 0 }) $false $gdidWarn

    # История сетей
    $netNames = @()
    try {
        foreach ($k in @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles' -ErrorAction Stop)) {
            $n = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).ProfileName
            if ($n) { $netNames += "$n" }
        }
    } catch { }
    $netVal = if ($netNames.Count -gt 0) { (@($netNames | Select-Object -First 4) -join ', ') + $(if ($netNames.Count -gt 4) { ' …' } else { '' }) } else { 'пусто' }
    & $add 'networks' 'История сетей Wi-Fi и Ethernet' 'Список всех сетей, к которым подключался компьютер — по ним видно, где вы бывали. Пароли Wi-Fi не трогаются.' $netVal 0 $netNames.Count ($netNames.Count -gt 0) ''

    # История флешек и дисков
    $usb = @()
    try {
        foreach ($dev in @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR' -ErrorAction Stop)) {
            foreach ($inst in @(Get-ChildItem -LiteralPath $dev.PSPath -ErrorAction SilentlyContinue)) {
                $fn = (Get-ItemProperty -LiteralPath $inst.PSPath -ErrorAction SilentlyContinue).FriendlyName
                if ($fn -and $usb -notcontains "$fn") { $usb += "$fn" }
            }
        }
    } catch { }
    $usbVal = if ($usb.Count -gt 0) { (@($usb | Select-Object -First 3) -join ', ') + $(if ($usb.Count -gt 3) { ' …' } else { '' }) } else { 'пусто' }
    & $add 'usb' 'История подключённых флешек' 'Windows помнит каждую флешку и внешний диск. Запись системная, показываем для сведения.' $usbVal 0 $usb.Count $false ''

    # История активности (Timeline)
    $cdp = Join-Path $env:LOCALAPPDATA 'ConnectedDevicesPlatform'
    $cdpMb = Get-FolderSizeMB $cdp
    & $add 'activity' 'База истории активности' 'ActivitiesCache.db — какие программы и документы вы открывали, с точным временем.' ("{0} МБ" -f $cdpMb) $cdpMb (Get-FileCount $cdp) ($cdpMb -gt 0) ''

    # Недавние документы
    $recent = [Environment]::GetFolderPath('Recent')
    $recentCount = Get-FileCount $recent
    & $add 'recent' 'Недавние документы и папки' 'Ярлыки всего, что вы открывали, плюс списки переходов на панели задач.' ("{0} записей" -f $recentCount) (Get-FolderSizeMB $recent) $recentCount ($recentCount -gt 0) ''

    # Строка поиска Проводника
    $www = 0
    try { $k = Get-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery' -ErrorAction Stop; $www = @($k.GetValueNames() | Where-Object { $_ -ne 'MRUListEx' }).Count } catch { }
    & $add 'searchhistory' 'Что вы искали в Проводнике' 'История запросов в строке поиска Проводника.' ("{0} запросов" -f $www) 0 $www ($www -gt 0) ''

    # Адресная строка Проводника
    $tp = 0
    try { $k = Get-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths' -ErrorAction Stop; $tp = @($k.GetValueNames()).Count } catch { }
    & $add 'typedpaths' 'Введённые пути и адреса' 'Что вы вручную набирали в адресной строке Проводника.' ("{0} записей" -f $tp) 0 $tp ($tp -gt 0) ''

    # Буфер обмена
    $clipDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Clipboard'
    $clipMb = Get-FolderSizeMB $clipDir
    $clipOn = Get-RegValue 'HKCU:\Software\Microsoft\Clipboard' 'EnableClipboardHistory'
    & $add 'clipboard' 'История буфера обмена' 'Всё скопированное (Win+V) хранится на диске.' ($(if ($clipOn -eq 1) { 'включена, ' } else { 'выключена, ' }) + "$clipMb МБ") $clipMb (Get-FileCount $clipDir) ($clipMb -gt 0) ''

    # Отчёты об ошибках
    $wer1 = Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'
    $wer2 = Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'
    $wer3 = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER'
    $werMb = (Get-FolderSizeMB $wer1) + (Get-FolderSizeMB $wer2) + (Get-FolderSizeMB $wer3)
    $werCount = (Get-FileCount $wer1) + (Get-FileCount $wer2)
    & $add 'wer' 'Архив отчётов об ошибках' 'Дампы и отчёты о сбоях: содержат пути файлов, имена программ, куски памяти.' ("{0} отчётов, {1} МБ" -f $werCount, [math]::Round($werMb,1)) $werMb $werCount ($werMb -gt 0) ''

    # Словарь персонализации ввода
    $inp = Join-Path $env:APPDATA 'Microsoft\InputPersonalization'
    $inpMb = Get-FolderSizeMB $inp
    & $add 'inputpers' 'Личный словарь набора текста' 'Слова, собранные из вашего набора и рукописного ввода.' ("{0} МБ" -f $inpMb) $inpMb (Get-FileCount $inp) ($inpMb -gt 0) ''

    # Журналы Windows о работе с программами
    $evN = 0
    foreach ($lg in $script:FootprintLogs) {
        try { $evN += [int](Get-WinEvent -ListLog $lg -ErrorAction Stop).RecordCount } catch { }
    }
    & $add 'eventlogs' 'Журналы Windows о работе с программами' 'Какие программы обращались к данным и камере, что запускалось и что отправлял клиент телеметрии.' ("{0} записей" -f $evN) 0 $evN ($evN -gt 0) ''

    # Кэш DNS
    $dnsN = 0
    try { $dnsN = @(Get-DnsClientCache -ErrorAction Stop).Count } catch { }
    & $add 'dnscache' 'Кэш DNS (следы сайтов)' 'Адреса сайтов и служб, к которым недавно обращался компьютер.' ("{0} записей" -f $dnsN) 0 $dnsN ($dnsN -gt 0) ''

    $totalMb = 0.0; $wipeable = 0
    foreach ($it in $items) { $totalMb += [double]$it.mb; if ($it.canWipe) { $wipeable++ } }
    return @{ time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); items = $items.ToArray()
              totalMb = [math]::Round($totalMb, 1); wipeable = $wipeable }
}

function Invoke-FootprintWipe {
    param([string[]]$Ids)
    foreach ($id in $Ids) {
        switch ($id) {
            'adid' {
                if ($DryRun) { Write-Log '   [тест] рекламный ID — стереть'; break }
                Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 -Comment 'рекламный ID — выкл'
                # «Уже стёрт» — только когда значения и правда нет. Раньше так
                # называлась любая ошибка, и отказ в доступе выглядел как успех.
                $adKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
                switch (Remove-RegStatus $adKey 'Id') {
                    'removed' { Write-Log '   [+] рекламный идентификатор стёрт'; $script:Changes++ }
                    'absent'  { Write-Log '   [-] рекламного ID нет -- стирать нечего' }
                    default   { Write-Log '   [!] рекламный идентификатор не стёрт: Windows не дала'; $script:Failures++ }
                }
            }
            'networks' {
                if ($DryRun) { Write-Log '   [тест] история сетей — очистить'; break }
                $n = 0; $nf = 0
                foreach ($k in @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles' -ErrorAction SilentlyContinue)) {
                    try { Remove-Item -LiteralPath $k.PSPath -Recurse -Force -ErrorAction Stop; $n++ } catch { $nf++ }
                }
                foreach ($sig in @('Unmanaged','Managed')) {
                    foreach ($k in @(Get-ChildItem ('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\' + $sig) -ErrorAction SilentlyContinue)) {
                        try { Remove-Item -LiteralPath $k.PSPath -Recurse -Force -ErrorAction Stop } catch { $nf++ }
                    }
                }
                Write-Log ("   [+] история сетей очищена: {0} записей (пароли Wi-Fi не тронуты)" -f $n); $script:Changes++
                # раньше неудачи не считались, и «очищена» писалось при любом исходе
                if ($nf -gt 0) { Write-Log ("   [!] записей сетей, которые Windows не отдала: {0}" -f $nf); $script:Failures++ }
            }
            'activity' {
                # Службы держат базу открытой — на время чистки останавливаем,
                # потом запускаем обратно. Раньше оставались остановленными.
                $cdpRun = @(Get-Service -Name 'cdp*' -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' } | ForEach-Object { $_.Name })
                foreach ($n in $cdpRun) { if (-not $DryRun) { Stop-Service -Name $n -Force -ErrorAction SilentlyContinue } }
                $null = Clear-Folder (Join-Path $env:LOCALAPPDATA 'ConnectedDevicesPlatform') 'база истории активности'
                foreach ($n in $cdpRun) {
                    if ($DryRun) { continue }
                    try { Start-Service -Name $n -ErrorAction Stop }
                    catch { Write-Log ("   [i] служба {0} сейчас не запустилась -- запустится после перезагрузки" -f $n) }
                }
            }
            'recent' {
                $null = Clear-Folder ([Environment]::GetFolderPath('Recent')) 'недавние документы'
                if (-not $DryRun) {
                    try { Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs' -Recurse -Force -ErrorAction Stop; Write-Log '   [+] список RecentDocs в реестре очищен' } catch [System.Management.Automation.ItemNotFoundException] { } catch { Write-Log ("   [!] список RecentDocs в реестре не очищен -- {0}" -f $_.Exception.Message); $script:Failures++ }
                }
            }
            'searchhistory' {
                if ($DryRun) { Write-Log '   [тест] история поиска Проводника — очистить'; break }
                try { Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery' -Recurse -Force -ErrorAction Stop; Write-Log '   [+] история поиска Проводника очищена'; $script:Changes++ } catch { Write-Log '   [-] история поиска уже пуста' }
            }
            'typedpaths' {
                if ($DryRun) { Write-Log '   [тест] введённые пути — очистить'; break }
                try { Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths' -Recurse -Force -ErrorAction Stop; Write-Log '   [+] введённые пути очищены'; $script:Changes++ } catch { Write-Log '   [-] введённых путей нет' }
            }
            'clipboard' {
                $null = Clear-Folder (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Clipboard') 'история буфера обмена'
            }
            'wer' {
                $null = Clear-Folder (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive') 'архив отчётов об ошибках'
                $null = Clear-Folder (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue') 'очередь отчётов об ошибках'
                $null = Clear-Folder (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER') 'локальные отчёты об ошибках'
            }
            'inputpers' {
                $null = Clear-Folder (Join-Path $env:APPDATA 'Microsoft\InputPersonalization') 'личный словарь набора'
            }
            'dnscache' {
                if ($DryRun) { Write-Log '   [тест] кэш DNS — очистить'; break }
                try { Clear-DnsClientCache -ErrorAction Stop; Write-Log '   [+] кэш DNS очищен'; $script:Changes++ } catch { Write-Log '   [!] не удалось очистить кэш DNS' }
            }
            'eventlogs' {
                if ($DryRun) { Write-Log '   [тест] журналы Windows о работе с программами — очистить'; break }
                $cleared = 0
                foreach ($lg in $script:FootprintLogs) {
                    $null = & wevtutil.exe cl $lg 2>&1
                    if ($LASTEXITCODE -eq 0) { $cleared++ }
                }
                Write-Log ("   [+] очищено журналов: {0} из {1}" -f $cleared, $script:FootprintLogs.Count)
                if ($cleared -gt 0) { $script:Changes++ }
            }
            default { Write-Log ("   [-] неизвестный элемент следа: {0}" -f $id) }
        }
    }
}

# --- отозвать или вернуть доступ программы к датчику ---
# --------------------------------------------------------------------------- #
#  Ключ ConsentStore -> путь в реестре (F-02). Окно присылает ключ таким, каким
#  его отдал -Spy (относительный путь под ConsentStore). Годятся три вида:
#      <разрешение>                              разрешение целиком
#      <разрешение>\<Пакет>_<ИздательId>          приложение из Store
#      <разрешение>\NonPackaged\<C:#путь#app.exe> обычная программа: путь к exe,
#                                                  где «\» заменены на «#»
#  Разрешение — только из списка, который движок сам показывает ($SpyCaps);
#  пакет — семейство пакета; программа — путь с буквой диска. Не годятся:
#  пустые сегменты, «.» и «..», кавычки, управляющие знаки, «/», корни
#  реестра, пути вместо ключей, сетевые пути программ. Путь в реестре
#  собирается из постоянного корня и проверенных сегментов, а не дописыванием
#  присланной строки. Плохой ключ — $null, и ничего не пишется.
# --------------------------------------------------------------------------- #
$script:ConsentRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
function Get-ConsentKeyPath {
    param([string]$Key)
    if (-not $Key -or $Key.Length -gt 320) { return $null }
    if ($Key -match '[\x00-\x1f\x7f"/]' -or $Key.Contains('..')) { return $null }
    $seg = $Key.Split([char]'\')
    if ($seg.Count -lt 1 -or $seg.Count -gt 3) { return $null }
    foreach ($s in $seg) { if ($s.Length -eq 0 -or $s -eq '.') { return $null } }
    $cap = $null
    foreach ($c in $script:SpyCaps) { if ($c.id -ieq $seg[0]) { $cap = [string]$c.id } }
    if (-not $cap) { return $null }
    $path = $script:ConsentRoot + '\' + $cap
    if ($seg.Count -eq 2) {
        if ($seg[1] -ieq 'NonPackaged') { return $null }
        if ($seg[1] -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{1,99}_[A-Za-z0-9]{13}$') { return $null }
        $path += '\' + $seg[1]
    } elseif ($seg.Count -eq 3) {
        if ($seg[1] -ine 'NonPackaged') { return $null }
        if ($seg[2] -notmatch '^[A-Za-z]:(#[^#<>:"|?*\\/]+)+$') { return $null }
        foreach ($p in $seg[2].Substring(2).Split([char]'#')) { if ($p -eq '.') { return $null } }
        $path += '\NonPackaged\' + $seg[2]
    }
    return $path
}

# Разрешение датчика пишется через Set-Reg: журнал заранее, сверка
# записанного (прямая запись шла бы мимо отката). Ключ проверяет
# Get-ConsentKeyPath (выше) — независимо от проверок окна. Успех — только
# если и запись, и журнал отката прошли (счётчик ошибок не вырос), и в
# реестре читается ровно записанное значение. Ответ: @{ key; value; ok;
# error } — как и раньше; invalid — признак негодного запроса (для кода выхода).
function Invoke-SensorSet {
    param([string]$Key, [string]$Value)
    $r = @{ key = $Key; value = $Value; ok = $false }
    $root = Get-ConsentKeyPath $Key
    if (-not $root -or $Value -notin @('Allow', 'Deny')) {
        $r.error = 'недопустимое имя датчика или значение'; $r.invalid = $true; return $r
    }
    $failBefore = $script:Failures
    Set-Reg -Path $root -Name 'Value' -Value $Value -Type 'String' -Comment ("датчик {0}: {1}" -f $Key, $Value)
    Save-JournalEntries -Quiet
    $wrote = ($script:Failures -eq $failBefore)
    $now = "$(Get-RegValue $root 'Value')"
    $r.ok = $wrote -and ($now -eq $Value)
    if (-not $r.ok) {
        $r.error = $(if (-not $wrote) { 'Windows не дала изменить разрешение или журнал отката не пишется' }
                     else { 'записано, но в реестре читается другое: ' + $(if ($now) { $now } else { 'пусто' }) })
    }
    return $r
}

if ($SensorSet) {
    $r = Invoke-SensorSet $SensorKey $SensorValue
    $invalid = [bool]$r.invalid
    $r.Remove('invalid')
    Emit-Json $r
    # Код выхода согласован с ответом (W11P-003): 0 — только при ok; 1 —
    # негодный ключ или значение (ничего не делалось); 2 — запись, журнал
    # или сверка не прошли. Раньше здесь всегда был 0.
    exit $(if ($r.ok) { 0 } elseif ($invalid) { 1 } else { 2 })
}

# --- список отдельных настроек внутри модулей ---
if ($ListDefs) {
    $groups = @()
    foreach ($m in $script:ModuleOrder) {
        $mi = @($script:Defs | Where-Object { $_.M -eq $m })
        if ($mi.Count -eq 0) { continue }
        $groups += @{ module = $m; title = $script:ModuleTitles[$m]
                      items = @($mi | ForEach-Object { @{ id = $_.Id; name = $_.C; kind = $_.T
                                                          target = "$($_.P)"; valueName = "$($_.N)"
                                                          risk = (Get-DefRisk $_)
                                                          note = $(if ($script:DefNotes.ContainsKey("$($_.C)")) { $script:DefNotes["$($_.C)"] } else { '' }) } }) }
    }
    Emit-Json @{ groups = $groups }
    exit 0
}

if ($Spy) {
    $r = Get-SpyReport
    try { $null = Update-SensorHistory $r } catch { }
    $r.days = Get-SensorDays
    $r.sensorGuard = [bool](Get-ScheduledTask -TaskName $script:SensorTask -ErrorAction SilentlyContinue)
    $r.doh = Get-DohStatus
    Emit-Json $r
    exit 0
}

if ($Footprint) { Emit-Json (Get-Footprint); exit 0 }

if ($LeakTest) { Emit-Json (Invoke-LeakTest); exit 0 }

if ($FootprintWipe) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Стирание цифрового следа'
    if ($WipeItems.Count -eq 0) { Write-Log '   [-] ничего не выбрано' }
    else { Invoke-FootprintWipe -Ids $WipeItems }
    Emit-Json (Get-Footprint)
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  СЛЕЖЕНИЕ ЗА ДАТЧИКАМИ
#  Каждые 30 минут сверяем журнал ConsentStore. Новая программа получила
#  доступ к камере/микрофону/геолокации -> всплывающее уведомление.
# =========================================================================== #
$script:SensorCapNames = @{
    webcam='камеру'; microphone='микрофон'; location='местоположение'
    contacts='контакты'; userAccountInformation='данные учётной записи'; userDataTasks='задачи и планы'
}

if ($InstallSensorGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Слежение за датчиками'
    Write-SessionUserNote
    try {
        Ensure-DataDir
        $engineDst = Install-TaskEngine

        # закладываем текущий список программ как известный — без уведомлений
        $r0 = Get-SpyReport
        try { $null = Update-SensorHistory $r0 } catch { }
        $pairs = @()
        foreach ($c in @($r0.caps)) { foreach ($it in @($c.items)) { $pairs += ($c.id + '|' + $it.app) } }
        Save-Json 'sensor-apps.json' @{ pairs = $pairs; updated = (Get-Date).ToString('s') }

        $action = New-ScheduledTaskAction -Execute $script:PsExe -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $engineDst + '" -SensorGuard' + $script:DataArg)
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration (New-TimeSpan -Days 3650)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        $principal = New-ScheduledTaskPrincipal -UserId $script:RunAccount -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $script:SensorTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log '   [+] слежение включено: сверка журнала каждые 30 минут'
        Write-Log '   [+] новая программа получит доступ к камере, микрофону или геолокации — придёт уведомление'
        Write-Log ("   [+] сейчас программ в журнале: {0}" -f $pairs.Count)
        Write-Log '   [+] попутно накапливается история для графика на «Обзоре»'
    } catch { Write-Log "   [!] не удалось: $($_.Exception.Message)"; $failed = $true }
    Write-Log '###DONE###'
    # Код честный: регистрация задачи могла не пройти (раньше здесь всегда был 0).
    exit $(if ($failed) { 1 } else { 0 })
}

if ($InstallNetGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Слежение за сетью'
    Write-SessionUserNote
    try {
        Ensure-DataDir
        $engineDst = Install-TaskEngine
        # без журнала разрешённых соединений слежению не из чего брать программы
        if (-not (Get-MonitorEnabled)) { $null = Set-MonitorEnabled $true }
        # Известными считаем всех, кто выходил в сеть за неделю, и тех, у кого
        # соединение открыто прямо сейчас; ещё час слежение учится молча.
        $known = @{}
        foreach ($k in @((Get-NetAppsSince -Since (Get-Date).AddDays(-7)).Keys)) { $known[$k] = $true }
        if ($script:NetReadError) { Write-Log ("   [!] журнал безопасности не читается: {0} -- слежение будет пробовать снова, а на странице «Монитор» об этом сказано" -f $script:NetReadError) }
        foreach ($c in @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue)) {
            try { $p = (Get-Process -Id $c.OwningProcess -ErrorAction Stop).Path; if ($p) { $known[$p.ToLowerInvariant()] = $true } } catch { }
        }
        Save-Json 'net-apps.json' @{ known = @($known.Keys); recent = @(); learnUntil = (Get-Date).AddHours(1).ToString('s'); last = (Get-Date).ToString('s') }
        $action = New-ScheduledTaskAction -Execute $script:PsExe -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $engineDst + '" -NetGuard' + $script:DataArg)
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 3650)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        $principal = New-ScheduledTaskPrincipal -UserId $script:RunAccount -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $script:NetTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log '   [+] слежение включено: сверка журнала брандмауэра каждые 15 минут'
        Write-Log ("   [+] известных программ: {0}; первый час слежение учится и молчит" -f $known.Count)
        Write-Log '   [+] новая программа выйдет в сеть — придёт уведомление, а на странице «Монитор» её можно отрезать'
    } catch { Write-Log "   [!] не удалось: $($_.Exception.Message)"; $failed = $true }
    Write-Log '###DONE###'
    # Код честный: регистрация задачи могла не пройти (раньше здесь всегда был 0).
    exit $(if ($failed) { 1 } else { 0 })
}

if ($RemoveNetGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Слежение за сетью'
    $rt = Remove-OwnTask $script:NetTask 'слежение за сетью'
    Write-Log '   [i] журнал соединений остаётся — он нужен монитору; выключается кнопкой монитора.'
    Write-Log '###DONE###'
    exit $(if ($rt -eq 'failed') { 1 } else { 0 })
}

# периодический запуск из планировщика: тихо, без вывода
if ($NetGuard) { $null = Invoke-NetGuard; exit 0 }

if ($RemoveSensorGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Слежение за датчиками'
    $rt = Remove-OwnTask $script:SensorTask 'слежение за датчиками'
    Write-Log '###DONE###'
    exit $(if ($rt -eq 'failed') { 1 } else { 0 })
}

if ($SensorGuard) {
    # периодический запуск из планировщика: тихо, без вывода
    $r = Get-SpyReport
    try { $null = Update-SensorHistory $r } catch { }

    $saved = Load-Json 'sensor-apps.json'
    $first = ($null -eq $saved)
    $known = @{}
    if ($saved -and $saved.pairs) { foreach ($p in @($saved.pairs)) { $known["$p"] = $true } }

    $newApps = @()
    foreach ($c in @($r.caps)) {
        foreach ($it in @($c.items)) {
            $k = $c.id + '|' + $it.app
            if ($known.ContainsKey($k)) { continue }
            $known[$k] = $true
            if (-not $first) { $newApps += @{ cap = $c.id; app = $it.app; last = $it.last } }
        }
    }
    # не сохранилось — в следующий раз о тех же программах сообщим снова; это видно в журнале задачи
    try { Save-Json 'sensor-apps.json' @{ pairs = @($known.Keys); updated = (Get-Date).ToString('s') } }
    catch { Write-Log ("   [-] список известных программ не сохранился: {0}" -f $_.Exception.Message) }

    if ($newApps.Count -gt 0) {
        $parts = @()
        foreach ($n in @($newApps | Select-Object -First 3)) {
            $t = $script:SensorCapNames["$($n.cap)"]
            if (-not $t) { $t = "$($n.cap)" }
            $parts += ("{0} — {1}" -f $n.app, $t)
        }
        $msg = ($parts -join '; ')
        if ($newApps.Count -gt 3) { $msg += (' и ещё ' + ($newApps.Count - 3)) }
        Show-Toast 'Новая программа получила доступ к датчикам' $msg
        Write-Log ("новых программ с доступом к датчикам: {0} -- {1}" -f $newApps.Count, $msg)
    }
    exit 0
}

# =========================================================================== #
#  ПРЕДУСТАНОВЛЕННЫЕ ПРИЛОЖЕНИЯ
#  Список того, что можно безопасно удалить, и само удаление.
# =========================================================================== #

# Трогать нельзя никогда — без этого система ломается
$script:AppxProtected = @(
    'Microsoft.WindowsStore','Microsoft.DesktopAppInstaller','Microsoft.StorePurchaseApp',
    'Microsoft.VCLibs','Microsoft.NET','Microsoft.UI.Xaml','Microsoft.Services.Store',
    'Microsoft.WindowsTerminal','Microsoft.SecHealthUI','Microsoft.Windows.Photos.Addon',
    'MicrosoftWindows.Client','Microsoft.AAD','Microsoft.AccountsControl','Microsoft.Win32WebViewHost',
    'Microsoft.CredDialogHost','Microsoft.ECApp','Microsoft.LockApp','Microsoft.Windows.ShellExperienceHost',
    'Microsoft.Windows.StartMenuExperienceHost','Microsoft.Windows.SecureAssessmentBrowser',
    'Microsoft.WindowsAppRuntime','Microsoft.HEIFImageExtension','Microsoft.HEVCVideoExtension',
    'Microsoft.WebpImageExtension','Microsoft.RawImageExtension','Microsoft.VP9VideoExtensions',
    'Microsoft.WebMediaExtensions','Microsoft.MicrosoftEdge'
)

# Что обычно ставят без спроса — помечаем как «можно убрать»
$script:AppxBloat = @{
    'MicrosoftWindows.Client.WebExperience' = 'Виджеты и лента Microsoft Start'
    'Microsoft.BingNews'                = 'Новости MSN'
    'Microsoft.BingWeather'             = 'Погода MSN'
    'Microsoft.BingSearch'              = 'Поиск Bing в Пуске'
    'Microsoft.BingFinance'             = 'Финансы MSN'
    'Microsoft.BingSports'              = 'Спорт MSN'
    'Clipchamp.Clipchamp'               = 'Видеоредактор Clipchamp'
    'Microsoft.GamingApp'               = 'Приложение Xbox'
    'Microsoft.XboxGameOverlay'         = 'Игровая панель Xbox'
    'Microsoft.XboxGamingOverlay'       = 'Игровая панель Xbox'
    'Microsoft.XboxIdentityProvider'    = 'Вход Xbox'
    'Microsoft.XboxSpeechToTextOverlay' = 'Субтитры Xbox'
    'Microsoft.MicrosoftSolitaireCollection' = 'Коллекция пасьянсов'
    'Microsoft.MicrosoftOfficeHub'      = 'Промо Microsoft 365'
    'Microsoft.Office.OneNote'          = 'OneNote из магазина'
    'MicrosoftTeams'                    = 'Teams (личный)'
    'MSTeams'                           = 'Teams (личный)'
    'Microsoft.SkypeApp'                = 'Skype'
    'Microsoft.YourPhone'               = 'Связь с телефоном'
    'Microsoft.People'                  = 'Люди'
    'Microsoft.WindowsMaps'             = 'Карты'
    'Microsoft.WindowsFeedbackHub'      = 'Центр отзывов'
    'Microsoft.GetHelp'                 = 'Справка'
    'Microsoft.Getstarted'              = 'Советы'
    'Microsoft.Microsoft3DViewer'       = 'Просмотр 3D'
    'Microsoft.MixedReality.Portal'     = 'Портал смешанной реальности'
    'Microsoft.ZuneMusic'               = 'Медиапроигрыватель'
    'Microsoft.ZuneVideo'               = 'Фильмы и ТВ'
    'Microsoft.Todos'                   = 'To Do'
    'Microsoft.PowerAutomateDesktop'    = 'Power Automate'
    'Microsoft.Windows.DevHome'         = 'Dev Home'
    'MicrosoftCorporationII.QuickAssist'= 'Быстрая помощь'
    'Microsoft.Copilot'                 = 'Copilot'
    'Microsoft.Windows.Ai.Copilot.Provider' = 'Copilot (компонент)'
    'Microsoft.OutlookForWindows'       = 'Новый Outlook'
    'Microsoft.MicrosoftStickyNotes'    = 'Записки'
    'Microsoft.549981C3F5F10'           = 'Cortana'
}

# Исключения из защищённых префиксов: сама «оболочка» MicrosoftWindows.Client
# трогать нельзя, а вот доска виджетов внутри неё удаляется безболезненно —
# на Home это единственный способ убрать её совсем.
$script:AppxAllowed = @('MicrosoftWindows.Client.WebExperience')

function Test-AppxProtected {
    param([string]$Name)
    foreach ($a in $script:AppxAllowed) { if ($Name -eq $a) { return $false } }
    foreach ($p in $script:AppxProtected) { if ($Name -like ($p + '*')) { return $true } }
    return $false
}

function Get-AppxList {
    $list = @()
    $pkgs = @()
    try { $pkgs = @(Get-AppxPackage -ErrorAction Stop | Where-Object { -not $_.IsFramework }) } catch { }
    foreach ($p in $pkgs) {
        $name = [string]$p.Name
        if (Test-AppxProtected $name) { continue }
        $bloat = $script:AppxBloat.ContainsKey($name)
        $title = if ($bloat) { $script:AppxBloat[$name] } else { $name }
        $list += @{ name = $name; title = $title; publisher = [string]$p.Publisher
                    version = [string]$p.Version; bloat = [bool]$bloat
                    system = [bool]($p.SignatureKind -eq 'System') }
    }
    return @($list | Sort-Object { -[int][bool]$_.bloat }, { $_.title })
}

if ($ListApps) {
    $appList = @(Get-AppxList)      # через переменную — иначе один элемент уедет объектом
    Emit-Json @{ apps = $appList; time = (Get-Date).ToString('yyyy-MM-dd HH:mm') }
    exit 0
}

if ($RemoveApps) {
    Write-Section 'Удаление предустановленных приложений'
    if ($AppItems.Count -eq 0) { Write-Log '   [-] ничего не выбрано'; Write-Log '###DONE###'; exit 0 }
    $done = 0
    foreach ($name in $AppItems) {
        if (Test-AppxProtected $name) { Write-Log ("   [-] {0} — системный компонент, пропущен" -f $name); continue }
        if ($DryRun) { Write-Log ("   [тест] {0} — будет удалён" -f $name); continue }
        $pkgs = @(Get-AppxPackage -Name $name -ErrorAction SilentlyContinue)
        if ($pkgs.Count -eq 0) { Write-Log ("   [-] {0} — не найден" -f $name); continue }
        foreach ($p in $pkgs) {
            try {
                Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop
                Write-Log ("   [+] удалён: {0}" -f $name); $done++; $script:Changes++
            } catch { Write-Log ("   [!] {0} -- {1}" -f $name, $_.Exception.Message); $script:Failures++ }
        }
        if ($AllUsers -and (Test-Admin)) {
            try {
                $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $name })
                foreach ($pp in $prov) {
                    Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null
                    Write-Log ("   [+] больше не ставится новым пользователям: {0}" -f $name)
                }
            } catch {
                # раньше молча: приложение удалялось у вас, но возвращалось каждому новому пользователю
                Write-Log ("   [!] {0} -- для новых пользователей не убрано: {1}" -f $name, $_.Exception.Message); $script:Failures++
            }
        }
    }
    Write-Log ("   удалено приложений: {0}" -f $done)
    Emit-Json @{ removed = $done }
    Write-Log '###DONE###'
    # 2 — дошёл до конца, но не всё прошло (окно пишет «Готово, с ошибками»); раньше всегда 0
    exit $(if ($script:Failures -gt 0) { 2 } else { 0 })
}

if ($CleanJunk) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Emit-Json @{ error='нужны права администратора' }; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Уборка за старыми версиями'
    $before = @(Find-JunkValues).Count
    $gone = Remove-JunkValues
    if ($before -eq 0) { Write-Log '   [-] мусорных параметров нет' }
    Emit-Json @{ found = $before; removed = $gone }
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  РЕЗЕРВНЫЕ КОПИИ: показать и вернуть
#  Копии .reg программа делала и раньше, но импортировать их приходилось
#  руками. Теперь круг замкнут: снимок -> откат по журналу -> импорт копии.
# =========================================================================== #
function Get-BackupList {
    # Первым — защищённое хранилище (W11P-005): копия оттуда и копия той же
    # папки на рабочем столе — одна копия, показывается защищённая
    $roots = @(Get-BackupStoreDir)
    if ($BackupRoot) { $roots += $BackupRoot }
    $roots += [Environment]::GetFolderPath('Desktop')
    $roots += $script:DataDir
    $seen = @{}
    $names = @{}
    $list = @()
    foreach ($root in $roots) {
        if (-not $root -or $seen.ContainsKey($root) -or -not (Test-Path -LiteralPath $root)) { continue }
        $seen[$root] = $true
        foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -Filter 'Win11Privacy-Backup-*' -ErrorAction SilentlyContinue)) {
            if ($names.ContainsKey($dir.Name)) { continue }
            $files = @(Get-ChildItem -LiteralPath $dir.FullName -File -Filter '*.reg' -ErrorAction SilentlyContinue)
            if ($files.Count -eq 0) { continue }
            $names[$dir.Name] = $true
            $size = 0
            foreach ($f in $files) { $size += $f.Length }
            $list += @{ path = $dir.FullName; name = $dir.Name
                        when = $dir.CreationTime.ToString('yyyy-MM-dd HH:mm')
                        branches = $files.Count; kb = [math]::Round($size / 1KB, 1)
                        signed = (Test-Path -LiteralPath (Join-Path $dir.FullName 'backup-sig.json'))
                        protected = ($root -eq (Get-BackupStoreDir)) }
        }
    }
    return @($list | Sort-Object { $_.when } -Descending)
}

# Копии, сделанные этой версией и новее, подписаны списком версии 2. Список
# версии 1 для такой копии — признак подмены (понижение формата, чтобы
# убрать из копии файл вместе со строкой списка): имя папки с датой входит в
# подпись каждого файла, и подделать его нельзя.
$script:BackupV2Since = '20261115'
function Test-BackupV1Allowed {
    param([string]$Leaf)
    if (Test-Path -LiteralPath (Join-Path (Get-BackupStoreDir) $Leaf)) { return $false }
    $m = [regex]::Match($Leaf, '^Win11Privacy-Backup-(\d{8})-\d{6}')
    if (-not $m.Success) { return $false }
    return ($m.Groups[1].Value -lt $script:BackupV2Since)
}

# --------------------------------------------------------------------------- #
#  Возврат из резервной копии (W11P-001). Папку копии на рабочем столе может
#  переписать любая программа пользователя, а импорт идёт с правами
#  администратора. Порядок:
#    1. список подписей (backup-sig.json) разбирается строгим разбором — без
#       повторов полей, только ожидаемые поля и имена файлов; у версии 2
#       сверяется подпись самого списка и имя папки;
#    2. в папке должны быть ровно файлы из списка: лишний .reg, ссылка или
#       недостающий файл — копия не импортируется вовсе;
#    3. каждый файл читается один раз в память, подпись сверяется на этих
#       байтах, проверяется содержимое (целая выгрузка reg.exe, ветка из тех,
#       что выгружает программа, без удалений и разделов вне ветки), и эти же
#       байты пишутся в рабочую папку внутри защищённого корня;
#    4. только если проверены все файлы — импорт. Перед импортом каждого файла
#       он открывается без права записи для других, подпись сверяется ещё раз,
#       и reg.exe читает файл, пока он открыт: проверенные байты — ровно те,
#       что импортируются.
#  Любая несостыковка — отказ целиком, а не «всё, кроме подозрительного»:
#  частично подменённая копия не возвращает в реестр ничего.
# --------------------------------------------------------------------------- #
function Read-BackupManifest {
    param([string]$Dir)
    $mf = Join-Path $Dir $script:BackupManifestName
    $item = Get-Item -LiteralPath $mf -Force -ErrorAction SilentlyContinue
    if ($null -eq $item -or $item.PSIsContainer) { throw 'копия не подписана (её сделала прежняя версия или подпись удалена) -- программа её не импортирует; при необходимости откройте нужный .reg вручную' }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'список подписей копии -- ссылка' }
    if ($item.Length -gt 1MB) { throw 'список подписей копии слишком большой' }
    $bytes = [IO.File]::ReadAllBytes($mf)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $bytes = [byte[]]($bytes[3..($bytes.Length - 1)]) }
    foreach ($b in $bytes) {
        if (($b -gt 0x7E) -or (($b -lt 0x20) -and ($b -ne 0x09) -and ($b -ne 0x0A) -and ($b -ne 0x0D))) { throw 'список подписей копии повреждён' }
    }
    try { $m = ConvertFrom-EngineRequest ([Text.Encoding]::ASCII.GetString($bytes)) }
    catch { throw ('список подписей копии не читается: ' + $_.Exception.Message) }
    foreach ($k in @($m.Keys)) { if (@('version', 'files', 'folder', 'sig') -cnotcontains $k) { throw ('в списке подписей лишнее поле: ' + $k) } }
    $ver = $m['version']
    if ($ver -isnot [int] -or ($ver -ne 1 -and $ver -ne 2)) { throw 'неизвестная версия списка подписей' }
    if ($m['files'] -isnot [hashtable] -or $m['files'].Count -eq 0) { throw 'в списке подписей нет файлов' }
    $files = @{}
    foreach ($n in @($m['files'].Keys)) {
        $s = $m['files'][$n]
        if ([string]$n -cnotmatch $script:BackupFileRx) { throw ('недопустимое имя файла в списке подписей: ' + $n) }
        if ($s -isnot [string] -or $s -cnotmatch '^[0-9a-f]{64}$') { throw ('недопустимая подпись в списке: ' + $n) }
        $files[[string]$n] = $s
    }
    $leaf = Split-Path $Dir -Leaf
    if ($ver -eq 2) {
        if ($m['folder'] -isnot [string] -or $m['folder'] -ine $leaf) { throw 'список подписей от другой папки копии' }
        if ($m['sig'] -isnot [string] -or $m['sig'] -cne (Get-BackupManifestSig $leaf $files)) { throw 'подпись списка файлов не сходится -- список изменён' }
    } elseif ($m.ContainsKey('folder') -or $m.ContainsKey('sig')) { throw 'у списка версии 1 не бывает этих полей' }
    elseif (-not (Test-BackupV1Allowed $leaf)) { throw 'список подписей прежнего вида у копии, сделанной этой версией программы, -- подмена' }
    return @{ version = $ver; files = $files }
}

# Ветки, которые программа выгружает в копии (из всех модулей), в виде
# заголовков .reg: только их и возвращает импорт
function Get-BackupAllowedBranches {
    $set = @{}
    foreach ($d in $script:Defs) {
        if ($script:RegTypes -notcontains $d.T) { continue }
        $full = ([string]$d.P -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKCU:\\', 'HKEY_CURRENT_USER\').TrimEnd('\')
        $set[$full.ToLowerInvariant()] = $true
    }
    return $set
}

# Содержимое .reg перед импортом: целая выгрузка reg.exe (UTF-16 с меткой,
# заголовок, законченная последняя запись), первый раздел — ветка из тех, что
# выгружает программа, остальные разделы — внутри неё, удалений («[-…]») нет.
# Пустая строка — годится, иначе — почему нет.
function Test-RegImportContent {
    param([byte[]]$Bytes, [hashtable]$Allowed)
    if ($Bytes.Length -lt 4 -or $Bytes[0] -ne 0xFF -or $Bytes[1] -ne 0xFE -or ($Bytes.Length % 2) -ne 0) { return 'файл не в том виде, в каком его пишет reg.exe (UTF-16)' }
    $t = [Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2)
    if (-not $t.StartsWith("Windows Registry Editor Version 5.00`r`n`r`n[", [StringComparison]::Ordinal)) { return 'в начале файла нет заголовка выгрузки' }
    if (-not $t.EndsWith("`r`n`r`n")) { return 'файл оборван: последняя запись не закончена' }
    $branch = $null
    foreach ($line in $t.Split([string[]]@("`r`n"), [StringSplitOptions]::None)) {
        if (-not $line.StartsWith('[')) { continue }
        if (-not $line.EndsWith(']')) { return 'непонятная строка раздела' }
        $key = $line.Substring(1, $line.Length - 2)
        if ($key.StartsWith('-')) { return 'в копии есть удаление раздела' }
        $low = $key.ToLowerInvariant()
        if ($null -eq $branch) {
            if (-not $Allowed.ContainsKey($low)) { return ('ветка не из тех, что выгружает программа: ' + $key) }
            $branch = $low
        } elseif ($low -ne $branch -and -not $low.StartsWith($branch + '\')) { return ('раздел вне выгруженной ветки: ' + $key) }
    }
    if ($null -eq $branch) { return 'в файле нет ни одного раздела' }
    return ''
}

# --------------------------------------------------------------------------- #
#  Сверка после импорта (T-3). reg.exe import неделим только на словах: он
#  пишет значения по одному, и код 0 ещё не значит, что в реестре теперь то,
#  что в копии (значение мог тут же переписать кто-то другой, часть могла не
#  записаться). Поэтому после импорта ветка выгружается заново тем же
#  reg.exe и сравнивается с файлом копии: каждый раздел копии есть, каждое
#  значение — с теми же данными и того же вида (текст значения у reg.exe
#  включает вид: dword:, hex(2): …). Значения, которых в копии не было,
#  остаются — reg.exe import ничего не удаляет, и это не ошибка сверки.
# --------------------------------------------------------------------------- #
# Выгрузка reg.exe (текст) → @{ раздел (строчными) → @{ имя значения
# (строчными) → данные } }. Строки, продолженные «\», склеиваются; имя
# значения — в кавычках с «\"» и «\\» внутри, «@» — значение по умолчанию.
# Строка, которая не начинается ни с «[», ни с «"», ни с «@», — продолжение
# прежнего значения (перевод строки внутри строкового значения): так её
# прочитают обе стороны сверки одинаково.
function ConvertFrom-RegExportText {
    param([string]$Text)
    $map = @{}
    $cur = $null; $name = $null; $data = $null; $cont = $false
    $flush = { if ($null -ne $cur -and $null -ne $name) { $map[$cur][$name] = $data } }
    foreach ($line in $Text.Split([string[]]@("`r`n"), [StringSplitOptions]::None)) {
        if ($cont) {
            $piece = $line.TrimStart()
            if ($piece.EndsWith('\')) { $data += $piece.Substring(0, $piece.Length - 1) } else { $data += $piece; $cont = $false }
            continue
        }
        if ($line.StartsWith('[') -and $line.EndsWith(']')) {
            & $flush; $name = $null
            $cur = $line.Substring(1, $line.Length - 2).ToLowerInvariant()
            if (-not $map.ContainsKey($cur)) { $map[$cur] = @{} }
            continue
        }
        if ($null -eq $cur -or $line -eq '') { continue }
        $rest = $null
        if ($line.StartsWith('@=')) { & $flush; $name = '@'; $rest = $line.Substring(2) }
        elseif ($line.StartsWith('"')) {
            $sb = New-Object System.Text.StringBuilder
            $i = 1; $closed = $false
            while ($i -lt $line.Length) {
                $c = $line[$i]
                if ($c -eq '\' -and $i + 1 -lt $line.Length) { $null = $sb.Append($line[$i + 1]); $i += 2; continue }
                if ($c -eq '"') { $closed = $true; break }
                $null = $sb.Append($c); $i++
            }
            if ($closed -and $i + 1 -lt $line.Length -and $line[$i + 1] -eq '=') {
                & $flush; $name = $sb.ToString().ToLowerInvariant(); $rest = $line.Substring($i + 2)
            }
        }
        if ($null -eq $rest) {
            # продолжение строкового значения с переводом строки внутри
            if ($null -ne $name) { $data += "`n" + $line }
            continue
        }
        if ($rest.EndsWith('\')) { $data = $rest.Substring(0, $rest.Length - 1); $cont = $true } else { $data = $rest }
    }
    & $flush
    return $map
}

# Первый раздел файла копии — сама ветка, как её записал reg.exe
function Get-RegFileBranch {
    param([byte[]]$Bytes)
    $t = [Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2)
    foreach ($line in $t.Split([string[]]@("`r`n"), [StringSplitOptions]::None)) {
        if ($line.StartsWith('[') -and $line.EndsWith(']')) { return $line.Substring(1, $line.Length - 2) }
    }
    return ''
}

# Ветка копии (HKEY_LOCAL_MACHINE\…) → путь PowerShell (HKLM:\…) для New-RegBackup
function ConvertTo-PsRegPath {
    param([string]$Branch)
    if ($Branch -match '^HKEY_LOCAL_MACHINE\\(.+)$') { return ('HKLM:\' + $Matches[1]) }
    if ($Branch -match '^HKEY_CURRENT_USER\\(.+)$') { return ('HKCU:\' + $Matches[1]) }
    return ''
}

# После импорта: ветка выгружается заново (в ту же защищённую рабочую
# папку) и сравнивается с копией. state: restored — всё из копии на месте;
# differs — чего-то нет или данные другие (missing — сколько); unverified —
# выгрузить ветку заново не вышло, сверить не с чем.
function Test-RegImported {
    param([byte[]]$Bytes, [string]$Work, [string]$Name)
    $out = @{ state = 'unverified'; missing = 0; error = '' }
    try {
        $branch = Get-RegFileBranch $Bytes
        if (-not $branch) { $out.error = 'в копии нет раздела'; return $out }
        $native = ($branch -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM\' -replace '^HKEY_CURRENT_USER\\', 'HKCU\')
        $file = Join-Path $Work ('verify-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '-' + $Name)
        $why = Export-RegKey $native $file
        if ($why) { $out.error = ("ветка не выгрузилась для сверки: {0}" -f $why); return $out }
        $after = [IO.File]::ReadAllBytes($file)
        try { [IO.File]::Delete($file) } catch { }
        $want = ConvertFrom-RegExportText ([Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2))
        $now = ConvertFrom-RegExportText ([Text.Encoding]::Unicode.GetString($after, 2, $after.Length - 2))
        $miss = 0
        foreach ($k in @($want.Keys)) {
            if (-not $now.ContainsKey($k)) { $miss += [Math]::Max(1, $want[$k].Count); continue }
            foreach ($v in @($want[$k].Keys)) {
                if (-not $now[$k].ContainsKey($v) -or [string]$now[$k][$v] -cne [string]$want[$k][$v]) { $miss++ }
            }
        }
        $out.missing = $miss
        $out.state = $(if ($miss -eq 0) { 'restored' } else { 'differs' })
        return $out
    } catch { $out.state = 'unverified'; $out.error = "$($_.Exception.Message)"; return $out }
}

# --------------------------------------------------------------------------- #
#  Восстановление из копии по шагам (T-3). Сделать импорт неделимым нельзя
#  (у reg.exe import нет транзакции, и изображать её программа не будет),
#  поэтому восстановление ведёт подписанную запись о своём ходе
#  (Write-OpRecord 'restore') и держит замок операции (Enter-OpLock):
#    Prepared          — копия проверена, состояние до восстановления
#                        сохранено (снимок — обычная подписанная копия в
#                        хранилище), запись на диске; реестр ещё не тронут;
#    InProgress        — идёт импорт: у каждого файла своя стадия (pending,
#                        importing — запись легла ДО запуска reg.exe,
#                        restored — импортирован и сверен, failed, unverified);
#    Restored          — все файлы импортированы и сверены: запись убирается;
#    PartiallyRestored — запуск дожил до конца, но вернулось не всё: запись
#                        остаётся, следующий запуск о ней скажет;
#    Failed            — не импортировано ничего, реестр не тронут: записи нет;
#    RecoveryRequired  — так её видит следующий запуск, если она осталась в
#                        InProgress, а замок свободен (процесс умер посередине),
#                        или в PartiallyRestored (Get-RestoreRecovery).
#  Сам по себе ничего не повторяется: ни следующий запуск, ни страж не
#  доделывают импорт без человека. Довести — снова выбрать ту же копию (её
#  импорт можно повторять: те же значения запишутся так же) или вернуть
#  снимок «до восстановления». Повтор после обрыва снимок не переснимает:
#  остаётся самый первый — состояние до первого незаконченного восстановления.
# --------------------------------------------------------------------------- #
$script:RestoreOp = 'restore'

# Незаконченное восстановление глазами окна и следующего запуска. state:
# none; InProgress — идёт сейчас (замок занят); RecoveryRequired — оборвалось
# посередине или вернулось не всё (recoveryRequired = $true); Interrupted —
# оборвалось до первого импорта (реестр не тронут); Untrusted / Unreadable —
# запись есть, но верить ей нельзя или она не читается.
function Get-RestoreRecovery {
    $r = Read-OpRecord $script:RestoreOp
    $o = [ordered]@{ state = 'none'; recoveryRequired = $false; folder = ''; path = ''; snapshot = ''; stage = ''; restored = 0; files = 0; started = ''; error = "$($r.error)" }
    if ($r.state -eq 'none') { return $o }
    if ($r.state -eq 'unreadable') { $o.state = 'Unreadable'; $o.recoveryRequired = $true; return $o }
    if ($r.state -eq 'untrusted') { $o.state = 'Untrusted'; $o.recoveryRequired = $true; return $o }
    $d = $r.data
    $o.folder = "$($d.folder)"; $o.path = "$($d.path)"; $o.snapshot = "$($d.snapshot)"; $o.stage = "$($d.state)"; $o.started = "$($d.started)"
    $o.files = @($d.files).Count
    $o.restored = @(@($d.files) | Where-Object { "$($_.state)" -eq 'restored' }).Count
    # закончено и сверено, только запись не убралась — незаконченного нет
    if ("$($d.state)" -eq 'Restored') { $o.state = 'none'; return $o }
    $running = Test-OpRunning $script:RestoreOp
    if ($running -eq $true) { $o.state = 'InProgress'; return $o }
    if ("$($d.state)" -eq 'Prepared') { $o.state = 'Interrupted'; return $o }
    $o.state = 'RecoveryRequired'; $o.recoveryRequired = $true
    return $o
}

function Restore-BackupFolder {
    param([string]$Path)
    $res = @{ restored = 0; failed = 0; refused = 0; error = ''; state = 'Failed'; snapshot = ''; unverified = 0; imported = 0; resumed = $false; files = @() }
    $work = $null
    $lock = $null
    $rec = $null
    $recWritten = $false
    try {
        $dirItem = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $dirItem.PSIsContainer -or ($dirItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'папка копии -- ссылка или не папка' }
        $folder = $dirItem.Name
        $man = Read-BackupManifest $dirItem.FullName

        # В папке — ровно файлы из подписанного списка
        $present = @{}
        foreach ($f in @(Get-ChildItem -LiteralPath $dirItem.FullName -Force -ErrorAction Stop)) {
            if ($f.Name -ieq $script:BackupManifestName -or $f.Name -notlike '*.reg') { continue }
            if ($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Write-Log ("   [!] {0} -- ссылка или папка вместо файла копии" -f $f.Name); $res.refused++; continue
            }
            if (-not $man.files.ContainsKey($f.Name)) {
                Write-Log ("   [!] {0} -- этого файла в подписанной копии не было" -f $f.Name); $res.refused++; continue
            }
            $present[$f.Name] = $f
        }
        foreach ($n in @($man.files.Keys)) {
            if (-not $present.ContainsKey($n)) { Write-Log ("   [!] {0} -- файла из подписанного списка нет в папке" -f $n); $res.refused++ }
        }
        if ($res.refused -gt 0) { throw 'копия изменена после создания -- не импортируется ничего' }

        # Проверка и перенос в защищённую рабочую папку — всех файлов до импорта
        Remove-StaleWorkDirs 'restore-'
        $work = New-SafeWorkDir 'restore-'
        $allowed = Get-BackupAllowedBranches
        $staged = New-Object System.Collections.Generic.List[object]
        foreach ($n in @($present.Keys | Sort-Object)) {
            $src = $present[$n]
            if ($src.Length -gt 64MB) { Write-Log ("   [!] {0} -- слишком большой файл" -f $n); $res.refused++; continue }
            $bytes = [IO.File]::ReadAllBytes($src.FullName)
            if ((Get-BackupBytesSig $bytes $folder $n) -cne $man.files[$n]) { Write-Log ("   [!] {0} -- файл изменён после создания копии" -f $n); $res.refused++; continue }
            $why = Test-RegImportContent $bytes $allowed
            if ($why) { Write-Log ("   [!] {0} -- {1}" -f $n, $why); $res.refused++; continue }
            $dst = Join-Path $work $n
            $fs = [IO.File]::Open($dst, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush($true) } finally { $fs.Dispose() }
            $staged.Add(@{ name = $n; path = $dst; sig = $man.files[$n]; branch = (Get-RegFileBranch $bytes) })
        }
        if ($res.refused -gt 0) { throw 'в копии есть изменённые или чужие файлы -- не импортируется ничего' }

        # --- Отсюда меняется реестр (T-3): сначала замок и запись о ходе ---
        $lock = Enter-OpLock $script:RestoreOp
        if ($null -eq $lock) { throw 'идёт другое восстановление из копии -- дождитесь его конца; ничего не импортировано' }
        $prev = Read-OpRecord $script:RestoreOp
        if ($prev.state -eq 'unreadable') { throw ("запись о прошлом восстановлении сейчас не читается ({0}) -- ничего не импортировано, повторите позже" -f $prev.error) }
        if ($prev.state -eq 'untrusted') {
            $aside = Set-OpRecordAside $script:RestoreOp
            Write-Log ("   [!] запись о прошлом восстановлении недоверенная ({0}) -- по ней ничего не делается, она отложена как {1}" -f $prev.error, $aside)
        }
        $open = $null
        if ($prev.state -eq 'valid' -and "$($prev.data.state)" -in @('InProgress', 'PartiallyRestored')) { $open = $prev.data }
        if ($open) {
            $res.resumed = $true
            $res.snapshot = "$($open.snapshot)"
            Write-Log ("   [!] прошлое восстановление из копии не закончено ({0}: {1}, вернулось файлов {2} из {3}) -- реестр мог остаться восстановленным частично" -f "$($open.folder)", "$($open.state)",
                       @(@($open.files) | Where-Object { "$($_.state)" -eq 'restored' }).Count, @($open.files).Count)
            if ($res.snapshot) { Write-Log ("   [i] снимок «до восстановления» остаётся прежним (состояние до первой попытки): {0}" -f $res.snapshot) }
        } else {
            # Состояние до восстановления — обычной подписанной копией тех же
            # веток в хранилище (New-RegBackup). Не сохранилось — не
            # импортируем ничего: вернуться потом было бы не к чему.
            $keys = @($staged | ForEach-Object { ConvertTo-PsRegPath "$($_.branch)" } | Where-Object { $_ } | Select-Object -Unique)
            $existing = @($keys | Where-Object { Test-Path -LiteralPath $_ })
            if ($existing.Count -gt 0) {
                $sn = New-RegBackup $existing
                if ($sn.error -or -not $sn.dir -or [int]$sn.saved -lt $existing.Count) {
                    $why = $(if ($sn.error) { $sn.error } elseif (@($sn.missed).Count -gt 0) { @($sn.missed)[0] } else { 'выгрузилось не всё' })
                    throw ("состояние реестра до восстановления не сохранилось ({0}) -- ничего не импортировано: вернуться потом было бы не к чему" -f $why)
                }
                $res.snapshot = $sn.dir
                Write-Log ("   [+] состояние до восстановления сохранено: {0}" -f $sn.dir)
            } else { Write-Log '   [i] веток этой копии сейчас в реестре нет -- сохранять до восстановления нечего' }
        }
        $rec = [ordered]@{
            state = 'Prepared'; folder = $folder; path = $dirItem.FullName; snapshot = $res.snapshot
            started = (Get-Date).ToString('s'); attempt = $(if ($open) { [int]"0$($open.attempt)" + 1 } else { 1 })
            previous = $(if ($open -and "$($open.path)" -ine $dirItem.FullName) { "$($open.path)" } else { '' })
            files = @(foreach ($s in $staged) { [ordered]@{ name = "$($s.name)"; branch = "$($s.branch)"; state = 'pending' } })
        }
        Write-OpRecord $script:RestoreOp $rec
        $recWritten = $true

        $i = -1
        foreach ($s in $staged) {
            $i++
            # стадия файла — на диск ДО запуска reg.exe: оборвись импорт, запись
            # скажет, какой файл мог остаться записанным наполовину
            $rec.files[$i].state = 'importing'; $rec.state = 'InProgress'
            Write-OpRecord $script:RestoreOp $rec
            # Файл открыт без права записи для других, пока reg.exe его читает:
            # подпись, сверенная здесь, — подпись импортируемых байтов
            $fs = [IO.File]::Open($s.path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                $ms = New-Object System.IO.MemoryStream
                $fs.CopyTo($ms)
                $b = $ms.ToArray()
                if ((Get-BackupBytesSig $b $folder $s.name) -cne $s.sig) {
                    Write-Log ("   [!] {0} -- копия в рабочей папке не сходится с подписью" -f $s.name); $res.refused++
                    $rec.files[$i].state = 'refused'
                } else {
                    $r = Invoke-RegExe ('import "{0}"' -f $s.path)
                    $res.imported++
                    # «reg.exe закончил с кодом 0» — ещё не «в реестре то, что в копии»
                    $v = Test-RegImported $b $work $s.name
                    if ($r.code -eq 0 -and $v.state -eq 'restored') { Write-Log ("   [+] вернули и сверили: {0}" -f $s.name); $res.restored++; $rec.files[$i].state = 'restored' }
                    elseif ($r.code -ne 0) { Write-Log ("   [!] не удалось: {0} (код {1}: {2})" -f $s.name, $r.code, $r.error); $res.failed++; $rec.files[$i].state = 'failed' }
                    elseif ($v.state -eq 'unverified') { Write-Log ("   [!] {0} импортирован, но сверить его не удалось: {1}" -f $s.name, $v.error); $res.failed++; $res.unverified++; $rec.files[$i].state = 'unverified' }
                    else { Write-Log ("   [!] {0} импортирован, но в реестре не то, что в копии: значений не на месте {1}" -f $s.name, $v.missing); $res.failed++; $rec.files[$i].state = 'failed' }
                }
            } finally { $fs.Dispose() }
            Write-OpRecord $script:RestoreOp $rec
        }
        if ($res.restored -eq $staged.Count -and $res.failed -eq 0 -and $res.refused -eq 0) {
            $rec.state = 'Restored'
            Write-OpRecord $script:RestoreOp $rec
            if (-not (Remove-OpRecord $script:RestoreOp)) { Write-Log '   [i] запись о ходе восстановления не убралась (в ней итог «восстановлено»)' }
            $res.state = 'Restored'
        } elseif ($res.imported -eq 0 -and -not $res.resumed) {
            # не импортировано ничего, реестр не тронут: незаконченного нет
            $null = Remove-OpRecord $script:RestoreOp
            $res.state = 'Failed'
        } else {
            $rec.state = 'PartiallyRestored'
            Write-OpRecord $script:RestoreOp $rec
            $res.state = 'PartiallyRestored'
        }
        $recWritten = $false
    } catch {
        $res.error = $_.Exception.Message
        # Запуск жив, но оборвался посередине: итог — по тому, что успело
        # случиться. Не записалось — на диске остаётся InProgress, и следующий
        # запуск увидит RecoveryRequired.
        $partial = ($res.imported -gt 0 -or $res.resumed)
        $res.state = $(if ($partial) { 'PartiallyRestored' } else { 'Failed' })
        if ($recWritten -and $null -ne $rec) {
            try {
                if ($partial) { $rec.state = 'PartiallyRestored'; Write-OpRecord $script:RestoreOp $rec }
                else { $null = Remove-OpRecord $script:RestoreOp }
            } catch { }
        }
    }
    finally {
        if ($work -and (Test-Path -LiteralPath $work)) {
            $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
            Remove-TreeNoFollow $work $st
        }
        if ($null -ne $lock) { $lock.Dispose() }
    }
    if ($null -ne $rec) { $res.files = @(@($rec.files) | ForEach-Object { @{ name = "$($_.name)"; state = "$($_.state)" } }) }
    return $res
}

if ($ListBackups) {
    $bkList = @(Get-BackupList)
    # незаконченное восстановление — окно скажет о нём над списком копий
    $rcv = $null
    try { $rcv = Get-RestoreRecovery } catch { $rcv = [ordered]@{ state = 'Unreadable'; recoveryRequired = $true; error = "$($_.Exception.Message)" } }
    Emit-Json @{ items = $bkList; count = $bkList.Count; recovery = $rcv }
    exit 0
}

if ($RestoreBackup) {
    if (-not (Test-Admin)) { Emit-Json @{ error = 'нужны права администратора' }; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Восстановление из резервной копии'
    if (-not $BackupPath -or -not (Test-Path -LiteralPath $BackupPath)) {
        Write-Log '   [!] папка копии не найдена'
        Emit-Json @{ error = 'папка копии не найдена' }; Write-Log '###DONE###'; exit 1
    }
    $regFiles = @(Get-ChildItem -LiteralPath $BackupPath -File -Filter '*.reg' -ErrorAction SilentlyContinue)
    if ($regFiles.Count -eq 0) {
        Write-Log '   [!] в этой папке нет файлов .reg'
        Emit-Json @{ error = 'в папке нет файлов .reg' }; Write-Log '###DONE###'; exit 1
    }
    Write-Log ("   найдено файлов: {0}" -f $regFiles.Count)
    if ($DryRun) { foreach ($f in $regFiles) { Write-Log ("   [тест] {0}" -f $f.Name) }; Write-Log '###DONE###'; exit 0 }
    $rb = Restore-BackupFolder $BackupPath
    if ($rb.error) { Write-Log ("   [!] {0}" -f $rb.error); $script:Failures++ }
    $script:Changes += $rb.restored; $script:Failures += $rb.failed + $rb.refused
    Write-Log ("   возвращено и сверено веток: {0}" -f $rb.restored)
    if ($rb.failed -gt 0) { Write-Log ("   не удалось вернуть: {0}" -f $rb.failed) }
    if ($rb.refused -gt 0) { Write-Log ("   не импортировано из-за подписи: {0}" -f $rb.refused) }
    switch ($rb.state) {
        'Restored' { Write-Log '   Значения вернулись к состоянию на момент копии (сверено). Перезагрузите компьютер.' }
        'PartiallyRestored' {
            Write-Log '   [!] Восстановление не закончено: реестр восстановлен частично.'
            Write-Log '       Довести его -- снова выбрать эту же копию (повторный импорт пишет те же значения).'
            if ($rb.snapshot) { Write-Log ("       Вернуть как было до восстановления -- выбрать копию {0}" -f (Split-Path $rb.snapshot -Leaf)) }
        }
        default { Write-Log '   Реестр не изменён.' }
    }
    Emit-Json @{ restored = $rb.restored; failed = $rb.failed; refused = $rb.refused; error = $rb.error; path = $BackupPath
                 state = $rb.state; snapshot = $rb.snapshot; unverified = $rb.unverified; imported = $rb.imported; resumed = $rb.resumed; files = @($rb.files) }
    Write-Log '###DONE###'
    # 0 — всё импортировано и сверено (Restored); 2 — реестр восстановлен
    # частично (PartiallyRestored: что-то импортировано, но не всё вернулось
    # или не сверилось); 1 — не импортировано ничего, реестр не тронут
    # (отказ или ошибка до импорта). Раньше «вернулось не всё» давало 0, а
    # «reg.exe закончил с кодом 0» считалось «вернулось», без сверки.
    exit $(if ($rb.state -eq 'Restored') { 0 } elseif ($rb.state -eq 'PartiallyRestored') { 2 } else { 1 })
}

if ($ListStartup) {
    $stList = @(Get-StartupList)
    $stOn   = @($stList | Where-Object { $_.enabled })
    Emit-Json @{ items = $stList; total = $stList.Count; on = $stOn.Count
                 advise = @($stOn | Where-Object { $_.advise }).Count
                 time = (Get-Date).ToString('yyyy-MM-dd HH:mm') }
    exit 0
}

if ($StartupSet) {
    $wantOn = ($StartupValue -eq 'On')
    Write-Section $(if ($wantOn) { 'Автозагрузка: вернуть записи' } else { 'Автозагрузка: отключить записи' })
    if ($StartupItems.Count -eq 0) { Write-Log '   [-] ничего не выбрано'; Emit-Json @{ changed = 0 }; Write-Log '###DONE###'; exit 0 }
    $known = @{}
    foreach ($it in @(Get-StartupList)) { $known[[string]$it.id] = $it }
    $done = 0
    foreach ($id in $StartupItems) {
        $raw = ConvertFrom-StartupId $id
        if (-not $raw) { Write-Log ("   [!] непонятная запись: {0}" -f $id); $script:Failures++; continue }
        $it = $known[[string]$id]
        $label = $(if ($it) { [string]$it.name } else { $raw })
        if ($it -and ([bool]$it.enabled) -eq $wantOn) { Write-Log ("   [в] {0} -- уже так" -f $label); $script:Already++; continue }
        if ($DryRun) { Write-Log ("   [тест] {0}" -f $label); continue }
        # журнал раньше изменения: «как было» — на диск, потом переключение
        if (-not (Test-CanModify $label)) { break }
        $sj = @{ kind = 'startup'; id = $raw; name = $label
                 old = $(if ($wantOn) { 'Off' } else { 'On' }); newValue = $(if ($wantOn) { 'On' } else { 'Off' }) }
        if (-not (Write-AheadEntry $sj)) { Write-Log ("   [!] {0} -- не меняется: «как было» не легло в журнал отката" -f $label); $script:Failures++; break }
        $r = Set-StartupState $raw $wantOn
        if ($r.ok) {
            Write-Log ("   [+] {0} -- {1}" -f $label, $(if ($wantOn) { 'снова запускается' } else { 'больше не запускается' }))
            $done++; $script:Changes++
        } else {
            Undo-AheadEntry $sj
            Write-Log ("   [!] {0} -- {1}" -f $label, $r.error); $script:Failures++
        }
    }
    Save-JournalEntries
    Write-Log ("   изменено записей: {0}" -f $done)
    Emit-Json @{ changed = $done; failures = $script:Failures }
    Write-Log '###DONE###'
    # 2 — дошёл до конца, но не всё прошло (окно пишет «Готово, с ошибками»); раньше всегда 0
    exit $(if ($script:Failures -gt 0) { 2 } else { 0 })
}

# =========================================================================== #
#  ДОКАЗАТЕЛЬСТВО РЕЗУЛЬТАТА
#  Индекс говорит лишь «настройки на месте». Здесь собирается то, что можно
#  сравнить «до» и «после»: сколько событий уходило, сколько доменов молчит,
#  сколько сборщиков осталось включёнными и сколько телеметрии ждёт отправки.
# =========================================================================== #
# $Checked — уже посчитанные результаты Check-Def (их отдаёт -Audit). Без них
# снимок сам обходит все определения; с ними страница «Проверка» открывается
# вдвое быстрее, потому что 191 проверка выполняется один раз, а не дважды.
function Get-ProofSnapshot {
    param($Checked = $null, $Dns = $null)
    $ok = 0; $tot = 0; $etwOff = 0; $etwTotal = 0
    if ($null -ne $Checked) {
        foreach ($r in @($Checked)) {
            if ($r.module -in @('cleanup', 'startup', 'buffer', 'oem')) { continue }
            if ($r.blocked -or $r.na -or $r.absent) { continue }   # absent — программы нет на компьютере
            $tot++
            if ($r.ok) { $ok++ }
            if ($r.module -eq 'etw') { $etwTotal++; if ($r.ok) { $etwOff++ } }
        }
    } else {
        foreach ($d in $script:Defs) {
            if ($d.M -in @('cleanup', 'startup', 'buffer', 'oem')) { continue }
            $r = Check-Def $d
            $tot++
            if ($r.ok) { $ok++ }
            if ($d.M -eq 'etw') { $etwTotal++; if ($r.ok) { $etwOff++ } }
        }
    }
    $dnsEvidence = $(if ($null -ne $Dns) { @($Dns) } else { @(Get-DnsEvidence) })
    $buf = Get-BufferInfo
    $fw = @(Get-NetFirewallRule -Group $script:FwGroup -ErrorAction SilentlyContinue).Count
    $startOn = 0; $startBad = 0
    try {
        $stAll = @(Get-StartupList)
        $startOn  = @($stAll | Where-Object { $_.enabled }).Count
        $startBad = @($stAll | Where-Object { $_.enabled -and $_.advise }).Count
    } catch { }
    $base = Load-Json 'xray-baseline.json'
    $tasks = 0
    try {
        foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
            if (($t.TaskPath + $t.TaskName) -match 'Appraiser|Consolidator|UsbCeip|DmClient|QueueReporting|ProgramDataUpdater|KernelCeip|Sqm-Tasks|GatherNetworkInfo|Device Information') {
                if (-not (Test-TaskDisabled $t)) { $tasks++ }
            }
        }
    } catch { }
    return @{
        time       = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        ok         = $ok
        total      = $tot
        dnsBlocked = @($dnsEvidence | Where-Object { $_.blocked }).Count
        dnsOpen    = @($dnsEvidence | Where-Object { -not $_.blocked }).Count
        bufferMb   = $buf.mb
        bufferFiles= $buf.files
        fwRules    = $fw
        etwOff     = $etwOff
        etwTotal   = $etwTotal
        tasksLive  = $tasks
        startupOn  = $startOn
        startupBad = $startBad
        xrayPerDay = $(if ($base -and $base.perDay) { [int]$base.perDay } else { 0 })
        diagTrack  = $(try { [string](Get-Service DiagTrack -ErrorAction Stop).StartType } catch { 'нет' })
    }
}

if ($ProofSave) {
    $snap = Get-ProofSnapshot
    Save-Json 'proof-before.json' $snap
    Emit-Json $snap
    exit 0
}

if ($Proof) {
    $before = Load-Json 'proof-before.json'
    $after = Get-ProofSnapshot
    $xrayNow = 0
    $xr = Load-Json 'xray-last.json'
    if ($xr -and $xr.perDay) { $xrayNow = [int]$xr.perDay }
    Emit-Json @{ before = $before; after = $after; xrayNow = $xrayNow
                 has = [bool]$before }
    exit 0
}

# =========================================================================== #
#  САМОПРОВЕРКА: может ли программа реально менять настройки на этом ПК
# =========================================================================== #
# Пробная запись в реестр. Убирается ровно то, что создала сама проверка:
# своё значение (имя у каждого запуска своё — чужое «Probe» не затрётся) и
# ключи, которых до проверки не было, — если в них ничего не осталось.
# Раньше самопроверка стирала всю ветку Software\Win11Privacy со всем, что в
# ней лежало до неё.
function Test-RegWriteProbe {
    param([string]$Key)
    $res = @{ ok = $false; error = '' }
    $name = 'Probe-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    # верхний из ключей, которых нет (неизвестно — значит «есть»): удалить
    # потом можно только его и только пустым
    $created = Get-TopMissingKey $Key
    try {
        # New-Item -Force по существующему ключу пересоздал бы его пустым
        if ($created) { New-Item -Path $Key -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $Key -Name $name -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        $res.ok = ((Get-ItemProperty -LiteralPath $Key -Name $name -ErrorAction Stop).$name -eq 1)
    } catch { $res.error = $_.Exception.Message }
    if ((Get-RegRaw $Key $name).exists) {
        try { Remove-ItemProperty -LiteralPath $Key -Name $name -Force -ErrorAction Stop }
        catch { Write-Log ("   [!] пробное значение {0}\{1} не удалилось: {2}" -f $Key, $name, $_.Exception.Message) }
    }
    if ($created -and (Test-RegKeyExists $created) -and (Test-KeyTreeEmpty $created)) {
        try { Remove-Item -LiteralPath $created -Recurse -Force -ErrorAction Stop }
        catch { Write-Log ("   [!] пробный ключ {0} не удалился: {1}" -f $created, $_.Exception.Message) }
    }
    return $res
}

if ($SelfTest) {
    Write-Section 'Самопроверка: может ли программа менять настройки'
    $r = @{}
    $r.admin = Test-Admin
    Write-Log ("   пользователь          : {0}" -f $env:USERNAME)
    Write-Log ("   права администратора  : {0}" -f $(if ($r.admin) { 'ЕСТЬ' } else { 'НЕТ  <-- изменения невозможны' }))
    Write-Log ("   PowerShell            : {0}" -f $PSVersionTable.PSVersion)
    Write-Log ("   политика выполнения   : {0}" -f (Get-ExecutionPolicy))
    Write-Log ("   файл движка           : {0}" -f $PSCommandPath)
    Write-Log ''

    # --- реестр пользователя (HKCU) ---
    $p = Test-RegWriteProbe 'HKCU:\Software\Win11Privacy\SelfTest'
    $r.hkcu = [bool]$p.ok
    if ($p.error) { Write-Log ("   [!] {0}" -f $p.error) }
    Write-Log ("   [{0}] запись в реестр пользователя (HKCU)" -f $(if ($r.hkcu) { '+' } else { '!' }))

    # --- реестр системы (HKLM) ---
    $p = Test-RegWriteProbe 'HKLM:\SOFTWARE\Win11Privacy\SelfTest'
    $r.hklm = [bool]$p.ok
    if ($p.error) { Write-Log ("   [!] {0}" -f $p.error) }
    Write-Log ("   [{0}] запись в реестр системы (HKLM) — сюда идут политики" -f $(if ($r.hklm) { '+' } else { '!' }))

    # --- хранилище резервных копий ---
    # Копии лежат в ProgramData\Win11Privacy\backups (W11P-005): защищённый
    # корень и путь до него, само хранилище — не ссылка и без чужих прав.
    # Пробная выгрузка не делается: на рабочий стол движок больше не пишет.
    $r.backup = $false
    $store = Get-BackupStoreDir
    Write-Log ("   папка для копий       : {0}" -f $store)
    try {
        if (-not (Assert-SafeRoot)) { throw 'папка ProgramData\Win11Privacy не защищена' }
        if (Test-Path -LiteralPath $store) {
            if (-not (Test-ItemTrusted (Get-Item -LiteralPath $store -Force))) { throw 'хранилище копий не защищено (ссылка или чужие права)' }
        }
        $r.backup = $true
    } catch { Write-Log ("   [!] {0}" -f $_.Exception.Message) }
    Write-Log ("   [{0}] хранилище резервных копий" -f $(if ($r.backup) { '+' } else { '!' }))

    # --- службы, задачи, брандмауэр, hosts ---
    $r.services = $false
    try { $null = Get-Service -Name 'DiagTrack' -ErrorAction Stop; $r.services = $true } catch { }
    Write-Log ("   [{0}] доступ к службам" -f $(if ($r.services) { '+' } else { '-' }))

    $r.tasks = $false
    try { $null = Get-ScheduledTask -ErrorAction Stop | Select-Object -First 1; $r.tasks = $true } catch { }
    Write-Log ("   [{0}] доступ к планировщику задач" -f $(if ($r.tasks) { '+' } else { '!' }))

    $r.firewall = [bool](Get-Command New-NetFirewallRule -ErrorAction SilentlyContinue)
    Write-Log ("   [{0}] управление брандмауэром" -f $(if ($r.firewall) { '+' } else { '!' }))

    $r.hosts = $false
    try {
        $fs = [IO.File]::Open($script:HostsPath, 'Open', 'ReadWrite', 'ReadWrite')
        $fs.Close(); $r.hosts = $true
    } catch { Write-Log ("   [!] hosts: {0}" -f $_.Exception.Message) }
    Write-Log ("   [{0}] файл hosts доступен для записи" -f $(if ($r.hosts) { '+' } else { '!' }))

    Write-Log ''
    $bad = @()
    if (-not $r.admin)  { $bad += 'нет прав администратора' }
    if (-not $r.hklm)   { $bad += 'нельзя писать в реестр системы' }
    if (-not $r.backup) { $bad += 'хранилище резервных копий не защищено' }
    if ($bad.Count -eq 0) {
        Write-Log 'ИТОГ: всё работает — программа может применять настройки на этом компьютере.'
        Write-Log 'Если изменения всё равно не применяются, пришлите этот журнал целиком.'
    } else {
        Write-Log ('ИТОГ: мешает — ' + ($bad -join '; ') + '.')
        Write-Log 'Скорее всего программу блокирует антивирус или она запущена без прав администратора.'
    }
    Emit-Json $r
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  Audit
# =========================================================================== #
if ($Audit) {
    if ($Modules.Count -eq 0) { $Modules = $script:ModuleOrder }
    # Проверка идёт до полуминуты и раньше молчала до самого ответа: окно
    # показывало бегущую полосу, по которой не понять, идёт работа или нет.
    $planned = @($script:Defs | Where-Object { ($Modules -contains $_.M) -and ($SkipItems -notcontains $_.Id) })
    $script:AuditTotal = $planned.Count
    $script:AuditDone = 0
    $items = @()
    $oemInfo = $null
    $blockedSet = @{}
    $bj = Load-Json 'blocked.json'
    if ($bj -and $bj.ids) { foreach ($i in @($bj.ids)) { $blockedSet["$i"] = $true } }
    # Модули программ, которых на компьютере нет (то же Detect-Apps, по
    # которому окно гасит их строки в настройках): их пункты не входят ни в
    # общий итог, ни в счёт раздела, а окно такие разделы не показывает.
    # Раньше «Visual Studio Code 0 из 3» висел красным, хотя VS Code не было.
    # Если определить программы не удалось — не скрываем ничего: лишний
    # раздел на виду безопаснее, чем спрятанное несоответствие.
    $appAbsent = @{}
    if ($WithProof -or @($Modules | Where-Object { "$_" -like 'app_*' }).Count -gt 0) {
        try {
            foreach ($a in @(Detect-Apps)) { if (-not $a.found) { $appAbsent["$($a.id)"] = $true } }
        } catch {
            $appAbsent = @{}
            Write-Host ("[!] Не удалось определить установленные программы: " + $_.Exception.Message + " - разделы программ показаны все")
        }
    }
    foreach ($d in $script:Defs) {
        if ($Modules -notcontains $d.M) { continue }
        if ($SkipItems -contains $d.Id) { continue }
        $r = Check-Def $d
        $script:AuditDone++
        # интерфейс читает эти строки и показывает честный ход работы
        if ($script:AuditTotal -gt 0 -and ($script:AuditDone % 5 -eq 0 -or $script:AuditDone -eq $script:AuditTotal)) {
            Write-Host ("###PROGRESS### {0}/{1} {2}" -f $script:AuditDone, $script:AuditTotal, $script:ModuleTitles[$d.M])
        }
        $r.id = $d.Id
        $r.absent = [bool]$appAbsent.ContainsKey($d.M)
        # Windows не отдала этот параметр при применении — это не «не применено»
        # «нет на этой версии Windows» важнее записанного отказа: это причина
        # честнее и не зависит от того, что когда-то не отдалось
        $r.blocked = [bool]((-not $r.ok) -and (-not $r.na) -and (-not $r.absent) -and $blockedSet.ContainsKey($d.Id))
        if ($r.blocked) { $r.actual = 'Windows не разрешает' }
        if (-not $r.ContainsKey('na')) { $r.na = $false }
        $items += $r
    }
    if ($Modules -contains 'oem') {
        $oemInfo = Detect-Oem
        foreach ($it in $oemInfo.items) {
            $ok = ($it.state -match 'Disabled')
            $items += @{ module='oem'; name=("{0}: {1}" -f $(if ($it.type -eq 'svc') { 'служба' } else { 'задача' }), $it.display); ok=$ok; expected='Disabled'; actual=$it.state; absent=$false }
        }
    }
    $counted = @($items | Where-Object { (-not $_.blocked) -and (-not $_.na) -and (-not $_.absent) })
    $okCount = @($counted | Where-Object { $_.ok }).Count
    $blockedCount = @($items | Where-Object { $_.blocked }).Count
    $naCount = @($items | Where-Object { $_.na -and (-not $_.absent) }).Count
    $groups = @()
    foreach ($m in $script:ModuleOrder) {
        $mi = @($items | Where-Object { $_.module -eq $m })
        if ($mi.Count -eq 0) { continue }
        $mc = @($mi | Where-Object { (-not $_.blocked) -and (-not $_.na) -and (-not $_.absent) })
        # пункты раздела отсутствующей программы остаются в ответе (по ним
        # «Что изменится» и проверка отката сверяют значения), но раздел
        # помечен и в счёт не идёт
        $groups += @{ module=$m; title=$script:ModuleTitles[$m]; ok=@($mc | Where-Object { $_.ok }).Count; total=$mc.Count
                      blocked=@($mi | Where-Object { $_.blocked }).Count; absent=[bool]$appAbsent.ContainsKey($m); items=$mi }
    }
    $absentCount = @($groups | Where-Object { $_.absent }).Count
    $dnsList = @(Get-DnsEvidence)
    $result = @{
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); ok = $okCount; total = $counted.Count
        blocked = $blockedCount; notApplicable = $naCount; notInstalled = $absentCount; groups = $groups
        dns = $dnsList; buffer = (Get-BufferInfo); edition = (Get-Edition); doh = (Get-DohStatus)
        monitorEnabled = (Get-MonitorEnabled); hostsBlocked = (Test-HostsBlock)
        junk = @(Find-JunkValues).Count
    }
    # Доказательство результата в том же прогоне: интерфейсу больше не нужно
    # звать -Proof отдельно, а значит все проверки выполняются один раз.
    if ($WithProof) {
        $proofItems = New-Object System.Collections.Generic.List[object]
        foreach ($it in $items) { $proofItems.Add($it) }
        foreach ($d in $script:Defs) {
            if (($Modules -contains $d.M) -and ($SkipItems -notcontains $d.Id)) { continue }   # уже посчитан выше
            $pr = Check-Def $d
            $pr.absent = [bool]$appAbsent.ContainsKey($d.M)
            $proofItems.Add($pr)
        }
        $xr = Load-Json 'xray-last.json'
        $result.proof = @{
            before  = (Load-Json 'proof-before.json')
            after   = (Get-ProofSnapshot -Checked $proofItems.ToArray() -Dns $dnsList)
            has     = [bool](Load-Json 'proof-before.json')
            xrayNow = $(if ($xr -and $xr.perDay) { [int]$xr.perDay } else { 0 })
        }
    }
    Emit-Json $result
    exit 0
}

# =========================================================================== #
#  ОТКАТ ПО ЖУРНАЛУ
#  Возвращает каждый параметр реестра в то значение, которое было до нас.
# =========================================================================== #
# --------------------------------------------------------------------------- #
#  Другие пользователи и профиль по умолчанию. Настройки из HKCU касаются
#  только вошедшего. С -AllProfiles они ложатся и в кусты других профилей
#  этого компьютера, и в профиль Default — его копию получает каждый новый
#  пользователь. Не загруженный куст подключается на время записи.
# --------------------------------------------------------------------------- #
function Get-OtherProfiles {
    $me = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $out = New-Object System.Collections.Generic.List[object]
    $out.Add(@{ name = 'Default'; sid = ''; file = (Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT') })
    foreach ($p in @(Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue)) {
        if ($p.Special -or -not $p.LocalPath -or "$($p.SID)" -eq $me -or "$($p.SID)" -notlike 'S-1-5-21-*') { continue }
        $out.Add(@{ name = (Split-Path $p.LocalPath -Leaf); sid = "$($p.SID)"; file = (Join-Path $p.LocalPath 'NTUSER.DAT') })
    }
    return @($out | Where-Object { Test-Path -LiteralPath $_.file })
}

# Куст, оставшийся подключённым после оборванного запуска: процесс упал или
# его закрыли посреди записи. Такой профиль Windows при входе человека не
# загрузит и выдаст ему временный. В имени подключения — номер процесса
# движка; процесса с таким номером больше нет — куст отключается. Подключения
# идущего сейчас запуска (процесс жив) не трогаются.
function Get-HiveMountNames { return @([Microsoft.Win32.Registry]::Users.GetSubKeyNames()) }

function Clear-StaleHiveMounts {
    if ($script:StaleHivesChecked) { return }
    $script:StaleHivesChecked = $true
    $names = @()
    try { $names = @(Get-HiveMountNames) }
    catch { Write-Log ("   [!] список подключённых кустов не прочитался: {0}" -f $_.Exception.Message); return }
    foreach ($n in $names) {
        if ($n -notmatch '^W11P_(\d{1,7})_[0-9a-f]{6}$') { continue }
        if (Get-Process -Id ([int]$Matches[1]) -ErrorAction SilentlyContinue) { continue }
        $null = & reg.exe unload "HKU\$n" 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Log ("   [+] отключён куст профиля, оставшийся от оборванного запуска (HKU\{0})" -f $n) }
        else { Write-Log ("   [!] куст профиля от оборванного запуска (HKU\{0}) не отключился -- перезагрузите компьютер" -f $n); $script:Failures++ }
    }
}

# Выполняет $Body с корнем куста профиля. Вошедший пользователь — его куст уже
# загружен; иначе файл NTUSER.DAT подключается под временным именем и
# отключается обратно. В имени — номер этого процесса (см. Clear-StaleHiveMounts).
function Use-ProfileHive {
    param($Prof, [scriptblock]$Body)
    Clear-StaleHiveMounts
    if ($Prof.sid -and (Test-Path -LiteralPath ('Registry::HKEY_USERS\' + $Prof.sid))) {
        $null = & $Body ('Registry::HKEY_USERS\' + $Prof.sid); return $true
    }
    $mount = 'W11P_' + $PID + '_' + [guid]::NewGuid().ToString('N').Substring(0, 6)
    $null = & reg.exe load "HKU\$mount" "$($Prof.file)" 2>&1
    if ($LASTEXITCODE -ne 0) { return $false }
    $unloaded = $false
    try { $null = & $Body ('Registry::HKEY_USERS\' + $mount) }
    finally {
        # пока живы ссылки на ключи, куст не отключится
        for ($i = 0; $i -lt 10; $i++) {
            [gc]::Collect(); [gc]::WaitForPendingFinalizers()
            $null = & reg.exe unload "HKU\$mount" 2>&1
            if ($LASTEXITCODE -eq 0) { $unloaded = $true; break }
            Start-Sleep -Milliseconds 700
        }
        # Раньше неудача здесь проходила молча. А подключённый чужой куст —
        # это профиль, который Windows при входе этого человека не загрузит и
        # выдаст временный. После перезагрузки куст отключается сам.
        if (-not $unloaded) {
            Write-Log ("   [!] профиль {0}: файл NTUSER.DAT остался подключённым (HKU\{1}) -- перезагрузите компьютер, прежде чем этот пользователь войдёт в Windows" -f $Prof.name, $mount)
            $script:Failures++
        }
    }
    return $true
}

# $Only — вместо всех профилей взять ровно эти (по SID): так настройки
# пользователя доходят до того, кто вошёл в Windows, когда пароль
# администратора ввёл он, а работает движок от имени администратора.
function Apply-ProfilesHives {
    param([object[]]$Only)
    $defs = @($script:Defs | Where-Object { ($Modules -contains $_.M) -and ($SkipItems -notcontains $_.Id) -and
                                            ($script:RegTypes -contains $_.T) -and "$($_.P)" -like 'HKCU:\*' -and (Test-DefApplicable $_) })
    if ($defs.Count -eq 0) { return }
    $profiles = $(if ($null -ne $Only) { @($Only) } else { @(Get-OtherProfiles) })
    if ($profiles.Count -eq 0) { return }
    if ($null -eq $Only) { Write-Section 'Другие пользователи и профиль по умолчанию' }
    foreach ($pr in $profiles) {
        if ($DryRun) { Write-Log ("   [тест] профиль {0}: настроек {1}" -f $pr.name, $defs.Count); continue }
        if ($script:JournalFailed) { Write-Log ("   [!] профиль {0}: не меняется -- журнал отката сейчас не пишется" -f $pr.name); $script:Failures++; continue }
        $cnt = @{ changed = 0; failed = 0; refused = $false; notes = (New-Object System.Collections.Generic.List[string]) }
        $mounted = Use-ProfileHive $pr {
            param($root)
            # Сначала — что меняем и как было, всей пачкой на диск (журнал
            # раньше изменения); потом сами изменения; неудачные — отзываются.
            # Раньше запись в журнал шла после изменения и ложилась на диск
            # только в конце: обрыв посередине оставлял чужой профиль
            # изменённым без пути назад.
            $plan = New-Object System.Collections.Generic.List[object]
            foreach ($d in $defs) {
                $sub = ("$($d.P)" -replace '^HKCU:\\', '')
                $kp = "$root\$sub"
                $cur = Get-RegValue $kp $d.N
                if ($null -ne $cur -and (ConvertTo-RegComparable $cur $d.Type) -eq (ConvertTo-RegComparable $d.V $d.Type)) { continue }
                # как у Set-Reg: в журнал — вид и данные прежнего значения как есть
                $raw = Get-RegRaw $kp $d.N
                if (-not $raw.ok -or ($null -ne $cur -and -not $raw.exists)) { $cnt.failed++; $cnt.notes.Add(("{0}: прежнее значение не прочиталось" -f $d.N)); continue }
                if ($raw.exists -and -not (Test-RegKind $raw.kind)) { $cnt.failed++; $cnt.notes.Add(("{0}: прежнее значение вида {1} откат не вернул бы" -f $d.N, $raw.kind)); continue }
                $e = @{ kind = 'hive'; file = $pr.file; sid = $pr.sid; profile = $pr.name; sub = $sub
                        name = $d.N; type = $(if ($raw.exists) { $raw.kind } else { $d.Type }); existed = [bool]$raw.exists
                        old = $(if ($raw.exists) { $raw.value } else { '' }); newValue = "$($d.V)"
                        time = (Get-Date).ToString('s'); run = $script:RunId }
                $script:Journal.Add($e)
                $plan.Add(@{ d = $d; kp = $kp; e = $e })
            }
            if ($plan.Count -eq 0) { return }
            Save-JournalEntries -Quiet
            if ($script:JournalFailed) { $cnt.refused = $true; return }
            foreach ($p in $plan) {
                try {
                    if (-not (Test-Path -LiteralPath $p.kp)) { New-Item -Path $p.kp -Force -ErrorAction Stop | Out-Null }
                    New-ItemProperty -LiteralPath $p.kp -Name $p.d.N -Value $p.d.V -PropertyType $p.d.Type -Force -ErrorAction Stop | Out-Null
                } catch { Undo-AheadEntry $p.e; $cnt.failed++; $cnt.notes.Add(("{0}: {1}" -f $p.d.N, $_.Exception.Message)); continue }
                # «команда прошла» — ещё не «значение такое»; запись в журнале
                # остаётся в любом случае: значение уже не прежнее
                $now = Get-RegRaw $p.kp $p.d.N
                if (-not $now.ok -or -not $now.exists -or $now.kind -ne $p.d.Type -or
                    (ConvertTo-RegComparable $now.value $p.d.Type) -ne (ConvertTo-RegComparable $p.d.V $p.d.Type)) {
                    $cnt.failed++; $cnt.notes.Add(("{0}: записано, но читается другое" -f $p.d.N)); continue
                }
                $cnt.changed++
            }
        }
        if ($cnt.refused) { Write-Log ("   [!] профиль {0}: не меняется -- «как было» не легло в журнал отката" -f $pr.name); continue }
        if (-not $mounted) { Write-Log ("   [!] профиль {0}: куст не подключился (пользователь занят или файл недоступен)" -f $pr.name); $script:Failures++; continue }
        Write-Log ("   [{0}] профиль {1}: изменено настроек {2}{3}" -f $(if ($cnt.failed) { '!' } else { '+' }), $pr.name, $cnt.changed, $(if ($cnt.failed) { ", не удалось $($cnt.failed)" } else { '' }))
        foreach ($n in $cnt.notes) { Write-Log ("       {0}" -f $n) }
        $script:Changes += $cnt.changed; $script:Failures += $cnt.failed
    }
    Save-JournalEntries -Quiet
}

# Возвращает записи одного профиля в то, что было до программы. Куст
# подключается один раз на все записи этого профиля, а не на каждую; итог —
# у каждой записи свой, со сверкой (см. Restore-RegValue).
function Restore-HiveEntries {
    param([object[]]$Entries)
    $first = $Entries[0]
    $results = @{}
    $mounted = Use-ProfileHive @{ name = "$($first.profile)"; sid = "$($first.sid)"; file = "$($first.file)" } {
        param($root)
        for ($n = 0; $n -lt $Entries.Count; $n++) {
            $it = $Entries[$n]
            $results[$n] = Restore-RegValue "$root\$($it.sub)" "$($it.name)" ([bool]$it.existed) $it.old "$($it.type)"
        }
    }
    $out = New-Object System.Collections.Generic.List[object]
    for ($n = 0; $n -lt $Entries.Count; $n++) {
        if (-not $mounted) { $out.Add(@{ ok = $false; error = 'куст профиля не подключился (пользователь занят или файл недоступен)' }) }
        elseif ($results.ContainsKey($n)) { $out.Add($results[$n]) }
        else { $out.Add(@{ ok = $false; error = 'запись не обработана' }) }
    }
    return , $out.ToArray()
}

function Restore-Journal {
    # Куст, оставшийся от оборванного запуска, — первым делом, даже если в
    # журнале нет ни одной записи о профилях: оборванный запуск мог не успеть
    # их записать, а куст уже подключить (проверено на VM: процесс убит, пока
    # куст подключён). Раньше уборка шла только вместе с возвратом профилей.
    Clear-StaleHiveMounts
    if (-not (Test-DataTrusted)) {
        Write-Log '   [!] папка данных программы не защищена от подмены -- журналу отката сейчас нельзя верить, ничего не возвращаем'
        $script:Failures++
        return @{ restored = 0; failed = 0; state = 'untrusted' }
    }
    $jf = Read-JournalFile
    # подпись не сошлась или её нечем проверить — почему, уже сказано выше
    if (-not $jf.trusted) { $script:Failures++; return @{ restored = 0; failed = 0; state = 'untrusted' } }
    if ($jf.items.Count -eq 0) { Write-Log '   [-] журнал пуст — возвращать нечего'; return @{ restored = 0; failed = 0; legacy = $jf.legacy; state = $jf.state } }
    # Журнал идёт от старых записей к новым, и про каждый параметр нужна
    # первая: она помнит состояние до нас. Раньше список переворачивался, и у
    # журнала с повторами (версии до схлопывания) возвращалось то значение,
    # которое программа сама же записала в прошлый раз.
    $ok = 0; $seen = @{}; $startBack = 0; $svcBack = 0; $malformed = 0
    $failed = New-Object System.Collections.Generic.List[object]
    $hiveGroups = [ordered]@{}
    $createdKeys = New-Object System.Collections.Generic.List[string]
    # программы, чей файл настроек завела сама программа (appcfg, created)
    $createdApps = New-Object 'System.Collections.Generic.HashSet[string]'
    # Записи, с которыми откат закончил (вернул или отбросил как негодные).
    # Из журнала уходят только они: что дописал другой запуск, пока шёл
    # откат, остаётся. Раньше журнал переписывался списком неудач целиком.
    $handled = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($e in @($jf.items)) {
        # запись не по форме не исполняется: подпись не заменяет проверку
        # допустимости. В журнал такая запись не возвращается.
        $why = Test-JournalEntryShape $e
        if ($why) { $malformed++; $null = $handled.Add((Get-JournalEntryId $e)); Write-Log ("   [!] запись журнала не по форме ({0}) -- пропущена" -f $why); continue }
        # записи автозагрузки возвращаем тем же способом, каким гасили
        if ("$($e.kind)" -eq 'startup') {
            $key = "startup|$($e.id)"
            if ($seen.ContainsKey($key)) { $null = $handled.Add((Get-JournalEntryId $e)); continue }
            $seen[$key] = $true
            $r = Set-StartupState ([string]$e.id) ("$($e.old)" -eq 'On')
            if ($r.ok) { $startBack++; $null = $handled.Add((Get-JournalEntryId $e)) }
            else { $failed.Add($e); Write-Log ("   [!] не вернулось: {0} -- {1}" -f $key, $r.error) }
            continue
        }
        if ("$($e.kind)" -eq 'hive') {
            # записи других профилей — пачкой на профиль, после остальных
            $key = Get-JournalKey (ConvertTo-Fields $e)
            if ($seen.ContainsKey($key)) { $null = $handled.Add((Get-JournalEntryId $e)); continue }
            $seen[$key] = $true
            $hf = "$($e.file)".ToLowerInvariant()
            if (-not $hiveGroups.Contains($hf)) { $hiveGroups[$hf] = New-Object System.Collections.Generic.List[object] }
            $hiveGroups[$hf].Add($e)
            continue
        }
        $kind = "$($e.kind)"
        $key = Get-JournalKey (ConvertTo-Fields $e)
        if ($seen.ContainsKey($key)) { $null = $handled.Add((Get-JournalEntryId $e)); continue }      # только самое раннее состояние
        $seen[$key] = $true
        $r = Restore-JournalEntry $e
        if (-not $r.ok) { $failed.Add($e); Write-Log ("   [!] не вернулось: {0} -- {1}" -f $key, $r.error); continue }
        $null = $handled.Add((Get-JournalEntryId $e))
        if ($kind -eq 'reg' -and "$($e.createdKey)") { $createdKeys.Add("$($e.createdKey)") }
        if ($kind -eq 'appcfg' -and $e.created) { $null = $createdApps.Add("$($e.app)") }
        if ($r.note) { Write-Log ("   [i] {0} -- {1}" -f $key, $r.note) }
        if ($kind -eq 'reg') { $ok++ } else { $svcBack++ }
    }
    foreach ($hf in @($hiveGroups.Keys)) {
        $group = $hiveGroups[$hf].ToArray()
        $res = Restore-HiveEntries $group
        for ($n = 0; $n -lt $group.Count; $n++) {
            $he = $group[$n]
            if ($res[$n].ok) { $ok++; $null = $handled.Add((Get-JournalEntryId $he)); continue }
            $failed.Add($he)
            Write-Log ("   [!] не вернулось: профиль {0}, {1}\{2} -- {3}" -f $he.profile, $he.sub, $he.name, $res[$n].error)
        }
    }
    # ключи, которых не было до программы, — после всех значений
    if ($createdKeys.Count -gt 0) { Remove-CreatedKeys $createdKeys.ToArray() }
    # файлы настроек сторонних программ, которые завела программа, — после всех ключей
    foreach ($app in @($createdApps)) { Remove-CreatedAppFile $app }
    if ($malformed -gt 0) { $script:Failures++ }
    $bad = $failed.Count
    Write-Log ("   [+] возвращено параметров реестра: {0}" -f $ok)
    if ($svcBack -gt 0) { Write-Log ("   [+] возвращено служб, задач и переменных среды: {0}" -f $svcBack) }
    if ($startBack -gt 0) { Write-Log ("   [+] возвращено записей автозагрузки: {0}" -f $startBack) }
    # Что вернуть не удалось, остаётся в журнале: раньше он стирался целиком,
    # даже когда откат прошёл не весь, и вторая попытка была невозможна.
    # Пустой журнал остаётся файлом: по нему видно, что он нового образца.
    if ($bad -gt 0) { Write-Log ("   [!] не удалось вернуть: {0} -- эти записи остались в журнале" -f $bad); $script:Failures++ }
    try { Remove-JournalEntries $handled }
    catch { Write-Log ("   [!] журнал отката не переписался: {0}" -f $_.Exception.Message); $script:Failures++ }
    return @{ restored = $ok + $svcBack; startup = $startBack; failed = $bad; legacy = $jf.legacy; state = $jf.state }
}

# --------------------------------------------------------------------------- #
#  Журнал изменений в человеческом виде. Записи группируются по ключу: важно
#  самое раннее состояние — именно его вернёт откат. Название берём из
#  описания настройки, чтобы в списке было «уровень телеметрии», а не путь.
# --------------------------------------------------------------------------- #
function Get-ChangeGroups {
    # только то, чему можно верить: подписанное или из защищённой папки
    $j = Read-JournalFile -ReadOnly
    if ($j.items.Count -eq 0) { return @() }
    $byPath = @{}
    foreach ($d in $script:Defs) {
        if ($script:RegTypes -notcontains $d.T) { continue }
        $k = ("{0}|{1}" -f $d.P, $d.N).ToLowerInvariant()
        if (-not $byPath.ContainsKey($k)) { $byPath[$k] = @{ title = [string]$d.C; module = [string]$d.M } }
    }
    $order = New-Object System.Collections.Generic.List[string]
    $groups = @{}
    foreach ($e in @($j.items)) {
        $kind = "$($e.kind)"
        if ($kind -eq 'startup') {
            $key = 'startup|' + "$($e.id)"
            $title = $(if ("$($e.name)") { "$($e.name)" } else { "$($e.id)" })
            $where = 'автозагрузка'
            $was = $(if ("$($e.old)" -eq 'On') { 'запускалась' } else { 'была отключена' })
            $now = $(if ("$($e.newValue)" -eq 'On') { 'запускается' } else { 'отключена' })
        } elseif ($kind -eq 'hive') {
            # настройка другого профиля: называется так же, как своя, а где — видно по профилю
            $key = Get-JournalKey (ConvertTo-Fields $e)
            $pk = ("HKCU:\{0}|{1}" -f "$($e.sub)", "$($e.name)").ToLowerInvariant()
            $title = $(if ($byPath.ContainsKey($pk)) { $byPath[$pk].title } else { "$($e.name)" })
            $where = ("профиль {0}: {1}" -f "$($e.profile)", "$($e.sub)")
            $was = $(if ($e.existed) { "$($e.old)" } else { 'не было' })
            $now = "$($e.newValue)"
        } elseif ($kind -eq 'audit') {
            $key = Get-JournalKey (ConvertTo-Fields $e)
            $title = 'журнал соединений брандмауэра (наблюдение за сетью)'
            $where = 'политика аудита'
            $was = Get-AuditName "$($e.old)"
            $now = Get-AuditName "$($e.newValue)"
        } elseif ($kind -in @('svc', 'task', 'env')) {
            $key = Get-JournalKey (ConvertTo-Fields $e)
            $target = $(if ($kind -eq 'task') { "$($e.path)" } else { "$($e.name)" })
            $def = @($script:Defs | Where-Object { "$($_.P)" -eq $target -and (
                        ($kind -eq 'svc' -and $_.T -in @('svc', 'svcopt')) -or ($kind -eq 'task' -and $_.T -eq 'task') -or ($kind -eq 'env' -and $_.T -eq 'env')) } | Select-Object -First 1)
            $title = $(if ($def.Count -gt 0) { [string]$def[0].C } elseif ($kind -eq 'task') { Split-Path $target -Leaf } else { $target })
            if ($kind -eq 'svc') {
                $where = 'службы Windows'
                $was = Get-StartName "$($e.old)" "$($e.delayed)"
                $now = Get-StartName "$($e.newValue)"
            } elseif ($kind -eq 'task') {
                $where = 'планировщик задач'
                $was = 'включена'; $now = 'отключена'
            } else {
                $where = 'переменные среды'
                $was = $(if ($e.existed) { "$($e.old)" } else { 'не было' })
                $now = "$($e.newValue)"
            }
        } else {
            $key = ("reg|{0}|{1}" -f "$($e.path)", "$($e.name)").ToLowerInvariant()
            $pk = ("{0}|{1}" -f "$($e.path)", "$($e.name)").ToLowerInvariant()
            $title = $(if ($byPath.ContainsKey($pk)) { $byPath[$pk].title } else { "$($e.name)" })
            $where = "$($e.path)"
            $was = $(if ($e.existed) { "$($e.old)" } else { 'не было' })
            $now = "$($e.newValue)"
        }
        # у схлопнутой записи число правок лежит в ней самой
        $times = [int]$(if ($e.PSObject.Properties['count'] -and [int]$e.count -gt 0) { $e.count } else { 1 })
        $when = $(if ($e.PSObject.Properties['lastTime'] -and "$($e.lastTime)") { "$($e.lastTime)" } else { "$($e.time)" })
        if (-not $groups.ContainsKey($key)) {
            $order.Add($key)
            $groups[$key] = @{ id = (ConvertTo-StartupId $key); kind = $kind; title = $title
                               where = $where; was = $was; now = $now
                               time = $when; count = $times }
        } else {
            # самое раннее «было» уже записано, обновляем только текущее значение
            $groups[$key].now = $now
            $groups[$key].time = $when
            $groups[$key].count = [int]$groups[$key].count + $times
        }
    }
    $out = @()
    foreach ($k in $order) { $out += $groups[$k] }
    [array]::Reverse($out)          # свежие изменения сверху
    return $out
}

# Возвращает одну запись журнала и убирает её из changes.json
function Restore-ChangeKey {
    param([string]$Key)
    Clear-StaleHiveMounts
    if (-not (Test-DataTrusted)) { return @{ ok = $false; error = 'папка данных программы не защищена от подмены' } }
    $jf = Read-JournalFile
    if (-not $jf.trusted) { return @{ ok = $false; error = 'журналу отката нельзя верить: подпись не сошлась или её нечем проверить' } }
    if ($jf.items.Count -eq 0) { return @{ ok = $false; error = 'журнал пуст' } }
    $mine = @($jf.items | Where-Object { (Get-JournalKey (ConvertTo-Fields $_)) -eq $Key })
    if ($mine.Count -eq 0) { return @{ ok = $false; error = 'запись не найдена' } }
    $first = $mine[0]              # самое раннее состояние
    $why = Test-JournalEntryShape $first
    if ($why) { return @{ ok = $false; error = ('запись журнала не по форме: ' + $why) } }
    if ("$($first.kind)" -eq 'startup') {
        $r = Set-StartupState ([string]$first.id) ("$($first.old)" -eq 'On')
    } elseif ("$($first.kind)" -eq 'hive') {
        $r = (Restore-HiveEntries @($first))[0]
    } else {
        $r = Restore-JournalEntry $first
    }
    # denied — Windows не дала; missing — того, что возвращать, больше нет.
    # Запись журнала убирается только после сверки (её делает возврат записи).
    if (-not $r.ok) { return @{ ok = $false; denied = [bool]$r.denied; error = "$($r.error)" } }
    if ("$($first.kind)" -eq 'reg' -and "$($first.createdKey)") { Remove-CreatedKeys @("$($first.createdKey)") }
    # журнал перечитывается под замком: дописанное другим запуском остаётся
    try { Remove-JournalKey $Key }
    catch { return @{ ok = $false; error = ('возвращено, но журнал не переписался: ' + $_.Exception.Message) } }
    return @{ ok = $true; missing = [bool]$r.missing; note = "$($r.note)" }
}

if ($ChangeLog) {
    $chg = @(Get-ChangeGroups)
    $j = Read-JournalFile -ReadOnly
    Emit-Json @{ items = $chg; count = $chg.Count
                 raw = @($j.items).Count
                 updated = "$($j.updated)"
                 trusted = [bool]$j.trusted }
    exit 0
}

if ($RestoreItems) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Emit-Json @{ error='нужны права администратора' }; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Возврат выбранных изменений'
    if ($ChangeItems.Count -eq 0) { Write-Log '   [-] ничего не выбрано'; Emit-Json @{ restored = 0 }; Write-Log '###DONE###'; exit 0 }
    $done = 0
    foreach ($id in $ChangeItems) {
        $key = ConvertFrom-StartupId $id
        if (-not $key) { Write-Log ("   [!] непонятная запись: {0}" -f $id); $script:Failures++; continue }
        $r = Restore-ChangeKey $key
        if ($r.ok) { Write-Log ("   [+] возвращено: {0}" -f $key); $done++; $script:Changes++ }
        else { Write-Log ("   [!] {0} -- {1}" -f $key, $r.error); $script:Failures++ }
    }
    Write-Log ("   возвращено записей: {0}" -f $done)
    Emit-Json @{ restored = $done; failures = $script:Failures }
    Write-Log '###DONE###'
    # 2 — дошёл до конца, но не всё прошло (окно пишет «Готово, с ошибками»); раньше всегда 0
    exit $(if ($script:Failures -gt 0) { 2 } else { 0 })
}

# --------------------------------------------------------------------------- #
#  Номер устройства: состояние, смена, возврат как было
# --------------------------------------------------------------------------- #
if ($GdidStatus) { Emit-Json (Get-GdidStatus); exit 0 }

# Код выхода, как у применения и отката: 0 — всё прошло и проверено, 2 —
# дошёл до конца, но не всё (окно пишет «Готово, с ошибками»): Partial,
# Unverified, AccessDenied, Failed, RestoreFailed. Код берётся из того же
# итога, что уходит в ответ (wipe/restore.exitCode), и из счёта ошибок —
# поэтому окно, журнал работы и код выхода не расходятся. Раньше смена номера
# кончалась кодом 0, когда стирание не удалось, но ошибок «не насчиталось».
function Get-GdidExitCode {
    param($Result)
    if ($null -eq $Result -or -not $Result['success'] -or $script:Failures -gt 0) { return 2 }
    return 0
}

if ($GdidReissue) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Смена номера устройства'
    # закрыт — значит, блок цел и в нём сервер выдачи; одной метки мало
    $lockedNow = Test-HostsBlockCurrent -Kind 'lock'
    if ($lockedNow) { Write-Log '   [i] сервер выдачи закрыт: после стирания нового номера Windows не получит' }
    elseif (Test-HostsBlock -Kind 'lock') { Write-Log '   [!] блок сервера выдачи в hosts побит или устарел: Windows может сразу получить новый номер' }
    $wiped = Invoke-GdidWipe
    if ($wiped -and -not $lockedNow) {
        Write-Log '   [i] Новый номер Windows получит при следующем обращении к учётной записи Microsoft (Магазин, Параметры) или после перезагрузки.'
        Write-Log '   [i] Магазин, Xbox и OneDrive могут попросить войти заново.'
    }
    $wr = $script:GdidWipeResult
    if ($null -eq $wr) { $wr = New-GdidResult 'wipe'; $script:Failures++ }
    $code = Get-GdidExitCode $wr
    $wr['exitCode'] = $code
    $gs = Get-GdidStatus
    $gs['wipe'] = $wr
    Emit-Json $gs
    Write-Log '###DONE###'
    exit $code
}

if ($GdidRestore) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Номер устройства: вернуть как было'
    # Итог возврата — той же формы, что у стирания (New-GdidResult). Стадии:
    # guard, services, hosts, firewall, start — у каждой Restored,
    # NotModified (программа это не меняла), NotFound, AccessDenied или
    # RestoreFailed; всё сверяется после изменения. Раньше снятие блоков hosts
    # не проверялось вовсе, снятие правила брандмауэра — тоже, а «вернуто»
    # говорилось и тогда, когда одна из стадий не прошла.
    $rr = New-GdidResult 'restore'
    $script:GdidRestoreResult = $rr
    $stage = {
        param([string]$Name, [string]$State, [string]$Why = '')
        $rr.stages[$Name] = $State
        $rr['checked'] = [int]$rr['checked'] + 1
        if ($State -in @('RestoreFailed', 'AccessDenied')) { $rr['failed'] = [int]$rr['failed'] + 1; if ($Why) { $rr.errors.Add(("{0}: {1}" -f $Name, $Why)) } }
        elseif ($State -eq 'NotFound' -and $Why) { $rr.warnings.Add(("{0}: {1}" -f $Name, $Why)) }
        if ($State -eq 'Restored') { $rr['removed'] = [int]$rr['removed'] + 1 }
    }
    # Сначала страж: иначе, сработав посреди возврата, он поставил бы всё
    # обратно. Раньше профиль стража правился последним. Переписанный профиль
    # перечитывается: «записалось» — ещё не «страж больше не следит».
    $prof = Load-Json 'profile.json'
    if ($prof -and $prof.modules -and @(@($prof.modules) | Where-Object { $_ -in @('gdid', 'gdidlock') }).Count -gt 0) {
        $profSkip = @($(if ($prof.PSObject.Properties['skip']) { @($prof.skip) } else { @() }))
        try {
            Save-Json 'profile.json' @{ version = 1; modules = @(@($prof.modules) | Where-Object { $_ -notin @('gdid', 'gdidlock') })
                                        skip = $profSkip; created = "$($prof.created)" }
            $chkProf = Load-Json 'profile.json'
            if ($chkProf -and @(@($chkProf.modules) | Where-Object { $_ -in @('gdid', 'gdidlock') }).Count -eq 0) {
                Write-Log '   [+] страж больше не следит за номером устройства'
                & $stage 'guard' 'Restored'
            } else {
                Write-Log '   [!] профиль стража переписан, но читается не таким -- он может снова отключить службы номера'
                & $stage 'guard' 'RestoreFailed' 'профиль стража не прочитался после записи'; $script:Failures++
            }
        } catch { Write-Log ("   [!] профиль стража не переписался ({0}) -- он может снова отключить службы номера" -f $_.Exception.Message); & $stage 'guard' 'RestoreFailed' "$($_.Exception.Message)"; $script:Failures++ }
    } else { & $stage 'guard' 'NotModified' }
    # тип запуска служб — по журналу: ровно то, что было до программы
    $restored = New-Object System.Collections.Generic.List[string]
    $svcRes = New-Object System.Collections.Generic.List[object]
    foreach ($r in @(Restore-GdidServiceStarts)) {
        $svcRes.Add($r)
        switch ($r.result) {
            'restored'     { Write-Log ("   [+] служба {0}: тип запуска возвращён ({1})" -f $r.name, (Get-StartName "$(Get-SvcStart $r.name)")); $restored.Add($r.name); $script:Changes++; & $stage ('service:' + $r.name) 'Restored' }
            'notChanged'   { Write-Log ("   [-] служба {0}: программа её не меняла" -f $r.name); & $stage ('service:' + $r.name) 'NotModified' }
            'notFound'     { Write-Log ("   [i] служба {0}: её больше нет на этой системе -- возвращать некуда, запись в журнале оставлена" -f $r.name); & $stage ('service:' + $r.name) 'NotFound' $r.error }
            'accessDenied' { Write-Log ("   [!] служба {0}: Windows не дала вернуть тип запуска -- {1}" -f $r.name, $r.error); $script:Failures++; & $stage ('service:' + $r.name) 'AccessDenied' $r.error }
            default        { Write-Log ("   [!] служба {0}: тип запуска не вернулся -- {1}" -f $r.name, $r.error); $script:Failures++; & $stage ('service:' + $r.name) 'RestoreFailed' $r.error }
        }
    }
    # Блоки hosts: снятие сверяется (Remove-HostsBlock), и до него видно,
    # был ли блок вообще. Раньше ответ Remove-HostsBlock отбрасывался.
    foreach ($hk in @('gdid', 'lock')) {
        $had = Get-GdidHostsFound $hk
        $ok = Remove-HostsBlock -Kind $hk
        $left = Get-GdidHostsFound $hk
        if (-not $ok -or $left -ne 0) {
            if ($ok) { Write-Log ("   [!] блок hosts ({0}) после снятия читается на месте" -f $hk); $script:Failures++ }
            & $stage ('hosts:' + $hk) 'RestoreFailed' $(if ($left -lt 0) { 'hosts не прочитался' } else { 'блок остался в hosts' })
        } elseif ($had -gt 0) { & $stage ('hosts:' + $hk) 'Restored' }
        else { & $stage ('hosts:' + $hk) $(if ($had -lt 0) { 'RestoreFailed' } else { 'NotModified' }) $(if ($had -lt 0) { 'hosts не прочитался' } else { '' }) }
    }
    # «Правила не было» и «правило не снялось» — разное: раньше любая ошибка
    # брандмауэра называлась «правила не было», а снятие не сверялось
    $fwName = Get-FwRuleName 'svc' 'wlidsvc'
    $fev = $null
    $fwRules = @(Get-NetFirewallRule -DisplayName $fwName -ErrorAction SilentlyContinue -ErrorVariable fev)
    $fwErr = @($fev | Where-Object { $_ -and "$($_.CategoryInfo.Category)" -ne 'ObjectNotFound' })
    if ($fwRules.Count -eq 0 -and $fwErr.Count -gt 0) { Write-Log ("   [!] брандмауэр не ответил, есть ли правило для wlidsvc: {0}" -f $fwErr[0]); $script:Failures++; & $stage 'firewall' 'RestoreFailed' "$($fwErr[0])" }
    elseif ($fwRules.Count -eq 0) { Write-Log '   [-] правила брандмауэра для wlidsvc не было'; & $stage 'firewall' 'NotModified' }
    else {
        $fwWhy = ''
        try { Remove-NetFirewallRule -DisplayName $fwName -ErrorAction Stop } catch { $fwWhy = "$($_.Exception.Message)" }
        $fev2 = $null
        $fwLeft = @(Get-NetFirewallRule -DisplayName $fwName -ErrorAction SilentlyContinue -ErrorVariable fev2)
        $fwErr2 = @($fev2 | Where-Object { $_ -and "$($_.CategoryInfo.Category)" -ne 'ObjectNotFound' })
        if (-not $fwWhy -and $fwLeft.Count -eq 0 -and $fwErr2.Count -eq 0) { Write-Log '   [+] правило брандмауэра для wlidsvc снято'; $script:Changes++; & $stage 'firewall' 'Restored' }
        else {
            if (-not $fwWhy) { $fwWhy = $(if ($fwLeft.Count -gt 0) { 'правило осталось на месте' } else { "брандмауэр не ответил: $($fwErr2[0])" }) }
            Write-Log ("   [!] правило брандмауэра для wlidsvc не снялось: {0}" -f $fwWhy); $script:Failures++
            & $stage 'firewall' $(if ($fwWhy -match 'Access is denied|Отказано в доступе') { 'AccessDenied' } else { 'RestoreFailed' }) $fwWhy
        }
    }
    # Службы, которым вернули тип запуска, — в работу сразу, если Windows даёт.
    # Раньше запускалась одна CDPSvc, и даже когда программа её не меняла.
    $sync = Sync-GdidRestoredServices @($restored | Where-Object { $_ -ne 'wlidsvc' })
    foreach ($p in @($sync.pending)) { Write-Log ("   [i] служба {0}: тип запуска возвращён, но Windows применит его позже -- до тех пор она не работает" -f $p); $rr.warnings.Add(("отложено: {0}" -f $p)) }
    foreach ($f in @($sync.failed)) { Write-Log ("   [!] служба не запустилась: {0}" -f $f); $script:Failures++; $rr['failed'] = [int]$rr['failed'] + 1; $rr.errors.Add(("не запустилась: {0}" -f $f)) }
    $rr.stages['start'] = $(if (@($sync.failed).Count -gt 0) { 'RestoreFailed' } elseif (@($sync.pending).Count -gt 0) { 'Pending' } else { 'ok' })
    # Оборванное стирание номера: службы, что работали до него и стоят
    # сейчас, — запустить и сверить (Restore-GdidInterruptedWipe). Раньше о
    # них не знал никто: список жил только в памяти оборвавшегося запуска.
    $iw = Restore-GdidInterruptedWipe
    switch ($iw.state) {
        'NotModified' { & $stage 'interruptedWipe' 'NotModified' }
        'Restored' {
            foreach ($n in @($iw.started)) { Write-Log ("   [+] служба {0} снова работает (её остановило оборванное стирание номера)" -f $n) }
            foreach ($n in @($iw.skipped)) { Write-Log ("   [i] служба {0} после оборванного стирания не запускается: её нет или она отключена" -f $n) }
            if ($iw.error) { Write-Log ("   [i] {0}" -f $iw.error) }
            if (@($iw.started).Count -gt 0) { $script:Changes++ }
            & $stage 'interruptedWipe' 'Restored'
        }
        default {
            foreach ($n in @($iw.failed)) { Write-Log ("   [!] служба {0} после оборванного стирания не запустилась" -f $n) }
            if ($iw.error) { Write-Log ("   [!] {0}" -f $iw.error) }
            $script:Failures++
            & $stage 'interruptedWipe' 'RestoreFailed' ((@($iw.failed) + @($iw.error | Where-Object { $_ })) -join '; ')
        }
    }
    if ((Get-SvcStart 'wlidsvc') -eq 4 -and $restored -notcontains 'wlidsvc') {
        Write-Log '   [i] служба учётных записей Microsoft (wlidsvc) отключена, но не программой (в журнале отката её нет) -- она её не трогает'
    }
    Write-Log '   [i] Стёртый раньше номер не вернётся: Windows получит новый при следующем обращении к учётной записи Microsoft.'
    # Итог: Restored — что программа меняла, возвращено и сверено; NotModified —
    # программа ничего из этого не меняла; Partial — что-то вернулось, что-то
    # нет; RestoreFailed — не вернулось ничего из того, что надо было вернуть
    $rr.serviceStates = $svcRes.ToArray()
    $rr.remaining = [int]$rr.failed
    $restState = $(if ($rr.failed -gt 0 -or $script:Failures -gt 0) { if ($rr.removed -gt 0) { 'Partial' } else { 'RestoreFailed' } }
                   elseif ($rr.removed -gt 0) { 'Restored' } else { 'NotModified' })
    Set-GdidResultState $rr $restState
    if ($restState -in @('Partial', 'RestoreFailed')) { Write-Log '   [!] вернулось не всё -- что именно, сказано выше' }
    $code = Get-GdidExitCode $rr
    $rr['exitCode'] = $code
    $gs = Get-GdidStatus
    $gs['restore'] = @{ restored = $restored.ToArray(); pending = @($sync.pending); failed = @($sync.failed)
                        state = $restState; result = $rr }
    Emit-Json $gs
    Write-Log '###DONE###'
    exit $code
}
# --------------------------------------------------------------------------- #
#  Что программа накопила о вас у себя. Для программы про приватность честно
#  показывать и свои файлы — и уметь их стереть.
#
#  Данными программы считается только то, что она кладёт сама: имена ниже и
#  файлы по строгим образцам. Раньше сюда шло и всё прочее, что лежало в
#  папке, — и -PurgeData стёр бы любые чужие файлы, окажись папка данных не
#  той. Неизвестный файл не показывается и не удаляется.
# --------------------------------------------------------------------------- #
$script:DataFiles = @(
    @{ file = 'sensor-history.json'; title = 'История датчиков по дням: кто включал камеру, микрофон и геолокацию' },
    @{ file = 'sensor-apps.json';    title = 'Список программ, которым доступ к датчикам уже известен' },
    @{ file = 'startup-known.json';  title = 'Известные записи автозагрузки — по ним страж замечает новые' },
    @{ file = 'changes.json';        title = 'Журнал изменений: что программа поменяла и что было до неё' },
    @{ file = 'proof-before.json';   title = 'Снимок «до»: состояние системы перед первым применением' },
    @{ file = 'xray-last.json';      title = 'Последний результат рентгена телеметрии' },
    @{ file = 'xray-baseline.json';  title = 'Эталон рентгена: сколько событий уходило до настройки' },
    @{ file = 'profile.json';        title = 'Профиль стража: какие разделы он сторожит' },
    @{ file = 'guard-last.json';     title = 'Последняя проверка стража' },
    @{ file = 'guard.log';           title = 'Журнал работы стража' },
    @{ file = 'net-apps.json';       title = 'Программы, выходившие в сеть, — по ним слежение замечает новые' },
    @{ file = 'xray-history.json';   title = 'История рентгена по дням: сколько событий уходило' },
    @{ file = 'blocked.json';        title = 'Настройки, которые Windows не дала применить' },
    @{ file = 'oem-disabled.json';   title = 'Компоненты производителя, отключённые прежней версией' },
    @{ file = 'watcher-last.txt';    title = 'Время последнего живого уведомления' },
    @{ file = 'journal-check.json';  title = 'Проба записи журнала, оставшаяся после обрыва' }
)
# Файлы с изменчивой частью имени: журнал, отложенный проверкой (метка
# времени — как у Read-JournalFile), и недописанная копия файла данных
# (Save-Json пишет рядом «имя.tmp»). Копия движка и ключ подписи — не данные
# о человеке и сюда не входят.
$script:DataFilePatterns = @(
    @{ rx = '^changes\.(broken|unverifiable|unverified)-\d{8}-\d{6}\.json$'
       title = 'Отложенный журнал отката: повреждён или не прошёл проверку подписи' },
    @{ rx = ('^(' + (@($script:DataFiles | ForEach-Object { [regex]::Escape($_.file) }) -join '|') + ')\.tmp$')
       title = 'Недописанная копия файла данных: осталась после обрыва записи' }
)

# Название файла данных программы — или $null, если файл не её.
function Get-DataFileTitle {
    param([string]$Name)
    foreach ($d in $script:DataFiles) { if ($Name -ieq $d.file) { return $d.title } }
    foreach ($p in $script:DataFilePatterns) { if ($Name -match $p.rx) { return $p.title } }
    return $null
}

# Можно ли удалить этот файл как данные программы: обычный файл (не папка и
# не ссылка) с именем из списка выше. Сверяется перед каждым удалением, а не
# только при составлении списка.
function Test-DataFileOwned {
    param($Item)
    if ($null -eq $Item -or $Item.PSIsContainer) { return $false }
    if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    return ($null -ne (Get-DataFileTitle $Item.Name))
}

function Get-DataFiles {
    $out = @()
    if (-not (Test-Path -LiteralPath $script:DataDir -PathType Container)) { return @() }
    foreach ($fi in @(Get-ChildItem -LiteralPath $script:DataDir -File -Force -ErrorAction SilentlyContinue)) {
        if (-not (Test-DataFileOwned $fi)) { continue }
        $out += @{ file = $fi.Name; title = (Get-DataFileTitle $fi.Name); kb = [math]::Round($fi.Length / 1KB, 1)
                   changed = $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }
    }
    return @($out | Sort-Object { -[double]$_.kb })
}

if ($DataInfo) {
    $dataList = @(Get-DataFiles)
    $sum = 0.0
    foreach ($d in $dataList) { $sum += [double]$d.kb }
    Emit-Json @{ items = $dataList; count = $dataList.Count; kb = [math]::Round($sum, 1)
                 folder = $script:DataDir }
    exit 0
}

if ($PurgeData) {
    Write-Section 'Удаление данных программы'
    $dataList = @(Get-DataFiles)
    if ($dataList.Count -eq 0) { Write-Log '   [-] программа ничего о вас не хранит'; Emit-Json @{ removed = 0 }; Write-Log '###DONE###'; exit 0 }
    $gone = 0
    foreach ($d in $dataList) {
        $full = Join-Path $script:DataDir $d.file
        if ($DryRun) { Write-Log ("   [тест] {0}" -f $d.file); continue }
        # между списком и удалением на месте файла могла появиться папка или ссылка
        if (-not (Test-DataFileOwned (Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue))) {
            Write-Log ("   [-] пропущен: {0} -- это уже не файл данных программы" -f $d.file); continue
        }
        try { Remove-Item -LiteralPath $full -Force -ErrorAction Stop; Write-Log ("   [+] удалён: {0}" -f $d.file); $gone++ }
        catch { Write-Log ("   [!] не удалось удалить {0} -- {1}" -f $d.file, $_.Exception.Message); $script:Failures++ }
    }
    Write-Log ("   удалено файлов: {0}" -f $gone)
    Write-Log '   Журнал отката тоже стёрт — вернуть настройки «как было» программа больше не сможет.'
    Emit-Json @{ removed = $gone }
    Write-Log '###DONE###'
    # 2 — дошёл до конца, но не всё прошло (окно пишет «Готово, с ошибками»); раньше всегда 0
    exit $(if ($script:Failures -gt 0) { 2 } else { 0 })
}

if ($RestoreAll) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Возврат настроек реестра по журналу'
    $r = Restore-Journal
    Emit-Json $r
    Write-Log '###DONE###'
    # Код выхода честный: 2 — журналу нельзя верить или вернулось не всё.
    # Раньше здесь всегда был 0, и окно показывало «Готово», хотя по
    # недоверенному журналу не возвращалось ничего (полный откат это различает).
    if ("$($r.state)" -eq 'untrusted' -or [int]$r.failed -gt 0 -or $script:Failures -gt 0) { exit 2 }
    exit 0
}

# =========================================================================== #
#  Revert (откат)
# =========================================================================== #
if ($Revert) {
    Write-Log 'ОТКАТ ИЗМЕНЕНИЙ'
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }

    # Страж и слежение — первыми. Раньше их задачи удалялись после возврата
    # журнала, и страж, сработавший посреди отката, снова ставил то, что откат
    # только что вернул.
    Write-Section 'Страж'
    $null = Remove-OwnTask $script:GuardTask 'задача стража'
    $null = Remove-OwnTask $script:SensorTask 'слежение за датчиками'
    $null = Remove-OwnTask $script:NetTask 'слежение за сетью'
    $null = Remove-OwnTask 'Win11Privacy Watcher' 'живые уведомления'

    Write-Section 'Настройки реестра, службы, задачи'; $rj = Restore-Journal
    # Журнал прежних версий не знает, какими были службы, задачи и переменные
    # среды до программы. Только для него — прежний откат «по умолчанию», и
    # только для того, что сейчас выключено. Раньше сюда вело и отсутствие
    # файла журнала — а его нет и тогда, когда недоверенный журнал только что
    # отложен: отказ от подделки оборачивался откатом по умолчанию. Теперь —
    # только журнал прежнего образца, которому можно верить.
    $legacyRevert = ("$($rj.state)" -eq 'legacy')
    if ("$($rj.state)" -eq 'untrusted') { Write-Log '   [!] журналу отката нельзя верить -- службы, задачи и политика аудита «по умолчанию» тоже не возвращаются' }
    elseif ("$($rj.state)" -eq 'none') { Write-Log '   [-] журнала нет -- службы, задачи и переменные среды возвращать не по чему' }
    Write-Section 'Файл hosts'; $null = Remove-HostsBlock
    Write-Section 'Брандмауэр'; Remove-FwRules
    # Политику аудита возвращает журнал — ровно ту, что была до программы.
    # Журнал прежних версий её не знает: тогда, как раньше, выключаем.
    Write-Section 'Монитор'
    if ($legacyRevert) { if (Get-MonitorEnabled) { Set-MonitorEnabled $false | Out-Null } else { Write-Log '   [-] журнал аудита не включён' } }
    else { Write-Log '   [-] политика аудита возвращена по журналу (если программа её меняла)' }

    if ($legacyRevert) {
        Write-Section 'Службы (журнал прежней версии)'
        foreach ($svc in @(@{N='DiagTrack';S='Automatic'}, @{N='dmwappushservice';S='Manual'}, @{N='NvTelemetryContainer';S='Automatic'}, @{N='InventorySvc';S='Automatic'})) {
            $s = Get-Service -Name $svc.N -ErrorAction SilentlyContinue
            if (-not $s) { continue }                               # службы нет на этом компьютере
            if ($s.StartType -ne 'Disabled') { continue }           # не выключена — не трогаем
            try { Set-Service -Name $svc.N -StartupType $svc.S -ErrorAction Stop; Write-Log "   [+] $($svc.N) -> $($svc.S)" }
            catch { Write-Log ("   [!] {0} -- не вернулась: {1}" -f $svc.N, $_.Exception.Message); $script:Failures++ }
        }
        Write-Section 'Задачи планировщика (журнал прежней версии)'
        foreach ($d in $script:Defs) {
            if ($d.T -eq 'task') {
                $pp = Split-TaskPath $d.P
                $st = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction SilentlyContinue
                if (-not $st) { continue }
                if (-not (Test-TaskDisabled $st)) { continue }
                if ((Set-TaskEnabled $d.P $true) -in @('ok', 'system')) { Write-Log "   [+] включена: $($pp[1])" } else { Write-Log "   [-] пропущена: $($pp[1])" }
            } elseif ($d.T -eq 'taskglob') {
                foreach ($t in @(Get-TaskGlobTasks $d.P -AnyFolder | Where-Object { Test-TaskDisabled $_ })) {
                    try { Enable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null; Write-Log "   [+] включена: $($t.TaskName)" } catch { Write-Log ("   [!] не включилась: {0} -- {1}" -f $t.TaskName, $_.Exception.Message); $script:Failures++ }
                }
            }
        }
    }
    Write-Section 'Компоненты производителя'
    # Новые версии возвращают их по журналу отката (выше). Здесь — список
    # прежних версий, oem-disabled.json. Подписи у него нет, поэтому из него
    # берётся только то, что программа сама сейчас узнаёт как компонент
    # производителя: та же служба или задача, тот же вид. Чужое имя,
    # дописанное в файл, не включается.
    $oemSaved = Load-Json 'oem-disabled.json'
    if ($oemSaved) {
        $oemLeft = 0
        $known = @{}
        foreach ($k in @((Detect-Oem).items)) { $known[("{0}|{1}" -f $k.type, $k.name).ToLowerInvariant()] = $true }
        foreach ($it in @($oemSaved)) {
            $type = "$($it.type)"; $name = "$($it.name)"
            if ($type -notin @('svc', 'task') -or -not $known.ContainsKey(("{0}|{1}" -f $type, $name).ToLowerInvariant())) {
                Write-Log ("   [!] {0} -- не компонент производителя на этом компьютере, пропущено" -f $name); continue
            }
            try {
                if ($type -eq 'svc') { Set-Service -Name $name -StartupType $(if ("$($it.state)" -match 'Auto') { 'Automatic' } else { 'Manual' }) -ErrorAction Stop; Write-Log "   [+] служба $name -> $($it.state)" }
                else { $pp = Split-TaskPath $name; Enable-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop | Out-Null; Write-Log "   [+] задача $($pp[1]) включена" }
            } catch { Write-Log ("   [!] {0} -- не вернулось: {1}" -f $name, $_.Exception.Message); $script:Failures++; $oemLeft++ }
        }
        # не всё вернулось — список остаётся для второй попытки
        if ($oemLeft -eq 0) { Remove-Item -LiteralPath (Join-Path $script:DataDir 'oem-disabled.json') -Force -ErrorAction SilentlyContinue }
    } else { Write-Log '   [-] список прежней версии не найден -- если программа их отключала, они вернулись по журналу' }

    Write-Section 'Сторонние программы'
    # Переменные среды возвращает журнал. Журнал прежней версии их не знает:
    # тогда убираем только то, что стоит ровно в нашем значении.
    if ($legacyRevert) {
        foreach ($d in @($script:Defs | Where-Object { $_.T -eq 'env' })) {
            if ([string][Environment]::GetEnvironmentVariable($d.P, 'User') -ne [string]$d.V) { continue }
            try { [Environment]::SetEnvironmentVariable($d.P, $null, 'User'); Write-Log "   [+] переменная $($d.P) удалена" } catch { Write-Log ("   [!] переменная {0} не удалена -- {1}" -f $d.P, $_.Exception.Message); $script:Failures++ }
        }
    }
    # Настройки VS Code и Firefox возвращает журнал — по одному ключу (выше).
    # Раньше здесь поверх файла копировалась копия, снятая при первом
    # применении: всё, что человек поменял в настройках после, пропадало
    # (проверено на VM). Копии прежних версий не трогаем и не применяем —
    # только говорим, где они лежат.
    foreach ($f in @((Get-VsCodeSettingsPath), (Get-FirefoxPoliciesPath))) {
        if ($f -and (Test-Path -LiteralPath "$f.win11privacy.bak")) {
            Write-Log ("   [i] копия файла настроек от прежней версии программы оставлена как есть: {0}.win11privacy.bak" -f $f)
            Write-Log '       Нужные из неё значения перенесите вручную: поверх нынешних настроек она не копируется.'
        }
    }
    # Политики Chrome, Office и Visual Studio раньше удалялись целыми ветками —
    # вместе с корпоративными, которых программа не ставила. Это обычные
    # параметры реестра, и журнал уже вернул каждый из них как было.

    if ($legacyRevert) {
        # Самые старые версии ставили это без журнала. Снимаем, только если
        # стоит ровно наше значение.
        Write-Section 'Геолокация, Защитник, виджеты (журнал прежней версии)'
        foreach ($rv in @(
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'; N='DisableLocation'; V='1' },
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'; N='DisableWindowsLocationProvider'; V='1' },
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice'; N='AllowFindMyDevice'; V='0' },
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'; N='SpyNetReporting'; V='0' },
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'; N='SubmitSamplesConsent'; V='2' },
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; N='AllowNewsAndInterests'; V='0' })) {
            if ("$(Get-RegValue $rv.P $rv.N)" -ne $rv.V) { continue }
            try { Remove-ItemProperty -LiteralPath $rv.P -Name $rv.N -Force -ErrorAction Stop; Write-Log "   [+] снято: $($rv.N)" } catch { Write-Log ("   [!] не снято: {0} -- {1}" -f $rv.N, $_.Exception.Message); $script:Failures++ }
        }
        $locKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
        if ("$(Get-RegValue $locKey 'Value')" -eq 'Deny') {
            try { New-ItemProperty -LiteralPath $locKey -Name 'Value' -Value 'Allow' -PropertyType String -Force -ErrorAction Stop | Out-Null; Write-Log '   [+] доступ к местоположению возвращён (Allow)' } catch { Write-Log ("   [!] доступ к местоположению не возвращён -- {0}" -f $_.Exception.Message); $script:Failures++ }
        }
    }

    Write-Section 'Данные программы'
    $left = @(Get-DataFiles)
    # копия движка для стража больше не нужна — задача уже удалена
    foreach ($f in @($script:TaskEngine, (Join-Path $script:DataDir 'engine.ps1'))) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        try { Remove-Item -LiteralPath $f -Force -ErrorAction Stop }
        catch { Write-Log ("   [!] копия движка не удалилась: {0} -- {1}" -f $f, $_.Exception.Message); $script:Failures++ }
    }
    # в журнале что-то осталось: то, что вернуть не удалось, или то, что
    # успел дописать другой запуск, — он остаётся для второй попытки
    $journalLeft = @((Read-JournalFile -ReadOnly).items).Count
    if ($left.Count -eq 0) { Write-Log '   [-] программа ничего о вас не хранит' }
    else {
        foreach ($d in $left) {
            if ($d.file -eq 'changes.json' -and $journalLeft -gt 0) { Write-Log ("   [-] журнал отката оставлен: в нём записей {0}, вернуть их пока не удалось" -f $journalLeft); continue }
            # Отложенный журнал (повреждён, подпись не сошлась, проверить
            # нечем) — след подмены, а при потерянном ключе и единственная
            # копия журнала. Раньше откат стирал его вместе с остальными
            # данными сразу после того, как отложил.
            if ($d.file -like 'changes.*-*.json') { Write-Log ("   [-] отложенный журнал оставлен: {0}" -f $d.file); continue }
            try { Remove-Item -LiteralPath (Join-Path $script:DataDir $d.file) -Force -ErrorAction Stop; Write-Log ("   [+] удалён: {0}" -f $d.file) }
            catch { Write-Log ("   [!] не удалось удалить {0} -- {1}" -f $d.file, $_.Exception.Message); $script:Failures++ }
        }
    }

    Write-Log ''
    Write-Log ("Ошибок              : {0}" -f $script:Failures)
    if ("$($rj.state)" -eq 'untrusted') {
        Write-Log '[!] Настройки по журналу изменений не возвращены: журналу нельзя верить (почему — сказано выше).'
        Write-Log 'Запасной вариант — резервная копия реестра на рабочем столе или точка восстановления Windows.'
    } elseif ([int]$rj.failed -gt 0) {
        Write-Log ("[!] Вернулось не всё: записей журнала, которые вернуть не удалось, -- {0} (какие и почему — выше). Они остались в журнале: повторите откат после перезагрузки." -f $rj.failed)
        Write-Log 'Запасной вариант — резервная копия реестра на рабочем столе или точка восстановления Windows.'
    } elseif ("$($rj.state)" -eq 'none' -or ([int]$rj.restored + [int]$rj.startup) -eq 0) {
        # Раньше и здесь говорилось «возвращены и сверены», хотя по журналу
        # не возвращалось ничего: его не было или он был пуст.
        Write-Log 'Журнала изменений нет или он пуст -- по нему возвращать было нечего. Остальное (hosts, брандмауэр, страж) убрано, как сказано выше.'
    } else {
        Write-Log 'Настройки реестра возвращены по журналу изменений и сверены — ручной импорт .reg больше не нужен.'
        Write-Log 'Папка резервной копии на рабочем столе остаётся как запасной вариант.'
    }
    Write-Log 'Готово. Перезагрузите компьютер.'
    Write-Log '###DONE###'
    # 2 — откат прошёл не весь или журналу нельзя было верить (см. выше)
    if ($script:Failures -gt 0) { exit 2 }
    exit 0
}

# =========================================================================== #
#  ПРИМЕНЕНИЕ
# =========================================================================== #
if (-not (Test-Admin)) { Write-Log 'ОШИБКА: требуются права администратора.'; Write-Log '###DONE###'; exit 1 }

$osInfo = (Get-CimInstance Win32_OperatingSystem).Caption
$edInfo = Get-Edition
Write-Log "Система : $osInfo (сборка $([System.Environment]::OSVersion.Version.Build), редакция $($edInfo.id))"
Write-Log "Модули  : $($Modules -join ', ')"
if ($DryRun) { Write-Log 'РЕЖИМ ТЕСТА: изменения не применяются.' }
if ($edInfo.kind -ne 'enterprise' -and (Use-Module 'telemetry')) {
    Write-Log 'Примечание: на редакциях Home/Pro минимальный уровень телеметрии — «Обязательные данные»; полное отключение доступно только в Enterprise/Education.'
}

# --- Снимок «до» для доказательства результата -------------------------- #
if (-not $DryRun -and -not (Load-Json 'proof-before.json')) {
    try { Save-Json 'proof-before.json' (Get-ProofSnapshot); Write-Log 'Состояние «до» запомнено — потом покажем разницу.' }
    catch { Write-Log ("   [-] состояние «до» не запомнилось ({0}) -- разницу «до и после» показать будет не с чем" -f $_.Exception.Message) }
}

$script:BackupEnabled = $true    # дальше идёт ручное применение

# куст профиля, оставшийся подключённым после оборванного запуска, — сразу
if (-not $DryRun) { Clear-StaleHiveMounts }

# Журнал отката должен писаться до первого изменения, а не выясниться в конце
if (-not (Test-JournalWritable)) {
    Write-Log 'ПРИМЕНЕНИЕ ОТМЕНЕНО: журнал отката не записывается, а без него изменения нельзя было бы вернуть. Система не тронута.'
    Write-Log '###DONE###'
    exit 1
}

# --- Уборка за старыми версиями --------------------------------------------- #
$junkFound = @(Find-JunkValues)
if ($junkFound.Count -gt 0) {
    Write-Section 'Уборка за старыми версиями программы'
    Write-Log ("   найдено параметров, записанных под числовыми именами: {0}" -f $junkFound.Count)
    $null = Remove-JunkValues
}

# Что делать, если настройки модуля не поддались: обходной путь тем же результатом
$script:ModuleHints = @{
    widgets = 'Ключи политики виджетов Windows не отдаёт. Тот же результат даёт удаление пакета «Виджеты и лента Microsoft Start» на странице «Приложения».'
}

# --- Модули по определениям ------------------------------------------------- #
foreach ($m in $script:ModuleOrder) {
    if (-not (Use-Module $m)) { continue }
    if ($m -in @('cleanup','startup','buffer','oem')) { continue }
    # ВАЖНО: имя переменной не должно совпадать с $script:Defs — в PowerShell
    # регистр не различается, и фильтрация затёрла бы весь список определений.
    $modDefs = @($script:Defs | Where-Object { $_.M -eq $m })
    if ($modDefs.Count -eq 0) { continue }
    Write-Section $script:ModuleTitles[$m]
    # Защитник под «Защитой от подделки»: политики MAPS могут лечь в реестр,
    # но Защитник их не применит, пока она включена. Предупреждаем заранее,
    # чтобы «применено» по реестру не принимали за выключенную отправку.
    if ($m -eq 'defender' -and -not $DryRun -and (Test-TamperProtection)) {
        Write-Log '   [!] включена «Защита от подделки» Защитника: облачную защиту и отправку образцов Windows не отдаёт даже политикой.'
        Write-Log '       Параметры этого модуля лягут в реестр, но подействуют, только если сначала выключить «Защиту от подделки» вручную: Безопасность Windows > Защита от вирусов и угроз > Управление настройками.'
    }
    # Без сервера выдачи номера учётная запись Microsoft не работает вовсе —
    # при входе в Windows через неё запрет не ставим, а объясняем почему.
    if ($m -eq 'gdidlock' -and (Get-GdidLockRefusal)) {
        if ((Get-GdidLockRefusal) -eq 'msa') {
            Write-Log '   [!] не применено: вы входите в Windows через учётную запись Microsoft, а без сервера выдачи номера она перестанет работать.'
            Write-Log '       Сначала перейдите на локальную учётную запись: Параметры > Учётные записи > Ваши данные.'
        } else { Write-Log ("   [!] не применено: {0}" -f (Get-ManagedReason)) }
        $script:Failures++
        continue
    }
    # Сервер выдачи закрывается для всего компьютера: у других пользователей,
    # которые входят через учётную запись Microsoft, она тоже перестанет работать
    if ($m -eq 'gdidlock' -and -not $DryRun) {
        $otherMsa = @(Get-OtherMsaAccounts)
        if ($otherMsa.Count -gt 0) {
            Write-Log ("   [!] на компьютере есть и другие учётные записи Microsoft: {0}. Пока стоит запрет, их вход в учётную запись Microsoft, Магазин, Xbox и OneDrive работать не будут." -f ($otherMsa -join ', '))
        } elseif ($script:GdidOtherMsaError) {
            Write-Log ("   [!] не удалось проверить, есть ли на компьютере другие учётные записи Microsoft ({0}). Если есть -- пока стоит запрет, их вход в учётную запись Microsoft работать не будет." -f $script:GdidOtherMsaError)
        }
    }
    $failBefore = $script:Failures + $script:Blocked
    foreach ($d in $modDefs) {
        if ($SkipItems -contains $d.Id) { Write-Log ("   [п] {0} -- пропущено по вашему выбору" -f $d.C); continue }
        if (-not (Test-DefApplicable $d)) { Write-Log ("   [-] {0} -- нет на этой версии Windows" -f $d.C); continue }
        Apply-Def $d
    }
    if (($script:Failures + $script:Blocked) -gt $failBefore -and $script:ModuleHints.ContainsKey($m)) {
        Write-Log ("   [i] {0}" -f $script:ModuleHints[$m])
    }
}

# --- Компоненты производителя ---------------------------------------------- #
if ((Use-Module 'oem') -and -not $script:JournalFailed) {
    Write-Section 'Компоненты сбора данных производителя'
    $oem = Detect-Oem
    Write-Log ("   производитель: {0} {1}" -f $oem.manufacturer, $oem.model)
    if ($oem.items.Count -eq 0) { Write-Log '   [-] компонентов сбора данных не найдено' }
    # Что было до программы, теперь пишется в подписанный журнал отката, как
    # у любой службы и задачи. Раньше список лежал отдельно, в
    # oem-disabled.json без подписи: в переносимой папке его мог дописать
    # кто угодно, и откат включил бы указанные там службы и задачи.
    foreach ($it in $oem.items) {
        if ($DryRun) { Write-Log ("   [тест] {0} {1} -- отключить" -f $it.type, $it.display); continue }
        if ($script:JournalFailed) { break }
        try {
            if ($it.type -eq 'svc') {
                $s = Get-Service -Name $it.name -ErrorAction Stop
                if ($s.StartType -eq 'Disabled' -and $s.Status -ne 'Running') { Write-Log ("   [в] {0} -- уже отключено" -f $it.display); $script:Already++; continue }
                $was = Get-SvcJournalState $it.name $s
                if (-not (Write-AheadEntry $was)) { Write-Log ("   [!] {0} -- не меняется: «как было» не легло в журнал отката" -f $it.display); $script:Failures++; break }
                try {
                    if ($s.Status -eq 'Running') { Stop-Service -Name $it.name -Force -ErrorAction SilentlyContinue }
                    Set-Service -Name $it.name -StartupType Disabled -ErrorAction Stop
                } catch { if ($was.running) { Start-Service -Name $it.name -ErrorAction SilentlyContinue }; Undo-AheadEntry $was; throw }
            } else {
                $pp = Split-TaskPath $it.name
                $st = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop
                if (Test-TaskDisabled $st) { Write-Log ("   [в] {0} -- уже отключено" -f $it.display); $script:Already++; continue }
                $tj = @{ kind = 'task'; path = $it.name; old = 'Enabled'; newValue = 'Disabled' }
                if (-not (Write-AheadEntry $tj)) { Write-Log ("   [!] {0} -- не меняется: «как было» не легло в журнал отката" -f $it.display); $script:Failures++; break }
                try { Disable-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop | Out-Null } catch { Undo-AheadEntry $tj; throw }
            }
            Write-Log ("   [+] отключено: {0}" -f $it.display); $script:Changes++
        } catch { Write-Log ("   [!] не удалось: {0} -- {1}" -f $it.display, $_.Exception.Message); $script:Failures++ }
    }
    Save-JournalEntries -Quiet
}

# --- Тот, кто вошёл в Windows, если это не мы ------------------------------- #
#  Пароль администратора мог ввести обычный пользователь: тогда настройки
#  HKCU легли бы в профиль администратора, а человек за компьютером не
#  получил бы ничего — и проверка, читая тот же HKCU, сказала бы «применено».
if (-not $script:JournalFailed) {
    $sessUser = Get-OtherSessionUser
    if ($sessUser) {
        Write-Section 'Пользователь, который вошёл в Windows'
        Write-Log ("   программа работает от имени {0}, а за компьютером {1}" -f $script:RunAccount, $sessUser.name)
        if (-not $sessUser.profile) {
            Write-Log '   [!] папку его профиля Windows не назвала -- настройки пользователя до него не дойдут'
            $script:Failures++
        } else {
            Write-Log '   настройки пользователя ложатся и в его профиль, а страж и слежение ставятся на его вход'
            Apply-ProfilesHives -Only @(@{ name = $sessUser.name; sid = $sessUser.sid; file = (Join-Path $sessUser.profile 'NTUSER.DAT') })
        }
    }
}

# --- Другие пользователи и профиль по умолчанию ----------------------------- #
if ($AllProfiles -and -not $script:JournalFailed) { Apply-ProfilesHives }

# --- Буфер телеметрии ------------------------------------------------------- #
if ((Use-Module 'buffer') -and -not $script:JournalFailed) { Purge-Buffer }

# --- Чистка ----------------------------------------------------------------- #
if ((Use-Module 'cleanup') -and -not $script:JournalFailed) {
    Write-Section 'Чистка временных файлов'
    $total = 0.0
    $wu = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    $wuWasRunning = ($wu -and $wu.Status -eq 'Running')
    if ($wuWasRunning -and -not $DryRun) { Stop-Service wuauserv -Force -ErrorAction SilentlyContinue }
    # Системные папки движок чистит сам, но только то, чей владелец
    # доверенный: в C:\Windows\Temp может завести папку любой пользователь, и
    # подложенная им ссылка увела бы удаление с правами администратора в
    # защищённую папку. Папки профиля чистит задача от имени самого
    # пользователя — там повышения, которым можно злоупотребить, нет вовсе
    # (см. Clear-UserFolders). Во временной папке свежие файлы остаются: ими
    # ещё пользуются запущенные программы.
    $sysTargets = @(
        @{ P = "$env:SystemRoot\Temp";                               L = 'временные файлы Windows' },
        @{ P = "$env:SystemRoot\SoftwareDistribution\Download";      L = 'кэш загруженных обновлений' },
        @{ P = "$env:SystemRoot\Logs\CBS";                           L = 'логи обслуживания компонентов' },
        @{ P = "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"; L = 'очередь отчётов об ошибках' }
    )
    $userTargets = @(
        @{ P = "$env:TEMP";                                      L = 'временные файлы пользователя'; Age = $script:TempKeepHours },
        @{ P = "$env:LOCALAPPDATA\Microsoft\Windows\WER";         L = 'локальные отчёты об ошибках';  Age = 0 },
        @{ P = "$env:LOCALAPPDATA\CrashDumps";                    L = 'дампы аварийных завершений';   Age = 0 },
        @{ P = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache";   L = 'кэш интернет-файлов';          Age = 0 },
        @{ P = "$env:LOCALAPPDATA\D3DSCache";                     L = 'кэш шейдеров DirectX';         Age = 0 },
        @{ P = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer";    L = 'кэш эскизов';                  Age = 0; Filter = 'thumbcache_*.db' }
    )
    $steps = $sysTargets.Count + 2 + [int][bool]$EmptyRecycleBin
    $n = 0
    Write-Log ("   шагов всего: {0}" -f $steps)
    foreach ($t in $sysTargets) {
        $n++
        $tag = '[{0,3}%] ({1}/{2})' -f [int](100.0 * $n / $steps), $n, $steps
        $total += (Clear-FolderContents -FolderPath $t.P -Label $t.L -Step $tag -TrustedOwnerOnly)
    }
    $n++
    Write-Log ('[{0,3}%] ({1}/{2}) папки профиля -- чистит задача от вашего имени, без прав администратора' -f [int](100.0 * $n / $steps), $n, $steps)
    $total += (Clear-UserFolders $userTargets)
    if (-not $DryRun) {
        # Корзина — только по отдельному согласию: вернуть из неё уже ничего
        # нельзя, а раньше она очищалась вместе с кэшами, заодно.
        if ($EmptyRecycleBin) {
            $n++
            $tag = '[{0,3}%] ({1}/{2})' -f [int](100.0 * $n / $steps), $n, $steps
            try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Log ("   {0} корзина очищена" -f $tag) } catch { Write-Log ("   {0} корзина уже пуста" -f $tag) }
        } else {
            Write-Log '   [-] корзина не тронута: очистить её можно, только отметив это отдельно'
        }
        $n++
        $tag = '[{0,3}%] ({1}/{2})' -f [int](100.0 * $n / $steps), $n, $steps
        try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop | Out-Null; Write-Log ("   {0} кэш Delivery Optimization очищен" -f $tag) } catch { Write-Log ("   {0} кэш Delivery Optimization пропущен" -f $tag) }
    }
    if ($wuWasRunning -and -not $DryRun) { Start-Service wuauserv -ErrorAction SilentlyContinue }
    Write-Log '   [100%] чистка завершена'
    Write-Log ('   ИТОГО освобождено: ~{0} МБ' -f [math]::Round($total, 1))
}

# --- Автозагрузка ----------------------------------------------------------- #
if (Use-Module 'startup') {
    Write-Section 'Автозагрузка (только отчёт, ничего не отключается)'
    $stItems = @(Get-StartupList)
    if ($stItems.Count -gt 0) {
        foreach ($s in $stItems) {
            Write-Log ("   {0} {1}" -f $(if ($s.enabled) { '*' } else { '-' }), $s.name)
            Write-Log ("       команда : {0}" -f $s.cmd)
            Write-Log ("       источник: {0}" -f $s.source)
            if ($s.note) { Write-Log ("       это     : {0}" -f $s.note) }
        }
        Write-Log ''
        Write-Log ("   Всего записей: {0}, из них работает: {1}, лишних: {2}" -f $stItems.Count,
                   @($stItems | Where-Object { $_.enabled }).Count,
                   @($stItems | Where-Object { $_.enabled -and $_.advise }).Count)
    } else { Write-Log '   (записей не найдено)' }
    Write-Log ''; Write-Log '   Отключить лишнее: страница «Автозагрузка» или -StartupSet -StartupItems <id> -StartupValue Off.'
}

# --- Итог ------------------------------------------------------------------- #
Write-Section 'Итог'
# журнал для отката — дописываем к тому, что было раньше
Save-JournalEntries
if ($script:JournalFailed) {
    Write-Log '[!] Применение остановлено на середине: журнал отката перестал записываться. Что успело измениться до остановки, видно выше.'
}
# что Windows не отдала — запоминаем для проверки; что отдала — забываем
if (-not $DryRun -and ($script:BlockedIds.Count -gt 0 -or $script:UnblockedIds.Count -gt 0)) {
    try {
        $prevB = Load-Json 'blocked.json'
        $setB = @{}
        if ($prevB -and $prevB.ids) { foreach ($i in @($prevB.ids)) { $setB["$i"] = $true } }
        foreach ($i in $script:BlockedIds.Keys) { $setB[$i] = $true }
        foreach ($i in $script:UnblockedIds.Keys) { $setB.Remove($i) }
        Save-Json 'blocked.json' @{ ids = @($setB.Keys); updated = (Get-Date).ToString('s') }
    } catch { Write-Log ("   [-] список настроек, которые Windows не отдала, не сохранился: {0}" -f $_.Exception.Message) }
}

Write-Log ("Изменений применено : {0}" -f $script:Changes)
Write-Log ("Было уже настроено : {0}" -f $script:Already)
Write-Log ("Ошибок              : {0}" -f $script:Failures)
if ($script:Blocked -gt 0) { Write-Log ("Windows не разрешила: {0} (см. пометки [-] выше)" -f $script:Blocked) }
if ($script:BackupDir) { Write-Log ("Резервная копия     : {0}" -f $script:BackupDir) }
Write-Log ''
if ($script:Changes -gt 0) { Write-Log 'Перезагрузите компьютер, чтобы всё вступило в силу. Нажмите «Проверить» — программа прочитает реальное состояние системы.' }
else { Write-Log 'Менять было нечего — всё уже настроено. Нажмите «Проверить», чтобы увидеть состояние системы.' }
Emit-Json @{ changes=$script:Changes; already=$script:Already; failures=$script:Failures
             blocked=$script:Blocked; backup=$script:BackupDir }
Write-Log '###DONE###'
# Код выхода — итог для тихого режима и сценариев: 0 — всё прошло, 2 — работа
# закончена, но с ошибками (какими — в журнале выше). Раньше применение
# всегда заканчивалось нулём, и «успех или неудача профиля» не различались.
if ($script:JournalFailed -or $script:Failures -gt 0) { exit 2 }
exit 0
