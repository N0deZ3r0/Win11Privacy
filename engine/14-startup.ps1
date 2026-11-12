
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
        $list += (New-StartupItem ('task|' + $full) ([string]$t.TaskName) $cmd 'планировщик задач, при входе' 'task' ($t.State -ne 'Disabled'))
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
    try {
        Ensure-DataDir
        $engineDst = Install-TaskEngine
        $mods = @($Modules | Where-Object { $_ -notin @('cleanup','startup','buffer') })
        # Снятые внутри модуля пункты страж тоже помнит: иначе он «чинил» бы
        # то, что человек оставил нарочно, — например, DoSvc ради Магазина.
        Save-Json 'profile.json' @{ version=1; modules=$mods; skip=@($SkipItems); created=(Get-Date).ToString('s') }
        $action = New-ScheduledTaskAction -Execute $script:PsExe -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $engineDst + '" -Guard' + $script:DataArg)
        $t1 = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
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
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $script:GuardTask -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log ("   [+] страж установлен: проверка через 3 минуты после входа в систему и {0}" -f $(if ($GuardDaily) { 'каждый день в 12:00' } else { 'по воскресеньям в 12:00' }))
        if ($triggers.Count -gt 2) { Write-Log '   [+] и через 5 минут после каждого установленного обновления Windows' }
        else { Write-Log '   [-] пробуждение после обновлений недоступно на этой системе' }
        Write-Log ("   [+] отслеживается модулей: {0}" -f $mods.Count)
        Write-Log ("   [+] журнал: {0}" -f (Join-Path $script:DataDir 'guard.log'))
    } catch { Write-Log "   [!] не удалось установить стража: $($_.Exception.Message)" }
    Write-Log '###DONE###'
    exit 0
}

if ($RemoveGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Страж приватности'
    $rt = Remove-OwnTask $script:GuardTask 'задача стража'
    Write-Log '###DONE###'
    if ($rt -eq 'failed') { exit 1 }
    exit 0
}

