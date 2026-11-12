
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
    } catch { }
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
        try { Save-Json 'xray-last.json' @{ time = $r.time; perDay = $r.perDay; mbPerDay = $r.mbPerDay } } catch { }
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
    exit 0
}

# --- Страж запускается после объявления рентгена: он делает дневной замер --- #
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
