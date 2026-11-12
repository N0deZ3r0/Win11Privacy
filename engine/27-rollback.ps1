
# =========================================================================== #
#  ОТКАТ ПО ЖУРНАЛУ
#  Возвращает каждый параметр реестра в то значение, которое было до нас.
# =========================================================================== #
# --------------------------------------------------------------------------- #
#  Другие пользователи и профиль по умолчанию. Настройки из HKCU касаются
#  только вошедшего. С -AllProfiles они ложатся и в кусты других профилей
#  этого компьютера, и в профиль Default — его копию получает каждый новый
#  пользователь. Не загруженный куст подключается на время записи.
# --------------------------------------------------------------------------- #
function Get-OtherProfiles {
    $me = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $out = New-Object System.Collections.Generic.List[object]
    $out.Add(@{ name = 'Default'; sid = ''; file = (Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT') })
    foreach ($p in @(Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue)) {
        if ($p.Special -or -not $p.LocalPath -or "$($p.SID)" -eq $me -or "$($p.SID)" -notlike 'S-1-5-21-*') { continue }
        $out.Add(@{ name = (Split-Path $p.LocalPath -Leaf); sid = "$($p.SID)"; file = (Join-Path $p.LocalPath 'NTUSER.DAT') })
    }
    return @($out | Where-Object { Test-Path -LiteralPath $_.file })
}

# Выполняет $Body с корнем куста профиля. Вошедший пользователь — его куст уже
# загружен; иначе файл NTUSER.DAT подключается под временным именем и
# отключается обратно.
function Use-ProfileHive {
    param($Prof, [scriptblock]$Body)
    if ($Prof.sid -and (Test-Path -LiteralPath ('Registry::HKEY_USERS\' + $Prof.sid))) {
        $null = & $Body ('Registry::HKEY_USERS\' + $Prof.sid); return $true
    }
    $mount = 'W11P_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $null = & reg.exe load "HKU\$mount" "$($Prof.file)" 2>&1
    if ($LASTEXITCODE -ne 0) { return $false }
    $unloaded = $false
    try { $null = & $Body ('Registry::HKEY_USERS\' + $mount) }
    finally {
        # пока живы ссылки на ключи, куст не отключится
        for ($i = 0; $i -lt 10; $i++) {
            [gc]::Collect(); [gc]::WaitForPendingFinalizers()
            $null = & reg.exe unload "HKU\$mount" 2>&1
            if ($LASTEXITCODE -eq 0) { $unloaded = $true; break }
            Start-Sleep -Milliseconds 700
        }
        # Раньше неудача здесь проходила молча. А подключённый чужой куст —
        # это профиль, который Windows при входе этого человека не загрузит и
        # выдаст временный. После перезагрузки куст отключается сам.
        if (-not $unloaded) {
            Write-Log ("   [!] профиль {0}: файл NTUSER.DAT остался подключённым (HKU\{1}) -- перезагрузите компьютер, прежде чем этот пользователь войдёт в Windows" -f $Prof.name, $mount)
            $script:Failures++
        }
    }
    return $true
}

function Apply-ProfilesHives {
    $defs = @($script:Defs | Where-Object { ($Modules -contains $_.M) -and ($SkipItems -notcontains $_.Id) -and
                                            ($script:RegTypes -contains $_.T) -and "$($_.P)" -like 'HKCU:\*' -and (Test-DefApplicable $_) })
    if ($defs.Count -eq 0) { return }
    Write-Section 'Другие пользователи и профиль по умолчанию'
    foreach ($pr in @(Get-OtherProfiles)) {
        if ($DryRun) { Write-Log ("   [тест] профиль {0}: настроек {1}" -f $pr.name, $defs.Count); continue }
        if ($script:JournalFailed) { Write-Log ("   [!] профиль {0}: не меняется -- журнал отката сейчас не пишется" -f $pr.name); $script:Failures++; continue }
        $cnt = @{ changed = 0; failed = 0; refused = $false }
        $mounted = Use-ProfileHive $pr {
            param($root)
            # Сначала — что меняем и как было, всей пачкой на диск (журнал
            # раньше изменения); потом сами изменения; неудачные — отзываются.
            # Раньше запись в журнал шла после изменения и ложилась на диск
            # только в конце: обрыв посередине оставлял чужой профиль
            # изменённым без пути назад.
            $plan = New-Object System.Collections.Generic.List[object]
            foreach ($d in $defs) {
                $sub = ("$($d.P)" -replace '^HKCU:\\', '')
                $kp = "$root\$sub"
                $cur = Get-RegValue $kp $d.N
                if ($null -ne $cur -and (ConvertTo-RegComparable $cur $d.Type) -eq (ConvertTo-RegComparable $d.V $d.Type)) { continue }
                $e = @{ kind = 'hive'; file = $pr.file; sid = $pr.sid; profile = $pr.name; sub = $sub
                        name = $d.N; type = $d.Type; existed = ($null -ne $cur)
                        old = $(if ($null -ne $cur) { $cur } else { '' }); newValue = "$($d.V)"
                        time = (Get-Date).ToString('s'); run = $script:RunId }
                $script:Journal.Add($e)
                $plan.Add(@{ d = $d; kp = $kp; e = $e })
            }
            if ($plan.Count -eq 0) { return }
            Save-JournalEntries -Quiet
            if ($script:JournalFailed) { $cnt.refused = $true; return }
            foreach ($p in $plan) {
                try {
                    if (-not (Test-Path -LiteralPath $p.kp)) { New-Item -Path $p.kp -Force -ErrorAction Stop | Out-Null }
                    New-ItemProperty -LiteralPath $p.kp -Name $p.d.N -Value $p.d.V -PropertyType $p.d.Type -Force -ErrorAction Stop | Out-Null
                    $cnt.changed++
                } catch { Undo-AheadEntry $p.e; $cnt.failed++ }
            }
        }
        if ($cnt.refused) { Write-Log ("   [!] профиль {0}: не меняется -- «как было» не легло в журнал отката" -f $pr.name); continue }
        if (-not $mounted) { Write-Log ("   [!] профиль {0}: куст не подключился (пользователь занят или файл недоступен)" -f $pr.name); $script:Failures++; continue }
        Write-Log ("   [+] профиль {0}: изменено настроек {1}{2}" -f $pr.name, $cnt.changed, $(if ($cnt.failed) { ", не удалось $($cnt.failed)" } else { '' }))
        $script:Changes += $cnt.changed; $script:Failures += $cnt.failed
    }
    Save-JournalEntries -Quiet
}

# Возвращает одну запись другого профиля в то, что было до программы
function Restore-HiveEntry {
    param($Entry)
    $res = @{ ok = $false; error = '' }
    $mounted = Use-ProfileHive @{ name = "$($Entry.profile)"; sid = "$($Entry.sid)"; file = "$($Entry.file)" } {
        param($root)
        $kp = "$root\$($Entry.sub)"
        try {
            if ($Entry.existed) {
                if (-not (Test-Path -LiteralPath $kp)) { New-Item -Path $kp -Force -ErrorAction Stop | Out-Null }
                New-ItemProperty -LiteralPath $kp -Name $Entry.name -Value $Entry.old -PropertyType $Entry.type -Force -ErrorAction Stop | Out-Null
            } else { Remove-ItemProperty -LiteralPath $kp -Name $Entry.name -Force -ErrorAction SilentlyContinue }
            $res.ok = $true
        } catch { $res.error = $_.Exception.Message }
    }
    if (-not $mounted) { $res.error = 'куст профиля не подключился' }
    return $res
}

function Restore-Journal {
    if (-not (Test-DataTrusted)) {
        Write-Log '   [!] папка данных программы не защищена от подмены -- журналу отката сейчас нельзя верить, ничего не возвращаем'
        $script:Failures++
        return @{ restored = 0; failed = 0; state = 'untrusted' }
    }
    $jf = Read-JournalFile
    # подпись не сошлась или её нечем проверить — почему, уже сказано выше
    if (-not $jf.trusted) { $script:Failures++; return @{ restored = 0; failed = 0; state = 'untrusted' } }
    if ($jf.items.Count -eq 0) { Write-Log '   [-] журнал пуст — возвращать нечего'; return @{ restored = 0; failed = 0; legacy = $jf.legacy; state = $jf.state } }
    # Журнал идёт от старых записей к новым, и про каждый параметр нужна
    # первая: она помнит состояние до нас. Раньше список переворачивался, и у
    # журнала с повторами (версии до схлопывания) возвращалось то значение,
    # которое программа сама же записала в прошлый раз.
    $ok = 0; $seen = @{}; $startBack = 0; $svcBack = 0; $malformed = 0
    $failed = New-Object System.Collections.Generic.List[object]
    foreach ($e in @($jf.items)) {
        # запись не по форме не исполняется: подпись не заменяет проверку
        # допустимости. В журнал такая запись не возвращается.
        $why = Test-JournalEntryShape $e
        if ($why) { $malformed++; Write-Log ("   [!] запись журнала не по форме ({0}) -- пропущена" -f $why); continue }
        # записи автозагрузки возвращаем тем же способом, каким гасили
        if ("$($e.kind)" -eq 'startup') {
            $key = "startup|$($e.id)"
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $r = Set-StartupState ([string]$e.id) ("$($e.old)" -eq 'On')
            if ($r.ok) { $startBack++ } else { $failed.Add($e) }
            continue
        }
        if ("$($e.kind)" -eq 'hive') {
            $key = Get-JournalKey (ConvertTo-Fields $e)
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $r = Restore-HiveEntry $e
            if ($r.ok) { $ok++ } else { $failed.Add($e) }
            continue
        }
        $kind = "$($e.kind)"
        if ($kind -notin @('reg', 'svc', 'task', 'env', 'audit')) { continue }
        $key = Get-JournalKey (ConvertTo-Fields $e)
        if ($seen.ContainsKey($key)) { continue }      # только самое раннее состояние
        $seen[$key] = $true
        $r = Restore-JournalEntry $e
        if (-not $r.ok) { $failed.Add($e); Write-Log ("   [!] не вернулось: {0} -- {1}" -f $key, $r.error); continue }
        if ($r.note) { Write-Log ("   [i] {0} -- {1}" -f $key, $r.note) }
        if ($kind -eq 'reg') { $ok++ } else { $svcBack++ }
    }
    if ($malformed -gt 0) { $script:Failures++ }
    $bad = $failed.Count
    Write-Log ("   [+] возвращено параметров реестра: {0}" -f $ok)
    if ($svcBack -gt 0) { Write-Log ("   [+] возвращено служб, задач и переменных среды: {0}" -f $svcBack) }
    if ($startBack -gt 0) { Write-Log ("   [+] возвращено записей автозагрузки: {0}" -f $startBack) }
    # Что вернуть не удалось, остаётся в журнале: раньше он стирался целиком,
    # даже когда откат прошёл не весь, и вторая попытка была невозможна.
    # Пустой журнал остаётся файлом: по нему видно, что он нового образца.
    if ($bad -gt 0) { Write-Log ("   [!] не удалось вернуть: {0} -- эти записи остались в журнале" -f $bad) }
    try { Use-JournalLock { Write-JournalFile $failed.ToArray() $jf.legacy } }
    catch { Write-Log ("   [!] журнал отката не переписался: {0}" -f $_.Exception.Message); $script:Failures++ }
    return @{ restored = $ok + $svcBack; startup = $startBack; failed = $bad; legacy = $jf.legacy; state = $jf.state }
}

