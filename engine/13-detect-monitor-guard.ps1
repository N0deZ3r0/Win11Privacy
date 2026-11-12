
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
