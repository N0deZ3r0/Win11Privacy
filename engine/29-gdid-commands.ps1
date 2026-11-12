# --------------------------------------------------------------------------- #
#  Номер устройства: состояние, смена, возврат как было
# --------------------------------------------------------------------------- #
if ($GdidStatus) { Emit-Json (Get-GdidStatus); exit 0 }

if ($GdidReissue) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Смена номера устройства'
    $lockedNow = Test-HostsBlock -Kind 'lock'
    if ($lockedNow) { Write-Log '   [i] сервер выдачи закрыт: после стирания нового номера Windows не получит' }
    $wiped = Invoke-GdidWipe
    if ($wiped -and -not $lockedNow) {
        Write-Log '   [i] Новый номер Windows получит при следующем обращении к учётной записи Microsoft (Магазин, Параметры) или после перезагрузки.'
        Write-Log '   [i] Магазин, Xbox и OneDrive могут попросить войти заново.'
    }
    Emit-Json (Get-GdidStatus)
    Write-Log '###DONE###'
    exit 0
}

if ($GdidRestore) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Номер устройства: вернуть как было'
    # тип запуска служб — по журналу: ровно то, что было до программы
    foreach ($n in @('CDPSvc', 'CDPUserSvc', 'DoSvc')) {
        $r = Restore-ChangeKey (("reg|HKLM:\SYSTEM\CurrentControlSet\Services\{0}|Start" -f $n).ToLowerInvariant())
        if ($r.ok) { Write-Log ("   [+] служба {0}: тип запуска возвращён" -f $n); $script:Changes++ }
        else { Write-Log ("   [-] служба {0}: программа её не меняла" -f $n) }
    }
    Remove-HostsBlock -Kind 'gdid'
    Remove-HostsBlock -Kind 'lock'
    try { Remove-NetFirewallRule -DisplayName (Get-FwRuleName 'svc' 'wlidsvc') -ErrorAction Stop; Write-Log '   [+] правило брандмауэра для wlidsvc снято' }
    catch { Write-Log '   [-] правила брандмауэра для wlidsvc не было' }
    # иначе страж тут же поставил бы всё обратно
    $prof = Load-Json 'profile.json'
    if ($prof -and $prof.modules -and @(@($prof.modules) | Where-Object { $_ -in @('gdid', 'gdidlock') }).Count -gt 0) {
        $profSkip = @($(if ($prof.PSObject.Properties['skip']) { @($prof.skip) } else { @() }))
        Save-Json 'profile.json' @{ version = 1; modules = @(@($prof.modules) | Where-Object { $_ -notin @('gdid', 'gdidlock') })
                                    skip = $profSkip; created = "$($prof.created)" }
        Write-Log '   [+] страж больше не следит за номером устройства'
    }
    if ((Get-SvcStart 'CDPSvc') -ne 4) {
        try { Start-Service CDPSvc -ErrorAction Stop }
        # тип запуска уже возвращён (это и есть снятие запрета); сразу служба
        # стартует не всегда — сказано прямо, но это не ошибка
        catch { Write-Log ("   [i] служба CDPSvc сейчас не запустилась ({0}) -- она запустится после перезагрузки" -f $_.Exception.Message) }
    }
    Write-Log '   [i] Стёртый раньше номер не вернётся: Windows получит новый при следующем обращении к учётной записи Microsoft.'
    Emit-Json (Get-GdidStatus)
    Write-Log '###DONE###'
    exit 0
}

