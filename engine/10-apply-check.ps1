
# =========================================================================== #
#  Применение / проверка одного определения
# =========================================================================== #
# --------------------------------------------------------------------------- #
#  УБОРКА ЗА СТАРЫМИ ВЕРСИЯМИ
#  В версиях 1.1.0–1.5.0 счётчик внутри Def затирал имя параметра, и настройки
#  писались в реестр под числовыми именами: «0», «1», «2» вместо AllowTelemetry.
#  Они ничего не настраивали. Находим ровно свои: имя — число, оно совпадает с
#  номером определения по этому пути, а значение — с тем, что мы бы записали.
# --------------------------------------------------------------------------- #
function Find-JunkValues {
    $byIdx = @{}
    $paths = @{}
    foreach ($d in $script:Defs) {
        if ($script:RegTypes -notcontains $d.T) { continue }
        $paths["$($d.P)"] = $true
        $parts = "$($d.Id)" -split '#'
        if ($parts.Count -ne 2) { continue }
        $k = "$($d.P)|$([int]$parts[1])"
        if (-not $byIdx.ContainsKey($k)) { $byIdx[$k] = $d }
    }
    $junk = @()
    foreach ($path in @($paths.Keys)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $names = @()
        # без -ErrorAction Stop отказ доступа не ловится try/catch и сыплется в вывод
        try { $names = @((Get-Item -LiteralPath $path -ErrorAction Stop).GetValueNames()) } catch { continue }
        foreach ($nm in $names) {
            if ($nm -notmatch '^[0-9]{1,3}$') { continue }
            $k = "$path|$([int]$nm)"
            if (-not $byIdx.ContainsKey($k)) { continue }
            $cur = Get-RegValue $path $nm
            if ($null -eq $cur) { continue }
            if ("$cur" -ne "$($byIdx[$k].V)") { continue }      # значение чужое — не наше
            $junk += @{ path = $path; name = $nm; title = "$($byIdx[$k].C)" }
        }
    }
    return @($junk)
}

function Remove-JunkValues {
    $junkList = @(Find-JunkValues)
    if ($junkList.Count -eq 0) { return 0 }
    $gone = 0
    foreach ($j in $junkList) {
        if ($DryRun) { Write-Log ("   [тест] мусор от старой версии: {0} -> {1}" -f $j.path, $j.name); continue }
        try {
            Remove-ItemProperty -LiteralPath $j.path -Name $j.name -Force -ErrorAction Stop
            Write-Log ("   [+] убран мусорный параметр {0} ({1})" -f $j.name, $j.title)
            $gone++
        } catch { Write-Log ("   [!] не удалось убрать {0} -> {1}" -f $j.path, $j.name) }
    }
    return $gone
}

# Останавливает службу, отключённую через реестр, и её копии для каждого
# пользователя (CDPUserSvc_1a2b3): запись в реестре вступает в силу только
# после перезагрузки, а до неё служба продолжила бы работать.
function Stop-ServiceInstances {
    param([string]$Name)
    foreach ($s in @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $Name -or $_.Name -like ($Name + '_*') })) {
        if ($s.Status -ne 'Running') { continue }
        try { Stop-Service -Name $s.Name -Force -ErrorAction Stop; Write-Log ("       остановлена: {0}" -f $s.Name) }
        catch { Write-Log ("       {0} остановится после перезагрузки" -f $s.Name) }
    }
}

# Служба не отключилась. Отказ в доступе — решение Windows (часть служб она
# не отдаёт даже администратору): это «не разрешает», как у политик, и
# проверка его потом не считает «не применённым». Любая другая причина —
# ошибка, и она видна в итоге.
function Test-AccessDeniedError {
    param($Err)
    $ex = $(if ($Err -is [System.Management.Automation.ErrorRecord]) { $Err.Exception } else { $Err })
    while ($null -ne $ex) {
        if ($ex -is [System.UnauthorizedAccessException]) { return $true }
        if ($ex -is [System.ComponentModel.Win32Exception] -and $ex.NativeErrorCode -eq 5) { return $true }
        $ex = $ex.InnerException
    }
    return $false
}

function Write-SvcFailure {
    param($Def, $Err)
    $msg = "$($Err.Exception.Message)"
    if (Test-AccessDeniedError $Err) {
        Write-Log ("   [-] {0} -- Windows не даёт менять эту службу" -f $Def.C)
        $script:Blocked++
        if ($null -ne $script:BlockedIds) { $script:BlockedIds[$Def.Id] = $true }
        return
    }
    Write-Log ("   [!] {0} -- не отключилась: {1}" -f $Def.C, $msg)
    $script:Failures++
}

function Apply-Def {
    param($d)
    # журнал отката не пишется — больше ничего не меняем (причина уже в журнале работы)
    if ($script:JournalFailed -and -not $DryRun) { return }
    switch ($d.T) {
        'reg' { Set-Reg -Path $d.P -Name $d.N -Value $d.V -Type $d.Type -Comment $d.C }
        'regsvc' {
            # служба есть не на каждой редакции Windows — чего нет, то не создаём
            if (-not (Test-Path -LiteralPath $d.P)) { Write-Log ("   [-] {0} -- нет на этой системе" -f $d.C); return }
            Set-Reg -Path $d.P -Name $d.N -Value $d.V -Type $d.Type -Comment $d.C
            # останавливаем, только если отключение действительно записалось:
            # иначе служба тут же запустилась бы снова
            if (-not $DryRun -and "$($d.V)" -eq '4' -and "$(Get-RegValue $d.P $d.N)" -eq '4') { Stop-ServiceInstances (Split-Path $d.P -Leaf) }
        }
        'regpol' { Set-Reg -Path $d.P -Name $d.N -Value $d.V -Type $d.Type -Comment $d.C -Policy -DefId $d.Id }
        'regif' {
            # сессия трассировки есть не на каждой сборке Windows — чего нет, то не создаём
            if (Test-Path -LiteralPath $d.P) { Set-Reg -Path $d.P -Name $d.N -Value $d.V -Type $d.Type -Comment $d.C }
            else { Write-Log ("   [-] {0} -- нет на этой системе" -f $d.C) }
        }
        'svc' {
            if ($DryRun) { Write-Log "   [тест] $($d.C) -- отключить"; return }
            # «Службы нет» и «служба не отключилась» — разное. Раньше любая
            # ошибка называлась «недоступна» и в ошибки не шла: отказ при
            # отключении выглядел как отсутствие службы, а итог — успехом.
            $s = Get-Service -Name $d.P -ErrorAction SilentlyContinue
            if (-not $s) { Write-Log "   [-] $($d.C) -- нет на этой системе"; return }
            try {
                if ($s.StartType -eq 'Disabled' -and $s.Status -ne 'Running') {
                    Write-Log "   [в] $($d.C) -- уже настроено"; $script:Already++; return
                }
                if (-not (Test-CanModify $d.C)) { return }
                Ensure-Backup
                $was = Get-SvcJournalState $d.P $s
                if (-not (Write-AheadEntry $was)) { Write-Log "   [!] $($d.C) -- не меняется: «как было» не легло в журнал отката"; $script:Failures++; return }
                try {
                    if ($s.Status -eq 'Running') { Stop-Service -Name $d.P -Force -ErrorAction SilentlyContinue }
                    Set-Service -Name $d.P -StartupType Disabled -ErrorAction Stop
                } catch {
                    # не отключилась — работавшую запускаем обратно, запись отзываем
                    if ($was.running) { Start-Service -Name $d.P -ErrorAction SilentlyContinue }
                    Undo-AheadEntry $was
                    throw
                }
                Write-Log "   [+] $($d.C) -- остановлена и отключена"; $script:Changes++
                if ($null -ne $script:UnblockedIds) { $script:UnblockedIds[$d.Id] = $true }
            } catch { Write-SvcFailure $d $_ }
        }
        'svcopt' {
            $s = Get-Service -Name $d.P -ErrorAction SilentlyContinue
            if (-not $s) { return }
            if ($DryRun) { Write-Log "   [тест] $($d.C) -- отключить"; return }
            try {
                if ($s.StartType -eq 'Disabled' -and $s.Status -ne 'Running') {
                    Write-Log "   [в] $($d.C) -- уже настроено"; $script:Already++; return
                }
                if (-not (Test-CanModify $d.C)) { return }
                Ensure-Backup
                $was = Get-SvcJournalState $d.P $s
                if (-not (Write-AheadEntry $was)) { Write-Log "   [!] $($d.C) -- не меняется: «как было» не легло в журнал отката"; $script:Failures++; return }
                try {
                    if ($s.Status -eq 'Running') { Stop-Service -Name $d.P -Force -ErrorAction SilentlyContinue }
                    Set-Service -Name $d.P -StartupType Disabled -ErrorAction Stop
                } catch {
                    if ($was.running) { Start-Service -Name $d.P -ErrorAction SilentlyContinue }
                    Undo-AheadEntry $was
                    throw
                }
                Write-Log "   [+] $($d.C) -- отключена"; $script:Changes++
                if ($null -ne $script:UnblockedIds) { $script:UnblockedIds[$d.Id] = $true }
            } catch { Write-SvcFailure $d $_ }
        }
        'task' {
            $pp = Split-TaskPath $d.P
            if ($DryRun) { Write-Log "   [тест] $($d.C) -- отключить"; return }
            $st = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction SilentlyContinue
            if (-not $st) { Write-Log "   [-] $($d.C) -- нет на этой системе"; return }
            if (Test-TaskDisabled $st) { Write-Log "   [в] $($d.C) -- уже настроено"; $script:Already++; return }
            if (-not (Test-CanModify $d.C)) { return }
            Ensure-Backup
            $tj = @{ kind = 'task'; path = $d.P; old = 'Enabled'; newValue = 'Disabled' }
            if (-not (Write-AheadEntry $tj)) { Write-Log "   [!] $($d.C) -- не меняется: «как было» не легло в журнал отката"; $script:Failures++; return }
            switch (Set-TaskEnabled $d.P $false) {
                'ok'      { Write-Log "   [+] $($d.C) -- отключена"; $script:Changes++ }
                'system'  { Write-Log "   [+] $($d.C) -- отключена от имени системы (администратору Windows её не отдаёт)"; $script:Changes++ }
                'missing' { Undo-AheadEntry $tj; Write-Log "   [-] $($d.C) -- нет на этой системе" }
                default   { Undo-AheadEntry $tj; Write-Log "   [!] $($d.C) -- Windows не дала отключить задачу"; $script:Failures++ }
            }
        }
        'taskglob' {
            $ts = @(Get-TaskGlobTasks $d.P)
            if ($ts.Count -eq 0) { return }
            foreach ($t in $ts) {
                if ($DryRun) { Write-Log "   [тест] задача $($t.TaskName) -- отключить"; continue }
                if (Test-TaskDisabled $t) { Write-Log "   [в] задача $($t.TaskName) -- уже отключена"; $script:Already++; continue }
                if (-not (Test-CanModify ("задача " + $t.TaskName))) { break }
                Ensure-Backup
                $tj = @{ kind = 'task'; path = ($t.TaskPath + $t.TaskName); old = 'Enabled'; newValue = 'Disabled' }
                if (-not (Write-AheadEntry $tj)) { Write-Log ("   [!] задача {0} -- не меняется: «как было» не легло в журнал отката" -f $t.TaskName); $script:Failures++; break }
                # тем же путём, что и задачи по имени: со сверкой и запасным путём
                # от имени системы. Раньше неудача здесь шла как «[-]», не как ошибка.
                switch (Set-TaskEnabled ($t.TaskPath + $t.TaskName) $false) {
                    'ok'      { Write-Log "   [+] задача $($t.TaskName) -- отключена"; $script:Changes++ }
                    'system'  { Write-Log "   [+] задача $($t.TaskName) -- отключена от имени системы"; $script:Changes++ }
                    'missing' { Undo-AheadEntry $tj; Write-Log "   [-] задача $($t.TaskName) -- пропала, пока шла работа" }
                    default   { Undo-AheadEntry $tj; Write-Log "   [!] задача $($t.TaskName) -- Windows не дала отключить"; $script:Failures++ }
                }
            }
        }
        'env' {
            if ($DryRun) { Write-Log "   [тест] $($d.C)"; return }
            if ([string][Environment]::GetEnvironmentVariable($d.P, 'User') -eq [string]$d.V) {
                Write-Log "   [в] $($d.C) -- уже настроено"; $script:Already++; return
            }
            if (-not (Test-CanModify $d.C)) { return }
            Ensure-Backup
            $prevEnv = [Environment]::GetEnvironmentVariable($d.P, 'User')
            $ej = @{ kind = 'env'; name = $d.P; existed = [bool]($null -ne $prevEnv)
                     old = $(if ($null -ne $prevEnv) { [string]$prevEnv } else { '' }); newValue = [string]$d.V }
            if (-not (Write-AheadEntry $ej)) { Write-Log "   [!] $($d.C) -- не меняется: «как было» не легло в журнал отката"; $script:Failures++; return }
            try {
                [Environment]::SetEnvironmentVariable($d.P, [string]$d.V, 'User')
                Write-Log "   [+] $($d.C)"; $script:Changes++
            }
            catch { Undo-AheadEntry $ej; Write-Log "   [!] не удалось: $($d.C)"; $script:Failures++ }
        }
        'vscode'  { Set-VsCodeValue -Key $d.P -Value $d.V -Comment $d.C }
        'firefox' { Set-FirefoxPolicy -Key $d.P -Value $d.V -Comment $d.C }
        'hosts'   { Apply-Hosts }
        'gdidhosts' { Apply-Hosts -Kind 'gdid' }
        'gdidlockhosts' { Apply-Hosts -Kind 'lock' }
        'gdidwipe' {
            # Пока сервер выдачи открыт, стёртый номер сразу сменится новым —
            # это смена номера, а не запрет. Без закрытого сервера не стираем.
            if (-not $DryRun -and -not (Test-HostsBlock -Kind 'lock')) {
                Write-Log ("   [-] {0} -- пропущено: сервер выдачи номера не закрыт" -f $d.C); return
            }
            $null = Invoke-GdidWipe
        }
        'fwsvc'   { Apply-FwRule -Kind 'svc' -Target $d.P -Comment $d.C }
        'fwapp'   { Apply-FwRule -Kind 'app' -Target $d.P -Comment $d.C }
        'fwips'   { Apply-FwIpBlock }
    }
}

# Стоит ли параметр реестра так, как задумано: те же данные и тот же вид.
# Раньше сравнивались только строки, и REG_SZ «1» на месте DWORD 1 шёл как
# «применено», хотя Windows такой параметр не понимает.
function Test-RegDefValue {
    param($Def)
    $raw = Get-RegRaw $Def.P $Def.N
    if (-not $raw.ok) { return @{ ok = $false; actual = ("не читается: {0}" -f $raw.error) } }
    if (-not $raw.exists) { return @{ ok = $false; actual = 'не задано' } }
    $want = $(if ($Def.Type) { "$($Def.Type)" } else { 'DWord' })
    $got = ConvertTo-RegComparable $raw.value $raw.kind
    if ("$($raw.kind)" -ne $want) { return @{ ok = $false; actual = ("{0} (вид {1}, нужен {2})" -f $got, $raw.kind, $want) } }
    return @{ ok = ($got -eq (ConvertTo-RegComparable $Def.V $want)); actual = $got }
}

# Настройки, которой на этой версии Windows не существует, не бывает
# «не применённой»: помечаем na и не считаем ни в плюс, ни в минус.
function Test-DefApplicable {
    param($d)
    $minB = 0
    try { $minB = [int]$d.Min } catch { }
    if ($minB -le 0 -or $script:OsBuild -le 0) { return $true }
    return ($script:OsBuild -ge $minB)
}

function Check-Def {
    param($d)
    $ok = $false; $actual = ''
    if (-not (Test-DefApplicable $d)) {
        return @{ module=$d.M; name=$d.C; ok=$false; na=$true
                  expected="$($d.V)"; actual='нет на этой версии Windows' }
    }
    # Запрет выдачи номера при входе через учётную запись Microsoft недоступен
    # вовсе — индекс за него не снижается, как и за то, чего нет в этой Windows.
    if ($d.M -eq 'gdidlock' -and (Get-GdidLockRefusal)) {
        return @{ module=$d.M; name=$d.C; ok=$false; na=$true
                  expected="$($d.V)"; actual=$(if ((Get-GdidLockRefusal) -eq 'msa') { 'недоступно при входе через учётную запись Microsoft' } else { 'недоступно на компьютере организации' }) }
    }
    switch ($d.T) {
        { $_ -in @('regif', 'regsvc') } {
            if (-not (Test-Path -LiteralPath $d.P)) { $ok = $true; $actual = 'нет на этой системе' }
            else { $rc = Test-RegDefValue $d; $ok = $rc.ok; $actual = $rc.actual }
        }
        'regpol' {
            # Проверяем как обычный параметр. «Windows не разрешает» — это факт,
            # известный только после неудачной записи, и подставляется он в
            # -Audit по журналу отказов; здесь догадок не строим.
            $rc = Test-RegDefValue $d; $ok = $rc.ok; $actual = $rc.actual
        }
        'reg' { $rc = Test-RegDefValue $d; $ok = $rc.ok; $actual = $rc.actual }
        'svc' {
            $s = Get-Service -Name $d.P -ErrorAction SilentlyContinue
            if (-not $s) { $ok = $true; $actual = 'нет службы' }
            else { $actual = "$($s.StartType) / $($s.Status)"; $ok = ($s.StartType -eq 'Disabled') }
        }
        'svcopt' {
            $s = Get-Service -Name $d.P -ErrorAction SilentlyContinue
            if (-not $s) { $ok = $true; $actual = 'нет службы' }
            else { $actual = "$($s.StartType)"; $ok = ($s.StartType -eq 'Disabled') }
        }
        'task' {
            $pp = Split-TaskPath $d.P
            $t = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction SilentlyContinue
            if (-not $t) { $ok = $true; $actual = 'нет задачи' }
            else { $ok = Test-TaskDisabled $t; $actual = $(if ($ok) { 'Disabled' } else { [string]$t.State }) }
        }
        'taskglob' {
            $ts = @(Get-TaskGlobTasks $d.P)
            $bad = @($ts | Where-Object { -not (Test-TaskDisabled $_) })
            $ok = ($bad.Count -eq 0); $actual = "всего $($ts.Count), активных $($bad.Count)"
        }
        'env' {
            $v = [Environment]::GetEnvironmentVariable($d.P, 'User')
            $actual = if ($v) { $v } else { 'не задано' }
            $ok = ("$v" -eq "$($d.V)")
        }
        'vscode' {
            $v = Get-VsCodeValue $d.P
            $actual = if ($null -eq $v) { 'не задано' } else { "$v" }
            $ok = ($null -ne $v) -and ("$v".ToLower() -eq "$($d.V)".ToLower())
        }
        'firefox' {
            $v = Get-FirefoxPolicy $d.P
            $actual = if ($null -eq $v) { 'не задано' } else { "$v" }
            $ok = ($null -ne $v) -and ("$v".ToLower() -eq "$($d.V)".ToLower())
        }
        { $_ -in @('hosts', 'gdidhosts', 'gdidlockhosts') } {
            $hk = $(switch ($d.T) { 'gdidhosts' { 'gdid' } 'gdidlockhosts' { 'lock' } default { 'telemetry' } })
            $ok = Test-HostsBlockCurrent -Kind $hk
            $actual = if ($ok) { 'блок установлен' } elseif (Test-HostsBlock -Kind $hk) { 'блок устарел' } else { 'нет блока' }
        }
        'gdidwipe' {
            $ok = (@(Get-GdidCopies).Count -eq 0); $actual = if ($ok) { 'номера нет' } else { 'номер на месте' }
        }
        'fwips' {
            $ok = Test-FwIpRule -Fresh
            $actual = if ($ok) { 'адреса заблокированы' } elseif (Test-FwIpRule) { 'адреса устарели' } else { 'нет правила' }
        }
        'fwsvc' { $ok = Test-FwRule -Kind 'svc' -Target $d.P; $actual = if ($ok) { 'правило есть' } else { 'нет правила' } }
        'fwapp' { $ok = Test-FwRule -Kind 'app' -Target $d.P; $actual = if ($ok) { 'правило есть' } else { 'нет правила' } }
    }
    return @{ module=$d.M; name=$d.C; ok=[bool]$ok; expected="$($d.V)"; actual=$actual }
}

# --- hosts ------------------------------------------------------------------ #
$script:HostsDomains = @(
    'vortex.data.microsoft.com','vortex-win.data.microsoft.com','telecommand.telemetry.microsoft.com',
    'telemetry.microsoft.com','watson.telemetry.microsoft.com','oca.telemetry.microsoft.com',
    'sqm.telemetry.microsoft.com','df.telemetry.microsoft.com','wes.df.telemetry.microsoft.com',
    'reports.wes.df.telemetry.microsoft.com','services.wes.df.telemetry.microsoft.com','sqm.df.telemetry.microsoft.com',
    'telemetry.urs.microsoft.com','choice.microsoft.com','v10.events.data.microsoft.com','v20.events.data.microsoft.com',
    'us-v10.events.data.microsoft.com','eu-v10.events.data.microsoft.com','self.events.data.microsoft.com',
    'functional.events.data.microsoft.com','browser.pipe.aria.microsoft.com','mobile.pipe.aria.microsoft.com',
    'telemetry.appex.bing.net','nexus.officeapps.live.com','nexusrules.officeapps.live.com',
    'eu-mobile.events.data.microsoft.com','us-mobile.events.data.microsoft.com',
    'jp.events.data.microsoft.com','uk.events.data.microsoft.com',
    'in.events.data.microsoft.com','au.events.data.microsoft.com',
    'ca.events.data.microsoft.com','br.events.data.microsoft.com',
    'de.events.data.microsoft.com','fr.events.data.microsoft.com',
    'asia.events.data.microsoft.com','tb.events.data.microsoft.com',
    'v10.vortex-win.data.microsoft.com','v10c.events.data.microsoft.com',
    'events-sandbox.data.microsoft.com','events.data.microsoft.com',
    'watson.events.data.microsoft.com','umwatson.events.data.microsoft.com',
    'settings-win.data.microsoft.com','settings-sandbox.data.microsoft.com',
    'ceuswatcab01.blob.core.windows.net','ceuswatcab02.blob.core.windows.net',
    'eaus2watcab01.blob.core.windows.net','eaus2watcab02.blob.core.windows.net',
    'weus2watcab01.blob.core.windows.net','weus2watcab02.blob.core.windows.net',
    'oca.telemetry.microsoft.com.nsatc.net','sqm.telemetry.microsoft.com.nsatc.net',
    'telecommand.telemetry.microsoft.com.nsatc.net','vortex-sandbox.data.microsoft.com',
    'cs11.wpc.v0cdn.net','cs1137.wpc.gammacdn.net','modern.watson.data.microsoft.com',
    'browser.events.data.msn.com',
    # Найдены разбором чистой Windows 11 25H2 (сборка 26300): адреса прямой
    # отправки 1DS, зашитые в системные файлы и в скачанную настройку UTC.
    # mobile.events — главный из них: на него шлют Защитник (MDCoreSvc),
    # оболочка (AriaSDKWrapper.dll), Copilot, «Архивация» и «История файлов»,
    # минуя службу DiagTrack. Региональные v20 UTC выбирает по стране.
    'mobile.events.data.microsoft.com','au-mobile.events.data.microsoft.com',
    'jp-mobile.events.data.microsoft.com','uk-mobile.events.data.microsoft.com',
    'pf.events.data.microsoft.com','eu-office.events.data.microsoft.com',
    'browser.events.data.microsoft.com','nw-umwatson.events.data.microsoft.com',
    'au-v10.events.data.microsoft.com','in-v10.events.data.microsoft.com','jp-v10.events.data.microsoft.com',
    'au-v20.events.data.microsoft.com','eu-v20.events.data.microsoft.com','in-v20.events.data.microsoft.com',
    'jp-v20.events.data.microsoft.com','uk-v20.events.data.microsoft.com','us-v20.events.data.microsoft.com',
    'us4-v20.events.data.microsoft.com','us5-v20.events.data.microsoft.com',
    'au.vortex-win.data.microsoft.com','uk.vortex-win.data.microsoft.com','web.vortex.data.microsoft.com',
    'settings.data.microsoft.com','evrsettings-win.data.microsoft.com',
    'activity.windows.com',
    # licensing.mp.microsoft.com здесь больше нет: DNS ведёт его на общий
    # вход frontdoor.licensing.commerce.microsoft.com, через который идут и
    # лицензии приложений Магазина. Закрыв его, программа ломала бы платные
    # приложения, а человек не связал бы это с настройкой приватности.
    # В наблюдении за сетью это имя осталось (TelemetryDnsRegex): видно, что
    # обращение было, но блокировка его не касается.
    # Найдено записью Windows 11 с программой на максимуме: эти адреса всё ещё
    # получали данные. bat.bing.com — рекламный счётчик Bing в Магазине;
    # nelreports.net — отчёты Edge и других программ о сетевых ошибках
    # (Network Error Logging); default.exp-tas.com — раздача экспериментов
    # приложениям («Фотографии», VS Code). Без них всё работает как прежде.
    'bat.bing.com','deff.nelreports.net','aefd.nelreports.net','default.exp-tas.com')
$script:HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"

# Имена, адреса которых делят с чужими службами: по IP их блокировать нельзя
# (см. Get-TelemetryIpList). Проверено запросами DNS: watcab-узлы отвечают
# адресом общего хранилища Azure, default.exp-tas.com — края e-msedge.
$script:FwIpSharedRx = '\.blob\.core\.windows\.net$|^default\.exp-tas\.com$|^bat\.bing\.com$|\.nelreports\.net$|' +
                       '^telemetry\.appex\.bing\.net$|officeapps\.live\.com$|\.data\.msn\.com$|' +
                       '^activity\.windows\.com$|^choice\.microsoft\.com$|\.v0cdn\.net$|\.gammacdn\.net$|' +
                       '^licensing\.mp\.microsoft\.com$'

# Серверы, через которые компьютер регистрируется в каталоге устройств Microsoft
# и сообщает номер устройства. login.live.com здесь нет и быть не должно: без
# него перестанет работать вход в учётную запись Microsoft. Первые три имени
# публично не разрешаются, но Windows их спрашивает — блокировать есть что.
# cs.dds.microsoft.com — нынешний адрес каталога: остальные имена каталога
# публично не разрешаются, но Windows их спрашивает.
$script:GdidHosts = @('cs.dds.microsoft.com', 'dds.microsoft.com', 'fd.dds.microsoft.com', 'aad.cs.dds.microsoft.com',
                      'cdpcs.access.microsoft.com', 'geo.prod.do.dsp.mp.microsoft.com')

# Сервер, который выдаёт номер новому устройству. Его закрывает только запрет
# выдачи (модуль gdidlock) и только у тех, кто входит в Windows без учётной
# записи Microsoft: без него эта учётная запись не работает вовсе.
$script:GdidLockHosts = @('login.live.com', 'account.live.com')

# У блоков номера устройства свои метки: блок телеметрии и они ставятся и
# проверяются порознь. Общий шаблон $script:HostsMarkRegex узнаёт все — откат
# убирает всё, что программа дописала в hosts.
$script:HostsMarkGdidStart = '# --- Win11Privacy: device id block (begin) ---'
$script:HostsMarkGdidEnd   = '# --- Win11Privacy: device id block (end) ---'
$script:HostsMarkLockStart = '# --- Win11Privacy: device id lock (begin) ---'
$script:HostsMarkLockEnd   = '# --- Win11Privacy: device id lock (end) ---'

# Блок телеметрии — любая метка программы, кроме меток номера устройства:
# так узнаются и метки прежних версий, побитые в «?».
function Test-HostsBlock {
    param([string]$Kind = 'telemetry')
    try { $lines = @(Get-Content -LiteralPath $script:HostsPath -ErrorAction Stop) } catch { return $false }
    if ($Kind -eq 'gdid') { return [bool]($lines -contains $script:HostsMarkGdidStart) }
    if ($Kind -eq 'lock') { return [bool]($lines -contains $script:HostsMarkLockStart) }
    return [bool](@(@($lines -match $script:HostsMarkRegex) | Where-Object { $_ -notlike '*device id*' }).Count -gt 0)
}

# Принадлежит ли открывающая метка блоку этого вида
function Test-HostsMarkKind {
    param([string]$Line, [string]$Kind)
    switch ($Kind) {
        'all'  { return $true }
        'gdid' { return ($Line -eq $script:HostsMarkGdidStart) }
        'lock' { return ($Line -eq $script:HostsMarkLockStart) }
        default { return ($Line -notlike '*device id*') }
    }
}

# Строка «0.0.0.0» отвечает только на запрос IPv4. Если у сервера есть адрес
# IPv6, Windows спросит его у DNS и соединится мимо блока — поэтому на каждое
# имя пишется и строка «::».
function Get-HostsWanted {
    param([string]$Kind = 'telemetry')
    $domains = $(switch ($Kind) { 'gdid' { $script:GdidHosts } 'lock' { $script:GdidLockHosts } default { $script:HostsDomains } })
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($d in @($domains)) { $out.Add('0.0.0.0 ' + $d); $out.Add(':: ' + $d) }
    return $out.ToArray()
}

function Get-HostsBlockLines {
    param([string]$Kind = 'telemetry')
    $out = New-Object System.Collections.Generic.List[string]
    try { $lines = @(Get-Content -LiteralPath $script:HostsPath -ErrorAction Stop) } catch { return @() }
    $inside = $false; $mine = $false
    foreach ($l in $lines) {
        if ($l -match $script:HostsMarkRegex) {
            if (-not $inside) { $inside = $true; $mine = (Test-HostsMarkKind $l $Kind) } else { $inside = $false }
            continue
        }
        if ($inside -and $mine -and $l -match '^\s*(0\.0\.0\.0|::)\s+(\S+)\s*$') { $out.Add($Matches[1] + ' ' + $Matches[2]) }
    }
    return $out.ToArray()
}

# Блок стоит и в нём ровно нужный список. Раньше хватало самой метки, и
# домены, добавленные в новых версиях, до уже поставленного блока не доходили.
function Test-HostsBlockCurrent {
    param([string]$Kind = 'telemetry')
    if (-not (Test-HostsBlock -Kind $Kind)) { return $false }
    $have = @(Get-HostsBlockLines -Kind $Kind | Select-Object -Unique)
    $want = @(Get-HostsWanted -Kind $Kind | Select-Object -Unique)
    if ($have.Count -ne $want.Count) { return $false }
    $set = @{}
    foreach ($h in $have) { $set[$h] = $true }
    foreach ($w in $want) { if (-not $set.ContainsKey($w)) { return $false } }
    return $true
}

function Apply-Hosts {
    param([string]$Kind = 'telemetry')
    $wanted = @(Get-HostsWanted -Kind $Kind)
    $count = [int]($wanted.Count / 2)
    $present = Test-HostsBlock -Kind $Kind
    if ($present -and (Test-HostsBlockCurrent -Kind $Kind)) { Write-Log '   [-] блок уже присутствует'; return }
    if ($DryRun) {
        Write-Log $(if ($present) { "   [тест] блок будет обновлён до доменов: $count" } else { "   [тест] будет заблокировано доменов: $count" })
        return
    }
    try {
        if ($script:BackupDir -and (Test-Path -LiteralPath $script:BackupDir)) {
            $copy = Join-Path $script:BackupDir 'hosts.original'
            # копия нужна та, что была до программы, а не после первого блока
            if (-not (Test-Path -LiteralPath $copy)) { Copy-Item -LiteralPath $script:HostsPath -Destination $copy -Force -ErrorAction SilentlyContinue }
        }
        # Весь файл — одной подменой: прежний блок этого вида убран, новый
        # дописан, всё чужое на месте. Раньше прежний блок удалялся отдельной
        # записью, а новый дописывался следом (Add-Content): между ними блока
        # не было вовсе, а оборванная дозапись оставляла его половину.
        $cut = Get-HostsLinesWithout (Read-HostsLines) $Kind
        $block = @('') + $(switch ($Kind) { 'gdid' { $script:HostsMarkGdidStart } 'lock' { $script:HostsMarkLockStart } default { $script:HostsMarkStart } })
        $block += $wanted
        $block += $(switch ($Kind) { 'gdid' { $script:HostsMarkGdidEnd } 'lock' { $script:HostsMarkLockEnd } default { $script:HostsMarkEnd } })
        Write-HostsFile (@($cut.keep) + $block)
        ipconfig /flushdns | Out-Null
        if ($present) { Write-Log ("   [+] список доменов обновлён, теперь их: {0}" -f $count) }
        else { Write-Log ("   [+] заблокировано доменов: {0}" -f $count) }
        $script:Changes++
    } catch { Write-Log "   [!] не удалось изменить hosts: $($_.Exception.Message) (возможно, защищён антивирусом)"; $script:Failures++ }
}

# Kind = all убирает все блоки программы (общий откат); telemetry, gdid и
# lock — только блок своего вида, остальные остаются на месте.
# $true — блока больше нет (убран или не было), $false — hosts не переписался
# (посчитано ошибкой). Файл пишется рядом и подменяет прежний одним действием
# системы: раньше hosts переписывался на месте, и обрыв посередине оставлял
# его недописанным — вместе со строками, которые человек вписал сам.
function Remove-HostsBlock {
    param([string]$Kind = 'all', [switch]$Quiet)
    try {
        $cut = Get-HostsLinesWithout (Read-HostsLines) $Kind
        if ($cut.found -eq 0) { if (-not $Quiet) { Write-Log '   [-] блока в hosts нет' }; return $true }
        Write-HostsFile $cut.keep
        ipconfig /flushdns | Out-Null
        if (-not $Quiet) { Write-Log '   [+] блок блокировки доменов удалён' }
        return $true
    } catch {
        Write-Log ("   [!] hosts не переписался ({0}) -- блок остался на месте" -f $_.Exception.Message)
        $script:Failures++
        return $false
    }
}

# Кодировка hosts — та, в которой он лежит: метка UTF-8 или UTF-16 — она,
# иначе системная ANSI (так его пишет Windows; чужие строки с нелатинскими
# буквами остаются байт в байт).
function Get-HostsEncoding {
    $b = New-Object byte[] 3
    $n = 0
    $fs = [IO.File]::Open($script:HostsPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try { $n = $fs.Read($b, 0, 3) } finally { $fs.Dispose() }
    if ($n -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return (New-Object System.Text.UTF8Encoding $true) }
    if ($n -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { return [System.Text.Encoding]::Unicode }
    return [System.Text.Encoding]::Default
}

function Read-HostsLines { return , ([string[]][IO.File]::ReadAllLines($script:HostsPath, (Get-HostsEncoding))) }

# Строки hosts без блоков программы этого вида. Внутри блока убираются только
# свои строки: чужая строка значит, что закрывающую метку кто-то стёр, и
# дальше идёт уже не наше. Пустую строку перед блоком ставила сама программа.
function Get-HostsLinesWithout {
    param([string[]]$Lines, [string]$Kind)
    $keep = New-Object System.Collections.Generic.List[string]
    $inside = $false; $found = 0
    foreach ($l in @($Lines)) {
        if ($l -match $script:HostsMarkRegex) {
            if (-not $inside) {
                if (-not (Test-HostsMarkKind $l $Kind)) { $keep.Add($l); continue }
                $found++
                if ($keep.Count -gt 0 -and $keep[$keep.Count - 1] -eq '') { $keep.RemoveAt($keep.Count - 1) }
                $inside = $true
            } else { $inside = $false }
            continue
        }
        if ($inside -and $l -notmatch '^\s*((0\.0\.0\.0|::)\s+\S+)?\s*$') { $inside = $false }
        if (-not $inside) { $keep.Add($l) }
    }
    return @{ keep = $keep.ToArray(); found = $found }
}

# hosts целиком: копия рядом (в той же кодировке), сверка копии строка в
# строку, затем подмена одним действием системы (ReplaceFile — права и
# атрибуты прежнего файла сохраняются). Обрыв в любой миг оставляет либо
# прежний hosts, либо новый, но не половину. Копия после себя не остаётся.
function Write-HostsFile {
    param([string[]]$Lines)
    $enc = Get-HostsEncoding
    $tmp = $script:HostsPath + '.w11p-new'
    $want = [string[]]@($Lines)
    try {
        [IO.File]::WriteAllLines($tmp, $want, $enc)
        $back = [IO.File]::ReadAllLines($tmp, $enc)
        if ($back.Count -ne $want.Count) { throw 'копия hosts не совпала с задуманной' }
        for ($i = 0; $i -lt $back.Count; $i++) { if ($back[$i] -cne $want[$i]) { throw ('копия hosts не совпала с задуманной в строке {0}' -f ($i + 1)) } }
        Replace-FileAtomic $tmp $script:HostsPath
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

# --- брандмауэр ------------------------------------------------------------- #
function Get-FwRuleName { param([string]$Kind, [string]$Target) if ($Kind -eq 'svc') { return "Win11Privacy: служба $Target" } return ("Win11Privacy: " + (Split-Path $Target -Leaf)) }

function Test-FwRule {
    param([string]$Kind, [string]$Target)
    $r = Get-NetFirewallRule -DisplayName (Get-FwRuleName $Kind $Target) -ErrorAction SilentlyContinue
    return [bool]($r -and $r.Enabled -eq 'True')
}

function Apply-FwRule {
    param([string]$Kind, [string]$Target, [string]$Comment)
    if ($DryRun) { Write-Log "   [тест] $Comment"; return }
    $name = Get-FwRuleName $Kind $Target
    try {
        if (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue) { Write-Log "   [-] $Comment -- уже есть"; return }
        if ($Kind -eq 'svc') {
            New-NetFirewallRule -DisplayName $name -Group $script:FwGroup -Direction Outbound -Action Block -Service $Target -Profile Any -Enabled True -ErrorAction Stop | Out-Null
        } else {
            New-NetFirewallRule -DisplayName $name -Group $script:FwGroup -Direction Outbound -Action Block -Program $Target -Profile Any -Enabled True -ErrorAction Stop | Out-Null
        }
        Write-Log "   [+] $Comment"; $script:Changes++
    } catch { Write-Log "   [!] не удалось: $Comment -- $($_.Exception.Message)"; $script:Failures++ }
}

# Адреса телеметрии: часть известна давно, часть узнаём разбором имён
# перед самой блокировкой — так список не устаревает.
$script:FwIpRuleName = 'Win11Privacy: адреса телеметрии'
$script:TelemetryIps = @(
    '13.64.90.137','13.68.31.193','13.68.82.8','13.69.109.130','13.69.239.72',
    '13.73.26.107','20.44.86.43','40.79.85.125','51.104.136.2',
    '65.52.100.7','65.52.100.9','65.52.100.11','65.55.252.43','65.55.252.63',
    '65.55.252.70','65.55.252.71','65.55.252.92','65.55.252.93',
    '66.119.144.157','168.61.24.141','168.61.146.25','168.62.187.13',
    '191.232.139.2','191.232.80.58','191.239.52.100'
)

# Имена спрашиваются все сразу, а не по одному. Части адресов из списка давно
# нет, и на каждый такой запрос Windows ждёт ответа DNS: за VPN или при
# молчащем DNS роутера — по 10–15 секунд. По очереди шаг тянулся минутами без
# единой строки в журнале и выглядел зависшим. Кто не ответил за отведённое
# время, в правило не попадёт — известные адреса выше в нём есть всегда.
# Имена спрашиваются у DNS-сервера В ОБХОД hosts. Раньше разрешение шло через
# системный резолвер, а он сначала смотрит в hosts: при стоящем блоке каждое
# имя «разрешалось» в 0.0.0.0, отсеивалось, и в правило попадали только
# зашитые адреса. Имена спрашиваются все сразу, в пуле потоков: по одному шаг
# тянулся минутами, пока мёртвые имена ждали ответа. Берутся и адреса IPv6.
function Get-TelemetryIpList {
    param([int]$TimeoutMs = 10000)
    $set = @{}
    foreach ($ip in $script:TelemetryIps) { $set[$ip] = $true }
    # Правило брандмауэра закрывает адреса для ВСЕХ программ, а часть имён
    # сбора живёт на общих узлах: ceuswatcab01.blob.core.windows.net — это
    # общий узел Azure Storage, default.exp-tas.com — общий край e-msedge,
    # nexus.officeapps.live.com — общий вход Office (проверено запросами DNS).
    # Закрыв такой адрес, программа закрыла бы вместе с ним чужие службы —
    # чьи-то файлы в облаке, обновления, лицензии. По IP эти имена не
    # блокируются; в hosts они остаются, и там блокировка точная, по имени.
    $shared = @($script:HostsDomains | Where-Object { $_ -match $script:FwIpSharedRx } | Select-Object -Unique)
    $names = @($script:HostsDomains | Where-Object { $_ -notmatch $script:FwIpSharedRx } | Select-Object -Unique)
    if ($shared.Count -gt 0) {
        Write-Log ("   имён на общих узлах (их адреса делят чужие службы) не блокируется по IP: {0} -- в hosts они закрыты" -f $shared.Count)
    }
    $pool = [runspacefactory]::CreateRunspacePool(1, 32)
    $pool.Open()
    $jobs = New-Object System.Collections.Generic.List[object]
    foreach ($nm in $names) {
        $parsed = $null
        if ([System.Net.IPAddress]::TryParse($nm, [ref]$parsed)) { if (Test-PublicIp $nm) { $set[$nm] = $true }; continue }
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        # -DnsOnly: мёртвое имя не уходит искать себя по локальной сети (LLMNR, NetBIOS)
        $null = $ps.AddScript('param($n) @(Resolve-DnsName -Name $n -Type A_AAAA -NoHostsFile -DnsOnly -QuickTimeout -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress } | ForEach-Object { [string]$_.IPAddress })').AddArgument($nm)
        $jobs.Add(@{ ps = $ps; h = $ps.BeginInvoke() })
    }
    $until = (Get-Date).AddMilliseconds($TimeoutMs)
    $answered = 0
    foreach ($j in $jobs) {
        $left = [int][math]::Max(0, ($until - (Get-Date)).TotalMilliseconds)
        if ($j.h.AsyncWaitHandle.WaitOne($left)) {
            try {
                $res = @($j.ps.EndInvoke($j.h))
                if ($res.Count -gt 0) { $answered++ }
                foreach ($a in $res) { if (Test-PublicIp "$a") { $set["$a"] = $true } }
            } catch { }
            $j.ps.Dispose()
        } else {
            # Не ответившее имя не ждём: синхронная остановка висела бы, пока
            # DNS не сдастся сам. Хвосты уйдут вместе с процессом движка.
            try { $null = $j.ps.BeginStop($null, $null) } catch { }
        }
    }
    try { $null = $pool.BeginClose($null, $null) } catch { }
    return @{ ips = @($set.Keys); answered = $answered; asked = $names.Count }
}

# Правило помнит дату обновления в описании. Адреса серверов меняются, и
# старше двух недель правило считается устаревшим — страж его обновит.
function Test-FwIpRule {
    param([switch]$Fresh)
    $r = Get-NetFirewallRule -DisplayName $script:FwIpRuleName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $r) { return $false }
    if (-not $Fresh) { return $true }
    if ("$($r.Description)" -match '(\d{4}-\d{2}-\d{2})') { try { return ([datetime]$Matches[1]) -gt (Get-Date).AddDays(-14) } catch { } }
    return $false
}

# IP-адрес в каноническом виде (IPv6 — сжатый, строчными), не адрес — $null
function ConvertTo-IpCanonical {
    param([string]$Text)
    $ip = $null
    if ([System.Net.IPAddress]::TryParse("$Text".Trim(), [ref]$ip)) { return $ip.ToString().ToLowerInvariant() }
    return $null
}

function Apply-FwIpBlock {
    if ($DryRun) { Write-Log '   [тест] будут заблокированы адреса сбора телеметрии'; return }
    try {
        Write-Log '   узнаю текущие адреса серверов сбора — не дольше 10 секунд'
        $found = Get-TelemetryIpList
        $ips = @($found.ips)
        Write-Log ("   ответили DNS имён: {0} из {1}" -f $found.answered, $found.asked)
        # каждый адрес — в каноническом виде и один раз: «2001:DB8::1» и
        # «2001:db8:0::1» — один адрес, и сверять потом надо множества
        $wantSet = @{}
        foreach ($a in $ips) { $n = ConvertTo-IpCanonical $a; if ($n) { $wantSet[$n] = $true } }
        $ips = @($wantSet.Keys | Sort-Object)
        if ($ips.Count -eq 0) { Write-Log '   [-] адреса не определились'; return }
        # Новое правило ставится рядом со старым, проверяется, и только потом
        # старое убирается. Раньше старое удалялось первым: не создалось
        # новое — не оставалось никакого, и адреса сбора открывались.
        $old = @(Get-NetFirewallRule -DisplayName $script:FwIpRuleName -ErrorAction SilentlyContinue)
        $id = 'Win11Privacy-TelemetryIp-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        New-NetFirewallRule -Name $id -DisplayName $script:FwIpRuleName -Group $script:FwGroup -Direction Outbound -Action Block `
            -RemoteAddress $ips -Profile Any -Enabled True -Description ('Win11Privacy: updated ' + (Get-Date).ToString('yyyy-MM-dd')) -ErrorAction Stop | Out-Null
        $why = ''
        $new = Get-NetFirewallRule -Name $id -ErrorAction SilentlyContinue
        if (-not $new) { $why = 'правило не появилось' }
        elseif ("$($new.Enabled)" -ne 'True' -or "$($new.Action)" -ne 'Block' -or "$($new.Direction)" -ne 'Outbound') { $why = 'правило создалось не таким, как задумано' }
        else {
            # множество адресов в правиле — ровно то, что задумано: не только
            # сколько, но и какие (раньше сверялось одно число)
            $gotSet = @{}
            foreach ($a in @((Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $new -ErrorAction Stop).RemoteAddress)) {
                $n = ConvertTo-IpCanonical $a
                $gotSet[$(if ($n) { $n } else { "?$a" })] = $true
            }
            $missing = @($wantSet.Keys | Where-Object { -not $gotSet.ContainsKey($_) } | Sort-Object)
            $extra = @($gotSet.Keys | Where-Object { -not $wantSet.ContainsKey($_) } | Sort-Object)
            if ($missing.Count -or $extra.Count) {
                $why = ("в правиле не те адреса: нет {0}, лишние {1}" -f $(if ($missing.Count) { $missing -join ', ' } else { '—' }), $(if ($extra.Count) { $extra -join ', ' } else { '—' }))
            }
        }
        if ($why) {
            Remove-NetFirewallRule -Name $id -ErrorAction SilentlyContinue
            Write-Log ("   [!] новое правило не прошло проверку ({0}) -- {1}" -f $why, $(if ($old.Count) { 'оставлено прежнее' } else { 'адреса не заблокированы' }))
            $script:Failures++; return
        }
        foreach ($o in $old) {
            try { Remove-NetFirewallRule -Name $o.Name -ErrorAction Stop }
            catch { Write-Log ("   [!] прежнее правило адресов не убралось: {0}" -f $_.Exception.Message); $script:Failures++ }
        }
        Write-Log ("   [+] заблокировано адресов: {0}" -f $ips.Count)
        Write-Log '   [-] если что-то перестанет работать — снимите этот пункт и нажмите «Откат»'
        $script:Changes++
    } catch { Write-Log "   [!] не удалось заблокировать адреса: $($_.Exception.Message)"; $script:Failures++ }
}

# Шифрованный DNS в системе и браузерах — через него hosts не работает
function Get-DohStatus {
    $win = $false
    try {
        $root = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters'
        foreach ($k in @(Get-ChildItem -LiteralPath $root -Recurse -ErrorAction SilentlyContinue)) {
            if ($k.PSChildName -match '^\d+\.' -or $k.PSPath -match 'DohInterfaceSettings') {
                $v = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).DohFlags
                if ($null -ne $v -and [int64]$v -ne 0) { $win = $true }
            }
        }
    } catch { }
    $policy = (Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'DoHPolicy')
    $edge = (Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DnsOverHttpsMode')
    $chrome = (Get-RegValue 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'DnsOverHttpsMode')
    return @{ windows = $win; policy = "$policy"; edge = "$edge"; chrome = "$chrome"
              blocked = ("$policy" -eq '1' -and "$edge" -eq 'off' -and "$chrome" -eq 'off') }
}

