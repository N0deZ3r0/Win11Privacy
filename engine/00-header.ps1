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
