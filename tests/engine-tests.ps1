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
    Check 'настроек больше 200' ($ids.Count -gt 200) ("получено: " + $ids.Count)
    Check 'номера настроек уникальны' (($ids | Select-Object -Unique).Count -eq $ids.Count)
    $empty = @($groups | Where-Object { -not $_.title })
    Check 'у всех модулей есть название' ($empty.Count -eq 0)

    $names = @($groups | ForEach-Object { $_.module })
    foreach ($need in @('network', 'sync', 'history')) {
        Check ("модуль $need на месте") ($names -contains $need)
    }

    # одна и та же настройка не должна попадать в список дважды: раньше две
    # задачи планировщика были записаны по два раза и считались как разные
    $seen = @{}; $twice = 0
    foreach ($g in $groups) {
        foreach ($i in @($g.items)) {
            $k = "$($g.module)|$($i.name)"
            if ($seen.ContainsKey($k)) { $twice++ } else { $seen[$k] = $true }
        }
    }
    Check 'нет повторяющихся настроек' ($twice -eq 0) ("повторов: " + $twice)
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
if ($all) { Check 'настроек в аудите больше 200' ([int]$all.total -gt 200) ("получено: " + $all.total) }

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
if ($foot) {
    $footIds = @($foot.items | ForEach-Object { $_.id })
    foreach ($need in @('psreadline', 'runmru', 'rdp', 'thumbs', 'recall')) {
        Check ("след: элемент $need на месте") ($footIds -contains $need)
    }
    $noWhat = @($foot.items | Where-Object { -not $_.what })
    Check 'у всех элементов следа есть пояснение' ($noWhat.Count -eq 0)
}
$apps = Get-EngineJson @('-ListApps')
Check 'список приложений отвечает' ($null -ne $apps -and $null -ne $apps.apps)
# Проба связи. Куда именно дозвонится агент сборки — неизвестно (сеть у него
# своя), поэтому проверяем форму ответа, а не результат.
$probe = Get-EngineJson @('-Probe', '-ProbeTimeout', '1500')
Check 'проба связи отвечает' ($null -ne $probe -and $null -ne $probe.items)
if ($probe) {
    Check 'проба проверила все адреса' ([int]$probe.total -ge 12) ("получено: " + $probe.total)
    Check 'открытых плюс закрытых = всего' (([int]$probe.open + [int]$probe.blocked) -eq [int]$probe.total)
    $noState = @($probe.items | Where-Object { -not $_.state })
    Check 'у каждого адреса есть состояние' ($noState.Count -eq 0)
}

$self = Get-EngineJson @('-SelfTest')
Check 'самопроверка отвечает' ($null -ne $self)
$log = Get-EngineJson @('-ChangeLog')
Check 'журнал отката отвечает' ($null -ne $log)

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Применение (тестовый прогон, ничего не меняется)'
if ($isAdmin) {
    $mods = 'telemetry,errors,activity,history,input,edge,ads,copilot,sync,network'
    $out = Run-Engine @('-DryRun', '-NoBackup', '-NoRestorePoint', '-Modules', $mods)
    $sections = @([regex]::Matches($out, '(?m)^--- ')).Count - 1     # минус раздел «Итог»
    Check 'выполнены все выбранные модули (регрессия: $defs === $script:Defs)' ($sections -ge 10) `
          ("разделов: " + $sections + " из 10")
    Check 'в тестовом прогоне нет изменений' ($out -match 'Изменений применено : 0')
} else {
    Write-Host '  (пропущено: нужны права администратора)'
}

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host ("Пройдено: " + $script:Passed + ", провалено: " + $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
