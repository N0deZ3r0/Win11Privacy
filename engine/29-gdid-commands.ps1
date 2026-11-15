# --------------------------------------------------------------------------- #
#  Номер устройства: состояние, смена, возврат как было
# --------------------------------------------------------------------------- #
if ($GdidStatus) { Emit-Json (Get-GdidStatus); exit 0 }

# Код выхода, как у применения и отката: 0 — всё прошло, 2 — дошёл до конца,
# но не всё (окно пишет «Готово, с ошибками»). Раньше смена номера и возврат
# всегда кончались кодом 0, даже когда стирание не удалось.
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
    $gs = Get-GdidStatus
    $gs['wipe'] = $script:GdidWipeResult
    Emit-Json $gs
    Write-Log '###DONE###'
    exit $(if ($script:Failures -gt 0) { 2 } else { 0 })
}

if ($GdidRestore) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Номер устройства: вернуть как было'
    # Сначала страж: иначе, сработав посреди возврата, он поставил бы всё
    # обратно. Раньше профиль стража правился последним.
    $prof = Load-Json 'profile.json'
    if ($prof -and $prof.modules -and @(@($prof.modules) | Where-Object { $_ -in @('gdid', 'gdidlock') }).Count -gt 0) {
        $profSkip = @($(if ($prof.PSObject.Properties['skip']) { @($prof.skip) } else { @() }))
        try {
            Save-Json 'profile.json' @{ version = 1; modules = @(@($prof.modules) | Where-Object { $_ -notin @('gdid', 'gdidlock') })
                                        skip = $profSkip; created = "$($prof.created)" }
            Write-Log '   [+] страж больше не следит за номером устройства'
        } catch { Write-Log ("   [!] профиль стража не переписался ({0}) -- он может снова отключить службы номера" -f $_.Exception.Message); $script:Failures++ }
    }
    # тип запуска служб — по журналу: ровно то, что было до программы
    $restored = New-Object System.Collections.Generic.List[string]
    foreach ($r in @(Restore-GdidServiceStarts)) {
        switch ($r.result) {
            'restored'   { Write-Log ("   [+] служба {0}: тип запуска возвращён ({1})" -f $r.name, (Get-StartName "$(Get-SvcStart $r.name)")); $restored.Add($r.name); $script:Changes++ }
            'notChanged' { Write-Log ("   [-] служба {0}: программа её не меняла" -f $r.name) }
            default      { Write-Log ("   [!] служба {0}: тип запуска не вернулся -- {1}" -f $r.name, $r.error); $script:Failures++ }
        }
    }
    # статус удаления блока проверяется (раньше его выводило прямо в журнал как «True»)
    $null = Remove-HostsBlock -Kind 'gdid'
    $null = Remove-HostsBlock -Kind 'lock'
    # «Правила не было» и «правило не снялось» — разное: раньше любая ошибка
    # брандмауэра называлась «правила не было»
    $fwName = Get-FwRuleName 'svc' 'wlidsvc'
    $fev = $null
    $fwRules = @(Get-NetFirewallRule -DisplayName $fwName -ErrorAction SilentlyContinue -ErrorVariable fev)
    $fwErr = @($fev | Where-Object { $_ -and "$($_.CategoryInfo.Category)" -ne 'ObjectNotFound' })
    if ($fwRules.Count -eq 0 -and $fwErr.Count -gt 0) { Write-Log ("   [!] брандмауэр не ответил, есть ли правило для wlidsvc: {0}" -f $fwErr[0]); $script:Failures++ }
    elseif ($fwRules.Count -eq 0) { Write-Log '   [-] правила брандмауэра для wlidsvc не было' }
    else {
        try { Remove-NetFirewallRule -DisplayName $fwName -ErrorAction Stop; Write-Log '   [+] правило брандмауэра для wlidsvc снято'; $script:Changes++ }
        catch { Write-Log ("   [!] правило брандмауэра для wlidsvc не снялось: {0}" -f $_.Exception.Message); $script:Failures++ }
    }
    # Службы, которым вернули тип запуска, — в работу сразу, если Windows даёт.
    # Раньше запускалась одна CDPSvc, и даже когда программа её не меняла.
    $sync = Sync-GdidRestoredServices @($restored | Where-Object { $_ -ne 'wlidsvc' })
    foreach ($p in @($sync.pending)) { Write-Log ("   [i] служба {0}: тип запуска возвращён, но Windows применит его позже -- до тех пор она не работает" -f $p) }
    foreach ($f in @($sync.failed)) { Write-Log ("   [!] служба не запустилась: {0}" -f $f); $script:Failures++ }
    if ((Get-SvcStart 'wlidsvc') -eq 4 -and $restored -notcontains 'wlidsvc') {
        Write-Log '   [i] служба учётных записей Microsoft (wlidsvc) отключена, но не программой (в журнале отката её нет) -- она её не трогает'
    }
    Write-Log '   [i] Стёртый раньше номер не вернётся: Windows получит новый при следующем обращении к учётной записи Microsoft.'
    $gs = Get-GdidStatus
    $gs['restore'] = @{ restored = $restored.ToArray(); pending = @($sync.pending); failed = @($sync.failed) }
    Emit-Json $gs
    Write-Log '###DONE###'
    exit $(if ($script:Failures -gt 0) { 2 } else { 0 })
}

