
# =========================================================================== #
#  Purge buffer (отдельная команда)
# =========================================================================== #
if ($PurgeBuffer) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Purge-Buffer
    Emit-Json (Get-BufferInfo)
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  РЕНТГЕН ТЕЛЕМЕТРИИ
#  Читает реальные события диагностики, которые Windows собрала о компьютере,
#  через встроенный модуль Microsoft.DiagnosticDataViewer.
# =========================================================================== #
$script:XrayDbDir = Join-Path $env:ProgramData 'Microsoft\Diagnosis\EventTranscript'

# Правила расшифровки: имя события -> человеческая категория
$script:XrayRules = @(
    @{ rx = 'Inventory\.(Core|Application)|InventoryApplication|AppInv|InstalledApplication';
       cat = 'Список установленных программ'; what = 'Какие программы стоят на компьютере, их версии и издатели' },
    @{ rx = 'Census|SystemInfo|Hardware|Processor|Memory|Storage|Battery|Firmware|Bios|Chassis';
       cat = 'Инвентаризация железа'; what = 'Модель ноутбука, процессор, память, диски, серийные номера' },
    @{ rx = 'AppInteractivity|AppLaunch|AppUsage|Win32kTraceLogging|AppActivity|ProcessStart|FocusTime';
       cat = 'Какие программы ты запускал'; what = 'Что открывал, сколько времени провёл, как часто' },
    @{ rx = 'PnP|DeviceConfig|DeviceInventory|USB|Bluetooth|Peripheral|Driver';
       cat = 'Подключённые устройства'; what = 'Флешки, наушники, принтеры, мыши — что и когда подключал' },
    @{ rx = 'WER|Fault|AppCrash|Watson|Hang|Reliability|BugCheck|Crash';
       cat = 'Сбои и падения программ'; what = 'Какие программы падали, с какими ошибками, имена файлов' },
    @{ rx = 'Edge|Browser|WebView|Chromium|SmartScreen';
       cat = 'Браузер'; what = 'Активность в браузере, посещения, проверки сайтов' },
    @{ rx = 'Search|Cortana|Bing|Suggest';
       cat = 'Поиск'; what = 'Что искал в меню Пуск и как использовался поиск' },
    @{ rx = 'Store|AppXDeployment|Purchase|License|Xbox|Game';
       cat = 'Магазин, игры и лицензии'; what = 'Установки из магазина, покупки, игровая активность' },
    @{ rx = 'Defender|Antivirus|Antimalware|Security|Firewall|Tpm|SecureBoot';
       cat = 'Безопасность'; what = 'Состояние защиты, проверки, обнаружения' },
    @{ rx = 'Update|WindowsUpdate|SIH|WUFB|Servicing|Setup360|UpdateAgent|Delivery';
       cat = 'Обновления'; what = 'Установка обновлений, версии, ошибки установки' },
    @{ rx = 'Location|Geolocation|Position|Wifi.*Scan|Sensor';
       cat = 'Местоположение и датчики'; what = 'Где находится компьютер, окружающие сети' },
    @{ rx = 'Logon|Login|Account|AAD|MSA|Identity|User\.|Profile|Credential';
       cat = 'Учётная запись'; what = 'Входы в систему, привязка к учётной записи Microsoft' },
    @{ rx = 'Network|Dns|Tcp|Connectivity|Ndis|Wlan|Ethernet';
       cat = 'Сеть'; what = 'Сетевые подключения, качество связи' },
    @{ rx = 'Power|Sleep|Resume|Boot|Shutdown|Uptime|Kernel\.Process';
       cat = 'Питание и загрузка'; what = 'Когда включал и выключал, время работы' },
    @{ rx = 'Office|Word|Excel|Outlook|OneDrive|Teams';
       cat = 'Office и OneDrive'; what = 'Работа с документами и облаком' },
    @{ rx = 'Heartbeat|Diagtrack|Telemetry|Utc\.|SelfHost|OneSettings|Aria';
       cat = 'Служебное телеметрии'; what = 'Служебные события самой системы сбора данных' }
)

function Get-XrayCategory {
    param([string]$Name)
    foreach ($r in $script:XrayRules) { if ($Name -match $r.rx) { return $r } }
    return @{ cat = 'Прочее'; what = 'События, не попавшие в известные категории' }
}

function Test-XrayModule {
    if (Get-Command Get-DiagnosticData -ErrorAction SilentlyContinue) { return $true }
    Import-Module Microsoft.DiagnosticDataViewer -ErrorAction SilentlyContinue
    return [bool](Get-Command Get-DiagnosticData -ErrorAction SilentlyContinue)
}

function Get-XrayViewingEnabled {
    try {
        if (Get-Command Get-DiagnosticDataViewingSetting -ErrorAction SilentlyContinue) {
            $s = Get-DiagnosticDataViewingSetting
            if ($null -ne $s) {
                foreach ($p in @('DiagnosticDataViewingEnabled','Enabled','IsEnabled')) {
                    if ($s.PSObject.Properties.Name -contains $p) { return [bool]$s.$p }
                }
                return [bool]$s
            }
        }
    } catch { }
    $v = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\EventTranscript' 'EnableEventTranscript'
    return ($v -eq 1)
}

function Get-XrayDbInfo {
    $mb = 0; $found = $false
    try {
        $items = @(Get-ChildItem -LiteralPath $script:XrayDbDir -Force -ErrorAction Stop)
        if ($items.Count -gt 0) {
            $found = $true
            $sum = ($items | Measure-Object -Property Length -Sum).Sum
            if ($sum) { $mb = [math]::Round($sum / 1MB, 2) }
        }
    } catch { }
    return @{ exists = $found; mb = $mb; path = $script:XrayDbDir }
}

function Get-XrayStatusObject {
    return @{
        moduleAvailable = (Test-XrayModule)
        recording       = (Get-XrayViewingEnabled)
        db              = (Get-XrayDbInfo)
        baseline        = (Load-Json 'xray-baseline.json')
    }
}

# --- Основное сканирование ------------------------------------------------- #
# --------------------------------------------------------------------------- #
#  ЧТО ИМЕННО О ВАС УЗНАЛИ
#  Рентген уже читает настоящие события. Здесь их содержимое превращается в
#  человеческие факты: не «1420 событий инвентаризации», а «названия 47 ваших
#  программ, модель ноутбука, серийный номер диска». Правило, которое ничего
#  не нашло, просто не показывается — выдумывать нечего.
# --------------------------------------------------------------------------- #
$script:FactRules = @(
    @{ id = 'apps';    title = 'Названия установленных программ'
       what = 'Windows перечисляет, что у вас стоит: имя, издатель и версия каждой программы.'
       re = '"(?:ProgramName|AppName|PackageFullName|ProductName)"\s*:\s*"([^"]{2,90})"' },
    @{ id = 'files';   title = 'Имена запускавшихся файлов'
       what = 'В событиях видно, какие исполняемые файлы вы открывали.'
       re = '"(?:FileName|BinaryName|ImageName|ExeName)"\s*:\s*"([^"]{2,90})"' },
    @{ id = 'device';  title = 'Модель и производитель компьютера'
       what = 'Точная модель железа — по ней устройство узнаётся среди прочих.'
       re = '"(?:deviceMake|deviceModel|SystemManufacturer|SystemProductName|Model|Manufacturer)"\s*:\s*"([^"]{2,80})"' },
    @{ id = 'ids';     title = 'Идентификаторы, которыми вас метят'
       what = 'Постоянные номера устройства и учётной записи: по ним события связываются в один профиль.'
       # номер устройства в учётной записи (GDID) событие несёт полем device.id: «g:» и цифры
       re = '(?:"(?:localId|deviceId|machineId|userId|globalDeviceId|sqmId)"\s*:\s*"|"id"\s*:\s*"(?=g:\d{6}))([^"]{6,120})' },
    @{ id = 'serial';  title = 'Серийные номера железа'
       what = 'Серийный номер не меняется никогда — это самая надёжная метка устройства.'
       re = '"(?:SerialNumber|BaseBoardSerial|BiosSerial|DiskSerial)"\s*:\s*"([^"]{4,80})"' },
    @{ id = 'hw';      title = 'Начинка компьютера'
       what = 'Процессор, память, диски и видеокарта — подробная опись железа.'
       re = '"(?:ProcessorIdentifier|ProcessorManufacturer|TotalPhysicalRAM|PrimaryDiskType|GraphicsAdapter|CpuFamily)"\s*:\s*"?([^",]{2,80})"?' },
    @{ id = 'net';     title = 'Сетевые адреса и имена сетей'
       what = 'MAC-адрес и названия сетей говорят, где физически стоит компьютер.'
       re = '"(?:MacAddress|SSID|NetworkName|BSSID)"\s*:\s*"([^"]{4,80})"' },
    @{ id = 'user';    title = 'Учётная запись и язык'
       what = 'Имя пользователя, страна, часовой пояс и раскладка.'
       re = '"(?:UserName|AccountName|CountryRegion|TimeZone|Locale|UserLocale|KeyboardLayout)"\s*:\s*"([^"]{2,80})"' },
    @{ id = 'devices'; title = 'Подключённые устройства'
       what = 'Всё, что вы подключали: принтеры, флешки, наушники, телефоны.'
       re = '"(?:DeviceName|FriendlyName|DeviceInstanceId|ContainerId)"\s*:\s*"([^"]{4,90})"' },
    @{ id = 'errors';  title = 'Сбои программ с их именами'
       what = 'Имена упавших программ и модулей — заодно видно, чем вы пользуетесь.'
       re = '"(?:FaultingApplicationName|CrashingProcess|ExceptionModule)"\s*:\s*"([^"]{2,90})"' }
)

function Add-FactValue {
    param($Store, [string]$Id, [string]$Value)
    $v = $Value.Trim()
    if (-not $v) { return }
    if ($v -match '^[\{\[]') { return }               # GUID-ы и структуры пропускаем
    if ($v -match '^(?:0|1|true|false|null|unknown|n/a)$') { return }
    if (-not $Store.ContainsKey($Id)) { $Store[$Id] = @{} }
    if ($Store[$Id].Count -ge 400) { return }           # памяти ради
    if ($Store[$Id].ContainsKey($v)) { $Store[$Id][$v]++ } else { $Store[$Id][$v] = 1 }
}

function Invoke-XrayScan {
    param([int]$Hours, [int]$Max)

    if (-not (Test-XrayModule)) {
        return @{ error = 'Модуль Microsoft.DiagnosticDataViewer недоступен на этой системе.' }
    }
    if (-not (Get-XrayViewingEnabled)) {
        return @{ error = 'Запись диагностики выключена. Нажмите «Включить запись», подождите — и повторите.'; recording = $false }
    }

    $start = (Get-Date).AddHours(-$Hours)
    $events = @()
    try { $events = @(Get-DiagnosticData -StartTime $start -RecordCount $Max -ErrorAction Stop) }
    catch { return @{ error = ("Не удалось прочитать данные: " + $_.Exception.Message) } }

    if ($events.Count -eq 0) {
        return @{ error = 'Событий за выбранный период нет. Если запись включена только что — подождите час-другой.'; total = 0; recording = $true }
    }

    $cats = @{}
    $names = @{}
    $bytes = 0
    $ids = @{}
    $apps = @{}
    $samples = @{}
    $facts = @{}

    foreach ($ev in $events) {
        $n = [string]$ev.Name
        $p = [string]$ev.Payload
        $bytes += $p.Length

        $rule = Get-XrayCategory $n
        $c = $rule.cat
        if (-not $cats.ContainsKey($c)) { $cats[$c] = @{ count = 0; bytes = 0; what = $rule.what; names = @{} } }
        $cats[$c].count++
        $cats[$c].bytes += $p.Length
        if ($cats[$c].names.ContainsKey($n)) { $cats[$c].names[$n]++ } else { $cats[$c].names[$n] = 1 }

        if ($names.ContainsKey($n)) { $names[$n]++ } else { $names[$n] = 1 }

        if (-not $samples.ContainsKey($c) -and $p.Length -gt 40) {
            $txt = $p
            if ($txt.Length -gt 1800) { $txt = $txt.Substring(0, 1800) + ' …' }
            $samples[$c] = @{ name = $n; time = $ev.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'); payload = $txt }
        }

        # что именно о вас узнали — по тем же событиям
        foreach ($rule in $script:FactRules) {
            foreach ($m in [regex]::Matches($p, $rule.re)) { Add-FactValue $facts $rule.id $m.Groups[1].Value }
        }

        # идентификаторы, которыми помечены события
        foreach ($m in [regex]::Matches($p, '"(localId|deviceId|machineId|userId|sessionId|deviceClass|osVer|deviceMake|deviceModel)"\s*:\s*"([^"]{2,120})"')) {
            $k = $m.Groups[1].Value; $v = $m.Groups[2].Value
            if (-not $ids.ContainsKey($k)) { $ids[$k] = @{} }
            if (-not $ids[$k].ContainsKey($v)) { $ids[$k][$v] = 0 }
            $ids[$k][$v]++
        }
        # названия программ, попавшие в инвентаризацию
        if ($n -match 'Inventory|AppInv|AppInteractivity|AppLaunch') {
            foreach ($m in [regex]::Matches($p, '"(?:ProgramName|AppName|Name|PackageFullName|FileName)"\s*:\s*"([^"]{2,90})"')) {
                $v = $m.Groups[1].Value
                if ($v -match '^[\{\d]' ) { continue }
                if ($apps.ContainsKey($v)) { $apps[$v]++ } else { $apps[$v] = 1 }
            }
        }
    }

    $span = [math]::Max(0.05, $Hours)
    $perDay  = [math]::Round($events.Count * 24.0 / $span, 0)
    $mbTotal = $bytes / 1MB
    $mbDay   = [math]::Round($mbTotal * 24.0 / $span, 2)

    $catList = @()
    foreach ($k in ($cats.Keys | Sort-Object { -$cats[$_].count })) {
        $topNames = @($cats[$k].names.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 |
                      ForEach-Object { @{ name = $_.Key; count = $_.Value } })
        $catList += @{
            name = $k; count = $cats[$k].count
            mb = [math]::Round($cats[$k].bytes / 1MB, 3)
            what = $cats[$k].what
            share = [math]::Round(100.0 * $cats[$k].count / $events.Count, 1)
            topNames = $topNames
            sample = $(if ($samples.ContainsKey($k)) { $samples[$k] } else { $null })
        }
    }

    $idList = @()
    foreach ($k in $ids.Keys) {
        $vals = @($ids[$k].GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3 |
                  ForEach-Object { @{ value = $_.Key; count = $_.Value } })
        $idList += @{ key = $k; distinct = $ids[$k].Count; values = $vals }
    }

    $appList = @($apps.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 25 |
                 ForEach-Object { @{ name = $_.Key; count = $_.Value } })

    $factList = @()
    foreach ($rule in $script:FactRules) {
        if (-not $facts.ContainsKey($rule.id)) { continue }
        $vals = @($facts[$rule.id].GetEnumerator() | Sort-Object Value -Descending)
        if ($vals.Count -eq 0) { continue }
        $factList += @{
            id = $rule.id; title = $rule.title; what = $rule.what
            distinct = $vals.Count
            examples = @($vals | Select-Object -First 6 | ForEach-Object { [string]$_.Key })
        }
    }

    $result = @{
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); hours = $Hours; recording = $true
        total = $events.Count; distinctNames = $names.Count
        mb = [math]::Round($mbTotal, 2); perDay = $perDay; mbPerDay = $mbDay
        perYear = [math]::Round($perDay * 365, 0); mbPerYear = [math]::Round($mbDay * 365, 1)
        categories = $catList; identifiers = $idList; apps = $appList; facts = $factList
        topNames = @($names.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15 |
                     ForEach-Object { @{ name = $_.Key; count = $_.Value } })
        db = (Get-XrayDbInfo)
    }

    $base = Load-Json 'xray-baseline.json'
    if ($base -and $base.perDay) {
        $result.baselinePerDay = $base.perDay
        $result.baselineTime = $base.time
        $result.deltaPercent = $(if ([double]$base.perDay -gt 0) { [math]::Round(100.0 * (1.0 - ($perDay / [double]$base.perDay)), 1) } else { 0 })
    }
    return $result
}

if ($XrayStatus) { Emit-Json (Get-XrayStatusObject); exit 0 }

if ($XrayEnable) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Рентген: включение записи'
    if (-not (Test-XrayModule)) { Write-Log '   [!] модуль Microsoft.DiagnosticDataViewer недоступен' }
    else {
        try {
            Enable-DiagnosticDataViewing -ErrorAction Stop
            Write-Log '   [+] запись диагностики включена'
        } catch {
            Write-Log "   [!] $($_.Exception.Message)"
            Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\EventTranscript' 'EnableEventTranscript' 1 -Comment 'запись событий диагностики (резервный способ)'
        }
    }
    Write-Log ''
    Write-Log 'Windows теперь ведёт ЛОКАЛЬНУЮ копию своих диагностических событий,'
    Write-Log 'чтобы их можно было прочитать. Объём отправки при этом не растёт.'
    Write-Log 'Дайте системе поработать хотя бы час, затем нажмите «Сканировать».'
    Write-Log '###DONE###'
    exit 0
}

if ($XrayDisable) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Рентген: выключение записи'
    try { Disable-DiagnosticDataViewing -ErrorAction Stop; Write-Log '   [+] запись выключена' }
    catch { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\EventTranscript' 'EnableEventTranscript' 0 -Comment 'запись событий диагностики — выкл' }
    Write-Log '###DONE###'
    exit 0
}
