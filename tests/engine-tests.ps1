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
if ($all) { Check 'настроек в аудите больше 150' ([int]$all.total -gt 150) ("получено: " + $all.total) }

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

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Порядок объявлений в движке'
$engineText = Get-Content -LiteralPath $engine -Raw -Encoding UTF8
$posStartup = $engineText.IndexOf('function Get-StartupList')
$posGuard = $engineText.IndexOf('function Run-Guard')
Check 'функции автозагрузки объявлены выше стража' ($posStartup -gt 0 -and $posStartup -lt $posGuard) `
      ("Get-StartupList на " + $posStartup + ", Run-Guard на " + $posGuard)

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
Write-Host ("Пройдено: " + $script:Passed + ", провалено: " + $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
