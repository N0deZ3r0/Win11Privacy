
# =========================================================================== #
#  РЕЗЕРВНЫЕ КОПИИ: показать и вернуть
#  Копии .reg программа делала и раньше, но импортировать их приходилось
#  руками. Теперь круг замкнут: снимок -> откат по журналу -> импорт копии.
# =========================================================================== #
function Get-BackupList {
    $roots = @()
    if ($BackupRoot) { $roots += $BackupRoot }
    $roots += [Environment]::GetFolderPath('Desktop')
    $roots += $script:DataDir
    $seen = @{}
    $list = @()
    foreach ($root in $roots) {
        if (-not $root -or $seen.ContainsKey($root) -or -not (Test-Path -LiteralPath $root)) { continue }
        $seen[$root] = $true
        foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -Filter 'Win11Privacy-Backup-*' -ErrorAction SilentlyContinue)) {
            $files = @(Get-ChildItem -LiteralPath $dir.FullName -File -Filter '*.reg' -ErrorAction SilentlyContinue)
            if ($files.Count -eq 0) { continue }
            $size = 0
            foreach ($f in $files) { $size += $f.Length }
            $list += @{ path = $dir.FullName; name = $dir.Name
                        when = $dir.CreationTime.ToString('yyyy-MM-dd HH:mm')
                        branches = $files.Count; kb = [math]::Round($size / 1KB, 1)
                        signed = (Test-Path -LiteralPath (Join-Path $dir.FullName 'backup-sig.json')) }
        }
    }
    return @($list | Sort-Object { $_.when } -Descending)
}

# Возврат из резервной копии. Папку копии на рабочем столе может переписать
# любая программа пользователя, а импорт идёт с правами администратора:
# раньше дописанный в .reg ключ (путь к программе службы, автозагрузка всех
# пользователей) выполнился бы с этими правами. Теперь каждый файл подписан
# при создании копии (backup-sig.json, тем же ключом, что и журнал отката).
# Файл копируется в защищённую папку, подпись сверяется на копии, и
# импортируется копия: подменить файл между сверкой и импортом нельзя.
# Неподписанный или изменённый файл не импортируется.
function Restore-BackupFolder {
    param([string]$Path)
    $res = @{ restored = 0; failed = 0; refused = 0; error = '' }
    $sigs = $null
    try { $sigs = (Get-Content -LiteralPath (Join-Path $Path 'backup-sig.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json).files } catch { }
    if ($null -eq $sigs) {
        $res.error = 'копия не подписана (её сделала прежняя версия или подпись удалена) -- программа её не импортирует; при необходимости откройте нужный .reg вручную'
        return $res
    }
    if (-not (Assert-SafeRoot)) { $res.error = 'папка ProgramData\Win11Privacy не защищена -- проверять копию негде'; return $res }
    $folder = Split-Path $Path -Leaf
    $work = Join-Path $script:SafeRoot ('restore-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        New-Item -ItemType Directory -Path $work -Force -ErrorAction Stop | Out-Null
        foreach ($f in @(Get-ChildItem -LiteralPath $Path -File -Filter '*.reg' -ErrorAction Stop)) {
            $p = $sigs.PSObject.Properties[$f.Name]
            $want = $(if ($p) { "$($p.Value)" } else { '' })
            if (-not $want) { Write-Log ("   [!] {0} -- этого файла в подписанной копии не было, не импортируется" -f $f.Name); $res.refused++; continue }
            $copy = Join-Path $work $f.Name
            Copy-Item -LiteralPath $f.FullName -Destination $copy -Force -ErrorAction Stop
            if ((Get-BackupFileSig $copy $folder $f.Name) -ne $want) {
                Write-Log ("   [!] {0} -- файл изменён после создания копии, не импортируется" -f $f.Name); $res.refused++; continue
            }
            $r = Invoke-RegExe ('import "{0}"' -f $copy)
            if ($r.code -eq 0) { Write-Log ("   [+] вернули: {0}" -f $f.Name); $res.restored++ }
            else { Write-Log ("   [!] не удалось: {0} (код {1}: {2})" -f $f.Name, $r.code, $r.error); $res.failed++ }
        }
    } catch { $res.error = $_.Exception.Message }
    finally { if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } }
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
    exit $(if ($rb.error -or ($rb.restored -eq 0 -and ($rb.failed + $rb.refused) -gt 0)) { 1 } else { 0 })
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
    exit 0
}
