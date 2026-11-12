# --------------------------------------------------------------------------- #
#  Журнал изменений в человеческом виде. Записи группируются по ключу: важно
#  самое раннее состояние — именно его вернёт откат. Название берём из
#  описания настройки, чтобы в списке было «уровень телеметрии», а не путь.
# --------------------------------------------------------------------------- #
function Get-ChangeGroups {
    # только то, чему можно верить: подписанное или из защищённой папки
    $j = Read-JournalFile -ReadOnly
    if ($j.items.Count -eq 0) { return @() }
    $byPath = @{}
    foreach ($d in $script:Defs) {
        if ($script:RegTypes -notcontains $d.T) { continue }
        $k = ("{0}|{1}" -f $d.P, $d.N).ToLowerInvariant()
        if (-not $byPath.ContainsKey($k)) { $byPath[$k] = @{ title = [string]$d.C; module = [string]$d.M } }
    }
    $order = New-Object System.Collections.Generic.List[string]
    $groups = @{}
    foreach ($e in @($j.items)) {
        $kind = "$($e.kind)"
        if ($kind -eq 'startup') {
            $key = 'startup|' + "$($e.id)"
            $title = $(if ("$($e.name)") { "$($e.name)" } else { "$($e.id)" })
            $where = 'автозагрузка'
            $was = $(if ("$($e.old)" -eq 'On') { 'запускалась' } else { 'была отключена' })
            $now = $(if ("$($e.newValue)" -eq 'On') { 'запускается' } else { 'отключена' })
        } elseif ($kind -eq 'hive') {
            # настройка другого профиля: называется так же, как своя, а где — видно по профилю
            $key = Get-JournalKey (ConvertTo-Fields $e)
            $pk = ("HKCU:\{0}|{1}" -f "$($e.sub)", "$($e.name)").ToLowerInvariant()
            $title = $(if ($byPath.ContainsKey($pk)) { $byPath[$pk].title } else { "$($e.name)" })
            $where = ("профиль {0}: {1}" -f "$($e.profile)", "$($e.sub)")
            $was = $(if ($e.existed) { "$($e.old)" } else { 'не было' })
            $now = "$($e.newValue)"
        } elseif ($kind -eq 'audit') {
            $key = Get-JournalKey (ConvertTo-Fields $e)
            $title = 'журнал соединений брандмауэра (наблюдение за сетью)'
            $where = 'политика аудита'
            $was = Get-AuditName "$($e.old)"
            $now = Get-AuditName "$($e.newValue)"
        } elseif ($kind -in @('svc', 'task', 'env')) {
            $key = Get-JournalKey (ConvertTo-Fields $e)
            $target = $(if ($kind -eq 'task') { "$($e.path)" } else { "$($e.name)" })
            $def = @($script:Defs | Where-Object { "$($_.P)" -eq $target -and (
                        ($kind -eq 'svc' -and $_.T -in @('svc', 'svcopt')) -or ($kind -eq 'task' -and $_.T -eq 'task') -or ($kind -eq 'env' -and $_.T -eq 'env')) } | Select-Object -First 1)
            $title = $(if ($def.Count -gt 0) { [string]$def[0].C } elseif ($kind -eq 'task') { Split-Path $target -Leaf } else { $target })
            if ($kind -eq 'svc') {
                $where = 'службы Windows'
                $was = Get-StartName "$($e.old)" "$($e.delayed)"
                $now = Get-StartName "$($e.newValue)"
            } elseif ($kind -eq 'task') {
                $where = 'планировщик задач'
                $was = 'включена'; $now = 'отключена'
            } else {
                $where = 'переменные среды'
                $was = $(if ($e.existed) { "$($e.old)" } else { 'не было' })
                $now = "$($e.newValue)"
            }
        } else {
            $key = ("reg|{0}|{1}" -f "$($e.path)", "$($e.name)").ToLowerInvariant()
            $pk = ("{0}|{1}" -f "$($e.path)", "$($e.name)").ToLowerInvariant()
            $title = $(if ($byPath.ContainsKey($pk)) { $byPath[$pk].title } else { "$($e.name)" })
            $where = "$($e.path)"
            $was = $(if ($e.existed) { "$($e.old)" } else { 'не было' })
            $now = "$($e.newValue)"
        }
        # у схлопнутой записи число правок лежит в ней самой
        $times = [int]$(if ($e.PSObject.Properties['count'] -and [int]$e.count -gt 0) { $e.count } else { 1 })
        $when = $(if ($e.PSObject.Properties['lastTime'] -and "$($e.lastTime)") { "$($e.lastTime)" } else { "$($e.time)" })
        if (-not $groups.ContainsKey($key)) {
            $order.Add($key)
            $groups[$key] = @{ id = (ConvertTo-StartupId $key); kind = $kind; title = $title
                               where = $where; was = $was; now = $now
                               time = $when; count = $times }
        } else {
            # самое раннее «было» уже записано, обновляем только текущее значение
            $groups[$key].now = $now
            $groups[$key].time = $when
            $groups[$key].count = [int]$groups[$key].count + $times
        }
    }
    $out = @()
    foreach ($k in $order) { $out += $groups[$k] }
    [array]::Reverse($out)          # свежие изменения сверху
    return $out
}

# Возвращает одну запись журнала и убирает её из changes.json
function Restore-ChangeKey {
    param([string]$Key)
    if (-not (Test-DataTrusted)) { return @{ ok = $false; error = 'папка данных программы не защищена от подмены' } }
    $jf = Read-JournalFile
    if (-not $jf.trusted) { return @{ ok = $false; error = 'журналу отката нельзя верить: подпись не сошлась или её нечем проверить' } }
    if ($jf.items.Count -eq 0) { return @{ ok = $false; error = 'журнал пуст' } }
    $mine = @($jf.items | Where-Object { (Get-JournalKey (ConvertTo-Fields $_)) -eq $Key })
    if ($mine.Count -eq 0) { return @{ ok = $false; error = 'запись не найдена' } }
    $first = $mine[0]              # самое раннее состояние
    $why = Test-JournalEntryShape $first
    if ($why) { return @{ ok = $false; error = ('запись журнала не по форме: ' + $why) } }
    if ("$($first.kind)" -eq 'startup') {
        $r = Set-StartupState ([string]$first.id) ("$($first.old)" -eq 'On')
    } elseif ("$($first.kind)" -eq 'hive') {
        $r = (Restore-HiveEntries @($first))[0]
    } else {
        $r = Restore-JournalEntry $first
    }
    if (-not $r.ok) { return @{ ok = $false; error = "$($r.error)" } }
    # журнал перечитывается под замком: дописанное другим запуском остаётся
    try { Remove-JournalKey $Key }
    catch { return @{ ok = $false; error = ('возвращено, но журнал не переписался: ' + $_.Exception.Message) } }
    return @{ ok = $true }
}

if ($ChangeLog) {
    $chg = @(Get-ChangeGroups)
    $j = Read-JournalFile -ReadOnly
    Emit-Json @{ items = $chg; count = $chg.Count
                 raw = @($j.items).Count
                 updated = "$($j.updated)"
                 trusted = [bool]$j.trusted }
    exit 0
}

if ($RestoreItems) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Emit-Json @{ error='нужны права администратора' }; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Возврат выбранных изменений'
    if ($ChangeItems.Count -eq 0) { Write-Log '   [-] ничего не выбрано'; Emit-Json @{ restored = 0 }; Write-Log '###DONE###'; exit 0 }
    $done = 0
    foreach ($id in $ChangeItems) {
        $key = ConvertFrom-StartupId $id
        if (-not $key) { Write-Log ("   [!] непонятная запись: {0}" -f $id); $script:Failures++; continue }
        $r = Restore-ChangeKey $key
        if ($r.ok) { Write-Log ("   [+] возвращено: {0}" -f $key); $done++; $script:Changes++ }
        else { Write-Log ("   [!] {0} -- {1}" -f $key, $r.error); $script:Failures++ }
    }
    Write-Log ("   возвращено записей: {0}" -f $done)
    Emit-Json @{ restored = $done; failures = $script:Failures }
    Write-Log '###DONE###'
    exit 0
}

