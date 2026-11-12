# --- Службы, задачи и переменные среды в журнале отката --------------------- #
#  Раньше журнал помнил только реестр, а полный откат включал службы и задачи
#  «по умолчанию»: DiagTrack — автоматически, все задачи из списка — включить.
#  Задача, которую человек выключил сам задолго до программы, после отката
#  включалась. Теперь у каждой записано, какой она была до нас.
function Add-JournalEntry {
    param($Entry)
    if ($DryRun) { return }
    $Entry['time'] = (Get-Date).ToString('s')
    $script:Journal.Add($Entry)
    if ($script:Journal.Count -ge 10) { Save-JournalEntries -Quiet }
}

# Журнал раньше изменения (write-ahead). Прежде запись о том, «как было»,
# добавлялась после изменения и ложилась на диск пачками по десять: обрыв
# процесса между изменением и записью оставлял изменение без пути назад.
# Теперь «как было» сначала ложится на диск, и только потом меняется
# система. Не легло — менять нельзя ($false). Изменение не прошло — запись
# отзывается (Undo-AheadEntry): «было» в ней верное, просто изменения не было.
function Write-AheadEntry {
    param($Entry)
    if ($DryRun) { return $true }
    if ($script:JournalFailed) { return $false }
    $Entry['time'] = (Get-Date).ToString('s')
    $Entry['run'] = $script:RunId
    $script:Journal.Add($Entry)
    Save-JournalEntries -Quiet
    return (-not $script:JournalFailed)
}

function Undo-AheadEntry {
    param($Entry)
    if ($DryRun) { return }
    # ещё не на диске — просто убрать из очереди; уже на диске — отозвать при следующей записи
    if ($script:Journal.Remove($Entry)) { return }
    $null = $script:JournalRetract.Add((Get-JournalKey (ConvertTo-Fields $Entry)))
}

# Менять систему можно, только пока журнал отката пишется. Раньше это
# проверялось в применении модулей, но не в прямых вызовах записи реестра.
function Test-CanModify {
    param([string]$Label)
    if ($DryRun) { return $true }
    if ($script:JournalFailed) { Write-Log ("   [!] {0} -- не меняется: журнал отката сейчас не пишется" -f $Label); $script:Failures++; return $false }
    return $true
}

function Get-SvcJournalState {
    param([string]$Name, $Svc)
    $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    $start = Get-RegValue $k 'Start'
    $delayed = Get-RegValue $k 'DelayedAutostart'
    return @{ kind = 'svc'; name = $Name
              old = $(if ($null -ne $start) { "$start" } else { '' })
              delayed = $(if ($null -ne $delayed) { "$delayed" } else { '' })
              running = [bool]($Svc -and $Svc.Status -eq 'Running')
              newValue = '4' }
}

# Задачу программа гасит, только если она была включена, — это и запоминаем
function Add-TaskJournal {
    param([string]$Path)
    Add-JournalEntry @{ kind = 'task'; path = $Path; old = 'Enabled'; newValue = 'Disabled' }
}

# Политика аудита словами — для страницы «Журнал изменений»
function Get-AuditName {
    param([string]$Value)
    switch ("$Value") { '1' { return 'успех' } '2' { return 'отказ' } '3' { return 'успех и отказ' } }
    return 'выкл'
}

# Тип запуска службы словами — для страницы «Журнал изменений»
function Get-StartName {
    param([string]$Start, [string]$Delayed = '')
    switch ("$Start") {
        '0' { return 'при загрузке системы' }
        '1' { return 'системная' }
        '2' { if ("$Delayed" -eq '1') { return 'автоматически (отложенный запуск)' } return 'автоматически' }
        '3' { return 'вручную' }
        '4' { return 'отключена' }
    }
    return 'не было'
}

# Форма записи журнала перед тем, как по ней что-то делать. Подпись говорит,
# что запись не меняли, но не то, что она допустима: вид — из известных, поля
# на месте, пути реестра — только в его ветках, имена служб, задач и
# переменных — допустимого вида, GUID аудита — наш. Пустая строка — годится,
# иначе — почему нет.
function Test-JournalEntryShape {
    param($Entry)
    $f = ConvertTo-Fields $Entry
    $kind = "$($f['kind'])"
    $types = @('String', 'ExpandString', 'DWord', 'QWord', 'Binary', 'MultiString')
    $regPath = '^(HKLM|HKCU):\\[^\x00-\x1f]+$|^Registry::HKEY_(LOCAL_MACHINE|CURRENT_USER|USERS)\\[^\x00-\x1f]+$'
    switch ($kind) {
        'reg' {
            if ("$($f['path'])" -notmatch $regPath) { return 'путь не в ветке реестра' }
            if (-not "$($f['name'])") { return 'пустое имя параметра' }
            if ($f['existed'] -and "$($f['type'])" -notin $types) { return 'неизвестный тип значения' }
            return ''
        }
        'svc' {
            if ("$($f['name'])" -notmatch '^[A-Za-z0-9_.\-$]{1,256}$') { return 'недопустимое имя службы' }
            if ("$($f['old'])" -notmatch '^[0-4]?$') { return 'недопустимый тип запуска' }
            if ("$($f['delayed'])" -notmatch '^[01]?$') { return 'недопустимый отложенный запуск' }
            return ''
        }
        'task' {
            if ("$($f['path'])" -notmatch '^\\[^"\x00-\x1f%]+$') { return 'недопустимый путь задачи' }
            if ("$($f['old'])" -notin @('Enabled', 'Disabled')) { return 'недопустимое состояние задачи' }
            return ''
        }
        'env' {
            if ("$($f['name'])" -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,254}$') { return 'недопустимое имя переменной' }
            return ''
        }
        'audit' {
            if ("$($f['guid'])" -ne $script:AuditGuid) { return 'чужая подкатегория аудита' }
            if ("$($f['old'])" -notmatch '^[0-3]$') { return 'недопустимое значение аудита' }
            return ''
        }
        'startup' {
            if (-not "$($f['id'])") { return 'пустая запись автозагрузки' }
            if ("$($f['old'])" -notin @('On', 'Off')) { return 'недопустимое состояние автозагрузки' }
            return ''
        }
        'hive' {
            if ("$($f['file'])" -notmatch '^[A-Za-z]:\\[^\x00-\x1f]*\\NTUSER\.DAT$') { return 'недопустимый файл куста' }
            if ("$($f['sub'])" -match '^\\|\.\.|[\x00-\x1f]' -or -not "$($f['sub'])") { return 'недопустимый путь в кусте' }
            if (-not "$($f['name'])") { return 'пустое имя параметра' }
            if ($f['existed'] -and "$($f['type'])" -notin $types) { return 'неизвестный тип значения' }
            return ''
        }
    }
    return 'неизвестный вид записи'
}

# Возвращает одну запись журнала (реестр, служба, задача, переменная среды).
# Записи автозагрузки и чужих профилей возвращаются своими функциями.
function Restore-JournalEntry {
    param($e)
    try {
        switch ("$($e.kind)") {
            'svc' {
                $name = "$($e.name)"
                if (-not (Get-Service -Name $name -ErrorAction SilentlyContinue)) { return @{ ok = $true; note = 'службы больше нет' } }
                $start = "$($e.old)"
                $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
                $type = switch ($start) { '2' { 'Automatic' } '3' { 'Manual' } '4' { 'Disabled' } default { '' } }
                if ($type) { Set-Service -Name $name -StartupType $type -ErrorAction Stop }
                elseif ($start -ne '') { Set-ItemProperty -LiteralPath $k -Name 'Start' -Value ([int]$start) -Type DWord -ErrorAction Stop }
                if ("$($e.delayed)" -ne '') { Set-ItemProperty -LiteralPath $k -Name 'DelayedAutostart' -Value ([int]"$($e.delayed)") -Type DWord -ErrorAction SilentlyContinue }
                # тип запуска сверяется: «команда прошла» — ещё не «вернулось»
                if ($start -ne '' -and "$(Get-RegValue $k 'Start')" -ne $start) {
                    return @{ ok = $false; error = ("тип запуска не вернулся: сейчас {0}, нужно {1}" -f (Get-StartName "$(Get-RegValue $k 'Start')"), (Get-StartName $start)) }
                }
                # работала до нас — запускаем снова, чтобы не ждать перезагрузки;
                # не запустилась сейчас — так и сказано (тип запуска уже верный)
                if ($e.running -and $start -ne '4') {
                    try { Start-Service -Name $name -ErrorAction Stop }
                    catch { return @{ ok = $true; note = ("тип запуска возвращён, но сейчас служба не запустилась: {0}" -f $_.Exception.Message) } }
                }
                return @{ ok = $true }
            }
            'task' {
                if ("$($e.old)" -ne 'Enabled') { return @{ ok = $true } }
                $r = Set-TaskEnabled "$($e.path)" $true
                if ($r -in @('ok', 'system')) { return @{ ok = $true } }
                # задачи больше нет — возвращать нечего, но это не «вернулось»
                if ($r -eq 'missing') { return @{ ok = $true; note = 'задачи больше нет' } }
                return @{ ok = $false; error = 'Windows не дала включить задачу' }
            }
            'env' {
                $v = $(if ($e.existed) { "$($e.old)" } else { $null })
                [Environment]::SetEnvironmentVariable("$($e.name)", $v, 'User')
                return @{ ok = $true }
            }
            'audit' {
                $r = Set-AuditSetting "$($e.guid)" ([int]"$($e.old)")
                if ($r.ok) { return @{ ok = $true } }
                return @{ ok = $false; error = ("auditpol (код {0}): {1}" -f $r.code, $r.out) }
            }
            default {
                if ($e.existed) {
                    if (-not (Test-Path -LiteralPath $e.path)) { New-Item -Path $e.path -Force -ErrorAction Stop | Out-Null }
                    New-ItemProperty -LiteralPath $e.path -Name $e.name -Value $e.old -PropertyType $e.type -Force -ErrorAction Stop | Out-Null
                } else {
                    Remove-ItemProperty -LiteralPath $e.path -Name $e.name -Force -ErrorAction SilentlyContinue
                }
                return @{ ok = $true }
            }
        }
    } catch { return @{ ok = $false; error = $_.Exception.Message } }
}
