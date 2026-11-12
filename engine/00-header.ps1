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
    [switch]$GdidReissue,
    [switch]$GdidRestore
)

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
