
# =========================================================================== #
#  Revert (откат)
# =========================================================================== #
if ($Revert) {
    Write-Log 'ОТКАТ ИЗМЕНЕНИЙ'
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }

    Write-Section 'Настройки реестра, службы, задачи'; $rj = Restore-Journal
    # Журнал прежних версий не знает, какими были службы, задачи и переменные
    # среды до программы. Только для него — прежний откат «по умолчанию», и
    # только для того, что сейчас выключено. Раньше сюда вело и отсутствие
    # файла журнала — а его нет и тогда, когда недоверенный журнал только что
    # отложен: отказ от подделки оборачивался откатом по умолчанию. Теперь —
    # только журнал прежнего образца, которому можно верить.
    $legacyRevert = ("$($rj.state)" -eq 'legacy')
    if ("$($rj.state)" -eq 'untrusted') { Write-Log '   [!] журналу отката нельзя верить -- службы, задачи и политика аудита «по умолчанию» тоже не возвращаются' }
    elseif ("$($rj.state)" -eq 'none') { Write-Log '   [-] журнала нет -- службы, задачи и переменные среды возвращать не по чему' }
    Write-Section 'Файл hosts'; Remove-HostsBlock
    Write-Section 'Брандмауэр'; Remove-FwRules
    # Политику аудита возвращает журнал — ровно ту, что была до программы.
    # Журнал прежних версий её не знает: тогда, как раньше, выключаем.
    Write-Section 'Монитор'
    if ($legacyRevert) { if (Get-MonitorEnabled) { Set-MonitorEnabled $false | Out-Null } else { Write-Log '   [-] журнал аудита не включён' } }
    else { Write-Log '   [-] политика аудита возвращена по журналу (если программа её меняла)' }
    Write-Section 'Страж'
    try { Unregister-ScheduledTask -TaskName $script:GuardTask -Confirm:$false -ErrorAction Stop; Write-Log '   [+] задача стража удалена' } catch { Write-Log '   [-] стража нет' }
    try { Unregister-ScheduledTask -TaskName $script:SensorTask -Confirm:$false -ErrorAction Stop; Write-Log '   [+] слежение за датчиками удалено' } catch { Write-Log '   [-] слежения за датчиками нет' }
    try { Unregister-ScheduledTask -TaskName $script:NetTask -Confirm:$false -ErrorAction Stop; Write-Log '   [+] слежение за сетью удалено' } catch { Write-Log '   [-] слежения за сетью нет' }
    try { Unregister-ScheduledTask -TaskName 'Win11Privacy Watcher' -Confirm:$false -ErrorAction Stop; Write-Log '   [+] живые уведомления удалены' } catch { Write-Log '   [-] живых уведомлений нет' }

    if ($legacyRevert) {
        Write-Section 'Службы (журнал прежней версии)'
        foreach ($svc in @(@{N='DiagTrack';S='Automatic'}, @{N='dmwappushservice';S='Manual'}, @{N='NvTelemetryContainer';S='Automatic'}, @{N='InventorySvc';S='Automatic'})) {
            try {
                $s = Get-Service -Name $svc.N -ErrorAction Stop
                if ($s.StartType -ne 'Disabled') { continue }       # не выключена — не трогаем
                Set-Service -Name $svc.N -StartupType $svc.S -ErrorAction Stop; Write-Log "   [+] $($svc.N) -> $($svc.S)"
            } catch { Write-Log "   [-] $($svc.N) -- пропущено" }
        }
        Write-Section 'Задачи планировщика (журнал прежней версии)'
        foreach ($d in $script:Defs) {
            if ($d.T -eq 'task') {
                $pp = Split-TaskPath $d.P
                $st = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction SilentlyContinue
                if (-not $st) { continue }
                if ($st.State -ne 'Disabled') { continue }
                if ((Set-TaskEnabled $d.P $true) -in @('ok', 'system')) { Write-Log "   [+] включена: $($pp[1])" } else { Write-Log "   [-] пропущена: $($pp[1])" }
            } elseif ($d.T -eq 'taskglob') {
                foreach ($t in @(Get-TaskGlobTasks $d.P -AnyFolder | Where-Object { $_.State -eq 'Disabled' })) {
                    try { Enable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null; Write-Log "   [+] включена: $($t.TaskName)" } catch { Write-Log ("   [!] не включилась: {0} -- {1}" -f $t.TaskName, $_.Exception.Message); $script:Failures++ }
                }
            }
        }
    }
    Write-Section 'Компоненты производителя'
    # Новые версии возвращают их по журналу отката (выше). Здесь — список
    # прежних версий, oem-disabled.json. Подписи у него нет, поэтому из него
    # берётся только то, что программа сама сейчас узнаёт как компонент
    # производителя: та же служба или задача, тот же вид. Чужое имя,
    # дописанное в файл, не включается.
    $oemSaved = Load-Json 'oem-disabled.json'
    if ($oemSaved) {
        $known = @{}
        foreach ($k in @((Detect-Oem).items)) { $known[("{0}|{1}" -f $k.type, $k.name).ToLowerInvariant()] = $true }
        foreach ($it in @($oemSaved)) {
            $type = "$($it.type)"; $name = "$($it.name)"
            if ($type -notin @('svc', 'task') -or -not $known.ContainsKey(("{0}|{1}" -f $type, $name).ToLowerInvariant())) {
                Write-Log ("   [!] {0} -- не компонент производителя на этом компьютере, пропущено" -f $name); continue
            }
            try {
                if ($type -eq 'svc') { Set-Service -Name $name -StartupType $(if ("$($it.state)" -match 'Auto') { 'Automatic' } else { 'Manual' }) -ErrorAction Stop; Write-Log "   [+] служба $name -> $($it.state)" }
                else { $pp = Split-TaskPath $name; Enable-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop | Out-Null; Write-Log "   [+] задача $($pp[1]) включена" }
            } catch { Write-Log "   [-] $name -- пропущено" }
        }
        Remove-Item -LiteralPath (Join-Path $script:DataDir 'oem-disabled.json') -Force -ErrorAction SilentlyContinue
    } else { Write-Log '   [-] список прежней версии не найден -- если программа их отключала, они вернулись по журналу' }

    Write-Section 'Сторонние программы'
    # Переменные среды возвращает журнал. Журнал прежней версии их не знает:
    # тогда убираем только то, что стоит ровно в нашем значении.
    if ($legacyRevert) {
        foreach ($d in @($script:Defs | Where-Object { $_.T -eq 'env' })) {
            if ([string][Environment]::GetEnvironmentVariable($d.P, 'User') -ne [string]$d.V) { continue }
            try { [Environment]::SetEnvironmentVariable($d.P, $null, 'User'); Write-Log "   [+] переменная $($d.P) удалена" } catch { Write-Log ("   [!] переменная {0} не удалена -- {1}" -f $d.P, $_.Exception.Message); $script:Failures++ }
        }
    }
    foreach ($f in @((Get-VsCodeSettingsPath), (Get-FirefoxPoliciesPath))) {
        if ($f -and (Test-Path -LiteralPath "$f.win11privacy.bak")) {
            try { Copy-Item -LiteralPath "$f.win11privacy.bak" -Destination $f -Force -ErrorAction Stop; Remove-Item -LiteralPath "$f.win11privacy.bak" -Force -ErrorAction SilentlyContinue; Write-Log "   [+] восстановлен: $f" } catch { Write-Log ("   [!] не восстановлен: {0} -- {1}" -f $f, $_.Exception.Message); $script:Failures++ }
        }
    }
    # Политики Chrome, Office и Visual Studio раньше удалялись целыми ветками —
    # вместе с корпоративными, которых программа не ставила. Это обычные
    # параметры реестра, и журнал уже вернул каждый из них как было.

    if ($legacyRevert) {
        # Самые старые версии ставили это без журнала. Снимаем, только если
        # стоит ровно наше значение.
        Write-Section 'Геолокация, Защитник, виджеты (журнал прежней версии)'
        foreach ($rv in @(
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'; N='DisableLocation'; V='1' },
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'; N='DisableWindowsLocationProvider'; V='1' },
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice'; N='AllowFindMyDevice'; V='0' },
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'; N='SpyNetReporting'; V='0' },
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'; N='SubmitSamplesConsent'; V='2' },
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; N='AllowNewsAndInterests'; V='0' })) {
            if ("$(Get-RegValue $rv.P $rv.N)" -ne $rv.V) { continue }
            try { Remove-ItemProperty -LiteralPath $rv.P -Name $rv.N -Force -ErrorAction Stop; Write-Log "   [+] снято: $($rv.N)" } catch { Write-Log ("   [!] не снято: {0} -- {1}" -f $rv.N, $_.Exception.Message); $script:Failures++ }
        }
        $locKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
        if ("$(Get-RegValue $locKey 'Value')" -eq 'Deny') {
            try { New-ItemProperty -LiteralPath $locKey -Name 'Value' -Value 'Allow' -PropertyType String -Force -ErrorAction Stop | Out-Null; Write-Log '   [+] доступ к местоположению возвращён (Allow)' } catch { Write-Log ("   [!] доступ к местоположению не возвращён -- {0}" -f $_.Exception.Message); $script:Failures++ }
        }
    }

    Write-Section 'Данные программы'
    $left = @(Get-DataFiles)
    # копия движка для стража больше не нужна — задача уже удалена
    try { Remove-Item -LiteralPath $script:TaskEngine -Force -ErrorAction SilentlyContinue } catch { }
    try { Remove-Item -LiteralPath (Join-Path $script:DataDir 'engine.ps1') -Force -ErrorAction SilentlyContinue } catch { }
    if ($left.Count -eq 0) { Write-Log '   [-] программа ничего о вас не хранит' }
    else {
        foreach ($d in $left) {
            # что вернуть не удалось, остаётся в журнале для второй попытки
            if ($d.file -eq 'changes.json' -and [int]$rj.failed -gt 0) { Write-Log '   [-] журнал отката оставлен: в нём то, что вернуть не удалось'; continue }
            # Отложенный журнал (повреждён, подпись не сошлась, проверить
            # нечем) — след подмены, а при потерянном ключе и единственная
            # копия журнала. Раньше откат стирал его вместе с остальными
            # данными сразу после того, как отложил.
            if ($d.file -like 'changes.*-*.json') { Write-Log ("   [-] отложенный журнал оставлен: {0}" -f $d.file); continue }
            try { Remove-Item -LiteralPath (Join-Path $script:DataDir $d.file) -Force -ErrorAction Stop; Write-Log ("   [+] удалён: {0}" -f $d.file) }
            catch { Write-Log ("   [!] не удалось удалить {0}" -f $d.file) }
        }
    }

    Write-Log ''
    if ("$($rj.state)" -eq 'untrusted') {
        Write-Log '[!] Настройки по журналу изменений не возвращены: журналу нельзя верить (почему — сказано выше).'
        Write-Log 'Запасной вариант — резервная копия реестра на рабочем столе или точка восстановления Windows.'
    } else {
        Write-Log 'Настройки реестра возвращены по журналу изменений — ручной импорт .reg больше не нужен.'
        Write-Log 'Папка резервной копии на рабочем столе остаётся как запасной вариант.'
    }
    Write-Log 'Готово. Перезагрузите компьютер.'
    Write-Log '###DONE###'
    exit 0
}
