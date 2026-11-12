
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
            if ($r.blocked -or $r.na) { continue }
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
                if ($t.State -ne 'Disabled') { $tasks++ }
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
