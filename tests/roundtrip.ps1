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
#  Службы, задачи, переменные среды и чужие политики. Откат должен вернуть их
#  ровно такими, какими застал, а не «по умолчанию»: раньше задача, которую
#  человек выключил сам, после отката включалась, DiagTrack становилась
#  «автоматически», переменная среды пропадала, а корпоративные политики
#  Chrome удалялись вместе с нашей одной.
# --------------------------------------------------------------------------- #
Write-Host ''
Write-Host 'Службы, задачи, переменные среды, чужие политики'
$stateModules = 'services,network,cloudsync,doh,app_devtools'
$engineText = Get-Content -LiteralPath $engine -Raw -Encoding UTF8
$taskPaths = @([regex]::Matches($engineText, "(?m)^Def '(?:network|cloudsync)' 'task' '([^']+)'") | ForEach-Object { $_.Groups[1].Value })
$live = @()
foreach ($tp in $taskPaths) {
    $leaf = Split-Path $tp -Leaf; $dir = (Split-Path $tp -Parent) + '\'
    $t = Get-ScheduledTask -TaskPath $dir -TaskName $leaf -ErrorAction SilentlyContinue
    if ($t -and $t.State -ne 'Disabled') { $live += @{ path = $tp; dir = $dir; leaf = $leaf } }
}
# На серверной Windows сборки GitHub части задач Windows 11 нет вовсе — тогда
# сценарий пропускается, а не валит сборку: на Windows 11 он проходит на ВМ.
if ($live.Count -lt 2) { Write-Host ("  [--]   включённых задач из списка нашлось {0} — сценарий пропущен" -f $live.Count) }
else { Check 'нашлись две включённые задачи из списка' $true }
$svcKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\DiagTrack'
$svcStart0 = (Get-ItemProperty -LiteralPath $svcKey -Name Start -ErrorAction SilentlyContinue).Start
$env0 = [Environment]::GetEnvironmentVariable('POWERSHELL_UPDATECHECK', 'User')
$chrome = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
$chromeExisted = Test-Path -LiteralPath $chrome
$home0 = (Get-ItemProperty -LiteralPath $chrome -Name HomepageLocation -ErrorAction SilentlyContinue).HomepageLocation
$doh0 = (Get-ItemProperty -LiteralPath $chrome -Name DnsOverHttpsMode -ErrorAction SilentlyContinue).DnsOverHttpsMode
if ($live.Count -ge 2 -and $null -ne $svcStart0) {
    # «человек настроил сам, до программы»
    Disable-ScheduledTask -TaskPath $live[0].dir -TaskName $live[0].leaf -ErrorAction SilentlyContinue | Out-Null
    Set-Service -Name DiagTrack -StartupType Manual -ErrorAction SilentlyContinue
    [Environment]::SetEnvironmentVariable('POWERSHELL_UPDATECHECK', 'LTS', 'User')
    if (-not $chromeExisted) { New-Item -Path $chrome -Force | Out-Null }
    New-ItemProperty -LiteralPath $chrome -Name HomepageLocation -Value 'https://example.org/' -PropertyType String -Force | Out-Null

    $out2 = Run-Engine @('-Modules', $stateModules, '-NoRestorePoint')
    Check 'применение (службы, задачи) доработало до конца' ($out2 -match '###DONE###')
    $t1 = Get-ScheduledTask -TaskPath $live[1].dir -TaskName $live[1].leaf -ErrorAction SilentlyContinue
    Check 'включённая задача отключена' ($t1 -and $t1.State -eq 'Disabled')
    Check 'DiagTrack отключена' ((Get-ItemProperty -LiteralPath $svcKey -Name Start).Start -eq 4)
    Check 'переменная среды выставлена' ([Environment]::GetEnvironmentVariable('POWERSHELL_UPDATECHECK', 'User') -eq 'Off')
    if (Test-Path -LiteralPath $changes) {
        $cj3 = Get-Content -LiteralPath $changes -Raw -Encoding UTF8 | ConvertFrom-Json
        $kinds = @($cj3.items | ForEach-Object { "$($_.kind)" } | Select-Object -Unique)
        Check 'в журнале есть службы, задачи и переменные среды' (($kinds -contains 'svc') -and ($kinds -contains 'task') -and ($kinds -contains 'env')) ($kinds -join ',')
        Check 'журнал нового образца, с подписью' ("$($cj3.schema)" -eq '3' -and -not $cj3.legacy -and "$($cj3.sig)".Length -eq 64) ("schema=$($cj3.schema)")
    } else { Check 'журнал записан' $false }

    $out3 = Run-Engine @('-Revert')
    Check 'откат (службы, задачи) доработал до конца' ($out3 -match '###DONE###')
    $t0 = Get-ScheduledTask -TaskPath $live[0].dir -TaskName $live[0].leaf -ErrorAction SilentlyContinue
    $t1 = Get-ScheduledTask -TaskPath $live[1].dir -TaskName $live[1].leaf -ErrorAction SilentlyContinue
    Check 'задача, выключенная до программы, осталась выключенной' ($t0 -and $t0.State -eq 'Disabled') ("состояние: " + $t0.State)
    Check 'задача, включённая до программы, включена снова' ($t1 -and $t1.State -ne 'Disabled') ("состояние: " + $t1.State)
    $svcStart = (Get-ItemProperty -LiteralPath $svcKey -Name Start).Start
    Check 'DiagTrack вернулась в «вручную», а не «автоматически»' ($svcStart -eq 3) ("Start=" + $svcStart)
    Check 'переменная среды вернулась к своему значению' ([Environment]::GetEnvironmentVariable('POWERSHELL_UPDATECHECK', 'User') -eq 'LTS')
    Check 'чужая политика Chrome осталась' ((Get-ItemProperty -LiteralPath $chrome -Name HomepageLocation -ErrorAction SilentlyContinue).HomepageLocation -eq 'https://example.org/')
    $dohBack = (Get-ItemProperty -LiteralPath $chrome -Name DnsOverHttpsMode -ErrorAction SilentlyContinue).DnsOverHttpsMode
    Check 'своя политика Chrome снята' ("$dohBack" -eq "$doh0") ("DnsOverHttpsMode=" + $dohBack)
    Check 'откат не шёл по старой схеме «по умолчанию»' ($out3 -notmatch 'журнал прежней версии')

    # вернуть машину как было до теста
    if ($live.Count -ge 1) { Enable-ScheduledTask -TaskPath $live[0].dir -TaskName $live[0].leaf -ErrorAction SilentlyContinue | Out-Null }
    Set-ItemProperty -LiteralPath $svcKey -Name Start -Value $svcStart0 -Type DWord -ErrorAction SilentlyContinue
    [Environment]::SetEnvironmentVariable('POWERSHELL_UPDATECHECK', $env0, 'User')
    if ($chromeExisted) {
        if ($null -ne $home0) { New-ItemProperty -LiteralPath $chrome -Name HomepageLocation -Value $home0 -PropertyType String -Force | Out-Null }
        else { Remove-ItemProperty -LiteralPath $chrome -Name HomepageLocation -ErrorAction SilentlyContinue }
    } else { Remove-Item -LiteralPath $chrome -Recurse -Force -ErrorAction SilentlyContinue }
}

# --------------------------------------------------------------------------- #
try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ''
Write-Host ("Пройдено: {0}, провалено: {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
