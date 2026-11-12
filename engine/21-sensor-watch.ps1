
# =========================================================================== #
#  СЛЕЖЕНИЕ ЗА ДАТЧИКАМИ
#  Каждые 30 минут сверяем журнал ConsentStore. Новая программа получила
#  доступ к камере/микрофону/геолокации -> всплывающее уведомление.
# =========================================================================== #
$script:SensorCapNames = @{
    webcam='камеру'; microphone='микрофон'; location='местоположение'
    contacts='контакты'; userAccountInformation='данные учётной записи'; userDataTasks='задачи и планы'
}

if ($InstallSensorGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Слежение за датчиками'
    try {
        Ensure-DataDir
        $engineDst = Install-TaskEngine

        # закладываем текущий список программ как известный — без уведомлений
        $r0 = Get-SpyReport
        try { $null = Update-SensorHistory $r0 } catch { }
        $pairs = @()
        foreach ($c in @($r0.caps)) { foreach ($it in @($c.items)) { $pairs += ($c.id + '|' + $it.app) } }
        Save-Json 'sensor-apps.json' @{ pairs = $pairs; updated = (Get-Date).ToString('s') }

        $action = New-ScheduledTaskAction -Execute $script:PsExe -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $engineDst + '" -SensorGuard' + $script:DataArg)
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration (New-TimeSpan -Days 3650)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $script:SensorTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log '   [+] слежение включено: сверка журнала каждые 30 минут'
        Write-Log '   [+] новая программа получит доступ к камере, микрофону или геолокации — придёт уведомление'
        Write-Log ("   [+] сейчас программ в журнале: {0}" -f $pairs.Count)
        Write-Log '   [+] попутно накапливается история для графика на «Обзоре»'
    } catch { Write-Log "   [!] не удалось: $($_.Exception.Message)" }
    Write-Log '###DONE###'
    exit 0
}

if ($InstallNetGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Слежение за сетью'
    try {
        Ensure-DataDir
        $engineDst = Install-TaskEngine
        # без журнала разрешённых соединений слежению не из чего брать программы
        if (-not (Get-MonitorEnabled)) { $null = Set-MonitorEnabled $true }
        # Известными считаем всех, кто выходил в сеть за неделю, и тех, у кого
        # соединение открыто прямо сейчас; ещё час слежение учится молча.
        $known = @{}
        foreach ($k in @((Get-NetAppsSince -Since (Get-Date).AddDays(-7)).Keys)) { $known[$k] = $true }
        if ($script:NetReadError) { Write-Log ("   [!] журнал безопасности не читается: {0} -- слежение будет пробовать снова, а на странице «Монитор» об этом сказано" -f $script:NetReadError) }
        foreach ($c in @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue)) {
            try { $p = (Get-Process -Id $c.OwningProcess -ErrorAction Stop).Path; if ($p) { $known[$p.ToLowerInvariant()] = $true } } catch { }
        }
        Save-Json 'net-apps.json' @{ known = @($known.Keys); recent = @(); learnUntil = (Get-Date).AddHours(1).ToString('s'); last = (Get-Date).ToString('s') }
        $action = New-ScheduledTaskAction -Execute $script:PsExe -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $engineDst + '" -NetGuard' + $script:DataArg)
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 3650)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $script:NetTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log '   [+] слежение включено: сверка журнала брандмауэра каждые 15 минут'
        Write-Log ("   [+] известных программ: {0}; первый час слежение учится и молчит" -f $known.Count)
        Write-Log '   [+] новая программа выйдет в сеть — придёт уведомление, а на странице «Монитор» её можно отрезать'
    } catch { Write-Log "   [!] не удалось: $($_.Exception.Message)" }
    Write-Log '###DONE###'
    exit 0
}

if ($RemoveNetGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Слежение за сетью'
    $rt = Remove-OwnTask $script:NetTask 'слежение за сетью'
    Write-Log '   [i] журнал соединений остаётся — он нужен монитору; выключается кнопкой монитора.'
    Write-Log '###DONE###'
    exit $(if ($rt -eq 'failed') { 1 } else { 0 })
}

# периодический запуск из планировщика: тихо, без вывода
if ($NetGuard) { $null = Invoke-NetGuard; exit 0 }

if ($RemoveSensorGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Слежение за датчиками'
    $rt = Remove-OwnTask $script:SensorTask 'слежение за датчиками'
    Write-Log '###DONE###'
    exit $(if ($rt -eq 'failed') { 1 } else { 0 })
}

if ($SensorGuard) {
    # периодический запуск из планировщика: тихо, без вывода
    $r = Get-SpyReport
    try { $null = Update-SensorHistory $r } catch { }

    $saved = Load-Json 'sensor-apps.json'
    $first = ($null -eq $saved)
    $known = @{}
    if ($saved -and $saved.pairs) { foreach ($p in @($saved.pairs)) { $known["$p"] = $true } }

    $newApps = @()
    foreach ($c in @($r.caps)) {
        foreach ($it in @($c.items)) {
            $k = $c.id + '|' + $it.app
            if ($known.ContainsKey($k)) { continue }
            $known[$k] = $true
            if (-not $first) { $newApps += @{ cap = $c.id; app = $it.app; last = $it.last } }
        }
    }
    # не сохранилось — в следующий раз о тех же программах сообщим снова; это видно в журнале задачи
    try { Save-Json 'sensor-apps.json' @{ pairs = @($known.Keys); updated = (Get-Date).ToString('s') } }
    catch { Write-Log ("   [-] список известных программ не сохранился: {0}" -f $_.Exception.Message) }

    if ($newApps.Count -gt 0) {
        $parts = @()
        foreach ($n in @($newApps | Select-Object -First 3)) {
            $t = $script:SensorCapNames["$($n.cap)"]
            if (-not $t) { $t = "$($n.cap)" }
            $parts += ("{0} — {1}" -f $n.app, $t)
        }
        $msg = ($parts -join '; ')
        if ($newApps.Count -gt 3) { $msg += (' и ещё ' + ($newApps.Count - 3)) }
        Show-Toast 'Новая программа получила доступ к датчикам' $msg
        Write-Log ("новых программ с доступом к датчикам: {0} -- {1}" -f $newApps.Count, $msg)
    }
    exit 0
}
