#Requires -Version 5.1
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
    [switch]$ProofSave
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

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

# =========================================================================== #
#  Константы
# =========================================================================== #
$script:HostsMarkStart = '# --- Win11Privacy: блокировка телеметрии (начало) ---'
$script:HostsMarkEnd   = '# --- Win11Privacy: блокировка телеметрии (конец) ---'
$script:FwGroup        = 'Win11Privacy'
$script:DataDir        = Join-Path $env:ProgramData 'Win11Privacy'
$script:GuardTask      = 'Win11Privacy Guard'
$script:SensorTask     = 'Win11Privacy Sensor'
$script:AuditGuid      = '{0CCE9226-69AE-11D9-BED3-505054503030}'   # Filtering Platform Connection
$script:DiagDir        = Join-Path $env:ProgramData 'Microsoft\Diagnosis'
$script:Changes = 0
$script:Failures = 0
$script:Already = 0
# Журнал изменений реестра: что было до нашего вмешательства.
# Без него откат требовал ручного импорта .reg-файлов.
$script:Journal = New-Object System.Collections.Generic.List[object]
$script:TelemetryDnsRegex = 'telemetry|vortex|events\.data\.microsoft|pipe\.aria|watson|settings-win\.data|ceipdata|telecommand|sqm\.|nexusrules|nexus\.officeapps|data\.microsoft\.com|activity\.windows\.com|licensing\.mp\.microsoft|browser\.events'

# =========================================================================== #
#  Служебные функции
# =========================================================================== #
function Write-Log { param([string]$Message = '') Write-Host $Message }
function Write-Section { param([string]$Title) Write-Log ''; Write-Log ('--- ' + $Title + ' ' + ('-' * [Math]::Max(3, 60 - $Title.Length))) }
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

function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord', [string]$Comment = '')
    $label = if ($Comment) { $Comment } else { "$Path -> $Name" }
    if ($DryRun) { Write-Log "   [тест] $label"; return }

    # Если параметр уже такой, как нужно — не трогаем его: часть значений
    # панели задач Windows защищает от перезаписи даже тем же самым числом.
    $cur = Get-RegValue $Path $Name
    if ($null -ne $cur -and "$cur" -eq "$Value") { Write-Log "   [в] $label -- уже настроено"; $script:Already++; return }

    # запоминаем прежнее состояние — по нему работает откат одной кнопкой
    try {
        $script:Journal.Add(@{ kind = 'reg'; path = $Path; name = $Name; type = $Type
                               existed = [bool]($null -ne $cur); old = $(if ($null -ne $cur) { $cur } else { '' })
                               newValue = "$Value"; time = (Get-Date).ToString('s') })
    } catch { }

    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        Write-Log "   [+] $label"; $script:Changes++
    } catch {
        $after = Get-RegValue $Path $Name
        if ($null -ne $after -and "$after" -eq "$Value") { Write-Log "   [в] $label -- уже настроено"; $script:Already++; return }
        if ($_.Exception -is [UnauthorizedAccessException]) {
            Write-Log "   [!] $label -- Windows не разрешает менять этот параметр (защищён системой)"
        } else {
            Write-Log "   [!] не удалось: $label -- $($_.Exception.Message)"
        }
        $script:Failures++
    }
}

function Get-FolderSizeMB {
    param([string]$FolderPath)
    if (-not (Test-Path -LiteralPath $FolderPath)) { return 0 }
    $sum = (Get-ChildItem -LiteralPath $FolderPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if (-not $sum) { return 0 }
    return [math]::Round($sum / 1MB, 1)
}

function Clear-FolderContents {
    param([string]$FolderPath, [string]$Label, [string]$Step = '')
    if (-not (Test-Path -LiteralPath $FolderPath)) {
        if ($Step) { Write-Log ("   {0} {1} -- нечего чистить" -f $Step, $Label) }
        return 0.0
    }
    $before = Get-FolderSizeMB $FolderPath
    if ($DryRun) { Write-Log ("   {0} [тест] {1} -- можно освободить ~{2} МБ" -f $Step, $Label, $before); return 0.0 }
    Get-ChildItem -LiteralPath $FolderPath -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $freed = [math]::Max(0, [math]::Round($before - (Get-FolderSizeMB $FolderPath), 1))
    if ($Step) { Write-Log ("   {0} {1} -- освобождено {2} МБ" -f $Step, $Label, $freed) }
    else { Write-Log ("   [+] {0} -- освобождено {1} МБ" -f $Label, $freed) }
    return [double]$freed
}

function Split-TaskPath {
    param([string]$Full)
    $name = Split-Path $Full -Leaf
    $path = (Split-Path $Full -Parent)
    if (-not $path.EndsWith('\')) { $path += '\' }
    return @($path, $name)
}

function Ensure-DataDir { if (-not (Test-Path -LiteralPath $script:DataDir)) { New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null } }

function Save-Json { param([string]$Name, $Object) Ensure-DataDir; ($Object | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $script:DataDir $Name) -Encoding UTF8 }
function Load-Json { param([string]$Name) $p = Join-Path $script:DataDir $Name; if (Test-Path -LiteralPath $p) { try { return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null } } return $null }

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
    param($M, $T, $P, $N, $V, $Type = 'DWord', $C = '')
    $n = 0
    if ($script:DefSeq.ContainsKey($M)) { $n = [int]$script:DefSeq[$M] }
    $script:DefSeq[$M] = $n + 1
    $script:Defs.Add(@{ M=$M; T=$T; P=$P; N=$N; V=$V; Type=$Type; C=$C; Id=("{0}#{1}" -f $M, $n) })
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

$sys = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
Def 'activity' 'reg' $sys 'EnableActivityFeed' 0 'DWord' 'лента активности — выкл'
Def 'activity' 'reg' $sys 'PublishUserActivities' 0 'DWord' 'не публиковать активность'
Def 'activity' 'reg' $sys 'UploadUserActivities' 0 'DWord' 'не выгружать активность в облако'
Def 'activity' 'reg' $sys 'AllowClipboardHistory' 0 'DWord' 'история буфера обмена — выкл'
Def 'activity' 'reg' $sys 'AllowCrossDeviceClipboard' 0 'DWord' 'синхронизация буфера между устройствами — выкл'

Def 'input' 'reg' 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1 'DWord' 'не собирать набранный текст'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1 'DWord' 'не собирать рукописный ввод'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0 'DWord' 'не собирать контакты'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0 'DWord' 'персонализация ввода — отказ'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0 'DWord' 'облачное распознавание речи — выкл'
Def 'input' 'reg' 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1 'DWord' 'не отдавать сайтам список языков'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\appDiagnostics' 'Value' 'Deny' 'String' 'приложениям запрещена диагностика других приложений'

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

$ai = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
Def 'copilot' 'reg' 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 'DWord' 'Windows Copilot — выкл'
Def 'copilot' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 'DWord' 'Windows Copilot — выкл для всех'
Def 'copilot' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0 'DWord' 'кнопка Copilot на панели задач — убрать'
Def 'copilot' 'reg' $ai 'DisableAIDataAnalysis' 1 'DWord' 'Recall (снимки экрана) — выкл'
Def 'copilot' 'reg' $ai 'AllowRecallEnablement' 0 'DWord' 'запрет включения Recall'
Def 'copilot' 'reg' 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1 'DWord' 'Recall — выкл для пользователя'

# Весь ИИ Windows
Def 'ai' 'reg' $ai 'DisableClickToDo' 1 'DWord' 'Click to Do — выкл'
Def 'ai' 'reg' $ai 'TurnOffSavingSnapshots' 1 'DWord' 'сохранение снимков экрана — выкл'
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
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'HideRecommendedSection' 1 'DWord' 'Пуск: раздел «Рекомендуем» — скрыть'
Def 'ai' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowRecommendations' 0 'DWord' 'Проводник: рекомендации в «Главной» — выкл'

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

Def 'widgets' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 'DWord' 'виджеты и лента новостей MSN — выкл'
Def 'widgets' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 0 'DWord' 'кнопка виджетов на панели задач — убрать'
Def 'widgets' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0 'DWord' 'лента новостей и интересов — выкл (запасной ключ)'

$dfn = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'
Def 'defender' 'reg' $dfn 'SpyNetReporting' 0 'DWord' 'Защитник: облачная отправка MAPS — выкл'
Def 'defender' 'reg' $dfn 'SubmitSamplesConsent' 2 'DWord' 'Защитник: отправка образцов файлов — никогда'

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
    '\Microsoft\Windows\Autochk\Proxy')) {
    Def 'services' 'task' $tp '' 'Disabled' '' ('задача ' + (Split-Path $tp -Leaf))
}

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

$script:ModuleOrder = @('telemetry','errors','activity','input','edge','delivery','location','ads','widgets','search','copilot','ai',
                        'defender','onedrive','services','etw','hosts','firewall','fwips','doh','buffer','app_nvidia','app_vscode','app_chrome','app_firefox',
                        'app_office','app_devtools','app_vs','oem','cleanup','startup')
$script:ModuleTitles = @{
    telemetry='Телеметрия и диагностика'; errors='Отчёты об ошибках'; activity='История активности и буфер обмена';
    input='Персонализация ввода, рукописный ввод, речь'; edge='Microsoft Edge'; delivery='Раздача обновлений другим ПК';
    location='Геолокация и поиск устройства'; ads='Рекламный ID и реклама в интерфейсе'; widgets='Виджеты и лента новостей';
    search='Поиск: Bing, Cortana, облако'; copilot='Copilot и Recall';
    ai='ИИ-функции Windows'; defender='Защитник: облако и образцы'; etw='Сессии трассировки телеметрии'; onedrive='OneDrive: синхронизация и реклама'; services='Службы и задачи телеметрии'; hosts='Блокировка телеметрийных доменов (hosts)';
    firewall='Брандмауэр: блокировка служб телеметрии'; fwips='Брандмауэр: адреса сбора телеметрии'; doh='Шифрованный DNS (обход блокировки)'; buffer='Неотправленная телеметрия'; app_nvidia='NVIDIA';
    app_vscode='Visual Studio Code'; app_chrome='Google Chrome'; app_firefox='Mozilla Firefox'; app_office='Microsoft Office';
    app_devtools='PowerShell 7 / .NET SDK'; app_vs='Visual Studio'; oem='Компоненты сбора данных производителя';
    cleanup='Чистка временных файлов'; startup='Автозагрузка (отчёт)'
}

# =========================================================================== #
#  Файлы конфигурации сторонних программ
# =========================================================================== #
function Get-VsCodeSettingsPath { return (Join-Path $env:APPDATA 'Code\User\settings.json') }

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

function Set-VsCodeValue {
    param([string]$Key, $Value, [string]$Comment)
    $p = Get-VsCodeSettingsPath
    if ($DryRun) { Write-Log "   [тест] $Comment"; return }
    try {
        $dir = Split-Path $p -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $txt = if (Test-Path -LiteralPath $p) { Get-Content -LiteralPath $p -Raw -ErrorAction Stop } else { '' }
        if (-not $txt -or $txt.Trim() -eq '') { $txt = "{`n}" }
        $bak = "$p.win11privacy.bak"
        if (-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $p -Destination $bak -Force -ErrorAction SilentlyContinue }
        $jsonVal = if ($Value -is [bool]) { $Value.ToString().ToLower() } elseif ($Value -is [string]) { '"' + $Value + '"' } else { "$Value" }
        $rx = '("' + [regex]::Escape($Key) + '"\s*:\s*)("[^"]*"|true|false|-?[\d.]+)'
        if ([regex]::IsMatch($txt, $rx)) {
            $txt = [regex]::Replace($txt, $rx, ('${1}' + $jsonVal), 1)
        } else {
            $idx = $txt.IndexOf('{')
            if ($idx -lt 0) { $txt = "{`n}"; $idx = 0 }
            $insert = "`n    `"$Key`": $jsonVal,"
            $rest = $txt.Substring($idx + 1)
            if ($rest.Trim() -eq '}') { $insert = $insert.TrimEnd(',') + "`n" }
            $txt = $txt.Substring(0, $idx + 1) + $insert + $rest
        }
        [IO.File]::WriteAllText($p, $txt, (New-Object System.Text.UTF8Encoding($false)))
        Write-Log "   [+] $Comment"; $script:Changes++
    } catch { Write-Log "   [!] не удалось: $Comment -- $($_.Exception.Message)"; $script:Failures++ }
}

function Get-FirefoxPoliciesPath {
    foreach ($d in @((Join-Path $env:ProgramFiles 'Mozilla Firefox'), (Join-Path ${env:ProgramFiles(x86)} 'Mozilla Firefox'))) {
        if ($d -and (Test-Path -LiteralPath (Join-Path $d 'firefox.exe'))) { return (Join-Path $d 'distribution\policies.json') }
    }
    return $null
}

function Get-FirefoxPolicy {
    param([string]$Key)
    $p = Get-FirefoxPoliciesPath
    if (-not $p -or -not (Test-Path -LiteralPath $p)) { return $null }
    try { $j = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json; return $j.policies.$Key } catch { return $null }
}

function Set-FirefoxPolicy {
    param([string]$Key, $Value, [string]$Comment)
    $p = Get-FirefoxPoliciesPath
    if (-not $p) { Write-Log "   [-] Firefox не найден"; return }
    if ($DryRun) { Write-Log "   [тест] $Comment"; return }
    try {
        $dir = Split-Path $p -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $obj = $null
        if (Test-Path -LiteralPath $p) {
            $bak = "$p.win11privacy.bak"
            if (-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $p -Destination $bak -Force -ErrorAction SilentlyContinue }
            try { $obj = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json } catch { $obj = $null }
        }
        if (-not $obj) { $obj = New-Object PSObject }
        if (-not ($obj.PSObject.Properties.Name -contains 'policies')) { $obj | Add-Member -NotePropertyName 'policies' -NotePropertyValue (New-Object PSObject) }
        if ($obj.policies.PSObject.Properties.Name -contains $Key) { $obj.policies.$Key = $Value }
        else { $obj.policies | Add-Member -NotePropertyName $Key -NotePropertyValue $Value }
        ($obj | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $p -Encoding UTF8
        Write-Log "   [+] $Comment"; $script:Changes++
    } catch { Write-Log "   [!] не удалось: $Comment -- $($_.Exception.Message)"; $script:Failures++ }
}

# =========================================================================== #
#  Применение / проверка одного определения
# =========================================================================== #
function Apply-Def {
    param($d)
    switch ($d.T) {
        'reg' { Set-Reg -Path $d.P -Name $d.N -Value $d.V -Type $d.Type -Comment $d.C }
        'regif' {
            # сессия трассировки есть не на каждой сборке Windows — чего нет, то не создаём
            if (Test-Path -LiteralPath $d.P) { Set-Reg -Path $d.P -Name $d.N -Value $d.V -Type $d.Type -Comment $d.C }
            else { Write-Log ("   [-] {0} -- нет на этой системе" -f $d.C) }
        }
        'svc' {
            if ($DryRun) { Write-Log "   [тест] $($d.C) -- отключить"; return }
            try {
                $s = Get-Service -Name $d.P -ErrorAction Stop
                if ($s.Status -eq 'Running') { Stop-Service -Name $d.P -Force -ErrorAction SilentlyContinue }
                Set-Service -Name $d.P -StartupType Disabled -ErrorAction Stop
                Write-Log "   [+] $($d.C) -- остановлена и отключена"; $script:Changes++
            } catch { Write-Log "   [-] $($d.C) -- недоступна" }
        }
        'svcopt' {
            $s = Get-Service -Name $d.P -ErrorAction SilentlyContinue
            if (-not $s) { return }
            if ($DryRun) { Write-Log "   [тест] $($d.C) -- отключить"; return }
            try {
                if ($s.Status -eq 'Running') { Stop-Service -Name $d.P -Force -ErrorAction SilentlyContinue }
                Set-Service -Name $d.P -StartupType Disabled -ErrorAction Stop
                Write-Log "   [+] $($d.C) -- отключена"; $script:Changes++
            } catch { Write-Log "   [-] $($d.C) -- не удалось" }
        }
        'task' {
            $pp = Split-TaskPath $d.P
            if ($DryRun) { Write-Log "   [тест] $($d.C) -- отключить"; return }
            try { Disable-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop | Out-Null; Write-Log "   [+] $($d.C) -- отключена"; $script:Changes++ }
            catch { Write-Log "   [-] $($d.C) -- не найдена" }
        }
        'taskglob' {
            $ts = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like $d.P })
            if ($ts.Count -eq 0) { return }
            foreach ($t in $ts) {
                if ($DryRun) { Write-Log "   [тест] задача $($t.TaskName) -- отключить"; continue }
                try { Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null; Write-Log "   [+] задача $($t.TaskName) -- отключена"; $script:Changes++ }
                catch { Write-Log "   [-] задача $($t.TaskName) -- не удалось" }
            }
        }
        'env' {
            if ($DryRun) { Write-Log "   [тест] $($d.C)"; return }
            try { [Environment]::SetEnvironmentVariable($d.P, [string]$d.V, 'User'); Write-Log "   [+] $($d.C)"; $script:Changes++ }
            catch { Write-Log "   [!] не удалось: $($d.C)"; $script:Failures++ }
        }
        'vscode'  { Set-VsCodeValue -Key $d.P -Value $d.V -Comment $d.C }
        'firefox' { Set-FirefoxPolicy -Key $d.P -Value $d.V -Comment $d.C }
        'hosts'   { Apply-Hosts }
        'fwsvc'   { Apply-FwRule -Kind 'svc' -Target $d.P -Comment $d.C }
        'fwapp'   { Apply-FwRule -Kind 'app' -Target $d.P -Comment $d.C }
        'fwips'   { Apply-FwIpBlock }
    }
}

function Check-Def {
    param($d)
    $ok = $false; $actual = ''
    switch ($d.T) {
        'regif' {
            if (-not (Test-Path -LiteralPath $d.P)) { $ok = $true; $actual = 'нет на этой системе' }
            else {
                $v = Get-RegValue $d.P $d.N
                $actual = if ($null -eq $v) { 'не задано' } else { "$v" }
                $ok = ($null -ne $v) -and ("$v" -eq "$($d.V)")
            }
        }
        'reg' {
            $v = Get-RegValue $d.P $d.N
            $actual = if ($null -eq $v) { 'не задано' } else { "$v" }
            $ok = ($null -ne $v) -and ("$v" -eq "$($d.V)")
        }
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
            else { $actual = [string]$t.State; $ok = ($t.State -eq 'Disabled') }
        }
        'taskglob' {
            $ts = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like $d.P })
            $bad = @($ts | Where-Object { $_.State -ne 'Disabled' })
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
        'hosts' {
            $ok = Test-HostsBlock; $actual = if ($ok) { 'блок установлен' } else { 'нет блока' }
        }
        'fwips' { $ok = Test-FwIpRule; $actual = if ($ok) { 'адреса заблокированы' } else { 'нет правила' } }
        'fwsvc' { $ok = Test-FwRule -Kind 'svc' -Target $d.P; $actual = if ($ok) { 'правило есть' } else { 'нет правила' } }
        'fwapp' { $ok = Test-FwRule -Kind 'app' -Target $d.P; $actual = if ($ok) { 'правило есть' } else { 'нет правила' } }
    }
    return @{ module=$d.M; name=$d.C; ok=[bool]$ok; expected="$($d.V)"; actual=$actual }
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
    'browser.events.data.msn.com','self.events.data.microsoft.com',
    'activity.windows.com','licensing.mp.microsoft.com')
$script:HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"

function Test-HostsBlock { try { return (@(Get-Content -LiteralPath $script:HostsPath -ErrorAction Stop) -contains $script:HostsMarkStart) } catch { return $false } }

function Apply-Hosts {
    if ($DryRun) { Write-Log ("   [тест] будет заблокировано доменов: {0}" -f $script:HostsDomains.Count); return }
    try {
        if ($script:BackupDir -and (Test-Path -LiteralPath $script:BackupDir)) {
            Copy-Item -LiteralPath $script:HostsPath -Destination (Join-Path $script:BackupDir 'hosts.original') -Force -ErrorAction SilentlyContinue
        }
        if (Test-HostsBlock) { Write-Log '   [-] блок уже присутствует'; return }
        $block = @('') + $script:HostsMarkStart
        foreach ($d in $script:HostsDomains) { $block += ('0.0.0.0 ' + $d) }
        $block += $script:HostsMarkEnd
        Add-Content -LiteralPath $script:HostsPath -Value $block -Encoding ASCII -ErrorAction Stop
        ipconfig /flushdns | Out-Null
        Write-Log ("   [+] заблокировано доменов: {0}" -f $script:HostsDomains.Count); $script:Changes++
    } catch { Write-Log "   [!] не удалось изменить hosts: $($_.Exception.Message) (возможно, защищён антивирусом)"; $script:Failures++ }
}

function Remove-HostsBlock {
    try {
        $lines = Get-Content -LiteralPath $script:HostsPath -ErrorAction Stop
        $s = [Array]::IndexOf($lines, $script:HostsMarkStart); $e = [Array]::IndexOf($lines, $script:HostsMarkEnd)
        if ($s -ge 0 -and $e -gt $s) {
            $new = @()
            if ($s -gt 0) { $new += $lines[0..($s-1)] }
            if ($e -lt ($lines.Count - 1)) { $new += $lines[($e+1)..($lines.Count-1)] }
            Set-Content -LiteralPath $script:HostsPath -Value $new -Encoding ASCII -Force
            ipconfig /flushdns | Out-Null
            Write-Log '   [+] блок блокировки доменов удалён'
        } else { Write-Log '   [-] блока в hosts нет' }
    } catch { Write-Log "   [!] hosts: $($_.Exception.Message)" }
}

# --- брандмауэр ------------------------------------------------------------- #
function Get-FwRuleName { param([string]$Kind, [string]$Target) if ($Kind -eq 'svc') { return "Win11Privacy: служба $Target" } return ("Win11Privacy: " + (Split-Path $Target -Leaf)) }

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

function Get-TelemetryIpList {
    $set = @{}
    foreach ($ip in $script:TelemetryIps) { $set[$ip] = $true }
    foreach ($d in $script:HostsDomains) {
        try {
            foreach ($r in (Resolve-DnsName -Name $d -Type A -ErrorAction Stop)) {
                if ($r.IPAddress -and (Test-PublicIp $r.IPAddress)) { $set[$r.IPAddress] = $true }
            }
        } catch { }
    }
    return @($set.Keys)
}

function Test-FwIpRule {
    return [bool](Get-NetFirewallRule -DisplayName $script:FwIpRuleName -ErrorAction SilentlyContinue)
}

function Apply-FwIpBlock {
    if ($DryRun) { Write-Log '   [тест] будут заблокированы адреса сбора телеметрии'; return }
    try {
        $ips = Get-TelemetryIpList
        if ($ips.Count -eq 0) { Write-Log '   [-] адреса не определились'; return }
        Get-NetFirewallRule -DisplayName $script:FwIpRuleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName $script:FwIpRuleName -Group $script:FwGroup -Direction Outbound -Action Block `
            -RemoteAddress $ips -Profile Any -Enabled True -ErrorAction Stop | Out-Null
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

function Remove-FwRules {
    try {
        $rules = @(Get-NetFirewallRule -Group $script:FwGroup -ErrorAction SilentlyContinue)
        if ($rules.Count -gt 0) { $rules | Remove-NetFirewallRule -ErrorAction SilentlyContinue; Write-Log "   [+] удалено правил брандмауэра: $($rules.Count)" }
        else { Write-Log '   [-] правил брандмауэра нет' }
    } catch { Write-Log "   [!] брандмауэр: $($_.Exception.Message)" }
}

# --- аудит соединений (монитор) -------------------------------------------- #
function Get-MonitorEnabled {
    try {
        $out = & auditpol.exe /get /subcategory:$script:AuditGuid /r 2>$null
        $csv = $out | Where-Object { $_ -and $_ -notmatch '^Machine Name' -and $_ -notmatch '^Имя компьютера' } | Select-Object -Last 1
        if (-not $csv) { return $false }
        return ($csv -match 'Failure|Отказ|Сбой')
    } catch { return $false }
}

function Set-MonitorEnabled {
    param([bool]$On)
    $flag = if ($On) { 'enable' } else { 'disable' }
    try {
        $null = & auditpol.exe /set /subcategory:$script:AuditGuid /failure:$flag 2>&1
        Write-Log ("   [+] журнал перехваченных соединений: {0}" -f $(if ($On) { 'включён' } else { 'выключен' }))
        return $true
    } catch { Write-Log "   [!] auditpol: $($_.Exception.Message)"; return $false }
}

function Test-PublicIp {
    param([string]$Ip)
    if (-not $Ip) { return $false }
    if ($Ip -match '^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|22[4-9]\.|23\d\.|255\.|0\.)') { return $false }
    if ($Ip -match '^(fe80|ff0|::1|fc|fd)') { return $false }
    return $true
}

function Get-MonitorStats {
    param([int]$Hours)
    $since = (Get-Date).AddHours(-$Hours)
    $events = @()
    try { $events = @(Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=5157; StartTime=$since } -MaxEvents 6000 -ErrorAction Stop) } catch { }
    $dns = @{}
    try { Get-DnsClientCache -ErrorAction SilentlyContinue | ForEach-Object { if ($_.Data -and -not $dns.ContainsKey($_.Data)) { $dns[$_.Data] = $_.Entry } } } catch { }
    $byProc = @{}; $byDest = @{}; $total = 0; $telemetryHits = 0
    foreach ($ev in $events) {
        try {
            $x = [xml]$ev.ToXml()
            $data = @{}
            foreach ($n in $x.Event.EventData.Data) { $data[[string]$n.Name] = [string]$n.'#text' }
            if ($data['Direction'] -ne '%%14593') { continue }          # только исходящие
            $ip = $data['DestAddress']
            if (-not (Test-PublicIp $ip)) { continue }
            $app = $data['Application']; if ($app) { $app = ($app -split '\\')[-1] } else { $app = '?' }
            $total++
            if ($byProc.ContainsKey($app)) { $byProc[$app]++ } else { $byProc[$app] = 1 }
            $key = $ip
            if ($byDest.ContainsKey($key)) { $byDest[$key].count++ } else {
                $dom = if ($dns.ContainsKey($ip)) { $dns[$ip] } else { '' }
                $byDest[$key] = @{ ip=$ip; domain=$dom; count=1; port=$data['DestPort'] }
            }
            if ($byDest[$key].domain -match $script:TelemetryDnsRegex) { $telemetryHits++ }
        } catch { }
    }
    $procList = @($byProc.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 12 | ForEach-Object { @{ name=$_.Key; count=$_.Value } })
    $destList = @($byDest.Values | Sort-Object { $_.count } -Descending | Select-Object -First 25)
    return @{ enabled=(Get-MonitorEnabled); hours=$Hours; since=$since.ToString('yyyy-MM-dd HH:mm'); total=$total;
              telemetryHits=$telemetryHits; events=$events.Count; byProcess=$procList; byDest=$destList;
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
function Get-BufferInfo {
    $size = -1; $files = 0
    try {
        $items = @(Get-ChildItem -LiteralPath $script:DiagDir -Recurse -Force -Include '*.rbs','*.etl' -ErrorAction Stop)
        $files = $items.Count
        $sum = ($items | Measure-Object -Property Length -Sum).Sum
        $size = if ($sum) { [math]::Round($sum / 1MB, 2) } else { 0 }
    } catch { $size = -1 }
    return @{ mb=$size; files=$files; path=$script:DiagDir }
}

function Purge-Buffer {
    Write-Section 'Неотправленная телеметрия'
    $info = Get-BufferInfo
    if ($info.mb -eq 0 -and $info.files -eq 0) { Write-Log '   [-] буфер пуст'; return }
    if ($DryRun) { Write-Log ("   [тест] будет стёрто ~{0} МБ ({1} файлов)" -f $info.mb, $info.files); return }
    $svc = Get-Service -Name DiagTrack -ErrorAction SilentlyContinue
    $wasRunning = ($svc -and $svc.Status -eq 'Running')
    if ($wasRunning) { Stop-Service -Name DiagTrack -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 800 }
    try {
        $null = & takeown.exe /F "$script:DiagDir" /R /A /D Y 2>&1
        $null = & icacls.exe "$script:DiagDir" /grant '*S-1-5-32-544:(OI)(CI)F' /T /C /Q 2>&1
    } catch { }
    $deleted = 0; $bytes = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $script:DiagDir -Recurse -Force -Include '*.rbs','*.etl' -ErrorAction SilentlyContinue)) {
        try { $len = $f.Length; Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $deleted++; $bytes += $len } catch { }
    }
    if ($wasRunning -and $svc.StartType -ne 'Disabled') { Start-Service -Name DiagTrack -ErrorAction SilentlyContinue }
    if ($deleted -gt 0) { Write-Log ("   [+] стёрто файлов: {0}, {1} МБ" -f $deleted, [math]::Round($bytes / 1MB, 2)); $script:Changes++ }
    else { Write-Log '   [!] не удалось удалить файлы буфера (доступ запрещён)'; $script:Failures++ }
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
        apps = $apps; oem = $oem
        guardInstalled = [bool]$guardTask
        watcherInstalled = [bool](Get-ScheduledTask -TaskName 'Win11Privacy Watcher' -ErrorAction SilentlyContinue)
        sensorGuardInstalled = [bool](Get-ScheduledTask -TaskName $script:SensorTask -ErrorAction SilentlyContinue)
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

if ($EnableMonitor) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Монитор утечек'
    foreach ($d in $script:Defs) { if ($d.M -eq 'firewall') { Apply-Def $d } }
    $ok = Set-MonitorEnabled $true
    Write-Log 'Перехваченные попытки отправки теперь считаются. Статистика — на странице «Монитор».'
    Write-Log '###DONE###'
    exit $(if ($ok) { 0 } else { 1 })
}

if ($DisableMonitor) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Монитор утечек'
    $ok = Set-MonitorEnabled $false
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

function Run-Guard {
    param([bool]$Verbose)
    $profile = Load-Json 'profile.json'
    if (-not $profile -or -not $profile.modules) { Write-Log 'Профиль стража не найден.'; return @{ error='нет профиля' } }
    $mods = @($profile.modules)
    $last = Load-Json 'guard-last.json'
    $lastTime = if ($last -and $last.time) { [datetime]$last.time } else { (Get-Date).AddDays(-30) }

    $drifted = @()
    foreach ($d in $script:Defs) {
        if ($mods -notcontains $d.M) { continue }
        if ($d.T -in @('taskglob','svcopt')) { continue }
        $r = Check-Def $d
        if (-not $r.ok) { $drifted += $r }
    }
    $driftModules = @($drifted | ForEach-Object { $_.module } | Select-Object -Unique)
    $fixed = 0
    if ($driftModules.Count -gt 0) {
        $script:Modules = $driftModules
        foreach ($m in $driftModules) {
            if ($m -in @('cleanup','startup','buffer','oem')) { continue }
            Write-Section ($script:ModuleTitles[$m])
            foreach ($d in $script:Defs) { if ($d.M -eq $m) { Apply-Def $d; $fixed++ } }
        }
    }
    $kbs = Get-RecentHotfixes -Since $lastTime
    $summary = @{
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); checked = $mods; drifted = @($drifted | ForEach-Object { $_.name })
        driftModules = @($driftModules | ForEach-Object { $script:ModuleTitles[$_] }); fixed = $fixed; hotfixes = $kbs
    }
    Save-Json 'guard-last.json' $summary
    $line = "{0}  проверено модулей: {1}, сбито: {2}, исправлено: {3}, обновления: {4}" -f $summary.time, $mods.Count, $drifted.Count, $fixed, ($kbs -join ' ')
    try { Ensure-DataDir; Add-Content -LiteralPath (Join-Path $script:DataDir 'guard.log') -Value $line -Encoding UTF8 } catch { }
    if ($drifted.Count -gt 0) {
        $kbText = if ($kbs.Count -gt 0) { " После обновлений: " + ($kbs -join ', ') + "." } else { '' }
        Show-Toast 'Страж приватности' ("Windows вернула настроек: {0}. Исправлено.{1}" -f $drifted.Count, $kbText)
    }
    Write-Log $line
    return $summary
}

if ($InstallGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Страж приватности'
    try {
        Ensure-DataDir
        $engineDst = Join-Path $script:DataDir 'engine.ps1'
        Copy-Item -LiteralPath $PSCommandPath -Destination $engineDst -Force
        $mods = @($Modules | Where-Object { $_ -notin @('cleanup','startup','buffer') })
        Save-Json 'profile.json' @{ version=1; modules=$mods; created=(Get-Date).ToString('s') }
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $engineDst + '" -Guard')
        $t1 = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $t1.Delay = 'PT3M'
        $t2 = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 12:00
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $script:GuardTask -Action $action -Trigger @($t1, $t2) -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log ("   [+] страж установлен: проверка через 3 минуты после входа в систему и по воскресеньям в 12:00")
        Write-Log ("   [+] отслеживается модулей: {0}" -f $mods.Count)
        Write-Log ("   [+] журнал: {0}" -f (Join-Path $script:DataDir 'guard.log'))
    } catch { Write-Log "   [!] не удалось установить стража: $($_.Exception.Message)" }
    Write-Log '###DONE###'
    exit 0
}

if ($RemoveGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Страж приватности'
    try { Unregister-ScheduledTask -TaskName $script:GuardTask -Confirm:$false -ErrorAction Stop; Write-Log '   [+] задача стража удалена' } catch { Write-Log '   [-] задача стража не найдена' }
    Write-Log '###DONE###'
    exit 0
}

if ($Guard) {
    if (-not (Test-Admin)) { exit 1 }
    $null = Run-Guard -Verbose $false
    exit 0
}

if ($GuardNow) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Страж: проверка сейчас'
    $s = Run-Guard -Verbose $true
    Emit-Json $s
    Write-Log '###DONE###'
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

    $result = @{
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); hours = $Hours; recording = $true
        total = $events.Count; distinctNames = $names.Count
        mb = [math]::Round($mbTotal, 2); perDay = $perDay; mbPerDay = $mbDay
        perYear = [math]::Round($perDay * 365, 0); mbPerYear = [math]::Round($mbDay * 365, 1)
        categories = $catList; identifiers = $idList; apps = $appList
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

if ($XrayScan) {
    $r = Invoke-XrayScan -Hours $XrayHours -Max $XrayMax
    if (-not $r.error) { try { Save-Json 'xray-last.json' @{ time = $r.time; perDay = $r.perDay; mbPerDay = $r.mbPerDay } } catch { } }
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
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $script:XrayDbDir -Force -ErrorAction SilentlyContinue)) {
        try { Remove-Item -LiteralPath $f.FullName -Force -Recurse -ErrorAction Stop; $n++ } catch { }
    }
    if ($was -and $svc.StartType -ne 'Disabled') { Start-Service DiagTrack -ErrorAction SilentlyContinue }
    Write-Log ("   [+] удалено файлов: {0} (было {1} МБ)" -f $n, $before)
    Emit-Json (Get-XrayDbInfo)
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

if ($SnapshotList) { Emit-Json @{ snapshots = (Get-SnapshotList) }; exit 0 }

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
    try {
        Ensure-DataDir
        $engineDst = Join-Path $script:DataDir 'engine.ps1'
        if ($PSCommandPath -ne $engineDst) { Copy-Item -LiteralPath $PSCommandPath -Destination $engineDst -Force }
        if (-not (Get-MonitorEnabled)) { Set-MonitorEnabled $true | Out-Null }
        foreach ($d in $script:Defs) { if ($d.M -eq 'firewall') { Apply-Def $d } }

        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $engineDst + '" -WatcherNotify')
        $cls = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
        $trigger = New-CimInstance -CimClass $cls -ClientOnly
        $trigger.Subscription = '<QueryList><Query Id="0" Path="Security"><Select Path="Security">*[System[(EventID=5157)]]</Select></Query></QueryList>'
        $trigger.Enabled = $true
        $trigger.Delay = 'PT5S'
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 3)
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $script:WatcherTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log '   [+] уведомления включены: всплывашка при перехвате отправки телеметрии'
        Write-Log '   [+] чтобы не мешать, одно уведомление не чаще чем раз в 10 минут'
    } catch { Write-Log "   [!] не удалось: $($_.Exception.Message)" }
    Write-Log '###DONE###'
    exit 0
}

if ($RemoveWatcher) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Живые уведомления'
    try { Unregister-ScheduledTask -TaskName $script:WatcherTask -Confirm:$false -ErrorAction Stop; Write-Log '   [+] уведомления выключены' }
    catch { Write-Log '   [-] задача уведомлений не найдена' }
    Write-Log '###DONE###'
    exit 0
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
    $since = (Get-Date).AddMinutes(-11)
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
    @{ id='appDiagnostics';         title='Диагностика других программ' }
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
                try {
                    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 -Comment 'рекламный ID — выкл'
                    Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name 'Id' -Force -ErrorAction Stop
                    Write-Log '   [+] рекламный идентификатор стёрт'; $script:Changes++
                } catch { Write-Log '   [-] рекламный ID уже стёрт' }
            }
            'networks' {
                if ($DryRun) { Write-Log '   [тест] история сетей — очистить'; break }
                $n = 0
                foreach ($k in @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles' -ErrorAction SilentlyContinue)) {
                    try { Remove-Item -LiteralPath $k.PSPath -Recurse -Force -ErrorAction Stop; $n++ } catch { }
                }
                foreach ($sig in @('Unmanaged','Managed')) {
                    foreach ($k in @(Get-ChildItem ('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\' + $sig) -ErrorAction SilentlyContinue)) {
                        try { Remove-Item -LiteralPath $k.PSPath -Recurse -Force -ErrorAction Stop } catch { }
                    }
                }
                Write-Log ("   [+] история сетей очищена: {0} записей (пароли Wi-Fi не тронуты)" -f $n); $script:Changes++
            }
            'activity' {
                foreach ($svc in @(Get-Service -Name 'cdp*' -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' })) {
                    if (-not $DryRun) { Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue }
                }
                $null = Clear-FolderContents (Join-Path $env:LOCALAPPDATA 'ConnectedDevicesPlatform') 'база истории активности'
            }
            'recent' {
                $null = Clear-FolderContents ([Environment]::GetFolderPath('Recent')) 'недавние документы'
                if (-not $DryRun) {
                    try { Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs' -Recurse -Force -ErrorAction Stop; Write-Log '   [+] список RecentDocs в реестре очищен' } catch { }
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
                $null = Clear-FolderContents (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Clipboard') 'история буфера обмена'
            }
            'wer' {
                $null = Clear-FolderContents (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive') 'архив отчётов об ошибках'
                $null = Clear-FolderContents (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue') 'очередь отчётов об ошибках'
                $null = Clear-FolderContents (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER') 'локальные отчёты об ошибках'
            }
            'inputpers' {
                $null = Clear-FolderContents (Join-Path $env:APPDATA 'Microsoft\InputPersonalization') 'личный словарь набора'
            }
            'dnscache' {
                if ($DryRun) { Write-Log '   [тест] кэш DNS — очистить'; break }
                try { Clear-DnsClientCache -ErrorAction Stop; Write-Log '   [+] кэш DNS очищен'; $script:Changes++ } catch { Write-Log '   [!] не удалось очистить кэш DNS' }
            }
            default { Write-Log ("   [-] неизвестный элемент следа: {0}" -f $id) }
        }
    }
}

# --- отозвать или вернуть доступ программы к датчику ---
if ($SensorSet) {
    $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\' + $SensorKey
    $r = @{ key = $SensorKey; value = $SensorValue; ok = $false }
    try {
        if (-not (Test-Path -LiteralPath $root)) { New-Item -Path $root -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $root -Name 'Value' -Value $SensorValue -PropertyType String -Force -ErrorAction Stop | Out-Null
        $r.ok = $true
    } catch { $r.error = $_.Exception.Message }
    Emit-Json $r
    exit 0
}

# --- список отдельных настроек внутри модулей ---
if ($ListDefs) {
    $groups = @()
    foreach ($m in $script:ModuleOrder) {
        $mi = @($script:Defs | Where-Object { $_.M -eq $m })
        if ($mi.Count -eq 0) { continue }
        $groups += @{ module = $m; title = $script:ModuleTitles[$m]
                      items = @($mi | ForEach-Object { @{ id = $_.Id; name = $_.C } }) }
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
    try {
        Ensure-DataDir
        $engineDst = Join-Path $script:DataDir 'engine.ps1'
        if ($PSCommandPath -ne $engineDst) { Copy-Item -LiteralPath $PSCommandPath -Destination $engineDst -Force }

        # закладываем текущий список программ как известный — без уведомлений
        $r0 = Get-SpyReport
        try { $null = Update-SensorHistory $r0 } catch { }
        $pairs = @()
        foreach ($c in @($r0.caps)) { foreach ($it in @($c.items)) { $pairs += ($c.id + '|' + $it.app) } }
        Save-Json 'sensor-apps.json' @{ pairs = $pairs; updated = (Get-Date).ToString('s') }

        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $engineDst + '" -SensorGuard')
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration (New-TimeSpan -Days 3650)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $script:SensorTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log '   [+] слежение включено: сверка журнала каждые 30 минут'
        Write-Log '   [+] новая программа получит доступ к камере, микрофону или геолокации — придёт уведомление'
        Write-Log ("   [+] сейчас программ в журнале: {0}" -f $pairs.Count)
        Write-Log '   [+] попутно накапливается история для графика на «Обзоре»'
    } catch { Write-Log "   [!] не удалось: $($_.Exception.Message)" }
    Write-Log '###DONE###'
    exit 0
}

if ($RemoveSensorGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Слежение за датчиками'
    try { Unregister-ScheduledTask -TaskName $script:SensorTask -Confirm:$false -ErrorAction Stop; Write-Log '   [+] слежение отключено' }
    catch { Write-Log '   [-] задача слежения не найдена' }
    Write-Log '###DONE###'
    exit 0
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
    try { Save-Json 'sensor-apps.json' @{ pairs = @($known.Keys); updated = (Get-Date).ToString('s') } } catch { }

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

function Test-AppxProtected {
    param([string]$Name)
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
    Emit-Json @{ apps = (Get-AppxList); time = (Get-Date).ToString('yyyy-MM-dd HH:mm') }
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
            } catch { }
        }
    }
    Write-Log ("   удалено приложений: {0}" -f $done)
    Emit-Json @{ removed = $done }
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  ДОКАЗАТЕЛЬСТВО РЕЗУЛЬТАТА
#  Индекс говорит лишь «настройки на месте». Здесь собирается то, что можно
#  сравнить «до» и «после»: сколько событий уходило, сколько доменов молчит,
#  сколько сборщиков осталось включёнными и сколько телеметрии ждёт отправки.
# =========================================================================== #
function Get-ProofSnapshot {
    $ok = 0; $tot = 0; $etwOff = 0; $etwTotal = 0
    foreach ($d in $script:Defs) {
        if ($d.M -in @('cleanup', 'startup', 'buffer', 'oem')) { continue }
        $r = Check-Def $d
        $tot++
        if ($r.ok) { $ok++ }
        if ($d.M -eq 'etw') { $etwTotal++; if ($r.ok) { $etwOff++ } }
    }
    $dns = @(Get-DnsEvidence)
    $buf = Get-BufferInfo
    $fw = @(Get-NetFirewallRule -Group $script:FwGroup -ErrorAction SilentlyContinue).Count
    $base = Load-Json 'xray-baseline.json'
    $tasks = 0
    try {
        foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
            if (($t.TaskPath + $t.TaskName) -match 'Appraiser|Consolidator|UsbCeip|DmClient|QueueReporting|ProgramDataUpdater|KernelCeip|Sqm-Tasks|GatherNetworkInfo|Device Information') {
                if ($t.State -ne 'Disabled') { $tasks++ }
            }
        }
    } catch { }
    return @{
        time       = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        ok         = $ok
        total      = $tot
        dnsBlocked = @($dns | Where-Object { $_.blocked }).Count
        dnsOpen    = @($dns | Where-Object { -not $_.blocked }).Count
        bufferMb   = $buf.mb
        bufferFiles= $buf.files
        fwRules    = $fw
        etwOff     = $etwOff
        etwTotal   = $etwTotal
        tasksLive  = $tasks
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
    $r.hkcu = $false
    try {
        $k = 'HKCU:\Software\Win11Privacy\SelfTest'
        if (-not (Test-Path -LiteralPath $k)) { New-Item -Path $k -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $k -Name 'Probe' -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        $r.hkcu = ((Get-ItemProperty -LiteralPath $k -Name 'Probe' -ErrorAction Stop).Probe -eq 1)
        Remove-Item -LiteralPath 'HKCU:\Software\Win11Privacy' -Recurse -Force -ErrorAction SilentlyContinue
    } catch { Write-Log ("   [!] {0}" -f $_.Exception.Message) }
    Write-Log ("   [{0}] запись в реестр пользователя (HKCU)" -f $(if ($r.hkcu) { '+' } else { '!' }))

    # --- реестр системы (HKLM) ---
    $r.hklm = $false
    try {
        $k = 'HKLM:\SOFTWARE\Win11Privacy\SelfTest'
        if (-not (Test-Path -LiteralPath $k)) { New-Item -Path $k -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $k -Name 'Probe' -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        $r.hklm = ((Get-ItemProperty -LiteralPath $k -Name 'Probe' -ErrorAction Stop).Probe -eq 1)
        Remove-Item -LiteralPath 'HKLM:\SOFTWARE\Win11Privacy' -Recurse -Force -ErrorAction SilentlyContinue
    } catch { Write-Log ("   [!] {0}" -f $_.Exception.Message) }
    Write-Log ("   [{0}] запись в реестр системы (HKLM) — сюда идут политики" -f $(if ($r.hklm) { '+' } else { '!' }))

    # --- резервная копия на рабочий стол ---
    $r.backup = $false
    $root = if ($BackupRoot) { $BackupRoot } else { [Environment]::GetFolderPath('Desktop') }
    Write-Log ("   папка для копий       : {0}" -f $root)
    try {
        $probeDir = Join-Path $root ('Win11Privacy-SelfTest-' + (Get-Date -Format 'HHmmss'))
        New-Item -ItemType Directory -Path $probeDir -Force -ErrorAction Stop | Out-Null
        $probeFile = Join-Path $probeDir 'probe.reg'
        $null = & reg.exe export 'HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' "$probeFile" /y 2>&1
        $r.backup = (Test-Path -LiteralPath $probeDir)
        Remove-Item -LiteralPath $probeDir -Recurse -Force -ErrorAction SilentlyContinue
    } catch { Write-Log ("   [!] {0}" -f $_.Exception.Message) }
    Write-Log ("   [{0}] создание папки резервной копии" -f $(if ($r.backup) { '+' } else { '!' }))

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
    if (-not $r.backup) { $bad += 'нельзя создать папку резервной копии' }
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
    $items = @()
    $oemInfo = $null
    foreach ($d in $script:Defs) {
        if ($Modules -notcontains $d.M) { continue }
        if ($SkipItems -contains $d.Id) { continue }
        $items += (Check-Def $d)
    }
    if ($Modules -contains 'oem') {
        $oemInfo = Detect-Oem
        foreach ($it in $oemInfo.items) {
            $ok = ($it.state -match 'Disabled')
            $items += @{ module='oem'; name=("{0}: {1}" -f $(if ($it.type -eq 'svc') { 'служба' } else { 'задача' }), $it.display); ok=$ok; expected='Disabled'; actual=$it.state }
        }
    }
    $okCount = @($items | Where-Object { $_.ok }).Count
    $groups = @()
    foreach ($m in $script:ModuleOrder) {
        $mi = @($items | Where-Object { $_.module -eq $m })
        if ($mi.Count -eq 0) { continue }
        $groups += @{ module=$m; title=$script:ModuleTitles[$m]; ok=@($mi | Where-Object { $_.ok }).Count; total=$mi.Count; items=$mi }
    }
    $result = @{
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); ok = $okCount; total = $items.Count; groups = $groups
        dns = (Get-DnsEvidence); buffer = (Get-BufferInfo); edition = (Get-Edition); doh = (Get-DohStatus)
        monitorEnabled = (Get-MonitorEnabled); hostsBlocked = (Test-HostsBlock)
    }
    Emit-Json $result
    exit 0
}

# =========================================================================== #
#  ОТКАТ ПО ЖУРНАЛУ
#  Возвращает каждый параметр реестра в то значение, которое было до нас.
# =========================================================================== #
function Restore-Journal {
    $j = Load-Json 'changes.json'
    if (-not $j -or -not $j.items) { Write-Log '   [-] журнал пуст — возвращать нечего'; return @{ restored = 0; failed = 0 } }
    $items = @($j.items)
    [array]::Reverse($items)
    $ok = 0; $bad = 0; $seen = @{}
    foreach ($e in $items) {
        if ("$($e.kind)" -ne 'reg') { continue }
        $key = "$($e.path)|$($e.name)"
        if ($seen.ContainsKey($key)) { continue }      # только самое раннее состояние
        $seen[$key] = $true
        try {
            if ($e.existed) {
                if (-not (Test-Path -LiteralPath $e.path)) { New-Item -Path $e.path -Force -ErrorAction Stop | Out-Null }
                New-ItemProperty -LiteralPath $e.path -Name $e.name -Value $e.old -PropertyType $e.type -Force -ErrorAction Stop | Out-Null
            } else {
                Remove-ItemProperty -LiteralPath $e.path -Name $e.name -Force -ErrorAction SilentlyContinue
            }
            $ok++
        } catch { $bad++ }
    }
    Write-Log ("   [+] возвращено параметров реестра: {0}" -f $ok)
    if ($bad -gt 0) { Write-Log ("   [!] не удалось вернуть: {0}" -f $bad) }
    try { Remove-Item -LiteralPath (Join-Path $script:DataDir 'changes.json') -Force -ErrorAction SilentlyContinue } catch { }
    return @{ restored = $ok; failed = $bad }
}

if ($ChangeLog) {
    $j = Load-Json 'changes.json'
    $n = 0
    if ($j -and $j.items) { $n = @($j.items).Count }
    Emit-Json @{ count = $n; updated = $(if ($j) { "$($j.updated)" } else { '' }) }
    exit 0
}

if ($RestoreAll) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Возврат настроек реестра по журналу'
    $r = Restore-Journal
    Emit-Json $r
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  Revert (откат)
# =========================================================================== #
if ($Revert) {
    Write-Log 'ОТКАТ ИЗМЕНЕНИЙ'
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }

    Write-Section 'Настройки реестра'; $null = Restore-Journal
    Write-Section 'Файл hosts'; Remove-HostsBlock
    Write-Section 'Брандмауэр'; Remove-FwRules
    Write-Section 'Монитор'; if (Get-MonitorEnabled) { Set-MonitorEnabled $false | Out-Null } else { Write-Log '   [-] журнал аудита не включён' }
    Write-Section 'Страж'
    try { Unregister-ScheduledTask -TaskName $script:GuardTask -Confirm:$false -ErrorAction Stop; Write-Log '   [+] задача стража удалена' } catch { Write-Log '   [-] стража нет' }
    try { Unregister-ScheduledTask -TaskName $script:SensorTask -Confirm:$false -ErrorAction Stop; Write-Log '   [+] слежение за датчиками удалено' } catch { Write-Log '   [-] слежения за датчиками нет' }
    try { Unregister-ScheduledTask -TaskName 'Win11Privacy Watcher' -Confirm:$false -ErrorAction Stop; Write-Log '   [+] живые уведомления удалены' } catch { Write-Log '   [-] живых уведомлений нет' }

    Write-Section 'Службы'
    foreach ($svc in @(@{N='DiagTrack';S='Automatic'}, @{N='dmwappushservice';S='Manual'}, @{N='NvTelemetryContainer';S='Automatic'})) {
        try { $null = Get-Service -Name $svc.N -ErrorAction Stop; Set-Service -Name $svc.N -StartupType $svc.S -ErrorAction Stop; Write-Log "   [+] $($svc.N) -> $($svc.S)" }
        catch { Write-Log "   [-] $($svc.N) -- пропущено" }
    }
    Write-Section 'Задачи планировщика'
    foreach ($d in $script:Defs) {
        if ($d.T -eq 'task') {
            $pp = Split-TaskPath $d.P
            try { Enable-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop | Out-Null; Write-Log "   [+] включена: $($pp[1])" } catch { Write-Log "   [-] пропущена: $($pp[1])" }
        } elseif ($d.T -eq 'taskglob') {
            foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like $d.P })) {
                try { Enable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null; Write-Log "   [+] включена: $($t.TaskName)" } catch { }
            }
        }
    }
    Write-Section 'Компоненты производителя'
    $oemSaved = Load-Json 'oem-disabled.json'
    if ($oemSaved) {
        foreach ($it in @($oemSaved)) {
            try {
                if ($it.type -eq 'svc') { Set-Service -Name $it.name -StartupType $(if ($it.state -match 'Auto') { 'Automatic' } else { 'Manual' }) -ErrorAction Stop; Write-Log "   [+] служба $($it.name) -> $($it.state)" }
                else { $pp = Split-TaskPath $it.name; Enable-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop | Out-Null; Write-Log "   [+] задача $($pp[1]) включена" }
            } catch { Write-Log "   [-] $($it.name) -- пропущено" }
        }
        Remove-Item -LiteralPath (Join-Path $script:DataDir 'oem-disabled.json') -Force -ErrorAction SilentlyContinue
    } else { Write-Log '   [-] ничего не отключалось' }

    Write-Section 'Сторонние программы'
    foreach ($v in @('POWERSHELL_TELEMETRY_OPTOUT','POWERSHELL_UPDATECHECK','DOTNET_CLI_TELEMETRY_OPTOUT')) {
        try { [Environment]::SetEnvironmentVariable($v, $null, 'User'); Write-Log "   [+] переменная $v удалена" } catch { }
    }
    foreach ($f in @((Get-VsCodeSettingsPath), (Get-FirefoxPoliciesPath))) {
        if ($f -and (Test-Path -LiteralPath "$f.win11privacy.bak")) {
            try { Copy-Item -LiteralPath "$f.win11privacy.bak" -Destination $f -Force -ErrorAction Stop; Remove-Item -LiteralPath "$f.win11privacy.bak" -Force -ErrorAction SilentlyContinue; Write-Log "   [+] восстановлен: $f" } catch { }
        }
    }
    foreach ($k in @('HKLM:\SOFTWARE\Policies\Google\Chrome','HKCU:\Software\Policies\Microsoft\office','HKLM:\SOFTWARE\Policies\Microsoft\VisualStudio')) {
        # политики сторонних программ создавались только нами — удаляем целиком
        if (Test-Path -LiteralPath $k) { try { Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction Stop; Write-Log "   [+] удалены политики: $k" } catch { } }
    }

    Write-Section 'Геолокация, Защитник, виджеты'
    foreach ($rv in @(
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'; N='DisableLocation' },
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'; N='DisableWindowsLocationProvider' },
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice'; N='AllowFindMyDevice' },
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'; N='SpyNetReporting' },
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'; N='SubmitSamplesConsent' },
        @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; N='AllowNewsAndInterests' })) {
        try { Remove-ItemProperty -LiteralPath $rv.P -Name $rv.N -Force -ErrorAction Stop; Write-Log "   [+] снято: $($rv.N)" } catch { }
    }
    try { New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' -Name 'Value' -Value 'Allow' -PropertyType String -Force -ErrorAction Stop | Out-Null; Write-Log '   [+] доступ к местоположению возвращён (Allow)' } catch { }

    Write-Log ''
    Write-Log 'Настройки реестра возвращены по журналу изменений — ручной импорт .reg больше не нужен.'
    Write-Log 'Папка резервной копии на рабочем столе остаётся как запасной вариант.'
    Write-Log 'Готово. Перезагрузите компьютер.'
    Write-Log '###DONE###'
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
    try { Save-Json 'proof-before.json' (Get-ProofSnapshot); Write-Log 'Состояние «до» запомнено — потом покажем разницу.' } catch { }
}

# --- Резервная копия -------------------------------------------------------- #
$script:BackupDir = ''
if (-not $NoBackup -and -not $DryRun) {
    Write-Section 'Резервная копия реестра'
    $root = if ($BackupRoot) { $BackupRoot } else { [Environment]::GetFolderPath('Desktop') }
    $script:BackupDir = Join-Path $root ('Win11Privacy-Backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $keys = @($script:Defs | Where-Object { $_.T -eq 'reg' -and $Modules -contains $_.M } | ForEach-Object { $_.P } | Select-Object -Unique)
    try {
        New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
        $n = 0
        foreach ($k in $keys) {
            if (Test-Path -LiteralPath $k) {
                $native = $k -replace '^HKLM:\\','HKLM\' -replace '^HKCU:\\','HKCU\'
                $file = Join-Path $script:BackupDir ((($k -replace '[:\\ ]','_')) + '.reg')
                $null = & reg.exe export "$native" "$file" /y 2>&1
                $n++
            }
        }
        Write-Log ("   [+] сохранено веток: {0} -> {1}" -f $n, $script:BackupDir)
    } catch { Write-Log "   [!] не удалось создать резервную копию: $($_.Exception.Message)" }
}

# --- Точка восстановления --------------------------------------------------- #
if (-not $NoRestorePoint -and -not $DryRun) {
    Write-Section 'Точка восстановления системы'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
        Checkpoint-Computer -Description 'Win11Privacy: до изменений' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-Log '   [+] точка восстановления создана'
    } catch { Write-Log "   [!] точку восстановления создать не удалось: $($_.Exception.Message)" }
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
    foreach ($d in $modDefs) {
        if ($SkipItems -contains $d.Id) { Write-Log ("   [п] {0} -- пропущено по вашему выбору" -f $d.C); continue }
        Apply-Def $d
    }
}

# --- Компоненты производителя ---------------------------------------------- #
if (Use-Module 'oem') {
    Write-Section 'Компоненты сбора данных производителя'
    $oem = Detect-Oem
    Write-Log ("   производитель: {0} {1}" -f $oem.manufacturer, $oem.model)
    if ($oem.items.Count -eq 0) { Write-Log '   [-] компонентов сбора данных не найдено' }
    $disabledList = @()
    foreach ($it in $oem.items) {
        if ($DryRun) { Write-Log ("   [тест] {0} {1} -- отключить" -f $it.type, $it.display); continue }
        try {
            if ($it.type -eq 'svc') {
                $s = Get-Service -Name $it.name -ErrorAction Stop
                if ($s.Status -eq 'Running') { Stop-Service -Name $it.name -Force -ErrorAction SilentlyContinue }
                Set-Service -Name $it.name -StartupType Disabled -ErrorAction Stop
            } else {
                $pp = Split-TaskPath $it.name
                Disable-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop | Out-Null
            }
            $disabledList += $it
            Write-Log ("   [+] отключено: {0}" -f $it.display); $script:Changes++
        } catch { Write-Log ("   [!] не удалось: {0} -- {1}" -f $it.display, $_.Exception.Message); $script:Failures++ }
    }
    if ($disabledList.Count -gt 0) {
        $prev = Load-Json 'oem-disabled.json'
        $all = @(); if ($prev) { $all += @($prev) }; $all += $disabledList
        Save-Json 'oem-disabled.json' $all
    }
}

# --- Буфер телеметрии ------------------------------------------------------- #
if (Use-Module 'buffer') { Purge-Buffer }

# --- Чистка ----------------------------------------------------------------- #
if (Use-Module 'cleanup') {
    Write-Section 'Чистка временных файлов'
    $total = 0.0
    $wu = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    $wuWasRunning = ($wu -and $wu.Status -eq 'Running')
    if ($wuWasRunning -and -not $DryRun) { Stop-Service wuauserv -Force -ErrorAction SilentlyContinue }
    $targets = @(
        @{ P = $env:TEMP;                                            L = 'временные файлы пользователя' },
        @{ P = "$env:SystemRoot\Temp";                               L = 'временные файлы Windows' },
        @{ P = "$env:SystemRoot\SoftwareDistribution\Download";      L = 'кэш загруженных обновлений' },
        @{ P = "$env:SystemRoot\Logs\CBS";                           L = 'логи обслуживания компонентов' },
        @{ P = "$env:LOCALAPPDATA\Microsoft\Windows\WER";            L = 'локальные отчёты об ошибках' },
        @{ P = "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"; L = 'очередь отчётов об ошибках' },
        @{ P = "$env:LOCALAPPDATA\CrashDumps";                       L = 'дампы аварийных завершений' },
        @{ P = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache";      L = 'кэш интернет-файлов' },
        @{ P = "$env:LOCALAPPDATA\D3DSCache";                        L = 'кэш шейдеров DirectX' }
    )
    $steps = $targets.Count + 3
    $n = 0
    Write-Log ("   шагов всего: {0}" -f $steps)
    foreach ($t in $targets) {
        $n++
        $tag = '[{0,3}%] ({1}/{2})' -f [int](100.0 * $n / $steps), $n, $steps
        $total += (Clear-FolderContents -FolderPath $t.P -Label $t.L -Step $tag)
    }
    if (-not $DryRun) {
        $thumbs = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
        if (Test-Path -LiteralPath $thumbs) {
            $before = Get-FolderSizeMB $thumbs
            Get-ChildItem -LiteralPath $thumbs -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            $f = [math]::Max(0, [math]::Round($before - (Get-FolderSizeMB $thumbs), 1)); $total += $f
            Write-Log ("   {0} кэш эскизов -- освобождено {1} МБ" -f ('[{0,3}%] ({1}/{2})' -f [int](100.0 * ($n + 1) / $steps), ($n + 1), $steps), $f)
        }
        $n++   # шаг «кэш эскизов» засчитан
        $n++   # следующий шаг — корзина
        $tag = '[{0,3}%] ({1}/{2})' -f [int](100.0 * $n / $steps), $n, $steps
        try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Log ("   {0} корзина очищена" -f $tag) } catch { Write-Log ("   {0} корзина уже пуста" -f $tag) }
        $n++
        $tag = '[{0,3}%] ({1}/{2})' -f [int](100.0 * $n / $steps), $n, $steps
        try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop; Write-Log ("   {0} кэш Delivery Optimization очищен" -f $tag) } catch { Write-Log ("   {0} кэш Delivery Optimization пропущен" -f $tag) }
    }
    if ($wuWasRunning -and -not $DryRun) { Start-Service wuauserv -ErrorAction SilentlyContinue }
    Write-Log '   [100%] чистка завершена'
    Write-Log ('   ИТОГО освобождено: ~{0} МБ' -f [math]::Round($total, 1))
}

# --- Автозагрузка ----------------------------------------------------------- #
if (Use-Module 'startup') {
    Write-Section 'Автозагрузка (только отчёт, ничего не отключается)'
    $items = @()
    try { $items = @(Get-CimInstance Win32_StartupCommand -ErrorAction Stop) } catch { }
    if ($items.Count -gt 0) {
        foreach ($s in $items) { Write-Log ("   * {0}" -f $s.Name); Write-Log ("       команда : {0}" -f $s.Command); Write-Log ("       источник: {0}" -f $s.Location) }
    } else { Write-Log '   (записей не найдено)' }
    Write-Log ''; Write-Log '   Отключить лишнее: Ctrl+Shift+Esc -> вкладка «Автозагрузка приложений».'
}

# --- Итог ------------------------------------------------------------------- #
Write-Section 'Итог'
# журнал для отката — дописываем к тому, что было раньше
if (-not $DryRun -and $script:Journal.Count -gt 0) {
    try {
        $prev = Load-Json 'changes.json'
        $all = New-Object System.Collections.Generic.List[object]
        if ($prev -and $prev.items) { foreach ($e in @($prev.items)) { $all.Add($e) } }
        foreach ($e in $script:Journal) { $all.Add($e) }
        Save-Json 'changes.json' @{ items = $all.ToArray(); updated = (Get-Date).ToString('s') }
        Write-Log ("Записано в журнал отката: {0}" -f $script:Journal.Count)
    } catch { }
}

Write-Log ("Изменений применено : {0}" -f $script:Changes)
Write-Log ("Было уже настроено : {0}" -f $script:Already)
Write-Log ("Ошибок              : {0}" -f $script:Failures)
if ($script:BackupDir) { Write-Log ("Резервная копия     : {0}" -f $script:BackupDir) }
Write-Log ''
Write-Log 'Перезагрузите компьютер, чтобы всё вступило в силу. Нажмите «Проверить» — программа прочитает реальное состояние системы.'
Emit-Json @{ changes=$script:Changes; already=$script:Already; failures=$script:Failures; backup=$script:BackupDir }
Write-Log '###DONE###'
