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
    [switch]$GdidRestore
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
