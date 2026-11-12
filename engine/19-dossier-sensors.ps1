
# =========================================================================== #
#  ДОСЬЕ, часть 1: кто включал камеру, микрофон, геолокацию
#  Windows сама ведёт журнал обращений к датчикам (ConsentStore) —
#  мы его читаем и показываем человеку. Только чтение.
# =========================================================================== #
$script:SpyCaps = @(
    @{ id='webcam';                 title='Камера' },
    @{ id='microphone';             title='Микрофон' },
    @{ id='location';               title='Местоположение' },
    @{ id='graphicsCaptureProgrammatic'; title='Снимки экрана' },
    @{ id='graphicsCaptureWithoutBorder'; title='Захват экрана без рамки' },
    @{ id='userNotificationListener'; title='Чтение уведомлений' },
    @{ id='documentsLibrary';       title='Документы' },
    @{ id='picturesLibrary';        title='Изображения' },
    @{ id='videosLibrary';          title='Видео' },
    @{ id='broadFileSystemAccess';  title='Весь диск' },
    @{ id='contacts';               title='Контакты' },
    @{ id='appointments';           title='Календарь' },
    @{ id='email';                  title='Почта' },
    @{ id='chat';                   title='Сообщения' },
    @{ id='phoneCall';              title='Звонки' },
    @{ id='phoneCallHistory';       title='Журнал звонков' },
    @{ id='userDataTasks';          title='Задачи и планы' },
    @{ id='userAccountInformation'; title='Данные учётной записи' },
    @{ id='activity';               title='Сведения об активности' },
    @{ id='bluetoothSync';          title='Обмен с устройствами' },
    @{ id='radios';                 title='Управление радиомодулями' },
    @{ id='sensors.custom';         title='Датчики устройства' },
    @{ id='humanInterfaceDevice';   title='Устройства ввода' },
    @{ id='cellularData';           title='Сотовая связь' },
    @{ id='appDiagnostics';         title='Диагностика других программ' },
    # Эти категории Windows завела позже: ИИ-модели системы, ключи доступа,
    # периферия. Раньше «Досье» их просто не показывало.
    @{ id='systemAIModels';         title='ИИ-модели Windows' },
    @{ id='passkeys';               title='Ключи доступа (passkeys)' },
    @{ id='passkeysEnumeration';    title='Перечень ключей доступа' },
    @{ id='bluetooth';              title='Bluetooth' },
    @{ id='usb';                    title='USB-устройства' },
    @{ id='serialCommunication';    title='COM-порты' },
    @{ id='wiFiDirect';             title='Wi-Fi Direct' },
    @{ id='wifiData';               title='Данные о сетях Wi-Fi' },
    @{ id='gazeInput';              title='Отслеживание взгляда' }
)

function ConvertTo-FriendlyAppName {
    param([string]$Key)
    if ($Key -match '#') {
        $p = $Key -replace '#','\'
        $leaf = Split-Path $p -Leaf
        if ($leaf) { return $leaf }
        return $Key
    }
    $i = $Key.IndexOf('_')
    if ($i -gt 0) { return $Key.Substring(0, $i) }
    return $Key
}

function Get-SpyReport {
    $caps = @(); $activeNow = 0; $week = 0
    $since7 = (Get-Date).AddDays(-7)
    foreach ($cap in $script:SpyCaps) {
        $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\' + $cap.id
        $global = Get-RegValue $root 'Value'
        $keys = @()
        if (Test-Path -LiteralPath $root) {
            foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                if ($k.PSChildName -eq 'NonPackaged') { $keys += @(Get-ChildItem -LiteralPath $k.PSPath -ErrorAction SilentlyContinue) }
                else { $keys += $k }
            }
        }
        $items = @()
        foreach ($k in $keys) {
            $start = 0L; $stop = 0L
            try {
                $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop
                if ($null -ne $p.LastUsedTimeStart) { $start = [long]$p.LastUsedTimeStart }
                if ($null -ne $p.LastUsedTimeStop)  { $stop  = [long]$p.LastUsedTimeStop }
            } catch { }
            if ($start -le 0 -and -not $SpyAll) { continue }
            $active = ($stop -le 0 -or $stop -lt $start)
            $lastTicks = [Math]::Max($start, $stop)
            $last = $null
            if ($lastTicks -gt 0) { try { $last = [DateTime]::FromFileTime($lastTicks) } catch { } }
            $never = ($null -eq $last)
            if ($never) { $last = [datetime]'1900-01-01' }
            $minutes = 0.0
            if (-not $active -and $stop -gt $start) { $minutes = [math]::Round(($stop - $start) / 600000000.0, 1) }
            if ($active -and -not $never) { $activeNow++ } else { $active = $false }
            if (-not $never -and $last -ge $since7) { $week++ }
            $rel = ($k.PSPath -replace '^.*\\ConsentStore\\', '')
            $allow = 'Allow'
            try { $vv = (Get-ItemProperty -LiteralPath $k.PSPath -Name 'Value' -ErrorAction Stop).Value; if ($vv) { $allow = "$vv" } } catch { }
            $items += @{ app = (ConvertTo-FriendlyAppName $k.PSChildName); key = $rel; value = $allow
                         last = $(if ($never) { '' } else { $last.ToString('yyyy-MM-dd HH:mm') })
                         minutes = $minutes; active = [bool]$active; never = [bool]$never
                         sort = $last.Ticks }
        }
        # один и тот же exe может числиться под несколькими ключами — оставляем самое свежее
        $seen = @{}; $dedup = @()
        foreach ($it in @($items | Sort-Object { $_.sort } -Descending)) {
            $k = $it.app.ToLowerInvariant()
            if ($seen.ContainsKey($k)) {
                if ($it.minutes -gt $dedup[$seen[$k]].minutes) { $dedup[$seen[$k]].minutes = $it.minutes }
                continue
            }
            $seen[$k] = $dedup.Count; $dedup += $it
        }
        $items = @($dedup | Select-Object -First 40)
        foreach ($it in $items) { $it.Remove('sort') }
        $caps += @{ id = $cap.id; title = $cap.title
                    global = $(if ("$global") { "$global" } else { 'Allow' })
                    count = $items.Count; items = $items }
    }
    return @{ time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); activeNow = $activeNow; week = $week; caps = $caps }
}

# --- Накопленная история обращений к датчикам ------------------------------ #
# ConsentStore хранит только последнее использование, поэтому при каждом
# сборе досье и каждой проверке слежения новые метки складываются в журнал —
# из него строится график по дням.
function Update-SensorHistory {
    param($Report)
    $hist = Load-Json 'sensor-history.json'
    $known = @{}
    $events = @()
    if ($hist -and $hist.events) {
        foreach ($e in @($hist.events)) {
            $events += $e
            $known[("{0}|{1}|{2}" -f $e.cap, $e.app, $e.time)] = $true
        }
    }
    $new = @()
    foreach ($c in @($Report.caps)) {
        foreach ($it in @($c.items)) {
            $k = "{0}|{1}|{2}" -f $c.id, $it.app, $it.last
            if ($known.ContainsKey($k)) { continue }
            $ev = @{ cap = $c.id; app = $it.app; time = $it.last; minutes = $it.minutes }
            $events += $ev; $new += $ev; $known[$k] = $true
        }
    }
    if ($new.Count -gt 0 -or -not $hist) {
        if ($events.Count -gt 2000) { $events = @($events | Sort-Object { "$($_.time)" } | Select-Object -Last 2000) }
        Save-Json 'sensor-history.json' @{ events = $events; updated = (Get-Date).ToString('s') }
    }
    return ,$new
}

function Get-SensorDays {
    $hist = Load-Json 'sensor-history.json'
    $byDay = @{}
    if ($hist -and $hist.events) {
        foreach ($e in @($hist.events)) {
            $ds = "$($e.time)"
            if ($ds.Length -lt 10) { continue }
            $ds = $ds.Substring(0, 10)
            if (-not $byDay.ContainsKey($ds)) { $byDay[$ds] = @{ cam=0; mic=0; loc=0; other=0 } }
            switch ("$($e.cap)") {
                'webcam'     { $byDay[$ds].cam++ }
                'microphone' { $byDay[$ds].mic++ }
                'location'   { $byDay[$ds].loc++ }
                default      { $byDay[$ds].other++ }
            }
        }
    }
    $days = @()
    for ($i = 13; $i -ge 0; $i--) {
        $d = (Get-Date).Date.AddDays(-$i)
        $ds = $d.ToString('yyyy-MM-dd')
        $rec = if ($byDay.ContainsKey($ds)) { $byDay[$ds] } else { @{ cam=0; mic=0; loc=0; other=0 } }
        $days += @{ date = $d.ToString('dd.MM'); cam = $rec.cam; mic = $rec.mic; loc = $rec.loc; other = $rec.other }
    }
    return $days
}
