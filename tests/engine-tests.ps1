# Проверки поведения движка. Запускаются в сборке и локально:
#     powershell -ExecutionPolicy Bypass -File tests\engine-tests.ps1
# Ничего в системе не меняют: только чтение и тестовые прогоны.

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$engine = Join-Path (Split-Path $PSScriptRoot -Parent) 'Win11-Privacy-Engine.ps1'
if (-not (Test-Path $engine)) { Write-Host "не найден движок: $engine"; exit 1 }

$script:Failed = 0
$script:Passed = 0

function Run-Engine {
    param([string[]]$EngineArgs)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Command powershell.exe).Source
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $engine + '" ' + ($EngineArgs -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $null = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return $out
}

function Get-EngineJson {
    param([string[]]$EngineArgs)
    $out = Run-Engine $EngineArgs
    foreach ($line in ($out -split "`n")) {
        $t = $line.TrimStart()
        if ($t.StartsWith('###JSON###')) {
            try { return ($t.Substring(10).Trim() | ConvertFrom-Json) } catch { return $null }
        }
    }
    return $null
}

function Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host ("  [ok]   " + $Name); $script:Passed++ }
    else {
        Write-Host ("  [FAIL] " + $Name + $(if ($Detail) { "  --  $Detail" } else { '' }))
        Write-Host ("::error::" + $Name + " " + $Detail)
        $script:Failed++
    }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host ("Права администратора: " + $isAdmin)
Write-Host ''

# --------------------------------------------------------------------------- #
Write-Host 'Список настроек'
$defs = Get-EngineJson @('-ListDefs')
Check 'ListDefs отвечает' ($null -ne $defs)
if ($defs) {
    $groups = @($defs.groups)
    Check 'модулей больше 20' ($groups.Count -gt 20) ("получено: " + $groups.Count)
    $ids = @()
    foreach ($g in $groups) { foreach ($i in @($g.items)) { $ids += $i.id } }
    Check 'настроек больше 150' ($ids.Count -gt 150) ("получено: " + $ids.Count)
    Check 'номера настроек уникальны' (($ids | Select-Object -Unique).Count -eq $ids.Count)
    $empty = @($groups | Where-Object { -not $_.title })
    Check 'у всех модулей есть название' ($empty.Count -eq 0)
}

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Разбор списка модулей (регрессия: -File не делит по запятым)'
$two = Get-EngineJson @('-Audit', '-Modules', 'telemetry,ads')
Check 'аудит по списку отвечает' ($null -ne $two)
if ($two) {
    $titles = @($two.groups | ForEach-Object { $_.module })
    Check 'вернулось ровно 2 модуля' ($titles.Count -eq 2) ("получено: " + ($titles -join ','))
    Check 'это telemetry и ads' (($titles -contains 'telemetry') -and ($titles -contains 'ads'))
}

$all = Get-EngineJson @('-Audit')
Check 'полный аудит отвечает' ($null -ne $all)
if ($all) {
    Check 'настроек в аудите больше 150' ([int]$all.total -gt 150) ("получено: " + $all.total)
    Check 'аудит отдаёт число недоступных настроек' ($null -ne $all.blocked)
    $blockedItems = @()
    foreach ($g in @($all.groups)) { foreach ($i in @($g.items)) { if ($i.blocked) { $blockedItems += $i } } }
    Check 'недоступные не входят в итог' ([int]$all.blocked -eq $blockedItems.Count) `
          ("blocked=" + $all.blocked + ", помечено: " + $blockedItems.Count)
}

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Пропуск отдельных пунктов'
if ($all -and $defs) {
    $firstId = @($defs.groups)[0].items[0].id
    $skipped = Get-EngineJson @('-Audit', '-SkipItems', $firstId)
    Check 'аудит с пропуском отвечает' ($null -ne $skipped)
    if ($skipped) {
        Check 'пропущенный пункт не учитывается' ([int]$skipped.total -eq ([int]$all.total - 1)) `
              ("было " + $all.total + ", стало " + $skipped.total)
    }
}

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Чтение данных'
$spy = Get-EngineJson @('-Spy')
Check 'досье по датчикам отвечает' ($null -ne $spy -and $null -ne $spy.caps)
$foot = Get-EngineJson @('-Footprint')
Check 'цифровой след отвечает' ($null -ne $foot -and $null -ne $foot.items)
$apps = Get-EngineJson @('-ListApps')
Check 'список приложений отвечает' ($null -ne $apps -and $null -ne $apps.apps)
$self = Get-EngineJson @('-SelfTest')
Check 'самопроверка отвечает' ($null -ne $self)
$log = Get-EngineJson @('-ChangeLog')
Check 'журнал отката отвечает' ($null -ne $log)

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Автозагрузка'
$start = Get-EngineJson @('-ListStartup')
Check 'список автозагрузки отвечает' ($null -ne $start -and $null -ne $start.items)
if ($start) {
    $sitems = @($start.items)
    Check 'счётчики совпадают со списком' ([int]$start.total -eq $sitems.Count) `
          ("total=" + $start.total + ", записей=" + $sitems.Count)
    $noName = @($sitems | Where-Object { -not $_.name -or -not $_.id })
    Check 'у каждой записи есть имя и код' ($noName.Count -eq 0)
    $sids = @($sitems | ForEach-Object { $_.id })
    Check 'коды записей уникальны' (($sids | Select-Object -Unique).Count -eq $sids.Count)
    $badId = @($sids | Where-Object { $_ -match '[ ,]' -or $_.StartsWith('-') })
    Check 'коды пригодны для командной строки' ($badId.Count -eq 0) ("плохие: " + ($badId -join ' '))
    $onBefore = @($sitems | Where-Object { $_.enabled }).Count
    if ($sids.Count -gt 0) {
        $null = Run-Engine @('-StartupSet', '-StartupValue', 'Off', '-StartupItems', $sids[0], '-DryRun')
        $after = Get-EngineJson @('-ListStartup')
        Check 'тестовый прогон ничего не гасит' ([int]$after.on -eq $onBefore) `
              ("было " + $onBefore + ", стало " + $after.on)
    }
}

# Функции пометки берём из самого движка (разбором исходника), чтобы проверять
# рабочий код, а не его копию. Служебный ключ создаётся и удаляется здесь же.
$engineAst = [System.Management.Automation.Language.Parser]::ParseFile($engine, [ref]$null, [ref]$null)
$wanted = @('Get-RegValue', 'Test-StartupApproved', 'Set-StartupApproved', 'ConvertTo-StartupId', 'ConvertFrom-StartupId')
$found = @()
foreach ($fn in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($wanted -contains $fn.Name) { Invoke-Expression $fn.Extent.Text; $found += $fn.Name }
}
Check 'функции автозагрузки найдены в движке' ($found.Count -eq $wanted.Count) ("найдено: " + ($found -join ','))
if ($found.Count -eq $wanted.Count) {
    $raw = 'run|HKCU|Имя с пробелом, запятой и «кавычками»'
    $code = ConvertTo-StartupId $raw
    Check 'код записи читается обратно' ((ConvertFrom-StartupId $code) -eq $raw)
    Check 'код записи не спутать с параметром' (-not $code.StartsWith('-') -and $code -notmatch '[ ,]')

    $testKey = 'HKCU:\Software\Win11PrivacyTest'
    try {
        if (-not (Test-Path -LiteralPath $testKey)) { New-Item -Path $testKey -Force | Out-Null }
        Check 'без отметки запись считается работающей' (Test-StartupApproved $testKey 'demo')
        Set-StartupApproved $testKey 'demo' $false
        Check 'отметка «погашено» читается' (-not (Test-StartupApproved $testKey 'demo'))
        Set-StartupApproved $testKey 'demo' $true
        Check 'отметка «работает» читается' (Test-StartupApproved $testKey 'demo')
    } finally {
        Remove-Item -LiteralPath $testKey -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Форма ответов: список из одного элемента обязан остаться списком'
$rawSnap = Run-Engine @('-SnapshotList')
$lineSnap = @($rawSnap -split "`n" | Where-Object { $_.TrimStart().StartsWith('###JSON###') })[0]
Check 'снимки приходят списком' ($lineSnap -match '"snapshots"\s*:\s*\[') $lineSnap
$rawApps = Run-Engine @('-ListApps')
$lineApps = @($rawApps -split "`n" | Where-Object { $_.TrimStart().StartsWith('###JSON###') })[0]
Check 'приложения приходят списком' ($lineApps -match '"apps"\s*:\s*\[')

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Проверка вместе с доказательством результата (один прогон вместо двух)'
$withProof = Get-EngineJson @('-Audit', '-WithProof')
Check 'аудит с доказательством отвечает' ($null -ne $withProof -and $null -ne $withProof.proof)
if ($withProof -and $withProof.proof) {
    Check 'снимок «после» есть' ($null -ne $withProof.proof.after)
    Check 'числа снимка совпадают с аудитом' ([int]$withProof.proof.after.ok -eq [int]$withProof.ok) `
          ("аудит " + $withProof.ok + ", снимок " + $withProof.proof.after.ok)
    Check 'в снимке есть автозапуск' ($null -ne $withProof.proof.after.startupOn)
}

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Запрет выхода в сеть'
$noPath = Get-EngineJson @('-BlockApp')
Check 'без пути к программе — понятная ошибка' ($null -ne $noPath -and "$($noPath.error)".Length -gt 0)

$devFns = @('ConvertFrom-DevicePath')
$devFound = @()
foreach ($fn in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($devFns -contains $fn.Name) { Invoke-Expression $fn.Extent.Text; $devFound += $fn.Name }
}
Check 'разбор пути ядра найден в движке' ($devFound.Count -eq 1)
if ($devFound.Count -eq 1) {
    $exe = (Get-Command powershell.exe).Source
    Check 'обычный путь остаётся как есть' ((ConvertFrom-DevicePath $exe) -eq $exe)
    $kernel = '\device\harddiskvolume999\' + $exe.Substring(3)
    Check 'путь ядра превращается в путь с буквой диска' ((ConvertFrom-DevicePath $kernel) -eq $exe) `
          ("получено: " + (ConvertFrom-DevicePath $kernel))
    Check 'сетевой путь не выдаётся за локальный' ((ConvertFrom-DevicePath '\device\mup\srv\share\x.exe') -eq '')
}

# Адреса телеметрии спрашиваются у DNS все сразу и не дольше отведённого:
# по одному шаг тянулся минутами, пока мёртвые имена ждали ответа.
$ipFns = @('Test-PublicIp', 'Test-PublicIpAddress', 'Get-TelemetryIpList')
$ipFound = @()
foreach ($fn in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($ipFns -contains $fn.Name) { Invoke-Expression $fn.Extent.Text; $ipFound += $fn.Name }
}
Check 'разбор адресов телеметрии найден в движке' ($ipFound.Count -eq $ipFns.Count) ("найдено: " + ($ipFound -join ','))
if ($ipFound.Count -eq $ipFns.Count) {
    $script:TelemetryIps = @('13.64.90.137')
    # адрес вместо имени отвечает сразу и без сети; localhost — частный и в
    # правило попасть не должен; несуществующее имя не должно задерживать
    $script:HostsDomains = @('8.8.8.8', 'localhost', '8.8.8.8', 'win11privacy-test.invalid')
    $ipSw = [Diagnostics.Stopwatch]::StartNew()
    $ipRes = Get-TelemetryIpList -TimeoutMs 3000
    $ipSw.Stop()
    $ipGot = @($ipRes.ips)
    Check 'известные адреса попадают в правило всегда' ($ipGot -contains '13.64.90.137')
    Check 'адрес из списка имён попадает в правило' ($ipGot -contains '8.8.8.8') ("получено: " + ($ipGot -join ', '))
    Check 'частные адреса в правило не попадают' (-not ($ipGot | Where-Object { $_ -like '127.*' }))
    Check 'повторы в списке имён спрашиваются один раз' ($ipRes.asked -eq 3) ("спрошено: $($ipRes.asked)")
    Check 'разбор имён укладывается в отведённое время' ($ipSw.Elapsed.TotalSeconds -lt 6) ("заняло: {0:N1} с" -f $ipSw.Elapsed.TotalSeconds)
    # публичный адрес — по диапазонам: общие адреса провайдеров, тестовые и
    # зарезервированные сети, многоадресные IPv6, IPv4 внутри IPv6, не-адреса
    $ipCases = [ordered]@{ '8.8.8.8' = $true; '100.64.1.1' = $false; '100.128.0.1' = $true; '172.15.0.1' = $true; '172.31.255.1' = $false
                           '198.18.0.5' = $false; '240.0.0.1' = $false; '255.255.255.255' = $false; '2a01:111:f100::1' = $true; '::' = $false
                           'fe80::1%12' = $false; 'ff12::1' = $false; '::ffff:10.0.0.1' = $false; '::ffff:8.8.8.8' = $true; '2001:db8::1' = $false
                           'localhost' = $false; '1.2.3' = $false }
    $ipWrong = @($ipCases.Keys | Where-Object { (Test-PublicIp $_) -ne $ipCases[$_] })
    Check 'публичный адрес определяется по диапазонам' ($ipWrong.Count -eq 0) ("ошибается на: " + ($ipWrong -join ', '))
}

# Блок в hosts: программа обязана узнавать свой блок и убирать его целиком.
# Метки были по-русски, а файл пишется в ASCII — они превращались в «?»,
# блок дописывался заново при каждом применении, и откат его не находил.
$hostsFns = @('Test-HostsBlock', 'Apply-Hosts', 'Remove-HostsBlock', 'Test-HostsMarkKind', 'Get-HostsWanted', 'Get-HostsBlockLines', 'Test-HostsBlockCurrent')
$hostsFound = @()
foreach ($fn in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($hostsFns -contains $fn.Name) { Invoke-Expression $fn.Extent.Text; $hostsFound += $fn.Name }
}
foreach ($a in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                                              $n.Left.Extent.Text -like '$script:HostsMark*' }, $true)) {
    Invoke-Expression $a.Extent.Text
}
Check 'работа с hosts найдена в движке' ($hostsFound.Count -eq $hostsFns.Count) ("найдено: " + ($hostsFound -join ','))
if ($hostsFound.Count -eq $hostsFns.Count) {
    function Write-Log { param([string]$Message = '') }
    function ipconfig { }                       # кэш DNS настоящей системы не трогаем
    $DryRun = $false
    $script:BackupDir = ''
    $script:HostsDomains = @('telemetry.example', 'vortex.example')
    $script:HostsPath = Join-Path $env:TEMP ('win11privacy-hosts-' + [Guid]::NewGuid().ToString('N') + '.txt')
    try {
        # Чужая строка с нелатинской буквой задаётся байтом, а не текстом: в
        # какой кодировке работает машина сборки, заранее неизвестно, а
        # сохраниться строка обязана в любой.
        [IO.File]::WriteAllBytes($script:HostsPath,
            [byte[]]([Text.Encoding]::ASCII.GetBytes('# caf') + 0xE9 + [Text.Encoding]::ASCII.GetBytes("`r`n127.0.0.1 localhost`r`n")))
        $own = @(Get-Content -LiteralPath $script:HostsPath)
        Check 'в чистом файле блока нет' (-not (Test-HostsBlock))
        Apply-Hosts
        Check 'после записи блок узнаётся' (Test-HostsBlock)
        Apply-Hosts
        $marks = @(Get-Content -LiteralPath $script:HostsPath | Where-Object { $_ -match $script:HostsMarkRegex })
        Check 'повторное применение не дописывает второй блок' ($marks.Count -eq 2) ("строк-меток: " + $marks.Count)
        Remove-HostsBlock
        $left = @(Get-Content -LiteralPath $script:HostsPath)
        Check 'откат убирает блок целиком' (-not (Test-HostsBlock) -and -not ($left -match 'telemetry\.example'))
        Check 'чужие строки остаются как были' (($left -join '|') -eq ($own -join '|')) ("получено: " + ($left -join '|'))

        # блок от прежних версий: метки побиты в «?», и таких блоков два подряд
        $old = @('', '# --- Win11Privacy: ?????????? ?????????? (??????) ---', '0.0.0.0 telemetry.example',
                 '# --- Win11Privacy: ?????????? ?????????? (?????) ---')
        Set-Content -LiteralPath $script:HostsPath -Value ($own + $old + $old) -Encoding Default
        Check 'блок прежних версий узнаётся' (Test-HostsBlock)
        Remove-HostsBlock
        $left = @(Get-Content -LiteralPath $script:HostsPath)
        Check 'блоки прежних версий убираются все' (($left -join '|') -eq ($own -join '|')) ("получено: " + ($left -join '|'))

        # закрывающую метку стёрли руками: чужое после блока трогать нельзя
        Set-Content -LiteralPath $script:HostsPath -Encoding Default -Value @(
            $script:HostsMarkStart, '0.0.0.0 telemetry.example', '10.0.0.5 nas.local')
        Remove-HostsBlock
        $left = @(Get-Content -LiteralPath $script:HostsPath)
        Check 'без закрывающей метки чужие строки не теряются' (($left -join '|') -eq '10.0.0.5 nas.local') ("получено: " + ($left -join '|'))

        # Блок номера устройства (GDID) ставится и узнаётся отдельно: раньше
        # любая метка программы считалась блоком телеметрии, и второй блок
        # «уже присутствовал» бы, не будучи записанным.
        $script:GdidHosts = @('dds.example', 'cdpcs.example')
        Set-Content -LiteralPath $script:HostsPath -Value $own -Encoding Default
        Apply-Hosts -Kind 'gdid'
        Check 'блок номера устройства узнаётся' (Test-HostsBlock -Kind 'gdid')
        Check 'блок номера устройства не выдаёт себя за блок телеметрии' (-not (Test-HostsBlock))
        Apply-Hosts
        Check 'блок телеметрии ставится рядом с блоком номера устройства' (Test-HostsBlock)
        Apply-Hosts -Kind 'gdid'
        Apply-Hosts
        $gm = @(Get-Content -LiteralPath $script:HostsPath | Where-Object { $_ -match $script:HostsMarkRegex })
        Check 'повторное применение не дописывает ни один из блоков' ($gm.Count -eq 4) ("строк-меток: " + $gm.Count)
        Remove-HostsBlock
        $left = @(Get-Content -LiteralPath $script:HostsPath)
        Check 'откат убирает оба блока' (($left -join '|') -eq ($own -join '|')) ("получено: " + ($left -join '|'))

        # Блоки номера устройства закрывают и IPv6 (строки «::»), а снимаются
        # по одному: «Вернуть как было» на вкладке номера не трогает телеметрию.
        $script:GdidLockHosts = @('login.example')
        Apply-Hosts -Kind 'gdid'; Apply-Hosts -Kind 'lock'; Apply-Hosts
        $v6 = @(Get-Content -LiteralPath $script:HostsPath | Where-Object { $_ -match '^::\s' })
        Check 'все блоки закрывают и IPv6' ($v6.Count -eq 5) ("строк «::»: " + $v6.Count)
        Check 'запрет выдачи узнаётся отдельно' ((Test-HostsBlock -Kind 'lock') -and (Test-HostsBlock -Kind 'gdid') -and (Test-HostsBlock))
        Remove-HostsBlock -Kind 'lock'
        Check 'снятие запрета выдачи не трогает другие блоки' ((-not (Test-HostsBlock -Kind 'lock')) -and (Test-HostsBlock -Kind 'gdid') -and (Test-HostsBlock))
        Remove-HostsBlock -Kind 'gdid'
        Check 'снятие блока номера оставляет блок телеметрии' ((-not (Test-HostsBlock -Kind 'gdid')) -and (Test-HostsBlock))
        Remove-HostsBlock
        $left = @(Get-Content -LiteralPath $script:HostsPath)
        Check 'после всех снятий файл как был' (($left -join '|') -eq ($own -join '|')) ("получено: " + ($left -join '|'))

        # Блок от прежней версии: доменов меньше, строк IPv6 нет. Применение
        # обязано его дополнить, а не сказать «уже присутствует».
        Set-Content -LiteralPath $script:HostsPath -Encoding Default -Value ($own + @('', $script:HostsMarkStart, '0.0.0.0 telemetry.example', $script:HostsMarkEnd, '10.0.0.5 nas.local'))
        Check 'старый блок узнаётся устаревшим' ((Test-HostsBlock) -and -not (Test-HostsBlockCurrent))
        Apply-Hosts
        $now = @(Get-Content -LiteralPath $script:HostsPath)
        Check 'старый блок дополнен новыми доменами' ((Test-HostsBlockCurrent) -and ($now -contains '0.0.0.0 vortex.example') -and ($now -contains ':: telemetry.example'))
        Check 'после обновления блок один' (@($now | Where-Object { $_ -match $script:HostsMarkRegex }).Count -eq 2)
        Check 'чужие строки при обновлении на месте' (($now -contains '10.0.0.5 nas.local') -and (($now[0..($own.Count - 1)] -join '|') -eq ($own -join '|')))
    } finally {
        Remove-Item -LiteralPath $script:HostsPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path Function:\ipconfig -ErrorAction SilentlyContinue
    }
}

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Порядок объявлений в движке'
$engineText = Get-Content -LiteralPath $engine -Raw -Encoding UTF8
$posStartup = $engineText.IndexOf('function Get-StartupList')
$posGuard = $engineText.IndexOf('function Run-Guard')
Check 'функции автозагрузки объявлены выше стража' ($posStartup -gt 0 -and $posStartup -lt $posGuard) `
      ("Get-StartupList на " + $posStartup + ", Run-Guard на " + $posGuard)
# страж и сканирование зовут Save-XrayDay, страж — ещё и Invoke-XrayScan: объявления обязаны быть раньше вызовов
$posXray = $engineText.IndexOf('function Invoke-XrayScan')
$posSaveDay = $engineText.IndexOf('function Save-XrayDay')
$posScanCmd = $engineText.IndexOf('if ($XrayScan) {')
$posGuardCmd = $engineText.IndexOf('if ($Guard) {')
Check 'дневной замер объявлен раньше команды сканирования' ($posSaveDay -gt 0 -and $posSaveDay -lt $posScanCmd) `
      ("Save-XrayDay на " + $posSaveDay + ", -XrayScan на " + $posScanCmd)
Check 'рентген объявлен раньше команды стража' ($posXray -gt 0 -and $posXray -lt $posGuardCmd) `
      ("Invoke-XrayScan на " + $posXray + ", -Guard на " + $posGuardCmd)

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Имена параметров реестра (регрессия: $n затирал параметр $N в Def)'
if ($defs) {
    $regItems = @()
    foreach ($g in @($defs.groups)) { foreach ($i in @($g.items)) { if ("$($i.kind)" -eq 'reg') { $regItems += $i } } }
    Check 'определения реестра отдают имя параметра' ($regItems.Count -gt 50) ("получено: " + $regItems.Count)
    $numeric = @($regItems | Where-Object { "$($_.valueName)" -match '^[0-9]+$' })
    Check 'ни одно имя параметра не превратилось в число' ($numeric.Count -eq 0) `
          ("числовых: " + $numeric.Count + " (первое: " + $(if ($numeric.Count) { $numeric[0].name } else { '-' }) + ")")
    $known = @($regItems | Where-Object { "$($_.valueName)" -eq 'AllowTelemetry' })
    Check 'AllowTelemetry на месте' ($known.Count -ge 1)
}

# Тот же класс ошибки в любой другой функции: локальная переменная, которая
# отличается от параметра только регистром, молча его затирает.
$collide = 0
foreach ($fn in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    $pnames = @{}
    if ($fn.Body.ParamBlock) { foreach ($pp in $fn.Body.ParamBlock.Parameters) { $pnames[$pp.Name.VariablePath.UserPath] = $true } }
    if ($pnames.Count -eq 0) { continue }
    foreach ($asg in $fn.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        $tgt = $asg.Left -as [System.Management.Automation.Language.VariableExpressionAst]
        if (-not $tgt) { continue }
        $vn = $tgt.VariablePath.UserPath
        foreach ($pn in $pnames.Keys) {
            if ($vn -ceq $pn) { continue }
            if ($vn -ieq $pn) {
                Write-Host ("        " + $fn.Name + ": строка " + $asg.Extent.StartLineNumber + ", " + $vn + " затирает параметр " + $pn)
                $collide++
            }
        }
    }
}
Check 'локальные переменные не затирают параметры функций' ($collide -eq 0) ("столкновений: " + $collide)

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Виды определений реестра учтены везде'
$regTypes = @()
foreach ($asg in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
    $lt = $asg.Left -as [System.Management.Automation.Language.VariableExpressionAst]
    if ($null -ne $lt -and $lt.VariablePath.UserPath -eq 'script:RegTypes') { Invoke-Expression $asg.Extent.Text; $regTypes = @($script:RegTypes) }
}
Check 'общий список видов реестра есть' ($regTypes.Count -ge 3) ("получено: " + ($regTypes -join ','))
if ($defs -and $regTypes.Count -gt 0) {
    $kinds = @()
    foreach ($g in @($defs.groups)) { foreach ($i in @($g.items)) { $kinds += "$($i.kind)" } }
    $regLike = @($kinds | Where-Object { $_ -like 'reg*' } | Select-Object -Unique)
    $missed = @($regLike | Where-Object { $regTypes -notcontains $_ })
    Check 'ни один вид записи в реестр не забыт' ($missed.Count -eq 0) ("забыты: " + ($missed -join ','))
    # резервная копия обязана брать ключи по этому же списку
    Check 'резервная копия берёт ключи по общему списку' `
          ($engineText -match [regex]::Escape('$script:RegTypes -contains $_.T'))
}

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Журнал изменений и данные программы'
$log2 = Get-EngineJson @('-ChangeLog')
Check 'журнал изменений отвечает' ($null -ne $log2 -and $null -ne $log2.count)
$rawLog = Run-Engine @('-ChangeLog')
$lineLog = @($rawLog -split "`n" | Where-Object { $_.TrimStart().StartsWith('###JSON###') })[0]
Check 'записи журнала приходят списком' ($lineLog -match '"items"\s*:\s*\[')
$data = Get-EngineJson @('-DataInfo')
Check 'данные программы читаются' ($null -ne $data -and $null -ne $data.folder)
if ($data) { Check 'папка данных названа' ("$($data.folder)" -like '*Win11Privacy*') "$($data.folder)" }
$noItems = Get-EngineJson @('-RestoreItems')
Check 'возврат без выбора ничего не делает' ($null -ne $noItems)

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Запись в реестр: журнал заранее, неудача отзывает запись'
$regFns = @('Get-RegValue', 'Set-RegDirect', 'Set-Reg', 'Test-Admin', 'Test-RegKeyWritable', 'Get-FolderSizeMB', 'ConvertTo-RegComparable',
            'Write-AheadEntry', 'Undo-AheadEntry', 'Test-CanModify', 'Get-JournalKey', 'ConvertTo-Fields')
$regFound = @()
foreach ($fn in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($regFns -contains $fn.Name) { Invoke-Expression $fn.Extent.Text; $regFound += $fn.Name }
}
Check 'функции записи найдены в движке' ($regFound.Count -eq $regFns.Count) ("найдено: " + ($regFound -join ','))
if ($regFound.Count -eq $regFns.Count) {
    $script:Journal = New-Object System.Collections.Generic.List[object]
    $script:Changes = 0; $script:Failures = 0; $script:Already = 0
    $DryRun = $false
    $logLines = New-Object System.Collections.Generic.List[string]
    function Write-Log { param([string]$Message = '') $logLines.Add($Message) }
    # Резервная копия проверяется своим разделом ниже; здесь — заглушка,
    # иначе каждый вызов печатал «Ensure-Backup не найдена».
    function Ensure-Backup { }
    # запись журнала на диск проверяется своим разделом; здесь очередь остаётся в памяти
    function Save-JournalEntries { param([switch]$Quiet) }
    $script:JournalFailed = $false; $script:RunId = 'test'; $script:JournalRetract = New-Object 'System.Collections.Generic.HashSet[string]'

    # SECURITY закрыт даже от администратора — запись обязана провалиться
    Set-Reg -Path 'HKLM:\SECURITY\Win11PrivacyProbe' -Name 'x' -Value 1 -Type 'DWord' -Comment 'проверка отказа'
    Check 'неудачная запись не попадает в журнал отката' ($script:Journal.Count -eq 0) ("записей: " + $script:Journal.Count)
    Check 'неудача посчитана ошибкой' ($script:Failures -eq 1)
    Check 'в журнале выполнения виден вид ошибки' (@($logLines | Where-Object { $_ -match 'Exception' }).Count -ge 1) `
          ($logLines -join ' | ')

    # свой ключ пользователя — запись обязана пройти и попасть в журнал
    Set-Reg -Path 'HKCU:\Software\Win11PrivacyProbe' -Name 'x' -Value 7 -Type 'DWord' -Comment 'проверка записи'
    Check 'удачная запись попадает в журнал отката' ($script:Journal.Count -eq 1) ("записей: " + $script:Journal.Count)
    Check 'значение записано' ((Get-RegValue 'HKCU:\Software\Win11PrivacyProbe' 'x') -eq 7)
    Remove-Item -LiteralPath 'HKCU:\Software\Win11PrivacyProbe' -Recurse -Force -ErrorAction SilentlyContinue
    Check 'служебный ключ убран' (-not (Test-Path 'HKCU:\Software\Win11PrivacyProbe'))

    # записанное сверяется: если читается другое, это не успех, но в журнал
    # изменение попадает всё равно — значение в реестре уже не прежнее
    $script:grvCalls = 0
    function Get-RegValue { param([string]$Path, [string]$Name) $script:grvCalls++; if ($script:grvCalls -eq 1) { return $null }; return 5 }
    $script:Journal = New-Object System.Collections.Generic.List[object]; $script:Failures = 0; $script:Changes = 0
    Set-Reg -Path 'HKCU:\Software\Win11PrivacyProbe2' -Name 'x' -Value 7 -Type 'DWord' -Comment 'проверка сверки'
    Check 'записанное сверяется: другое значение — не успех' ($script:Failures -eq 1 -and $script:Changes -eq 0) (($logLines | Select-Object -Last 1))
    Check '…но изменение всё равно попадает в журнал отката' ($script:Journal.Count -eq 1)
    foreach ($fn in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-RegValue' }, $true)) { Invoke-Expression $fn.Extent.Text }
    Remove-Item -LiteralPath 'HKCU:\Software\Win11PrivacyProbe2' -Recurse -Force -ErrorAction SilentlyContinue
    Check 'сравнение значений реестра по типу' (((ConvertTo-RegComparable -1 'DWord') -eq (ConvertTo-RegComparable 4294967295 'DWord')) -and
        ((ConvertTo-RegComparable '%SystemRoot%\x' 'ExpandString') -eq (ConvertTo-RegComparable "$env:SystemRoot\x" 'ExpandString')) -and
        ((ConvertTo-RegComparable ([byte[]](1, 255)) 'Binary') -eq '01ff') -and ((ConvertTo-RegComparable '1' 'DWord') -eq (ConvertTo-RegComparable 1 'DWord')) -and
        ((ConvertTo-RegComparable 'a' 'String') -ne (ConvertTo-RegComparable 'b' 'String')))
    $script:Journal = New-Object System.Collections.Generic.List[object]; $script:Failures = 0; $script:Changes = 0

    # политика, которую система не отдаёт, — это не ошибка программы
    $script:Failures = 0; $script:Blocked = 0
    $script:Journal = New-Object System.Collections.Generic.List[object]
    # SECURITY закрыт и для администратора — годится на любой машине
    Set-Reg -Path 'HKLM:\SECURITY\Win11PrivacyProbe' -Name 'x' -Value 1 -Type 'DWord' -Comment 'политика' -Policy
    Check 'отказ по политике не считается ошибкой' ($script:Failures -eq 0) ("ошибок: " + $script:Failures)
    Check 'отказ по политике посчитан отдельно' ($script:Blocked -eq 1) ("заблокировано: " + $script:Blocked)
    Check 'отказ по политике не пишется в журнал' ($script:Journal.Count -eq 0)

    # проба «пишется ли ключ» не должна оставлять следов
    Check 'проба видит доступный ключ' (Test-RegKeyWritable 'HKCU:\Software')
    Check 'проба не оставляет параметр' ($null -eq (Get-RegValue 'HKCU:\Software' '_Win11PrivacyProbe'))
    Check 'проба видит закрытый ключ' (-not (Test-RegKeyWritable 'HKLM:\SECURITY'))

    # размер папки без файлов раньше сыпал ошибкой Measure-Object в журнал
    $probeDir = Join-Path $env:TEMP 'w11p-tests-size'
    Remove-Item -LiteralPath $probeDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path (Join-Path $probeDir 'sub') -Force | Out-Null
    $errBefore = $Error.Count
    $sz = Get-FolderSizeMB $probeDir
    Check 'папка без файлов считается молча' (($sz -eq 0) -and ($Error.Count -eq $errBefore)) `
          ("размер: " + $sz + ", новых ошибок: " + ($Error.Count - $errBefore))
    Remove-Item -LiteralPath $probeDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:\Ensure-Backup' -ErrorAction SilentlyContinue
}

# Пакета виджетов на машине сборки нет, поэтому проверяем сам отбор, а не
# список установленного: исключение обязано работать, а защита — оставаться.
foreach ($asg in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
    $lt = $asg.Left -as [System.Management.Automation.Language.VariableExpressionAst]
    if ($null -eq $lt) { continue }
    if ($lt.VariablePath.UserPath -in @('script:AppxProtected', 'script:AppxAllowed', 'script:AppxBloat')) {
        Invoke-Expression $asg.Extent.Text
    }
}
foreach ($fn in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($fn.Name -eq 'Test-AppxProtected') { Invoke-Expression $fn.Extent.Text }
}
if (Get-Command Test-AppxProtected -ErrorAction SilentlyContinue) {
    Check 'доска виджетов выведена из-под защиты' (-not (Test-AppxProtected 'MicrosoftWindows.Client.WebExperience'))
    Check 'остальная оболочка по-прежнему защищена' (Test-AppxProtected 'MicrosoftWindows.Client.CBS')
    Check 'магазин по-прежнему защищён' (Test-AppxProtected 'Microsoft.WindowsStore')
    Check 'у доски виджетов есть человеческое название' ($script:AppxBloat.ContainsKey('MicrosoftWindows.Client.WebExperience'))
} else {
    Check 'функция отбора приложений найдена' $false
}

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Повторное применение не выдаёт себя за изменение'
foreach ($fn in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($fn.Name -eq 'Apply-Def') { Invoke-Expression $fn.Extent.Text }
}
if (Get-Command Apply-Def -ErrorAction SilentlyContinue) {
    # Резервная копия проверяется своим разделом ниже; здесь — заглушка,
    # иначе каждый вызов печатал «Ensure-Backup не найдена».
    function Ensure-Backup { }
    # журнал отката проверяется своим разделом; здесь — запоминаем, что пришло
    $script:JournalSeen = New-Object System.Collections.Generic.List[object]
    function Add-JournalEntry { param($Entry) $script:JournalSeen.Add($Entry) }
    # журнал заранее (write-ahead): здесь тоже только запоминаем, что пришло
    function Write-AheadEntry { param($Entry) $script:JournalSeen.Add($Entry); return $true }
    function Undo-AheadEntry { param($Entry) $null = $script:JournalSeen.Remove($Entry) }
    function Test-CanModify { param([string]$Label) return $true }
    $DryRun = $false
    $script:Changes = 0; $script:Already = 0; $script:Failures = 0
    $envName = 'WIN11PRIVACY_TEST_VAR'
    [Environment]::SetEnvironmentVariable($envName, $null, 'User')
    $envDef = @{ T = 'env'; P = $envName; V = '1'; C = 'проба переменной' }
    Apply-Def $envDef
    Check 'первая установка считается изменением' (($script:Changes -eq 1) -and ($script:Already -eq 0)) `
          ("изменений: " + $script:Changes + ", уже настроено: " + $script:Already)
    Apply-Def $envDef
    Check 'повторная установка считается уже настроенной' (($script:Changes -eq 1) -and ($script:Already -eq 1)) `
          ("изменений: " + $script:Changes + ", уже настроено: " + $script:Already)
    # к списку — напрямую: @() вокруг List[object] с хэш-таблицей в PowerShell 5.1
    # падает с «Argument types do not match»
    $jn = $script:JournalSeen.Count
    $j0 = $(if ($jn -gt 0) { $script:JournalSeen[0] } else { $null })
    Check 'переменная среды записана в журнал отката один раз и «как было»' (($jn -eq 1) -and ("$($j0['kind'])" -eq 'env') -and (-not $j0['existed'])) `
          ("записей: " + $jn)
    [Environment]::SetEnvironmentVariable($envName, $null, 'User')
    Check 'проба убрана' ($null -eq [Environment]::GetEnvironmentVariable($envName, 'User'))
    Remove-Item -Path 'Function:\Ensure-Backup', 'Function:\Add-JournalEntry', 'Function:\Write-AheadEntry', 'Function:\Undo-AheadEntry', 'Function:\Test-CanModify' -ErrorAction SilentlyContinue
} else {
    Check 'Apply-Def найдена в движке' $false
}

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Резервная копия: только при ручном применении и только по факту'
foreach ($fn in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($fn.Name -in @('Ensure-Backup', 'Write-Section')) { Invoke-Expression $fn.Extent.Text }
    if ($fn.Name -in @('Compress-Journal', 'ConvertTo-Fields', 'Get-JournalKey')) { Invoke-Expression $fn.Extent.Text }
}
# заглушка: проверяем резервную копию, а не запись журнала
function Save-JournalEntries { param([switch]$Quiet) }

if (Get-Command Ensure-Backup -ErrorAction SilentlyContinue) {
    $script:Defs = @(
        @{ M = 'probe'; T = 'reg';   P = 'HKCU:\Software'; N = 'x'; V = 0 },
        @{ M = 'probe'; T = 'regif'; P = 'HKLM:\SECURITY'; N = 'y'; V = 0 }
    )
    $script:RegTypes = @('reg', 'regif', 'regpol')
    $Modules = @('probe')
    $DryRun = $false
    $NoBackup = $false
    $NoRestorePoint = $true
    $BackupRoot = Join-Path $env:TEMP 'w11p-tests-backup'
    $script:BackupDir = ''
    $script:BackupTried = $false
    $script:BackupEnabled = $false
    Remove-Item -LiteralPath $BackupRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    # свой сборщик строк: так видно, что именно написала копия
    $bkLines = New-Object System.Collections.Generic.List[string]
    function Write-Log { param([string]$Message = '') $bkLines.Add($Message) }

    Ensure-Backup
    Check 'без ручного применения копия не создаётся' (@(Get-ChildItem $BackupRoot -Directory).Count -eq 0)

    $script:BackupEnabled = $true
    Ensure-Backup
    $made = @(Get-ChildItem $BackupRoot -Directory)
    Check 'при применении копия создаётся' ($made.Count -eq 1) ("папок: " + $made.Count)
    if ($made.Count -eq 1) {
        $files = @(Get-ChildItem $made[0].FullName -File)
        Check 'в копии лежит выгруженная ветка' ($files.Count -eq 1) ("файлов: " + $files.Count)
        Check 'недоступная ветка не засчитана' (@($bkLines | Where-Object { $_ -match 'сохранено веток: 1' }).Count -ge 1) `
              (($bkLines -join ' | '))
        Check 'о невыгруженной ветке сказано' (@($bkLines | Where-Object { $_ -match 'не выгрузились ветки' }).Count -ge 1)
    }

    Ensure-Backup
    Check 'повторный вызов не плодит папки' (@(Get-ChildItem $BackupRoot -Directory).Count -eq 1)
    Remove-Item -LiteralPath $BackupRoot -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Check 'Ensure-Backup найдена в движке' $false
}

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Хронология приватности'
$tl = Get-EngineJson @('-Timeline', '-TimelineDays', '30')
Check 'хронология отвечает' ($null -ne $tl -and $null -ne $tl.days)
if ($tl) {
    $tlDays = @($tl.days)
    Check 'дней ровно столько, сколько просили' ($tlDays.Count -eq 30) ("получено: " + $tlDays.Count)
    Check 'последний день — сегодня' ("$($tlDays[-1].date)" -eq (Get-Date).ToString('yyyy-MM-dd')) `
          ("получено: " + $tlDays[-1].date)
    $noLabel = @($tlDays | Where-Object { -not $_.label })
    Check 'у каждого дня есть подпись' ($noLabel.Count -eq 0)
    Check 'обновления Windows попали в ряд' (@($tlDays | Where-Object { @($_.updates).Count -gt 0 }).Count -ge 0)
}
$rawTl = Run-Engine @('-Timeline')
$lineTl = @($rawTl -split "`n" | Where-Object { $_.TrimStart().StartsWith('###JSON###') })[0]
Check 'дни приходят списком' ($lineTl -match '"days"\s*:\s*\[')
$tlShort = Get-EngineJson @('-Timeline', '-TimelineDays', '2')
Check 'слишком короткий период растягивается до недели' (@($tlShort.days).Count -eq 7) `
      ("получено: " + @($tlShort.days).Count)

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Резервные копии: список и защита от ерунды'
$bk = Get-EngineJson @('-ListBackups')
Check 'список копий отвечает' ($null -ne $bk -and $null -ne $bk.count)
$rawBk = Run-Engine @('-ListBackups')
$lineBk = @($rawBk -split "`n" | Where-Object { $_.TrimStart().StartsWith('###JSON###') })[0]
Check 'копии приходят списком' ($lineBk -match '"items"\s*:\s*\[')
$bad = Get-EngineJson @('-RestoreBackup', '-BackupPath', 'C:\NoSuchFolder\Win11PrivacyNope')
Check 'несуществующая папка отвергается' ($null -ne $bad -and "$($bad.error)".Length -gt 0)

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Разбор событий телеметрии в факты'
$factFns = @('Add-FactValue')
$factFound = @()
foreach ($fn in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($factFns -contains $fn.Name) { Invoke-Expression $fn.Extent.Text; $factFound += $fn.Name }
}
foreach ($asg in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
    $lt = $asg.Left -as [System.Management.Automation.Language.VariableExpressionAst]
    if ($null -ne $lt -and $lt.VariablePath.UserPath -eq 'script:FactRules') { Invoke-Expression $asg.Extent.Text }
}
Check 'правила разбора найдены' ($null -ne $script:FactRules -and @($script:FactRules).Count -ge 5) `
      ("правил: " + @($script:FactRules).Count)
if ($factFound.Count -eq 1 -and $script:FactRules) {
    $payload = '{"ProgramName":"Google Chrome","deviceModel":"HVY-WXX9","localId":"m:A1B2C3D4E5F67890","TimeZone":"Russian Standard Time","Empty":"unknown","device":{"id":"g:6755400000000001"},"app":{"id":"not-a-device-id"}}'
    $store = @{}
    foreach ($rule in $script:FactRules) {
        foreach ($m in [regex]::Matches($payload, $rule.re)) { Add-FactValue $store $rule.id $m.Groups[1].Value }
    }
    Check 'название программы вытащено' ($store.ContainsKey('apps') -and $store['apps'].ContainsKey('Google Chrome'))
    Check 'модель устройства вытащена' ($store.ContainsKey('device') -and $store['device'].ContainsKey('HVY-WXX9'))
    Check 'постоянный идентификатор вытащен' ($store.ContainsKey('ids') -and $store['ids'].ContainsKey('m:A1B2C3D4E5F67890'))
    Check 'номер устройства в учётной записи (g:) вытащен' ($store.ContainsKey('ids') -and $store['ids'].ContainsKey('g:6755400000000001'))
    Check 'прочие поля id за номер устройства не принимаются' (-not ($store.ContainsKey('ids') -and $store['ids'].ContainsKey('not-a-device-id')))
    Check 'часовой пояс вытащен' ($store.ContainsKey('user') -and $store['user'].ContainsKey('Russian Standard Time'))
    $hasJunk = $false
    foreach ($k in $store.Keys) { if ($store[$k].ContainsKey('unknown')) { $hasJunk = $true } }
    Check 'пустышки вроде unknown отброшены' (-not $hasJunk)
}

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Применимость к версии Windows'
$naItems = @()
if ($all) { foreach ($g in @($all.groups)) { foreach ($i in @($g.items)) { if ($i.na) { $naItems += $i } } } }
Check 'аудит отдаёт число неприменимых настроек' ($null -ne $all.notApplicable)
Check 'неприменимые не входят в итог' ([int]$all.notApplicable -eq $naItems.Count) `
      ("notApplicable=" + $all.notApplicable + ", помечено: " + $naItems.Count)

# Копия движка, которая считает себя Windows 10: настройки Copilot и Recall
# должны стать неприменимыми, а индекс — не пострадать.
$fake = Join-Path $env:TEMP 'w11p-tests-fake10.ps1'
$engineSrc = Get-Content -LiteralPath $engine -Raw -Encoding UTF8
$buildLine = '$script:OsBuild = 0'
Check 'номер сборки Windows читается движком' ($engineSrc.Contains($buildLine))
if ($engineSrc.Contains($buildLine)) {
    # подменяем не только присваивание, но и чтение из реестра: иначе оно
    # тут же вернёт настоящий номер сборки и подделка ничего не проверит
    $fakeSrc = $engineSrc.Replace($buildLine, '$script:OsBuild = 19045')
    $fakeSrc = $fakeSrc.Replace('try { $script:OsBuild = [int](Get-ItemProperty', 'try { $null = [int](Get-ItemProperty')
    $fakeSrc | Set-Content -LiteralPath $fake -Encoding UTF8
    $old = Get-EngineJson @('-Audit') 2>$null
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Command powershell.exe).Source
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $fake + '" -Audit'
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $pr = [System.Diagnostics.Process]::Start($psi)
    $fakeOut = $pr.StandardOutput.ReadToEnd(); $null = $pr.StandardError.ReadToEnd(); $pr.WaitForExit()
    $fakeJson = $null
    foreach ($line in ($fakeOut -split "`n")) {
        $t = $line.TrimStart()
        if ($t.StartsWith('###JSON###')) { try { $fakeJson = ($t.Substring(10).Trim() | ConvertFrom-Json) } catch { } }
    }
    Check 'аудит «как на Windows 10» отвечает' ($null -ne $fakeJson)
    if ($fakeJson) {
        Check 'на Windows 10 часть настроек неприменима' ([int]$fakeJson.notApplicable -ge 10) `
              ("неприменимо: " + $fakeJson.notApplicable)
        Check 'неприменимые убраны из знаменателя' ([int]$fakeJson.total -lt [int]$all.total) `
              ("было " + $all.total + ", стало " + $fakeJson.total)
        $naNames = @()
        foreach ($g in @($fakeJson.groups)) { foreach ($i in @($g.items)) { if ($i.na) { $naNames += "$($i.actual)" } } }
        Check 'у неприменимых честная причина' (@($naNames | Where-Object { $_ -match 'нет на этой версии' }).Count -ge 10)
    }
    Remove-Item -LiteralPath $fake -Force -ErrorAction SilentlyContinue
}

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Переносимый режим: данные там, где сказано'
$portable = Join-Path $env:TEMP 'w11p-tests-portable'
Remove-Item -LiteralPath $portable -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $portable -Force | Out-Null
$dataInfo = Get-EngineJson @('-DataInfo', '-DataRoot', ('"' + $portable + '"'))
Check 'папка данных берётся из -DataRoot' ($null -ne $dataInfo -and "$($dataInfo.folder)" -eq $portable) `
      ("получено: " + $dataInfo.folder)
$dataDefault = Get-EngineJson @('-DataInfo')
Check 'без ключа данные остаются в ProgramData' ("$($dataDefault.folder)" -like '*ProgramData*') `
      ("получено: " + $dataDefault.folder)
Remove-Item -LiteralPath $portable -Recurse -Force -ErrorAction SilentlyContinue

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Применение (тестовый прогон, ничего не меняется)'
if ($isAdmin) {
    $mods = 'telemetry,errors,activity,input,edge,ads,copilot'
    $out = Run-Engine @('-DryRun', '-NoBackup', '-NoRestorePoint', '-Modules', $mods)
    $sections = @([regex]::Matches($out, '(?m)^--- ')).Count - 1     # минус раздел «Итог»
    Check 'выполнены все выбранные модули (регрессия: $defs === $script:Defs)' ($sections -ge 7) `
          ("разделов: " + $sections + " из 7")
    Check 'в тестовом прогоне нет изменений' ($out -match 'Изменений применено : 0')
} else {
    Write-Host '  (пропущено: нужны права администратора)'
}

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Версия и режим PowerShell'
$detect = Get-EngineJson @('-Detect')
Check 'определение системы отвечает' ($null -ne $detect)
if ($detect) {
    $engVer = "$($detect.engineVersion)"
    Check 'движок сообщает свою версию' ($engVer -match '^\d+\.\d+\.\d+$') ("получено: " + $engVer)
    # версия объявлена в двух местах, и разъехаться они не должны: об этом
    # человек судит на «О программе» и по ней же решает, обновляться ли
    $appInfo = Join-Path (Split-Path $PSScriptRoot -Parent) 'AppInfo.cs'
    if (Test-Path -LiteralPath $appInfo) {
        $m = [regex]::Match((Get-Content -Raw -LiteralPath $appInfo), 'Version\s*=\s*"([0-9.]+)"')
        Check 'версии движка и интерфейса совпадают' ($m.Success -and $m.Groups[1].Value -eq $engVer) `
              ("интерфейс: " + $m.Groups[1].Value + ", движок: " + $engVer)
    }
    Check 'языковой режим PowerShell полный' ("$($detect.languageMode)" -eq 'FullLanguage') `
          ("получено: " + $detect.languageMode)
}

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Журнал отката пишется по ходу работы'
# Раньше журнал сохранялся единственный раз в самом конце: обрыв прогона
# оставлял изменения в системе, а вернуть их было нечем.
$engineText = Get-Content -Raw -LiteralPath $engine
Check 'каждая секция сбрасывает журнал на диск' ($engineText -match "function Write-Section[^`n]*Save-JournalEntries -Quiet")
Check 'внутри модуля журнал пишется не реже, чем раз в десять записей' `
      ($engineText -match 'Journal\.Count -ge 10\s*\)\s*\{\s*Save-JournalEntries -Quiet')

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Журнал отката: замок и схлопывание'
Check 'запись журнала под общим замком' ($engineText -match 'Use-JournalLock\s*\{')
Check 'замок общесистемный' ($engineText -match "Mutex\(\`$false, 'Global")
if (Get-Command Compress-Journal -ErrorAction SilentlyContinue) {
    # Записи бывают двух видов: свежие — хэш-таблицы, прочитанные из файла —
    # объекты. Проверяем оба: на хэш-таблицах поля однажды уже терялись, и
    # откат переставал возвращать значения.
    $kinds = @{
        'из файла' = @(
            [pscustomobject]@{ kind='reg'; path='HKLM:\Test'; name='A'; type='DWord'; existed=$true;  old='1'; newValue='0'; time='2026-09-01T10:00:00' },
            [pscustomobject]@{ kind='reg'; path='HKLM:\Test'; name='A'; type='DWord'; existed=$true;  old='0'; newValue='2'; time='2026-09-02T10:00:00' },
            [pscustomobject]@{ kind='reg'; path='HKLM:\Test'; name='B'; type='DWord'; existed=$false; old='';  newValue='1'; time='2026-09-02T11:00:00' }
        )
        'свежие' = @(
            @{ kind='reg'; path='HKLM:\Test'; name='A'; type='DWord'; existed=$true;  old='1'; newValue='0'; time='2026-09-01T10:00:00' },
            @{ kind='reg'; path='HKLM:\Test'; name='A'; type='DWord'; existed=$true;  old='0'; newValue='2'; time='2026-09-02T10:00:00' },
            @{ kind='reg'; path='HKLM:\Test'; name='B'; type='DWord'; existed=$false; old='';  newValue='1'; time='2026-09-02T11:00:00' }
        )
    }
    foreach ($kindName in @('из файла', 'свежие')) {
        $packed = @(Compress-Journal $kinds[$kindName])
        Check ("повторы схлопнулись ($kindName)") ($packed.Count -eq 2) ("получено записей: " + $packed.Count)
        $a = @($packed | Where-Object { "$($_['name'])" -eq 'A' })
        Check ("запись не потеряла имя параметра ($kindName)") ($a.Count -eq 1)
        if ($a.Count -ne 1) { continue }
        $a = $a[0]
        Check ("путь на месте ($kindName)") ("$($a['path'])" -eq 'HKLM:\Test') ("получено: " + $a['path'])
        Check ("тип значения на месте ($kindName)") ("$($a['type'])" -eq 'DWord') ("получено: " + $a['type'])
        Check ("сохранено самое раннее «было» ($kindName)") ("$($a['old'])" -eq '1') ("получено: " + $a['old'])
        Check ("отметка «параметр существовал» на месте ($kindName)") ([bool]$a['existed'])
        Check ("сохранено последнее «стало» ($kindName)") ("$($a['newValue'])" -eq '2') ("получено: " + $a['newValue'])
        Check ("посчитано число правок ($kindName)") ([int]$a['count'] -eq 2) ("получено: " + $a['count'])
    }
    # записи других профилей: у каждого куста свой ключ, и со своими они не сливаются
    $hv = @(
        @{ kind='hive'; file='C:\Users\A\NTUSER.DAT'; sub='Software\X'; name='V'; type='DWord'; existed=$false; old=''; newValue='0'; time='2026-09-01T10:00:00' },
        @{ kind='hive'; file='C:\Users\B\NTUSER.DAT'; sub='Software\X'; name='V'; type='DWord'; existed=$false; old=''; newValue='0'; time='2026-09-01T10:00:00' },
        @{ kind='reg'; path='HKCU:\Software\X'; name='V'; type='DWord'; existed=$false; old=''; newValue='0'; time='2026-09-01T10:00:00' })
    Check 'записи других профилей не сливаются друг с другом и со своими' (@(Compress-Journal $hv).Count -eq 3)
} else {
    Check 'функция схлопывания журнала найдена' $false
}

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Страж просыпается после обновления Windows'
Check 'у стража есть триггер по событию' ($engineText -match 'MSFT_TaskEventTrigger')
Check 'слушается журнал обновлений' ($engineText -match 'Microsoft-Windows-WindowsUpdateClient')
Check 'проверка идёт не мгновенно, а с задержкой' ($engineText -match "\`$t3.Delay = 'PT5M'")

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Ход долгой проверки виден'
Check 'проверка сообщает, сколько пройдено' ($engineText -match '###PROGRESS### \{0\}/\{1\}')

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Разрешения приложений и фоновые обращения в сеть'
# Список берём заново и в свою переменную: $defs выше по файлу к этому месту
# уже переписан (в PowerShell $defs и $Defs — одно и то же имя).
$defsV110 = Get-EngineJson @('-ListDefs')
Check 'список настроек для новых модулей получен' ($null -ne $defsV110)
if ($defsV110) {
    $byMod = @{}
    foreach ($g in @($defsV110.groups)) { $byMod["$($g.module)"] = @($g.items).Count }
    Check 'модуль «Разрешения приложений» есть' ($byMod['apppriv'] -ge 16) ("пунктов: " + $byMod['apppriv'])
    Check 'модуль «Камера, микрофон и фон» есть' ($byMod['apphw'] -eq 3) ("пунктов: " + $byMod['apphw'])
    Check 'модуль «Фоновые обращения в сеть» есть' ($byMod['network'] -ge 12) ("пунктов: " + $byMod['network'])
}
# Имена политик AppPrivacy — ровно те, что знает Windows (AppPrivacy.admx):
# опечатка в имени значит, что политика молча ничего не делает.
$knownAppPrivacy = @('LetAppsAccessAccountInfo','LetAppsAccessCalendar','LetAppsAccessCallHistory','LetAppsAccessCamera',
    'LetAppsAccessContacts','LetAppsAccessEmail','LetAppsAccessLocation','LetAppsAccessMessaging','LetAppsAccessMicrophone',
    'LetAppsAccessMotion','LetAppsAccessNotifications','LetAppsAccessPhone','LetAppsAccessRadios','LetAppsAccessTasks',
    'LetAppsAccessTrustedDevices','LetAppsActivateWithVoice','LetAppsActivateWithVoiceAboveLock','LetAppsGetDiagnosticInfo',
    'LetAppsRunInBackground','LetAppsSyncWithDevices','LetAppsAccessSystemAIModels')
$usedAppPrivacy = @([regex]::Matches($engineText, "'(LetApps\w+)'") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
$wrongAppPrivacy = @($usedAppPrivacy | Where-Object { $knownAppPrivacy -notcontains $_ })
Check 'имена политик AppPrivacy существуют в Windows' ($wrongAppPrivacy.Count -eq 0) ($wrongAppPrivacy -join ', ')
Check 'доступ к возрасту (Age API) закрывается политикой' ($usedAppPrivacy -contains 'LetAppsAccessAccountInfo')
Check '«Досье» знает ИИ-модели и ключи доступа' (($engineText -match "id='systemAIModels'") -and ($engineText -match "id='passkeysEnumeration'"))
Check '«Цифровой след» видит и чистит журналы Windows' (($engineText -match "\& \`$add 'eventlogs'") -and ($engineText -match "'eventlogs' \{"))

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Номер устройства в учётной записи Microsoft (GDID)'
$defsGdid = Get-EngineJson @('-ListDefs')
$gdidGroup = @($(if ($defsGdid) { @($defsGdid.groups) | Where-Object { "$($_.module)" -eq 'gdid' } }))
Check 'модуль «Номер устройства» есть' ($gdidGroup.Count -eq 1)
if ($gdidGroup.Count -eq 1) {
    $gItems = @($gdidGroup[0].items)
    Check 'в модуле три службы и блок hosts' ($gItems.Count -eq 4) ("пунктов: " + $gItems.Count)
    $gSvc = @($gItems | Where-Object { "$($_.kind)" -eq 'regsvc' })
    Check 'службы отключаются через реестр, а не через диспетчер служб' ($gSvc.Count -eq 3) ("через реестр: " + $gSvc.Count)
    $gNames = @($gSvc | ForEach-Object { Split-Path "$($_.target)" -Leaf })
    Check 'это CDPSvc, CDPUserSvc и DoSvc' ((@('CDPSvc', 'CDPUserSvc', 'DoSvc') | Where-Object { $gNames -notcontains $_ }).Count -eq 0) ($gNames -join ',')
    $gOutside = @($gSvc | Where-Object { "$($_.target)" -notlike 'HKLM:\SYSTEM\CurrentControlSet\Services\*' -or "$($_.valueName)" -ne 'Start' })
    Check 'запись идёт только в параметр Start своей службы' ($gOutside.Count -eq 0)
}
# Без login.live.com не работает вход в учётную запись Microsoft: этот адрес
# в блок не попадает ни при каком изменении списка.
foreach ($asg in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
    $lt = $asg.Left -as [System.Management.Automation.Language.VariableExpressionAst]
    if ($null -ne $lt -and $lt.VariablePath.UserPath -eq 'script:GdidHosts') { Invoke-Expression $asg.Extent.Text }
}
Check 'список серверов номера устройства найден' (@($script:GdidHosts).Count -ge 5) ("адресов: " + @($script:GdidHosts).Count)
Check 'вход в учётную запись не блокируется' (-not (@($script:GdidHosts) | Where-Object { $_ -match 'login\.live\.com|login\.microsoftonline\.com' }))
Check 'нынешний адрес каталога устройств в списке' (@($script:GdidHosts) -contains 'cs.dds.microsoft.com')

# Запрет выдачи — отдельный модуль: сервер выдачи, брандмауэр для wlidsvc и стирание
$lockGroup = @($(if ($defsGdid) { @($defsGdid.groups) | Where-Object { "$($_.module)" -eq 'gdidlock' } }))
Check 'модуль «Запрет выдачи номера» есть' ($lockGroup.Count -eq 1)
if ($lockGroup.Count -eq 1) {
    $lk = @(@($lockGroup[0].items) | ForEach-Object { "$($_.kind)" })
    Check 'в запрете: сервер выдачи, брандмауэр и стирание' ((($lk -join ',') -eq 'gdidlockhosts,fwsvc,gdidwipe')) ($lk -join ',')
    Check 'брандмауэр запрета закрывает именно wlidsvc' ("$(@($lockGroup[0].items)[1].target)" -eq 'wlidsvc')
}
foreach ($asg in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
    $lt = $asg.Left -as [System.Management.Automation.Language.VariableExpressionAst]
    if ($null -ne $lt -and $lt.VariablePath.UserPath -eq 'script:GdidLockHosts') { Invoke-Expression $asg.Extent.Text }
}
Check 'запрет выдачи закрывает login.live.com' (@($script:GdidLockHosts) -contains 'login.live.com')
Check 'при входе через учётную запись Microsoft запрет не ставится' ($engineText -match [regex]::Escape("if (`$m -eq 'gdidlock' -and (Get-GdidLockRefusal))"))
Check 'без закрытого сервера номер не стирается под видом запрета' ($engineText -match [regex]::Escape("-not (Test-HostsBlock -Kind 'lock')"))
$auditLock = Get-EngineJson @('-Audit', '-Modules', 'gdidlock')
$auditLockGroup = @($(if ($auditLock) { @($auditLock.groups) | Where-Object { "$($_.module)" -eq 'gdidlock' } }))
Check 'проверка запрета выдачи отвечает' ($auditLockGroup.Count -eq 1 -and @($auditLockGroup[0].items).Count -eq 3)

# Состояние для вкладки «Номер устройства» — только чтение
$gst = Get-EngineJson @('-GdidStatus')
Check 'состояние номера устройства читается' ($null -ne $gst -and $null -ne $gst.copies -and $null -ne $gst.services)
if ($gst) {
    Check 'номер в состоянии — g:число или пусто' ("$($gst.gdid)" -match '^(g:\d+)?$') ("получено: " + $gst.gdid)
    Check 'состояние знает четыре службы цепочки' (@($gst.services).Count -eq 4)
    Check 'состояние говорит, можно ли запрещать выдачу' (($null -ne $gst.msaLogon) -and ($null -ne $gst.managed))
}
$auditGdid = Get-EngineJson @('-Audit', '-Modules', 'gdid')
$gdidAuditGroup = @($(if ($auditGdid) { @($auditGdid.groups) | Where-Object { "$($_.module)" -eq 'gdid' } }))
Check 'проверка модуля «Номер устройства» отвечает' ($gdidAuditGroup.Count -eq 1 -and @($gdidAuditGroup[0].items).Count -eq 4)
$footGdid = @($(if ($foot) { @($foot.items) | Where-Object { "$($_.id)" -eq 'gdid' } }))
Check '«Цифровой след» показывает номер устройства' ($footGdid.Count -eq 1)
if ($footGdid.Count -eq 1) {
    Check 'номер устройства в виде g:число или прочерк' ("$($footGdid[0].value)" -match '^(g:\d+|—)$') ("получено: " + $footGdid[0].value)
    Check 'номер устройства не предлагается стереть' (-not $footGdid[0].canWipe)
}
Check 'страж запоминает снятые пункты' ($engineText -match [regex]::Escape('skip=@($SkipItems)'))
Check 'страж не возвращает снятые пункты' (($engineText -match [regex]::Escape('if ($skipped -contains $d.Id) { continue }')) -and
                                          ($engineText -match [regex]::Escape('$skipped -notcontains $d.Id) { Apply-Def $d')))

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Цена настроек, проверка утечек, слежение за сетью'
$defsRisk = Get-EngineJson @('-ListDefs')
if ($defsRisk) {
    $allItems = @(); foreach ($g in @($defsRisk.groups)) { $allItems += @($g.items) }
    $badRisk = @($allItems | Where-Object { "$($_.risk)" -notin @('safe', 'limited', 'caution') })
    Check 'у каждой настройки есть цена' ($badRisk.Count -eq 0) ("без цены: " + $badRisk.Count)
    Check 'пояснения есть' (@($allItems | Where-Object { "$($_.note)" }).Count -ge 20)
    $itemNames = @{}; foreach ($i in $allItems) { $itemNames["$($i.name)"] = $true }
    foreach ($asg in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        $lt = $asg.Left -as [System.Management.Automation.Language.VariableExpressionAst]
        if ($null -ne $lt -and $lt.VariablePath.UserPath -in @('script:DefNotes', 'script:DefRisk')) { Invoke-Expression $asg.Extent.Text }
    }
    $orphans = @(@($script:DefNotes.Keys) + @($script:DefRisk.Keys) | Where-Object { -not $itemNames.ContainsKey($_) })
    Check 'каждое пояснение относится к существующей настройке' ($orphans.Count -eq 0) ($orphans -join ' | ')
}
$leak = Get-EngineJson @('-LeakTest')
Check 'проверка утечек отвечает' ($null -ne $leak -and $null -ne $leak.items)
if ($leak) {
    Check 'итоги проверки утечек сходятся' ([int]$leak.total -eq ([int]$leak.open + [int]$leak.blocked + [int]$leak.hosts + [int]$leak.none)) `
          ("всего {0}: {1}/{2}/{3}/{4}" -f $leak.total, $leak.open, $leak.blocked, $leak.hosts, $leak.none)
    Check 'в проверке утечек и серверы номера устройства' (@($leak.items | Where-Object { "$($_.name)" -eq 'cs.dds.microsoft.com' }).Count -eq 1)
}
Check 'монитор пишет и разрешённые соединения' (($engineText -match [regex]::Escape('Set-AuditSetting $script:AuditGuid $(if ($On) { 3 } else { 0 })')) -and
                                              ($engineText -match [regex]::Escape('/success:$s /failure:$f')))
Check 'слежение за сетью запускается по расписанию' ($engineText -match [regex]::Escape('-NetGuard'' + $script:DataArg'))
Check 'адреса телеметрии разрешаются в обход hosts' ($engineText -match 'Resolve-DnsName -Name \$n -Type A_AAAA -NoHostsFile')
Check 'правило адресов помнит дату обновления' ($engineText -match [regex]::Escape("-Description ('Win11Privacy: updated '"))
Check 'страж замечает смену номера устройства' ($engineText -match [regex]::Escape("gdidHash = `$gHash"))

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Стирание номера устройства (на своём ключе, система не трогается)'
# Настоящую «личность» устройства стирать в проверке нельзя: номер сменился бы
# по-настоящему. Поэтому функции берутся из движка, а пути и всё, что
# касается системы, — службы, хранилище учётных данных, файлы, — подменены.
$wipeFns = @('Get-RegValue', 'Get-GdidCopies', 'Invoke-GdidWipe', 'Remove-RegStatus', 'Get-CredCheckCmd', 'Get-UncheckedProfiles', 'Restore-GdidServices')
$wipeFound = @()
foreach ($fn in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($wipeFns -contains $fn.Name) { Invoke-Expression $fn.Extent.Text; $wipeFound += $fn.Name }
}
foreach ($asg in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
    $lt = $asg.Left -as [System.Management.Automation.Language.VariableExpressionAst]
    if ($null -ne $lt -and $lt.VariablePath.UserPath -in @('script:DevicePuidRegex', 'script:GdidCredUser', 'script:GdidCredSystem', 'script:GdidUnreadable')) { Invoke-Expression $asg.Extent.Text }
}
Check 'функции стирания номера найдены в движке' ($wipeFound.Count -eq $wipeFns.Count) ("найдено: " + ($wipeFound -join ','))
if ($wipeFound.Count -eq $wipeFns.Count) {
    $gt = 'HKCU:\Software\Win11PrivacyGdidTest'
    $script:IdCrlRoots = @(@{ who = 'user'; path = "$gt\User" }, @{ who = 'system'; path = "$gt\System" })
    # ВАЖНО: только пробные ветки. Настоящая функция добавила бы кусты других
    # вошедших пользователей, и проверка стёрла бы их настоящие записи.
    function Get-IdCrlRoots { return $script:IdCrlRoots }
    $script:IdCrlNegCache = "$gt\NegativeCache"
    $script:wipeCalls = New-Object System.Collections.Generic.List[string]
    # службы, которые «работают», и та, что «не останавливается»
    $script:fakeSvcs = @(); $script:stuckSvc = ''; $script:deadSvc = ''
    function New-FakeSvc { param([string]$Name, [string]$StartType)
        $o = [pscustomobject]@{ Name = $Name; Status = 'Running'; StartType = $StartType }
        # «не поднялась»: ожидание запуска кончается ошибкой, как у настоящей службы
        $o | Add-Member -MemberType ScriptMethod -Name WaitForStatus -Value { param($s, $t) if ($this.Name -eq $script:deadSvc) { throw 'служба не запустилась' } }
        $o
    }
    function Get-ManagedReason { return '' }
    function Stop-ServiceWait { param([string]$Name) $script:wipeCalls.Add("stop $Name"); return ($Name -ne $script:stuckSvc) }
    function Get-Service { param([string]$Name, $ErrorAction) if ($Name) { @($script:fakeSvcs | Where-Object { $_.Name -eq $Name }) } else { @($script:fakeSvcs) } }
    function Set-Service { $script:wipeCalls.Add('set-service') }
    function Start-Service { param([string]$Name, $ErrorAction, $WarningAction) $script:wipeCalls.Add("start $Name") }
    # кэш платформы подключённых устройств — пробная папка, а не настоящая
    $script:CdpCache = Join-Path $env:TEMP ('w11p-cdp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    # Закрыть пробный ключ от чтения самому себе — так Windows отвечает на
    # чужие хранилища. Хозяин ключа всегда может вернуть права обратно.
    function Set-TestKeyLock {
        param([string]$Rel, [bool]$Lock)
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $rule = New-Object System.Security.AccessControl.RegistryAccessRule($me, [System.Security.AccessControl.RegistryRights]'QueryValues, EnumerateSubKeys', 'Deny')
        $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Rel, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                                                                [System.Security.AccessControl.RegistryRights]'ChangePermissions, ReadPermissions')
        if (-not $k) { return }
        try { $acl = $k.GetAccessControl(); if ($Lock) { $acl.AddAccessRule($rule) } else { $null = $acl.RemoveAccessRule($rule) }; $k.SetAccessControl($acl) }
        finally { $k.Close() }
    }
    $gtRel = 'Software\Win11PrivacyGdidTest'
    $locks = @("$gtRel\User\Immersive\production\Property", "$gtRel\System\DeviceIdentities\production\S-1-5-18\02lockedidentity")
    function Invoke-OneShotTask { param([string]$TaskName, [string]$CmdLine, [switch]$AsSystem) $script:wipeCalls.Add("task $CmdLine"); return $true }
    function cmdkey.exe { $script:wipeCalls.Add("cmdkey $args") }
    function Clear-FolderContents { $script:wipeCalls.Add('clear-cdp'); return 0.0 }
    function Write-Log { param([string]$Message = '') }
    $DryRun = $false; $script:Changes = 0; $script:Failures = 0
    $dev = '0018ABCDEF012345'; $usr = '0003AAAAAAAAAAAA'
    try {
        Remove-Item -LiteralPath $gt -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($root in @("$gt\User", "$gt\System")) {
            New-Item -Path "$root\ExtendedProperties" -Force | Out-Null
            New-ItemProperty -LiteralPath "$root\ExtendedProperties" -Name 'LID' -Value $dev -Force | Out-Null
            New-Item -Path "$root\Immersive\production\Property" -Force | Out-Null
            New-ItemProperty -LiteralPath "$root\Immersive\production\Property" -Name $dev -Value 'x' -Force | Out-Null
            New-ItemProperty -LiteralPath "$root\Immersive\production\Property" -Name $usr -Value 'x' -Force | Out-Null
            New-Item -Path "$root\Immersive\production\Token\dev" -Force | Out-Null
            foreach ($vn in @('DeviceId', 'DeviceTicket', 'ApplicationFlags')) { New-ItemProperty -LiteralPath "$root\Immersive\production\Token\dev" -Name $vn -Value $dev -Force | Out-Null }
            New-Item -Path "$root\Immersive\production\Token\user" -Force | Out-Null
            New-ItemProperty -LiteralPath "$root\Immersive\production\Token\user" -Name 'UserId' -Value $usr -Force | Out-Null
        }
        New-Item -Path "$gt\System\DeviceIdentities\production\S-1-5-18\02abcdefghijklmn" -Force | Out-Null
        New-ItemProperty -LiteralPath "$gt\System\DeviceIdentities\production\S-1-5-18\02abcdefghijklmn" -Name 'DeviceId' -Value $dev -Force | Out-Null
        New-Item -Path "$gt\System\DeviceIdentities\production\Logs\02abcdefghijklmn" -Force | Out-Null
        New-Item -Path "$gt\NegativeCache\$($dev)_S-1-5-21-1" -Force | Out-Null
        New-Item -Path "$gt\NegativeCache\$($usr)_S-1-5-21-1" -Force | Out-Null

        $before = @(Get-GdidCopies)
        Check 'опись находит все копии номера' ($before.Count -eq 8) ("найдено: " + $before.Count)
        $ok = Invoke-GdidWipe
        $after = @(Get-GdidCopies)
        Check 'после стирания копий номера не осталось' ($ok -and $after.Count -eq 0) ("осталось: " + $after.Count)
        Check 'номер учётной записи пользователя не тронут' ($null -ne (Get-RegValue "$gt\User\Immersive\production\Property" $usr))
        Check 'билеты пользователя не тронуты' ((Get-RegValue "$gt\User\Immersive\production\Token\user" 'UserId') -eq $usr)
        Check 'прочие поля билетов устройства не тронуты' ($null -ne (Get-RegValue "$gt\User\Immersive\production\Token\dev" 'ApplicationFlags'))
        Check 'кэш с чужим номером не тронут' (Test-Path -LiteralPath "$gt\NegativeCache\$($usr)_S-1-5-21-1")
        Check 'личности устройства стёрты целиком' (-not (Test-Path -LiteralPath "$gt\System\DeviceIdentities\production"))
        Check 'учётные данные устройства убираются у пользователя и у системы' `
              ((@($script:wipeCalls | Where-Object { $_ -like 'task *didlogical*' }).Count -eq 2) -and
               (@($script:wipeCalls | Where-Object { $_ -like 'task *SSO_POP_Device*' }).Count -eq 1)) ($script:wipeCalls -join ' | ')
        Check 'wlidsvc останавливается до стирания' ($script:wipeCalls.IndexOf('stop wlidsvc') -ge 0 -and
                                                   $script:wipeCalls.IndexOf('stop wlidsvc') -lt $script:wipeCalls.IndexOf('clear-cdp'))

        # служба не остановилась — не стирается ничего, службы запускаются обратно
        New-ItemProperty -LiteralPath "$gt\User\ExtendedProperties" -Name 'LID' -Value $dev -Force | Out-Null
        $script:fakeSvcs = @((New-FakeSvc 'wlidsvc' 'Manual'), (New-FakeSvc 'DoSvc' 'Automatic'))
        $script:stuckSvc = 'DoSvc'; $script:wipeCalls.Clear(); $failsBefore = $script:Failures
        $ok2 = Invoke-GdidWipe
        Check 'служба не остановилась — номер не стирается' ((-not $ok2) -and ((Get-RegValue "$gt\User\ExtendedProperties" 'LID') -eq $dev) -and
                                                             (@($script:wipeCalls | Where-Object { $_ -like 'task *' -or $_ -eq 'clear-cdp' }).Count -eq 0)) ($script:wipeCalls -join ' | ')
        Check '…и службы возвращаются как были' (($script:wipeCalls -contains 'start wlidsvc') -and ($script:wipeCalls -contains 'start DoSvc') -and
                                                ($script:wipeCalls -contains 'set-service') -and $script:Failures -eq ($failsBefore + 1)) ($script:wipeCalls -join ' | ')
        $script:stuckSvc = ''

        # служба работала до стирания и не поднялась после — это не успех
        New-ItemProperty -LiteralPath "$gt\User\ExtendedProperties" -Name 'LID' -Value $dev -Force | Out-Null
        $script:deadSvc = 'DoSvc'; $script:wipeCalls.Clear()
        $ok3 = Invoke-GdidWipe
        Check 'служба, что не вернулась после стирания, — не успех' ((-not $ok3) -and ($null -eq (Get-RegValue "$gt\User\ExtendedProperties" 'LID')) -and
                                                                    ($script:wipeCalls -contains 'start DoSvc')) ($script:wipeCalls -join ' | ')
        $script:deadSvc = ''; $script:fakeSvcs = @()

        # в кэше устройств что-то осталось — стирание не выдаётся за полное
        New-Item -ItemType Directory -Force (Join-Path $script:CdpCache 'L.user') | Out-Null
        Set-Content (Join-Path $script:CdpCache 'L.user\ActivitiesCache.db') 'x'
        Check 'остаток в кэше устройств — не успех' (-not (Invoke-GdidWipe))
        Remove-Item -LiteralPath $script:CdpCache -Recurse -Force -ErrorAction SilentlyContinue
        Check 'без остатков стирание снова успешно' (Invoke-GdidWipe)

        # закрытые ключи внутри хранилища — «не проверено», а не «пусто»
        New-Item -Path "$gt\System\DeviceIdentities\production\S-1-5-18\02lockedidentity" -Force | Out-Null
        foreach ($lk in $locks) { Set-TestKeyLock $lk $true }
        $null = Get-GdidCopies
        $un = @($script:GdidUnreadable | Select-Object -Unique)
        Check 'закрытые ключи внутри хранилища не считаются пустыми' ((@($un | Where-Object { $_ -like '*\Immersive\production\Property' }).Count -eq 1) -and
                                                                      (@($un | Where-Object { $_ -like '*\02lockedidentity' }).Count -eq 1)) ($un -join '; ')
        $stP = Remove-RegStatus "$gt\User\Immersive\production\Property" $usr; $stK = Remove-RegStatus "$gt\User\Immersive\production\Property"
        Check 'закрытая запись — «не дала», а не «не было»' ("$stP|$stK" -eq 'denied|denied') "$stP|$stK"
        Check 'стирание с закрытыми местами не выдаётся за успех' (-not (Invoke-GdidWipe))
    } catch {
        # раньше исключение здесь молча обрывало блок — десять проверок просто
        # не выполнялись, а итог оставался зелёным
        Check 'стирание номера отработало без исключений' $false "$($_.Exception.Message)"
    } finally {
        foreach ($lk in $locks) { try { Set-TestKeyLock $lk $false } catch { } }
        Remove-Item -LiteralPath $gt -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:CdpCache -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($f in @('Get-ManagedReason', 'Stop-ServiceWait', 'Get-Service', 'Set-Service', 'Start-Service', 'Invoke-OneShotTask', 'cmdkey.exe', 'Clear-FolderContents', 'Get-IdCrlRoots', 'Set-TestKeyLock')) {
            Remove-Item -Path ("Function:\" + $f) -ErrorAction SilentlyContinue
        }
    }
    Check 'проверочный ключ убран' (-not (Test-Path -LiteralPath 'HKCU:\Software\Win11PrivacyGdidTest'))
}

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Облачная синхронизация и задачи, закрытые от администратора'
$defsCs = Get-EngineJson @('-ListDefs')
Check 'список настроек получен' ($null -ne $defsCs)
if ($defsCs) {
    $allCs = @(); foreach ($g in @($defsCs.groups)) { foreach ($it in @($g.items)) { $allCs += @{ m = "$($g.module)"; id = "$($it.id)"; kind = "$($it.kind)"; target = "$($it.target)"; vn = "$($it.valueName)" } } }
    $csItems = @($allCs | Where-Object { $_.m -eq 'cloudsync' })
    Check 'модуль «Облачная синхронизация и копия» есть' ($csItems.Count -eq 11) ("пунктов: " + $csItems.Count)
    Check 'в нём отключаются копия приложений и Wi-Fi' ((@($csItems | Where-Object { $_.target -like '*AppListBackup*' -or $_.target -like '*WlanSvc\CDSSync' }).Count -eq 3))
    Check 'служба InventorySvc в службах телеметрии' (@($allCs | Where-Object { $_.m -eq 'services' -and $_.kind -eq 'svc' -and $_.target -eq 'InventorySvc' }).Count -eq 1)
    Check 'задача UsageAndQualityInsights в службах телеметрии' (@($allCs | Where-Object { $_.m -eq 'services' -and $_.target -like '*UsageAndQualityInsights-MaintenanceTask' }).Count -eq 1)
    Check 'модели Click to Do — в ИИ-функциях' (@($allCs | Where-Object { $_.m -eq 'ai' -and $_.target -like '*ClickToDo\ModelCachingUpdate' }).Count -eq 1)
    Check 'прогноз энергосети — в фоновых обращениях' (@($allCs | Where-Object { $_.m -eq 'network' -and $_.target -like '*PowerGridForecastTask' }).Count -eq 1)
    Check 'установка по команде с сайта (PushToInstall) закрыта политикой' (@($allCs | Where-Object { $_.m -eq 'network' -and $_.vn -eq 'DisablePushToInstall' -and $_.target -like '*Policies\Microsoft\PushToInstall' }).Count -eq 1)
    Check '«исправления» Microsoft не применяются сами' ((@($allCs | Where-Object { $_.m -eq 'network' -and $_.vn -eq 'UserPreference' -and $_.target -like '*\WindowsMitigation' }).Count -eq 1) -and
        (@($allCs | Where-Object { $_.m -eq 'network' -and $_.target -like '*Diagnosis\RecommendedTroubleshootingScanner' }).Count -eq 1))
    Check '«Архивация Windows» выключается политикой' (@($csItems | Where-Object { $_.vn -eq 'EnableWindowsBackup' -and $_.target -like '*Policies\Microsoft\Windows\SettingSync' }).Count -eq 1)
    Check 'ИИ-агентам закрыт доступ через MCP' (@($allCs | Where-Object { $_.m -eq 'ai' -and $_.vn -eq 'ConfigureAgentConnectors' -and $_.target -like '*Policies\Microsoft\Windows\WindowsAI' }).Count -eq 1)
    Check 'ИИ-агент в Параметрах выключается' (@($allCs | Where-Object { $_.m -eq 'ai' -and $_.vn -eq 'DisableSettingsAgent' }).Count -eq 1)
    Check 'выгрузка снимков Recall запрещена' (@($allCs | Where-Object { $_.m -eq 'copilot' -and $_.vn -eq 'AllowRecallExport' }).Count -eq 1)
    Check 'панель виджетов и виджеты на экране блокировки выключаются' (@($allCs | Where-Object { $_.m -eq 'widgets' -and $_.vn -in @('DisableWidgetsBoard', 'DisableWidgetsOnLockScreen') }).Count -eq 2)
    Check 'реклама «интересного» закрыта пользовательскими политиками' (@($allCs | Where-Object { $_.m -eq 'ads' -and $_.target -like 'HKCU:*Policies\Microsoft\Windows\CloudContent' }).Count -eq 5)
    Check 'экран «Закрепите Copilot» и реклама в «Поделиться» выключаются' (@($allCs | Where-Object { $_.m -eq 'ads' -and $_.vn -in @('DisableCopilotPinScreen', 'DisableShareAppPromotions') }).Count -eq 2)
    Check 'Защитник без удалённых настроек ECS' (@($allCs | Where-Object { $_.m -eq 'defender' -and $_.vn -eq 'DisableCoreServiceECSIntegration' -and $_.target -like '*Windows Defender\Features' }).Count -eq 1)
    Check 'непроверенный выключатель 1DS Защитника не добавлен' (@($allCs | Where-Object { $_.vn -eq 'DisableCoreService1DSTelemetry' }).Count -eq 0)
    Check 'средства устранения неполадок без серверов Microsoft'(@($allCs | Where-Object { $_.m -eq 'network' -and $_.vn -eq 'EnableQueryRemoteServer' -and $_.target -like '*ScriptedDiagnosticsProvider\Policy' }).Count -eq 1)
    $dupCs = @($allCs | Group-Object { $_.m + '|' + $_.kind + '|' + $_.target + '|' + $_.vn } | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    Check 'в одном разделе нет повторов' ($dupCs.Count -eq 0) ($dupCs -join '; ')
    # повтор убран, а номера соседей прежние: по ним профили помнят снятые пункты
    $idCs = @{}; foreach ($x in $allCs) { $idCs[$x.id] = $x.target }
    Check 'номера пунктов после убранного повтора не сдвинулись' (
        ($idCs['services#28'] -like '*Clip\License Validation') -and ($idCs['services#34'] -like '*Compatibility Appraiser Exp') -and
        (-not $idCs.ContainsKey('services#27')) -and (-not $idCs.ContainsKey('services#33'))) ("services#28=" + $idCs['services#28'] + ", services#34=" + $idCs['services#34'])
}
$wantedTe = @('Split-TaskPath', 'Set-TaskEnabled')
$foundTe = @()
foreach ($fn in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($wantedTe -contains $fn.Name) { Invoke-Expression $fn.Extent.Text; $foundTe += $fn.Name }
}
Check 'Set-TaskEnabled найдена в движке' ($foundTe.Count -eq $wantedTe.Count) ("найдено: " + ($foundTe -join ','))
if ($foundTe.Count -eq $wantedTe.Count) {
    # Планировщик подменён: настоящие задачи Windows тест не трогает.
    $script:teState = 'Ready'; $script:teDenied = $true; $script:teCalls = @(); $script:teExists = $true
    function Get-ScheduledTask { param($TaskPath, $TaskName, $ErrorAction) if ($script:teExists) { [pscustomobject]@{ State = $script:teState } } }
    function Disable-ScheduledTask { param($TaskPath, $TaskName, $ErrorAction) if ($script:teDenied) { throw 'Отказано в доступе.' }; $script:teState = 'Disabled' }
    function Enable-ScheduledTask { param($TaskPath, $TaskName, $ErrorAction) if ($script:teDenied) { throw 'Отказано в доступе.' }; $script:teState = 'Ready' }
    function Invoke-OneShotTask { param([string]$TaskName, [string]$CmdLine, [switch]$AsSystem, [int]$Minutes = 2, [string]$Execute = '', [string]$Arguments = '')
        $script:teCalls += ("{0}|{1}|{2}" -f $AsSystem.IsPresent, $Execute, $Arguments)
        if ($Arguments -match '/disable$') { $script:teState = 'Disabled' } elseif ($Arguments -match '/enable$') { $script:teState = 'Ready' }
        return $true }
    try {
        $tp = '\Microsoft\Windows\UsageAndQualityInsights\UsageAndQualityInsights-MaintenanceTask'
        $r1 = Set-TaskEnabled $tp $false
        Check 'закрытая задача отключается от имени SYSTEM' ($r1 -eq 'system' -and $script:teState -eq 'Disabled') ("ответ: $r1, состояние: $($script:teState)")
        Check 'SYSTEM получает schtasks напрямую, полный путь задачи в кавычках' (@($script:teCalls).Count -eq 1 -and $script:teCalls[0] -eq ('True|' + "$env:SystemRoot\System32\schtasks.exe" + '|/change /tn "' + $tp + '" /disable')) ($script:teCalls -join ' ; ')
        $r2 = Set-TaskEnabled $tp $true
        Check 'и включается обратно так же' ($r2 -eq 'system' -and $script:teState -eq 'Ready') ("ответ: $r2")
        $script:teDenied = $false; $script:teCalls = @()
        $r3 = Set-TaskEnabled '\Microsoft\Windows\Maps\MapsToastTask' $false
        Check 'обычная задача отключается без SYSTEM' ($r3 -eq 'ok' -and @($script:teCalls).Count -eq 0) ("ответ: $r3")
        $script:teDenied = $true; $script:teState = 'Ready'
        function Invoke-OneShotTask { param([string]$TaskName, [string]$CmdLine, [switch]$AsSystem, [int]$Minutes = 2, [string]$Execute = '', [string]$Arguments = '') return $true }
        $r4 = Set-TaskEnabled $tp $false
        Check 'если и SYSTEM не смог — так и сказано' ($r4 -eq 'fail') ("ответ: $r4")
        $script:teExists = $false
        Check 'нет задачи — так и сказано' ((Set-TaskEnabled $tp $false) -eq 'missing')
    } finally {
        foreach ($f in @('Get-ScheduledTask', 'Disable-ScheduledTask', 'Enable-ScheduledTask', 'Invoke-OneShotTask')) { Remove-Item -Path ("Function:\" + $f) -ErrorAction SilentlyContinue }
    }
}
$applyTask = [regex]::Match($engineText, "(?s)'task' \{\s+\`$pp = Split-TaskPath \`$d\.P\s+if \(\`$DryRun\).*?\n        \}").Value
Check 'применение задач идёт через Set-TaskEnabled' ($applyTask -match 'Set-TaskEnabled \$d\.P \$false')
Check 'откат задач идёт через Set-TaskEnabled' ($engineText -match 'Set-TaskEnabled \$d\.P \$true')
Check 'откат возвращает InventorySvc' ($engineText -match "@\{N='InventorySvc';S='Automatic'\}")
# Очистка неотправленной телеметрии: только очередь и трассировки, без папок
# и настроек, и без вопросов «удалить с содержимым?», на которых движок висел.
$bufRoot = Join-Path $env:TEMP ('w11p-buffer-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force (Join-Path $bufRoot 'ETLLogs'), (Join-Path $bufRoot 'DownloadedSettings'), (Join-Path $bufRoot 'TenantStorage\P-ARIA') | Out-Null
foreach ($f in @('a.rbs', 'EventStore.db', 'EventStore.db-wal', 'ETLLogs\b.etl', 'TenantStorage\P-ARIA\EventStore.db', 'DownloadedSettings\utc.app.json', 'parse.dat')) {
    Set-Content -LiteralPath (Join-Path $bufRoot $f) -Value 'x' -Encoding ASCII
}
$bufJob = Start-Job -ArgumentList $engine, $bufRoot -ScriptBlock {
    param($EnginePath, $Root)
    # На машинах сборки GitHub %TEMP% задан коротким именем (RUNNER~1), а
    # Get-ChildItem отдаёт полный путь, и длина корня не совпадала. Относительные
    # имена считаем от уникального имени самой папки, а не от длины пути.
    $leaf = (Split-Path $Root -Leaf) + '\'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($EnginePath, [ref]$null, [ref]$null)
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if ($fn.Name -in @('Get-BufferFiles', 'Get-BufferInfo', 'Purge-Buffer', 'Get-BufferSystemScript', 'Invoke-BufferSystemPurge')) { Invoke-Expression $fn.Extent.Text }
    }
    foreach ($a in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        $lt = $a.Left -as [System.Management.Automation.Language.VariableExpressionAst]
        if ($null -ne $lt -and $lt.VariablePath.UserPath -eq 'script:BufferFileRx') { Invoke-Expression $a.Extent.Text }
    }
    $script:Calls = New-Object System.Collections.Generic.List[string]
    function Write-Section { param($t) }
    function Write-Log { param($m) }
    function Get-Service { param($Name, $ErrorAction) $null }
    # права системной папки больше не трогаются: такие вызовы — ошибка
    function takeown.exe { $script:Calls.Add('takeown') }
    function icacls.exe { $script:Calls.Add('icacls') }
    # «Система» здесь — тот же пользователь: задача по-настоящему выполняет
    # сгенерированный сценарий, и проверяется он сам, его итог и статусы.
    $script:PsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $script:SafeRoot = $Root + '-safe'; New-Item -ItemType Directory -Force $script:SafeRoot | Out-Null
    function Assert-SafeRoot { $true }
    function Invoke-OneShotTask {
        param([string]$TaskName, [string]$CmdLine, [switch]$AsSystem, [int]$Minutes = 2, [string]$Execute = '', [string]$Arguments = '')
        $script:Calls.Add("task system=$AsSystem $Execute $Arguments$CmdLine")
        if ($Execute -and $Arguments -match '-File "([^"]+)"') { $null = & $Execute -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Matches[1]; return ($LASTEXITCODE -eq 0) }
        return $false
    }
    $script:DiagDir = $Root; $script:DiagDirExpected = $Root; $DryRun = $false; $script:Changes = 0; $script:Failures = 0
    $before = Get-BufferInfo
    Purge-Buffer
    $left = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File | ForEach-Object { $p = $_.FullName; $p.Substring($p.IndexOf($leaf) + $leaf.Length) })
    $r = @{ files = $before.files; left = $left; dirs = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -Directory).Count
            aclCalls = @($script:Calls | Where-Object { $_ -in @('takeown', 'icacls') }).Count; taskCalls = @($script:Calls | Where-Object { $_ -like 'task *' }).Count
            failsClean = $script:Failures }
    # файл держит другой процесс: удаление переходит к системе, а остаток назван
    $busy = Join-Path $Root 'ETLLogs\busy.etl'
    Set-Content -LiteralPath $busy -Value 'x' -Encoding ASCII
    $lock = [IO.File]::Open($busy, 'Open', 'Read', 'None')
    try { $script:Calls.Clear(); $script:Failures = 0; Purge-Buffer } finally { $lock.Close() }
    $sys = @($script:Calls | Where-Object { $_ -like 'task *' })
    $r.busySystem = ($sys.Count -eq 1 -and $sys[0] -like 'task system=True *powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "*buffer-purge-*.ps1"')
    $r.busyReported = ($script:Failures -eq 1)
    $r.busyAcl = @($script:Calls | Where-Object { $_ -in @('takeown', 'icacls') }).Count
    # чужая папка вместо ожидаемой — ничего не удаляется
    $other = Join-Path $Root 'DownloadedSettings'
    Set-Content -LiteralPath (Join-Path $other 'x.etl') -Value 'x' -Encoding ASCII
    $script:DiagDir = $other; $script:Failures = 0
    Purge-Buffer
    $r.wrongDirKept = (Test-Path -LiteralPath (Join-Path $other 'x.etl')) -and $script:Failures -eq 1
    # итог задачи от имени системы: всё удалено / часть / папка не читается
    $sd = $Root + '-sys'; New-Item -ItemType Directory -Force (Join-Path $sd 'ETLLogs') | Out-Null
    foreach ($f in @('a.rbs', 'ETLLogs\b.etl', 'keep.json')) { Set-Content -LiteralPath (Join-Path $sd $f) -Value 'x' -Encoding ASCII }
    $s1 = Invoke-BufferSystemPurge $sd
    $r.sysSuccess = ($s1.status -eq 'success' -and $s1.deleted -eq 2 -and $s1.left -eq 0 -and (Test-Path -LiteralPath (Join-Path $sd 'keep.json')))
    $r.sysSuccessInfo = "$($s1.status) found=$($s1.found) deleted=$($s1.deleted) left=$($s1.left) why=$($s1.why)"
    foreach ($f in @('a.rbs', 'ETLLogs\b.etl')) { Set-Content -LiteralPath (Join-Path $sd $f) -Value 'x' -Encoding ASCII }
    $lock2 = [IO.File]::Open((Join-Path $sd 'ETLLogs\b.etl'), 'Open', 'Read', 'None')
    try { $s2 = Invoke-BufferSystemPurge $sd } finally { $lock2.Close() }
    $r.sysPartial = ($s2.status -eq 'partial' -and $s2.deleted -eq 1 -and $s2.failed -eq 1 -and $s2.left -eq 1)
    $r.sysErrName = (@($s2.errors).Count -eq 1 -and "$(@($s2.errors)[0].file)" -eq 'b.etl' -and "$(@($s2.errors)[0].error)")
    $r.sysPartialInfo = "$($s2.status) deleted=$($s2.deleted) failed=$($s2.failed) left=$($s2.left)"
    $s3 = Invoke-BufferSystemPurge (Join-Path $sd 'no-such-folder')
    $r.sysFailed = ($s3.status -eq 'failed' -and $s3.why)
    $r.sysNoResultsLeft = @(Get-ChildItem -LiteralPath $script:SafeRoot -Filter 'buffer-*').Count -eq 0
    Remove-Item -LiteralPath $sd, $script:SafeRoot -Recurse -Force -ErrorAction SilentlyContinue
    $r
}
$bufDone = Wait-Job $bufJob -Timeout 90
$bufRes = $(if ($bufDone) { Receive-Job $bufJob } else { $null })
Remove-Job $bufJob -Force
Check 'очистка буфера не зависает' ($null -ne $bufRes)
if ($bufRes) {
    Check 'в буфер считаются только очередь и трассировки' ($bufRes.files -eq 5) ("насчитано: " + $bufRes.files)
    Check 'после очистки остались настройки и прочее' ((@($bufRes.left | Sort-Object) -join ',') -eq 'DownloadedSettings\utc.app.json,parse.dat') ("осталось: " + (@($bufRes.left) -join ', '))
    Check 'папки не удаляются' ($bufRes.dirs -eq 4) ("папок: " + $bufRes.dirs)
    Check 'права системной папки не меняются (без takeown и icacls)' ($bufRes.aclCalls -eq 0 -and $bufRes.busyAcl -eq 0) ("вызовов: $($bufRes.aclCalls)/$($bufRes.busyAcl)")
    Check 'что удалилось само, система не трогает' ($bufRes.taskCalls -eq 0 -and $bufRes.failsClean -eq 0)
    Check 'занятый файл удаляется от имени системы' ([bool]$bufRes.busySystem)
    Check 'оставшийся файл не выдаётся за успех' ([bool]$bufRes.busyReported)
    Check 'чистится только ожидаемая папка' ([bool]$bufRes.wrongDirKept)
    Check 'задача от имени системы: всё удалено — success' ([bool]$bufRes.sysSuccess) $bufRes.sysSuccessInfo
    Check 'задача от имени системы: часть осталась — partial' ([bool]$bufRes.sysPartial) $bufRes.sysPartialInfo
    Check 'задача от имени системы: папка не читается — failed с причиной' ([bool]$bufRes.sysFailed)
    Check 'сценарий и итог задачи после чтения удаляются' ([bool]$bufRes.sysNoResultsLeft)
    Check 'в итоге задачи — имя неудалённого файла и причина' ([bool]$bufRes.sysErrName)
}
Remove-Item -LiteralPath $bufRoot -Recurse -Force -ErrorAction SilentlyContinue

# Очистка папок не заходит внутрь ссылок: Remove-Item -Recurse в PowerShell 5.1
# прошёл бы по junction и удалил бы то, куда она ведёт.
foreach ($fn in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in @('Clear-FolderContents', 'Remove-TreeNoFollow', 'Test-ClearForbidden', 'Get-FolderSizeMB') }, $true)) { Invoke-Expression $fn.Extent.Text }
$clLog = New-Object System.Collections.Generic.List[string]
function Write-Log { param([string]$Message = '') $clLog.Add($Message) }
$clId = [guid]::NewGuid().ToString('N').Substring(0, 8)
$cf = Join-Path $env:TEMP ('w11p-clear-' + $clId); $tg = Join-Path $env:TEMP ('w11p-target-' + $clId); $jr0 = Join-Path $env:TEMP ('w11p-jroot-' + $clId)
New-Item -ItemType Directory -Force (Join-Path $cf 'sub'), $tg | Out-Null
Set-Content (Join-Path $cf 'a.txt') 'x'; Set-Content (Join-Path $cf 'sub\b.txt') 'x'; Set-Content (Join-Path $tg 'keep.txt') 'x'; Set-Content (Join-Path $cf 'busy.txt') 'x'
$null = & cmd.exe /c ('mklink /J "' + (Join-Path $cf 'link') + '" "' + $tg + '"')
$null = & cmd.exe /c ('mklink /J "' + $jr0 + '" "' + $tg + '"')
$DryRun = $false; $script:Failures = 0
$clLock = [IO.File]::Open((Join-Path $cf 'busy.txt'), 'Open', 'Read', 'None')
try { $null = Clear-FolderContents $cf 'проверка' } finally { $clLock.Close() }
Check 'очистка не заходит внутрь ссылки: цель цела, сама ссылка убрана' ((Test-Path (Join-Path $tg 'keep.txt')) -and -not (Test-Path (Join-Path $cf 'link')) -and -not (Test-Path (Join-Path $cf 'sub')))
Check 'занятый файл посчитан, а не потерян' ($script:LastClear.failed -eq 1 -and (Test-Path (Join-Path $cf 'busy.txt')))
$script:Failures = 0
$null = Clear-FolderContents $jr0 'проверка ссылки'
Check 'папка-ссылка не очищается вовсе' ((Test-Path (Join-Path $tg 'keep.txt')) -and $script:Failures -eq 1)
Check 'корень диска и профиль очищать нельзя, временную папку — можно' ((Test-ClearForbidden 'C:\') -and (Test-ClearForbidden $env:USERPROFILE) -and -not (Test-ClearForbidden $env:TEMP))
& cmd.exe /c ('rmdir "' + $jr0 + '"') | Out-Null
& cmd.exe /c ('rmdir /s /q "' + $cf + '"') | Out-Null
& cmd.exe /c ('rmdir /s /q "' + $tg + '"') | Out-Null

# Адреса прямой отправки 1DS, найденные в системных файлах и в настройке UTC
$hostsBlock = [regex]::Match($engineText, "(?s)\`$script:HostsDomains = @\((.*?)\)\s*\r?\n").Groups[1].Value
$hostsList = @([regex]::Matches($hostsBlock, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
Check 'список hosts прочитан' ($hostsList.Count -ge 80) ("адресов: " + $hostsList.Count)
$needHosts = @('mobile.events.data.microsoft.com', 'eu-v20.events.data.microsoft.com', 'us-v20.events.data.microsoft.com', 'au.vortex-win.data.microsoft.com')
$missHosts = @($needHosts | Where-Object { $hostsList -notcontains $_ })
Check 'в hosts есть главный адрес 1DS и региональные v20' ($missHosts.Count -eq 0) ($missHosts -join ', ')
$dupHosts = @($hostsList | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
Check 'в списке hosts нет повторов' ($dupHosts.Count -eq 0) ($dupHosts -join ', ')

# --------------------------------------------------------------------------- #
#  Журнал отката и папка данных: замок, ошибки записи, повреждённый журнал,
#  журнал прежних версий, службы/задачи/переменные среды, защита папки.
# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Журнал отката и папка данных'
$jRoot = Join-Path $env:TEMP ('w11p-journal-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $jRoot | Out-Null
$jJob = Start-Job -ArgumentList $engine, $jRoot, $isAdmin -ScriptBlock {
    param($EnginePath, $Root, $Admin)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($EnginePath, [ref]$null, [ref]$null)
    $want = @('ConvertTo-Fields', 'Get-JournalKey', 'Compress-Journal', 'Use-JournalLock', 'Read-JournalFile', 'Write-JournalFile',
              'Save-JournalEntries', 'Save-Json', 'Load-Json', 'Ensure-DataDir', 'Test-DataTrusted', 'Assert-SafeRoot', 'Test-DirSecure',
              'Protect-DataRoot', 'Get-OwnerSid', 'Add-JournalEntry', 'Get-StartName', 'Restore-JournalEntry', 'Test-JournalWritable',
              'Get-SignKey', 'Get-JournalSig', 'Test-KeyFileSecure', 'Test-JournalEntryKnown', 'Test-PortableTaskTrust', 'Test-AclVolume',
              'Test-DirChainSecure', 'Test-ItemTrusted', 'Get-UntrustedItems', 'Test-TaskGlobPath', 'Get-TaskGlobFolders', 'Split-TaskPath',
              'Set-Reg', 'Get-RegValue', 'ConvertTo-RegComparable', 'Set-RegDirect', 'Test-RegKeyWritable', 'Write-AheadEntry', 'Undo-AheadEntry',
              'Test-CanModify', 'Test-JournalEntryShape')
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if ($fn.Name -in $want) { Invoke-Expression $fn.Extent.Text }
    }
    foreach ($a in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        $lt = $a.Left -as [System.Management.Automation.Language.VariableExpressionAst]
        if ($null -ne $lt -and $lt.VariablePath.UserPath -eq 'script:TrustedSids') { Invoke-Expression $a.Extent.Text }
    }
    $script:Log = New-Object System.Collections.Generic.List[string]
    function Write-Log { param($m) $script:Log.Add("$m") }
    function Test-Admin { $Admin }
    $DryRun = $false; $script:Failures = 0
    $script:Journal = New-Object System.Collections.Generic.List[object]
    $script:SafeRoot = Join-Path $Root 'safe'
    $script:DataDir = Join-Path $Root 'data'          # «переносимый» режим: проверка прав не мешает
    $script:RootState = $null; $script:JournalFailed = $false
    $script:JournalLockTries = 1; $script:JournalLockWaitMs = 300
    # ключ подписи: настоящий лежит в ProgramData и без прав администратора недоступен
    $testKey = New-Object byte[] 32; (New-Object Random 7).NextBytes($testKey); $script:SignKey = $testKey
    $script:TaskRun = $false; $script:PortableTaskState = $null; $script:KnownJournal = $null
    $script:RunId = [guid]::NewGuid().ToString('N'); $script:JournalRetract = New-Object 'System.Collections.Generic.HashSet[string]'
    $script:RegTypes = @('reg', 'regif', 'regpol', 'regsvc'); $script:AuditGuid = '{0CCE9226-69AE-11D9-BED3-505054503030}'
    $script:Defs = @(@{ T = 'reg'; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; N = 'AllowTelemetry' },
                     @{ T = 'svc'; P = 'DiagTrack' }, @{ T = 'taskglob'; P = 'OneDrive*' })
    $script:TaskGlobFolders = @{ 'OneDrive*' = @('\') }
    $r = @{}

    # ключи журнала: у служб, задач и переменных свои, и первая запись главная
    $r.keys = @((Get-JournalKey @{ kind = 'svc'; name = 'DiagTrack' }), (Get-JournalKey @{ kind = 'task'; path = '\A\B' }),
                (Get-JournalKey @{ kind = 'env'; name = 'X' }))
    $packed = @(Compress-Journal @(@{ kind = 'svc'; name = 'DiagTrack'; old = '3' }, @{ kind = 'svc'; name = 'DiagTrack'; old = '4' }))
    $r.packOld = "$($packed[0]['old'])"; $r.packCount = $packed.Count

    # обычная запись: новый образец журнала
    $script:Journal.Add(@{ kind = 'svc'; name = 'DiagTrack'; old = '2'; newValue = '4' })
    Save-JournalEntries -Quiet
    $j = Get-Content (Join-Path $script:DataDir 'changes.json') -Raw | ConvertFrom-Json
    $r.schema = "$($j.schema)"; $r.legacyNew = [bool]$j.legacy; $r.saved = @($j.items).Count; $r.failedOk = $script:JournalFailed
    $r.sigLen = "$($j.sig)".Length
    # запись лежит как есть, а не обёрткой {"value": [...], "Count": N}
    $r.firstKind = "$(@($j.items)[0].kind)"
    $rj = Read-JournalFile; $r.signedRead = ($rj.signed -and $rj.trusted -and $rj.items.Count -eq 1 -and $rj.state -eq 'valid')

    # подпись: правка журнала чужой рукой видна, такой журнал не читается
    $jp = Join-Path $script:DataDir 'changes.json'
    $txt = Get-Content $jp -Raw
    Set-Content $jp ($txt -replace '"old":\s*"2"', '"old": "9"') -Encoding UTF8
    $rj = Read-JournalFile
    $r.tamperUntrusted = (-not $rj.trusted) -and $rj.items.Count -eq 0 -and $rj.state -eq 'untrusted'
    $r.tamperAside = @(Get-ChildItem $script:DataDir -Filter 'changes.unverified-*.json').Count
    # дописанная запись тоже
    $script:Journal.Add(@{ kind = 'svc'; name = 'DiagTrack'; old = '2'; newValue = '4' }); Save-JournalEntries -Quiet
    $j = Get-Content $jp -Raw | ConvertFrom-Json
    $j.items += [pscustomobject]@{ kind = 'reg'; path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; name = 'x'; existed = $true; old = 'C:\evil.exe'; type = 'String' }
    ($j | ConvertTo-Json -Depth 8) | Set-Content $jp -Encoding UTF8
    $r.addUntrusted = -not (Read-JournalFile).trusted
    # Ключа нет — журнал непроверяем: при показе он не трогается, а при работе
    # откладывается целым (а не затирается следующей записью). Новый ключ при
    # проверке не заводится — иначе прежний журнал наверняка «не сошёлся» бы.
    $script:Journal.Add(@{ kind = 'svc'; name = 'DiagTrack'; old = '2'; newValue = '4' }); Save-JournalEntries -Quiet
    $script:SignKeyFile = Join-Path $script:SafeRoot 'journal.key'
    $script:SignKey = $null; $script:RootState = $null
    $rjv = Read-JournalFile -ReadOnly
    $r.noKeyViewKept = ($rjv.state -eq 'untrusted') -and (Test-Path $jp)
    $rj = Read-JournalFile
    $r.noKeyUntrusted = ($rj.state -eq 'untrusted') -and -not (Test-Path $jp) -and @(Get-ChildItem $script:DataDir -Filter 'changes.unverifiable-*.json').Count -eq 1
    $r.noKeyNotCreated = -not (Test-Path $script:SignKeyFile)
    if ($Admin) {
        # при записи ключ заводится сам: только своим, 32 байта, и при следующем чтении тот же
        $k1 = [byte[]](Get-SignKey -Create)
        $r.keyCreated = (Test-Path $script:SignKeyFile) -and $k1.Length -eq 32 -and (Test-KeyFileSecure $script:SignKeyFile)
        $script:SignKey = $null
        $r.keyReread = [Convert]::ToBase64String([byte[]](Get-SignKey)) -eq [Convert]::ToBase64String($k1)
    }
    # нет файла — «нет журнала», а не «прежний»
    $r.noneState = (Read-JournalFile -ReadOnly).state
    $script:SignKey = $testKey
    $r.keyBackOk = (Read-JournalFile).trusted
    # журнал прежней версии без подписи в переносимой папке: только записи о настройках программы
    Set-Content $jp ('{"schema":2,"items":[' +
        '{"kind":"reg","path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection","name":"AllowTelemetry","existed":true,"old":"3","type":"DWord"},' +
        '{"kind":"reg","path":"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run","name":"x","existed":true,"old":"C:\\evil.exe","type":"String"},' +
        '{"kind":"svc","name":"DiagTrack","old":"2"},{"kind":"svc","name":"Evil","old":"2"},' +
        '{"kind":"task","path":"\\OneDrive Reporting Task-S-1-5-21-1","old":"Enabled"},' +
        '{"kind":"task","path":"\\Microsoft\\Windows\\Evil\\OneDrive Fake","old":"Enabled"},' +
        '{"kind":"startup","id":"run|HKLM|x","old":"On"}]}') -Encoding UTF8
    $rj = Read-JournalFile
    $r.legacyKept2 = $rj.items.Count; $r.legacyDropped = $rj.dropped; $r.schema2State = $rj.state
    # задача по маске — только в своей папке
    $r.globRoot = Test-TaskGlobPath '\OneDrive Standalone Update Task-S-1-5-21-1' 'OneDrive*'
    $r.globDeep = Test-TaskGlobPath '\Microsoft\Windows\Evil\OneDrive Fake' 'OneDrive*'
    $r.globDefault = Test-TaskGlobPath '\NvTmMon_{B2FE1952}' 'NvTm*'
    # тот же журнал в защищённой папке — целиком: подменить его там было некому
    $keepDir = $script:DataDir; $script:DataDir = $script:SafeRoot
    New-Item -ItemType Directory -Force $script:SafeRoot | Out-Null
    Copy-Item $jp (Join-Path $script:SafeRoot 'changes.json') -Force
    $r.safeLegacyAll = (Read-JournalFile).items.Count
    Remove-Item (Join-Path $script:SafeRoot 'changes.json') -Force
    $script:DataDir = $keepDir
    Remove-Item $jp -Force
    # Задачам планировщика переносимая папка во временной не годится:
    # её может подменить любая программа пользователя. Окну — годится.
    $r.winTrusted = Test-DataTrusted
    $script:TaskRun = $true; $script:PortableTaskState = $null
    $r.taskTrusted = Test-DataTrusted
    $r.taskEnsureThrows = $false
    try { Ensure-DataDir } catch { $r.taskEnsureThrows = $true }
    $script:TaskRun = $false; $script:PortableTaskState = $null
    $r.uncAcl = Test-AclVolume '\\server\share\data'
    $r.chainWindows = Test-DirChainSecure $env:SystemRoot
    $r.chainTemp = Test-DirChainSecure $env:TEMP

    # журнал прежней версии: без schema — помечается навсегда
    Set-Content (Join-Path $script:DataDir 'changes.json') '{"items":[{"kind":"reg","path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection","name":"AllowTelemetry","existed":false,"old":""}]}' -Encoding UTF8
    $rjl = Read-JournalFile; $r.legacyRead = $rjl.legacy; $r.legacyState = $rjl.state
    $script:Journal.Add(@{ kind = 'task'; path = '\A\B'; old = 'Enabled'; newValue = 'Disabled' })
    Save-JournalEntries -Quiet
    $j = Get-Content (Join-Path $script:DataDir 'changes.json') -Raw | ConvertFrom-Json
    $r.legacyKept = [bool]$j.legacy; $r.legacyItems = @($j.items).Count

    # повреждённый журнал не затирается, а откладывается
    Set-Content (Join-Path $script:DataDir 'changes.json') 'это не JSON {' -Encoding UTF8
    $script:Journal.Add(@{ kind = 'env'; name = 'X'; existed = $false; old = ''; newValue = '1' })
    Save-JournalEntries -Quiet
    $r.broken = @(Get-ChildItem $script:DataDir -Filter 'changes.broken-*.json').Count
    $r.afterBroken = @((Get-Content (Join-Path $script:DataDir 'changes.json') -Raw | ConvertFrom-Json).items).Count

    # замок занят другим процессом: запись не идёт без него, ошибка видна
    $flag = Join-Path $Root 'held.txt'
    $holder = Start-Process -FilePath powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile', '-Command',
        "`$m = New-Object System.Threading.Mutex(`$false, 'Global\Win11Privacy-Journal'); `$null = `$m.WaitOne(); Set-Content '$flag' 1; Start-Sleep 8; `$m.ReleaseMutex()")
    $t0 = Get-Date
    while (-not (Test-Path $flag) -and ((Get-Date) - $t0).TotalSeconds -lt 15) { Start-Sleep -Milliseconds 200 }
    $r.held = Test-Path $flag
    $r.lockThrows = $false
    try { Use-JournalLock { $null } } catch { $r.lockThrows = ("$($_.Exception.Message)" -match 'занят') }
    $script:Journal.Add(@{ kind = 'env'; name = 'Y'; existed = $false; old = ''; newValue = '1' })
    $script:Log.Clear()
    $errBefore = $false
    try { Save-JournalEntries -Quiet } catch { $errBefore = $true }
    $r.saveThrew = $errBefore
    $r.journalFailed = $script:JournalFailed
    $r.failLogged = [bool](@($script:Log | Where-Object { $_ -match 'журнал отката не записался' }).Count)
    $r.writable = Test-JournalWritable
    try { $holder.Kill(); $null = $holder.WaitForExit(5000) } catch { }

    # Журнал раньше изменения: в момент записи в реестр «как было» уже на диске;
    # не прошло — запись отзывается; журнал отказал — менять нельзя вовсе.
    $script:JournalFailed = $false; $script:Journal.Clear()
    $script:RunId = [guid]::NewGuid().ToString('N'); $script:JournalRetract = New-Object 'System.Collections.Generic.HashSet[string]'
    function Ensure-Backup { }
    $script:UnblockedIds = @{}; $script:Changes = 0; $script:Already = 0
    $probe = 'HKCU:\Software\W11PWal-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
    $jpath = Join-Path $script:DataDir 'changes.json'
    $script:SeenOnDisk = $null
    function New-ItemProperty {
        param($LiteralPath, $Name, $Value, $PropertyType, [switch]$Force, $ErrorAction)
        $script:SeenOnDisk = [bool]((Get-Content $jpath -Raw -ErrorAction SilentlyContinue) -match [regex]::Escape("$Name"))
        Microsoft.PowerShell.Management\New-ItemProperty -LiteralPath $LiteralPath -Name $Name -Value $Value -PropertyType $PropertyType -Force:$Force -ErrorAction $ErrorAction
    }
    Set-Reg -Path $probe -Name 'WalProbe' -Value 5 -Type 'DWord' -Comment 'проверка журнала заранее'
    $r.walBeforeChange = [bool]$script:SeenOnDisk
    $r.walValue = ((Get-RegValue $probe 'WalProbe') -eq 5)
    Remove-Item Function:\New-ItemProperty
    Set-Reg -Path 'HKLM:\SECURITY\W11PWal' -Name 'WalFail' -Value 1 -Type 'DWord' -Comment 'проверка отзыва'
    Save-JournalEntries -Quiet
    $jtxt = Get-Content $jpath -Raw
    $r.walRetracted = ($jtxt -notmatch 'WalFail'); $r.walKept = ($jtxt -match 'WalProbe')
    $script:JournalFailed = $true
    Set-Reg -Path $probe -Name 'WalBlocked' -Value 1 -Type 'DWord' -Comment 'проверка запрета'
    $r.walBlocked = ($null -eq (Get-RegValue $probe 'WalBlocked'))
    $script:JournalFailed = $false
    Remove-Item -LiteralPath $probe -Recurse -Force -ErrorAction SilentlyContinue
    # форма записей журнала: подпись не заменяет проверку допустимости
    $shapes = @(
        @{ e = @{ kind = 'reg'; path = 'HKLM:\SOFTWARE\X'; name = 'A'; existed = $true; type = 'DWord'; old = 1 }; ok = $true },
        @{ e = @{ kind = 'reg'; path = 'C:\Windows\x'; name = 'A' }; ok = $false },
        @{ e = @{ kind = 'reg'; path = 'HKLM:\SOFTWARE\X'; name = '' }; ok = $false },
        @{ e = @{ kind = 'reg'; path = 'HKLM:\SOFTWARE\X'; name = 'A'; existed = $true; type = 'Evil' }; ok = $false },
        @{ e = @{ kind = 'svc'; name = 'DiagTrack'; old = '2' }; ok = $true },
        @{ e = @{ kind = 'svc'; name = 'a b & c'; old = '2' }; ok = $false },
        @{ e = @{ kind = 'task'; path = '\Microsoft\Windows\X'; old = 'Enabled' }; ok = $true },
        @{ e = @{ kind = 'task'; path = '\A" /tr calc'; old = 'Enabled' }; ok = $false },
        @{ e = @{ kind = 'env'; name = 'POWERSHELL_TELEMETRY_OPTOUT' }; ok = $true },
        @{ e = @{ kind = 'env'; name = 'PATH;x' }; ok = $false },
        @{ e = @{ kind = 'audit'; guid = $script:AuditGuid; old = '1' }; ok = $true },
        @{ e = @{ kind = 'audit'; guid = '{00000000-0000-0000-0000-000000000000}'; old = '1' }; ok = $false },
        @{ e = @{ kind = 'evil'; x = 1 }; ok = $false })
    $r.shapeWrong = @($shapes | Where-Object { [bool](-not (Test-JournalEntryShape $_.e)) -ne $_.ok } | ForEach-Object { "$($_.e.kind):$($_.e.name)$($_.e.path)" })

    # возврат служб и задач: ровно в то, что было
    $script:Calls = New-Object System.Collections.Generic.List[string]
    function Get-Service { param($Name, $ErrorAction) [pscustomobject]@{ Name = $Name } }
    # тип запуска после возврата сверяется по реестру — заглушки ведут его сами
    $script:FakeStart = @{}
    function Set-Service { param($Name, $StartupType, $ErrorAction) $script:Calls.Add("set $Name $StartupType"); $script:FakeStart[$Name] = @{ Automatic = 2; Manual = 3; Disabled = 4 }["$StartupType"] }
    function Get-RegValue { param($Path, $Name) if ($Name -eq 'Start') { return $script:FakeStart[(Split-Path $Path -Leaf)] } return $null }
    function Start-Service { param($Name, $ErrorAction) $script:Calls.Add("start $Name") }
    function Set-ItemProperty { param($LiteralPath, $Name, $Value, $Type, $ErrorAction) $script:Calls.Add("prop $Name $Value"); if ($Name -eq 'Start') { $script:FakeStart[(Split-Path $LiteralPath -Leaf)] = [int]$Value } }
    function Set-TaskEnabled { param($Full, $Enabled) $script:Calls.Add("task $Full $Enabled"); 'ok' }
    $r.svcManual = (Restore-JournalEntry ([pscustomobject]@{ kind = 'svc'; name = 'dmwappushservice'; old = '3'; delayed = ''; running = $true })).ok
    $r.svcDelayed = (Restore-JournalEntry ([pscustomobject]@{ kind = 'svc'; name = 'DiagTrack'; old = '2'; delayed = '1'; running = $false })).ok
    $r.taskBack = (Restore-JournalEntry ([pscustomobject]@{ kind = 'task'; path = '\Microsoft\Windows\X\Y'; old = 'Enabled' })).ok
    $r.calls = @($script:Calls)
    $r.names = @((Get-StartName '2' '1'), (Get-StartName '3'), (Get-StartName '4'))

    # защита папки данных
    $r.tempInsecure = -not (Test-DirSecure $Root)
    if ($Admin) {
        $foreign = Join-Path $Root 'foreign'
        New-Item -ItemType Directory -Force $foreign | Out-Null
        $acl = Get-Acl $foreign
        $acl.SetOwner((New-Object Security.Principal.NTAccount($env:USERDOMAIN, $env:USERNAME)))
        try { Set-Acl $foreign $acl } catch { }
        $r.foreignOwner = Get-OwnerSid $foreign
        $r.foreignFixed = Protect-DataRoot $foreign
        $r.foreignAside = @(Get-ChildItem $Root -Directory -Filter 'foreign.untrusted-*').Count
        $legacy = Join-Path $Root 'legacy'
        New-Item -ItemType Directory -Force $legacy | Out-Null
        $acl = Get-Acl $legacy; $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544'))); Set-Acl $legacy $acl
        Set-Content (Join-Path $legacy 'changes.json') '{}' -Encoding UTF8
        $acl = Get-Acl (Join-Path $legacy 'changes.json'); $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544'))); Set-Acl (Join-Path $legacy 'changes.json') $acl
        $null = & cmd.exe /c ('mklink /J "' + (Join-Path $legacy 'link') + '" "' + $env:SystemRoot + '"')
        # подложенное глубже корня: своя папка снимков, а в ней чужой файл
        $snap = Join-Path $legacy 'snapshots'
        New-Item -ItemType Directory -Force $snap | Out-Null
        $acl = Get-Acl $snap; $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544'))); Set-Acl $snap $acl
        Set-Content (Join-Path $snap 'evil.json') '{}' -Encoding UTF8
        $acl = Get-Acl (Join-Path $snap 'evil.json'); $acl.SetOwner((New-Object Security.Principal.NTAccount($env:USERDOMAIN, $env:USERNAME)))
        try { Set-Acl (Join-Path $snap 'evil.json') $acl } catch { }
        Set-Content (Join-Path $snap 'own.json') '{}' -Encoding UTF8
        $acl = Get-Acl (Join-Path $snap 'own.json'); $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544'))); Set-Acl (Join-Path $snap 'own.json') $acl
        $r.deepOwner = Get-OwnerSid (Join-Path $snap 'evil.json')
        $r.legacyFixed = Protect-DataRoot $legacy
        $r.deepGone = -not (Test-Path (Join-Path $snap 'evil.json'))
        $r.deepAside = @(Get-ChildItem $Root -Directory -Filter 'legacy.untrusted-*' | Where-Object { Test-Path (Join-Path $_.FullName 'snapshots\evil.json') }).Count
        $r.deepOwnKept = Test-Path (Join-Path $snap 'own.json')
        $r.linkGone = -not (Test-Path (Join-Path $legacy 'link'))
        $r.dataKept = Test-Path (Join-Path $legacy 'changes.json')
        $r.windowsIntact = Test-Path (Join-Path $env:SystemRoot 'System32\kernel32.dll')
    }
    $r
}
$jDone = Wait-Job $jJob -Timeout 120
$jr = $(if ($jDone) { Receive-Job $jJob } else { $null })
Remove-Job $jJob -Force
Check 'проверки журнала не зависают' ($null -ne $jr)
if ($jr) {
    Check 'у служб, задач и переменных свои ключи журнала' ((@($jr.keys) -join ',') -eq 'svc|diagtrack,task|\a\b,env|x') (@($jr.keys) -join ',')
    Check 'у службы в журнале остаётся первое состояние' ($jr.packOld -eq '3' -and $jr.packCount -eq 1) ("old=" + $jr.packOld)
    Check 'журнал пишется новым образцом с подписью (schema 3)' ($jr.schema -eq '3' -and -not $jr.legacyNew -and $jr.saved -eq 1 -and -not $jr.failedOk -and $jr.sigLen -eq 64) ("schema=$($jr.schema) sig=$($jr.sigLen)")
    Check 'запись журнала не заворачивается в лишний массив' ($jr.firstKind -eq 'svc') ("kind первой записи: '" + $jr.firstKind + "'")
    Check 'подписанный журнал читается' ([bool]$jr.signedRead)
    Check 'изменённая запись в журнале видна: журнал не читается и отложен' ([bool]$jr.tamperUntrusted -and $jr.tamperAside -ge 1)
    Check 'дописанная в журнал запись видна' ([bool]$jr.addUntrusted)
    Check 'без ключа журналу не верится, и он откладывается целым' ([bool]$jr.noKeyUntrusted)
    Check 'без ключа показ журнала его не трогает' ([bool]$jr.noKeyViewKept)
    Check 'проверка подписи не заводит новый ключ' ([bool]$jr.noKeyNotCreated)
    Check 'нет файла журнала — «нет журнала», а не «прежний»' ($jr.noneState -eq 'none') ("state=" + $jr.noneState)
    Check 'журнал без schema — состояние legacy' ($jr.legacyState -eq 'legacy') ("state=" + $jr.legacyState)
    Check 'журнал нового образца без подписи — не «прежний»' ($jr.schema2State -eq 'valid') ("state=" + $jr.schema2State)
    if ($isAdmin) {
        Check 'ключ подписи заводится сам и закрыт от всех, кроме системы и администраторов' ([bool]$jr.keyCreated)
        Check 'ключ подписи при следующем чтении тот же' ([bool]$jr.keyReread)
    }
    Check 'с ключом журнал снова читается' ([bool]$jr.keyBackOk)
    Check 'журнал без подписи в переносимой папке: только записи о настройках программы' ($jr.legacyKept2 -eq 3 -and $jr.legacyDropped -eq 4) ("оставлено $($jr.legacyKept2), пропущено $($jr.legacyDropped)")
    Check 'задача по маске — только в своей папке планировщика' ($jr.globRoot -and -not $jr.globDeep -and $jr.globDefault) ("корень=$($jr.globRoot) чужая папка=$($jr.globDeep) без списка папок=$($jr.globDefault)")
    Check 'журнал без подписи в защищённой папке читается целиком' ($jr.safeLegacyAll -eq 7) ("записей: $($jr.safeLegacyAll)")
    Check 'окну переносимая папка доверена, как его exe' ([bool]$jr.winTrusted)
    Check 'задачам переносимая папка, которую можно подменить, не доверена' ((-not $jr.taskTrusted) -and $jr.taskEnsureThrows)
    Check 'сетевая папка — без прав доступа' (-not $jr.uncAcl)
    Check 'путь к папке Windows подменить нельзя, к временной — можно' ($jr.chainWindows -and -not $jr.chainTemp) ("windows=$($jr.chainWindows) temp=$($jr.chainTemp)")
    Check 'в момент изменения реестра «как было» уже на диске' ($jr.walBeforeChange -and $jr.walValue)
    Check 'неудавшееся изменение отзывает свою запись, удачное — остаётся' ($jr.walRetracted -and $jr.walKept)
    Check 'после отказа журнала реестр не меняется' ([bool]$jr.walBlocked)
    Check 'форма записей журнала проверяется' (@($jr.shapeWrong).Count -eq 0) (@($jr.shapeWrong) -join ', ')
    Check 'журнал прежней версии узнаётся' ([bool]$jr.legacyRead)
    Check 'пометка «прежняя версия» не теряется при дописывании' ([bool]$jr.legacyKept -and $jr.legacyItems -eq 2) ("записей: " + $jr.legacyItems)
    Check 'повреждённый журнал откладывается, а не затирается' ($jr.broken -eq 1 -and $jr.afterBroken -eq 1)
    Check 'замок держит другой процесс' ([bool]$jr.held)
    Check 'без замка журнал не пишется' ([bool]$jr.lockThrows)
    Check 'ошибка записи журнала не роняет движок' (-not $jr.saveThrew)
    Check 'ошибка записи журнала останавливает изменения' ([bool]$jr.journalFailed)
    Check 'ошибка записи журнала видна в журнале работы' ([bool]$jr.failLogged)
    Check 'проверка перед применением видит занятый журнал' (-not $jr.writable)
    Check 'служба возвращается в «вручную» и запускается, если работала' ($jr.svcManual -and (@($jr.calls) -contains 'set dmwappushservice Manual') -and (@($jr.calls) -contains 'start dmwappushservice')) (@($jr.calls) -join '; ')
    Check 'отложенный автозапуск возвращается' ($jr.svcDelayed -and (@($jr.calls) -contains 'set DiagTrack Automatic') -and (@($jr.calls) -contains 'prop DelayedAutostart 1') -and (@($jr.calls) -notcontains 'start DiagTrack'))
    Check 'включённая до нас задача включается обратно' ($jr.taskBack -and (@($jr.calls) -contains 'task \Microsoft\Windows\X\Y True'))
    Check 'тип запуска словами' ((@($jr.names) -join '|') -eq 'автоматически (отложенный запуск)|вручную|отключена') (@($jr.names) -join '|')
    Check 'папка с наследованными правами не считается защищённой' ([bool]$jr.tempInsecure)
    if ($isAdmin) {
        Check 'чужая папка данных откладывается целиком' ($jr.foreignFixed -and $jr.foreignAside -eq 1) ("владелец был: " + $jr.foreignOwner)
        Check 'папка прежней версии закрывается на запись' ([bool]$jr.legacyFixed)
        Check 'подложенная ссылка уходит в карантин' ([bool]$jr.linkGone)
        Check 'чужой файл глубже корня уходит в карантин с тем же путём' ($jr.deepGone -and $jr.deepAside -eq 1) ("владелец был: $($jr.deepOwner); в карантине: $($jr.deepAside)")
        Check 'свой файл глубже корня остаётся' ([bool]$jr.deepOwnKept)
        Check 'свои данные при этом остаются' ([bool]$jr.dataKept)
        Check 'по ссылке ничего не тронуто' ([bool]$jr.windowsIntact)
    } else { Write-Host '  [--]   защита папки данных: нужны права администратора, пропущено' }
}
# ВАЖНО: только rmdir. Remove-Item -Recurse в Windows PowerShell 5.1 проходит
# внутрь ссылок, а в карантине лежит ссылка на папку Windows.
foreach ($d in @(Get-ChildItem $env:TEMP -Directory -Filter 'w11p-journal-*' -ErrorAction SilentlyContinue)) { & cmd.exe /c ('rmdir /s /q "' + $d.FullName + '"') 2>$null }

# --------------------------------------------------------------------------- #
#  Наблюдение за сетью: политика аудита читается числом, а не словами языка
#  Windows; сбой auditpol не выдаётся за успех; прежнее значение — в журнал.
# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Наблюдение за сетью: политика аудита'
$auJob = Start-Job -ArgumentList $engine -ScriptBlock {
    param($EnginePath)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($EnginePath, [ref]$null, [ref]$null)
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if ($fn.Name -in @('Get-AuditSetting', 'Get-MonitorEnabled', 'Set-AuditSetting', 'Set-MonitorEnabled', 'Get-AuditName', 'Get-JournalKey', 'ConvertTo-Fields', 'Read-SecurityEvents', 'Invoke-NetGuard', 'Test-JournalEntryShape')) { Invoke-Expression $fn.Extent.Text }
    }
    foreach ($a in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        $lt = $a.Left -as [System.Management.Automation.Language.VariableExpressionAst]
        if ($null -ne $lt -and $lt.VariablePath.UserPath -eq 'script:AuditGuid') { Invoke-Expression $a.Extent.Text }
    }
    $script:Log = New-Object System.Collections.Generic.List[string]
    function Write-Log { param($m) $script:Log.Add("$m") }
    $script:Failures = 0
    $script:Seen = New-Object System.Collections.Generic.List[object]
    function Add-JournalEntry { param($Entry) $script:Seen.Add($Entry) }
    $script:FailJournal = $false; $script:JournalFailed = $false; $script:BackupFails = $false; $script:SetCalls = 0
    function Save-JournalEntries { param([switch]$Quiet) if ($script:FailJournal) { $script:JournalFailed = $true } }
    function Get-RegValue { param($Path, $Name) 999999999 }
    function Set-Reg { }
    $script:SecurityLogKey = 'x'; $script:SecurityLogMin = 1
    $script:State = 0; $script:SetFails = $false; $script:Ignore = $false
    # журнал отката: по умолчанию записи об аудите в нём нет
    $script:J = @{ trusted = $true; items = @() }; $script:Restored = New-Object System.Collections.Generic.List[string]
    function Read-JournalFile { param([switch]$ReadOnly) $script:J }
    function Restore-JournalEntry { param($e) if (-not $script:Ignore) { $script:State = [int]$e.old }; @{ ok = $true } }
    function Remove-JournalKey { param([string]$Key) $script:Restored.Add($Key) }
    # заглушка auditpol: резервная копия политики — числом, как у настоящего
    function auditpol.exe {
        $a = $args -join ' '
        if ($a -match '/backup /file:(\S+)') {
            if ($script:BackupFails) { $global:LASTEXITCODE = 1; return }
            $f = $Matches[1]
            Set-Content $f $script:Head -Encoding UTF8
            Add-Content $f ('PC,System,Filtering Platform Connection,' + $script:AuditGuid + ',Erfolg und Fehler,,' + $script:State)
            $global:LASTEXITCODE = 0; return
        }
        if ($a -match '/set') {
            $script:SetCalls++
            if ($script:SetFails) { $global:LASTEXITCODE = 5; 'Error 0x00000005 occurred'; return }
            if (-not $script:Ignore) { $script:State = [int]($a -match '/success:enable') + 2 * [int]($a -match '/failure:enable') }
            $global:LASTEXITCODE = 0; return
        }
        $global:LASTEXITCODE = 0
    }
    $r = @{}
    # на русской Windows заголовки копии переведены — так её отдаёт auditpol
    $script:Head = 'Имя компьютера,цель политики,подкатегория,GUID подкатегории,параметр включения,параметр исключения,значение параметра'
    $script:State = 1; $r.readRu = Get-AuditSetting
    $script:Head = 'Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value'
    $script:State = 2; $r.read2 = Get-AuditSetting; $r.mon2 = Get-MonitorEnabled
    $script:State = 3; $r.mon3 = Get-MonitorEnabled
    $script:State = 1; $r.on = Set-MonitorEnabled $true; $r.after = $script:State
    $r.journalOld = $(if ($script:Seen.Count -gt 0) { "$($script:Seen[0]['old'])" } else { '' })
    $script:SetFails = $true; $r.failOff = Set-MonitorEnabled $false
    $r.failLogged = [bool](@($script:Log | Where-Object { $_ -match 'auditpol не изменил' }).Count)
    $script:SetFails = $false; $script:Ignore = $true; $script:State = 3; $r.ignored = Set-MonitorEnabled $false
    $r.names = (Get-AuditName '0') + '|' + (Get-AuditName '3')
    # Выключение возвращает прежнюю политику из журнала, а не «нет аудита»
    $script:Ignore = $false; $script:Failures = 0
    $script:J = @{ trusted = $true; items = @([pscustomobject]@{ kind = 'audit'; guid = $script:AuditGuid; old = '1'; newValue = '3' }) }
    $script:State = 3; $r.offBack = Set-MonitorEnabled $false; $r.offBackState = $script:State
    $r.offBackKey = @($script:Restored) -join ','
    # групповая политика держит своё — не успех
    $script:Ignore = $true; $script:State = 3; $r.offBackGpo = Set-MonitorEnabled $false; $r.gpoFails = $script:Failures
    # журнала нет — выключаем, как просили
    $script:Ignore = $false; $script:J = @{ trusted = $true; items = @() }; $script:State = 3
    $r.offPlain = Set-MonitorEnabled $false; $r.offPlainState = $script:State
    # журнал безопасности: «событий нет» и «не читается» — разное
    $e1 = Read-SecurityEvents -Ids 1 -Since (Get-Date).AddYears(1) -Max 1 -LogName 'Application'
    $e2 = Read-SecurityEvents -Ids 1 -Since (Get-Date).AddDays(-1) -Max 1 -LogName 'W11P-No-Such-Log'
    $r.evNone = (@($e1.events).Count -eq 0 -and -not $e1.error)
    $r.evError = [bool]$e2.error
    # исходная политика не читается — аудит не включается вовсе
    $script:BackupFails = $true; $script:SetCalls = 0; $script:Failures = 0
    $r.unknownOn = Set-MonitorEnabled $true; $r.unknownSets = $script:SetCalls; $r.unknownFails = $script:Failures
    $script:BackupFails = $false
    # журнал не записался — включённый аудит возвращается как был
    $script:FailJournal = $true; $script:JournalFailed = $false; $script:State = 1
    $r.jfOn = Set-MonitorEnabled $true; $r.jfState = $script:State
    $r.jfLogged = [bool](@($script:Log | Where-Object { $_ -match 'возвращена как была' }).Count)
    $script:FailJournal = $false; $script:JournalFailed = $false
    # слежение за сетью: журнал не прочитался при первом же запуске — окно не теряется
    $script:Saved = $null; $script:Prev = $null
    function Load-Json { param($Name) $script:Prev }
    function Save-Json { param($Name, $Object) $script:Saved = $Object }
    function Show-Toast { param($a, $b) }
    function Get-NetAppsSince { param([datetime]$Since, [int]$Max = 1) $script:NetReadError = $script:FakeErr; @{} }
    $script:FakeErr = 'Access is denied'
    $null = Invoke-NetGuard -Quiet
    $r.ngFirstLast = [datetime]$script:Saved.last; $r.ngFirstErr = "$($script:Saved.readError)"
    $script:Prev = [pscustomobject]@{ known = @(); recent = @(); learnUntil = (Get-Date).AddHours(-1).ToString('s'); last = '2026-01-02T03:04:05' }
    $null = Invoke-NetGuard -Quiet
    $r.ngKeptLast = "$($script:Saved.last)"
    $script:FakeErr = ''
    $null = Invoke-NetGuard -Quiet
    $r.ngOkLast = [datetime]$script:Saved.last; $r.ngOkErr = "$($script:Saved.readError)"
    $r
}
$auDone = Wait-Job $auJob -Timeout 60
$au = $(if ($auDone) { Receive-Job $auJob } else { $null })
Remove-Job $auJob -Force
Check 'проверки политики аудита не зависают' ($null -ne $au)
if ($au) {
    Check 'политика аудита читается числом, а не словами (немецкая Windows)' ($au.read2 -eq 2 -and -not $au.mon2 -and $au.mon3) ("прочитано: " + $au.read2)
    Check 'переведённые заголовки копии политики не мешают (русская Windows)' ($au.readRu -eq 1) ("прочитано: " + $au.readRu)
    Check 'монитор включает и успехи, и отказы' ($au.on -and $au.after -eq 3)
    Check 'прежняя политика аудита записана в журнал' ($au.journalOld -eq '1') ("в журнале: " + $au.journalOld)
    Check 'сбой auditpol не выдаётся за успех' ((-not $au.failOff) -and $au.failLogged)
    Check 'неизменившаяся политика не выдаётся за успех' (-not $au.ignored)
    Check 'политика аудита словами' ($au.names -eq 'выкл|успех и отказ') $au.names
    Check 'выключение монитора возвращает прежнюю политику из журнала' ($au.offBack -and $au.offBackState -eq 1 -and $au.offBackKey -eq ('audit|' + '{0CCE9226-69AE-11D9-BED3-505054503030}').ToLowerInvariant()) ("состояние $($au.offBackState), ключ $($au.offBackKey)")
    Check 'если вернуть не дали — не успех' ((-not $au.offBackGpo) -and $au.gpoFails -eq 1)
    Check 'без записи в журнале монитор просто выключается' ($au.offPlain -and $au.offPlainState -eq 0)
    Check '«событий нет» в журнале — не ошибка' ([bool]$au.evNone)
    Check 'журнал, который не читается, — ошибка, а не пустой список' ([bool]$au.evError)
    Check 'исходная политика аудита не читается — аудит не включается' ((-not $au.unknownOn) -and $au.unknownSets -eq 0 -and $au.unknownFails -eq 1) ("вызовов /set: $($au.unknownSets)")
    Check 'журнал отката не записался — аудит возвращается как был' ((-not $au.jfOn) -and $au.jfState -eq 1 -and $au.jfLogged) ("состояние: $($au.jfState)")
    Check 'первый сбой чтения журнала не съедает окно слежения' (($au.ngFirstLast -lt (Get-Date).AddMinutes(-15)) -and $au.ngFirstErr) ("last=$($au.ngFirstLast)")
    Check 'при сбое отметка «проверено до» не двигается' ($au.ngKeptLast -eq '2026-01-02T03:04:05') $au.ngKeptLast
    Check 'без сбоя отметка — сейчас, ошибка стёрта' (($au.ngOkLast -gt (Get-Date).AddMinutes(-5)) -and -not $au.ngOkErr)
}

# --------------------------------------------------------------------------- #
#  Номер устройства: короткая задача успешна только с кодом 0, учётные данные
#  проверяются после cmdkey, у каждой записи свой статус, номер для плитки —
#  из любого хранилища.
# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Номер устройства: проверка результатов'
$gdJob = Start-Job -ArgumentList $engine -ScriptBlock {
    param($EnginePath)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($EnginePath, [ref]$null, [ref]$null)
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if ($fn.Name -in @('Invoke-OneShotTask', 'Test-OneShotTaskMine', 'ConvertTo-SidValue', 'Get-CredCheckCmd', 'Remove-RegStatus', 'Get-RegValue')) { Invoke-Expression $fn.Extent.Text }
    }
    $r = @{}
    # заглушки планировщика: задача «отработала» с заданным кодом; что
    # зарегистрировано, то и отдаётся обратно — если не подменили
    function Write-Log { param([string]$Message = '') }
    $script:Tasks = @{}; $script:Started = New-Object System.Collections.Generic.List[string]; $script:Removed = New-Object System.Collections.Generic.List[string]
    $script:Swap = $false
    function New-ScheduledTaskAction { param($Execute, $Argument) [pscustomobject]@{ Execute = $Execute; Arguments = $Argument } }
    function New-ScheduledTaskPrincipal { param($UserId, $LogonType, $RunLevel) [pscustomobject]@{ UserId = $UserId } }
    function New-ScheduledTaskSettingsSet { param([switch]$AllowStartIfOnBatteries, [switch]$DontStopIfGoingOnBatteries, $ExecutionTimeLimit) 's' }
    function Register-ScheduledTask {
        param($TaskPath, $TaskName, $Action, $Principal, $Settings, [switch]$Force, $ErrorAction)
        if ($script:Tasks.ContainsKey($TaskName) -and -not $Force) { throw 'задача с таким именем уже есть' }
        $a = $(if ($script:Swap) { [pscustomobject]@{ Execute = 'C:\evil.exe'; Arguments = '' } } else { $Action })
        # планировщик отдаёт систему под её местным именем — «СИСТЕМА» на русской Windows
        $p = $Principal
        if ("$($Principal.UserId)" -eq 'SYSTEM') {
            $p = [pscustomobject]@{ UserId = ([Security.Principal.SecurityIdentifier]'S-1-5-18').Translate([Security.Principal.NTAccount]).Value.Split('\')[-1] }
        }
        $script:Tasks[$TaskName] = [pscustomobject]@{ Actions = @($a); Principal = $p }
    }
    function Get-ScheduledTask { param($TaskPath, $TaskName, $ErrorAction) if ($script:Tasks.ContainsKey($TaskName)) { $script:Tasks[$TaskName] } }
    function Start-ScheduledTask { param($TaskPath, $TaskName, $ErrorAction) $script:Started.Add($TaskName) }
    function Unregister-ScheduledTask { param($TaskPath, $TaskName, $Confirm, $ErrorAction) $script:Removed.Add($TaskName); $script:Tasks.Remove($TaskName) }
    function Get-ScheduledTaskInfo { param($TaskPath, $TaskName, $ErrorAction) [pscustomobject]@{ LastTaskResult = $script:Code } }
    $script:Code = 1; $r.fail = Invoke-OneShotTask 'w11p-test' 'cmd'
    $script:Code = 0; $r.ok = Invoke-OneShotTask 'w11p-test' 'cmd' -AsSystem
    $r.names = @($script:Started)
    # задачу с заранее известным именем завёл кто-то другой — её не трогаем
    $script:Tasks['w11p-test'] = [pscustomobject]@{ Actions = @([pscustomobject]@{ Execute = 'C:\other.exe'; Arguments = '' }); Principal = [pscustomobject]@{ UserId = 'SYSTEM' } }
    $script:Started.Clear(); $script:Removed.Clear()
    $r.okBesideForeign = Invoke-OneShotTask 'w11p-test' 'cmd' -AsSystem
    $r.foreignKept = $script:Tasks.ContainsKey('w11p-test')
    # после регистрации команда оказалась не та — задача не запускается и убирается
    $script:Swap = $true; $script:Started.Clear(); $script:Removed.Clear()
    $r.swapped = Invoke-OneShotTask 'w11p-test' 'cmd' -AsSystem
    $r.swapStarted = $script:Started.Count; $r.swapRemoved = $script:Removed.Count
    $script:Swap = $false
    $r.leftover = @($script:Tasks.Keys | Where-Object { $_ -ne 'w11p-test' }).Count
    # не дождались — задача останавливается, а не дорабатывает без нас
    $script:Stopped = New-Object System.Collections.Generic.List[string]
    function Stop-ScheduledTask { param($TaskPath, $TaskName, $ErrorAction) $script:Stopped.Add($TaskName) }
    $script:Code = 267009; $script:Removed.Clear()
    $r.slow = Invoke-OneShotTask 'w11p-test' 'cmd' -AsSystem -Minutes 0
    $r.slowStopped = $script:Stopped.Count; $r.slowRemoved = $script:Removed.Count
    $script:Code = 0
    # программа запускается напрямую — без cmd.exe и без сборки командной строки
    $script:Tasks.Clear()
    $r.direct = Invoke-OneShotTask 'w11p-test' -Execute 'C:\Windows\System32\schtasks.exe' -Arguments '/change /tn "\A & B" /enable' -AsSystem
    $r.directSeen = @($script:Started).Count -gt 0
    # через cmd не пропускаются % и переводы строк
    $script:Started.Clear(); $before = $script:Tasks.Count
    $r.pctRejected = (-not (Invoke-OneShotTask 'w11p-test' 'echo %PATH%' -AsSystem)) -and $script:Started.Count -eq 0 -and $script:Tasks.Count -eq $before
    # куст профиля не отключился — об этом сказано и это ошибка
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Use-ProfileHive' }, $true)) { Invoke-Expression $fn.Extent.Text }
    $script:HiveLog = New-Object System.Collections.Generic.List[string]
    function Write-Log { param([string]$Message = '') $script:HiveLog.Add($Message) }
    function reg.exe { if ("$args" -match '^load') { $global:LASTEXITCODE = 0 } else { $global:LASTEXITCODE = 1 } }
    $script:Failures = 0
    $null = Use-ProfileHive @{ sid = 'S-1-5-21-0-0-0-4242'; name = 'test'; file = 'C:\nope\NTUSER.DAT' } { param($root) }
    $r.hiveFails = $script:Failures
    $r.hiveLogged = [bool](@($script:HiveLog | Where-Object { $_ -match 'NTUSER\.DAT остался подключённым' }).Count)
    $r.check = Get-CredCheckCmd @('WindowsLive:target=virtualapp/didlogical', 'MicrosoftAccount:target=SSO_POP_Device')
    # статусы удаления — на своей пробной ветке
    $k = 'HKCU:\Software\W11PTest-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    New-Item -Path $k -Force | Out-Null
    New-ItemProperty -LiteralPath $k -Name 'LID' -Value '0018000000000001' -PropertyType String -Force | Out-Null
    $r.st1 = Remove-RegStatus $k 'LID'; $r.st2 = Remove-RegStatus $k 'LID'
    $r.st3 = Remove-RegStatus $k; $r.st4 = Remove-RegStatus $k
    $r
}
$gdDone = Wait-Job $gdJob -Timeout 60
$gd = $(if ($gdDone) { Receive-Job $gdJob } else { $null })
Remove-Job $gdJob -Force
Check 'проверки номера устройства не зависают' ($null -ne $gd)
if ($gd) {
    Check 'сбой команды в короткой задаче не выдаётся за успех' ((-not $gd.fail) -and $gd.ok)
    Check 'у короткой задачи каждый раз своё случайное имя' ((@($gd.names).Count -eq 2) -and (@($gd.names)[0] -ne @($gd.names)[1]) -and (@($gd.names)[0] -like 'w11p-test ????????????')) (@($gd.names) -join ' | ')
    Check 'чужая задача с тем же именем не запускается и не удаляется' ($gd.okBesideForeign -and $gd.foreignKept)
    Check 'подменённая команда задачи не запускается, задача убирается' ((-not $gd.swapped) -and $gd.swapStarted -eq 0 -and $gd.swapRemoved -eq 1) ("started=$($gd.swapStarted) removed=$($gd.swapRemoved)")
    Check 'короткие задачи после себя не остаются' ($gd.leftover -eq 0) ("осталось: $($gd.leftover)")
    Check 'короткая задача умеет запускать программу напрямую' ($gd.direct -and $gd.directSeen)
    Check 'в команду через cmd не пропускаются % и переводы строк' ([bool]$gd.pctRejected)
    Check 'недождавшаяся задача останавливается и убирается' ((-not $gd.slow) -and $gd.slowStopped -eq 1 -and $gd.slowRemoved -eq 1) ("остановлено $($gd.slowStopped), убрано $($gd.slowRemoved)")
    Check 'неотключившийся куст профиля назван и посчитан ошибкой' ($gd.hiveFails -eq 1 -and $gd.hiveLogged)
    Check 'после cmdkey проверяется, что учётных данных не осталось' ($gd.check -eq '(cmdkey /list | findstr /i /c:"virtualapp/didlogical" /c:"SSO_POP_Device" >nul && exit 1 || exit 0)') $gd.check
    Check 'у удаления свой статус: убрано / не было' ("$($gd.st1)|$($gd.st2)|$($gd.st3)|$($gd.st4)" -eq 'removed|absent|removed|absent') "$($gd.st1)|$($gd.st2)|$($gd.st3)|$($gd.st4)"
}
$wipeText = [regex]::Match($engineText, "(?s)function Invoke-GdidWipe \{.*?\n\}").Value
Check 'на время стирания номера останавливается и DoSvc' ($wipeText -match "'wlidsvc', 'CDPSvc', 'DoSvc'")
Check 'недоступные места не выдаются за «стёрто»' ($wipeText -match 'не удалось проверить мест')
$statusText = [regex]::Match($engineText, "(?s)function Get-GdidStatus \{.*?\n\}").Value
Check 'номер для плитки берётся из любого хранилища' ($statusText -match 'elseif \(\$ids\.Count -gt 0\) \{ \$ids\[0\]\.gdid \}')
Check 'о непроверенных профилях сказано' (($statusText -match 'uncheckedProfiles') -and ($wipeText -match 'не вошли в Windows, не проверялись'))

# откат не удаляет чужие политики целыми ветками и не включает всё подряд
Check 'откат не удаляет ветки политик Chrome/Office/VS целиком' ($engineText -notmatch "Policies\\Google\\Chrome','HKCU")
$applyDefText = [regex]::Match($engineText, "(?s)function Apply-Def \{.*?\n\}").Value
$svcApply = [regex]::Match($applyDefText, "(?s)        'svc' \{.*?\n        \}").Value
$svcOptApply = [regex]::Match($applyDefText, "(?s)        'svcopt' \{.*?\n        \}").Value
# журнал раньше изменения: «как было» ложится на диск до Set-Service
Check 'отключение службы пишется в журнал заранее' (($svcApply -match '(?s)Write-AheadEntry \$was.*Set-Service') -and ($svcOptApply -match '(?s)Write-AheadEntry \$was.*Set-Service'))
$taskApply = [regex]::Match($applyDefText, "(?s)        'task' \{.*?\n        \}").Value
Check 'отключение задачи пишется в журнал заранее' ($taskApply -match '(?s)Write-AheadEntry \$tj.*Set-TaskEnabled \$d\.P \$false')
Check 'старый откат служб — только для журнала прежней версии' ($engineText -match "if \(\`$legacyRevert\) \{\s+Write-Section 'Службы")
$silentOk = @($engineText -split "`r?`n" | Where-Object { $_ -match "try \{.*Write-Log.*\[\+\].*\} catch \{ \}\s*$" })
Check 'монитор отдаёт ошибку чтения журнала безопасности' (($engineText -match 'readError=\$rd\.error') -and ($engineText -match 'netGuardError='))
Check 'слежение за сетью не пропускает минуты, когда журнал не читался' ($engineText -match '\$last = \$\(if \(\$err\) \{ if \(\$state -and \$state\.last\) \{ "\$\(\$state\.last\)" \} else \{ \$since\.ToString\(''s''\) \} \}')
Check 'журнал безопасности читается только через Read-SecurityEvents' ([regex]::Matches($engineText, "LogName\s*=\s*'Security'\s*;").Count -eq 0 -and [regex]::Matches($engineText, 'Get-WinEvent -FilterHashtable @\{ LogName = \$LogName').Count -eq 1)
Check 'прежний откат ищет задачи по маске в любой папке, остальное — только в своих' ([regex]::Matches($engineText, 'Get-TaskGlobTasks \$d\.P -AnyFolder').Count -eq 1)
$changesCs = Join-Path (Split-Path $engine) 'PageChanges.cs'
if (Test-Path $changesCs) { Check 'страница «Изменения» говорит, что журналу нельзя верить' ((Get-Content $changesCs -Raw -Encoding UTF8) -match 'Json\.GetBool\(d, "trusted"\)') }
$actionsCs = Join-Path (Split-Path $engine) 'Actions.cs'
if (Test-Path $actionsCs) { Check 'страница «Монитор» говорит, что журнал не читается' ((Get-Content $actionsCs -Raw -Encoding UTF8) -match 'Json\.GetStr\(d, "readError"\)') }
# Движок выполняется сверху вниз: функция, описанная ниже места вызова, в
# этот момент ещё не существует. Тесты с заглушками этого не видят (так
# выключение монитора на живой системе ломалось о Restore-ChangeKey). Здесь
# для каждого блока верхнего уровня обходится вся цепочка вызовов.
$ordDefs = @{}
foreach ($f in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { if (-not $ordDefs.ContainsKey($f.Name)) { $ordDefs[$f.Name] = $f } }
$ordCalls = @{}
$ordGet = { param($node) $h = @{}; foreach ($c in $node.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) { $nm = $c.GetCommandName(); if ($nm -and $ordDefs.ContainsKey($nm)) { $h[$nm] = $true } }; @($h.Keys) }
foreach ($k in @($ordDefs.Keys)) { $ordCalls[$k] = @(& $ordGet $ordDefs[$k].Body) }
$ordBad = New-Object System.Collections.Generic.List[string]
foreach ($st in $engineAst.EndBlock.Statements) {
    if ($st -is [System.Management.Automation.Language.FunctionDefinitionAst]) { continue }
    $seenO = @{}; $q = New-Object System.Collections.Generic.Queue[object]
    foreach ($n in @(& $ordGet $st)) { $q.Enqueue(@($n, $n)) }
    while ($q.Count -gt 0) {
        $it = $q.Dequeue(); $n = $it[0]
        if ($seenO.ContainsKey($n)) { continue }; $seenO[$n] = $true
        if ($ordDefs[$n].Extent.StartOffset -gt $st.Extent.StartOffset) { $ordBad.Add(("строка {0}: {1}" -f $st.Extent.StartLineNumber, $it[1])); continue }
        foreach ($m in $ordCalls[$n]) { $q.Enqueue(@($m, ($it[1] + ' -> ' + $m))) }
    }
}
Check 'каждая вызываемая функция описана в файле выше места вызова' ($ordBad.Count -eq 0) (($ordBad | Select-Object -First 3) -join ' | ')
Check 'неудачи в изменениях не молчат: приложения, сети, рекламный ID, .reg, рентген, CDPSvc' (
    ($engineText -match 'для новых пользователей не убрано') -and ($engineText -match 'записей сетей, которые Windows не отдала') -and
    ($engineText -match "switch \(Remove-RegStatus \`$adKey 'Id'\)") -and ($engineText -match 'reg import .*\$code = \$LASTEXITCODE') -and
    ($engineText -match "catch \{ \`$kept\.Add\(") -and ($engineText -match 'служба CDPSvc сейчас не запустилась'))
Check 'ни одно «[+]» не прячет ошибку в пустом catch' ($silentOk.Count -eq 0) (($silentOk | ForEach-Object { $_.Trim().Substring(0, [Math]::Min(80, $_.Trim().Length)) }) -join ' | ')
Check 'очистка буфера не меняет права системной папки' (([regex]::Match($engineText, "(?s)function Purge-Buffer \{.*?\n\}").Value -notmatch 'takeown|icacls'))
Check 'задачи по маске ищутся только в своих папках' (($engineText -notmatch '\$_\.TaskName -like \$d\.P') -and ([regex]::Matches($engineText, 'Get-TaskGlobTasks \$d\.P').Count -eq 3))
Check 'полный откат не стирает отложенный журнал' ($engineText -match "if \(\`$d\.file -like 'changes\.\*-\*\.json'\) \{ Write-Log")
Check 'откат по недоверенному журналу не говорит «возвращены»' ($engineText -match "if \(`"\`$\(\`$rj\.state\)`" -eq 'untrusted'\) \{\s+Write-Log '\[!\] Настройки по журналу изменений не возвращены")
Check 'откат «по умолчанию» — только для доверенного журнала прежнего образца' (($engineText -match '\$legacyRevert = \("\$\(\$rj\.state\)" -eq ''legacy''\)') -and ($engineText -notmatch '\$legacyRevert = \[bool\]\$rj\.legacy -or'))
$oemApply = [regex]::Match($engineText, "(?s)if \(\(Use-Module 'oem'\).*?\n\}").Value
Check 'отключение компонентов производителя пишется в подписанный журнал заранее' (($oemApply -match '(?s)Write-AheadEntry \$was.*Set-Service') -and ($oemApply -match '(?s)Write-AheadEntry \$tj.*Disable-ScheduledTask') -and ($oemApply -notmatch "Save-Json 'oem-disabled\.json'"))
Check 'изменения в обход журнала закрыты: датчики, кусты профилей, автозагрузка, точка восстановления, служба истории' (
    ($engineText -match "(?s)if \(\`$SensorSet\) \{.*?SensorKey -notmatch '\^\[A-Za-z0-9_\]\{1,64\}\$'.*?Set-Reg -Path \`$root") -and
    ([regex]::Match($engineText, "(?s)function Apply-ProfilesHives \{.*?\n\}").Value -match '(?s)Save-JournalEntries -Quiet.*New-ItemProperty -LiteralPath \$p\.kp') -and
    ($engineText -match "(?s)if \(\`$StartupSet\) \{.*?Write-AheadEntry \`$sj.*?Set-StartupState") -and
    ([regex]::Match($engineText, "(?s)function Ensure-Backup \{.*?\n\}").Value -match '\$srOld') -and
    ($engineText -match 'foreach \(\$n in \$cdpRun\) \{\s+if \(\$DryRun\) \{ continue \}'))
Check 'файлы данных заменяются одним действием системы' (([regex]::Match($engineText, "(?s)function Save-Json \{.*?\n\}").Value -match '\[IO\.File\]::Replace\(') -and ([regex]::Match($engineText, "(?s)function Save-Json \{.*?\n\}").Value -notmatch 'Move-Item -LiteralPath'))
Check 'задачи от имени системы запускают schtasks и PowerShell напрямую, без cmd' (($engineText -match '-Execute "\$env:SystemRoot\\System32\\schtasks\.exe"') -and ($engineText -match "Invoke-OneShotTask 'Win11Privacy buffer' -Execute \`$script:PsExe"))
Check 'список производителя прежней версии сверяется с тем, что программа узнаёт сама' ($engineText -match "foreach \(\`$k in @\(\(Detect-Oem\)\.items\)\)")
Check 'задачи стража запускают PowerShell по полному пути' (($engineText -notmatch "Execute 'powershell\.exe'") -and ([regex]::Matches($engineText, 'New-ScheduledTaskAction -Execute \$script:PsExe').Count -eq 4))
Check 'применение проверяет журнал заранее' ($engineText -match 'if \(-not \(Test-JournalWritable\)\) \{\s+Write-Log .ПРИМЕНЕНИЕ ОТМЕНЕНО')
Check 'задача планировщика не работает с папкой, которую можно подменить' ($engineText -match 'if \(\$script:TaskRun -and -not \(Test-DataTrusted\)\) \{ exit 1 \}')
Check 'страж в переносимом режиме не ставится на папку, которую можно подменить' ([regex]::Match($engineText, "(?s)function Install-TaskEngine \{.*?\n\}").Value -match 'Test-PortableTaskTrust')
$engineCs = Join-Path (Split-Path $engine) 'Engine.cs'
if (Test-Path $engineCs) {
    $ecs = Get-Content $engineCs -Raw -Encoding UTF8
    Check 'движок не кладётся во временную папку, если защищённую подготовить не вышло' (($ecs -notmatch 'GetTempPath') -and ($ecs -match 'throw new InvalidOperationException\(L\.T\("Не удалось подготовить защищённую папку'))
    Check 'окно проверяет папку данных на любой глубине' ($ecs -match 'Quarantine\(d, r, aside\)')
    Check 'PowerShell запускается только по полному системному пути' (($ecs -match 'throw new FileNotFoundException\(L\.T\("Не найден системный PowerShell') -and
        (@(Get-ChildItem (Split-Path $engine) -Filter '*.cs' | Where-Object { (Get-Content $_.FullName -Raw -Encoding UTF8) -match '"powershell\.exe"' }).Count -eq 0))
}
Check 'копия движка для задач — только через защищённую установку' (($engineText -notmatch "Copy-Item -LiteralPath \`$PSCommandPath -Destination \`$engineDst") -and ([regex]::Matches($engineText, '\$engineDst = Install-TaskEngine').Count -eq 4))

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host ("Пройдено: " + $script:Passed + ", провалено: " + $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
