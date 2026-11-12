
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
