# --------------------------------------------------------------------------- #
#  Что программа накопила о вас у себя. Для программы про приватность честно
#  показывать и свои файлы — и уметь их стереть.
# --------------------------------------------------------------------------- #
$script:DataFiles = @(
    @{ file = 'sensor-history.json'; title = 'История датчиков по дням: кто включал камеру, микрофон и геолокацию' },
    @{ file = 'sensor-apps.json';    title = 'Список программ, которым доступ к датчикам уже известен' },
    @{ file = 'startup-known.json';  title = 'Известные записи автозагрузки — по ним страж замечает новые' },
    @{ file = 'changes.json';        title = 'Журнал изменений: что программа поменяла и что было до неё' },
    @{ file = 'proof-before.json';   title = 'Снимок «до»: состояние системы перед первым применением' },
    @{ file = 'xray-last.json';      title = 'Последний результат рентгена телеметрии' },
    @{ file = 'xray-baseline.json';  title = 'Эталон рентгена: сколько событий уходило до настройки' },
    @{ file = 'profile.json';        title = 'Профиль стража: какие разделы он сторожит' },
    @{ file = 'guard-last.json';     title = 'Последняя проверка стража' },
    @{ file = 'guard.log';           title = 'Журнал работы стража' },
    @{ file = 'net-apps.json';       title = 'Программы, выходившие в сеть, — по ним слежение замечает новые' }
)

function Get-DataFiles {
    $out = @()
    $seen = @{}
    foreach ($d in $script:DataFiles) {
        $seen[$d.file] = $true
        $full = Join-Path $script:DataDir $d.file
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $fi = Get-Item -LiteralPath $full -ErrorAction SilentlyContinue
        if (-not $fi) { continue }
        $out += @{ file = $d.file; title = $d.title; kb = [math]::Round($fi.Length / 1KB, 1)
                   changed = $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }
    }
    # снимки состояния и всё прочее, что могло появиться рядом
    if (Test-Path -LiteralPath $script:DataDir) {
        foreach ($fi in @(Get-ChildItem -LiteralPath $script:DataDir -File -ErrorAction SilentlyContinue)) {
            if ($seen.ContainsKey($fi.Name)) { continue }
            if ($fi.Name -like 'engine*.ps1') { continue }   # это сам движок для стража, не данные
            if ($fi.Name -like 'journal.key*') { continue }  # ключ подписи журнала — не данные о человеке
            $out += @{ file = $fi.Name; title = 'Снимок состояния или служебный файл'
                       kb = [math]::Round($fi.Length / 1KB, 1)
                       changed = $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }
        }
    }
    return @($out | Sort-Object { -[double]$_.kb })
}

if ($DataInfo) {
    $dataList = @(Get-DataFiles)
    $sum = 0.0
    foreach ($d in $dataList) { $sum += [double]$d.kb }
    Emit-Json @{ items = $dataList; count = $dataList.Count; kb = [math]::Round($sum, 1)
                 folder = $script:DataDir }
    exit 0
}

if ($PurgeData) {
    Write-Section 'Удаление данных программы'
    $dataList = @(Get-DataFiles)
    if ($dataList.Count -eq 0) { Write-Log '   [-] программа ничего о вас не хранит'; Emit-Json @{ removed = 0 }; Write-Log '###DONE###'; exit 0 }
    $gone = 0
    foreach ($d in $dataList) {
        $full = Join-Path $script:DataDir $d.file
        if ($DryRun) { Write-Log ("   [тест] {0}" -f $d.file); continue }
        try { Remove-Item -LiteralPath $full -Force -ErrorAction Stop; Write-Log ("   [+] удалён: {0}" -f $d.file); $gone++ }
        catch { Write-Log ("   [!] не удалось удалить {0} -- {1}" -f $d.file, $_.Exception.Message); $script:Failures++ }
    }
    Write-Log ("   удалено файлов: {0}" -f $gone)
    Write-Log '   Журнал отката тоже стёрт — вернуть настройки «как было» программа больше не сможет.'
    Emit-Json @{ removed = $gone }
    Write-Log '###DONE###'
    exit 0
}

if ($RestoreAll) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Возврат настроек реестра по журналу'
    $r = Restore-Journal
    Emit-Json $r
    Write-Log '###DONE###'
    exit 0
}
