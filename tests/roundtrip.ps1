# =========================================================================== #
#  Проверка «применили — проверили — откатили».
#
#  Остальные проверки только читают, и это их предел: они не могут сказать,
#  действительно ли откат возвращает систему в то состояние, в котором её
#  застали. Здесь настройки применяются по-настоящему, а потом откатываются,
#  и каждое значение сверяется с тем, что было до начала.
#
#  ВНИМАНИЕ: тест реально меняет настройки компьютера. Сам по себе он не
#  запускается — нужен ключ -Confirmed или переменная WIN11_ROUNDTRIP=1.
#  В сборке он выполняется на одноразовой машине GitHub Actions.
#
#      powershell -ExecutionPolicy Bypass -File tests\roundtrip.ps1 -Confirmed
# =========================================================================== #
[CmdletBinding()]
param(
    [switch]$Confirmed,
    # Модули только из тех, что пишут в реестр: службы, hosts и брандмауэр
    # трогать на чужой машине незачем, а проверяется тем же самым механизмом.
    [string]$Modules = 'telemetry,ads,activity,input,search,apppriv,network'
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$engine = Join-Path (Split-Path $PSScriptRoot -Parent) 'Win11-Privacy-Engine.ps1'
if (-not (Test-Path $engine)) { Write-Host "не найден движок: $engine"; exit 1 }

if (-not $Confirmed -and $env:WIN11_ROUNDTRIP -ne '1') {
    Write-Host 'Этот тест меняет настройки компьютера по-настоящему.'
    Write-Host 'Запускайте его на одноразовой или тестовой машине:'
    Write-Host '    powershell -ExecutionPolicy Bypass -File tests\roundtrip.ps1 -Confirmed'
    exit 2
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host '::error::нужны права администратора'; exit 1 }

$script:Failed = 0
$script:Passed = 0
function Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host ("  [ok]   " + $Name); $script:Passed++ }
    else {
        Write-Host ("  [FAIL] " + $Name + $(if ($Detail) { "  --  $Detail" } else { '' }))
        Write-Host ("::error::" + $Name + " " + $Detail)
        $script:Failed++
    }
}

# Своя папка данных и своя папка копий: журнал изменений теста не смешивается
# с журналом настоящей работы программы, и откат вернёт ровно наши правки.
$work    = Join-Path $env:TEMP ('win11privacy-roundtrip-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$dataDir = Join-Path $work 'data'
$bakDir  = Join-Path $work 'backup'
New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
New-Item -ItemType Directory -Path $bakDir  -Force | Out-Null

function Run-Engine {
    param([string[]]$EngineArgs)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Command powershell.exe).Source
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $engine + '" ' +
                     ($EngineArgs -join ' ') + ' -DataRoot "' + $dataDir + '" -BackupRoot "' + $bakDir + '"'
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
    foreach ($line in (Run-Engine $EngineArgs) -split "`n") {
        $t = $line.TrimStart()
        if ($t.StartsWith('###JSON###')) {
            try { return ($t.Substring(10).Trim() | ConvertFrom-Json) } catch { return $null }
        }
    }
    return $null
}

# Плоская карта «номер настройки -> что с ней сейчас»: по ней сравниваются
# состояния до и после отката.
function Get-State {
    param($Audit)
    $map = @{}
    if (-not $Audit) { return $map }
    foreach ($g in @($Audit.groups)) {
        foreach ($i in @($g.items)) {
            if (-not $i.id) { continue }
            $map["$($i.id)"] = @{ ok = [bool]$i.ok; actual = "$($i.actual)" }
        }
    }
    return $map
}

Write-Host ("Модули: " + $Modules)
Write-Host ("Рабочая папка: " + $work)
Write-Host ''

# --------------------------------------------------------------------------- #
Write-Host 'Состояние до'
$auditBefore = Get-EngineJson @('-Audit', '-Modules', $Modules)
Check 'проверка до применения отвечает' ($null -ne $auditBefore)
if (-not $auditBefore) { exit 1 }
$before = Get-State $auditBefore
Check 'настроек в проверке больше 20' ($before.Count -gt 20) ("получено: " + $before.Count)
Write-Host ("  применено до: {0} из {1}" -f $auditBefore.ok, $auditBefore.total)

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Применение'
$applyOut = Run-Engine @('-Modules', $Modules, '-NoRestorePoint')
Check 'движок доработал до конца' ($applyOut -match '###DONE###')
Check 'в журнале работы есть изменения' ($applyOut -match '\[\+\]')

$auditAfter = Get-EngineJson @('-Audit', '-Modules', $Modules)
Check 'проверка после применения отвечает' ($null -ne $auditAfter)
Write-Host ("  применено после: {0} из {1}" -f $auditAfter.ok, $auditAfter.total)
Check 'применённых стало больше' ([int]$auditAfter.ok -gt [int]$auditBefore.ok) `
      ("было " + $auditBefore.ok + ", стало " + $auditAfter.ok)

$after = Get-State $auditAfter
$notApplied = @()
foreach ($k in $after.Keys) { if (-not $after[$k].ok) { $notApplied += $k } }
# Часть параметров Windows не отдаёт даже администратору — движок помечает их
# отдельно и в знаменатель не считает. Здесь важно, что таких немного.
Check 'после применения осталось не применено меньше десятой части' `
      ($notApplied.Count * 10 -le $after.Count) ("не применено: " + $notApplied.Count + " из " + $after.Count)

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Следы применения'
$changes = Join-Path $dataDir 'changes.json'
Check 'журнал изменений записан' (Test-Path -LiteralPath $changes)
if (Test-Path -LiteralPath $changes) {
    $cj = Get-Content -LiteralPath $changes -Raw -Encoding UTF8 | ConvertFrom-Json
    Check 'в журнале есть записи' (@($cj.items).Count -gt 0) ("записей: " + @($cj.items).Count)
}
$regFiles = @(Get-ChildItem -LiteralPath $bakDir -Recurse -Filter '*.reg' -ErrorAction SilentlyContinue)
Check 'резервная копия реестра создана' ($regFiles.Count -gt 0) ("файлов: " + $regFiles.Count)

# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Откат'
$revertOut = Run-Engine @('-Revert')
Check 'откат доработал до конца' ($revertOut -match '###DONE###')

$auditBack = Get-EngineJson @('-Audit', '-Modules', $Modules)
Check 'проверка после отката отвечает' ($null -ne $auditBack)
$back = Get-State $auditBack
Write-Host ("  применено после отката: {0} из {1}" -f $auditBack.ok, $auditBack.total)

# Главная проверка: каждое значение вернулось туда, где было. Сравнивается не
# «сколько применено», а каждая настройка по отдельности — иначе взаимная
# компенсация ошибок прошла бы незамеченной.
$diff = @()
foreach ($k in $before.Keys) {
    if (-not $back.ContainsKey($k)) { $diff += ("$k -- пропала из проверки"); continue }
    if ($before[$k].actual -ne $back[$k].actual) {
        $diff += ("{0}: было '{1}', стало '{2}'" -f $k, $before[$k].actual, $back[$k].actual)
    }
}
Check 'после отката каждое значение вернулось к исходному' ($diff.Count -eq 0) `
      ($(if ($diff.Count -gt 0) { "расхождений " + $diff.Count + ": " + (($diff | Select-Object -First 5) -join '; ') } else { '' }))
Check 'счётчик применённых вернулся к исходному' ([int]$auditBack.ok -eq [int]$auditBefore.ok) `
      ("было " + $auditBefore.ok + ", после отката " + $auditBack.ok)

if (Test-Path -LiteralPath $changes) {
    $cj2 = Get-Content -LiteralPath $changes -Raw -Encoding UTF8 | ConvertFrom-Json
    Check 'журнал изменений после отката пуст' (@($cj2.items).Count -eq 0) ("осталось записей: " + @($cj2.items).Count)
}

# --------------------------------------------------------------------------- #
try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ''
Write-Host ("Пройдено: {0}, провалено: {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
