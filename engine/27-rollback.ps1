
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

# Куст, оставшийся подключённым после оборванного запуска: процесс упал или
# его закрыли посреди записи. Такой профиль Windows при входе человека не
# загрузит и выдаст ему временный. В имени подключения — номер процесса
# движка; процесса с таким номером больше нет — куст отключается. Подключения
# идущего сейчас запуска (процесс жив) не трогаются.
function Get-HiveMountNames { return @([Microsoft.Win32.Registry]::Users.GetSubKeyNames()) }

function Clear-StaleHiveMounts {
    if ($script:StaleHivesChecked) { return }
    $script:StaleHivesChecked = $true
    $names = @()
    try { $names = @(Get-HiveMountNames) }
    catch { Write-Log ("   [!] список подключённых кустов не прочитался: {0}" -f $_.Exception.Message); return }
    foreach ($n in $names) {
        if ($n -notmatch '^W11P_(\d{1,7})_[0-9a-f]{6}$') { continue }
        if (Get-Process -Id ([int]$Matches[1]) -ErrorAction SilentlyContinue) { continue }
        $null = & reg.exe unload "HKU\$n" 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Log ("   [+] отключён куст профиля, оставшийся от оборванного запуска (HKU\{0})" -f $n) }
        else { Write-Log ("   [!] куст профиля от оборванного запуска (HKU\{0}) не отключился -- перезагрузите компьютер" -f $n); $script:Failures++ }
    }
}

# Выполняет $Body с корнем куста профиля. Вошедший пользователь — его куст уже
# загружен; иначе файл NTUSER.DAT подключается под временным именем и
# отключается обратно. В имени — номер этого процесса (см. Clear-StaleHiveMounts).
function Use-ProfileHive {
    param($Prof, [scriptblock]$Body)
    Clear-StaleHiveMounts
    if ($Prof.sid -and (Test-Path -LiteralPath ('Registry::HKEY_USERS\' + $Prof.sid))) {
        $null = & $Body ('Registry::HKEY_USERS\' + $Prof.sid); return $true
    }
    $mount = 'W11P_' + $PID + '_' + [guid]::NewGuid().ToString('N').Substring(0, 6)
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
        $cnt = @{ changed = 0; failed = 0; refused = $false; notes = (New-Object System.Collections.Generic.List[string]) }
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
                # как у Set-Reg: в журнал — вид и данные прежнего значения как есть
                $raw = Get-RegRaw $kp $d.N
                if (-not $raw.ok -or ($null -ne $cur -and -not $raw.exists)) { $cnt.failed++; $cnt.notes.Add(("{0}: прежнее значение не прочиталось" -f $d.N)); continue }
                if ($raw.exists -and -not (Test-RegKind $raw.kind)) { $cnt.failed++; $cnt.notes.Add(("{0}: прежнее значение вида {1} откат не вернул бы" -f $d.N, $raw.kind)); continue }
                $e = @{ kind = 'hive'; file = $pr.file; sid = $pr.sid; profile = $pr.name; sub = $sub
                        name = $d.N; type = $(if ($raw.exists) { $raw.kind } else { $d.Type }); existed = [bool]$raw.exists
                        old = $(if ($raw.exists) { $raw.value } else { '' }); newValue = "$($d.V)"
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
                } catch { Undo-AheadEntry $p.e; $cnt.failed++; $cnt.notes.Add(("{0}: {1}" -f $p.d.N, $_.Exception.Message)); continue }
                # «команда прошла» — ещё не «значение такое»; запись в журнале
                # остаётся в любом случае: значение уже не прежнее
                $now = Get-RegValue $p.kp $p.d.N
                if ($null -eq $now -or (ConvertTo-RegComparable $now $p.d.Type) -ne (ConvertTo-RegComparable $p.d.V $p.d.Type)) {
                    $cnt.failed++; $cnt.notes.Add(("{0}: записано, но читается другое" -f $p.d.N)); continue
                }
                $cnt.changed++
            }
        }
        if ($cnt.refused) { Write-Log ("   [!] профиль {0}: не меняется -- «как было» не легло в журнал отката" -f $pr.name); continue }
        if (-not $mounted) { Write-Log ("   [!] профиль {0}: куст не подключился (пользователь занят или файл недоступен)" -f $pr.name); $script:Failures++; continue }
        Write-Log ("   [{0}] профиль {1}: изменено настроек {2}{3}" -f $(if ($cnt.failed) { '!' } else { '+' }), $pr.name, $cnt.changed, $(if ($cnt.failed) { ", не удалось $($cnt.failed)" } else { '' }))
        foreach ($n in $cnt.notes) { Write-Log ("       {0}" -f $n) }
        $script:Changes += $cnt.changed; $script:Failures += $cnt.failed
    }
    Save-JournalEntries -Quiet
}

# Возвращает записи одного профиля в то, что было до программы. Куст
# подключается один раз на все записи этого профиля, а не на каждую; итог —
# у каждой записи свой, со сверкой (см. Restore-RegValue).
function Restore-HiveEntries {
    param([object[]]$Entries)
    $first = $Entries[0]
    $results = @{}
    $mounted = Use-ProfileHive @{ name = "$($first.profile)"; sid = "$($first.sid)"; file = "$($first.file)" } {
        param($root)
        for ($n = 0; $n -lt $Entries.Count; $n++) {
            $it = $Entries[$n]
            $results[$n] = Restore-RegValue "$root\$($it.sub)" "$($it.name)" ([bool]$it.existed) $it.old "$($it.type)"
        }
    }
    $out = New-Object System.Collections.Generic.List[object]
    for ($n = 0; $n -lt $Entries.Count; $n++) {
        if (-not $mounted) { $out.Add(@{ ok = $false; error = 'куст профиля не подключился (пользователь занят или файл недоступен)' }) }
        elseif ($results.ContainsKey($n)) { $out.Add($results[$n]) }
        else { $out.Add(@{ ok = $false; error = 'запись не обработана' }) }
    }
    return , $out.ToArray()
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
    $hiveGroups = [ordered]@{}
    # Записи, с которыми откат закончил (вернул или отбросил как негодные).
    # Из журнала уходят только они: что дописал другой запуск, пока шёл
    # откат, остаётся. Раньше журнал переписывался списком неудач целиком.
    $handled = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($e in @($jf.items)) {
        # запись не по форме не исполняется: подпись не заменяет проверку
        # допустимости. В журнал такая запись не возвращается.
        $why = Test-JournalEntryShape $e
        if ($why) { $malformed++; $null = $handled.Add((Get-JournalEntryId $e)); Write-Log ("   [!] запись журнала не по форме ({0}) -- пропущена" -f $why); continue }
        # записи автозагрузки возвращаем тем же способом, каким гасили
        if ("$($e.kind)" -eq 'startup') {
            $key = "startup|$($e.id)"
            if ($seen.ContainsKey($key)) { $null = $handled.Add((Get-JournalEntryId $e)); continue }
            $seen[$key] = $true
            $r = Set-StartupState ([string]$e.id) ("$($e.old)" -eq 'On')
            if ($r.ok) { $startBack++; $null = $handled.Add((Get-JournalEntryId $e)) }
            else { $failed.Add($e); Write-Log ("   [!] не вернулось: {0} -- {1}" -f $key, $r.error) }
            continue
        }
        if ("$($e.kind)" -eq 'hive') {
            # записи других профилей — пачкой на профиль, после остальных
            $key = Get-JournalKey (ConvertTo-Fields $e)
            if ($seen.ContainsKey($key)) { $null = $handled.Add((Get-JournalEntryId $e)); continue }
            $seen[$key] = $true
            $hf = "$($e.file)".ToLowerInvariant()
            if (-not $hiveGroups.Contains($hf)) { $hiveGroups[$hf] = New-Object System.Collections.Generic.List[object] }
            $hiveGroups[$hf].Add($e)
            continue
        }
        $kind = "$($e.kind)"
        $key = Get-JournalKey (ConvertTo-Fields $e)
        if ($seen.ContainsKey($key)) { $null = $handled.Add((Get-JournalEntryId $e)); continue }      # только самое раннее состояние
        $seen[$key] = $true
        $r = Restore-JournalEntry $e
        if (-not $r.ok) { $failed.Add($e); Write-Log ("   [!] не вернулось: {0} -- {1}" -f $key, $r.error); continue }
        $null = $handled.Add((Get-JournalEntryId $e))
        if ($r.note) { Write-Log ("   [i] {0} -- {1}" -f $key, $r.note) }
        if ($kind -eq 'reg') { $ok++ } else { $svcBack++ }
    }
    foreach ($hf in @($hiveGroups.Keys)) {
        $group = $hiveGroups[$hf].ToArray()
        $res = Restore-HiveEntries $group
        for ($n = 0; $n -lt $group.Count; $n++) {
            $he = $group[$n]
            if ($res[$n].ok) { $ok++; $null = $handled.Add((Get-JournalEntryId $he)); continue }
            $failed.Add($he)
            Write-Log ("   [!] не вернулось: профиль {0}, {1}\{2} -- {3}" -f $he.profile, $he.sub, $he.name, $res[$n].error)
        }
    }
    if ($malformed -gt 0) { $script:Failures++ }
    $bad = $failed.Count
    Write-Log ("   [+] возвращено параметров реестра: {0}" -f $ok)
    if ($svcBack -gt 0) { Write-Log ("   [+] возвращено служб, задач и переменных среды: {0}" -f $svcBack) }
    if ($startBack -gt 0) { Write-Log ("   [+] возвращено записей автозагрузки: {0}" -f $startBack) }
    # Что вернуть не удалось, остаётся в журнале: раньше он стирался целиком,
    # даже когда откат прошёл не весь, и вторая попытка была невозможна.
    # Пустой журнал остаётся файлом: по нему видно, что он нового образца.
    if ($bad -gt 0) { Write-Log ("   [!] не удалось вернуть: {0} -- эти записи остались в журнале" -f $bad); $script:Failures++ }
    try { Remove-JournalEntries $handled }
    catch { Write-Log ("   [!] журнал отката не переписался: {0}" -f $_.Exception.Message); $script:Failures++ }
    return @{ restored = $ok + $svcBack; startup = $startBack; failed = $bad; legacy = $jf.legacy; state = $jf.state }
}

