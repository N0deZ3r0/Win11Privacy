
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
        # Windows не отдала этот параметр при применении — это не «не применено»
        # «нет на этой версии Windows» важнее записанного отказа: это причина
        # честнее и не зависит от того, что когда-то не отдалось
        $r.blocked = [bool]((-not $r.ok) -and (-not $r.na) -and $blockedSet.ContainsKey($d.Id))
        if ($r.blocked) { $r.actual = 'Windows не разрешает' }
        if (-not $r.ContainsKey('na')) { $r.na = $false }
        $items += $r
    }
    if ($Modules -contains 'oem') {
        $oemInfo = Detect-Oem
        foreach ($it in $oemInfo.items) {
            $ok = ($it.state -match 'Disabled')
            $items += @{ module='oem'; name=("{0}: {1}" -f $(if ($it.type -eq 'svc') { 'служба' } else { 'задача' }), $it.display); ok=$ok; expected='Disabled'; actual=$it.state }
        }
    }
    $counted = @($items | Where-Object { (-not $_.blocked) -and (-not $_.na) })
    $okCount = @($counted | Where-Object { $_.ok }).Count
    $blockedCount = @($items | Where-Object { $_.blocked }).Count
    $naCount = @($items | Where-Object { $_.na }).Count
    $groups = @()
    foreach ($m in $script:ModuleOrder) {
        $mi = @($items | Where-Object { $_.module -eq $m })
        if ($mi.Count -eq 0) { continue }
        $mc = @($mi | Where-Object { (-not $_.blocked) -and (-not $_.na) })
        $groups += @{ module=$m; title=$script:ModuleTitles[$m]; ok=@($mc | Where-Object { $_.ok }).Count; total=$mc.Count
                      blocked=@($mi | Where-Object { $_.blocked }).Count; items=$mi }
    }
    $dnsList = @(Get-DnsEvidence)
    $result = @{
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); ok = $okCount; total = $counted.Count
        blocked = $blockedCount; notApplicable = $naCount; groups = $groups
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
            $proofItems.Add((Check-Def $d))
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
