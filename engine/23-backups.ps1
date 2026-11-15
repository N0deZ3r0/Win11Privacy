
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

function Restore-BackupFolder {
    param([string]$Path)
    $res = @{ restored = 0; failed = 0; refused = 0; error = '' }
    $work = $null
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
            $staged.Add(@{ name = $n; path = $dst; sig = $man.files[$n] })
        }
        if ($res.refused -gt 0) { throw 'в копии есть изменённые или чужие файлы -- не импортируется ничего' }

        foreach ($s in $staged) {
            # Файл открыт без права записи для других, пока reg.exe его читает:
            # подпись, сверенная здесь, — подпись импортируемых байтов
            $fs = [IO.File]::Open($s.path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                $ms = New-Object System.IO.MemoryStream
                $fs.CopyTo($ms)
                if ((Get-BackupBytesSig $ms.ToArray() $folder $s.name) -cne $s.sig) {
                    Write-Log ("   [!] {0} -- копия в рабочей папке не сходится с подписью" -f $s.name); $res.refused++; continue
                }
                $r = Invoke-RegExe ('import "{0}"' -f $s.path)
                if ($r.code -eq 0) { Write-Log ("   [+] вернули: {0}" -f $s.name); $res.restored++ }
                else { Write-Log ("   [!] не удалось: {0} (код {1}: {2})" -f $s.name, $r.code, $r.error); $res.failed++ }
            } finally { $fs.Dispose() }
        }
    } catch { $res.error = $_.Exception.Message }
    finally {
        if ($work -and (Test-Path -LiteralPath $work)) {
            $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
            Remove-TreeNoFollow $work $st
        }
    }
    return $res
}

if ($ListBackups) {
    $bkList = @(Get-BackupList)
    Emit-Json @{ items = $bkList; count = $bkList.Count }
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
    Write-Log ("   возвращено веток: {0}" -f $rb.restored)
    if ($rb.failed -gt 0) { Write-Log ("   не удалось вернуть: {0}" -f $rb.failed) }
    if ($rb.refused -gt 0) { Write-Log ("   не импортировано из-за подписи: {0}" -f $rb.refused) }
    if ($rb.restored -gt 0) { Write-Log '   Значения вернулись к состоянию на момент копии. Перезагрузите компьютер.' }
    Emit-Json @{ restored = $rb.restored; failed = $rb.failed; refused = $rb.refused; error = $rb.error; path = $BackupPath }
    Write-Log '###DONE###'
    # 1 — ничего не вернулось (отказ или ошибка); 2 — вернулось не всё
    # (reg.exe не принял часть файлов). Раньше второе давало 0, и окно
    # писало «Готово».
    exit $(if ($rb.error -or ($rb.restored -eq 0 -and ($rb.failed + $rb.refused) -gt 0)) { 1 } elseif (($rb.failed + $rb.refused) -gt 0) { 2 } else { 0 })
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
