
# =========================================================================== #
#  ДОСЬЕ, часть 2: цифровой след на диске
# =========================================================================== #
function Get-FileCount { param([string]$P, [string]$Filter = '*')
    if (-not (Test-Path -LiteralPath $P)) { return 0 }
    return @(Get-ChildItem -LiteralPath $P -Filter $Filter -Force -ErrorAction SilentlyContinue).Count
}

# Журналы событий, где Windows хранит следы работы с программами и доступа к
# данным. Раньше «Цифровой след» их не видел, а записей там тысячи.
$script:FootprintLogs = @(
    'Microsoft-Windows-Privacy-Auditing/Operational',
    'Microsoft-Windows-UniversalTelemetryClient/Operational',
    'Microsoft-Windows-Application-Experience/Program-Telemetry',
    'Microsoft-Windows-Application-Experience/Program-Compatibility-Assistant',
    'Microsoft-Windows-Shell-Core/Operational'
)

function Get-Footprint {
    $items = New-Object System.Collections.Generic.List[object]
    $add = { param($id, $title, $what, $value, $mb, $count, $canWipe, $warn)
        $items.Add(@{ id=$id; title=$title; what=$what; value="$value"; mb=[double]$mb; count=[int]$count; canWipe=[bool]$canWipe; warn="$warn" }) }

    # Рекламный ID
    $adOn = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled'
    $adId = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Id'
    $adVal = if ($adId) { "$adId" } elseif ($adOn -eq 0) { 'выключен, ID стёрт' } else { 'нет' }
    & $add 'adid' 'Рекламный идентификатор' 'Уникальный ID, по которому рекламные сети узнают вас во всех приложениях.' $adVal 0 $(if ($adId) { 1 } else { 0 }) $([bool]$adId) ''

    # Постоянные ID машины
    $mg  = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Cryptography' 'MachineGuid'
    $sqm = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\SQMClient' 'MachineId'
    & $add 'machineid' 'Постоянные метки компьютера' 'MachineGuid и SQM MachineId — метки, которыми помечается телеметрия. Нужны системе, стереть нельзя.' ("$mg " + "$sqm").Trim() 0 2 $false ''

    # Номер устройства в учётной записи Microsoft (GDID). Лежит открытым текстом
    # шестнадцатеричным числом; Microsoft знает его в десятичном виде с «g:».
    # Простое стирание бесполезно — работа с ним на своей вкладке.
    $gdid = ConvertTo-Gdid "$(Get-RegValue 'HKCU:\SOFTWARE\Microsoft\IdentityCRL\ExtendedProperties' 'LID')"
    $gdidOff = ((Get-SvcStart 'CDPSvc') -eq 4 -and (Get-SvcStart 'DoSvc') -eq 4)
    $gdidWarn = $(if ($gdid -and -not $gdidOff) { 'передаётся' } else { '' })
    & $add 'gdid' 'Номер устройства в учётной записи Microsoft (GDID)' 'По этому номеру Microsoft узнаёт компьютер даже через VPN и выдаёт его по запросу властей. Не передавать, сменить или запретить выдачу — на вкладке «Номер устройства».' $(if ($gdid) { $gdid } else { '—' }) 0 $(if ($gdid) { 1 } else { 0 }) $false $gdidWarn

    # История сетей
    $netNames = @()
    try {
        foreach ($k in @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles' -ErrorAction Stop)) {
            $n = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).ProfileName
            if ($n) { $netNames += "$n" }
        }
    } catch { }
    $netVal = if ($netNames.Count -gt 0) { (@($netNames | Select-Object -First 4) -join ', ') + $(if ($netNames.Count -gt 4) { ' …' } else { '' }) } else { 'пусто' }
    & $add 'networks' 'История сетей Wi-Fi и Ethernet' 'Список всех сетей, к которым подключался компьютер — по ним видно, где вы бывали. Пароли Wi-Fi не трогаются.' $netVal 0 $netNames.Count ($netNames.Count -gt 0) ''

    # История флешек и дисков
    $usb = @()
    try {
        foreach ($dev in @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR' -ErrorAction Stop)) {
            foreach ($inst in @(Get-ChildItem -LiteralPath $dev.PSPath -ErrorAction SilentlyContinue)) {
                $fn = (Get-ItemProperty -LiteralPath $inst.PSPath -ErrorAction SilentlyContinue).FriendlyName
                if ($fn -and $usb -notcontains "$fn") { $usb += "$fn" }
            }
        }
    } catch { }
    $usbVal = if ($usb.Count -gt 0) { (@($usb | Select-Object -First 3) -join ', ') + $(if ($usb.Count -gt 3) { ' …' } else { '' }) } else { 'пусто' }
    & $add 'usb' 'История подключённых флешек' 'Windows помнит каждую флешку и внешний диск. Запись системная, показываем для сведения.' $usbVal 0 $usb.Count $false ''

    # История активности (Timeline)
    $cdp = Join-Path $env:LOCALAPPDATA 'ConnectedDevicesPlatform'
    $cdpMb = Get-FolderSizeMB $cdp
    & $add 'activity' 'База истории активности' 'ActivitiesCache.db — какие программы и документы вы открывали, с точным временем.' ("{0} МБ" -f $cdpMb) $cdpMb (Get-FileCount $cdp) ($cdpMb -gt 0) ''

    # Недавние документы
    $recent = [Environment]::GetFolderPath('Recent')
    $recentCount = Get-FileCount $recent
    & $add 'recent' 'Недавние документы и папки' 'Ярлыки всего, что вы открывали, плюс списки переходов на панели задач.' ("{0} записей" -f $recentCount) (Get-FolderSizeMB $recent) $recentCount ($recentCount -gt 0) ''

    # Строка поиска Проводника
    $www = 0
    try { $k = Get-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery' -ErrorAction Stop; $www = @($k.GetValueNames() | Where-Object { $_ -ne 'MRUListEx' }).Count } catch { }
    & $add 'searchhistory' 'Что вы искали в Проводнике' 'История запросов в строке поиска Проводника.' ("{0} запросов" -f $www) 0 $www ($www -gt 0) ''

    # Адресная строка Проводника
    $tp = 0
    try { $k = Get-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths' -ErrorAction Stop; $tp = @($k.GetValueNames()).Count } catch { }
    & $add 'typedpaths' 'Введённые пути и адреса' 'Что вы вручную набирали в адресной строке Проводника.' ("{0} записей" -f $tp) 0 $tp ($tp -gt 0) ''

    # Буфер обмена
    $clipDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Clipboard'
    $clipMb = Get-FolderSizeMB $clipDir
    $clipOn = Get-RegValue 'HKCU:\Software\Microsoft\Clipboard' 'EnableClipboardHistory'
    & $add 'clipboard' 'История буфера обмена' 'Всё скопированное (Win+V) хранится на диске.' ($(if ($clipOn -eq 1) { 'включена, ' } else { 'выключена, ' }) + "$clipMb МБ") $clipMb (Get-FileCount $clipDir) ($clipMb -gt 0) ''

    # Отчёты об ошибках
    $wer1 = Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'
    $wer2 = Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'
    $wer3 = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER'
    $werMb = (Get-FolderSizeMB $wer1) + (Get-FolderSizeMB $wer2) + (Get-FolderSizeMB $wer3)
    $werCount = (Get-FileCount $wer1) + (Get-FileCount $wer2)
    & $add 'wer' 'Архив отчётов об ошибках' 'Дампы и отчёты о сбоях: содержат пути файлов, имена программ, куски памяти.' ("{0} отчётов, {1} МБ" -f $werCount, [math]::Round($werMb,1)) $werMb $werCount ($werMb -gt 0) ''

    # Словарь персонализации ввода
    $inp = Join-Path $env:APPDATA 'Microsoft\InputPersonalization'
    $inpMb = Get-FolderSizeMB $inp
    & $add 'inputpers' 'Личный словарь набора текста' 'Слова, собранные из вашего набора и рукописного ввода.' ("{0} МБ" -f $inpMb) $inpMb (Get-FileCount $inp) ($inpMb -gt 0) ''

    # Журналы Windows о работе с программами
    $evN = 0
    foreach ($lg in $script:FootprintLogs) {
        try { $evN += [int](Get-WinEvent -ListLog $lg -ErrorAction Stop).RecordCount } catch { }
    }
    & $add 'eventlogs' 'Журналы Windows о работе с программами' 'Какие программы обращались к данным и камере, что запускалось и что отправлял клиент телеметрии.' ("{0} записей" -f $evN) 0 $evN ($evN -gt 0) ''

    # Кэш DNS
    $dnsN = 0
    try { $dnsN = @(Get-DnsClientCache -ErrorAction Stop).Count } catch { }
    & $add 'dnscache' 'Кэш DNS (следы сайтов)' 'Адреса сайтов и служб, к которым недавно обращался компьютер.' ("{0} записей" -f $dnsN) 0 $dnsN ($dnsN -gt 0) ''

    $totalMb = 0.0; $wipeable = 0
    foreach ($it in $items) { $totalMb += [double]$it.mb; if ($it.canWipe) { $wipeable++ } }
    return @{ time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); items = $items.ToArray()
              totalMb = [math]::Round($totalMb, 1); wipeable = $wipeable }
}

function Invoke-FootprintWipe {
    param([string[]]$Ids)
    foreach ($id in $Ids) {
        switch ($id) {
            'adid' {
                if ($DryRun) { Write-Log '   [тест] рекламный ID — стереть'; break }
                Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 -Comment 'рекламный ID — выкл'
                # «Уже стёрт» — только когда значения и правда нет. Раньше так
                # называлась любая ошибка, и отказ в доступе выглядел как успех.
                $adKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
                switch (Remove-RegStatus $adKey 'Id') {
                    'removed' { Write-Log '   [+] рекламный идентификатор стёрт'; $script:Changes++ }
                    'absent'  { Write-Log '   [-] рекламного ID нет -- стирать нечего' }
                    default   { Write-Log '   [!] рекламный идентификатор не стёрт: Windows не дала'; $script:Failures++ }
                }
            }
            'networks' {
                if ($DryRun) { Write-Log '   [тест] история сетей — очистить'; break }
                $n = 0; $nf = 0
                foreach ($k in @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles' -ErrorAction SilentlyContinue)) {
                    try { Remove-Item -LiteralPath $k.PSPath -Recurse -Force -ErrorAction Stop; $n++ } catch { $nf++ }
                }
                foreach ($sig in @('Unmanaged','Managed')) {
                    foreach ($k in @(Get-ChildItem ('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\' + $sig) -ErrorAction SilentlyContinue)) {
                        try { Remove-Item -LiteralPath $k.PSPath -Recurse -Force -ErrorAction Stop } catch { $nf++ }
                    }
                }
                Write-Log ("   [+] история сетей очищена: {0} записей (пароли Wi-Fi не тронуты)" -f $n); $script:Changes++
                # раньше неудачи не считались, и «очищена» писалось при любом исходе
                if ($nf -gt 0) { Write-Log ("   [!] записей сетей, которые Windows не отдала: {0}" -f $nf); $script:Failures++ }
            }
            'activity' {
                # Службы держат базу открытой — на время чистки останавливаем,
                # потом запускаем обратно. Раньше оставались остановленными.
                $cdpRun = @(Get-Service -Name 'cdp*' -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' } | ForEach-Object { $_.Name })
                foreach ($n in $cdpRun) { if (-not $DryRun) { Stop-Service -Name $n -Force -ErrorAction SilentlyContinue } }
                $null = Clear-FolderContents (Join-Path $env:LOCALAPPDATA 'ConnectedDevicesPlatform') 'база истории активности'
                foreach ($n in $cdpRun) {
                    if ($DryRun) { continue }
                    try { Start-Service -Name $n -ErrorAction Stop }
                    catch { Write-Log ("   [i] служба {0} сейчас не запустилась -- запустится после перезагрузки" -f $n) }
                }
            }
            'recent' {
                $null = Clear-FolderContents ([Environment]::GetFolderPath('Recent')) 'недавние документы'
                if (-not $DryRun) {
                    try { Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs' -Recurse -Force -ErrorAction Stop; Write-Log '   [+] список RecentDocs в реестре очищен' } catch [System.Management.Automation.ItemNotFoundException] { } catch { Write-Log ("   [!] список RecentDocs в реестре не очищен -- {0}" -f $_.Exception.Message); $script:Failures++ }
                }
            }
            'searchhistory' {
                if ($DryRun) { Write-Log '   [тест] история поиска Проводника — очистить'; break }
                try { Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery' -Recurse -Force -ErrorAction Stop; Write-Log '   [+] история поиска Проводника очищена'; $script:Changes++ } catch { Write-Log '   [-] история поиска уже пуста' }
            }
            'typedpaths' {
                if ($DryRun) { Write-Log '   [тест] введённые пути — очистить'; break }
                try { Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths' -Recurse -Force -ErrorAction Stop; Write-Log '   [+] введённые пути очищены'; $script:Changes++ } catch { Write-Log '   [-] введённых путей нет' }
            }
            'clipboard' {
                $null = Clear-FolderContents (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Clipboard') 'история буфера обмена'
            }
            'wer' {
                $null = Clear-FolderContents (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive') 'архив отчётов об ошибках'
                $null = Clear-FolderContents (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue') 'очередь отчётов об ошибках'
                $null = Clear-FolderContents (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER') 'локальные отчёты об ошибках'
            }
            'inputpers' {
                $null = Clear-FolderContents (Join-Path $env:APPDATA 'Microsoft\InputPersonalization') 'личный словарь набора'
            }
            'dnscache' {
                if ($DryRun) { Write-Log '   [тест] кэш DNS — очистить'; break }
                try { Clear-DnsClientCache -ErrorAction Stop; Write-Log '   [+] кэш DNS очищен'; $script:Changes++ } catch { Write-Log '   [!] не удалось очистить кэш DNS' }
            }
            'eventlogs' {
                if ($DryRun) { Write-Log '   [тест] журналы Windows о работе с программами — очистить'; break }
                $cleared = 0
                foreach ($lg in $script:FootprintLogs) {
                    $null = & wevtutil.exe cl $lg 2>&1
                    if ($LASTEXITCODE -eq 0) { $cleared++ }
                }
                Write-Log ("   [+] очищено журналов: {0} из {1}" -f $cleared, $script:FootprintLogs.Count)
                if ($cleared -gt 0) { $script:Changes++ }
            }
            default { Write-Log ("   [-] неизвестный элемент следа: {0}" -f $id) }
        }
    }
}

# --- отозвать или вернуть доступ программы к датчику ---
if ($SensorSet) {
    # Раньше разрешение датчика писалось в реестр напрямую: мимо журнала
    # отката (полный откат его не возвращал) и без проверки имени — «..\» в
    # имени датчика увёл бы запись в другую ветку. Теперь — только имя датчика
    # из букв и цифр, только Allow/Deny, и через Set-Reg: журнал заранее,
    # сверка записанного.
    $r = @{ key = $SensorKey; value = $SensorValue; ok = $false }
    if ($SensorKey -notmatch '^[A-Za-z0-9_]{1,64}$' -or $SensorValue -notin @('Allow', 'Deny')) {
        $r.error = 'недопустимое имя датчика или значение'; Emit-Json $r; exit 1
    }
    $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\' + $SensorKey
    $failBefore = $script:Failures
    Set-Reg -Path $root -Name 'Value' -Value $SensorValue -Type 'String' -Comment ("датчик {0}: {1}" -f $SensorKey, $SensorValue)
    Save-JournalEntries -Quiet
    $r.ok = ($script:Failures -eq $failBefore) -and ("$(Get-RegValue $root 'Value')" -eq $SensorValue)
    if (-not $r.ok) { $r.error = 'Windows не дала изменить разрешение или журнал отката не пишется' }
    Emit-Json $r
    exit 0
}

# --- список отдельных настроек внутри модулей ---
if ($ListDefs) {
    $groups = @()
    foreach ($m in $script:ModuleOrder) {
        $mi = @($script:Defs | Where-Object { $_.M -eq $m })
        if ($mi.Count -eq 0) { continue }
        $groups += @{ module = $m; title = $script:ModuleTitles[$m]
                      items = @($mi | ForEach-Object { @{ id = $_.Id; name = $_.C; kind = $_.T
                                                          target = "$($_.P)"; valueName = "$($_.N)"
                                                          risk = (Get-DefRisk $_)
                                                          note = $(if ($script:DefNotes.ContainsKey("$($_.C)")) { $script:DefNotes["$($_.C)"] } else { '' }) } }) }
    }
    Emit-Json @{ groups = $groups }
    exit 0
}

if ($Spy) {
    $r = Get-SpyReport
    try { $null = Update-SensorHistory $r } catch { }
    $r.days = Get-SensorDays
    $r.sensorGuard = [bool](Get-ScheduledTask -TaskName $script:SensorTask -ErrorAction SilentlyContinue)
    $r.doh = Get-DohStatus
    Emit-Json $r
    exit 0
}

if ($Footprint) { Emit-Json (Get-Footprint); exit 0 }

if ($LeakTest) { Emit-Json (Invoke-LeakTest); exit 0 }

if ($FootprintWipe) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Стирание цифрового следа'
    if ($WipeItems.Count -eq 0) { Write-Log '   [-] ничего не выбрано' }
    else { Invoke-FootprintWipe -Ids $WipeItems }
    Emit-Json (Get-Footprint)
    Write-Log '###DONE###'
    exit 0
}
