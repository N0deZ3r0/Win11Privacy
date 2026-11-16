
# =========================================================================== #
#  РЕЗЕРВНЫЕ КОПИИ: показать и вернуть
#  Копии .reg программа делала и раньше, но импортировать их приходилось
#  руками. Теперь круг замкнут: снимок -> откат по журналу -> импорт копии.
# =========================================================================== #
function Get-BackupList {
    # Первым — защищённое хранилище (W11P-005): копия оттуда и копия той же
    # папки на рабочем столе — одна копия, показывается защищённая
    $roots = @(Get-BackupStoreDir)
    if ($BackupRoot) { $roots += $BackupRoot }
    $roots += [Environment]::GetFolderPath('Desktop')
    $roots += $script:DataDir
    $seen = @{}
    $names = @{}
    $list = @()
    foreach ($root in $roots) {
        if (-not $root -or $seen.ContainsKey($root) -or -not (Test-Path -LiteralPath $root)) { continue }
        $seen[$root] = $true
        foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -Filter 'Win11Privacy-Backup-*' -ErrorAction SilentlyContinue)) {
            if ($names.ContainsKey($dir.Name)) { continue }
            $files = @(Get-ChildItem -LiteralPath $dir.FullName -File -Filter '*.reg' -ErrorAction SilentlyContinue)
            if ($files.Count -eq 0) { continue }
            $names[$dir.Name] = $true
            $size = 0
            foreach ($f in $files) { $size += $f.Length }
            $list += @{ path = $dir.FullName; name = $dir.Name
                        when = $dir.CreationTime.ToString('yyyy-MM-dd HH:mm')
                        branches = $files.Count; kb = [math]::Round($size / 1KB, 1)
                        signed = (Test-Path -LiteralPath (Join-Path $dir.FullName 'backup-sig.json'))
                        protected = ($root -eq (Get-BackupStoreDir)) }
        }
    }
    return @($list | Sort-Object { $_.when } -Descending)
}

# Копии, сделанные этой версией и новее, подписаны списком версии 2. Список
# версии 1 для такой копии — признак подмены (понижение формата, чтобы
# убрать из копии файл вместе со строкой списка): имя папки с датой входит в
# подпись каждого файла, и подделать его нельзя.
$script:BackupV2Since = '20261115'
function Test-BackupV1Allowed {
    param([string]$Leaf)
    if (Test-Path -LiteralPath (Join-Path (Get-BackupStoreDir) $Leaf)) { return $false }
    $m = [regex]::Match($Leaf, '^Win11Privacy-Backup-(\d{8})-\d{6}')
    if (-not $m.Success) { return $false }
    return ($m.Groups[1].Value -lt $script:BackupV2Since)
}

# --------------------------------------------------------------------------- #
#  Возврат из резервной копии (W11P-001). Папку копии на рабочем столе может
#  переписать любая программа пользователя, а импорт идёт с правами
#  администратора. Порядок:
#    1. список подписей (backup-sig.json) разбирается строгим разбором — без
#       повторов полей, только ожидаемые поля и имена файлов; у версии 2
#       сверяется подпись самого списка и имя папки;
#    2. в папке должны быть ровно файлы из списка: лишний .reg, ссылка или
#       недостающий файл — копия не импортируется вовсе;
#    3. каждый файл читается один раз в память, подпись сверяется на этих
#       байтах, проверяется содержимое (целая выгрузка reg.exe, ветка из тех,
#       что выгружает программа, без удалений и разделов вне ветки), и эти же
#       байты пишутся в рабочую папку внутри защищённого корня;
#    4. только если проверены все файлы — импорт. Перед импортом каждого файла
#       он открывается без права записи для других, подпись сверяется ещё раз,
#       и reg.exe читает файл, пока он открыт: проверенные байты — ровно те,
#       что импортируются.
#  Любая несостыковка — отказ целиком, а не «всё, кроме подозрительного»:
#  частично подменённая копия не возвращает в реестр ничего.
# --------------------------------------------------------------------------- #
function Read-BackupManifest {
    param([string]$Dir)
    $mf = Join-Path $Dir $script:BackupManifestName
    $item = Get-Item -LiteralPath $mf -Force -ErrorAction SilentlyContinue
    if ($null -eq $item -or $item.PSIsContainer) { throw 'копия не подписана (её сделала прежняя версия или подпись удалена) -- программа её не импортирует; при необходимости откройте нужный .reg вручную' }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'список подписей копии -- ссылка' }
    if ($item.Length -gt 1MB) { throw 'список подписей копии слишком большой' }
    $bytes = [IO.File]::ReadAllBytes($mf)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $bytes = [byte[]]($bytes[3..($bytes.Length - 1)]) }
    foreach ($b in $bytes) {
        if (($b -gt 0x7E) -or (($b -lt 0x20) -and ($b -ne 0x09) -and ($b -ne 0x0A) -and ($b -ne 0x0D))) { throw 'список подписей копии повреждён' }
    }
    try { $m = ConvertFrom-EngineRequest ([Text.Encoding]::ASCII.GetString($bytes)) }
    catch { throw ('список подписей копии не читается: ' + $_.Exception.Message) }
    foreach ($k in @($m.Keys)) { if (@('version', 'files', 'folder', 'sig') -cnotcontains $k) { throw ('в списке подписей лишнее поле: ' + $k) } }
    $ver = $m['version']
    if ($ver -isnot [int] -or ($ver -ne 1 -and $ver -ne 2)) { throw 'неизвестная версия списка подписей' }
    if ($m['files'] -isnot [hashtable] -or $m['files'].Count -eq 0) { throw 'в списке подписей нет файлов' }
    $files = @{}
    foreach ($n in @($m['files'].Keys)) {
        $s = $m['files'][$n]
        if ([string]$n -cnotmatch $script:BackupFileRx) { throw ('недопустимое имя файла в списке подписей: ' + $n) }
        if ($s -isnot [string] -or $s -cnotmatch '^[0-9a-f]{64}$') { throw ('недопустимая подпись в списке: ' + $n) }
        $files[[string]$n] = $s
    }
    $leaf = Split-Path $Dir -Leaf
    if ($ver -eq 2) {
        if ($m['folder'] -isnot [string] -or $m['folder'] -ine $leaf) { throw 'список подписей от другой папки копии' }
        if ($m['sig'] -isnot [string] -or $m['sig'] -cne (Get-BackupManifestSig $leaf $files)) { throw 'подпись списка файлов не сходится -- список изменён' }
    } elseif ($m.ContainsKey('folder') -or $m.ContainsKey('sig')) { throw 'у списка версии 1 не бывает этих полей' }
    elseif (-not (Test-BackupV1Allowed $leaf)) { throw 'список подписей прежнего вида у копии, сделанной этой версией программы, -- подмена' }
    return @{ version = $ver; files = $files }
}

# Ветки, которые программа выгружает в копии (из всех модулей), в виде
# заголовков .reg: только их и возвращает импорт
function Get-BackupAllowedBranches {
    $set = @{}
    foreach ($d in $script:Defs) {
        if ($script:RegTypes -notcontains $d.T) { continue }
        $full = ([string]$d.P -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKCU:\\', 'HKEY_CURRENT_USER\').TrimEnd('\')
        $set[$full.ToLowerInvariant()] = $true
    }
    return $set
}

# Содержимое .reg перед импортом: целая выгрузка reg.exe (UTF-16 с меткой,
# заголовок, законченная последняя запись), первый раздел — ветка из тех, что
# выгружает программа, остальные разделы — внутри неё, удалений («[-…]») нет.
# Пустая строка — годится, иначе — почему нет.
function Test-RegImportContent {
    param([byte[]]$Bytes, [hashtable]$Allowed)
    if ($Bytes.Length -lt 4 -or $Bytes[0] -ne 0xFF -or $Bytes[1] -ne 0xFE -or ($Bytes.Length % 2) -ne 0) { return 'файл не в том виде, в каком его пишет reg.exe (UTF-16)' }
    $t = [Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2)
    if (-not $t.StartsWith("Windows Registry Editor Version 5.00`r`n`r`n[", [StringComparison]::Ordinal)) { return 'в начале файла нет заголовка выгрузки' }
    if (-not $t.EndsWith("`r`n`r`n")) { return 'файл оборван: последняя запись не закончена' }
    $branch = $null
    foreach ($line in $t.Split([string[]]@("`r`n"), [StringSplitOptions]::None)) {
        if (-not $line.StartsWith('[')) { continue }
        if (-not $line.EndsWith(']')) { return 'непонятная строка раздела' }
        $key = $line.Substring(1, $line.Length - 2)
        if ($key.StartsWith('-')) { return 'в копии есть удаление раздела' }
        $low = $key.ToLowerInvariant()
        if ($null -eq $branch) {
            if (-not $Allowed.ContainsKey($low)) { return ('ветка не из тех, что выгружает программа: ' + $key) }
            $branch = $low
        } elseif ($low -ne $branch -and -not $low.StartsWith($branch + '\')) { return ('раздел вне выгруженной ветки: ' + $key) }
    }
    if ($null -eq $branch) { return 'в файле нет ни одного раздела' }
    return ''
}

# --------------------------------------------------------------------------- #
#  Сверка после импорта (T-3). reg.exe import неделим только на словах: он
#  пишет значения по одному, и код 0 ещё не значит, что в реестре теперь то,
#  что в копии (значение мог тут же переписать кто-то другой, часть могла не
#  записаться). Поэтому после импорта ветка выгружается заново тем же
#  reg.exe и сравнивается с файлом копии: каждый раздел копии есть, каждое
#  значение — с теми же данными и того же вида (текст значения у reg.exe
#  включает вид: dword:, hex(2): …). Значения, которых в копии не было,
#  остаются — reg.exe import ничего не удаляет, и это не ошибка сверки.
# --------------------------------------------------------------------------- #
# Выгрузка reg.exe (текст) → @{ раздел (строчными) → @{ имя значения
# (строчными) → данные } }. Строки, продолженные «\», склеиваются; имя
# значения — в кавычках с «\"» и «\\» внутри, «@» — значение по умолчанию.
# Строка, которая не начинается ни с «[», ни с «"», ни с «@», — продолжение
# прежнего значения (перевод строки внутри строкового значения): так её
# прочитают обе стороны сверки одинаково.
function ConvertFrom-RegExportText {
    param([string]$Text)
    $map = @{}
    $cur = $null; $name = $null; $data = $null; $cont = $false
    $flush = { if ($null -ne $cur -and $null -ne $name) { $map[$cur][$name] = $data } }
    foreach ($line in $Text.Split([string[]]@("`r`n"), [StringSplitOptions]::None)) {
        if ($cont) {
            $piece = $line.TrimStart()
            if ($piece.EndsWith('\')) { $data += $piece.Substring(0, $piece.Length - 1) } else { $data += $piece; $cont = $false }
            continue
        }
        if ($line.StartsWith('[') -and $line.EndsWith(']')) {
            & $flush; $name = $null
            $cur = $line.Substring(1, $line.Length - 2).ToLowerInvariant()
            if (-not $map.ContainsKey($cur)) { $map[$cur] = @{} }
            continue
        }
        if ($null -eq $cur -or $line -eq '') { continue }
        $rest = $null
        if ($line.StartsWith('@=')) { & $flush; $name = '@'; $rest = $line.Substring(2) }
        elseif ($line.StartsWith('"')) {
            $sb = New-Object System.Text.StringBuilder
            $i = 1; $closed = $false
            while ($i -lt $line.Length) {
                $c = $line[$i]
                if ($c -eq '\' -and $i + 1 -lt $line.Length) { $null = $sb.Append($line[$i + 1]); $i += 2; continue }
                if ($c -eq '"') { $closed = $true; break }
                $null = $sb.Append($c); $i++
            }
            if ($closed -and $i + 1 -lt $line.Length -and $line[$i + 1] -eq '=') {
                & $flush; $name = $sb.ToString().ToLowerInvariant(); $rest = $line.Substring($i + 2)
            }
        }
        if ($null -eq $rest) {
            # продолжение строкового значения с переводом строки внутри
            if ($null -ne $name) { $data += "`n" + $line }
            continue
        }
        if ($rest.EndsWith('\')) { $data = $rest.Substring(0, $rest.Length - 1); $cont = $true } else { $data = $rest }
    }
    & $flush
    return $map
}

# Первый раздел файла копии — сама ветка, как её записал reg.exe
function Get-RegFileBranch {
    param([byte[]]$Bytes)
    $t = [Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2)
    foreach ($line in $t.Split([string[]]@("`r`n"), [StringSplitOptions]::None)) {
        if ($line.StartsWith('[') -and $line.EndsWith(']')) { return $line.Substring(1, $line.Length - 2) }
    }
    return ''
}

# Ветка копии (HKEY_LOCAL_MACHINE\…) → путь PowerShell (HKLM:\…) для New-RegBackup
function ConvertTo-PsRegPath {
    param([string]$Branch)
    if ($Branch -match '^HKEY_LOCAL_MACHINE\\(.+)$') { return ('HKLM:\' + $Matches[1]) }
    if ($Branch -match '^HKEY_CURRENT_USER\\(.+)$') { return ('HKCU:\' + $Matches[1]) }
    return ''
}

# После импорта: ветка выгружается заново (в ту же защищённую рабочую
# папку) и сравнивается с копией. state: restored — всё из копии на месте;
# differs — чего-то нет или данные другие (missing — сколько); unverified —
# выгрузить ветку заново не вышло, сверить не с чем.
function Test-RegImported {
    param([byte[]]$Bytes, [string]$Work, [string]$Name)
    $out = @{ state = 'unverified'; missing = 0; error = '' }
    try {
        $branch = Get-RegFileBranch $Bytes
        if (-not $branch) { $out.error = 'в копии нет раздела'; return $out }
        $native = ($branch -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM\' -replace '^HKEY_CURRENT_USER\\', 'HKCU\')
        $file = Join-Path $Work ('verify-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '-' + $Name)
        $why = Export-RegKey $native $file
        if ($why) { $out.error = ("ветка не выгрузилась для сверки: {0}" -f $why); return $out }
        $after = [IO.File]::ReadAllBytes($file)
        try { [IO.File]::Delete($file) } catch { }
        $want = ConvertFrom-RegExportText ([Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2))
        $now = ConvertFrom-RegExportText ([Text.Encoding]::Unicode.GetString($after, 2, $after.Length - 2))
        $miss = 0
        foreach ($k in @($want.Keys)) {
            if (-not $now.ContainsKey($k)) { $miss += [Math]::Max(1, $want[$k].Count); continue }
            foreach ($v in @($want[$k].Keys)) {
                if (-not $now[$k].ContainsKey($v) -or [string]$now[$k][$v] -cne [string]$want[$k][$v]) { $miss++ }
            }
        }
        $out.missing = $miss
        $out.state = $(if ($miss -eq 0) { 'restored' } else { 'differs' })
        return $out
    } catch { $out.state = 'unverified'; $out.error = "$($_.Exception.Message)"; return $out }
}

# --------------------------------------------------------------------------- #
#  Восстановление из копии по шагам (T-3). Сделать импорт неделимым нельзя
#  (у reg.exe import нет транзакции, и изображать её программа не будет),
#  поэтому восстановление ведёт подписанную запись о своём ходе
#  (Write-OpRecord 'restore') и держит замок операции (Enter-OpLock):
#    Prepared          — копия проверена, состояние до восстановления
#                        сохранено (снимок — обычная подписанная копия в
#                        хранилище), запись на диске; реестр ещё не тронут;
#    InProgress        — идёт импорт: у каждого файла своя стадия (pending,
#                        importing — запись легла ДО запуска reg.exe,
#                        restored — импортирован и сверен, failed, unverified);
#    Restored          — все файлы импортированы и сверены: запись убирается;
#    PartiallyRestored — запуск дожил до конца, но вернулось не всё: запись
#                        остаётся, следующий запуск о ней скажет;
#    Failed            — не импортировано ничего, реестр не тронут: записи нет;
#    RecoveryRequired  — так её видит следующий запуск, если она осталась в
#                        InProgress, а замок свободен (процесс умер посередине),
#                        или в PartiallyRestored (Get-RestoreRecovery).
#  Сам по себе ничего не повторяется: ни следующий запуск, ни страж не
#  доделывают импорт без человека. Довести — снова выбрать ту же копию (её
#  импорт можно повторять: те же значения запишутся так же) или вернуть
#  снимок «до восстановления». Повтор после обрыва снимок не переснимает:
#  остаётся самый первый — состояние до первого незаконченного восстановления.
# --------------------------------------------------------------------------- #
$script:RestoreOp = 'restore'

# Незаконченное восстановление глазами окна и следующего запуска. state:
# none; InProgress — идёт сейчас (замок занят); RecoveryRequired — оборвалось
# посередине или вернулось не всё (recoveryRequired = $true); Interrupted —
# оборвалось до первого импорта (реестр не тронут); Untrusted / Unreadable —
# запись есть, но верить ей нельзя или она не читается.
function Get-RestoreRecovery {
    $r = Read-OpRecord $script:RestoreOp
    $o = [ordered]@{ state = 'none'; recoveryRequired = $false; folder = ''; path = ''; snapshot = ''; stage = ''; restored = 0; files = 0; started = ''; error = "$($r.error)" }
    if ($r.state -eq 'none') { return $o }
    if ($r.state -eq 'unreadable') { $o.state = 'Unreadable'; $o.recoveryRequired = $true; return $o }
    if ($r.state -eq 'untrusted') { $o.state = 'Untrusted'; $o.recoveryRequired = $true; return $o }
    $d = $r.data
    $o.folder = "$($d.folder)"; $o.path = "$($d.path)"; $o.snapshot = "$($d.snapshot)"; $o.stage = "$($d.state)"; $o.started = "$($d.started)"
    $o.files = @($d.files).Count
    $o.restored = @(@($d.files) | Where-Object { "$($_.state)" -eq 'restored' }).Count
    # закончено и сверено, только запись не убралась — незаконченного нет
    if ("$($d.state)" -eq 'Restored') { $o.state = 'none'; return $o }
    $running = Test-OpRunning $script:RestoreOp
    if ($running -eq $true) { $o.state = 'InProgress'; return $o }
    if ("$($d.state)" -eq 'Prepared') { $o.state = 'Interrupted'; return $o }
    $o.state = 'RecoveryRequired'; $o.recoveryRequired = $true
    return $o
}

function Restore-BackupFolder {
    param([string]$Path)
    $res = @{ restored = 0; failed = 0; refused = 0; error = ''; state = 'Failed'; snapshot = ''; unverified = 0; imported = 0; resumed = $false; files = @() }
    $work = $null
    $lock = $null
    $rec = $null
    $recWritten = $false
    try {
        $dirItem = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $dirItem.PSIsContainer -or ($dirItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'папка копии -- ссылка или не папка' }
        $folder = $dirItem.Name
        $man = Read-BackupManifest $dirItem.FullName

        # В папке — ровно файлы из подписанного списка
        $present = @{}
        foreach ($f in @(Get-ChildItem -LiteralPath $dirItem.FullName -Force -ErrorAction Stop)) {
            if ($f.Name -ieq $script:BackupManifestName -or $f.Name -notlike '*.reg') { continue }
            if ($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Write-Log ("   [!] {0} -- ссылка или папка вместо файла копии" -f $f.Name); $res.refused++; continue
            }
            if (-not $man.files.ContainsKey($f.Name)) {
                Write-Log ("   [!] {0} -- этого файла в подписанной копии не было" -f $f.Name); $res.refused++; continue
            }
            $present[$f.Name] = $f
        }
        foreach ($n in @($man.files.Keys)) {
            if (-not $present.ContainsKey($n)) { Write-Log ("   [!] {0} -- файла из подписанного списка нет в папке" -f $n); $res.refused++ }
        }
        if ($res.refused -gt 0) { throw 'копия изменена после создания -- не импортируется ничего' }

        # Проверка и перенос в защищённую рабочую папку — всех файлов до импорта
        Remove-StaleWorkDirs 'restore-'
        $work = New-SafeWorkDir 'restore-'
        $allowed = Get-BackupAllowedBranches
        $staged = New-Object System.Collections.Generic.List[object]
        foreach ($n in @($present.Keys | Sort-Object)) {
            $src = $present[$n]
            if ($src.Length -gt 64MB) { Write-Log ("   [!] {0} -- слишком большой файл" -f $n); $res.refused++; continue }
            $bytes = [IO.File]::ReadAllBytes($src.FullName)
            if ((Get-BackupBytesSig $bytes $folder $n) -cne $man.files[$n]) { Write-Log ("   [!] {0} -- файл изменён после создания копии" -f $n); $res.refused++; continue }
            $why = Test-RegImportContent $bytes $allowed
            if ($why) { Write-Log ("   [!] {0} -- {1}" -f $n, $why); $res.refused++; continue }
            $dst = Join-Path $work $n
            $fs = [IO.File]::Open($dst, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush($true) } finally { $fs.Dispose() }
            $staged.Add(@{ name = $n; path = $dst; sig = $man.files[$n]; branch = (Get-RegFileBranch $bytes) })
        }
        if ($res.refused -gt 0) { throw 'в копии есть изменённые или чужие файлы -- не импортируется ничего' }

        # --- Отсюда меняется реестр (T-3): сначала замок и запись о ходе ---
        $lock = Enter-OpLock $script:RestoreOp
        if ($null -eq $lock) { throw 'идёт другое восстановление из копии -- дождитесь его конца; ничего не импортировано' }
        $prev = Read-OpRecord $script:RestoreOp
        if ($prev.state -eq 'unreadable') { throw ("запись о прошлом восстановлении сейчас не читается ({0}) -- ничего не импортировано, повторите позже" -f $prev.error) }
        if ($prev.state -eq 'untrusted') {
            $aside = Set-OpRecordAside $script:RestoreOp
            Write-Log ("   [!] запись о прошлом восстановлении недоверенная ({0}) -- по ней ничего не делается, она отложена как {1}" -f $prev.error, $aside)
        }
        $open = $null
        if ($prev.state -eq 'valid' -and "$($prev.data.state)" -in @('InProgress', 'PartiallyRestored')) { $open = $prev.data }
        if ($open) {
            $res.resumed = $true
            $res.snapshot = "$($open.snapshot)"
            Write-Log ("   [!] прошлое восстановление из копии не закончено ({0}: {1}, вернулось файлов {2} из {3}) -- реестр мог остаться восстановленным частично" -f "$($open.folder)", "$($open.state)",
                       @(@($open.files) | Where-Object { "$($_.state)" -eq 'restored' }).Count, @($open.files).Count)
            if ($res.snapshot) { Write-Log ("   [i] снимок «до восстановления» остаётся прежним (состояние до первой попытки): {0}" -f $res.snapshot) }
        } else {
            # Состояние до восстановления — обычной подписанной копией тех же
            # веток в хранилище (New-RegBackup). Не сохранилось — не
            # импортируем ничего: вернуться потом было бы не к чему.
            $keys = @($staged | ForEach-Object { ConvertTo-PsRegPath "$($_.branch)" } | Where-Object { $_ } | Select-Object -Unique)
            $existing = @($keys | Where-Object { Test-Path -LiteralPath $_ })
            if ($existing.Count -gt 0) {
                $sn = New-RegBackup $existing
                if ($sn.error -or -not $sn.dir -or [int]$sn.saved -lt $existing.Count) {
                    $why = $(if ($sn.error) { $sn.error } elseif (@($sn.missed).Count -gt 0) { @($sn.missed)[0] } else { 'выгрузилось не всё' })
                    throw ("состояние реестра до восстановления не сохранилось ({0}) -- ничего не импортировано: вернуться потом было бы не к чему" -f $why)
                }
                $res.snapshot = $sn.dir
                Write-Log ("   [+] состояние до восстановления сохранено: {0}" -f $sn.dir)
            } else { Write-Log '   [i] веток этой копии сейчас в реестре нет -- сохранять до восстановления нечего' }
        }
        $rec = [ordered]@{
            state = 'Prepared'; folder = $folder; path = $dirItem.FullName; snapshot = $res.snapshot
            started = (Get-Date).ToString('s'); attempt = $(if ($open) { [int]"0$($open.attempt)" + 1 } else { 1 })
            previous = $(if ($open -and "$($open.path)" -ine $dirItem.FullName) { "$($open.path)" } else { '' })
            files = @(foreach ($s in $staged) { [ordered]@{ name = "$($s.name)"; branch = "$($s.branch)"; state = 'pending' } })
        }
        Write-OpRecord $script:RestoreOp $rec
        $recWritten = $true

        $i = -1
        foreach ($s in $staged) {
            $i++
            # стадия файла — на диск ДО запуска reg.exe: оборвись импорт, запись
            # скажет, какой файл мог остаться записанным наполовину
            $rec.files[$i].state = 'importing'; $rec.state = 'InProgress'
            Write-OpRecord $script:RestoreOp $rec
            # Файл открыт без права записи для других, пока reg.exe его читает:
            # подпись, сверенная здесь, — подпись импортируемых байтов
            $fs = [IO.File]::Open($s.path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                $ms = New-Object System.IO.MemoryStream
                $fs.CopyTo($ms)
                $b = $ms.ToArray()
                if ((Get-BackupBytesSig $b $folder $s.name) -cne $s.sig) {
                    Write-Log ("   [!] {0} -- копия в рабочей папке не сходится с подписью" -f $s.name); $res.refused++
                    $rec.files[$i].state = 'refused'
                } else {
                    $r = Invoke-RegExe ('import "{0}"' -f $s.path)
                    $res.imported++
                    # «reg.exe закончил с кодом 0» — ещё не «в реестре то, что в копии»
                    $v = Test-RegImported $b $work $s.name
                    if ($r.code -eq 0 -and $v.state -eq 'restored') { Write-Log ("   [+] вернули и сверили: {0}" -f $s.name); $res.restored++; $rec.files[$i].state = 'restored' }
                    elseif ($r.code -ne 0) { Write-Log ("   [!] не удалось: {0} (код {1}: {2})" -f $s.name, $r.code, $r.error); $res.failed++; $rec.files[$i].state = 'failed' }
                    elseif ($v.state -eq 'unverified') { Write-Log ("   [!] {0} импортирован, но сверить его не удалось: {1}" -f $s.name, $v.error); $res.failed++; $res.unverified++; $rec.files[$i].state = 'unverified' }
                    else { Write-Log ("   [!] {0} импортирован, но в реестре не то, что в копии: значений не на месте {1}" -f $s.name, $v.missing); $res.failed++; $rec.files[$i].state = 'failed' }
                }
            } finally { $fs.Dispose() }
            Write-OpRecord $script:RestoreOp $rec
        }
        if ($res.restored -eq $staged.Count -and $res.failed -eq 0 -and $res.refused -eq 0) {
            $rec.state = 'Restored'
            Write-OpRecord $script:RestoreOp $rec
            if (-not (Remove-OpRecord $script:RestoreOp)) { Write-Log '   [i] запись о ходе восстановления не убралась (в ней итог «восстановлено»)' }
            $res.state = 'Restored'
        } elseif ($res.imported -eq 0 -and -not $res.resumed) {
            # не импортировано ничего, реестр не тронут: незаконченного нет
            $null = Remove-OpRecord $script:RestoreOp
            $res.state = 'Failed'
        } else {
            $rec.state = 'PartiallyRestored'
            Write-OpRecord $script:RestoreOp $rec
            $res.state = 'PartiallyRestored'
        }
        $recWritten = $false
    } catch {
        $res.error = $_.Exception.Message
        # Запуск жив, но оборвался посередине: итог — по тому, что успело
        # случиться. Не записалось — на диске остаётся InProgress, и следующий
        # запуск увидит RecoveryRequired.
        $partial = ($res.imported -gt 0 -or $res.resumed)
        $res.state = $(if ($partial) { 'PartiallyRestored' } else { 'Failed' })
        if ($recWritten -and $null -ne $rec) {
            try {
                if ($partial) { $rec.state = 'PartiallyRestored'; Write-OpRecord $script:RestoreOp $rec }
                else { $null = Remove-OpRecord $script:RestoreOp }
            } catch { }
        }
    }
    finally {
        if ($work -and (Test-Path -LiteralPath $work)) {
            $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
            Remove-TreeNoFollow $work $st
        }
        if ($null -ne $lock) { $lock.Dispose() }
    }
    if ($null -ne $rec) { $res.files = @(@($rec.files) | ForEach-Object { @{ name = "$($_.name)"; state = "$($_.state)" } }) }
    return $res
}

if ($ListBackups) {
    $bkList = @(Get-BackupList)
    # незаконченное восстановление — окно скажет о нём над списком копий
    $rcv = $null
    try { $rcv = Get-RestoreRecovery } catch { $rcv = [ordered]@{ state = 'Unreadable'; recoveryRequired = $true; error = "$($_.Exception.Message)" } }
    Emit-Json @{ items = $bkList; count = $bkList.Count; recovery = $rcv }
    exit 0
}

if ($RestoreBackup) {
    if (-not (Test-Admin)) { Emit-Json @{ error = 'нужны права администратора' }; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Восстановление из резервной копии'
    if (-not $BackupPath -or -not (Test-Path -LiteralPath $BackupPath)) {
        Write-Log '   [!] папка копии не найдена'
        Emit-Json @{ error = 'папка копии не найдена' }; Write-Log '###DONE###'; exit 1
    }
    $regFiles = @(Get-ChildItem -LiteralPath $BackupPath -File -Filter '*.reg' -ErrorAction SilentlyContinue)
    if ($regFiles.Count -eq 0) {
        Write-Log '   [!] в этой папке нет файлов .reg'
        Emit-Json @{ error = 'в папке нет файлов .reg' }; Write-Log '###DONE###'; exit 1
    }
    Write-Log ("   найдено файлов: {0}" -f $regFiles.Count)
    if ($DryRun) { foreach ($f in $regFiles) { Write-Log ("   [тест] {0}" -f $f.Name) }; Write-Log '###DONE###'; exit 0 }
    $rb = Restore-BackupFolder $BackupPath
    if ($rb.error) { Write-Log ("   [!] {0}" -f $rb.error); $script:Failures++ }
    $script:Changes += $rb.restored; $script:Failures += $rb.failed + $rb.refused
    Write-Log ("   возвращено и сверено веток: {0}" -f $rb.restored)
    if ($rb.failed -gt 0) { Write-Log ("   не удалось вернуть: {0}" -f $rb.failed) }
    if ($rb.refused -gt 0) { Write-Log ("   не импортировано из-за подписи: {0}" -f $rb.refused) }
    switch ($rb.state) {
        'Restored' { Write-Log '   Значения вернулись к состоянию на момент копии (сверено). Перезагрузите компьютер.' }
        'PartiallyRestored' {
            Write-Log '   [!] Восстановление не закончено: реестр восстановлен частично.'
            Write-Log '       Довести его -- снова выбрать эту же копию (повторный импорт пишет те же значения).'
            if ($rb.snapshot) { Write-Log ("       Вернуть как было до восстановления -- выбрать копию {0}" -f (Split-Path $rb.snapshot -Leaf)) }
        }
        default { Write-Log '   Реестр не изменён.' }
    }
    Emit-Json @{ restored = $rb.restored; failed = $rb.failed; refused = $rb.refused; error = $rb.error; path = $BackupPath
                 state = $rb.state; snapshot = $rb.snapshot; unverified = $rb.unverified; imported = $rb.imported; resumed = $rb.resumed; files = @($rb.files) }
    Write-Log '###DONE###'
    # 0 — всё импортировано и сверено (Restored); 2 — реестр восстановлен
    # частично (PartiallyRestored: что-то импортировано, но не всё вернулось
    # или не сверилось); 1 — не импортировано ничего, реестр не тронут
    # (отказ или ошибка до импорта). Раньше «вернулось не всё» давало 0, а
    # «reg.exe закончил с кодом 0» считалось «вернулось», без сверки.
    exit $(if ($rb.state -eq 'Restored') { 0 } elseif ($rb.state -eq 'PartiallyRestored') { 2 } else { 1 })
}

if ($ListStartup) {
    $stList = @(Get-StartupList)
    $stOn   = @($stList | Where-Object { $_.enabled })
    Emit-Json @{ items = $stList; total = $stList.Count; on = $stOn.Count
                 advise = @($stOn | Where-Object { $_.advise }).Count
                 time = (Get-Date).ToString('yyyy-MM-dd HH:mm') }
    exit 0
}

if ($StartupSet) {
    $wantOn = ($StartupValue -eq 'On')
    Write-Section $(if ($wantOn) { 'Автозагрузка: вернуть записи' } else { 'Автозагрузка: отключить записи' })
    if ($StartupItems.Count -eq 0) { Write-Log '   [-] ничего не выбрано'; Emit-Json @{ changed = 0 }; Write-Log '###DONE###'; exit 0 }
    $known = @{}
    foreach ($it in @(Get-StartupList)) { $known[[string]$it.id] = $it }
    $done = 0
    foreach ($id in $StartupItems) {
        $raw = ConvertFrom-StartupId $id
        if (-not $raw) { Write-Log ("   [!] непонятная запись: {0}" -f $id); $script:Failures++; continue }
        $it = $known[[string]$id]
        $label = $(if ($it) { [string]$it.name } else { $raw })
        if ($it -and ([bool]$it.enabled) -eq $wantOn) { Write-Log ("   [в] {0} -- уже так" -f $label); $script:Already++; continue }
        if ($DryRun) { Write-Log ("   [тест] {0}" -f $label); continue }
        # журнал раньше изменения: «как было» — на диск, потом переключение
        if (-not (Test-CanModify $label)) { break }
        $sj = @{ kind = 'startup'; id = $raw; name = $label
                 old = $(if ($wantOn) { 'Off' } else { 'On' }); newValue = $(if ($wantOn) { 'On' } else { 'Off' }) }
        if (-not (Write-AheadEntry $sj)) { Write-Log ("   [!] {0} -- не меняется: «как было» не легло в журнал отката" -f $label); $script:Failures++; break }
        $r = Set-StartupState $raw $wantOn
        if ($r.ok) {
            Write-Log ("   [+] {0} -- {1}" -f $label, $(if ($wantOn) { 'снова запускается' } else { 'больше не запускается' }))
            $done++; $script:Changes++
        } else {
            Undo-AheadEntry $sj
            Write-Log ("   [!] {0} -- {1}" -f $label, $r.error); $script:Failures++
        }
    }
    Save-JournalEntries
    Write-Log ("   изменено записей: {0}" -f $done)
    Emit-Json @{ changed = $done; failures = $script:Failures }
    Write-Log '###DONE###'
    # 2 — дошёл до конца, но не всё прошло (окно пишет «Готово, с ошибками»); раньше всегда 0
    exit $(if ($script:Failures -gt 0) { 2 } else { 0 })
}
