# --------------------------------------------------------------------------- #
#  Проверки исправлений T-1, T-2, T-3 и GDID (2026-11-16).
#  Подключается из tests\engine-tests.ps1 (точкой): Check, $engine и
#  $engineAst — оттуда. Каждый блок работает в своём фоновом задании со
#  всеми функциями движка (AST) и своими заглушками; реестр — только пробные
#  ключи HKCU:\Software\W11PRemed-*, файлы — во временных папках.
#  Части, которым нужны права администратора, без них пропускаются с пометкой
#  (CI и VM идут от администратора).
# --------------------------------------------------------------------------- #

$remedAllFns = (@($engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) | ForEach-Object { $_.Extent.Text }) -join "`r`n"
$remedVars = @'
$script:TrustedSids = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
$script:ClearOwners = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-19', 'S-1-5-20', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
$script:JournalLockDepth = 0; $script:JournalLockTries = 50; $script:JournalLockWaitMs = 200
$script:TaskRun = $false; $script:PortableTaskState = $null; $script:KnownJournal = $null
$script:BackupManifestName = 'backup-sig.json'; $script:BackupFileRx = '^[A-Za-z0-9_.(){}+-]{1,200}\.reg$'
$script:BackupStoreKeep = 20; $script:BackupV2Since = '20261115'
$script:RestoreOp = 'restore'; $script:GdidWipeOp = 'gdid-wipe'
$script:GdidSvcNames = @('CDPSvc', 'CDPUserSvc', 'DoSvc'); $script:GdidUserSidRx = '^S-1-(5-21|12-1)-[\d-]+$'
$script:GdidCredUser = @('WindowsLive:target=virtualapp/didlogical', 'MicrosoftAccount:target=SSO_POP_Device'); $script:GdidCredSystem = @('WindowsLive:target=virtualapp/didlogical')
$script:AuditGuid = '{0CCE9226-69AE-11D9-BED3-505054503030}'
$script:RegTypes = @('reg', 'regif', 'regpol', 'regsvc')
$script:Failures = 0; $script:Changes = 0
function Write-Log { param([string]$Message = '') $script:RemedLog.Add("$Message") }
$script:RemedLog = New-Object System.Collections.Generic.List[string]
'@
Check 'исправления T-1…T-3: функции движка найдены' (($remedAllFns -match 'function Open-ProgramMutex') -and ($remedAllFns -match 'function New-PrivateWorkDir') -and
      ($remedAllFns -match 'function Write-OpRecord') -and ($remedAllFns -match 'function Restore-GdidInterruptedWipe'))

# =========================================================================== #
#  T-1. Замки по имени в Global\: чужой объект под именем программы
# =========================================================================== #
Write-Host ''
Write-Host 'T-1: замки Global\Win11Privacy-* — владелец и права'
$t1Job = Start-Job -ArgumentList $remedAllFns, $remedVars -ScriptBlock {
    param($Fns, $Vars)
    Invoke-Expression $Fns; Invoke-Expression $Vars
    $r = @{}
    $adm = [bool](Test-Admin); $r.admin = $adm
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $sec = { param([string]$S) $x = New-Object System.Security.AccessControl.MutexSecurity; $x.SetSecurityDescriptorSddlForm($S); $x }
    $tr = @('S-1-5-18', 'S-1-5-32-544')
    # решение «свой / чужой» — как у повышенного движка
    $cases = [ordered]@{
        'O:BAD:P(A;;0x1F0001;;;SY)(A;;0x1F0001;;;BA)'            = $true    # свой (заведён повышенным движком)
        'O:SYD:P(A;;0x1F0001;;;SY)(A;;0x1F0001;;;BA)'            = $true    # свой (заведён задачей SYSTEM)
        ('O:' + $me + 'D:P(A;;0x1F0001;;;SY)(A;;0x1F0001;;;BA)') = $false   # владелец — сам пользователь (так заводит его обычная программа)
        'O:BUD:P(A;;0x1F0001;;;BA)'                              = $false   # владелец — Пользователи
        'O:AUD:P(A;;0x1F0001;;;BA)'                              = $false   # владелец — Прошедшие проверку
        'O:BAD:P(A;;0x100000;;;WD)(A;;0x1F0001;;;BA)'            = $false   # Все могут ждать — взять и держать
        'O:BAD:P(A;;0x40000;;;AU)(A;;0x1F0001;;;BA)'             = $false   # смена прав
        'O:BAD:P(A;;0x80000;;;BU)(A;;0x1F0001;;;BA)'             = $false   # смена владельца
        'O:BAD:P(A;;0x10000;;;IU)(A;;0x1F0001;;;BA)'             = $false   # удаление
        'O:BAD:P(A;;GA;;;WD)'                                    = $false   # общее «всё»
        'O:BAD:NO_ACCESS_CONTROL'                                = $false   # пустой список прав (NULL DACL)
        'O:BAD:P(A;;0x20001;;;WD)(A;;0x1F0001;;;BA)'             = $true    # чтение прав и состояния — не опасно
        'O:BAD:P(D;;0x1F0001;;;WD)(A;;0x1F0001;;;BA)'            = $true    # запрет — не опасен
    }
    $bad = @()
    foreach ($s in $cases.Keys) { $p = Get-MutexSecurityProblem (& $sec $s) $tr; if ((-not $p) -ne $cases[$s]) { $bad += ("{0} -> [{1}]" -f $s, $p) } }
    $r.sddlBad = ($bad -join ' | '); $r.sddlN = $cases.Count
    $r.nullSec = [bool](Get-MutexSecurityProblem $null $tr)
    $r.selfRule = ((Test-MutexOwnerTrusted $me) -eq (-not $adm)) -and ((@(Get-MutexTrustedSids) -contains $me) -eq (-not $adm))
    $r.sysBa = (Test-MutexOwnerTrusted 'S-1-5-18') -and (Test-MutexOwnerTrusted 'S-1-5-32-544') -and -not (Test-MutexOwnerTrusted 'S-1-5-32-545') -and -not (Test-MutexOwnerTrusted '')

    # --- имени нет: заводится свой ---
    $n1 = 'Global\W11P-T1-' + [guid]::NewGuid().ToString('N')
    $m1 = Open-ProgramMutex $n1
    $s1 = $m1.GetAccessControl()
    $r.freeOwner = $s1.GetOwner([Security.Principal.SecurityIdentifier]).Value
    $r.freeWantOwner = $(if ($adm) { 'S-1-5-32-544' } else { $me })
    $r.freeSids = (@($s1.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique) -join ',')
    $r.freeWantSids = ((@('S-1-5-18', 'S-1-5-32-544') + $(if ($adm) { @() } else { @($me) })) | Sort-Object -Unique) -join ','
    $r.freeOk = $s1.AreAccessRulesProtected -and ((Get-MutexSecurityProblem $s1) -eq '')

    # --- второй экземпляр программы (другой процесс) берёт тот же замок как свой и ждёт ---
    $base = Join-Path $env:TEMP ('w11p-t1-' + [guid]::NewGuid().ToString('N').Substring(0, 8)); $null = New-Item -ItemType Directory -Force $base
    $want = @('Test-Admin', 'Get-MutexTrustedSids', 'Test-MutexOwnerTrusted', 'Get-MutexSecurityProblem', 'New-ProgramMutexSecurity', 'Open-ProgramMutex')
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Fns, [ref]$null, [ref]$null)
    $wText = (@($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $want -contains $n.Name }, $true)) | ForEach-Object { $_.Extent.Text }) -join "`r`n"
    $worker = Join-Path $base 'worker.ps1'
    Set-Content -LiteralPath $worker -Encoding UTF8 -Value (@'
param($Name, $Mode, $Gate)
'@ + "`r`n" + $wText + "`r`n" + @'
if ($Gate) { $until = (Get-Date).AddSeconds(30); while (-not (Test-Path -LiteralPath $Gate) -and (Get-Date) -lt $until) { Start-Sleep -Milliseconds 20 } }
try { $m = Open-ProgramMutex $Name } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 3 }
if ($Mode -eq 'held') { $got = $m.WaitOne(300); if ($got) { $m.ReleaseMutex(); exit 4 }; exit 0 }
try { $got = $m.WaitOne(20000) } catch [System.Threading.AbandonedMutexException] { $got = $true }
if (-not $got) { exit 5 }
Start-Sleep -Milliseconds 100
$m.ReleaseMutex(); $m.Dispose(); exit 0
'@)
    $ps = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $null = $m1.WaitOne(0)
    $pw = Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $worker + '"'), '-Name', $n1, '-Mode', 'held') -PassThru -WindowStyle Hidden -Wait
    $r.secondHeld = $pw.ExitCode
    $m1.ReleaseMutex(); $m1.Dispose()

    # --- одновременный запуск: 5 процессов разом заводят и берут один новый замок ---
    $n2 = 'Global\W11P-T1-' + [guid]::NewGuid().ToString('N')
    $gate = Join-Path $base 'go'
    $procs = @()
    foreach ($i in 1..5) { $procs += Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $worker + '"'), '-Name', $n2, '-Mode', 'race', '-Gate', ('"' + $gate + '"')) -PassThru -WindowStyle Hidden }
    Start-Sleep -Milliseconds 1500
    Set-Content -LiteralPath $gate -Value 'go'
    foreach ($p in $procs) { $null = $p.WaitForExit(60000) }
    $r.raceCodes = (@($procs | ForEach-Object { $_.ExitCode }) -join ',')

    # --- имя заранее занято: «Все — полный доступ» ---
    $n3 = 'Global\W11P-T1-' + [guid]::NewGuid().ToString('N')
    $c = $false; $sq3 = [System.Threading.Mutex]::new($false, $n3, [ref]$c, (& $sec 'D:P(A;;0x1F0001;;;WD)'))
    $r.sqAll = ''; try { $x = Open-ProgramMutex $n3; $x.Dispose(); $r.sqAll = 'accepted' } catch { $r.sqAll = "$($_.Exception.Message)" }
    $sq3.Dispose()
    # --- владелец — сам пользователь (так заводит замок любая его обычная
    #     программа): у повышенного движка — чужой. Без прав администратора
    #     повышенность изображается заглушкой Test-Admin — решение то же.
    $n4 = 'Global\W11P-T1-' + [guid]::NewGuid().ToString('N')
    $s4 = & $sec ('O:' + $me + 'D:P(A;;0x1F0001;;;SY)(A;;0x1F0001;;;BA)(A;;0x1F0001;;;' + $me + ')')
    $c = $false; $sq4 = [System.Threading.Mutex]::new($false, $n4, [ref]$c, $s4)
    $r.sqSelfElevated = & { function Test-Admin { $true }; try { $x = Open-ProgramMutex $n4; $x.Dispose(); 'accepted' } catch { "$($_.Exception.Message)" } }
    $r.sqSelfReal = $(try { $x = Open-ProgramMutex $n4; $x.Dispose(); 'accepted' } catch { "$($_.Exception.Message)" })
    # тот же чужой замок на имени Firefox — запись policies.json отказывает, файл не тронут
    $ffd = Join-Path $base 'ff\distribution'; $null = New-Item -ItemType Directory -Force $ffd
    $fff = Join-Path $ffd 'policies.json'
    [IO.File]::WriteAllText($fff, '{"policies":{"Keep":true}}', (New-Object System.Text.UTF8Encoding($false)))
    $ffb = [Convert]::ToBase64String([IO.File]::ReadAllBytes($fff))
    $c = $false
    $sqf = $null
    try { $sqf = [System.Threading.Mutex]::new($false, 'Global\Win11Privacy-FirefoxPolicies', [ref]$c, $s4) } catch { }
    $r.ffSquatMade = [bool]($sqf -and $c)
    if ($r.ffSquatMade) {
        $fr = & { function Test-Admin { $true }; Update-FirefoxPoliciesFile $fff 'X' 1 }
        $r.ffRefused = (-not $fr.ok) -and ("$($fr.why)" -match 'замок') -and ([Convert]::ToBase64String([IO.File]::ReadAllBytes($fff)) -eq $ffb)
        $r.ffWhy = "$($fr.why)"
        $sqf.Dispose()
    }
    $sq4.Dispose()
    # --- имя занято объектом другого вида и замком без доступа ---
    $n5 = 'Global\W11P-T1-' + [guid]::NewGuid().ToString('N')
    $ev = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::ManualReset, $n5)
    $r.sqEvent = $(try { $x = Open-ProgramMutex $n5; $x.Dispose(); 'accepted' } catch { "$($_.Exception.Message)" })
    $ev.Dispose()
    $n6 = 'Global\W11P-T1-' + [guid]::NewGuid().ToString('N')
    $c = $false; $sq6 = [System.Threading.Mutex]::new($false, $n6, [ref]$c, (& $sec 'D:P'))
    $r.sqDenied = $(try { $x = Open-ProgramMutex $n6; $x.Dispose(); 'accepted' } catch { "$($_.Exception.Message)" })
    $sq6.Dispose()
    # --- администратор: владелец «Администраторы», но ждать могут Пользователи ---
    if ($adm) {
        $n7 = 'Global\W11P-T1-' + [guid]::NewGuid().ToString('N')
        $c = $false; $sq7 = [System.Threading.Mutex]::new($false, $n7, [ref]$c, (& $sec 'O:BAD:P(A;;0x1F0001;;;BA)(A;;0x100000;;;BU)'))
        $r.admBadDacl = $(try { $x = Open-ProgramMutex $n7; $x.Dispose(); 'accepted' } catch { "$($_.Exception.Message)" })
        $sq7.Dispose()
    }
    & cmd.exe /c ('rmdir /s /q "' + $base + '"') 2>$null
    $r
}
$t1Done = Wait-Job $t1Job -Timeout 180
$t1 = $(if ($t1Done) { @(Receive-Job $t1Job) | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1 } else { $null })
Remove-Job $t1Job -Force
Check 'T-1: проверки замков не зависают' ($null -ne $t1)
if ($t1) {
    Check ("T-1: решение «свой / чужой» по владельцу и правам ({0} случаев, повышенный движок)" -f $t1.sddlN) (-not $t1.sddlBad) $t1.sddlBad
    Check 'T-1: права замка не читаются (дескриптор без READ_CONTROL) — чужой' ([bool]$t1.nullSec)
    Check 'T-1: SID самой учётной записи «свой» только без повышения; SYSTEM и Администраторы — всегда' ($t1.selfRule -and $t1.sysBa)
    Check 'T-1: имени нет — заводится свой замок (владелец «Администраторы» у повышенного движка, права закрыты)' ($t1.freeOk -and $t1.freeOwner -eq $t1.freeWantOwner -and $t1.freeSids -eq $t1.freeWantSids) ("владелец {0}, права {1}" -f $t1.freeOwner, $t1.freeSids)
    Check 'T-1: второй экземпляр (другой процесс) открывает свой замок и ждёт, пока он занят' ($t1.secondHeld -eq 0) ("код " + $t1.secondHeld)
    Check 'T-1: одновременный запуск — 5 процессов разом заводят и берут один замок, отказов нет' ($t1.raceCodes -eq '0,0,0,0,0') $t1.raceCodes
    Check 'T-1: имя заранее занято замком с правами «Все» — отказ' ($t1.sqAll -ne 'accepted' -and $t1.sqAll -match 'не только системе') $t1.sqAll
    Check 'T-1: замок с владельцем-пользователем (обычная программа) — у повышенного движка отказ' ($t1.sqSelfElevated -ne 'accepted' -and $t1.sqSelfElevated -match 'чужой учётной') $t1.sqSelfElevated
    if ($t1.admin) { Check 'T-1 (админ): тот же замок — отказ и без заглушки' ($t1.sqSelfReal -ne 'accepted') $t1.sqSelfReal }
    else { Check 'T-1: без повышения границы прав нет — замок своей учётной записи годится' ($t1.sqSelfReal -eq 'accepted') $t1.sqSelfReal }
    if ($t1.ffSquatMade) { Check 'T-1: чужой замок на имени Firefox — policies.json не пишется, файл не тронут' ([bool]$t1.ffRefused) $t1.ffWhy }
    else { Write-Host '  [--]   T-1: имя замка Firefox занято другим запуском — проверка чужого замка Firefox пропущена' }
    Check 'T-1: имя занято объектом другого вида — отказ' ($t1.sqEvent -ne 'accepted' -and $t1.sqEvent -match 'другого вида') $t1.sqEvent
    Check 'T-1: чужой замок без доступа — отказ при открытии' ($t1.sqDenied -ne 'accepted' -and $t1.sqDenied -match 'нет доступа') $t1.sqDenied
    if ($t1.admin) { Check 'T-1 (админ): владелец «Администраторы», но ждать могут Пользователи — отказ' ($t1.admBadDacl -ne 'accepted') $t1.admBadDacl }
    else { Write-Host '  [--]   T-1: замок с владельцем «Администраторы» и чужими правами: пропущено (нужны права администратора; решение проверено выше по SDDL)' }
}
$t1Text = [regex]::Match($remedAllFns, "(?s)function Open-ProgramMutex \{.*?\r?\n\}").Value
Check 'T-1: проверяется тот же дескриптор, что ждётся — после проверки имя заново не открывается' (
      $t1Text -and ($t1Text.Substring($t1Text.IndexOf('GetAccessControl')) -notmatch 'Mutex\]::new|OpenExisting|TryOpenExisting'))
Check 'T-1: замок Firefox — через общий Open-ProgramMutex, без Local\' (($remedAllFns -match "Open-ProgramMutex 'Global\\Win11Privacy-FirefoxPolicies'") -and ($remedAllFns -notmatch 'Local\\Win11Privacy'))

# =========================================================================== #
#  T-2. Копия политики аудита (auditpol /backup) — только в личной папке
# =========================================================================== #
Write-Host ''
Write-Host 'T-2: копия политики аудита — личная рабочая папка'
$t2Job = Start-Job -ArgumentList $remedAllFns, $remedVars -ScriptBlock {
    param($Fns, $Vars)
    Invoke-Expression $Fns; Invoke-Expression $Vars
    $r = @{}
    $adm = [bool](Test-Admin); $r.admin = $adm
    $script:SafeRoot = ''      # корня ещё нет (первый запуск)
    $script:Files = New-Object System.Collections.Generic.List[string]
    $script:Mode = ''
    $script:Junk = Join-Path $env:TEMP ('w11p-t2-' + [guid]::NewGuid().ToString('N').Substring(0, 8)); $null = New-Item -ItemType Directory -Force $script:Junk
    $script:Bait = Join-Path $script:Junk 'bait'; $null = New-Item -ItemType Directory -Force $script:Bait
    [IO.File]::WriteAllText((Join-Path $script:Bait 'keep.txt'), 'keep')
    function auditpol.exe {
        $a = $args -join ' '
        if ($a -match '/backup /file:(\S+)') {
            $f = $Matches[1]; $script:Files.Add($f)
            if ($script:Mode -eq 'fail') { $global:LASTEXITCODE = 1; return }
            if ($script:Mode -eq 'dir') { $null = New-Item -ItemType Directory -Force $f; $global:LASTEXITCODE = 0; return }
            if ($script:Mode -eq 'junction') { & cmd.exe /c ('mklink /J "' + $f + '" "' + $script:Bait + '"') | Out-Null; $global:LASTEXITCODE = 0; return }
            $val = $(switch ($script:Mode) { 'badval' { '7' } 'nonnum' { 'x' } 'emptyval' { '' } default { '3' } })
            $t = "Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value`r`nPC,System,Filtering Platform Connection," + $script:AuditGuid + ",x,," + $val + "`r`n"
            if ($script:Mode -eq 'big') { $t += ('#' * 5MB) }
            [IO.File]::WriteAllText($f, $t, (New-Object System.Text.UTF8Encoding($true)))
            if ($script:Mode -eq 'extra') { [IO.File]::WriteAllText((Join-Path (Split-Path $f -Parent) 'planted.csv'), 'x') }
            if ($script:Mode -eq 'old') { (Get-Item -LiteralPath $f).CreationTime = (Get-Date).AddHours(-2) }
            $global:LASTEXITCODE = 0; return
        }
        $global:LASTEXITCODE = 0
    }
    $r.ok = Get-AuditSetting
    $f0 = $script:Files[$script:Files.Count - 1]
    $r.okDir = Split-Path $f0 -Parent
    $r.okLeaf = Split-Path $f0 -Leaf
    $r.okGone = -not (Test-Path -LiteralPath $r.okDir)
    $r.okBase = [IO.Path]::GetFullPath((Split-Path $r.okDir -Parent)).TrimEnd('\')
    $r.wantBase = $(if ($adm) { [IO.Path]::GetFullPath((Join-Path $env:SystemRoot 'Temp')).TrimEnd('\') } else { [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') })
    $r.userTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $modes = [ordered]@{ extra = -1; dir = -1; junction = -1; old = -1; big = -1; badval = -1; nonnum = -1; fail = -1; emptyval = 0 }
    $bad = @()
    foreach ($m in $modes.Keys) {
        $script:Mode = $m
        $v = Get-AuditSetting
        $d = Split-Path $script:Files[$script:Files.Count - 1] -Parent
        if ($v -ne $modes[$m] -or (Test-Path -LiteralPath $d)) { $bad += ("{0}: {1}, папка {2}" -f $m, $v, $(if (Test-Path -LiteralPath $d) { 'осталась' } else { 'убрана' })) }
    }
    $script:Mode = ''
    $r.modesBad = ($bad -join ' | '); $r.modesN = $modes.Count
    $r.baitKept = (Test-Path -LiteralPath (Join-Path $script:Bait 'keep.txt'))
    # повышенный движок, а места, куда обычной программе не дотянуться, нет —
    # копии нет вовсе (auditpol даже не зовётся), политика «не прочиталась»
    $before = $script:Files.Count
    $r.noPlace = & { function Test-Admin { $true }; function Test-PathTrusted { param($Path) $false }; function Test-DirChainSecure { param($Dir) $false }; Get-AuditSetting }
    $r.noPlaceCalls = $script:Files.Count - $before
    # корень есть, но не защищён (временная папка) — не используется
    $script:SafeRoot = Join-Path $script:Junk 'fake-root'; $null = New-Item -ItemType Directory -Force $script:SafeRoot
    $r.fakeRootTrusted = [bool](Test-PathTrusted $script:SafeRoot)
    if ($adm) {
        $d = New-PrivateWorkDir 'w11p-audit-'
        $r.admDir = $d
        if ($d) {
            $acl = Get-Acl -LiteralPath $d
            $r.admUnder = [IO.Path]::GetFullPath((Split-Path $d -Parent)).TrimEnd('\')
            $r.admOwner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
            $r.admProtected = $acl.AreAccessRulesProtected
            $r.admSids = (@($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique) -join ',')
            $r.admTrusted = [bool](Test-ItemTrusted (Get-Item -LiteralPath $d -Force))
            Remove-PrivateWorkDir $d
            $r.admGone = -not (Test-Path -LiteralPath $d)
        }
        # оставшиеся от оборванного запуска: своя старая — убирается, свежая и
        # ссылка — нет (по ссылке не заходим, её цель цела)
        $sb = Join-Path $script:Junk 'stale'; $null = New-Item -ItemType Directory -Force $sb
        $old = New-Item -ItemType Directory -Force (Join-Path $sb 'w11p-audit-old'); [IO.File]::WriteAllText((Join-Path $old.FullName 'audit.csv'), 'x'); $old.LastWriteTime = (Get-Date).AddHours(-3)
        $new = New-Item -ItemType Directory -Force (Join-Path $sb 'w11p-audit-new')
        & cmd.exe /c ('mklink /J "' + (Join-Path $sb 'w11p-audit-lnk') + '" "' + $script:Bait + '"') | Out-Null
        (Get-Item -LiteralPath (Join-Path $sb 'w11p-audit-lnk') -Force).LastWriteTime = (Get-Date).AddHours(-3)
        Remove-StalePrivateDirs $sb 'w11p-audit-'
        $r.staleOld = -not (Test-Path -LiteralPath $old.FullName)
        $r.staleNew = (Test-Path -LiteralPath $new.FullName)
        $r.staleBait = (Test-Path -LiteralPath (Join-Path $script:Bait 'keep.txt'))
    }
    & cmd.exe /c ('rmdir /s /q "' + $script:Junk + '"') 2>$null
    $r
}
$t2Done = Wait-Job $t2Job -Timeout 120
$t2 = $(if ($t2Done) { @(Receive-Job $t2Job) | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1 } else { $null })
Remove-Job $t2Job -Force
Check 'T-2: проверки копии политики аудита не зависают' ($null -ne $t2)
if ($t2) {
    Check 'T-2: политика читается из копии в личной папке, папка убрана' ($t2.ok -eq 3 -and $t2.okLeaf -eq 'audit.csv' -and (Split-Path $t2.okDir -Leaf) -like 'w11p-audit-*' -and $t2.okGone) ("значение {0}, папка {1}" -f $t2.ok, $t2.okDir)
    if ($t2.admin) {
        Check 'T-2 (админ): корня нет — копия в своей папке Windows\Temp, не во временной папке пользователя' ($t2.okBase -eq $t2.wantBase -and $t2.okBase -ne $t2.userTemp) $t2.okBase
    } else {
        Check 'T-2: без повышения — временная папка пользователя (границы прав нет)' ($t2.okBase -eq $t2.wantBase) $t2.okBase
    }
    Check ("T-2: подменённая, лишняя, старая, огромная, не та копия, ссылка вместо файла — «не прочиталось» ({0} случаев), папка убрана" -f $t2.modesN) (-not $t2.modesBad) $t2.modesBad
    Check 'T-2: ссылка вместо копии — её цель не тронута' ([bool]$t2.baitKept)
    Check 'T-2: повышенный движок без защищённого места — копии нет вовсе, auditpol не зовётся, -1' ($t2.noPlace -eq -1 -and $t2.noPlaceCalls -eq 0) ("значение {0}, вызовов {1}" -f $t2.noPlace, $t2.noPlaceCalls)
    Check 'T-2: корень во временной папке не считается защищённым местом' (-not $t2.fakeRootTrusted)
    if ($t2.admin) {
        Check 'T-2 (админ): личная папка — права только SYSTEM и Администраторам, без наследования, владелец «Администраторы»' (
              $t2.admDir -and $t2.admProtected -and $t2.admOwner -eq 'S-1-5-32-544' -and $t2.admSids -eq 'S-1-5-18,S-1-5-32-544' -and $t2.admTrusted -and $t2.admGone) ("{0} {1} {2}" -f $t2.admDir, $t2.admOwner, $t2.admSids)
        Check 'T-2 (админ): корень не защищён — личная папка в Windows\Temp, а не в нём' ($t2.admUnder -eq $t2.wantBase) $t2.admUnder
        Check 'T-2 (админ): оставшиеся от обрыва — своя старая убирается, свежая и ссылка остаются, цель ссылки цела' ($t2.staleOld -and $t2.staleNew -and $t2.staleBait)
    } else {
        Write-Host '  [--]   T-2: права личной папки, Windows\Temp и уборка оставшихся: пропущено (нужны права администратора)'
    }
}
$auText = [regex]::Match($remedAllFns, "(?s)function Get-AuditSetting \{.*?\r?\n\}").Value
Check 'T-2: Get-AuditSetting не берёт временную папку пользователя и читает копию через Read-PrivateWorkFile' (
      $auText -and $auText -notmatch 'GetTempPath' -and $auText -match 'New-PrivateWorkDir' -and $auText -match 'Read-PrivateWorkFile' -and $auText -match 'Remove-PrivateWorkDir')

# =========================================================================== #
#  T-3. Восстановление из копии по шагам: запись о ходе, сверка, обрыв
# =========================================================================== #
Write-Host ''
Write-Host 'T-3: восстановление из копии — стадии, сверка, обрыв посередине'
$t3Job = Start-Job -ArgumentList $remedAllFns, $remedVars -ScriptBlock {
    param($Fns, $Vars)
    Invoke-Expression $Fns; Invoke-Expression $Vars
    $r = @{}
    $base = Join-Path $env:TEMP ('w11p-t3-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Force (Join-Path $base 'safe'), (Join-Path $base 'data')
    $script:SafeRoot = Join-Path $base 'safe'; $script:DataDir = Join-Path $base 'data'
    $script:RootState = $true
    $script:SignKey = [byte[]](1..32)
    function Assert-SafeRoot { $true }
    function Test-ItemTrusted { param($Item) -not ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) }
    # две ветки — пробные ключи; копия их и только их
    $tag = 'W11PRemed-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
    $kA = "HKCU:\Software\$tag\Alpha"; $kB = "HKCU:\Software\$tag\Beta"
    $script:Defs = @(@{ T = 'reg'; P = $kA; M = 't' }, @{ T = 'reg'; P = $kB; M = 't' })
    $set = {
        param($a, $b)
        $null = New-Item -Path $kA -Force; $null = New-Item -Path $kB -Force; $null = New-Item -Path "$kB\Sub" -Force
        Set-ItemProperty -Path $kA -Name 'Dw' -Value $a -Type DWord
        Set-ItemProperty -Path $kA -Name 'Str' -Value ('a"b\c-' + $a) -Type String
        Set-ItemProperty -Path $kB -Name 'Multi' -Value @('x', "y$b") -Type MultiString
        Set-ItemProperty -Path "$kB\Sub" -Name 'Bin' -Value ([byte[]](1..120)) -Type Binary
    }
    $state = { '{0}|{1}|{2}' -f (Get-ItemProperty -Path $kA -Name Dw -ErrorAction SilentlyContinue).Dw, (Get-ItemProperty -Path $kA -Name Str -ErrorAction SilentlyContinue).Str, (@((Get-ItemProperty -Path $kB -Name Multi -ErrorAction SilentlyContinue).Multi) -join ';') }
    & $set 1 1
    $want = & $state
    $bk = New-RegBackup @($kA, $kB)
    $r.bkOk = [bool]$bk.dir -and $bk.saved -eq 2
    $store = Join-Path $script:SafeRoot 'backups'
    $storeCount = { @(Get-ChildItem -LiteralPath $store -Directory -Force -ErrorAction SilentlyContinue).Count }
    $rec = { Read-OpRecord 'restore' }
    $realInvoke = ${function:Invoke-RegExe}
    $realExport = ${function:Export-RegKey}
    $realWrite = ${function:Write-OpRecord}

    # --- обычное восстановление: снимок «до», импорт, сверка, запись убрана ---
    & $set 9 9
    $n0 = & $storeCount
    $x = Restore-BackupFolder $bk.dir
    $r.okState = $x.state; $r.okRestored = $x.restored; $r.okErr = $x.error
    $r.okReg = ((& $state) -eq $want)
    $r.okSnap = [bool]$x.snapshot -and (Test-Path -LiteralPath $x.snapshot) -and ((& $storeCount) -eq $n0 + 1)
    $snapText = ''
    if ($r.okSnap) { foreach ($f in @(Get-ChildItem -LiteralPath $x.snapshot -Filter '*.reg')) { $snapText += [Text.Encoding]::Unicode.GetString([IO.File]::ReadAllBytes($f.FullName)) } }
    $r.okSnapHasBefore = ($snapText -match 'dword:00000009')
    $r.okNoRecord = ((& $rec).state -eq 'none')
    $r.okLockFree = ((Test-OpRunning 'restore') -eq $false)
    $r.okFiles = (@($x.files | Where-Object { $_.state -eq 'restored' }).Count -eq 2)

    # --- импорт «прошёл», а в реестре не то (reg.exe код 0, ветка Beta не записалась) ---
    & $set 5 5
    $x = & { function Invoke-RegExe { param([string]$Arguments, [int]$TimeoutMs = 300000) if ($Arguments -match '^import ".*Beta.*"$') { return @{ code = 0; error = '' } }; & $realInvoke $Arguments $TimeoutMs }; Restore-BackupFolder $bk.dir }
    $r.difState = $x.state; $r.difRestored = $x.restored; $r.difFailed = $x.failed; $r.difImported = $x.imported
    $rc = Get-RestoreRecovery
    $r.difRecovery = $rc.state; $r.difRecReq = $rc.recoveryRequired; $r.difRecRestored = $rc.restored; $r.difRecFiles = $rc.files
    $r.difSnap = $x.snapshot
    # --- повтор той же копии: доводит, снимок «до» прежний (не переснимается) ---
    $n1 = & $storeCount
    $x = Restore-BackupFolder $bk.dir
    $r.resState = $x.state; $r.resResumed = $x.resumed; $r.resReg = ((& $state) -eq $want)
    $r.resSnapSame = ($x.snapshot -eq $r.difSnap) -and ((& $storeCount) -eq $n1)
    $r.resNoRecord = ((& $rec).state -eq 'none')

    # --- сверить не с чем (ветка заново не выгружается) — не «восстановлено» ---
    & $set 6 6
    $x = & { function Export-RegKey { param([string]$Key, [string]$File) if ((Split-Path $File -Leaf) -like 'verify-*') { return 'отказ выгрузки (тест)' }; & $realExport $Key $File }; Restore-BackupFolder $bk.dir }
    $r.unvState = $x.state; $r.unvCount = $x.unverified
    $x = Restore-BackupFolder $bk.dir
    $r.unvFixed = ($x.state -eq 'Restored' -and $x.resumed)

    # --- состояние «до» не сохранилось — не импортируется ничего ---
    & $set 7 7
    $before = & $state
    $x = & { function Export-RegKey { param([string]$Key, [string]$File) if ($File -like '*\backup-*') { return 'нет места (тест)' }; & $realExport $Key $File }; Restore-BackupFolder $bk.dir }
    $r.snapFailState = $x.state; $r.snapFailImported = $x.imported; $r.snapFailErr = $x.error
    $r.snapFailReg = ((& $state) -eq $before); $r.snapFailNoRec = ((& $rec).state -eq 'none')

    # --- запись о ходе не пишется с самого начала — не импортируется ничего ---
    $x = & { function Write-OpRecord { param($Name, $Data) throw 'диск недоступен (тест)' }; Restore-BackupFolder $bk.dir }
    $r.recFailState = $x.state; $r.recFailImported = $x.imported; $r.recFailReg = ((& $state) -eq $before)

    # --- запись перестала писаться после первого файла — дальше не импортирует ---
    $script:W = 0
    $x = & { function Write-OpRecord { param($Name, $Data) $script:W++; if ($script:W -ge 4) { throw 'диск недоступен (тест)' }; & $realWrite $Name $Data }; Restore-BackupFolder $bk.dir }
    $r.midFailState = $x.state; $r.midFailImported = $x.imported
    $r.midFailRec = "$((& $rec).data.state)"
    $x = Restore-BackupFolder $bk.dir
    $r.midFailFixed = ($x.state -eq 'Restored' -and $x.resumed -and ((& $state) -eq $want))

    # --- второе восстановление в это время (замок занят другим процессом) ---
    $lockFile = Join-Path $script:SafeRoot 'restore.lock'
    $holder = Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile', '-Command',
        ("`$f = [IO.File]::Open('{0}', 'OpenOrCreate', 'ReadWrite', 'None'); Start-Sleep -Seconds 25; `$f.Dispose()" -f $lockFile))
    $until = (Get-Date).AddSeconds(10)
    do { Start-Sleep -Milliseconds 200; $busy = (Test-OpRunning 'restore') } while ($busy -ne $true -and (Get-Date) -lt $until)
    & $set 8 8
    $before = & $state
    $x = Restore-BackupFolder $bk.dir
    $r.busyRunning = ($busy -eq $true)
    $r.busyState = $x.state; $r.busyImported = $x.imported; $r.busyErr = $x.error; $r.busyReg = ((& $state) -eq $before)
    try { $holder.Kill() } catch { }
    $null = $holder.WaitForExit(10000)

    # --- запись подделана (подпись не сходится) — отложена, по ней ничего не делается ---
    & $realWrite 'restore' ([ordered]@{ state = 'InProgress'; folder = 'x'; path = 'C:\evil'; snapshot = 'C:\evil'; attempt = 1; files = @() })
    $p = Join-Path $script:DataDir 'op-restore.json'
    $t = [IO.File]::ReadAllText($p); [IO.File]::WriteAllText($p, $t.Replace('evil', 'other'))
    $r.tamperRead = (Read-OpRecord 'restore').state
    $x = Restore-BackupFolder $bk.dir
    $r.tamperState = $x.state; $r.tamperResumed = $x.resumed
    $r.tamperAside = (@(Get-ChildItem -LiteralPath $script:DataDir -Filter 'op-restore.untrusted-*.json').Count -eq 1)

    # --- запись сейчас не читается (файл занят) — «не читается», а не «нет» ---
    & $set 3 3
    & $realWrite 'restore' ([ordered]@{ state = 'PartiallyRestored'; folder = 'x'; path = 'x'; snapshot = ''; attempt = 1; files = @() })
    $hold = [IO.File]::Open($p, 'Open', 'Read', 'None')
    $x = Restore-BackupFolder $bk.dir
    $hold.Dispose()
    $r.unreadState = $x.state; $r.unreadImported = $x.imported; $r.unreadErr = $x.error
    $null = Remove-OpRecord 'restore'

    # --- обрыв процесса на каждой стадии (настоящий reg.exe, процесс умирает) ---
    $child = Join-Path $base 'child.ps1'
    Set-Content -LiteralPath $child -Encoding UTF8 -Value ('param($Safe, $Data, $KA, $KB, $Bk, $Stage)' + "`r`n" + $Fns + "`r`n" + $Vars + "`r`n" + @'
$script:SafeRoot = $Safe; $script:DataDir = $Data; $script:RootState = $true; $script:SignKey = [byte[]](1..32)
function Assert-SafeRoot { $true }
function Test-ItemTrusted { param($Item) -not ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) }
$script:Defs = @(@{ T = 'reg'; P = $KA; M = 't' }, @{ T = 'reg'; P = $KB; M = 't' })
$realWrite = ${function:Write-OpRecord}; $realInvoke = ${function:Invoke-RegExe}
$script:W = 0; $script:I = 0
function Write-OpRecord { param($Name, $Data) & $realWrite $Name $Data; $script:W++
    if ($Stage -eq 'prepared' -and $script:W -eq 1) { [Environment]::Exit(77) }
    if ($Stage -eq 'after-first' -and $script:W -eq 3) { [Environment]::Exit(77) } }
function Invoke-RegExe { param([string]$Arguments, [int]$TimeoutMs = 300000) $x = & $realInvoke $Arguments $TimeoutMs
    if ($Arguments -like 'import*') { $script:I++; if ($Stage -eq 'mid-import' -and $script:I -eq 1) { [Environment]::Exit(77) } }
    $x }
$null = Restore-BackupFolder $Bk
exit 0
'@)
    $r.workBefore = @(Get-ChildItem -LiteralPath $script:SafeRoot -Directory -Force | Where-Object { $_.Name -ne 'backups' }).Count
    $crash = New-Object System.Collections.Generic.List[object]
    foreach ($st in @('prepared', 'mid-import', 'after-first')) {
        & $set 4 4
        $p2 = Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -PassThru -Wait -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $child + '"'),
            '-Safe', ('"' + $script:SafeRoot + '"'), '-Data', ('"' + $script:DataDir + '"'), '-KA', ('"' + $kA + '"'), '-KB', ('"' + $kB + '"'), '-Bk', ('"' + $bk.dir + '"'), '-Stage', $st)
        $rc = Get-RestoreRecovery
        $lockFree = ((Test-OpRunning 'restore') -eq $false)
        $x = Restore-BackupFolder $bk.dir
        $crash.Add(@{ stage = $st; code = $p2.ExitCode; rcState = "$($rc.state)"; rcReq = [bool]$rc.recoveryRequired; rcRestored = [int]$rc.restored; rcStage = "$($rc.stage)"
                      lockFree = $lockFree; after = "$($x.state)"; resumed = [bool]$x.resumed; reg = ((& $state) -eq $want); noRec = ((& $rec).state -eq 'none') })
    }
    $r.crash = $crash.ToArray()
    $r.workLeft = @(Get-ChildItem -LiteralPath $script:SafeRoot -Directory -Force | Where-Object { $_.Name -ne 'backups' }).Count
    Remove-Item -Path "HKCU:\Software\$tag" -Recurse -Force -ErrorAction SilentlyContinue
    & cmd.exe /c ('rmdir /s /q "' + $base + '"') 2>$null
    $r
}
$t3Done = Wait-Job $t3Job -Timeout 600
$t3 = $(if ($t3Done) { @(Receive-Job $t3Job) | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1 } else { $null })
Remove-Job $t3Job -Force
Check 'T-3: проверки восстановления из копии не зависают' ($null -ne $t3)
if ($t3) {
    Check 'T-3: копия пробных веток сделана настоящим reg.exe' ([bool]$t3.bkOk)
    Check 'T-3: восстановление — Restored, значения в реестре как в копии (сверено)' ($t3.okState -eq 'Restored' -and $t3.okRestored -eq 2 -and $t3.okReg -and $t3.okFiles) ("{0}, вернулось {1}, {2}" -f $t3.okState, $t3.okRestored, $t3.okErr)
    Check 'T-3: до импорта состояние «до» сохранено подписанной копией в хранилище' ($t3.okSnap -and $t3.okSnapHasBefore)
    Check 'T-3: после успеха записи о ходе нет, замок свободен' ($t3.okNoRecord -and $t3.okLockFree)
    Check 'T-3: reg.exe «прошёл», а в реестре не то — PartiallyRestored, не успех' ($t3.difState -eq 'PartiallyRestored' -and $t3.difRestored -eq 1 -and $t3.difFailed -eq 1 -and $t3.difImported -eq 2) ("{0} {1}/{2}" -f $t3.difState, $t3.difRestored, $t3.difFailed)
    Check 'T-3: следующий запуск видит RecoveryRequired: вернулось 1 из 2' ($t3.difRecovery -eq 'RecoveryRequired' -and $t3.difRecReq -and $t3.difRecRestored -eq 1 -and $t3.difRecFiles -eq 2) $t3.difRecovery
    Check 'T-3: повтор той же копии доводит восстановление; снимок «до» прежний, не переснят' ($t3.resState -eq 'Restored' -and $t3.resResumed -and $t3.resReg -and $t3.resSnapSame -and $t3.resNoRecord)
    Check 'T-3: сверить не с чем (ветка не выгрузилась) — не «восстановлено», повтор доводит' ($t3.unvState -eq 'PartiallyRestored' -and $t3.unvCount -eq 2 -and $t3.unvFixed) ("{0}, не сверено {1}" -f $t3.unvState, $t3.unvCount)
    Check 'T-3: состояние «до» не сохранилось — не импортировано ничего, реестр не тронут, записи нет' ($t3.snapFailState -eq 'Failed' -and $t3.snapFailImported -eq 0 -and $t3.snapFailReg -and $t3.snapFailNoRec -and $t3.snapFailErr -match 'не сохранилось') $t3.snapFailErr
    Check 'T-3: запись о ходе не пишется — не импортировано ничего' ($t3.recFailState -eq 'Failed' -and $t3.recFailImported -eq 0 -and $t3.recFailReg)
    Check 'T-3: запись перестала писаться после первого файла — дальше не импортирует, итог честный, повтор доводит' ($t3.midFailState -eq 'PartiallyRestored' -and $t3.midFailImported -eq 1 -and $t3.midFailFixed) ("{0}, импортировано {1}, на диске {2}" -f $t3.midFailState, $t3.midFailImported, $t3.midFailRec)
    Check 'T-3: другое восстановление держит замок — отказ, не импортировано ничего' ($t3.busyRunning -and $t3.busyState -eq 'Failed' -and $t3.busyImported -eq 0 -and $t3.busyReg -and $t3.busyErr -match 'другое восстановление') $t3.busyErr
    Check 'T-3: подделанная запись о ходе — не верится, отложена, по ней ничего не делается' ($t3.tamperRead -eq 'untrusted' -and $t3.tamperState -eq 'Restored' -and -not $t3.tamperResumed -and $t3.tamperAside) ("{0} {1}" -f $t3.tamperRead, $t3.tamperState)
    Check 'T-3: запись о ходе не читается сейчас — отказ, а не «записи нет»' ($t3.unreadState -eq 'Failed' -and $t3.unreadImported -eq 0 -and $t3.unreadErr -match 'не читается') $t3.unreadErr
    foreach ($c in @($t3.crash)) {
        if ($c.stage -eq 'prepared') {
            Check 'T-3 обрыв после записи Prepared, до импорта — Interrupted (реестр не тронут), замок свободен, следующий запуск начинает заново' (
                  $c.code -eq 77 -and $c.rcState -eq 'Interrupted' -and -not $c.rcReq -and $c.lockFree -and $c.after -eq 'Restored' -and -not $c.resumed -and $c.reg -and $c.noRec) ("{0} {1} {2}" -f $c.code, $c.rcState, $c.after)
        } else {
            Check ("T-3 обрыв ({0}): следующий запуск — RecoveryRequired, замок свободен; повтор доводит до Restored" -f $c.stage) (
                  $c.code -eq 77 -and $c.rcState -eq 'RecoveryRequired' -and $c.rcReq -and $c.rcStage -eq 'InProgress' -and $c.lockFree -and $c.after -eq 'Restored' -and $c.resumed -and $c.reg -and $c.noRec) ("код {0}, {1}/{2}, вернулось {3}, затем {4}" -f $c.code, $c.rcState, $c.rcStage, $c.rcRestored, $c.after)
        }
    }
    Check 'T-3: обрывы проверены на трёх стадиях' (@($t3.crash).Count -eq 3)
    Check 'T-3: рабочие папки — только от оборванных запусков, внутри защищённого корня (их уберёт запуск через час)' ($t3.workBefore -eq 0 -and $t3.workLeft -le 3) ("до обрывов {0}, после {1}" -f $t3.workBefore, $t3.workLeft)
}
$rbBlock = [regex]::Match($remedAllFns, "(?s)function Restore-BackupFolder \{.*?\r?\n\}").Value
Check 'T-3: стадия файла ложится на диск раньше запуска reg.exe' ($rbBlock -match "(?s)state = 'importing'.*?Write-OpRecord .*?Invoke-RegExe \('import")
$rbCalls = [regex]::Matches((Get-Content -LiteralPath $engine -Raw -Encoding UTF8), '(?m)^(?!\s*#).*\bRestore-BackupFolder \$').Count
Check 'T-3: импорт сам по себе не повторяется — вызывает его только -RestoreBackup (действие человека)' ($rbCalls -eq 1) ("вызовов: " + $rbCalls)
$restoreBlock2 = [regex]::Match((Get-Content -LiteralPath $engine -Raw -Encoding UTF8), "(?s)if \(\`$RestoreBackup\) \{.*?\n\}").Value
Check 'T-3: код выхода по итогу — 0 Restored, 2 PartiallyRestored, 1 ничего не импортировано' ($restoreBlock2 -match "exit \`$\(if \(\`$rb\.state -eq 'Restored'\) \{ 0 \} elseif \(\`$rb\.state -eq 'PartiallyRestored'\) \{ 2 \} else \{ 1 \}\)")

# =========================================================================== #
#  GDID: кто за компьютером, учётные данные, оборванное стирание
# =========================================================================== #
Write-Host ''
Write-Host 'GDID: контекст пользователя, учётные данные, оборванное стирание'
$gdJob = Start-Job -ArgumentList $remedAllFns, $remedVars -ScriptBlock {
    param($Fns, $Vars)
    Invoke-Expression $Fns; Invoke-Expression $Vars
    $r = @{}
    $base = Join-Path $env:TEMP ('w11p-gd-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Force (Join-Path $base 'safe'), (Join-Path $base 'data')
    $script:SafeRoot = Join-Path $base 'safe'; $script:DataDir = Join-Path $base 'data'; $script:RootState = $true; $script:SignKey = [byte[]](1..32)
    function Assert-SafeRoot { $true }

    # --- кто сидит за компьютером: только explorer этого сеанса ---
    $script:UserSid = 'S-1-5-21-1-2-3-1000'; $script:RunAccount = 'PC\admin'
    function Get-MachinePath { param($Key, $Name, $Default) 'C:\Users\desk' }
    $script:CimFilter = ''; $script:CimFail = $false; $script:FakeOwner = 'S-1-12-1-11-22-33-44'
    function Get-CimInstance { param($ClassName, $Filter, $ErrorAction) $script:CimFilter = "$Filter"; if ($script:CimFail) { throw 'WMI не отвечает (тест)' }; [pscustomobject]@{ ProcessId = 4 } }
    function Invoke-CimMethod { param($InputObject, $MethodName, $ErrorAction) [pscustomobject]@{ Sid = $script:FakeOwner } }
    $script:SessionUserCache = $null
    $o = Get-OtherSessionUser
    $r.sessFilter = $script:CimFilter
    $r.sessWant = ("SessionId={0}" -f [Diagnostics.Process]::GetCurrentProcess().SessionId)
    $r.entraSeen = ($null -ne $o -and $o.sid -eq 'S-1-12-1-11-22-33-44')
    $script:CimFail = $true; $script:SessionUserCache = $null
    $o = Get-OtherSessionUser
    $r.cimFailNull = ($null -eq $o); $r.cimFailErr = "$script:SessionUserError"
    # предварительная проверка стирания: «неизвестно, кто за компьютером» — не начинаем
    function Get-GdidScan { @{ copies = @(); unreadable = @(); unchecked = 0; profiles = @{ enumerationFailed = $false; unloadedProfiles = 0; unverified = $false; places = @(); errors = @() }; state = 'NotFound'; unknown = @() } }
    function Get-GdidServiceSnapshot { @{ complete = $true; services = @(); problems = @() } }
    $script:SessionUserCache = $null
    $pf = Get-GdidPreflight
    $r.preBlocked = (-not $pf.ok) -and ((@($pf.blockers) -join ' ') -match 'кто сидит за компьютером')
    $script:CimFail = $false; $script:SessionUserCache = $null
    $pf = Get-GdidPreflight
    $r.preOk = [bool]$pf.ok
    Remove-Item Function:\Get-GdidScan, Function:\Get-GdidServiceSnapshot

    # --- пользователи для учётных данных: и Entra ID, без _Classes и системных ---
    $script:FakeOwner = 'S-1-5-21-1-2-3-1000'; $script:SessionUserCache = $null
    function Get-GdidHiveNames { @('S-1-12-1-111-222-333-444', 'S-1-5-21-1-2-3-1002', 'S-1-5-21-1-2-3-1002_Classes', '.DEFAULT', 'S-1-5-18', 'S-1-5-21-1-2-3-1000') }
    $u = @(Get-GdidCredUsers)
    $r.credUsers = (@($u | ForEach-Object { "$($_.sid)|$($_.session)" }) -join ',')

    # --- проверка учётных данных в cmd: сбой списка — код 2, а не «записей нет» ---
    $fake = Join-Path $base 'fakecmd'; $null = New-Item -ItemType Directory -Force $fake
    Set-Content -LiteralPath (Join-Path $fake 'cmdkey.cmd') -Encoding ASCII -Value @(
        '@echo off', 'if "%W11P_CK%"=="fail" exit /b 5', 'if "%W11P_CK%"=="left" echo     Target: WindowsLive:target=virtualapp/didlogical', 'echo Currently stored credentials:', 'exit /b 0')
    $cmd = Get-CredCheckCmd @('WindowsLive:target=virtualapp/didlogical', 'MicrosoftAccount:target=SSO_POP_Device')
    $codes = @{}
    foreach ($m in @('fail', 'left', 'none')) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "$env:WINDIR\System32\cmd.exe"; $psi.Arguments = '/d /c ' + $cmd; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $fake
        $psi.EnvironmentVariables['PATH'] = $fake + ';' + $env:PATH; $psi.EnvironmentVariables['W11P_CK'] = $m
        $pp = [Diagnostics.Process]::Start($psi); $pp.WaitForExit(); $codes[$m] = $pp.ExitCode
    }
    $r.ckFail = $codes['fail']; $r.ckLeft = $codes['left']; $r.ckNone = $codes['none']
    # своё хранилище движка не прочиталось — не «убрано»
    function Get-OtherSessionUser { @{ sid = 'S-1-5-21-1-2-3-1001'; name = 'PC\desk'; profile = 'C:\Users\desk'; isMe = $false } }
    function Get-GdidCredUsers { @(@{ name = 'PC\desk'; sid = 'S-1-5-21-1-2-3-1001'; session = $true }) }
    function Invoke-OneShotTask { $true }
    $script:CkFail = $true
    function cmdkey.exe { if ($script:CkFail) { $global:LASTEXITCODE = 5; 'CMDKEY: error (test)'; return }; $global:LASTEXITCODE = 0; 'Currently stored credentials:' }
    $cu = Clear-GdidUserCreds
    $r.ownFailState = $cu.state; $r.ownFailFails = $cu.fails
    $script:CkFail = $false
    $cu = Clear-GdidUserCreds
    $r.ownOkState = $cu.state

    # --- оборванное стирание: службы, что работали до него ---
    $script:Svc = @{}
    $script:Started = New-Object System.Collections.Generic.List[string]
    function Get-SvcScmView { param($Name) if (-not $script:Svc.ContainsKey($Name)) { return @{ ok = $true; found = $false; running = $false; status = ''; start = '' } }; $s = $script:Svc[$Name]; @{ ok = $true; found = $true; running = $s.run; status = $(if ($s.run) { 'Running' } else { 'Stopped' }); start = $s.start } }
    function Get-SvcStartInfo { param($Name) $s = $script:Svc[$Name]; if (-not $s) { return @{ name = $Name; start = -1; state = 'Missing' } }; @{ name = $Name; start = 2; state = $s.start } }
    function Start-Service { param($Name, $ErrorAction, $WarningAction) $script:Started.Add($Name); if ($script:Svc[$Name].nostart) { throw 'не запускается (тест)' }; $script:Svc[$Name].run = $true }
    function Get-Service { param($Name, $ErrorAction) $o = [pscustomobject]@{ Name = $Name }; $o | Add-Member -MemberType ScriptMethod -Name WaitForStatus -Value { param($a, $b) } ; $o }
    $script:Svc['CDPSvc'] = @{ run = $false; start = 'Automatic' }
    $script:Svc['DoSvc'] = @{ run = $true; start = 'Automatic' }
    $script:Svc['wlidsvc'] = @{ run = $false; start = 'Disabled' }
    Write-OpRecord 'gdid-wipe' ([ordered]@{ state = 'InProgress'; started = 'x'; running = @('CDPSvc', 'DoSvc', 'wlidsvc', 'CDPUserSvc_1a2b', 'evil;cmd'); notBack = @() })
    $rcv = Get-GdidWipeRecovery
    $r.rcvState = $rcv.state; $r.rcvStopped = (@($rcv.stopped) -join ','); $r.rcvRunning = (@($rcv.running) -join ',')
    $iw = Restore-GdidInterruptedWipe
    $r.iwState = $iw.state; $r.iwStarted = (@($iw.started) -join ','); $r.iwSkipped = (@($iw.skipped) -join ',')
    $r.iwNoRec = ((Read-OpRecord 'gdid-wipe').state -eq 'none')
    $r.iwNeverEvil = ($script:Started -notcontains 'evil;cmd')
    # служба не запустилась — запись остаётся, «не вернулось» названо
    $script:Svc['CDPSvc'] = @{ run = $false; start = 'Automatic'; nostart = $true }
    Write-OpRecord 'gdid-wipe' ([ordered]@{ state = 'InProgress'; started = 'x'; running = @('CDPSvc'); notBack = @() })
    $iw = Restore-GdidInterruptedWipe
    $r.iwFailState = $iw.state; $r.iwFailKept = ((Read-OpRecord 'gdid-wipe').state -eq 'valid'); $r.iwFailNames = (@($iw.failed) -join ',')
    $r.iwFailRecState = "$((Read-OpRecord 'gdid-wipe').data.state)"
    # после перезагрузки всё снова работает — «устоялось», а не «нужно восстановление»
    $script:Svc['CDPSvc'] = @{ run = $true; start = 'Automatic' }
    $r.settled = (Get-GdidWipeRecovery).state
    $null = Remove-OpRecord 'gdid-wipe'

    # --- само стирание на заглушках: запись до первого изменения, перенос служб ---
    $script:Calls = New-Object System.Collections.Generic.List[string]
    $realWrite = ${function:Write-OpRecord}
    function Write-OpRecord { param($Name, $Data) $script:Calls.Add('record:' + "$($Data.state)"); & $realWrite $Name $Data }
    function Get-ManagedReason { '' }
    $script:SnapSvc = @()
    function Get-GdidPreflight { @{ ok = $true; blockers = (New-Object System.Collections.Generic.List[string]); warnings = (New-Object System.Collections.Generic.List[string])
        scan = @{ copies = @(@{ who = 'user' }); unreadable = @(); unchecked = 0; profiles = @{ unverified = $false } }
        snapshot = @{ complete = $true; services = @($script:SnapSvc | ForEach-Object { @{} + $_ }); problems = @() } } }
    function Disable-GdidWlid { $script:Calls.Add('disable-wlid'); @{ ok = $true; changed = $false; entry = $null; why = '' } }
    function Stop-ServiceWait { param($Name) $script:Calls.Add('stop:' + $Name); $true }
    function Clear-GdidUserCreds { $script:Calls.Add('creds'); @{ state = 'Clean'; fails = 0; done = 1 } }
    function Invoke-OneShotTask { $script:Calls.Add('system-creds'); $true }
    function Remove-GdidRegistryCopies { $script:Calls.Add('registry'); @{ state = 'Clean'; removed = 1; denied = 0; kept = 0 } }
    function Clear-GdidCdpCache { $script:Calls.Add('cdp'); @{ state = 'NotFound'; others = 0 } }
    function Get-GdidScan { $script:Calls.Add('verify'); @{ copies = @(); unreadable = @(); unchecked = 0; profiles = @{ unverified = $false }; state = 'NotFound' } }
    $script:BackNames = @(); $script:NotBack = @()
    function Restore-GdidServices { param([string[]]$Running, $Wlid, $Snapshot) $script:Calls.Add('restore'); $script:BackNames = @($Running); $script:SnapRunning = @(@($Snapshot.services) | Where-Object { $_.running } | ForEach-Object { "$($_.name)" }); @{ notBack = @($script:NotBack); states = @() } }
    $DryRun = $false
    # прошлое стирание оборвалось после остановки CDPSvc: сейчас она стоит
    $script:SnapSvc = @(@{ name = 'wlidsvc'; running = $false; scmFound = $true; start = 3; status = 'Stopped' }, @{ name = 'CDPSvc'; running = $false; scmFound = $true; start = 2; status = 'Stopped' }, @{ name = 'DoSvc'; running = $true; scmFound = $true; start = 2; status = 'Running' })
    & $realWrite 'gdid-wipe' ([ordered]@{ state = 'InProgress'; started = 'x'; running = @('CDPSvc', 'DoSvc'); notBack = @() })
    $script:Calls.Clear()
    $ok = Invoke-GdidWipe
    $r.wipeOk = $ok
    $r.wipeBack = (@($script:BackNames | Sort-Object) -join ',')
    $r.wipeSnapRunning = (@($script:SnapRunning | Sort-Object) -join ',')
    $r.wipeOrder = ($script:Calls -join ' > ')
    $r.wipeNoRec = ((Read-OpRecord 'gdid-wipe').state -eq 'none')
    # службы не вернулись — запись остаётся с тем, что не вернулось
    $script:NotBack = @('CDPSvc'); $script:Calls.Clear()
    $null = Invoke-GdidWipe
    $rr = Read-OpRecord 'gdid-wipe'
    $r.nbKept = ($rr.state -eq 'valid' -and "$($rr.data.state)" -eq 'RestoreFailed' -and (@($rr.data.notBack) -contains 'CDPSvc'))
    $script:NotBack = @(); $null = Remove-OpRecord 'gdid-wipe'
    # запись не пишется — не меняется ничего
    $script:Calls.Clear()
    $ok = & { function Write-OpRecord { param($Name, $Data) throw 'диск недоступен (тест)' }; Invoke-GdidWipe }
    $r.recFailOk = $ok; $r.recFailCalls = ($script:Calls -join ' > '); $r.recFailState = "$($script:GdidWipeResult.state)"
    # другое стирание держит замок — не меняется ничего
    $lockFile = Join-Path $script:SafeRoot 'gdid-wipe.lock'
    $hold = [IO.File]::Open($lockFile, 'OpenOrCreate', 'ReadWrite', 'None')
    $script:Calls.Clear()
    $ok = Invoke-GdidWipe
    $hold.Dispose()
    $r.busyOk = $ok; $r.busyCalls = ($script:Calls -join ' > '); $r.busyErr = (@($script:GdidWipeResult.errors) -join ' ')

    # --- обрыв процесса на каждой стадии стирания: запись о ходе на диске, ---
    # --- следующий запуск видит службы, что работали, и запускает их       ---
    $child = Join-Path $base 'gchild.ps1'
    Set-Content -LiteralPath $child -Encoding UTF8 -Value ('param($Safe, $Data, $Stage)' + "`r`n" + $Fns + "`r`n" + $Vars + "`r`n" + @'
$script:SafeRoot = $Safe; $script:DataDir = $Data; $script:RootState = $true; $script:SignKey = [byte[]](1..32)
function Assert-SafeRoot { $true }
function Write-Log { param($m) }
$DryRun = $false
$die = { param($s) if ($Stage -eq $s) { [Environment]::Exit(77) } }
function Get-ManagedReason { '' }
function Get-GdidPreflight { & $die 'preflight'; @{ ok = $true; blockers = (New-Object System.Collections.Generic.List[string]); warnings = (New-Object System.Collections.Generic.List[string])
    scan = @{ copies = @(@{ who = 'user' }); unreadable = @(); unchecked = 0; profiles = @{ unverified = $false } }
    snapshot = @{ complete = $true; services = @(@{ name = 'wlidsvc'; running = $true; scmFound = $true; start = 3; status = 'Running' }, @{ name = 'CDPSvc'; running = $true; scmFound = $true; start = 2; status = 'Running' }); problems = @() } } }
function Disable-GdidWlid { & $die 'wlidsvc'; @{ ok = $true; changed = $false; entry = $null; why = '' } }
function Stop-ServiceWait { param($Name) & $die 'stop'; $true }
function Clear-GdidUserCreds { & $die 'creds'; @{ state = 'Clean'; fails = 0; done = 1 } }
function Invoke-OneShotTask { $true }
function Remove-GdidRegistryCopies { & $die 'identitycrl'; @{ state = 'Clean'; removed = 1; denied = 0; kept = 0 } }
function Clear-GdidCdpCache { @{ state = 'NotFound'; others = 0 } }
function Get-GdidScan { & $die 'verify'; @{ copies = @(); unreadable = @(); unchecked = 0; profiles = @{ unverified = $false }; state = 'NotFound' } }
function Restore-GdidServices { param([string[]]$Running, $Wlid, $Snapshot) & $die 'restore'; @{ notBack = @(); states = @() } }
$realRemove = ${function:Remove-OpRecord}
function Remove-OpRecord { param($Name) & $die 'final'; & $realRemove $Name }
$null = Invoke-GdidWipe
exit 0
'@)
    $gc = New-Object System.Collections.Generic.List[object]
    foreach ($st in @('preflight', 'wlidsvc', 'stop', 'creds', 'identitycrl', 'verify', 'restore', 'final')) {
        $null = Remove-OpRecord 'gdid-wipe'
        $p2 = Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -PassThru -Wait -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $child + '"'),
            '-Safe', ('"' + $script:SafeRoot + '"'), '-Data', ('"' + $script:DataDir + '"'), '-Stage', $st)
        $rc = & { function Get-SvcScmView { param($Name) @{ ok = $true; found = $true; running = $false; status = 'Stopped'; start = 'Automatic' } }; Get-GdidWipeRecovery }
        $gc.Add(@{ stage = $st; code = $p2.ExitCode; state = "$($rc.state)"; stopped = (@($rc.stopped) -join ','); lockFree = ((Test-OpRunning 'gdid-wipe') -eq $false) })
    }
    $r.gcrash = $gc.ToArray()
    & cmd.exe /c ('rmdir /s /q "' + $base + '"') 2>$null
    $r
}
$gdDone = Wait-Job $gdJob -Timeout 300
$gd = $(if ($gdDone) { @(Receive-Job $gdJob) | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1 } else { $null })
Remove-Job $gdJob -Force
Check 'GDID: проверки контекста и оборванного стирания не зависают' ($null -ne $gd)
if ($gd) {
    Check 'GDID: «кто за компьютером» — только explorer этого же сеанса' ($gd.sessFilter -match [regex]::Escape($gd.sessWant)) $gd.sessFilter
    Check 'GDID: вошедший с учётной записью Entra ID (S-1-12-1-…) тоже человек за компьютером' ([bool]$gd.entraSeen)
    Check 'GDID: WMI не ответил — «неизвестно» (ошибка записана), а не «за компьютером сам движок»' ($gd.cimFailNull -and $gd.cimFailErr -match 'WMI') $gd.cimFailErr
    Check 'GDID: неизвестно, кто за компьютером, — стирание не начинается; известно — начинается' ($gd.preBlocked -and $gd.preOk)
    Check 'GDID: учётные данные — у вошедшего, у Entra ID и у других вошедших; без _Classes, .DEFAULT и SYSTEM' ($gd.credUsers -eq 'S-1-5-21-1-2-3-1000|True,S-1-12-1-111-222-333-444|False,S-1-5-21-1-2-3-1002|False') $gd.credUsers
    Check 'GDID: проверка в задаче — сбой списка хранилища даёт код 2, запись осталась — 1, нет — 0' ($gd.ckFail -eq 2 -and $gd.ckLeft -eq 1 -and $gd.ckNone -eq 0) ("{0}/{1}/{2}" -f $gd.ckFail, $gd.ckLeft, $gd.ckNone)
    Check 'GDID: хранилище движка не прочиталось — не «убрано» (ошибка, не Clean); прочиталось и пусто — Clean' ($gd.ownFailState -ne 'Clean' -and $gd.ownFailFails -ge 1 -and $gd.ownOkState -eq 'Clean') ("{0}/{1}" -f $gd.ownFailState, $gd.ownOkState)
    Check 'GDID: оборванное стирание — RecoveryRequired, стоят те, что работали до него (wlidsvc по требованию не в счёт)' ($gd.rcvState -eq 'RecoveryRequired' -and $gd.rcvStopped -eq 'CDPSvc') ("{0}: {1}" -f $gd.rcvState, $gd.rcvStopped)
    Check 'GDID: имена служб из записи — только свои (чужое имя отброшено)' ($gd.rcvRunning -notmatch 'evil')
    Check 'GDID: «Вернуть как было» запускает остановленную, пропускает пропавшую и отключённую, запись убирает' (
          $gd.iwState -eq 'Restored' -and $gd.iwStarted -eq 'CDPSvc' -and $gd.iwSkipped -match 'CDPUserSvc_1a2b' -and $gd.iwSkipped -match 'wlidsvc' -and $gd.iwSkipped -match 'evil' -and $gd.iwNoRec -and $gd.iwNeverEvil) ("{0}: {1} / {2}" -f $gd.iwState, $gd.iwStarted, $gd.iwSkipped)
    Check 'GDID: служба не запустилась — RestoreFailed, запись остаётся с её именем' ($gd.iwFailState -eq 'RestoreFailed' -and $gd.iwFailKept -and $gd.iwFailNames -eq 'CDPSvc' -and $gd.iwFailRecState -eq 'RestoreFailed')
    Check 'GDID: после перезагрузки всё снова работает — Settled, восстановление не требуется' ($gd.settled -eq 'Settled') $gd.settled
    Check 'GDID: повторное стирание после обрыва запускает и службы, остановленные прошлым запуском' ($gd.wipeOk -and $gd.wipeBack -eq 'CDPSvc,DoSvc' -and $gd.wipeSnapRunning -eq 'CDPSvc,DoSvc' -and $gd.wipeNoRec) ("{0} | {1}" -f $gd.wipeBack, $gd.wipeSnapRunning)
    Check 'GDID: запись о ходе ложится раньше первого изменения (до wlidsvc)' ($gd.wipeOrder -match '^record:InProgress > disable-wlid') $gd.wipeOrder
    Check 'GDID: службы не вернулись — запись остаётся (RestoreFailed, с их именами)' ([bool]$gd.nbKept)
    Check 'GDID: запись о ходе не пишется — стирание не начинается, ничего не изменено' ((-not $gd.recFailOk) -and $gd.recFailCalls -eq '' -and $gd.recFailState -eq 'Failed') $gd.recFailCalls
    Check 'GDID: другое стирание держит замок — отказ, ничего не изменено' ((-not $gd.busyOk) -and $gd.busyCalls -eq '' -and $gd.busyErr -match 'другое стирание') $gd.busyErr
    $gcBad = @()
    foreach ($c in @($gd.gcrash)) {
        $want = $(if ($c.stage -eq 'preflight') { 'none' } else { 'RecoveryRequired' })
        if ($c.code -ne 77 -or $c.state -ne $want -or -not $c.lockFree -or ($want -ne 'none' -and $c.stopped -ne 'CDPSvc')) { $gcBad += ("{0}: код {1}, {2}, стоят [{3}], замок свободен {4}" -f $c.stage, $c.code, $c.state, $c.stopped, $c.lockFree) }
    }
    Check ("GDID: обрыв на каждой стадии ({0}) — до изменений записи нет, после — RecoveryRequired со службами, замок свободен" -f @($gd.gcrash).Count) ($gcBad.Count -eq 0 -and @($gd.gcrash).Count -eq 8) ($gcBad -join ' | ')
}

# =========================================================================== #
#  T-4. «Файл занят» — не «файла нет» (Windows PowerShell 5.1: ветка catch
#  [DirectoryNotFoundException] ловила «занят» после ~17 проходов)
# =========================================================================== #
Write-Host ''
Write-Host 'T-4: занятый файл данных — ошибка, а не «файла нет»'
$t4Job = Start-Job -ArgumentList $remedAllFns, $remedVars -ScriptBlock {
    param($Fns, $Vars)
    Invoke-Expression $Fns; Invoke-Expression $Vars
    $r = @{}
    $base = Join-Path $env:TEMP ('w11p-t4-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Force (Join-Path $base 'safe'), (Join-Path $base 'data')
    $script:SafeRoot = Join-Path $base 'safe'; $script:DataDir = Join-Path $base 'data'; $script:RootState = $true; $script:SignKey = [byte[]](1..32)
    function Assert-SafeRoot { $true }
    $f = Join-Path $base 'busy.txt'; [IO.File]::WriteAllText($f, 'x')
    # прежний вид функции: на этой сборке PowerShell он и давал «файла нет»
    function Read-TextSharedOld {
        param([string]$Path)
        for ($try = 1; ; $try++) {
            try {
                $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
                try { return (New-Object System.IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
            } catch [System.IO.FileNotFoundException] { return $null }
            catch [System.IO.DirectoryNotFoundException] { return $null }
            catch [System.IO.IOException] { if ($try -ge 30) { throw }; Start-Sleep -Milliseconds 20 }
        }
    }
    $h = [IO.File]::Open($f, 'Open', 'Read', 'None')
    $old = @(); foreach ($i in 1..3) { try { $x = Read-TextSharedOld $f; $old += $(if ($null -eq $x) { 'null' } else { 'text' }) } catch { $old += 'threw' } }
    $new = @(); foreach ($i in 1..5) { try { $x = Read-TextShared $f; $new += $(if ($null -eq $x) { 'null' } else { 'text' }) } catch { $new += 'threw' } }
    $h.Dispose()
    $r.old = ($old -join ','); $r.new = ($new -join ',')
    $r.free = ((Read-TextShared $f) -eq 'x')
    $r.missing = ($null -eq (Read-TextShared (Join-Path $base 'no-such.txt')))
    $r.missingDir = ($null -eq (Read-TextShared (Join-Path $base 'no-dir\x.txt')))
    # «занят» и «нет» — у Test-IoBusy / Test-IoMissing
    $busyEx = $null; $h = [IO.File]::Open($f, 'Open', 'Read', 'None')
    try { [IO.File]::Open($f, 'Open', 'Read', 'ReadWrite') } catch { $busyEx = $_.Exception }
    $h.Dispose()
    $missEx = $null; try { [IO.File]::Open((Join-Path $base 'none.txt'), 'Open') } catch { $missEx = $_.Exception }
    $r.kinds = ((Test-IoBusy $busyEx) -and -not (Test-IoMissing $busyEx) -and (Test-IoMissing $missEx) -and -not (Test-IoBusy $missEx))

    # --- сквозной случай: журнал отката открыт другим процессом без совместного доступа ---
    $script:Journal = New-Object System.Collections.Generic.List[object]; $script:JournalRetract = New-Object 'System.Collections.Generic.HashSet[string]'
    $script:RunId = 'test'; $script:JournalFailed = $false; $DryRun = $false; $script:Failures = 0
    Write-JournalFile @(@{ kind = 'reg'; path = 'HKCU:\Software\W11PRemedT4'; name = 'Old'; old = '1'; existed = $true; time = 'x'; count = 1; run = 'r0' }) $false
    $jp = Join-Path $script:DataDir 'changes.json'
    $before = [IO.File]::ReadAllBytes($jp)
    $holder = Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile', '-Command',
        ("`$f = [IO.File]::Open('{0}', 'Open', 'Read', 'None'); Set-Content -LiteralPath '{1}' -Value 'held'; Start-Sleep -Seconds 40; `$f.Dispose()" -f $jp, (Join-Path $base 'held.flag')))
    $until = (Get-Date).AddSeconds(15)
    while (-not (Test-Path -LiteralPath (Join-Path $base 'held.flag')) -and (Get-Date) -lt $until) { Start-Sleep -Milliseconds 100 }
    $jf = Read-JournalFile
    $r.jState = "$($jf.state)"; $r.jTrusted = [bool]$jf.trusted
    $jro = Read-JournalFile -ReadOnly
    $r.jRoState = "$($jro.state)"
    $script:Journal.Add(@{ kind = 'reg'; path = 'HKCU:\Software\W11PRemedT4'; name = 'New'; old = '2'; existed = $true; time = 'y'; count = 1; run = 'test' })
    Save-JournalEntries -Quiet
    $r.saveFailed = [bool]$script:JournalFailed
    try { $holder.Kill() } catch { }
    $null = $holder.WaitForExit(10000)
    $after = [IO.File]::ReadAllBytes($jp)
    $r.journalKept = ([Convert]::ToBase64String($before) -eq [Convert]::ToBase64String($after))
    $jf2 = Read-JournalFile
    $r.oldEntryThere = (@($jf2.items | Where-Object { "$($_.name)" -eq 'Old' }).Count -eq 1) -and $jf2.trusted
    & cmd.exe /c ('rmdir /s /q "' + $base + '"') 2>$null
    $r
}
$t4Done = Wait-Job $t4Job -Timeout 240
$t4 = $(if ($t4Done) { @(Receive-Job $t4Job) | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1 } else { $null })
Remove-Job $t4Job -Force
Check 'T-4: проверки занятого файла не зависают' ($null -ne $t4)
if ($t4) {
    if ($t4.old -match 'null') { Write-Host ('  [i]    T-4: прежний вид функции на этой сборке PowerShell отвечал «файла нет» на занятый файл: ' + $t4.old) }
    else { Write-Host ('  [i]    T-4: эта сборка PowerShell ошибку прежнего вида не воспроизводит: ' + $t4.old) }
    Check 'T-4: занятый файл — ошибка на каждом вызове (5 подряд), а не «файла нет»' ($t4.new -eq 'threw,threw,threw,threw,threw') $t4.new
    Check 'T-4: свободный файл читается, отсутствующий файл и папка — «нет»' ($t4.free -and $t4.missing -and $t4.missingDir)
    Check 'T-4: «занят» и «нет» различаются по самому исключению .NET' ([bool]$t4.kinds)
    Check 'T-4: журнал отката занят чужим процессом — «не читается», а не «журнала нет»' ($t4.jState -eq 'unreadable' -and -not $t4.jTrusted) $t4.jState
    Check 'T-4: показ журнала при занятом файле — тоже «не читается»' ($t4.jRoState -eq 'unreadable') $t4.jRoState
    Check 'T-4: в занятый журнал не дописывается (запись остановлена), история «как было» цела' ($t4.saveFailed -and $t4.journalKept -and $t4.oldEntryThere)
}
$t4Text = [regex]::Match($remedAllFns, "(?s)function Read-TextShared \{.*?\r?\n\}").Value
Check 'T-4: в движке нет фильтров catch [FileNotFoundException] / [DirectoryNotFoundException] для исключений .NET' (
      $t4Text -match 'Test-IoMissing' -and $remedAllFns -notmatch 'catch \[System\.IO\.(FileNotFound|DirectoryNotFound)Exception\]')
