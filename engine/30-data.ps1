# --------------------------------------------------------------------------- #
#  Что программа накопила о вас у себя. Для программы про приватность честно
#  показывать и свои файлы — и уметь их стереть.
#
#  Данными программы считается только то, что она кладёт сама: имена ниже и
#  файлы по строгим образцам. Раньше сюда шло и всё прочее, что лежало в
#  папке, — и -PurgeData стёр бы любые чужие файлы, окажись папка данных не
#  той. Неизвестный файл не показывается и не удаляется.
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
    @{ file = 'net-apps.json';       title = 'Программы, выходившие в сеть, — по ним слежение замечает новые' },
    @{ file = 'xray-history.json';   title = 'История рентгена по дням: сколько событий уходило' },
    @{ file = 'blocked.json';        title = 'Настройки, которые Windows не дала применить' },
    @{ file = 'oem-disabled.json';   title = 'Компоненты производителя, отключённые прежней версией' },
    @{ file = 'watcher-last.txt';    title = 'Время последнего живого уведомления' },
    @{ file = 'journal-check.json';  title = 'Проба записи журнала, оставшаяся после обрыва' }
)
# Файлы с изменчивой частью имени: журнал, отложенный проверкой (метка
# времени — как у Read-JournalFile), и недописанная копия файла данных
# (Save-Json пишет рядом «имя.tmp»). Копия движка и ключ подписи — не данные
# о человеке и сюда не входят.
$script:DataFilePatterns = @(
    @{ rx = '^changes\.(broken|unverifiable|unverified)-\d{8}-\d{6}\.json$'
       title = 'Отложенный журнал отката: повреждён или не прошёл проверку подписи' },
    @{ rx = ('^(' + (@($script:DataFiles | ForEach-Object { [regex]::Escape($_.file) }) -join '|') + ')\.tmp$')
       title = 'Недописанная копия файла данных: осталась после обрыва записи' }
)

# Название файла данных программы — или $null, если файл не её.
function Get-DataFileTitle {
    param([string]$Name)
    foreach ($d in $script:DataFiles) { if ($Name -ieq $d.file) { return $d.title } }
    foreach ($p in $script:DataFilePatterns) { if ($Name -match $p.rx) { return $p.title } }
    return $null
}

# Можно ли удалить этот файл как данные программы: обычный файл (не папка и
# не ссылка) с именем из списка выше. Сверяется перед каждым удалением, а не
# только при составлении списка.
function Test-DataFileOwned {
    param($Item)
    if ($null -eq $Item -or $Item.PSIsContainer) { return $false }
    if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    return ($null -ne (Get-DataFileTitle $Item.Name))
}

function Get-DataFiles {
    $out = @()
    if (-not (Test-Path -LiteralPath $script:DataDir -PathType Container)) { return @() }
    foreach ($fi in @(Get-ChildItem -LiteralPath $script:DataDir -File -Force -ErrorAction SilentlyContinue)) {
        if (-not (Test-DataFileOwned $fi)) { continue }
        $out += @{ file = $fi.Name; title = (Get-DataFileTitle $fi.Name); kb = [math]::Round($fi.Length / 1KB, 1)
                   changed = $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }
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
        # между списком и удалением на месте файла могла появиться папка или ссылка
        if (-not (Test-DataFileOwned (Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue))) {
            Write-Log ("   [-] пропущен: {0} -- это уже не файл данных программы" -f $d.file); continue
        }
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
