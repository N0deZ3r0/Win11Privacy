
# =========================================================================== #
#  ПРИМЕНЕНИЕ
# =========================================================================== #
if (-not (Test-Admin)) { Write-Log 'ОШИБКА: требуются права администратора.'; Write-Log '###DONE###'; exit 1 }

$osInfo = (Get-CimInstance Win32_OperatingSystem).Caption
$edInfo = Get-Edition
Write-Log "Система : $osInfo (сборка $([System.Environment]::OSVersion.Version.Build), редакция $($edInfo.id))"
Write-Log "Модули  : $($Modules -join ', ')"
if ($DryRun) { Write-Log 'РЕЖИМ ТЕСТА: изменения не применяются.' }
if ($edInfo.kind -ne 'enterprise' -and (Use-Module 'telemetry')) {
    Write-Log 'Примечание: на редакциях Home/Pro минимальный уровень телеметрии — «Обязательные данные»; полное отключение доступно только в Enterprise/Education.'
}

# --- Снимок «до» для доказательства результата -------------------------- #
if (-not $DryRun -and -not (Load-Json 'proof-before.json')) {
    try { Save-Json 'proof-before.json' (Get-ProofSnapshot); Write-Log 'Состояние «до» запомнено — потом покажем разницу.' }
    catch { Write-Log ("   [-] состояние «до» не запомнилось ({0}) -- разницу «до и после» показать будет не с чем" -f $_.Exception.Message) }
}

$script:BackupEnabled = $true    # дальше идёт ручное применение

# куст профиля, оставшийся подключённым после оборванного запуска, — сразу
if (-not $DryRun) { Clear-StaleHiveMounts }

# Журнал отката должен писаться до первого изменения, а не выясниться в конце
if (-not (Test-JournalWritable)) {
    Write-Log 'ПРИМЕНЕНИЕ ОТМЕНЕНО: журнал отката не записывается, а без него изменения нельзя было бы вернуть. Система не тронута.'
    Write-Log '###DONE###'
    exit 1
}

# --- Уборка за старыми версиями --------------------------------------------- #
$junkFound = @(Find-JunkValues)
if ($junkFound.Count -gt 0) {
    Write-Section 'Уборка за старыми версиями программы'
    Write-Log ("   найдено параметров, записанных под числовыми именами: {0}" -f $junkFound.Count)
    $null = Remove-JunkValues
}

# Что делать, если настройки модуля не поддались: обходной путь тем же результатом
$script:ModuleHints = @{
    widgets = 'Ключи политики виджетов Windows не отдаёт. Тот же результат даёт удаление пакета «Виджеты и лента Microsoft Start» на странице «Приложения».'
}

# --- Модули по определениям ------------------------------------------------- #
foreach ($m in $script:ModuleOrder) {
    if (-not (Use-Module $m)) { continue }
    if ($m -in @('cleanup','startup','buffer','oem')) { continue }
    # ВАЖНО: имя переменной не должно совпадать с $script:Defs — в PowerShell
    # регистр не различается, и фильтрация затёрла бы весь список определений.
    $modDefs = @($script:Defs | Where-Object { $_.M -eq $m })
    if ($modDefs.Count -eq 0) { continue }
    Write-Section $script:ModuleTitles[$m]
    # Без сервера выдачи номера учётная запись Microsoft не работает вовсе —
    # при входе в Windows через неё запрет не ставим, а объясняем почему.
    if ($m -eq 'gdidlock' -and (Get-GdidLockRefusal)) {
        if ((Get-GdidLockRefusal) -eq 'msa') {
            Write-Log '   [!] не применено: вы входите в Windows через учётную запись Microsoft, а без сервера выдачи номера она перестанет работать.'
            Write-Log '       Сначала перейдите на локальную учётную запись: Параметры > Учётные записи > Ваши данные.'
        } else { Write-Log ("   [!] не применено: {0}" -f (Get-ManagedReason)) }
        $script:Failures++
        continue
    }
    $failBefore = $script:Failures + $script:Blocked
    foreach ($d in $modDefs) {
        if ($SkipItems -contains $d.Id) { Write-Log ("   [п] {0} -- пропущено по вашему выбору" -f $d.C); continue }
        if (-not (Test-DefApplicable $d)) { Write-Log ("   [-] {0} -- нет на этой версии Windows" -f $d.C); continue }
        Apply-Def $d
    }
    if (($script:Failures + $script:Blocked) -gt $failBefore -and $script:ModuleHints.ContainsKey($m)) {
        Write-Log ("   [i] {0}" -f $script:ModuleHints[$m])
    }
}

# --- Компоненты производителя ---------------------------------------------- #
if ((Use-Module 'oem') -and -not $script:JournalFailed) {
    Write-Section 'Компоненты сбора данных производителя'
    $oem = Detect-Oem
    Write-Log ("   производитель: {0} {1}" -f $oem.manufacturer, $oem.model)
    if ($oem.items.Count -eq 0) { Write-Log '   [-] компонентов сбора данных не найдено' }
    # Что было до программы, теперь пишется в подписанный журнал отката, как
    # у любой службы и задачи. Раньше список лежал отдельно, в
    # oem-disabled.json без подписи: в переносимой папке его мог дописать
    # кто угодно, и откат включил бы указанные там службы и задачи.
    foreach ($it in $oem.items) {
        if ($DryRun) { Write-Log ("   [тест] {0} {1} -- отключить" -f $it.type, $it.display); continue }
        if ($script:JournalFailed) { break }
        try {
            if ($it.type -eq 'svc') {
                $s = Get-Service -Name $it.name -ErrorAction Stop
                if ($s.StartType -eq 'Disabled' -and $s.Status -ne 'Running') { Write-Log ("   [в] {0} -- уже отключено" -f $it.display); $script:Already++; continue }
                $was = Get-SvcJournalState $it.name $s
                if (-not (Write-AheadEntry $was)) { Write-Log ("   [!] {0} -- не меняется: «как было» не легло в журнал отката" -f $it.display); $script:Failures++; break }
                try {
                    if ($s.Status -eq 'Running') { Stop-Service -Name $it.name -Force -ErrorAction SilentlyContinue }
                    Set-Service -Name $it.name -StartupType Disabled -ErrorAction Stop
                } catch { if ($was.running) { Start-Service -Name $it.name -ErrorAction SilentlyContinue }; Undo-AheadEntry $was; throw }
            } else {
                $pp = Split-TaskPath $it.name
                $st = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop
                if (Test-TaskDisabled $st) { Write-Log ("   [в] {0} -- уже отключено" -f $it.display); $script:Already++; continue }
                $tj = @{ kind = 'task'; path = $it.name; old = 'Enabled'; newValue = 'Disabled' }
                if (-not (Write-AheadEntry $tj)) { Write-Log ("   [!] {0} -- не меняется: «как было» не легло в журнал отката" -f $it.display); $script:Failures++; break }
                try { Disable-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop | Out-Null } catch { Undo-AheadEntry $tj; throw }
            }
            Write-Log ("   [+] отключено: {0}" -f $it.display); $script:Changes++
        } catch { Write-Log ("   [!] не удалось: {0} -- {1}" -f $it.display, $_.Exception.Message); $script:Failures++ }
    }
    Save-JournalEntries -Quiet
}

# --- Другие пользователи и профиль по умолчанию ----------------------------- #
if ($AllProfiles -and -not $script:JournalFailed) { Apply-ProfilesHives }

# --- Буфер телеметрии ------------------------------------------------------- #
if ((Use-Module 'buffer') -and -not $script:JournalFailed) { Purge-Buffer }

# --- Чистка ----------------------------------------------------------------- #
if ((Use-Module 'cleanup') -and -not $script:JournalFailed) {
    Write-Section 'Чистка временных файлов'
    $total = 0.0
    $wu = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    $wuWasRunning = ($wu -and $wu.Status -eq 'Running')
    if ($wuWasRunning -and -not $DryRun) { Stop-Service wuauserv -Force -ErrorAction SilentlyContinue }
    $targets = @(
        @{ P = $env:TEMP;                                            L = 'временные файлы пользователя' },
        @{ P = "$env:SystemRoot\Temp";                               L = 'временные файлы Windows' },
        @{ P = "$env:SystemRoot\SoftwareDistribution\Download";      L = 'кэш загруженных обновлений' },
        @{ P = "$env:SystemRoot\Logs\CBS";                           L = 'логи обслуживания компонентов' },
        @{ P = "$env:LOCALAPPDATA\Microsoft\Windows\WER";            L = 'локальные отчёты об ошибках' },
        @{ P = "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"; L = 'очередь отчётов об ошибках' },
        @{ P = "$env:LOCALAPPDATA\CrashDumps";                       L = 'дампы аварийных завершений' },
        @{ P = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache";      L = 'кэш интернет-файлов' },
        @{ P = "$env:LOCALAPPDATA\D3DSCache";                        L = 'кэш шейдеров DirectX' }
    )
    $steps = $targets.Count + 3
    $n = 0
    Write-Log ("   шагов всего: {0}" -f $steps)
    foreach ($t in $targets) {
        $n++
        $tag = '[{0,3}%] ({1}/{2})' -f [int](100.0 * $n / $steps), $n, $steps
        $total += (Clear-FolderContents -FolderPath $t.P -Label $t.L -Step $tag)
    }
    if (-not $DryRun) {
        $thumbs = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
        if (Test-Path -LiteralPath $thumbs) {
            $before = Get-FolderSizeMB $thumbs
            Get-ChildItem -LiteralPath $thumbs -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            $f = [math]::Max(0, [math]::Round($before - (Get-FolderSizeMB $thumbs), 1)); $total += $f
            Write-Log ("   {0} кэш эскизов -- освобождено {1} МБ" -f ('[{0,3}%] ({1}/{2})' -f [int](100.0 * ($n + 1) / $steps), ($n + 1), $steps), $f)
        }
        $n++   # шаг «кэш эскизов» засчитан
        $n++   # следующий шаг — корзина
        $tag = '[{0,3}%] ({1}/{2})' -f [int](100.0 * $n / $steps), $n, $steps
        try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Log ("   {0} корзина очищена" -f $tag) } catch { Write-Log ("   {0} корзина уже пуста" -f $tag) }
        $n++
        $tag = '[{0,3}%] ({1}/{2})' -f [int](100.0 * $n / $steps), $n, $steps
        try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop | Out-Null; Write-Log ("   {0} кэш Delivery Optimization очищен" -f $tag) } catch { Write-Log ("   {0} кэш Delivery Optimization пропущен" -f $tag) }
    }
    if ($wuWasRunning -and -not $DryRun) { Start-Service wuauserv -ErrorAction SilentlyContinue }
    Write-Log '   [100%] чистка завершена'
    Write-Log ('   ИТОГО освобождено: ~{0} МБ' -f [math]::Round($total, 1))
}

# --- Автозагрузка ----------------------------------------------------------- #
if (Use-Module 'startup') {
    Write-Section 'Автозагрузка (только отчёт, ничего не отключается)'
    $stItems = @(Get-StartupList)
    if ($stItems.Count -gt 0) {
        foreach ($s in $stItems) {
            Write-Log ("   {0} {1}" -f $(if ($s.enabled) { '*' } else { '-' }), $s.name)
            Write-Log ("       команда : {0}" -f $s.cmd)
            Write-Log ("       источник: {0}" -f $s.source)
            if ($s.note) { Write-Log ("       это     : {0}" -f $s.note) }
        }
        Write-Log ''
        Write-Log ("   Всего записей: {0}, из них работает: {1}, лишних: {2}" -f $stItems.Count,
                   @($stItems | Where-Object { $_.enabled }).Count,
                   @($stItems | Where-Object { $_.enabled -and $_.advise }).Count)
    } else { Write-Log '   (записей не найдено)' }
    Write-Log ''; Write-Log '   Отключить лишнее: страница «Автозагрузка» или -StartupSet -StartupItems <id> -StartupValue Off.'
}

# --- Итог ------------------------------------------------------------------- #
Write-Section 'Итог'
# журнал для отката — дописываем к тому, что было раньше
Save-JournalEntries
if ($script:JournalFailed) {
    Write-Log '[!] Применение остановлено на середине: журнал отката перестал записываться. Что успело измениться до остановки, видно выше.'
}
# что Windows не отдала — запоминаем для проверки; что отдала — забываем
if (-not $DryRun -and ($script:BlockedIds.Count -gt 0 -or $script:UnblockedIds.Count -gt 0)) {
    try {
        $prevB = Load-Json 'blocked.json'
        $setB = @{}
        if ($prevB -and $prevB.ids) { foreach ($i in @($prevB.ids)) { $setB["$i"] = $true } }
        foreach ($i in $script:BlockedIds.Keys) { $setB[$i] = $true }
        foreach ($i in $script:UnblockedIds.Keys) { $setB.Remove($i) }
        Save-Json 'blocked.json' @{ ids = @($setB.Keys); updated = (Get-Date).ToString('s') }
    } catch { Write-Log ("   [-] список настроек, которые Windows не отдала, не сохранился: {0}" -f $_.Exception.Message) }
}

Write-Log ("Изменений применено : {0}" -f $script:Changes)
Write-Log ("Было уже настроено : {0}" -f $script:Already)
Write-Log ("Ошибок              : {0}" -f $script:Failures)
if ($script:Blocked -gt 0) { Write-Log ("Windows не разрешила: {0} (см. пометки [-] выше)" -f $script:Blocked) }
if ($script:BackupDir) { Write-Log ("Резервная копия     : {0}" -f $script:BackupDir) }
Write-Log ''
if ($script:Changes -gt 0) { Write-Log 'Перезагрузите компьютер, чтобы всё вступило в силу. Нажмите «Проверить» — программа прочитает реальное состояние системы.' }
else { Write-Log 'Менять было нечего — всё уже настроено. Нажмите «Проверить», чтобы увидеть состояние системы.' }
Emit-Json @{ changes=$script:Changes; already=$script:Already; failures=$script:Failures
             blocked=$script:Blocked; backup=$script:BackupDir }
Write-Log '###DONE###'
