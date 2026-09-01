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
