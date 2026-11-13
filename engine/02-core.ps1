
# =========================================================================== #
#  Служебные функции
# =========================================================================== #
function Write-Log { param([string]$Message = '') Write-Host $Message }
function Write-Section { param([string]$Title) Save-JournalEntries -Quiet; Write-Log ''; Write-Log ('--- ' + $Title + ' ' + ('-' * [Math]::Max(3, 60 - $Title.Length))) }
function Emit-Json { param($Object) Write-Host ('###JSON### ' + ($Object | ConvertTo-Json -Compress -Depth 8)) }
function Use-Module { param([string]$Name) return ($Modules -contains $Name) }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try { $p = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop; return $p.$Name } catch { return $null }
}

# Удаляет свою задачу планировщика (страж, слежение, уведомления). «Задачи
# нет» и «задача не удалилась» — разное: раньше любая ошибка удаления
# называлась «задачи нет», и оставшийся страж потом снова выключал то, что
# человек только что вернул. Ответ: removed, absent или failed (посчитано).
function Remove-OwnTask {
    param([string]$Name, [string]$What)
    # «нет такой задачи» (ObjectNotFound) и «планировщик не ответил» — тоже разное
    $t = $null
    try { $t = Get-ScheduledTask -TaskName $Name -ErrorAction Stop }
    catch {
        if ("$($_.CategoryInfo.Category)" -eq 'ObjectNotFound') { Write-Log ("   [-] {0}: нет" -f $What); return 'absent' }
        Write-Log ("   [!] {0}: планировщик не ответил -- {1}" -f $What, $_.Exception.Message); $script:Failures++; return 'failed'
    }
    if (-not $t) { Write-Log ("   [-] {0}: нет" -f $What); return 'absent' }
    # работающую сейчас — сначала остановить, чтобы она не доделала своё
    if ("$($t.State)" -eq 'Running') { Stop-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue }
    try { Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction Stop }
    catch { Write-Log ("   [!] {0}: не удалилось -- {1}" -f $What, $_.Exception.Message); $script:Failures++; return 'failed' }
    Write-Log ("   [+] {0}: удалено" -f $What)
    return 'removed'
}

# Выключена ли задача планировщика. State тут не годится: «Disabled» он
# показывает, только пока у задачи нет работающего экземпляра, — выключенная
# задача, которая ещё доделывает свой запуск, видна как «Running», а включённая
# — как «Ready» или «Running». Признак — Settings.Enabled; State — только
# если настроек у объекта нет.
function Test-TaskDisabled {
    param($Task)
    if ($null -eq $Task) { return $false }
    $s = $Task.Settings
    if ($null -ne $s -and $null -ne $s.Enabled) { return (-not [bool]$s.Enabled) }
    return ("$($Task.State)" -eq 'Disabled')
}

# Есть ли ключ: $true, $false или $null — неизвестно (нет доступа).
function Test-RegKeyExists {
    param([string]$Path)
    $k = $null
    try { $k = Open-RegKeyRead $Path; return ($null -ne $k) }
    catch { return $null }
    finally { if ($null -ne $k) { $k.Close() } }
}

# Самый верхний из ключей, которых нет на пути к $Path (его и всё ниже
# создаст New-Item -Force). Ключ уже есть — пустая строка. Если о ключе
# или его родителе нельзя сказать наверняка (нет доступа), он «есть»: удалять
# потом можно только то, что программа точно создала сама.
function Get-TopMissingKey {
    param([string]$Path)
    if ((Test-RegKeyExists $Path) -ne $false) { return '' }
    $top = $Path
    while ($true) {
        $parent = Split-Path -Path $top -Parent
        if (-not $parent -or $parent -eq $top -or (Test-RegKeyExists $parent) -ne $false) { break }
        $top = $parent
    }
    return $top
}

# Ключ и всё под ним без единого значения. Что-то не прочиталось — считаем,
# что не пуст: удалять можно только то, что точно пусто.
function Test-KeyTreeEmpty {
    param([string]$Path)
    try {
        $k = Get-Item -LiteralPath $Path -ErrorAction Stop
        try { if ($k.ValueCount -gt 0) { return $false } } finally { $k.Close() }
        foreach ($c in @(Get-ChildItem -LiteralPath $Path -Recurse -ErrorAction Stop)) {
            try { if ($c.ValueCount -gt 0) { return $false } } finally { $c.Close() }
        }
        return $true
    } catch { return $false }
}

# Ключ реестра на чтение — RegistryKey или $null, если ключа нет. Нет доступа
# (к нему или к ключу выше) — исключение, а не $null. Пути — как у провайдера
# PowerShell: HKLM:\…, HKCU:\…, Registry::HKEY_USERS\… и т. п.
function Open-RegKeyRead {
    param([string]$Path)
    $hive = $null; $sub = ''
    switch -Regex ($Path) {
        '^(HKLM:|Registry::HKEY_LOCAL_MACHINE)(\\(.*))?$' { $hive = [Microsoft.Win32.Registry]::LocalMachine; $sub = $Matches[3]; break }
        '^(HKCU:|Registry::HKEY_CURRENT_USER)(\\(.*))?$'  { $hive = [Microsoft.Win32.Registry]::CurrentUser; $sub = $Matches[3]; break }
        '^(HKU:|Registry::HKEY_USERS)(\\(.*))?$'          { $hive = [Microsoft.Win32.Registry]::Users; $sub = $Matches[3]; break }
        '^(HKCR:|Registry::HKEY_CLASSES_ROOT)(\\(.*))?$'  { $hive = [Microsoft.Win32.Registry]::ClassesRoot; $sub = $Matches[3]; break }
    }
    if ($null -eq $hive) { throw ("неизвестная ветка реестра: {0}" -f $Path) }
    # OpenSubKey('') — отдельный дескриптор самого куста: его можно закрыть
    return $hive.OpenSubKey("$sub".TrimEnd('\'), $false)
}

# Два прочитанных состояния значения (Get-RegRaw) — одно и то же: оба «нет»
# или оба есть, того же вида и с теми же данными.
function Test-RegSameRaw {
    param($A, $B)
    if (-not $A.exists -or -not $B.exists) { return ([bool]$A.exists -eq [bool]$B.exists) }
    return ("$($A.kind)" -eq "$($B.kind)" -and (ConvertTo-RegComparable $A.value $A.kind) -eq (ConvertTo-RegComparable $B.value $B.kind))
}

# Виды значений реестра, которые программа умеет записать и вернуть.
function Test-RegKind {
    param([string]$Kind)
    return ($Kind -in @('String', 'ExpandString', 'DWord', 'QWord', 'Binary', 'MultiString'))
}

# Значение реестра как оно лежит: вид (String, DWord, ...) и данные без
# раскрытия %переменных%. Get-ItemProperty раскрывает REG_EXPAND_SZ и вида не
# называет, а откату нужно и то и другое: «%SystemRoot%\x», возвращённое
# раскрытым, или строка, возвращённая числом, — уже не то, что было.
# ok = $false — прочитать не удалось (это не «параметра нет»).
# Ключ открывается средствами самого реестра (Open-RegKeyRead): «ключа нет»
# там — пустой ответ, «нет доступа» — исключение. Раньше сначала спрашивался
# Test-Path, а он ключ, до которого нельзя добраться, мог назвать отсутствующим,
# и в журнал легло бы «значения не было».
function Get-RegRaw {
    param([string]$Path, [string]$Name)
    $key = $null
    try {
        $key = Open-RegKeyRead $Path
        if ($null -eq $key) { return @{ ok = $true; exists = $false; kind = ''; value = $null } }
        if (@($key.GetValueNames()) -notcontains $Name) { return @{ ok = $true; exists = $false; kind = ''; value = $null } }
        return @{ ok = $true; exists = $true; kind = "$($key.GetValueKind($Name))"
                  value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
    } catch {
        # denied — Windows не даёт даже прочитать (это её решение, а не сбой)
        $ex = $_.Exception
        $denied = ($ex -is [System.UnauthorizedAccessException] -or $ex -is [System.Security.SecurityException] -or
                   $ex.InnerException -is [System.UnauthorizedAccessException] -or $ex.InnerException -is [System.Security.SecurityException])
        return @{ ok = $false; exists = $false; kind = ''; value = $null; denied = $denied
                  error = ("{0}: {1}" -f $ex.GetType().Name, $ex.Message) }
    } finally {
        # открытый ключ держит куст чужого профиля: его потом не отключить
        if ($null -ne $key) { try { $key.Close() } catch { } }
    }
}

# Запасная запись мимо провайдера PowerShell: обычный API реестра просит
# ровно те права, которые нужны, и иногда справляется там, где New-ItemProperty
# уже получил отказ. Заодно рассказывает, чем именно кончилась попытка.
function Set-RegDirect {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    try {
        $hive = $null; $sub = ''
        if ($Path -match '^HKLM:\\(.+)$')      { $hive = [Microsoft.Win32.Registry]::LocalMachine; $sub = $Matches[1] }
        elseif ($Path -match '^HKCU:\\(.+)$')  { $hive = [Microsoft.Win32.Registry]::CurrentUser;  $sub = $Matches[1] }
        elseif ($Path -match '^HKCR:\\(.+)$')  { $hive = [Microsoft.Win32.Registry]::ClassesRoot;  $sub = $Matches[1] }
        elseif ($Path -match '^HKU:\\(.+)$')   { $hive = [Microsoft.Win32.Registry]::Users;        $sub = $Matches[1] }
        else { return @{ ok = $false; error = 'неизвестный куст реестра' } }
        $key = $hive.CreateSubKey($sub, $true)
        if ($null -eq $key) { return @{ ok = $false; error = 'ключ не открылся на запись' } }
        try {
            switch ($Type) {
                'DWord'        { $key.SetValue($Name, [int]$Value,  [Microsoft.Win32.RegistryValueKind]::DWord) }
                'QWord'        { $key.SetValue($Name, [long]$Value, [Microsoft.Win32.RegistryValueKind]::QWord) }
                'Binary'       { $key.SetValue($Name, [byte[]]$Value, [Microsoft.Win32.RegistryValueKind]::Binary) }
                'ExpandString' { $key.SetValue($Name, [string]$Value, [Microsoft.Win32.RegistryValueKind]::ExpandString) }
                'MultiString'  { $key.SetValue($Name, [string[]]$Value, [Microsoft.Win32.RegistryValueKind]::MultiString) }
                default        { $key.SetValue($Name, [string]$Value, [Microsoft.Win32.RegistryValueKind]::String) }
            }
        } finally { $key.Close() }
        return @{ ok = $true }
    } catch { return @{ ok = $false; error = ("{0}: {1}" -f $_.Exception.GetType().Name, $_.Exception.Message) } }
}

# Пишет во временный параметр рядом и сразу его убирает. Так видно, закрыт
# ли ключ целиком или Windows держит только один конкретный параметр.
function Test-RegKeyWritable {
    param([string]$Path)
    $probe = '_Win11PrivacyProbe'
    $r = Set-RegDirect -Path $Path -Name $probe -Value 1 -Type 'DWord'
    if (-not $r.ok) { return $false }
    try { Remove-ItemProperty -LiteralPath $Path -Name $probe -Force -ErrorAction SilentlyContinue } catch { }
    return $true
}

# Значение реестра в виде, который можно сравнить с задуманным: DWORD больше
# 0x7FFFFFFF читается отрицательным числом, расширяемая строка — уже
# раскрытой, двоичное и многострочное — массивами.
function ConvertTo-RegComparable {
    param($Value, [string]$Type)
    if ($null -eq $Value) { return $null }
    switch ($Type) {
        'DWord' { try { $n = [decimal]"$Value"; if ($n -lt 0) { $n += [decimal]4294967296 }; return "$n" } catch { return "$Value" } }
        'QWord' { try { $n = [decimal]"$Value"; if ($n -lt 0) { $n += [decimal]::Parse('18446744073709551616') }; return "$n" } catch { return "$Value" } }
        'ExpandString' { return [Environment]::ExpandEnvironmentVariables("$Value") }
        'Binary' { return ((@($Value) | ForEach-Object { '{0:x2}' -f [byte]$_ }) -join '') }
        'MultiString' { return (@($Value) -join "`n") }
    }
    return "$Value"
}

function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord', [string]$Comment = '',
          [switch]$Policy, [string]$DefId = '')
    $label = if ($Comment) { $Comment } else { "$Path -> $Name" }
    if ($DryRun) { Write-Log "   [тест] $label"; return }

    # Если параметр уже такой, как нужно — не трогаем его: часть значений
    # панели задач Windows защищает от перезаписи даже тем же самым числом.
    # «Такой» — и по данным, и по виду: строка «1» вместо числа 1 раньше
    # считалась настроенной, хотя Windows читает такой параметр как ошибку.
    # Откату нужен прежний вид значения и данные как есть: раньше в журнал шёл
    # вид нового значения, и строка «1» возвращалась числом. Есть ли значение
    # вообще — тоже отсюда: пустое двоичное или многострочное Get-RegValue
    # отдаёт как «нет», и откат удалил бы его вместо возврата. Этот же
    # прочитанный вид решает, настроено ли уже: REG_SZ «1» на месте DWORD 1
    # раньше считался настроенным, хотя Windows читает такой параметр иначе.
    $cur = Get-RegValue $Path $Name
    $raw = Get-RegRaw $Path $Name
    if ($raw.ok -and $raw.exists -and "$($raw.kind)" -eq $Type -and
        (ConvertTo-RegComparable $raw.value $Type) -eq (ConvertTo-RegComparable $Value $Type)) { Write-Log "   [в] $label -- уже настроено"; $script:Already++; return }

    # Менять можно, только пока пишется журнал отката, — в том числе при
    # прямых вызовах (монитор, чистка), а не только из применения модулей.
    if (-not (Test-CanModify $label)) { return }
    Ensure-Backup          # копию делаем перед первым изменением, а не «всегда»
    if (-not $raw.ok -and $raw.denied -and $Policy) {
        # как и отказ в записи ниже: политику держит сама Windows
        Write-Log "   [-] $label -- Windows этой редакции не разрешает менять этот параметр"
        $script:Blocked++
        if ($DefId) { $script:BlockedIds[$DefId] = $true }
        return
    }
    if (-not $raw.ok -or ($null -ne $cur -and -not $raw.exists)) {
        # не прочиталось — «как было» записать нечем, а без него менять нельзя
        Write-Log ("   [!] {0} -- не меняется: прежнее значение не прочиталось ({1}), вернуть его было бы нечем" -f $label, $(if ($raw.error) { $raw.error } else { 'значение есть, но не читается' }))
        $script:Failures++; return
    }
    $existed = [bool]$raw.exists
    $oldValue = ''
    $oldType = $Type
    if ($existed) {
        if (-not (Test-RegKind $raw.kind)) {
            Write-Log ("   [!] {0} -- не меняется: прежнее значение вида {1}, такое откат вернуть не сумеет" -f $label, $raw.kind)
            $script:Failures++; return
        }
        $oldType = $raw.kind
        $oldValue = $raw.value
    }
    # Ключа нет — New-Item создаст и его, и недостающие ключи выше. Самый
    # верхний из них запоминается: откат уберёт его, если в нём не останется
    # ни одного значения. Раньше пустые ключи политик оставались навсегда.
    $createdKey = Get-TopMissingKey $Path
    # «Как было» — на диск раньше изменения (см. Write-AheadEntry). Если
    # изменение не пройдёт, запись отзывается: изменения ведь не было.
    # type — вид прежнего значения (им его и вернёт откат).
    $entry = @{ kind = 'reg'; path = $Path; name = $Name; type = $oldType; existed = $existed; old = $oldValue; newValue = "$Value" }
    if ($createdKey) { $entry['createdKey'] = $createdKey }
    if (-not (Write-AheadEntry $entry)) {
        Write-Log "   [!] $label -- не меняется: «как было» не легло в журнал отката"
        $script:Failures++; return
    }
    $done = $false
    $why = ''
    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        $done = $true
    } catch {
        $why = ("{0}: {1}" -f $_.Exception.GetType().Name, $_.Exception.Message)
        # Команда сообщила об ошибке, но значение могло и лечь. Раньше в этом
        # случае запись «как было» отзывалась («уже настроено»), хотя до записи
        # значение было другим — изменение было, и путь назад терялся. Теперь
        # такое значение — сделанное изменение: запись остаётся, дальше — сверка.
        $after = Get-RegRaw $Path $Name
        if ($after.ok -and $after.exists -and $after.kind -eq $Type -and (ConvertTo-RegComparable $after.value $Type) -eq (ConvertTo-RegComparable $Value $Type)) {
            Write-Log ("   [i] {0} -- команда записи сообщила об ошибке ({1}), но значение легло" -f $label, $why)
            $done = $true
        } else {
            $retry = Set-RegDirect -Path $Path -Name $Name -Value $Value -Type $Type
            if ($retry.ok) { $done = $true } else { $why += " / вторая попытка: $($retry.error)" }
        }
    }

    if ($done) {
        # «Команда прошла» — ещё не «значение такое»: читаем обратно и сверяем
        # и данные, и вид значения. Запись в журнале остаётся в любом случае:
        # значение уже не прежнее.
        $now = Get-RegRaw $Path $Name
        $want = ConvertTo-RegComparable $Value $Type
        $got = $(if ($now.ok -and $now.exists) { ConvertTo-RegComparable $now.value $Type } else { $null })
        if (-not $now.ok -or -not $now.exists -or $now.kind -ne $Type -or $got -ne $want) {
            $seen = $(if (-not $now.ok) { "не читается ($($now.error))" } elseif (-not $now.exists) { 'нет значения' } elseif ($now.kind -ne $Type) { "{0} вида {1}" -f $got, $now.kind } else { $got })
            Write-Log ("   [!] {0} -- записано, но читается другое: ожидалось {1} ({2}), сейчас {3}" -f $label, $want, $Type, $seen)
            $script:Failures++
            return
        }
        if ($Policy -and $DefId) { $script:UnblockedIds[$DefId] = $true }   # отдала — снимаем пометку
        Write-Log "   [+] $label"; $script:Changes++
        return
    }

    # Записать не вышло. Было ли изменение — решает не ответ команды, а то, что
    # лежит сейчас: прежнее значение — изменения не было, запись отзывается;
    # не прочиталось или стало чем-то третьим (запись оборвалась на середине) —
    # запись «как было» остаётся для отката, и это ошибка.
    $now = Get-RegRaw $Path $Name
    if (-not $now.ok -or -not (Test-RegSameRaw $now $raw)) {
        $state = $(if (-not $now.ok) { "не читается ({0})" -f $now.error } elseif (-not $now.exists) { 'значения нет' } else { "{0} вида {1}" -f (ConvertTo-RegComparable $now.value $now.kind), $now.kind })
        Write-Log ("   [!] {0} -- не записалось ({1}), но значение уже не прежнее: сейчас {2}. Запись «как было» оставлена для отката" -f $label, $why, $state)
        $script:Failures++
        return
    }
    Undo-AheadEntry $entry
    # ключ, который успел создать New-Item, — пустой и ничей: убираем
    if ($createdKey -and (Test-RegKeyExists $createdKey) -and (Test-KeyTreeEmpty $createdKey)) {
        Remove-Item -LiteralPath $createdKey -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($why -like '*UnauthorizedAccessException*' -or $why -like '*SecurityException*') {
        # Часть политик Windows держит сама и не отдаёт даже администратору —
        # это не поломка программы, а решение системы, и в ошибки оно не идёт.
        if ($Policy) {
            Write-Log "   [-] $label -- Windows этой редакции не разрешает менять этот параметр"
            $script:Blocked++
            if ($DefId) { $script:BlockedIds[$DefId] = $true }
            return
        }
        Write-Log "   [!] $label -- Windows не отдаёт этот параметр даже администратору"
        Write-Log "       ключ: $Path -> $Name"
        Write-Log "       права администратора у программы: $(if (Test-Admin) { 'есть' } else { 'НЕТ' })"
        if (Test-RegKeyWritable $Path) {
            Write-Log "       ключ пишется, но именно этот параметр Windows защищает"
        } else {
            Write-Log "       ключ закрыт целиком: менять его может только сама система"
        }
        Write-Log "       подробности: $why"
    } else {
        Write-Log "   [!] не удалось: $label -- $why"
    }
    $script:Failures++
}

function Get-FolderSizeMB {
    param([string]$FolderPath)
    if (-not (Test-Path -LiteralPath $FolderPath)) { return 0 }
    # только файлы: у каталогов нет Length, и Measure-Object сыпал ошибкой в журнал
    $sum = (Get-ChildItem -LiteralPath $FolderPath -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    if (-not $sum) { return 0 }
    return [math]::Round($sum / 1MB, 1)
}

# Удаление дерева, которое не заходит внутрь ссылок. Remove-Item -Recurse в
# PowerShell 5.1 проходит по junction и символическим ссылкам и удаляет то,
# куда они ведут: ссылка во временной папке на «Документы» стёрла бы
# документы. Здесь ссылка удаляется сама, как запись, — её цель не трогается.
# $Stats — @{ deleted; failed; skipped; errors }: что удалено, что нет и почему.
#
# -TrustedOwnerOnly — для общих системных папок (C:\Windows\Temp,
# ProgramData\...\WER), куда может писать любой пользователь: удаляется
# только то, чей владелец доверенный ($script:ClearOwners), и только в такие
# папки движок заходит. Остальное оставляется его хозяину.
$script:ClearOwners = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-19', 'S-1-5-20',
                        'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
function Test-TrustedOwner {
    param([string]$Path)
    try { return ($script:ClearOwners -contains (Get-Acl -LiteralPath $Path -ErrorAction Stop).GetOwner([Security.Principal.SecurityIdentifier]).Value) }
    catch { return $false }
}

function Remove-TreeNoFollow {
    param([string]$Path, $Stats, [switch]$TrustedOwnerOnly)
    try { $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop } catch { return }
    try {
        # Общая системная папка: чужое не трогаем и внутрь не заходим. Ссылки
        # пропускаются целиком: Get-Acl на ссылке отвечает про её ЦЕЛЬ, и по
        # владельцу судить о самой ссылке нельзя.
        if ($TrustedOwnerOnly -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not (Test-TrustedOwner $item.FullName))) { $Stats.skipped++; return }
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            if ($item.PSIsContainer) { [IO.Directory]::Delete($item.FullName, $false) } else { [IO.File]::Delete($item.FullName) }
            $Stats.deleted++
            return
        }
        if ($item.PSIsContainer) {
            foreach ($c in @(Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue)) { Remove-TreeNoFollow $c.FullName $Stats -TrustedOwnerOnly:$TrustedOwnerOnly }
            # папка уходит, только если опустела: что внутри не удалилось, уже посчитано
            if (@(Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0) { [IO.Directory]::Delete($item.FullName, $false) }
            return
        }
        if ($item.Attributes -band [IO.FileAttributes]::ReadOnly) { $item.Attributes = $item.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly) }
        [IO.File]::Delete($item.FullName)
        $Stats.deleted++
    } catch {
        $Stats.failed++
        if ($Stats.errors.Count -lt 3) { $Stats.errors.Add(("{0}: {1}" -f $item.Name, $_.Exception.Message)) }
    }
}

# Сценарий для задачи от имени пользователя: очищает его папки тем же
# способом — ссылки удаляются как записи, внутрь них не заходит. -MinAgeHours
# оставляет свежие файлы (во временной папке ими ещё пользуются программы).
function Get-ClearUserScript {
    return @'
param([string]$InputFile, [string]$ResultFile)
$in = (Get-Content -LiteralPath $InputFile -Raw -Encoding UTF8) | ConvertFrom-Json
function Clr($p, $s, $cut) {
  try { $i = Get-Item -LiteralPath $p -Force -ErrorAction Stop } catch { return }
  try {
    if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) {
      if ($i.PSIsContainer) { [IO.Directory]::Delete($i.FullName, $false) } else { [IO.File]::Delete($i.FullName) }
      $s.deleted++; return }
    if ($i.PSIsContainer) {
      foreach ($c in @(Get-ChildItem -LiteralPath $i.FullName -Force -ErrorAction SilentlyContinue)) { Clr $c.FullName $s $cut }
      if (@(Get-ChildItem -LiteralPath $i.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0) { [IO.Directory]::Delete($i.FullName, $false) }
      return }
    if ($cut -and ($i.LastWriteTime -gt $cut -or $i.CreationTime -gt $cut)) { $s.recent++; return }
    $len = $i.Length
    if ($i.Attributes -band [IO.FileAttributes]::ReadOnly) { $i.Attributes = $i.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly) }
    [IO.File]::Delete($i.FullName); $s.deleted++; $s.bytes += $len
  } catch { $s.failed++; if ($s.errors.Count -lt 3) { $s.errors += ('{0}: {1}' -f $i.Name, $_.Exception.Message) } }
}
$out = @()
foreach ($t in @($in.targets)) {
  $s = @{ path = "$($t.path)"; state = 'done'; deleted = 0; failed = 0; recent = 0; bytes = [int64]0; errors = @() }
  $p = "$($t.path)"
  if (-not (Test-Path -LiteralPath $p -PathType Container)) { $s.state = 'missing' }
  elseif ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { $s.state = 'link' }
  else {
    $cut = $null; if ([double]$t.minAgeHours -gt 0) { $cut = (Get-Date).AddHours(-[double]$t.minAgeHours) }
    $f = "$($t.filter)"
    $items = $(if ($f) { @(Get-ChildItem -LiteralPath $p -Filter $f -File -Force -ErrorAction SilentlyContinue) } else { @(Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue) })
    foreach ($c in $items) { Clr $c.FullName $s $cut }
  }
  $out += $s
}
ConvertTo-Json -InputObject @{ targets = $out } -Depth 5 -Compress | Set-Content -LiteralPath $ResultFile -Encoding UTF8
'@
}

# Папки, которые очищать нельзя ни при каком пути: корень диска и системные корни
function Test-ClearForbidden {
    param([string]$Full)
    $f = $Full.TrimEnd('\')
    if ($f -eq ([IO.Path]::GetPathRoot($Full)).TrimEnd('\')) { return $true }
    foreach ($p in @($env:SystemRoot, "$env:SystemRoot\System32", $env:ProgramData, $env:ProgramFiles, ${env:ProgramFiles(x86)},
                     $env:USERPROFILE, [Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('Desktop'), (Split-Path $env:USERPROFILE -Parent))) {
        if ($p -and $f -eq ([IO.Path]::GetFullPath($p)).TrimEnd('\')) { return $true }
    }
    return $false
}

function Clear-FolderContents {
    param([string]$FolderPath, [string]$Label, [string]$Step = '', [switch]$TrustedOwnerOnly)
    if (-not (Test-Path -LiteralPath $FolderPath)) {
        if ($Step) { Write-Log ("   {0} {1} -- нечего чистить" -f $Step, $Label) }
        return 0.0
    }
    $full = [IO.Path]::GetFullPath($FolderPath)
    # Сама папка — ссылка (например, временную папку подменили junction на
    # «Документы») или корень, который чистить нельзя: отказ, а не удаление.
    $dirItem = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if (($dirItem -and ($dirItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) -or (Test-ClearForbidden $full)) {
        Write-Log ("   [!] {0} -- папка {1} ведёт не туда (ссылка или системная папка) -- не очищается" -f $Label, $full)
        $script:Failures++
        return 0.0
    }
    # Большую папку посчитать и вычистить — это минуты, а строка шага
    # появлялась только в конце, и чистка выглядела зависшей.
    if ($Step) { Write-Log ("   {0} {1}..." -f $Step, $Label) }
    $before = Get-FolderSizeMB $full
    if ($DryRun) { Write-Log ("   {0} [тест] {1} -- можно освободить ~{2} МБ" -f $Step, $Label, $before); return 0.0 }
    $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
    foreach ($c in @(Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue)) { Remove-TreeNoFollow $c.FullName $st -TrustedOwnerOnly:$TrustedOwnerOnly }
    $freed = [math]::Max(0, [math]::Round($before - (Get-FolderSizeMB $full), 1))
    if ($Step) { Write-Log ("   {0} {1} -- освобождено {2} МБ" -f $Step, $Label, $freed) }
    else { Write-Log ("   [+] {0} -- освобождено {1} МБ" -f $Label, $freed) }
    # Что не удалилось, называется: раньше ошибки глушились, и «освобождено»
    # выглядело полным. Занятые файлы — обычное дело, это сведения, а не сбой.
    if ($st.skipped -gt 0) { Write-Log ("       оставлено файлов и папок других пользователей: {0}" -f $st.skipped) }
    if ($st.failed -gt 0) {
        Write-Log ("       не удалено (заняты или нет доступа): {0}" -f $st.failed)
        foreach ($e in $st.errors) { Write-Log ("       {0}" -f $e) }
    }
    $script:LastClear = $st
    return [double]$freed
}

# Системная ли папка: внутри Windows или ProgramData. Такие движок чистит сам
# (с -TrustedOwnerOnly); всё прочее — папки пользователя, их чистит задача
# от его имени.
function Test-SystemClearPath {
    param([string]$Full)
    foreach ($root in @($script:WinDir, $script:ProgramDataDir)) {
        if ($root -and $Full.StartsWith($root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# Папки пользователя — одной задачей от его имени. $Targets — список
# @{ P; L; Age (часы, 0 — все); Filter (маска файлов в самой папке) }.
# Возвращает освобождённые МБ.
function Clear-UserFolders {
    param([object[]]$Targets)
    $send = @(); $total = 0.0
    foreach ($t in $Targets) {
        # папки того, кто сидит за компьютером (см. Convert-ToSessionPath)
        $full = Convert-ToSessionPath ([IO.Path]::GetFullPath($t.P))
        if (Test-ClearForbidden $full) { Write-Log ("   [!] {0} -- {1} чистить нельзя" -f $t.L, $full); $script:Failures++; continue }
        $send += @{ path = $full; label = "$($t.L)"; minAgeHours = [double]$t.Age; filter = "$($t.Filter)" }
    }
    if ($send.Count -eq 0) { return 0.0 }
    if ($DryRun) { foreach ($s in $send) { Write-Log ("   [тест] {0} -- очистит задача от вашего имени" -f $s.label) }; return 0.0 }
    $r = Invoke-AsUser 'clear' (Get-ClearUserScript) @{ targets = $send } -Minutes 15
    if (-not $r.ok) {
        Write-Log ("   [!] папки профиля не очищены: {0}" -f $r.why); $script:Failures++
        return 0.0
    }
    for ($i = 0; $i -lt $send.Count; $i++) {
        $res = @($r.result.targets)[$i]
        $lbl = $send[$i].label
        if ($null -eq $res) { Write-Log ("   [!] {0} -- итога нет" -f $lbl); $script:Failures++; continue }
        switch ("$($res.state)") {
            'missing' { Write-Log ("   [-] {0} -- нечего чистить" -f $lbl) }
            'link'    { Write-Log ("   [!] {0} -- папка оказалась ссылкой и не очищается" -f $lbl); $script:Failures++ }
            default {
                $mb = [math]::Round([double]$res.bytes / 1MB, 1); $total += $mb
                Write-Log ("   [+] {0} -- освобождено {1} МБ" -f $lbl, $mb)
                if ([int]$res.recent -gt 0) { Write-Log ("       оставлено свежих файлов (моложе {0} ч): {1}" -f $send[$i].minAgeHours, $res.recent) }
                if ([int]$res.failed -gt 0) {
                    Write-Log ("       не удалено (заняты или нет доступа): {0}" -f $res.failed)
                    foreach ($e in @($res.errors)) { if ($e) { Write-Log ("       {0}" -f $e) } }
                }
            }
        }
    }
    return [double]$total
}

# Одна папка — тем способом, который ей годится (см. Test-SystemClearPath)
function Clear-Folder {
    param([string]$FolderPath, [string]$Label, [string]$Step = '', [double]$MinAgeHours = 0)
    $full = [IO.Path]::GetFullPath($FolderPath)
    if (Test-SystemClearPath $full) { return (Clear-FolderContents $full $Label $Step -TrustedOwnerOnly) }
    if ($Step) { Write-Log ("   {0} {1}..." -f $Step, $Label) }
    return (Clear-UserFolders @(@{ P = $full; L = $Label; Age = $MinAgeHours }))
}

# Задачи по маске имени (OneDrive*, NvTm*) — только в своих папках
# планировщика. Раньше проверялось одно имя: задача с подходящим именем
# годилась в любой папке, и откат журнала прежней версии мог включить чужую.
# OneDrive и NVIDIA кладут эти задачи в корень библиотеки.
$script:TaskGlobFolders = @{ 'OneDrive*' = @('\'); 'NvTm*' = @('\') }

function Get-TaskGlobFolders {
    param([string]$Glob)
    if ($script:TaskGlobFolders -and $script:TaskGlobFolders[$Glob]) { return @($script:TaskGlobFolders[$Glob]) }
    return @('\')
}

# полный путь задачи («\папка\имя») подходит под маску и её папки
function Test-TaskGlobPath {
    param([string]$Full, [string]$Glob)
    $pp = Split-TaskPath $Full
    return (((Get-TaskGlobFolders $Glob) -contains $pp[0]) -and ($pp[1] -like $Glob))
}

# -AnyFolder — только для прежнего отката: версии до 1.11 отключали задачи по
# маске в любой папке и в журнал их не писали; вернуть их можно лишь тем же
# поиском. Маски тут — свои, из списка программы, а не данные из журнала.
function Get-TaskGlobTasks {
    param([string]$Glob, [switch]$AnyFolder)
    $folders = @(Get-TaskGlobFolders $Glob)
    return @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { ($AnyFolder -or ($folders -contains $_.TaskPath)) -and ($_.TaskName -like $Glob) })
}

function Split-TaskPath {
    param([string]$Full)
    $name = Split-Path $Full -Leaf
    $path = (Split-Path $Full -Parent)
    if (-not $path.EndsWith('\')) { $path += '\' }
    return @($path, $name)
}

