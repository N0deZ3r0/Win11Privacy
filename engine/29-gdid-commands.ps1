# --------------------------------------------------------------------------- #
#  Номер устройства: состояние, смена, возврат как было
# --------------------------------------------------------------------------- #
if ($GdidStatus) { Emit-Json (Get-GdidStatus); exit 0 }

# Код выхода, как у применения и отката: 0 — всё прошло и проверено, 2 —
# дошёл до конца, но не всё (окно пишет «Готово, с ошибками»): Partial,
# Unverified, AccessDenied, Failed, RestoreFailed. Код берётся из того же
# итога, что уходит в ответ (wipe/restore.exitCode), и из счёта ошибок —
# поэтому окно, журнал работы и код выхода не расходятся. Раньше смена номера
# кончалась кодом 0, когда стирание не удалось, но ошибок «не насчиталось».
function Get-GdidExitCode {
    param($Result)
    if ($null -eq $Result -or -not $Result['success'] -or $script:Failures -gt 0) { return 2 }
    return 0
}

if ($GdidReissue) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Смена номера устройства'
    # закрыт — значит, блок цел и в нём сервер выдачи; одной метки мало
    $lockedNow = Test-HostsBlockCurrent -Kind 'lock'
    if ($lockedNow) { Write-Log '   [i] сервер выдачи закрыт: после стирания нового номера Windows не получит' }
    elseif (Test-HostsBlock -Kind 'lock') { Write-Log '   [!] блок сервера выдачи в hosts побит или устарел: Windows может сразу получить новый номер' }
    $wiped = Invoke-GdidWipe
    if ($wiped -and -not $lockedNow) {
        Write-Log '   [i] Новый номер Windows получит при следующем обращении к учётной записи Microsoft (Магазин, Параметры) или после перезагрузки.'
        Write-Log '   [i] Магазин, Xbox и OneDrive могут попросить войти заново.'
    }
    $wr = $script:GdidWipeResult
    if ($null -eq $wr) { $wr = New-GdidResult 'wipe'; $script:Failures++ }
    $code = Get-GdidExitCode $wr
    $wr['exitCode'] = $code
    $gs = Get-GdidStatus
    $gs['wipe'] = $wr
    Emit-Json $gs
    Write-Log '###DONE###'
    exit $code
}

if ($GdidRestore) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Номер устройства: вернуть как было'
    # Итог возврата — той же формы, что у стирания (New-GdidResult). Стадии:
    # guard, services, hosts, firewall, start — у каждой Restored,
    # NotModified (программа это не меняла), NotFound, AccessDenied или
    # RestoreFailed; всё сверяется после изменения. Раньше снятие блоков hosts
    # не проверялось вовсе, снятие правила брандмауэра — тоже, а «вернуто»
    # говорилось и тогда, когда одна из стадий не прошла.
    $rr = New-GdidResult 'restore'
    $script:GdidRestoreResult = $rr
    $stage = {
        param([string]$Name, [string]$State, [string]$Why = '')
        $rr.stages[$Name] = $State
        $rr['checked'] = [int]$rr['checked'] + 1
        if ($State -in @('RestoreFailed', 'AccessDenied')) { $rr['failed'] = [int]$rr['failed'] + 1; if ($Why) { $rr.errors.Add(("{0}: {1}" -f $Name, $Why)) } }
        elseif ($State -eq 'NotFound' -and $Why) { $rr.warnings.Add(("{0}: {1}" -f $Name, $Why)) }
        if ($State -eq 'Restored') { $rr['removed'] = [int]$rr['removed'] + 1 }
    }
    # Сначала страж: иначе, сработав посреди возврата, он поставил бы всё
    # обратно. Раньше профиль стража правился последним. Переписанный профиль
    # перечитывается: «записалось» — ещё не «страж больше не следит».
    $prof = Load-Json 'profile.json'
    if ($prof -and $prof.modules -and @(@($prof.modules) | Where-Object { $_ -in @('gdid', 'gdidlock') }).Count -gt 0) {
        $profSkip = @($(if ($prof.PSObject.Properties['skip']) { @($prof.skip) } else { @() }))
        try {
            Save-Json 'profile.json' @{ version = 1; modules = @(@($prof.modules) | Where-Object { $_ -notin @('gdid', 'gdidlock') })
                                        skip = $profSkip; created = "$($prof.created)" }
            $chkProf = Load-Json 'profile.json'
            if ($chkProf -and @(@($chkProf.modules) | Where-Object { $_ -in @('gdid', 'gdidlock') }).Count -eq 0) {
                Write-Log '   [+] страж больше не следит за номером устройства'
                & $stage 'guard' 'Restored'
            } else {
                Write-Log '   [!] профиль стража переписан, но читается не таким -- он может снова отключить службы номера'
                & $stage 'guard' 'RestoreFailed' 'профиль стража не прочитался после записи'; $script:Failures++
            }
        } catch { Write-Log ("   [!] профиль стража не переписался ({0}) -- он может снова отключить службы номера" -f $_.Exception.Message); & $stage 'guard' 'RestoreFailed' "$($_.Exception.Message)"; $script:Failures++ }
    } else { & $stage 'guard' 'NotModified' }
    # тип запуска служб — по журналу: ровно то, что было до программы
    $restored = New-Object System.Collections.Generic.List[string]
    $svcRes = New-Object System.Collections.Generic.List[object]
    foreach ($r in @(Restore-GdidServiceStarts)) {
        $svcRes.Add($r)
        switch ($r.result) {
            'restored'     { Write-Log ("   [+] служба {0}: тип запуска возвращён ({1})" -f $r.name, (Get-StartName "$(Get-SvcStart $r.name)")); $restored.Add($r.name); $script:Changes++; & $stage ('service:' + $r.name) 'Restored' }
            'notChanged'   { Write-Log ("   [-] служба {0}: программа её не меняла" -f $r.name); & $stage ('service:' + $r.name) 'NotModified' }
            'notFound'     { Write-Log ("   [i] служба {0}: её больше нет на этой системе -- возвращать некуда, запись в журнале оставлена" -f $r.name); & $stage ('service:' + $r.name) 'NotFound' $r.error }
            'accessDenied' { Write-Log ("   [!] служба {0}: Windows не дала вернуть тип запуска -- {1}" -f $r.name, $r.error); $script:Failures++; & $stage ('service:' + $r.name) 'AccessDenied' $r.error }
            default        { Write-Log ("   [!] служба {0}: тип запуска не вернулся -- {1}" -f $r.name, $r.error); $script:Failures++; & $stage ('service:' + $r.name) 'RestoreFailed' $r.error }
        }
    }
    # Блоки hosts: снятие сверяется (Remove-HostsBlock), и до него видно,
    # был ли блок вообще. Раньше ответ Remove-HostsBlock отбрасывался.
    foreach ($hk in @('gdid', 'lock')) {
        $had = Get-GdidHostsFound $hk
        $ok = Remove-HostsBlock -Kind $hk
        $left = Get-GdidHostsFound $hk
        if (-not $ok -or $left -ne 0) {
            if ($ok) { Write-Log ("   [!] блок hosts ({0}) после снятия читается на месте" -f $hk); $script:Failures++ }
            & $stage ('hosts:' + $hk) 'RestoreFailed' $(if ($left -lt 0) { 'hosts не прочитался' } else { 'блок остался в hosts' })
        } elseif ($had -gt 0) { & $stage ('hosts:' + $hk) 'Restored' }
        else { & $stage ('hosts:' + $hk) $(if ($had -lt 0) { 'RestoreFailed' } else { 'NotModified' }) $(if ($had -lt 0) { 'hosts не прочитался' } else { '' }) }
    }
    # «Правила не было» и «правило не снялось» — разное: раньше любая ошибка
    # брандмауэра называлась «правила не было», а снятие не сверялось
    $fwName = Get-FwRuleName 'svc' 'wlidsvc'
    $fev = $null
    $fwRules = @(Get-NetFirewallRule -DisplayName $fwName -ErrorAction SilentlyContinue -ErrorVariable fev)
    $fwErr = @($fev | Where-Object { $_ -and "$($_.CategoryInfo.Category)" -ne 'ObjectNotFound' })
    if ($fwRules.Count -eq 0 -and $fwErr.Count -gt 0) { Write-Log ("   [!] брандмауэр не ответил, есть ли правило для wlidsvc: {0}" -f $fwErr[0]); $script:Failures++; & $stage 'firewall' 'RestoreFailed' "$($fwErr[0])" }
    elseif ($fwRules.Count -eq 0) { Write-Log '   [-] правила брандмауэра для wlidsvc не было'; & $stage 'firewall' 'NotModified' }
    else {
        $fwWhy = ''
        try { Remove-NetFirewallRule -DisplayName $fwName -ErrorAction Stop } catch { $fwWhy = "$($_.Exception.Message)" }
        $fev2 = $null
        $fwLeft = @(Get-NetFirewallRule -DisplayName $fwName -ErrorAction SilentlyContinue -ErrorVariable fev2)
        $fwErr2 = @($fev2 | Where-Object { $_ -and "$($_.CategoryInfo.Category)" -ne 'ObjectNotFound' })
        if (-not $fwWhy -and $fwLeft.Count -eq 0 -and $fwErr2.Count -eq 0) { Write-Log '   [+] правило брандмауэра для wlidsvc снято'; $script:Changes++; & $stage 'firewall' 'Restored' }
        else {
            if (-not $fwWhy) { $fwWhy = $(if ($fwLeft.Count -gt 0) { 'правило осталось на месте' } else { "брандмауэр не ответил: $($fwErr2[0])" }) }
            Write-Log ("   [!] правило брандмауэра для wlidsvc не снялось: {0}" -f $fwWhy); $script:Failures++
            & $stage 'firewall' $(if ($fwWhy -match 'Access is denied|Отказано в доступе') { 'AccessDenied' } else { 'RestoreFailed' }) $fwWhy
        }
    }
    # Службы, которым вернули тип запуска, — в работу сразу, если Windows даёт.
    # Раньше запускалась одна CDPSvc, и даже когда программа её не меняла.
    $sync = Sync-GdidRestoredServices @($restored | Where-Object { $_ -ne 'wlidsvc' })
    foreach ($p in @($sync.pending)) { Write-Log ("   [i] служба {0}: тип запуска возвращён, но Windows применит его позже -- до тех пор она не работает" -f $p); $rr.warnings.Add(("отложено: {0}" -f $p)) }
    foreach ($f in @($sync.failed)) { Write-Log ("   [!] служба не запустилась: {0}" -f $f); $script:Failures++; $rr['failed'] = [int]$rr['failed'] + 1; $rr.errors.Add(("не запустилась: {0}" -f $f)) }
    $rr.stages['start'] = $(if (@($sync.failed).Count -gt 0) { 'RestoreFailed' } elseif (@($sync.pending).Count -gt 0) { 'Pending' } else { 'ok' })
    if ((Get-SvcStart 'wlidsvc') -eq 4 -and $restored -notcontains 'wlidsvc') {
        Write-Log '   [i] служба учётных записей Microsoft (wlidsvc) отключена, но не программой (в журнале отката её нет) -- она её не трогает'
    }
    Write-Log '   [i] Стёртый раньше номер не вернётся: Windows получит новый при следующем обращении к учётной записи Microsoft.'
    # Итог: Restored — что программа меняла, возвращено и сверено; NotModified —
    # программа ничего из этого не меняла; Partial — что-то вернулось, что-то
    # нет; RestoreFailed — не вернулось ничего из того, что надо было вернуть
    $rr.serviceStates = $svcRes.ToArray()
    $rr.remaining = [int]$rr.failed
    $restState = $(if ($rr.failed -gt 0 -or $script:Failures -gt 0) { if ($rr.removed -gt 0) { 'Partial' } else { 'RestoreFailed' } }
                   elseif ($rr.removed -gt 0) { 'Restored' } else { 'NotModified' })
    Set-GdidResultState $rr $restState
    if ($restState -in @('Partial', 'RestoreFailed')) { Write-Log '   [!] вернулось не всё -- что именно, сказано выше' }
    $code = Get-GdidExitCode $rr
    $rr['exitCode'] = $code
    $gs = Get-GdidStatus
    $gs['restore'] = @{ restored = $restored.ToArray(); pending = @($sync.pending); failed = @($sync.failed)
                        state = $restState; result = $rr }
    Emit-Json $gs
    Write-Log '###DONE###'
    exit $code
}
