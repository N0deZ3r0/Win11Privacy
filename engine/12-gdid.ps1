
# =========================================================================== #
#  НОМЕР УСТРОЙСТВА (GDID): где лежит, как сменить, как запретить выдачу
#  Номер — идентификатор «устройства» в службе учётных записей Microsoft
#  (Device PUID). Его выдаёт login.live.com, когда служба wlidsvc заводит
#  компьютеру «личность»: отдельную учётную запись устройства с ключом в
#  хранилище учётных данных. Номер привязан к этой личности, а не к железу —
#  поэтому переустановка Windows даёт новый. Копий номера в реестре несколько,
#  и пока цела личность, стёртые копии возвращаются тем же номером. Стереть
#  личность целиком — значит сменить номер: при следующем обращении Windows
#  заведёт новую и получит новый. Если сервер выдачи закрыт — не получит.
#  Разбор: github.com/SmtimesIWndr/gdid-reversal, github.com/yegors/deGDID.
# =========================================================================== #
$script:IdCrlRoots = @(
    @{ who = 'user';   path = 'HKCU:\SOFTWARE\Microsoft\IdentityCRL' },
    @{ who = 'system'; path = 'Registry::HKEY_USERS\.DEFAULT\Software\Microsoft\IdentityCRL' },
    @{ who = 'system'; path = 'Registry::HKEY_USERS\S-1-5-18\Software\Microsoft\IdentityCRL' })
$script:IdCrlNegCache = 'HKLM:\SOFTWARE\Microsoft\IdentityCRL\NegativeCache'
# Места, которые не удалось прочитать при последнем поиске копий: без них
# «копий не осталось» было бы неправдой.
$script:GdidUnreadable = New-Object System.Collections.Generic.List[string]
# Кэш платформы подключённых устройств: в нём регистрация в каталоге устройств
$script:CdpCache = Join-Path $env:LOCALAPPDATA 'ConnectedDevicesPlatform'

# Кроме своего профиля и системного — профили других пользователей, которые
# сейчас вошли в Windows: их кусты реестра подключены. Профили тех, кто сейчас
# не вошёл, не подключены — программа их не трогает и честно об этом пишет.
# Подключённые кусты реестра — одними именами, без открытия каждого
function Get-GdidHiveNames { return @([Microsoft.Win32.Registry]::Users.GetSubKeyNames()) }

# Профили людей: локальные и доменные учётные записи (S-1-5-21-…) и
# учётные записи Entra ID (S-1-12-1-…). Раньше вторые не считались вовсе.
$script:GdidUserSidRx = '^S-1-(5-21|12-1)-[\d-]+$'
$script:GdidProfileListKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'

function Get-IdCrlRoots {
    $roots = New-Object System.Collections.Generic.List[object]
    foreach ($r in $script:IdCrlRoots) { $roots.Add($r) }
    $me = ''
    try { $me = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value } catch { }
    # Список подключённых кустов не прочитался — копии номера у других
    # вошедших пользователей не искались, и это записано: опись тогда
    # Unverified, а стирание не начинается (Get-GdidPreflight). Раньше ошибка
    # глоталась, и «копий нет» говорилось, не заглянув к ним.
    $names = @()
    try { $names = @(Get-GdidHiveNames) } catch { $script:GdidUnreadable.Add('Registry::HKEY_USERS') }
    foreach ($sid in $names) {
        if ($sid -notmatch $script:GdidUserSidRx -or $sid -eq $me) { continue }
        $roots.Add(@{ who = 'other'; path = "Registry::HKEY_USERS\$sid\Software\Microsoft\IdentityCRL" })
    }
    return $roots.ToArray()
}

# Профили пользователей: какие подключены (их копии номера проверяются) и
# какие нет — тех, кто сейчас не вошёл в Windows: их куст не подключён, и
# программа его не подключает и не трогает. Ответ — не число, а опись:
#   loadedProfiles / unloadedProfiles (+ unloadedSids) — сколько каких;
#   enumerationFailed — список кустов (HKEY_USERS) или профилей (ProfileList)
#       не прочитался: сколько профилей не проверено, неизвестно. Раньше в
#       этом случае отвечалось «0», то есть «проверены все»;
#   unverified — проверены не все (есть неподключённые или список не прочитался);
#   places — что не прочиталось (для описи), errors — почему.
# state: Complete, Unloaded, EnumerationFailed.
function Get-UncheckedProfiles {
    $errs = New-Object System.Collections.Generic.List[string]
    $places = New-Object System.Collections.Generic.List[string]
    $loaded = $null
    try { $loaded = @(Get-GdidHiveNames) }
    catch { $places.Add('Registry::HKEY_USERS'); $errs.Add(("HKEY_USERS: {0}" -f $_.Exception.Message)) }
    $listed = $null
    $pl = $null
    try {
        $pl = Open-RegKeyRead $script:GdidProfileListKey
        # список профилей есть в любой Windows: его нет — прочитать не вышло
        if ($null -eq $pl) { $places.Add($script:GdidProfileListKey); $errs.Add('ProfileList: ключа нет') }
        else { $listed = @($pl.GetSubKeyNames()) }
    } catch { $places.Add($script:GdidProfileListKey); $errs.Add(("ProfileList: {0}" -f $_.Exception.Message)) }
    finally { if ($null -ne $pl) { $pl.Close() } }
    $loadedN = 0
    $unloaded = New-Object System.Collections.Generic.List[string]
    if ($null -ne $loaded -and $null -ne $listed) {
        foreach ($sid in $listed) {
            if ($sid -notmatch $script:GdidUserSidRx) { continue }
            if ($loaded -contains $sid) { $loadedN++ } else { $unloaded.Add($sid) }
        }
    }
    $failed = ($errs.Count -gt 0)
    return @{ loadedProfiles = $loadedN; unloadedProfiles = $unloaded.Count; unloadedSids = $unloaded.ToArray()
              enumerationFailed = $failed; unverified = ($failed -or $unloaded.Count -gt 0)
              places = $places.ToArray(); errors = $errs.ToArray()
              state = $(if ($failed) { 'EnumerationFailed' } elseif ($unloaded.Count -gt 0) { 'Unloaded' } else { 'Complete' }) }
}

# Ключ реестра для чтения — снимок: state ok, missing (ключа нет) или denied
# (Windows не дала открыть); имена значений и подключей и нужные значения.
# Через API реестра, а не провайдер PowerShell: Get-ChildItem открывает
# каждый подключ сам и путает «не пустили в подключ» с ошибкой перечисления.
function Read-GdidKey {
    param([string]$Path, [string[]]$Values = @())
    $k = $null
    try {
        $k = Open-RegKeyRead $Path
        if ($null -eq $k) { return @{ state = 'missing'; path = $Path; valueNames = @(); subKeys = @(); values = @{}; error = '' } }
        $vn = @($k.GetValueNames())
        $vals = @{}
        foreach ($n in @($Values)) { if ($vn -contains $n) { $vals[$n] = $k.GetValue($n) } }
        return @{ state = 'ok'; path = $Path; valueNames = $vn; subKeys = @($k.GetSubKeyNames()); values = $vals; error = '' }
    } catch {
        return @{ state = 'denied'; path = $Path; valueNames = @(); subKeys = @(); values = @{}; error = "$($_.Exception.Message)" }
    } finally { if ($null -ne $k) { $k.Close() } }
}

# Тот же ключ для записи (удаления). Нет ключа — $null; нет доступа — исключение.
function Open-GdidKeyWrite {
    param([string]$Path)
    $hive = $null; $sub = ''
    switch -Regex ($Path) {
        '^(HKLM:|Registry::HKEY_LOCAL_MACHINE)(\\(.*))?$' { $hive = [Microsoft.Win32.Registry]::LocalMachine; $sub = $Matches[3]; break }
        '^(HKCU:|Registry::HKEY_CURRENT_USER)(\\(.*))?$'  { $hive = [Microsoft.Win32.Registry]::CurrentUser; $sub = $Matches[3]; break }
        '^(HKU:|Registry::HKEY_USERS)(\\(.*))?$'          { $hive = [Microsoft.Win32.Registry]::Users; $sub = $Matches[3]; break }
    }
    if ($null -eq $hive -or -not "$sub".Trim('\')) { throw ("ключ не для записи: {0}" -f $Path) }
    return $hive.OpenSubKey("$sub".TrimEnd('\'), $true)
}

# Удалить одно значение и проверить, что его нет: removed, absent, denied
function Remove-GdidRegValue {
    param([string]$Path, [string]$Name)
    $k = $null
    try {
        $k = Open-GdidKeyWrite $Path
        if ($null -eq $k) { return 'absent' }
        if (@($k.GetValueNames()) -notcontains $Name) { return 'absent' }
        $k.DeleteValue($Name, $false)
    } catch { return 'denied' }
    finally { if ($null -ne $k) { $k.Close() } }
    # «команда прошла» — ещё не «значения нет»: сверяем
    $chk = Read-GdidKey $Path
    if ($chk.state -eq 'missing' -or ($chk.state -eq 'ok' -and @($chk.valueNames) -notcontains $Name)) { return 'removed' }
    return 'denied'
}

# Удалить один подключ и проверить, что его нет. Без -Tree удаляется только
# ключ без подключей: если внутри есть что-то ещё, ключ остаётся целым (kept)
# — удалять то, чего программа не опознала, нельзя.
# Ответ: removed, absent, denied, kept.
function Remove-GdidRegKey {
    param([string]$Parent, [string]$Name, [switch]$Tree)
    $pk = $null
    try {
        $pk = Open-GdidKeyWrite $Parent
        if ($null -eq $pk) { return 'absent' }
        if (@($pk.GetSubKeyNames()) -notcontains $Name) { return 'absent' }
        if (-not $Tree) {
            $ck = $pk.OpenSubKey($Name, $false)
            $n = $(if ($null -ne $ck) { try { $ck.SubKeyCount } finally { $ck.Close() } } else { 0 })
            if ($n -gt 0) { return 'kept' }
            $pk.DeleteSubKey($Name, $false)
        } else { $pk.DeleteSubKeyTree($Name, $false) }
    } catch {
        $ex = $_.Exception
        if ($ex -is [System.InvalidOperationException] -or $ex.InnerException -is [System.InvalidOperationException]) { return 'kept' }
        return 'denied'
    } finally { if ($null -ne $pk) { $pk.Close() } }
    $chk = Read-GdidKey ("{0}\{1}" -f $Parent.TrimEnd('\'), $Name)
    if ($chk.state -eq 'missing') { return 'removed' }
    return 'denied'
}

# Удаление одной записи с ответом: removed — было и убрано, absent — не было,
# denied — Windows не дала. Раньше всё удалялось молча, и отказ выглядел как успех.
function Remove-RegStatus {
    param([string]$Path, [string]$Name = '')
    # «Не было» — только когда Windows прямо ответила, что такого ключа нет.
    # Раньше параметр читался через Get-RegValue, а она и при отказе в доступе
    # отдаёт пустоту: закрытая запись засчитывалась как «не было», хотя номер
    # в ней оставался. Test-Path тоже не годится — на закрытый ключ он говорит
    # «есть», и дальше уже не понять, отчего не вышло.
    try { $key = Get-Item -LiteralPath $Path -ErrorAction Stop }
    catch [System.Management.Automation.ItemNotFoundException] { return 'absent' }
    catch { return 'denied' }
    try {
        if ($Name) {
            if (@($key.GetValueNames()) -notcontains $Name) { return 'absent' }
            Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop
        } else {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
    } catch { return 'denied' } finally { if ($key) { $key.Close() } }
    # «Команда прошла» — ещё не «удалено»: сверяем, что записи и правда нет
    try {
        $now = Get-Item -LiteralPath $Path -ErrorAction Stop
        try { if (-not $Name -or @($now.GetValueNames()) -contains $Name) { return 'denied' } } finally { $now.Close() }
    } catch [System.Management.Automation.ItemNotFoundException] { }
    catch { return 'denied' }
    return 'removed'
}
$script:DevicePuidRegex = '^0018[0-9A-Fa-f]{12}$'
# Учётные данные «личности» устройства — у пользователя и у самой системы
$script:GdidCredUser   = @('WindowsLive:target=virtualapp/didlogical', 'MicrosoftAccount:target=SSO_POP_Device')
$script:GdidCredSystem = @('WindowsLive:target=virtualapp/didlogical')
$script:GdidRefusal = $null

function ConvertTo-Gdid {
    param([string]$Hex)
    if ($Hex -notmatch '^[0-9A-Fa-f]{1,16}$') { return '' }
    try { return 'g:' + [Convert]::ToUInt64($Hex, 16) } catch { return '' }
}

# Тип запуска службы по реестру: число и слово. start = -1 и Missing — службы
# нет; -2 и ReadError — прочитать не удалось. Раньше оба случая давали -1:
# закрытый от чтения ключ выглядел «нет на этой системе».
function Get-SvcStartInfo {
    param([string]$Name)
    $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    $raw = Get-RegRaw $k 'Start'
    $why = ''
    if (-not $raw.ok) { $why = "$($raw.error)" }
    elseif (-not $raw.exists) {
        $kx = Test-RegKeyExists $k
        if ($kx -eq $false) { return @{ name = $Name; start = -1; state = 'Missing'; error = '' } }
        $why = $(if ($null -eq $kx) { 'ключ службы не читается' } else { 'у службы нет параметра Start' })
    } elseif ("$($raw.kind)" -ne 'DWord') { $why = ("параметр Start вида {0}" -f $raw.kind) }
    else {
        $v = [int64]$raw.value
        $state = $(switch ($v) { 0 { 'Boot' } 1 { 'System' } 2 { 'Automatic' } 3 { 'Manual' } 4 { 'Disabled' } default { '' } })
        if ($state) { return @{ name = $Name; start = [int]$v; state = $state; error = '' } }
        $why = ("непонятный тип запуска {0}" -f $v)
    }
    return @{ name = $Name; start = -2; state = 'ReadError'; error = $why }
}

function Get-SvcStart {
    param([string]$Name)
    return [int](Get-SvcStartInfo $Name).start
}

# Служба глазами диспетчера служб: работает ли и какой тип запуска он помнит.
# Службу, отключённую прямо в реестре, диспетчер до перезагрузки помнит
# прежней — и может запустить. found = $false — такой службы он не знает;
# ok = $false — не ответил.
function Get-SvcScmView {
    param([string]$Name)
    $ev = $null
    $s = Get-Service -Name $Name -ErrorAction SilentlyContinue -ErrorVariable ev
    if (-not $s) {
        $errs = @($ev | Where-Object { $_ -and "$($_.FullyQualifiedErrorId)" -notlike 'NoServiceFoundForGivenName*' })
        if ($errs.Count -eq 0) { return @{ ok = $true; found = $false; running = $false; status = ''; start = ''; error = '' } }
        return @{ ok = $false; found = $false; running = $false; status = ''; start = ''; error = "$($errs[0])" }
    }
    $s = @($s)[0]
    $run = ("$($s.Status)" -ne 'Stopped')
    try { $st = "$($s.StartType)" }
    catch { return @{ ok = $false; found = $true; running = $run; status = "$($s.Status)"; start = ''; error = $_.Exception.Message } }
    return @{ ok = $true; found = $true; running = $run; status = "$($s.Status)"; start = $st; error = '' }
}

# Служба целиком — одной записью: тип запуска по реестру (start, state —
# см. Get-SvcStartInfo) и глазами диспетчера служб (scmStart, running,
# status). Её же читают проверка передачи и снимок перед стиранием.
#   config  — Disabled, Manual, Automatic, Missing (службы нет), Unknown
#             (тип запуска не прочитался);
#   runtime — Running, Stopped, Missing, Unknown (диспетчер не ответил:
#             служба, к которой нет доступа, — «неизвестно», а не «стоит»);
#   readable — прочиталось всё, что нужно, чтобы судить о службе.
function Get-GdidSvcEntry {
    param([string]$Name)
    $i = Get-SvcStartInfo $Name
    $v = Get-SvcScmView $Name
    $i['running'] = [bool]$v.running
    $i['status'] = "$($v.status)"
    $i['scmStart'] = "$($v.start)"
    $i['scmOk'] = [bool]$v.ok
    $i['scmFound'] = [bool]$v.found
    $i['scmError'] = "$($v.error)"
    $i['config'] = $(switch ("$($i.state)") { 'Disabled' { 'Disabled' } 'Manual' { 'Manual' } { $_ -in @('Automatic', 'Boot', 'System') } { 'Automatic' } 'Missing' { 'Missing' } default { 'Unknown' } })
    $i['runtime'] = $(if (-not $v.ok) { 'Unknown' } elseif (-not $v.found) { 'Missing' } elseif ($v.running) { 'Running' } else { 'Stopped' })
    $i['readable'] = ("$($i.state)" -ne 'ReadError' -and [bool]$v.ok)
    return $i
}

# Копии CDPUserSvc у каждого вошедшего пользователя (CDPUserSvc_1a2b3) — по
# именам ключей служб, без открытия чужих (часть ключей служб закрыта).
function Get-GdidUserSvcInstances {
    $k = $null
    try {
        $k = Open-RegKeyRead 'HKLM:\SYSTEM\CurrentControlSet\Services'
        if ($null -eq $k) { return @{ ok = $false; names = @(); error = 'нет списка служб' } }
        $names = @($k.GetSubKeyNames() | Where-Object { $_ -match '^CDPUserSvc_[0-9A-Fa-f]+$' } | Sort-Object)
        return @{ ok = $true; names = $names; error = '' }
    } catch { return @{ ok = $false; names = @(); error = "$($_.Exception.Message)" } }
    finally { if ($null -ne $k) { $k.Close() } }
}

# Службы, через которые номер уходит наружу: их отключает модуль gdid
$script:GdidSvcNames = @('CDPSvc', 'CDPUserSvc', 'DoSvc')

# Идёт ли номер наружу. Одна проверка на всех: вкладка «Номер устройства» и
# «Цифровой след». Раньше обе смотрели только CDPSvc и DoSvc — CDPUserSvc и
# её копии у каждого пользователя (CDPUserSvc_1a2b3), которые модуль тоже
# отключает, не проверялись вовсе, а «службы нет» и «не прочиталось»
# сливались в одно.
#   off — отключено, и это проверено: все три службы отключены (или их нет),
#         ни одна не работает, копий CDPUserSvc с прежним типом запуска нет,
#         и диспетчер служб видит то же, что реестр;
#   pending — в реестре всё отключено, но действует ещё прежнее: служба не
#         остановилась, копия CDPUserSvc заведена до отключения (Windows
#         уберёт её при выходе пользователя) или диспетчер служб до
#         перезагрузки помнит прежний тип запуска;
#   known — прочиталось всё. Не прочиталось — off не бывает.
# state: Off, Pending, On (хоть одна служба может работать), Unknown.
function Get-GdidTransmitState {
    $problems = New-Object System.Collections.Generic.List[string]
    $look = {
        param([string]$SvcName)
        $Info = Get-GdidSvcEntry $SvcName
        if (-not $Info.scmOk) { $problems.Add(("{0}: диспетчер служб не ответил ({1})" -f $Info.name, $Info.scmError)) }
        if ($Info.state -eq 'ReadError') { $problems.Add(("{0}: тип запуска не прочитался ({1})" -f $Info.name, $Info.error)) }
        $Info
    }
    $out = New-Object System.Collections.Generic.List[object]
    $allOff = $true; $settled = $true; $on = $false
    foreach ($n in $script:GdidSvcNames) {
        $i = & $look $n
        if ($i.state -in @('Boot', 'System', 'Automatic', 'Manual')) { $on = $true }
        if ($i.state -notin @('Disabled', 'Missing')) { $allOff = $false }
        if ($i.running) { $settled = $false }
        if ($i.state -eq 'Disabled' -and $i.scmStart -and $i.scmStart -ne 'Disabled') { $settled = $false }
        if ($n -eq 'CDPUserSvc') {
            $inst = Get-GdidUserSvcInstances
            if (-not $inst.ok) { $problems.Add(("копии CDPUserSvc не перечислились: {0}" -f $inst.error)) }
            $il = New-Object System.Collections.Generic.List[object]
            foreach ($nm in @($inst.names)) {
                $ii = & $look $nm
                if ($ii.state -notin @('Disabled', 'Missing') -or $ii.running) { $settled = $false }
                if ($ii.running) { $i['running'] = $true }
                $il.Add($ii)
            }
            $i['instances'] = $il.ToArray()
        }
        $out.Add($i)
    }
    $known = ($problems.Count -eq 0)
    $off = ($known -and $allOff -and $settled)
    $state = $(if ($off) { 'Off' } elseif ($on) { 'On' } elseif (-not $known) { 'Unknown' } else { 'Pending' })
    return @{ off = $off; pending = ($state -eq 'Pending'); known = $known; state = $state
              services = $out.ToArray(); problems = $problems.ToArray() }
}

# Снимок служб перед стиранием — всех, которые стирание трогает: wlidsvc
# (её отключают на время стирания), CDPSvc, DoSvc, шаблон CDPUserSvc и его
# копии у вошедших пользователей (CDPUserSvc_1a2b3). У каждой — тип запуска
# по реестру и диспетчеру служб и работает ли она (Get-GdidSvcEntry).
# complete — прочиталось всё; без этого стирание не начинается: вернуть
# службы как были было бы не по чему. Раньше состояния собирались по
# отдельности, а ошибки Get-Service глотались — и служба, о которой ничего
# не узнали, после стирания оставалась остановленной.
function Get-GdidServiceSnapshot {
    $list = New-Object System.Collections.Generic.List[object]
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($n in @(@('wlidsvc') + @($script:GdidSvcNames))) { $list.Add((Get-GdidSvcEntry $n)) }
    $inst = Get-GdidUserSvcInstances
    if (-not $inst.ok) { $problems.Add(("копии CDPUserSvc не перечислились: {0}" -f $inst.error)) }
    foreach ($nm in @($inst.names)) {
        if (-not $nm) { continue }
        $e = Get-GdidSvcEntry $nm
        $e['instance'] = $true
        $list.Add($e)
    }
    foreach ($e in $list.ToArray()) {
        if ("$($e.state)" -eq 'ReadError') { $problems.Add(("{0}: тип запуска не прочитался ({1})" -f $e.name, $e.error)) }
        if (-not $e.scmOk) { $problems.Add(("{0}: диспетчер служб не ответил ({1})" -f $e.name, $e.scmError)) }
    }
    return @{ complete = ($problems.Count -eq 0); services = $list.ToArray(); problems = $problems.ToArray()
              time = (Get-Date).ToString('s') }
}

# Записи номера в реестре — одна опись и для поиска, и для стирания: стирание
# удаляет ровно найденное здесь, а не ветки целиком. Раньше опись пропускала
# DeviceIdentities\production\Logs, а стирание удаляло весь production вместе
# с ним и со всем, чего программа не опознала. Записи:
#   lid      — значение LID в ExtendedProperties (сам номер);
#   property — значения с именем-номером в Immersive\production\Property;
#   token    — значения DeviceId и DeviceTicket билета приложения (прочие
#              значения билета — ApplicationFlags, UserId, UserTicket — не его);
#   identity — «личность» устройства DeviceIdentities\production\<SID>\<имя>
#              со значением DeviceId; указатель на неё (ValidDeviceId в
#              разделе <SID>) — часть той же записи. Logs (история выдачи),
#              DeviceLicenseUpdateFailureCount и подключи без DeviceId — не
#              записи номера: они не считаются и не удаляются;
#   cache    — запись NegativeCache с именем «<номер>_<SID>»: весь ключ и
#              есть кэш этого номера.
# Каждое место, куда Windows не пустила, записывается само по себе в
# $script:GdidUnreadable: «не нашли» там — не то же самое, что «нет».
# $script:GdidUnknown — подключи личностей без DeviceId: оставлены как есть.
$script:GdidUnknown = New-Object System.Collections.Generic.List[string]
function Get-GdidCopies {
    $found = New-Object System.Collections.Generic.List[object]
    $script:GdidUnreadable.Clear()
    if ($null -eq $script:GdidUnknown) { $script:GdidUnknown = New-Object System.Collections.Generic.List[string] }
    $script:GdidUnknown.Clear()
    $seenSystem = $false
    $me = ''
    try { $me = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value } catch { }
    $read = {
        param([string]$KeyPath, [string[]]$Want = @())
        $k = Read-GdidKey $KeyPath $Want
        if ($k.state -eq 'denied') { $script:GdidUnreadable.Add($KeyPath) }
        $k
    }
    foreach ($r in (Get-IdCrlRoots)) {
        $rk = & $read $r.path
        if ($rk.state -ne 'ok') { continue }
        # .DEFAULT и S-1-5-18 — один и тот же куст SYSTEM: считаем его один раз
        if ($r.who -eq 'system') { if ($seenSystem) { continue }; $seenSystem = $true }
        $ep = "$($r.path)\ExtendedProperties"
        $ek = & $read $ep @('LID')
        if ($ek.state -eq 'ok' -and "$($ek.values['LID'])") {
            $found.Add(@{ who = $r.who; place = 'lid'; puid = "$($ek.values['LID'])"; path = $ep; values = @('LID'); key = $false })
        }
        $pp = "$($r.path)\Immersive\production\Property"
        $pk = & $read $pp
        foreach ($vn in @($pk.valueNames)) {
            if ($vn -match $script:DevicePuidRegex) { $found.Add(@{ who = $r.who; place = 'property'; puid = $vn; path = $pp; values = @($vn); key = $false }) }
        }
        $tp = "$($r.path)\Immersive\production\Token"
        $tl = & $read $tp
        foreach ($tn in @($tl.subKeys)) {
            $tk = & $read "$tp\$tn" @('DeviceId')
            if ($tk.state -ne 'ok') { continue }
            $tv = @(@('DeviceId', 'DeviceTicket') | Where-Object { @($tk.valueNames) -contains $_ })
            if ($tv.Count -gt 0) { $found.Add(@{ who = $r.who; place = 'token'; puid = "$($tk.values['DeviceId'])"; path = "$tp\$tn"; values = $tv; key = $false }) }
        }
        $dp = "$($r.path)\DeviceIdentities\production"
        $dl = & $read $dp
        foreach ($sn in @($dl.subKeys)) {
            if ($sn -eq 'Logs') { continue }
            # Чья личность: в кусте пользователя — его; в системном — по SID
            # раздела. Раньше любая S-1-5-21-* шла как «своя», и копии другого
            # пользователя считались копиями того, кто смотрит.
            $idWho = $(if ($r.who -ne 'system') { $r.who } elseif ($sn -notmatch $script:GdidUserSidRx) { 'system' }
                       elseif ($sn -eq $me) { 'user' } else { 'other' })
            $cp = "$dp\$sn"
            $ck = & $read $cp @('ValidDeviceId')
            if ($ck.state -ne 'ok') { continue }
            foreach ($inm in @($ck.subKeys)) {
                $ik = & $read "$cp\$inm" @('DeviceId')
                if ($ik.state -ne 'ok') { continue }
                if (@($ik.valueNames) -notcontains 'DeviceId') { $script:GdidUnknown.Add("$cp\$inm"); continue }
                $found.Add(@{ who = $idWho; place = 'identity'; puid = "$($ik.values['DeviceId'])"; path = "$cp\$inm"; values = @(); key = $true
                              parent = $cp; name = $inm; children = @($ik.subKeys).Count
                              pointer = $(if ("$($ck.values['ValidDeviceId'])" -eq $inm) { $cp } else { '' }) })
            }
        }
    }
    $nk = & $read $script:IdCrlNegCache
    foreach ($nn in @($nk.subKeys)) {
        if ($nn -match '^(0018[0-9A-Fa-f]{12})_') {
            $found.Add(@{ who = 'system'; place = 'cache'; puid = $Matches[1]; path = "$($script:IdCrlNegCache)\$nn"; values = @(); key = $true
                          parent = $script:IdCrlNegCache; name = $nn; tree = $true })
        }
    }
    return $found.ToArray()
}

# Опись копий номера с ответом, можно ли ей верить. state: Found — копии есть;
# NotFound — копий нет и проверено всё; Unverified — копий не нашлось, но часть
# мест не прочиталась, профили других пользователей не проверялись или их
# список не прочитался. «Не нашли» там, куда не пустили, — не то же самое,
# что «нет». profiles — опись профилей (Get-UncheckedProfiles).
function Get-GdidScan {
    $copies = @(Get-GdidCopies)
    $prof = Get-UncheckedProfiles
    foreach ($pl in @($prof.places)) { $script:GdidUnreadable.Add("$pl") }
    $unchecked = [int]$prof.unloadedProfiles
    $unread = @($script:GdidUnreadable | Select-Object -Unique)
    $state = $(if ($copies.Count -gt 0) { 'Found' } elseif ($unread.Count -gt 0 -or $prof.unverified) { 'Unverified' } else { 'NotFound' })
    return @{ copies = $copies; unreadable = $unread; unchecked = $unchecked; profiles = $prof; state = $state
              unknown = @($script:GdidUnknown | Select-Object -Unique) }
}

# Кусты реестра людей, о которых речь: самого движка (HKCU) и того, кто сидит
# за компьютером, если пароль администратора ввёл он (его куст подключён).
function Get-GdidUserHiveRoots {
    $roots = New-Object System.Collections.Generic.List[object]
    $roots.Add(@{ sid = "$($script:UserSid)"; root = 'HKCU:' })
    $o = Get-OtherSessionUser
    if ($o -and $o.sid -and "$($o.sid)" -ne "$($script:UserSid)") { $roots.Add(@{ sid = "$($o.sid)"; root = "Registry::HKEY_USERS\$($o.sid)" }) }
    return $roots.ToArray()
}

# Есть ли у ключа подключи: $true, $false; не прочитался — $null
function Test-GdidKeyHasChildren {
    param([string]$Path)
    $k = $null
    try { $k = Open-RegKeyRead $Path; return ($null -ne $k -and $k.SubKeyCount -gt 0) }
    catch { return $null }
    finally { if ($null -ne $k) { $k.Close() } }
}

# Учётная запись человека: чем он входит в Windows и подключена ли учётная
# запись Microsoft только к приложениям. Ответ:
#   source       — MicrosoftAccount (вход в Windows через неё), Local,
#                  ActiveDirectory (домен), AzureAD (Entra ID), Unknown;
#   signInMsa    — вход в Windows через учётную запись Microsoft. Не
#                  удалось узнать — «да»: осторожная сторона, запрет выдачи
#                  тогда не ставится;
#   connectedMsa — в профиле есть учётная запись Microsoft (Магазин, Почта,
#                  OneDrive), $null — профиль не прочитался. У локальной
#                  учётной записи это ещё не вход через неё;
#   known        — источник определился точно (по SAM или по виду SID).
# Раньше локальная учётная запись, у которой Microsoft подключена только к
# Магазину, и учётная запись без модуля LocalAccounts судились одним правилом.
function Get-GdidAccountKind {
    param([string]$Sid, [string]$Root)
    $conn = Test-GdidKeyHasChildren "$Root\SOFTWARE\Microsoft\IdentityCRL\UserExtendedProperties"
    $o = @{ sid = $Sid; source = 'Unknown'; signInMsa = $true; connectedMsa = $conn; known = $false; error = '' }
    # SID S-1-12-1-… — учётная запись Entra ID: это не учётная запись Microsoft
    if ($Sid -like 'S-1-12-1-*') { $o.source = 'AzureAD'; $o.signInMsa = $false; $o.known = $true; return $o }
    try {
        $u = Get-LocalUser -SID $Sid -ErrorAction Stop
        $src = "$($u.PrincipalSource)"
        if ($src -in @('MicrosoftAccount', 'Local', 'ActiveDirectory', 'AzureAD')) {
            $o.source = $src; $o.known = $true; $o.signInMsa = ($src -eq 'MicrosoftAccount')
            return $o
        }
        $o.error = ("источник учётной записи не назван ({0})" -f $src)
    } catch { $o.error = "$($_.Exception.Message)" }
    # Не локальная учётная запись (домен) или модуля учётных записей нет —
    # судим по профилю: есть в нём учётная запись Microsoft (или профиль не
    # прочитался) — считаем, что вход через неё.
    $o.signInMsa = ($conn -ne $false)
    return $o
}

# Учётные записи тех, о ком речь (движок и тот, кто сидит за компьютером)
function Get-GdidAccounts {
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($h in @(Get-GdidUserHiveRoots)) {
        if (-not $h.sid) { continue }
        $out.Add((Get-GdidAccountKind "$($h.sid)" "$($h.root)"))
    }
    return $out.ToArray()
}

# Учётная запись с этим SID — вход в Windows через учётную запись Microsoft
# (см. Get-GdidAccountKind)
function Test-MsaAccount {
    param([string]$Sid, [string]$Root)
    return [bool](Get-GdidAccountKind $Sid $Root).signInMsa
}

# Входит ли в Windows через учётную запись Microsoft тот, кто сидит за
# компьютером, или учётная запись самого движка. Раньше спрашивалось о
# $env:USERNAME — об учётной записи движка: если пароль администратора ввёл
# обычный пользователь, проверялся администратор, и запрет выдачи мог встать
# человеку, который входит через учётную запись Microsoft, — и сломать ему её.
function Test-MsaLogon {
    foreach ($h in @(Get-GdidUserHiveRoots)) {
        if (-not $h.sid) { continue }
        if (Test-MsaAccount $h.sid $h.root) { return $true }
    }
    return $false
}

# Другие учётные записи Microsoft на этом компьютере (кроме своей и того, кто
# сидит за ним): запрет выдачи закрывает сервер для всех, и их вход в учётную
# запись Microsoft тоже перестанет работать. Список — для предупреждения.
# Список не прочитался — $script:GdidOtherMsaError: предупреждение тогда
# говорит, что проверить не удалось (раньше это молча было «других нет»).
$script:GdidOtherMsaError = ''
function Get-OtherMsaAccounts {
    $script:GdidOtherMsaError = ''
    $skip = @(@(Get-GdidUserHiveRoots) | ForEach-Object { "$($_.sid)" })
    try { return @(Get-LocalUser -ErrorAction Stop | Where-Object { "$($_.PrincipalSource)" -eq 'MicrosoftAccount' -and $skip -notcontains "$($_.SID)" } | ForEach-Object { "$($_.Name)" }) }
    catch { $script:GdidOtherMsaError = "$($_.Exception.Message)"; return @() }
}

# Компьютер организации: там номер устройства связан с её учётной записью,
# и трогать его — сломать вход на работе. Ответ (считается один раз за запуск):
#   kind — domain (в домене), entra (Entra ID), hybrid (домен и Entra ID
#          сразу), mdm (под управлением организации), workAccount (добавлена
#          рабочая или учебная учётная запись — устройство при этом
#          организацией не управляется), unknown (проверить не удалось), '';
#   managed — устройством управляет организация (или это неизвестно);
#   workAccount — рабочая учётная запись подключена (отдельно от управления);
#   reason — то же словами, для окна и журнала работы.
# Встроенные «поставщики» Local, Deploy и Cloud Authority есть на любом
# домашнем компьютере — их не считаем. Не удалось проверить — отказ, а не
# «домашний»: раньше ошибка WMI или чтения реестра глоталась, и компьютер
# организации с неисправным WMI считался домашним.
# Рабочая учётная запись без управления тоже отказ (осторожная сторона: её
# вход привязан к регистрации устройства), но называется своим словом.
$script:GdidManagedCache = $null
$script:GdidManagementCache = $null
function Get-GdidManagement {
    if ($null -ne $script:GdidManagementCache) { return $script:GdidManagementCache }
    $script:GdidManagementCache = Get-GdidManagementNow
    return $script:GdidManagementCache
}

function Get-ManagedReason {
    if ($null -ne $script:GdidManagedCache) { return $script:GdidManagedCache }
    $script:GdidManagedCache = Get-ManagedReasonNow
    return $script:GdidManagedCache
}

function Get-ManagedReasonNow {
    $script:GdidManagementCache = Get-GdidManagementNow
    return "$($script:GdidManagementCache.reason)"
}

function Get-GdidManagementNow {
    $unknown = 'не удалось проверить, принадлежит ли компьютер организации'
    $o = @{ kind = ''; managed = $false; workAccount = $false; reason = ''; domain = $null; entra = $null; mdm = $null; errors = (New-Object System.Collections.Generic.List[string]) }
    $fail = { param([string]$Why) $o.errors.Add($Why); $o.kind = 'unknown'; $o.managed = $true; $o.reason = $unknown; $o }
    try { $o.domain = [bool](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain }
    catch { return (& $fail ("WMI: {0}" -f $_.Exception.Message)) }
    $aad = Test-GdidKeyHasChildren 'HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo'
    if ($null -eq $aad) { return (& $fail 'CloudDomainJoin\JoinInfo не читается') }
    $o.entra = [bool]$aad
    if ($o.domain -and $o.entra) { $o.kind = 'hybrid'; $o.managed = $true; $o.reason = 'компьютер в домене организации и подключён к её Entra ID'; return $o }
    if ($o.domain) { $o.kind = 'domain'; $o.managed = $true; $o.reason = 'компьютер в домене организации'; return $o }
    if ($o.entra) { $o.kind = 'entra'; $o.managed = $true; $o.reason = 'компьютер подключён к Entra ID организации'; return $o }
    # Управление организацией (MDM): запись в Enrollments от внешнего
    # поставщика в состоянии «зарегистрировано» или учётная запись OMA-DM
    $en = $null
    try {
        $en = Open-RegKeyRead 'HKLM:\SOFTWARE\Microsoft\Enrollments'
        if ($null -ne $en) {
            foreach ($sub in @($en.GetSubKeyNames())) {
                $ek = $en.OpenSubKey($sub, $false)
                if ($null -eq $ek) { continue }
                try {
                    $prov = "$($ek.GetValue('ProviderID'))"
                    if ($prov -and $prov -notin @('Local Authority', 'Deploy Authority', 'Cloud Authority') -and "$($ek.GetValue('EnrollmentState'))" -eq '1') { $o.mdm = $true }
                } finally { $ek.Close() }
            }
        }
    } catch { return (& $fail ("Enrollments: {0}" -f $_.Exception.Message)) }
    finally { if ($null -ne $en) { $en.Close() } }
    if (-not $o.mdm) {
        $om = Test-GdidKeyHasChildren 'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts'
        if ($null -eq $om) { return (& $fail 'OMADM\Accounts не читается') }
        $o.mdm = [bool]$om
    }
    if ($o.mdm) { $o.kind = 'mdm'; $o.managed = $true; $o.reason = 'компьютер под управлением организации (MDM)'; return $o }
    # Рабочая или учебная учётная запись — у того, кто сидит за компьютером,
    # и у самого движка (раньше смотрелся только HKCU движка)
    foreach ($h in @(Get-GdidUserHiveRoots)) {
        $wp = Test-GdidKeyHasChildren "$($h.root)\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin\JoinInfo"
        if ($null -eq $wp) { return (& $fail 'WorkplaceJoin\JoinInfo не читается') }
        if ($wp) { $o.workAccount = $true }
    }
    if ($o.workAccount) { $o.kind = 'workAccount'; $o.reason = 'в Windows добавлена рабочая или учебная учётная запись (компьютером организация не управляет)' }
    return $o
}


# 'msa' — вход в Windows через учётную запись Microsoft, 'managed' — компьютер
# организации, '' — запрет выдачи номера доступен. Считается один раз за запуск.
function Get-GdidLockRefusal {
    if ($null -ne $script:GdidRefusal) { return $script:GdidRefusal }
    $script:GdidRefusal = ''
    if (Test-MsaLogon) { $script:GdidRefusal = 'msa' }
    elseif (Get-ManagedReason) { $script:GdidRefusal = 'managed' }
    return $script:GdidRefusal
}

# Самая ранняя запись журнала отката о wlidsvc — её «как было» оставило
# прерванное стирание (процесс оборвался, служба осталась отключённой).
function Get-GdidWlidJournalEntry {
    $jf = Read-JournalFile -ReadOnly
    if (-not $jf.trusted) { return $null }
    foreach ($it in @($jf.items)) {
        $f = ConvertTo-Fields $it
        if ((Get-JournalKey $f) -eq 'svc|wlidsvc' -and -not (Test-JournalEntryShape $it)) { return $f }
    }
    return $null
}

# wlidsvc на время стирания отключается: её поднимает любой запрос Магазина.
# «Как было» сначала ложится в журнал отката (как у всех изменений). Раньше
# тип запуска помнил только сам движок: оборвись он посреди стирания — служба
# учётных записей Microsoft осталась бы отключённой навсегда (вход в неё,
# Магазин, Xbox), и ни возврат, ни откат о ней не знали бы.
# Ответ: ok — можно стирать; changed — потом вернуть по entry; why — почему нет.
function Disable-GdidWlid {
    $svc = Get-Service -Name wlidsvc -ErrorAction SilentlyContinue
    if (-not $svc) { return @{ ok = $true; changed = $false; entry = $null; why = 'службы учётных записей Microsoft (wlidsvc) на этой системе нет' } }
    $prev = Get-GdidWlidJournalEntry
    $entry = $prev
    if (-not $prev) {
        if ("$($svc.StartType)" -eq 'Disabled') { return @{ ok = $true; changed = $false; entry = $null; why = '' } }
        $entry = Get-SvcJournalState 'wlidsvc' $svc
        # Тип запуска не прочитался — вернуть его потом было бы нечем: тогда
        # не стираем вовсе. Раньше стирание шло дальше с включённой wlidsvc,
        # и она могла завести номер заново посреди стирания.
        if ("$($entry.old)" -notmatch '^[0-4]$') { return @{ ok = $false; changed = $false; entry = $null; why = 'тип запуска wlidsvc не прочитался -- вернуть его потом было бы нечем' } }
        if (-not (Write-AheadEntry $entry)) { return @{ ok = $false; changed = $false; entry = $null; why = 'журнал отката не пишется' } }
    }
    try { Set-Service -Name wlidsvc -StartupType Disabled -ErrorAction Stop }
    catch {
        if (-not $prev) { Undo-AheadEntry $entry; return @{ ok = $true; changed = $false; entry = $null; why = ("wlidsvc не отключилась на время стирания: {0}" -f $_.Exception.Message) } }
    }
    return @{ ok = $true; changed = $true; entry = $entry; why = '' }
}

# Тип запуска wlidsvc — по записи журнала, и запись после этого убирается
function Restore-GdidWlid {
    param($Wlid)
    if ($null -eq $Wlid -or -not $Wlid.changed -or $null -eq $Wlid.entry) { return @{ ok = $true; why = '' } }
    $e = @{ kind = 'svc'; name = 'wlidsvc'; old = "$($Wlid.entry.old)"; delayed = "$($Wlid.entry.delayed)"; running = $false }
    $r = Restore-JournalEntry $e
    if (-not $r.ok) { return @{ ok = $false; why = "$($r.error)" } }
    try { Remove-JournalKey 'svc|wlidsvc' }
    catch { Write-Log ("   [i] тип запуска wlidsvc возвращён, а запись о нём в журнале отката осталась: {0}" -f $_.Exception.Message) }
    return @{ ok = $true; why = '' }
}

# Вернуть службы как были — и проверить, что вернулись. Раньше ошибка запуска
# глоталась: служба, работавшая до стирания, могла остаться стоять, а
# стирание всё равно считалось успешным.
#   $Running  — службы, которые остановило само стирание и которые работали
#               до него (по снимку): запускаются только они. Те, что стояли
#               до стирания, не запускаются;
#   $Wlid     — ответ Disable-GdidWlid: тип запуска wlidsvc — по журналу;
#   $Snapshot — снимок до стирания (Get-GdidServiceSnapshot): с ним
#               сверяется итог. «Start-Service отработал» — ещё не «работает».
# Ответ: notBack — что не вернулось; states — каждая служба до и после.
function Restore-GdidServices {
    param([string[]]$Running, $Wlid, $Snapshot)
    $bad = New-Object System.Collections.Generic.List[string]
    $states = New-Object System.Collections.Generic.List[object]
    $w = Restore-GdidWlid $Wlid
    if (-not $w.ok) { $bad.Add('wlidsvc (тип запуска)'); Write-Log ("   [!] тип запуска wlidsvc не вернулся: {0}" -f $w.why) }
    foreach ($n in @($Running)) {
        if (-not $n) { continue }
        $why = ''
        try {
            Start-Service -Name $n -ErrorAction Stop -WarningAction SilentlyContinue
            (Get-Service -Name $n -ErrorAction Stop).WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
        } catch { $why = "$($_.Exception.Message)" }
        # «Start-Service отработал» — ещё не «работает»: сверяем сами
        $v = Get-SvcScmView $n
        # копия CDPUserSvc исчезла вместе с выходом пользователя — запускать нечего
        if ($v.ok -and -not $v.found -and $n -like 'CDPUserSvc_*') { continue }
        if (-not ($v.ok -and $v.found -and "$($v.status)" -eq 'Running')) {
            $bad.Add($n)
            if ($why) { Write-Log ("   [!] служба {0} не запустилась: {1}" -f $n, $why) }
        }
    }
    if ($null -ne $Snapshot) {
        foreach ($e in @($Snapshot.services)) {
            $after = Get-GdidSvcEntry "$($e.name)"
            # тип запуска wlidsvc, оставленной прерванным прежде стиранием, —
            # тот, что в журнале, а не «отключена» из снимка
            $wantStart = [int]$e.start
            if ("$($e.name)" -eq 'wlidsvc' -and $Wlid -and $Wlid.changed -and $Wlid.entry -and "$($Wlid.entry.old)" -match '^[0-4]$') { $wantStart = [int]"$($Wlid.entry.old)" }
            # копия CDPUserSvc пропала — пользователь вышел из Windows, и
            # Windows убрала её сама: это не «не вернулась»
            $gone = ([bool]$e.instance -and "$($after.state)" -eq 'Missing')
            $startOk = ("$($e.state)" -eq 'Missing' -or $gone -or [int]$after.start -eq $wantStart)
            $runOk = ((-not $e.running) -or $gone -or [bool]$after.running -or @($Running) -notcontains "$($e.name)")
            $states.Add(@{ name = "$($e.name)"; before = @{ start = [int]$e.start; running = [bool]$e.running; status = "$($e.status)" }
                           after = @{ start = [int]$after.start; running = [bool]$after.running; status = "$($after.status)" }
                           stopped = (@($Running) -contains "$($e.name)"); restored = ($startOk -and $runOk) })
            if (-not $startOk -and -not ("$($e.name)" -eq 'wlidsvc' -and $bad -contains 'wlidsvc (тип запуска)')) {
                $bad.Add(("{0} (тип запуска: был {1}, сейчас {2})" -f $e.name, (Get-StartName "$wantStart"), (Get-StartName "$($after.start)")))
            }
        }
    }
    return @{ notBack = $bad.ToArray(); states = $states.ToArray() }
}

function Stop-ServiceWait {
    param([string]$Name)
    # «Службы нет» — только когда диспетчер служб так и ответил. Раньше любая
    # ошибка Get-Service означала «остановлена», и стирание шло при работающей
    # службе, которая держала номер.
    $svc = $null
    try { $svc = Get-Service -Name $Name -ErrorAction Stop }
    catch { return ("$($_.FullyQualifiedErrorId)" -like 'NoServiceFoundForGivenName*') }
    if (-not $svc -or $svc.Status -eq 'Stopped') { return $true }
    for ($i = 1; $i -le 3; $i++) {
        # -WarningAction: иначе в журнал работы сыпалось «WARNING: Waiting for
        # service ... to stop» по-английски — ждём остановку мы и так сами
        try { Stop-Service -Name $Name -Force -ErrorAction Stop -WarningAction SilentlyContinue; $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(10)); return $true }
        catch { Start-Sleep -Milliseconds (500 * $i) }
    }
    return $false
}

# Короткая задача планировщика: команда от имени пользователя без повышения
# или от имени SYSTEM. Учётные данные устройства лежат в хранилище каждого из
# них, а у повышенного сеанса своё пространство — отсюда их не видно.
# Короткая задача планировщика: выполнить команду от имени системы или
# пользователя и убрать задачу. Имя у каждого запуска своё, случайное: задачу
# с заранее известным именем мог бы завести кто-то другой, и программа
# запустила бы — а потом и удалила — чужую. После регистрации задача
# сверяется (та ли команда и от чьего имени) и без этого не запускается.
function Test-OneShotTaskMine {
    # -UserSid — чья это задача, если не от имени самого движка (вошедший
    # пользователь, см. Invoke-AsUser)
    param([string]$TaskName, [string]$Exe, [string]$Arguments, [bool]$AsSystem, [string]$UserSid = '')
    $t = Get-ScheduledTask -TaskPath '\' -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t) { return $false }
    $acts = @($t.Actions)
    # пробелы по краям планировщик вправе подрезать — они ничего не меняют
    if ($acts.Count -ne 1 -or "$($acts[0].Execute)".Trim() -ne $Exe.Trim() -or "$($acts[0].Arguments)".Trim() -ne $Arguments.Trim()) { return $false }
    # Сверяем по SID: имя учётной записи системы Windows переводит
    # («СИСТЕМА» на русской), и по имени своя задача выглядела чужой.
    $sid = ConvertTo-SidValue "$($t.Principal.UserId)"
    if ($AsSystem) { return ($sid -eq 'S-1-5-18') }
    $want = $(if ($UserSid) { $UserSid } else { ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value })
    return ($sid -ne '' -and $sid -eq $want)
}

function ConvertTo-SidValue {
    param([string]$Name)
    if (-not $Name) { return '' }
    if ($Name -match '^S-1-[\d-]+$') { return $Name }
    try { return (New-Object Security.Principal.NTAccount($Name)).Translate([Security.Principal.SecurityIdentifier]).Value } catch { return '' }
}

function Invoke-OneShotTask {
    # -Minutes — сколько задаче разрешено работать; ждём её столько же и ещё
    # немного. Раньше ожидание было 30 секунд при разрешённых двух минутах.
    # -Execute/-Arguments — программа запускается напрямую, без cmd.exe. Через
    # cmd (-CmdLine) идут только постоянные строки программы, которым нужны
    # его «&&», «|», «>nul»; в них не пропускаются % (cmd раскрыл бы его как
    # переменную) и переводы строк (они разорвали бы команду).
    # -StartSeconds — сколько ждать, что задача вообще начнётся: задача от имени
    # пользователя, который сейчас не вошёл в Windows, не начнётся никогда, и
    # ждать её всё отведённое время незачем
    # -Account/-AccountSid — не от имени самого движка, а от имени другого
    # пользователя (вошедшего в Windows, когда движок работает от имени
    # администратора, чей пароль он ввёл)
    param([string]$TaskName, [string]$CmdLine, [switch]$AsSystem, [int]$Minutes = 2, [string]$Execute = '', [string]$Arguments = '',
          [int]$StartSeconds = 0, [string]$Account = '', [string]$AccountSid = '')
    $TaskName = '{0} {1}' -f $TaskName, [guid]::NewGuid().ToString('N').Substring(0, 12)
    if ($Execute) { $exe = $Execute; $arg = $Arguments }
    else {
        if ($CmdLine -match '[%\r\n]') { Write-Log '   [!] команда для короткой задачи содержит недопустимые знаки -- не запускается'; return $false }
        $exe = "$env:SystemRoot\System32\cmd.exe"; $arg = '/d /c ' + $CmdLine
    }
    $registered = $false
    try {
        $act = New-ScheduledTaskAction -Execute $exe -Argument $arg
        # учётная запись — из маркера самого процесса, а не из USERNAME
        $who = $(if ($AsSystem) { New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest }
                 else { New-ScheduledTaskPrincipal -UserId $(if ($Account) { $Account } else { $script:RunAccount }) -LogonType Interactive -RunLevel Limited })
        $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes $Minutes)
        # имя новое — задачу с ним никто завести не мог, поэтому без -Force
        Register-ScheduledTask -TaskPath '\' -TaskName $TaskName -Action $act -Principal $who -Settings $set -ErrorAction Stop | Out-Null
        $registered = $true
        if (-not (Test-OneShotTaskMine $TaskName $exe $arg ([bool]$AsSystem) $AccountSid)) { return $false }
        Start-ScheduledTask -TaskPath '\' -TaskName $TaskName -ErrorAction Stop
        # 267011 — ещё не запускалась, 267009 — выполняется
        $until = (Get-Date).AddSeconds(60 * $Minutes + 15)
        $startBy = $(if ($StartSeconds -gt 0) { (Get-Date).AddSeconds($StartSeconds) } else { $until })
        do {
            Start-Sleep -Milliseconds 400
            $res = (Get-ScheduledTaskInfo -TaskPath '\' -TaskName $TaskName -ErrorAction SilentlyContinue).LastTaskResult
            if ($res -eq 267011 -and (Get-Date) -ge $startBy) {
                Write-Log '   [!] короткая задача не начала работу: пользователь, от имени которого она идёт, сейчас не вошёл в Windows'
                return $false
            }
        } while (($res -eq 267009 -or $res -eq 267011) -and (Get-Date) -lt $until)
        # Успех — только если команда задачи завершилась с кодом 0. Раньше «да»
        # возвращалось, едва задача запустилась, и сбой команды выглядел успехом.
        return ($res -eq 0)
    } catch {
        Write-Log ("   [!] короткая задача не отработала: {0}" -f $_.Exception.Message)
        return $false
    }
    finally {
        # имя случайное и заведено нами — удаляем только его. Не дождались —
        # задачу сначала останавливаем: иначе она доработала бы уже без нас и,
        # например, дописала бы итог, который никто не прочтёт.
        if ($registered) {
            if ((Get-ScheduledTaskInfo -TaskPath '\' -TaskName $TaskName -ErrorAction SilentlyContinue).LastTaskResult -eq 267009) {
                Stop-ScheduledTask -TaskPath '\' -TaskName $TaskName -ErrorAction SilentlyContinue
            }
            Unregister-ScheduledTask -TaskPath '\' -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
            # не удалилась — так и сказано: задача от имени системы не должна
            # оставаться в планировщике незамеченной
            if (Get-ScheduledTask -TaskPath '\' -TaskName $TaskName -ErrorAction SilentlyContinue) {
                Write-Log ("   [!] короткая задача «{0}» не удалилась из планировщика -- удалите её вручную" -f $TaskName)
                $script:Failures++
            }
        }
    }
}

# --------------------------------------------------------------------------- #
#  Действия в папках самого пользователя — от его имени и без повышения.
#  Профиль (TEMP, AppData) открыт на запись любой программе этого
#  пользователя, а движок работает с правами администратора. Удаление или
#  запись там по пути с правами администратора нельзя привязать к тому, что
#  проверено: путь можно подменить между проверкой и действием. Поэтому
#  такие действия делает короткая задача от имени того же пользователя с
#  обычными правами — она может ровно то, что он может и сам.
#  Сценарий — постоянный текст движка; он и его данные кладутся в защищённую
#  папку (читать их пользователь может, менять — нет). Итог задача пишет в
#  свою временную папку, и движок берёт из него только числа и строки.
#  Ответ: ok — задача отработала и оставила итог; result — разобранный итог.
# --------------------------------------------------------------------------- #
function Invoke-AsUser {
    param([string]$Name, [string]$Script, $Data, [int]$Minutes = 5)
    if (-not (Test-Admin)) { return @{ ok = $false; result = $null; why = 'нужны права администратора' } }
    if (-not (Assert-SafeRoot)) { return @{ ok = $false; result = $null; why = 'папка ProgramData\Win11Privacy не защищена' } }
    # Чьи папки: того, кто сидит за компьютером. Если пароль администратора
    # ввёл обычный пользователь, это он, а не учётная запись движка.
    $account = $script:RunAccount; $accountSid = $script:UserSid; $profileDir = $script:UserProfileDir
    $other = Get-OtherSessionUser
    if ($other) {
        if (-not $other.name -or -not $other.profile) { return @{ ok = $false; result = $null; why = 'профиль вошедшего в Windows пользователя определить не удалось' } }
        $account = $other.name; $accountSid = $other.sid; $profileDir = $other.profile
    }
    if (-not $profileDir -or -not $account) { return @{ ok = $false; result = $null; why = 'папку профиля пользователя Windows не назвала' } }
    $id = [guid]::NewGuid().ToString('N')
    $sf = Join-Path $script:SafeRoot ('asuser-' + $id + '.ps1')
    $inf = Join-Path $script:SafeRoot ('asuser-' + $id + '.json')
    $rf = Join-Path $profileDir ('AppData\Local\Temp\w11p-asuser-' + $id + '.json')
    try {
        Set-Content -LiteralPath $sf -Value $Script -Encoding UTF8 -ErrorAction Stop
        Set-Content -LiteralPath $inf -Value (ConvertTo-Json -InputObject $Data -Depth 6 -Compress) -Encoding UTF8 -ErrorAction Stop
        $argLine = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -InputFile "{1}" -ResultFile "{2}"' -f $sf, $inf, $rf
        $null = Invoke-OneShotTask ('Win11Privacy ' + $Name) -Execute $script:PsExe -Arguments $argLine -Minutes $Minutes -StartSeconds 30 -Account $account -AccountSid $accountSid
        if (-not (Test-Path -LiteralPath $rf -PathType Leaf)) { return @{ ok = $false; result = $null; why = 'задача от имени пользователя не оставила итога' } }
        if ((Get-Item -LiteralPath $rf -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            return @{ ok = $false; result = $null; why = 'на месте итога задачи лежит ссылка' }
        }
        # Итог лежит в папке пользователя. Его должна была написать наша задача
        # от имени этого же пользователя: сверяем владельца. Чужой владелец —
        # файл подменили, итогу верить нельзя (из него всё равно берутся только
        # числа и короткие строки, но лишним это не будет).
        $rfOwner = ''
        try { $rfOwner = (Get-Acl -LiteralPath $rf -ErrorAction Stop).GetOwner([Security.Principal.SecurityIdentifier]).Value } catch { }
        if ($accountSid -and $rfOwner -and $rfOwner -ne $accountSid -and $script:TrustedSids -notcontains $rfOwner) {
            return @{ ok = $false; result = $null; why = 'итог задачи принадлежит не тому пользователю -- подмена' }
        }
        $txt = Read-TextShared $rf
        $res = $null
        try { $res = $txt | ConvertFrom-Json -ErrorAction Stop } catch { }
        if ($null -eq $res) { return @{ ok = $false; result = $null; why = 'итог задачи от имени пользователя не читается' } }
        return @{ ok = $true; result = $res; why = '' }
    } catch {
        return @{ ok = $false; result = $null; why = $_.Exception.Message }
    } finally {
        foreach ($f in @($sf, $inf)) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
        # итог лежит в папке пользователя: удаляется сама запись (File.Delete
        # не идёт по ссылке)
        try { if (Test-Path -LiteralPath $rf) { [IO.File]::Delete($rf) } } catch { }
    }
}

# Часть задач Windows закрыла от администратора: читать их можно, менять —
# только SYSTEM (UsageAndQualityInsights, модели Click to Do). Раньше такая
# задача оставалась включённой с пометкой «не найдена». Теперь, если
# администратору отказано, то же делает короткая задача от имени SYSTEM.
# Ответ: ok, system (сделано от SYSTEM), missing (задачи нет), fail.
function Set-TaskEnabled {
    param([string]$Full, [bool]$Enabled)
    $pp = Split-TaskPath $Full
    $t = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction SilentlyContinue
    if (-not $t) { return 'missing' }
    # отказ администратору — не ошибка: дальше то же сделает задача от SYSTEM
    $denied = $false
    try {
        if ($Enabled) { Enable-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop | Out-Null }
        else { Disable-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop | Out-Null }
    } catch { $denied = $true }
    if (-not $denied) {
        # «команда прошла» — ещё не «задача такая»: состояние сверяется
        $t = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction SilentlyContinue
        if ($t -and ((Test-TaskDisabled $t) -ne $Enabled)) { return 'ok' }
    }
    $flag = $(if ($Enabled) { '/enable' } else { '/disable' })
    # schtasks запускается напрямую, а не через cmd; кавычка в имени задачи
    # разорвала бы аргумент — такого имени у задачи Windows быть не может
    if ($Full -match '["\r\n]') { return 'fail' }
    $null = Invoke-OneShotTask -TaskName 'Win11Privacy Task' -Execute "$env:SystemRoot\System32\schtasks.exe" -Arguments ('/change /tn "{0}" {1}' -f $Full, $flag) -AsSystem
    $t = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction SilentlyContinue
    if ($t -and ((Test-TaskDisabled $t) -ne $Enabled)) { return 'system' }
    return 'fail'
}

# Часть команды: код 1, если хоть одна из записей ещё в хранилище, иначе 0
function Get-CredCheckCmd {
    param([string[]]$Targets)
    $finds = @($Targets | ForEach-Object { '/c:"' + ($_ -replace '^.*target=', '') + '"' }) -join ' '
    return '(cmdkey /list | findstr /i ' + $finds + ' >nul && exit 1 || exit 0)'
}

# Учётные данные «личности» устройства — у кого их чистить задачей от его
# имени: у того, кто сидит за компьютером (раньше — всегда у учётной записи
# самого движка: если пароль администратора ввёл обычный пользователь, его
# учётные данные устройства оставались на месте), и у других пользователей,
# которые сейчас в Windows (их кусты подключены). Хранилище самого движка
# чистит его собственный вызов cmdkey (см. Clear-GdidUserCreds).
# session = $true — тот, кто сидит за компьютером.
function Get-GdidCredUsers {
    $out = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $o = Get-OtherSessionUser
    if ($o) { $out.Add(@{ name = "$($o.name)"; sid = "$($o.sid)"; session = $true }); $seen["$($o.sid)"] = $true }
    else { $out.Add(@{ name = "$($script:RunAccount)"; sid = "$($script:UserSid)"; session = $true }) }
    $seen["$($script:UserSid)"] = $true
    $names = @()
    try { $names = @(Get-GdidHiveNames) } catch { }
    foreach ($sid in $names) {
        if ($sid -notmatch '^S-1-5-21-[\d-]+$' -or $seen.ContainsKey($sid)) { continue }
        $seen[$sid] = $true
        $nm = ''
        try { $nm = (New-Object Security.Principal.SecurityIdentifier($sid)).Translate([Security.Principal.NTAccount]).Value } catch { }
        $out.Add(@{ name = $nm; sid = $sid; session = $false })
    }
    return $out.ToArray()
}

# Шаг «учётные данные у пользователей». state: Clean, Partial, Failed.
function Clear-GdidUserCreds {
    $fails = 0; $done = 0
    # Код cmdkey сам по себе ничего не говорит: «такой записи нет» — тоже
    # ошибка. Поэтому в конце команда проверяет, что записей действительно не
    # осталось, и только тогда завершается с кодом 0.
    $userCmd = (@($script:GdidCredUser | ForEach-Object { 'cmdkey /delete:' + $_ + ' >nul 2>&1' }) -join ' & ') + ' & ' + (Get-CredCheckCmd $script:GdidCredUser)
    # хранилище учётной записи самого движка — его собственным вызовом
    foreach ($t in $script:GdidCredUser) { $null = & cmdkey.exe "/delete:$t" 2>&1 }
    if (Get-OtherSessionUser) {
        # движок — не тот, кто сидит за компьютером: его хранилище задача ниже
        # не проверит, поэтому сверка здесь же
        $targets = @($script:GdidCredUser | ForEach-Object { $_ -replace '^.*target=', '' })
        $left = @(@(& cmdkey.exe /list 2>&1) | ForEach-Object { "$_" } | Where-Object {
                      $line = $_; @($targets | Where-Object { $line.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0 })
        if ($left.Count -gt 0) { Write-Log ("   [!] учётные данные устройства у {0} убрать не удалось" -f $script:RunAccount); $fails++ }
    }
    foreach ($u in @(Get-GdidCredUsers)) {
        if (-not $u.name) {
            Write-Log ("   [!] учётные данные устройства у пользователя {0} не проверены: имя его учётной записи не определилось" -f $u.sid)
            $fails++; continue
        }
        $ok = Invoke-OneShotTask 'Win11Privacy GDID user' $userCmd -Account $u.name -AccountSid $u.sid -StartSeconds 30
        if ($u.session) {
            if ($ok) { Write-Log '   [+] учётные данные устройства у пользователя убраны'; $done++ }
            else { Write-Log '   [!] учётные данные устройства у пользователя убрать не удалось'; $fails++ }
        } elseif ($ok) { Write-Log ("   [+] учётные данные устройства у пользователя {0} убраны" -f $u.name); $done++ }
        else { Write-Log ("   [!] учётные данные устройства у пользователя {0} убрать не удалось -- задача от его имени идёт, только пока он в Windows" -f $u.name); $fails++ }
    }
    return @{ state = $(if ($fails -eq 0) { 'Clean' } elseif ($done -gt 0) { 'Partial' } else { 'Failed' }); fails = $fails; done = $done }
}

# Шаг «реестр»: удаляется ровно то, что нашла опись (Get-GdidCopies), —
# каждое значение и каждый ключ по отдельности, и каждое удаление сверяется.
# Ветки целиком больше не удаляются: раньше уходил весь
# DeviceIdentities\production вместе с Logs и чужими значениями.
# Ответы: removed (было и убрано — проверено), absent (уже не было), denied
# (Windows не дала, или после удаления запись осталась), kept (личность с
# подключами, которых программа не знает: оставлена целой). Места, которые
# опись не прочитала, — unreadable: о них «убрано» сказать нельзя.
# state: Clean (что было — убрано), NotFound (ничего не было), Partial,
# AccessDenied (не убрано ничего, Windows не дала), Unverified (не убрано
# ничего не из-за отказа, но часть мест не прочиталась).
function Remove-GdidRegistryCopies {
    $st = @{ removed = 0; absent = 0; denied = 0; kept = 0; records = 0; unreadable = 0
             deniedAt = (New-Object System.Collections.Generic.List[string]); keptAt = (New-Object System.Collections.Generic.List[string]) }
    $note = { param($res, $where) $st[$res]++; if ($res -eq 'denied') { $st.deniedAt.Add($where) } elseif ($res -eq 'kept') { $st.keptAt.Add($where) } }
    $recs = @(Get-GdidCopies)
    $st.unreadable = @($script:GdidUnreadable | Select-Object -Unique).Count
    foreach ($rec in $recs) {
        $st.records++
        if ($rec.key) {
            $res = Remove-GdidRegKey "$($rec.parent)" "$($rec.name)" -Tree:([bool]$rec.tree)
            & $note $res "$($rec.path)"
            # указатель раздела на эту личность (ValidDeviceId) — её же
            # запись: убирается, только если указывает ровно на неё
            if ($res -eq 'removed' -and "$($rec.pointer)") {
                $pv = Read-GdidKey "$($rec.pointer)" @('ValidDeviceId')
                if ($pv.state -eq 'ok' -and "$($pv.values['ValidDeviceId'])" -eq "$($rec.name)") {
                    & $note (Remove-GdidRegValue "$($rec.pointer)" 'ValidDeviceId') "$($rec.pointer)\ValidDeviceId"
                } elseif ($pv.state -eq 'denied') { & $note 'denied' "$($rec.pointer)\ValidDeviceId" }
            }
        } else {
            foreach ($vn in @($rec.values)) { & $note (Remove-GdidRegValue "$($rec.path)" "$vn") ("{0}\{1}" -f $rec.path, $vn) }
        }
    }
    Write-Log ("   [+] записи номера в реестре: убрано {0}, не было {1}" -f $st.removed, $st.absent)
    if ($st.denied -gt 0) {
        Write-Log ("   [!] Windows не дала убрать: {0}" -f $st.denied)
        foreach ($w in @($st.deniedAt | Select-Object -Unique -First 5)) { Write-Log ("       {0}" -f ($w -replace '^Microsoft\.PowerShell\.Core\\Registry::', '')) }
    }
    if ($st.kept -gt 0) {
        Write-Log ("   [!] личности устройства с незнакомым содержимым оставлены как есть: {0}" -f $st.kept)
        foreach ($w in @($st.keptAt | Select-Object -Unique -First 3)) { Write-Log ("       {0}" -f ($w -replace '^Registry::', '')) }
    }
    $bad = $st.denied + $st.kept
    $st['state'] = $(if ($bad -eq 0 -and $st.unreadable -eq 0) { if ($st.removed -gt 0) { 'Clean' } else { 'NotFound' } }
                     elseif ($st.removed -gt 0) { 'Partial' } elseif ($st.denied -gt 0) { 'AccessDenied' } elseif ($st.kept -gt 0) { 'Partial' } else { 'Unverified' })
    return $st
}

# Шаг «кэш платформы подключённых устройств»: в нём регистрация в каталоге.
# Чистка удаляет «что сможет» и называет освобождённый объём — это ещё не
# значит, что кэш пуст, поэтому после неё проверяется, что в нём осталось.
# Папка — того, кто сидит за компьютером: чистит её задача от его имени
# (Clear-Folder), и проверяется она же. Раньше проверялась папка учётной
# записи самого движка: при повышении под другой учётной записью проверка
# смотрела не туда. others — сколько других вошедших пользователей: их кэш
# не чистится, и «стёрто отовсюду» тогда сказать нельзя.
# state: Clean, NotFound, Partial (файлы остались), Unverified (не проверить).
#
# Проверка — своим обходом (Get-GdidDirLeft): по ссылкам (junction,
# символическим) он не ходит, а сама ссылка внутри кэша считается тем, что
# осталось. Раньше проверка (Get-ChildItem -Recurse -File) ссылок не видела
# вовсе, папку без доступа считала пустой, а «папки нет» решала Test-Path —
# и при отказе в доступе тоже говорила «нет».
function Get-GdidDirLeft {
    param([string]$Dir, [int]$MaxDepth = 32)
    $out = @{ files = 0; links = 0; errors = 0; samples = (New-Object System.Collections.Generic.List[string]); errorAt = (New-Object System.Collections.Generic.List[string]) }
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push(@($Dir, 0))
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        $d = [string]$cur[0]; $depth = [int]$cur[1]
        $items = $null
        try { $items = ([IO.DirectoryInfo]$d).GetFileSystemInfos() }
        catch { $out.errors++; if ($out.errorAt.Count -lt 3) { $out.errorAt.Add(("{0}: {1}" -f $d, $_.Exception.Message)) }; continue }
        foreach ($it in @($items)) {
            if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $out.links++
                if ($out.samples.Count -lt 3) { $out.samples.Add($it.FullName) }
                continue
            }
            if ($it -is [IO.DirectoryInfo]) {
                if ($depth -ge $MaxDepth) { $out.errors++; if ($out.errorAt.Count -lt 3) { $out.errorAt.Add(("{0}: слишком глубоко" -f $it.FullName)) }; continue }
                $stack.Push(@($it.FullName, ($depth + 1)))
                continue
            }
            $out.files++
            if ($out.samples.Count -lt 3) { $out.samples.Add($it.FullName) }
        }
    }
    return $out
}

function Clear-GdidCdpCache {
    $dir = Convert-ToSessionPath $script:CdpCache
    $others = @(@(Get-GdidCredUsers) | Where-Object { -not $_.session }).Count
    if ($others -gt 0) { Write-Log ("   [i] кэш платформы подключённых устройств других пользователей, которые сейчас в Windows, не чистится: {0}" -f $others) }
    # Сама папка: «нет» — только когда Windows так и ответила; ссылка вместо
    # папки не чистится (задача от имени пользователя тоже откажется)
    $root = $null
    try { $root = Get-Item -LiteralPath $dir -Force -ErrorAction Stop }
    catch [System.Management.Automation.ItemNotFoundException] { return @{ state = 'NotFound'; left = 0; dir = $dir; others = $others } }
    catch {
        Write-Log ("   [!] папку кэша платформы подключённых устройств не удалось открыть: {0} -- очищена ли она, неизвестно" -f $_.Exception.Message)
        return @{ state = 'Unverified'; left = 0; dir = $dir; others = $others }
    }
    if ($root.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Write-Log ("   [!] на месте кэша платформы подключённых устройств лежит ссылка ({0}) -- не очищается" -f $dir)
        return @{ state = 'Partial'; left = 1; dir = $dir; others = $others }
    }
    $null = Clear-Folder $dir 'кэш платформы подключённых устройств'
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        # папки не стало — это ещё надо подтвердить тем же способом
        try { $null = Get-Item -LiteralPath $dir -Force -ErrorAction Stop }
        catch [System.Management.Automation.ItemNotFoundException] { return @{ state = 'Clean'; left = 0; dir = $dir; others = $others } }
        catch { Write-Log '   [!] кэш платформы подключённых устройств не удалось проверить (нет доступа) -- очищен ли он, неизвестно'; return @{ state = 'Unverified'; left = 0; dir = $dir; others = $others } }
    }
    $lf = Get-GdidDirLeft $dir
    $left = [int]$lf.files + [int]$lf.links
    if ($left -gt 0) {
        Write-Log ("   [!] в кэше платформы подключённых устройств осталось: файлов {0}, ссылок {1} -- Windows их не отдала" -f $lf.files, $lf.links)
        foreach ($f in @($lf.samples)) { Write-Log ("       {0}" -f $f) }
        return @{ state = 'Partial'; left = $left; dir = $dir; others = $others }
    }
    if ([int]$lf.errors -gt 0) {
        Write-Log ("   [!] кэш платформы подключённых устройств не удалось проверить целиком (папок без доступа: {0}) -- очищен ли он, неизвестно" -f $lf.errors)
        foreach ($f in @($lf.errorAt)) { Write-Log ("       {0}" -f $f) }
        return @{ state = 'Unverified'; left = 0; dir = $dir; others = $others }
    }
    return @{ state = 'Clean'; left = 0; dir = $dir; others = $others }
}

# Стирает «личность» устройства и все известные копии номера. Пока сервер
# выдачи открыт, Windows при следующем обращении получит новый номер — это
# смена. Под запретом выдачи — номера не станет вовсе.
#
# Порядок: ограничения → предварительная проверка (только чтение) →
# wlidsvc — в журнал отката и отключить → остановка служб → учётные данные у
# пользователей → у системы → реестр → кэш платформы подключённых устройств →
# проверка → службы как были → итог.
# Предварительная проверка (Get-GdidPreflight) идёт до любого изменения:
# опись копий без мест без доступа, список профилей и полный снимок служб.
# Чего-то из этого нет — не меняется ничего. Раньше стирание начиналось,
# даже если часть мест не прочиталась, а состояния служб собирались без
# проверки ошибок.
# Проверка итога — пока службы стоят: иначе поднявшаяся wlidsvc успевала
# завести новый номер. Службы возвращаются в finally — на любом пути, и при
# исключении тоже: раньше ранний отказ возвращал службы по пустому списку.
# Итог — $script:GdidWipeResult (New-GdidResult); state:
#   Clean        — копии были и стёрты, проверено всё;
#   NotFound     — копий не было, проверено всё;
#   Partial      — что-то стёрто, а что-то нет (или не вернулись службы);
#   AccessDenied — Windows не дала убрать ни одной копии;
#   Unverified   — копий не нашлось, но проверено не всё: профили тех, кто
#                  не вошёл в Windows, места без доступа, чужие кэши;
#   Failed       — не стёрто ничего: отказ, предварительная проверка не
#                  прошла или службы не остановились;
#   DryRun       — пробный запуск: стирание началось бы и могло бы дойти до
#                  проверенного итога.
# Успех ($true) — только Clean, NotFound и DryRun.
$script:GdidWipeResult = $null

# Итог операции с номером — одна форма для стирания и возврата: окно, журнал
# работы и код выхода берут его отсюда и не расходятся.
#   operation — wipe или restore; status (и прежнее имя state) — итог;
#   success   — всё прошло и проверено (тогда exitCode 0, иначе 2);
#   complete  — проверено всё, что нужно для такого ответа;
#   checked   — сколько копий нашла опись до стирания (у возврата — стадий);
#   removed   — сколько записей убрано; remaining — сколько копий осталось;
#   failed    — сколько шагов не удалось; unverified — мест без доступа;
#   uncheckedProfiles — профили вне Windows и чужие непроверенные кэши;
#   serviceStates — службы до и после; warnings, errors; timestamp.
# Пустой итог — ещё не «чисто»: начальное состояние — Failed.
function New-GdidResult {
    param([string]$Operation)
    return [ordered]@{
        operation = $Operation; status = 'Failed'; state = 'Failed'; success = $false; complete = $false
        checked = 0; removed = 0; remaining = 0; failed = 0; unverified = 0; uncheckedProfiles = 0
        serviceStates = @(); warnings = (New-Object System.Collections.Generic.List[string]); errors = (New-Object System.Collections.Generic.List[string])
        timestamp = (Get-Date).ToString('s'); exitCode = 2
        # прежние поля ответа — их читают проверки и окно
        before = 0; after = 0; denied = 0; unreadable = 0; unchecked = 0; stages = [ordered]@{}; notBack = @(); preflight = @()
    }
}

# Итог — одним вызовом: состояние, успех, полнота и код выхода вместе
function Set-GdidResultState {
    param($Result, [string]$State)
    $Result['state'] = $State; $Result['status'] = $State
    $Result['success'] = ($State -in @('Clean', 'NotFound', 'DryRun', 'Restored', 'NotModified'))
    $Result['complete'] = [bool]$Result['success']
    $Result['exitCode'] = $(if ($Result['success']) { 0 } else { 2 })
}

# Предварительная проверка стирания — только чтение, до любого изменения.
# ok — можно начинать. blockers — почему нельзя: места без доступа (копии в
# них остались бы, и Windows вернула бы номер), список профилей не прочитался
# (чьи копии на месте, неизвестно), снимок служб неполный (вернуть их потом
# было бы не по чему). warnings — то, что стиранию не мешает, но полного
# «стёрто отовсюду» не даст: профили тех, кто не вошёл в Windows, и
# незнакомые подключи личностей (они не трогаются).
function Get-GdidPreflight {
    $p = @{ ok = $false; blockers = (New-Object System.Collections.Generic.List[string]); warnings = (New-Object System.Collections.Generic.List[string])
            scan = $null; snapshot = $null }
    $scan = Get-GdidScan
    $p.scan = $scan
    if ($scan.profiles.enumerationFailed) {
        $p.blockers.Add(("список профилей пользователей не прочитался ({0}) -- чьи копии номера на месте, неизвестно" -f (@($scan.profiles.errors) -join '; ')))
    }
    $regUnread = @(@($scan.unreadable) | Where-Object { @($scan.profiles.places) -notcontains $_ })
    if ($regUnread.Count -gt 0) {
        $p.blockers.Add(("мест без доступа на чтение: {0} ({1}) -- копии номера в них остались бы, и Windows вернула бы его" -f $regUnread.Count,
                         ((@($regUnread | Select-Object -First 3) | ForEach-Object { "$_" -replace '^Registry::', '' }) -join '; ')))
    }
    if ([int]$scan.profiles.unloadedProfiles -gt 0) {
        $p.warnings.Add(("профили пользователей, которые сейчас не вошли в Windows, не проверяются: {0}" -f $scan.profiles.unloadedProfiles))
    }
    if (@($scan.unknown).Count -gt 0) {
        $p.warnings.Add(("подключи личностей устройства без DeviceId оставлены как есть: {0}" -f @($scan.unknown).Count))
    }
    $snap = Get-GdidServiceSnapshot
    $p.snapshot = $snap
    if (-not $snap.complete) { foreach ($x in @($snap.problems)) { $p.blockers.Add(("службы: {0}" -f $x)) } }
    $p.ok = ($p.blockers.Count -eq 0)
    return $p
}

function Invoke-GdidWipe {
    $res = New-GdidResult 'wipe'
    $script:GdidWipeResult = $res
    $why = Get-ManagedReason
    if ($why) {
        Write-Log ("   [!] номер устройства не тронут: {0}. На таком компьютере он связан с учётной записью организации." -f $why)
        $res.stages['restrictions'] = 'refused'; $res.errors.Add("$why"); $res.failed = 1
        Set-GdidResultState $res 'Failed'
        $script:Failures++; return $false
    }
    $res.stages['restrictions'] = 'ok'

    # 0. предварительная проверка — только чтение: до неё не меняется ничего
    $pre = Get-GdidPreflight
    $before = @($pre.scan.copies)
    $res.before = $before.Count; $res.checked = $before.Count
    $res.unreadable = @($pre.scan.unreadable).Count; $res.unverified = $res.unreadable
    $res.unchecked = [int]$pre.scan.unchecked; $res.uncheckedProfiles = $res.unchecked
    $res.preflight = $pre.blockers.ToArray()
    foreach ($w in $pre.warnings.ToArray()) { $res.warnings.Add("$w") }
    $res.serviceStates = @(@($pre.snapshot.services) | ForEach-Object { @{ name = "$($_.name)"; before = @{ start = [int]$_.start; running = [bool]$_.running; status = "$($_.status)" } } })
    $res.stages['preflight'] = $(if ($pre.ok) { 'ok' } else { 'Failed' })
    $tag = $(if ($DryRun) { '[тест]' } else { '[!]' })
    if (-not $pre.ok) {
        Write-Log ("   {0} номер устройства не тронут: предварительная проверка не прошла -- ничего не изменено" -f $tag)
        foreach ($b in $pre.blockers.ToArray()) { Write-Log ("       {0}" -f $b); $res.errors.Add("$b") }
        $res.failed = 1
        # копий не нашлось, но проверить всё не вышло — «не проверено», а не «чисто»
        Set-GdidResultState $res $(if ($before.Count -eq 0) { 'Unverified' } else { 'Failed' })
        $script:Failures++; return $false
    }
    if ($DryRun) {
        Write-Log ("   [тест] копий номера устройства: {0} -- будут стёрты вместе с «личностью» устройства" -f $before.Count)
        # Пробный запуск не обещает больше, чем даст настоящий: раньше он
        # отвечал «успех» всегда, даже когда часть мест не проверялась
        $othersN = @(@(Get-GdidCredUsers) | Where-Object { -not $_.session }).Count
        $res.uncheckedProfiles = $res.unchecked + $othersN
        if ([bool]$pre.scan.profiles.unverified -or $othersN -gt 0) {
            Write-Log ("   [тест] проверено будет не всё: профилей вне Windows {0}, других вошедших пользователей {1} -- «стёрто отовсюду» стирание не скажет" -f $res.unchecked, $othersN)
            Set-GdidResultState $res 'Unverified'
            $script:Failures++; return $false
        }
        Set-GdidResultState $res 'DryRun'
        return $true
    }
    Write-Log ("   найдено копий номера: {0}" -f $before.Count)
    foreach ($w in $pre.warnings.ToArray()) { Write-Log ("   [i] {0}" -f $w) }

    # Службы, которые работали до стирания, — по снимку. Их стирание
    # останавливает (они держат номер в памяти и вернули бы его) и потом
    # запускает снова; стоявшие до стирания не запускаются.
    $snap = $pre.snapshot
    $runningBefore = @(@($snap.services) | Where-Object { $_.running -and $_.scmFound } | ForEach-Object { "$($_.name)" })
    # что стирание пыталось остановить — возвращается всё это (из тех, что работали)
    $touched = New-Object System.Collections.Generic.List[string]
    $notBackMsg = '   [!] службы не вернулись в прежнее состояние: {0}. Перезагрузка компьютера вернёт их.'
    $wlid = $null
    $fails = 0
    $aborted = ''
    $verify = $null
    $reg = @{ removed = 0; denied = 0; kept = 0 }
    $cdp = @{ others = 0 }
    $restore = $null
    try {
        $wlid = Disable-GdidWlid
        if (-not $wlid.ok) {
            Write-Log ("   [!] номер устройства не тронут: {0} -- службу учётных записей Microsoft нельзя отключить на время стирания, не записав, как было." -f $wlid.why)
            $res.stages['services'] = 'refused'; $res.errors.Add("$($wlid.why)")
            $aborted = 'refused'
        } else {
            if ($wlid.why) { Write-Log ("   [i] {0}" -f $wlid.why) }
            $res.stages['services'] = 'saved'
            $touched.Add('wlidsvc')
            if (-not (Stop-ServiceWait 'wlidsvc')) {
                Write-Log '   [!] служба учётных записей Microsoft (wlidsvc) занята и не остановилась. Закройте Магазин и Параметры и повторите или перезагрузите компьютер. Ничего не стёрто.'
                $aborted = 'stop'
            } else {
                # Служба, которая не остановилась, держит номер в памяти и
                # записала бы его обратно посреди стирания. Тогда не стираем
                # ничего и возвращаем всё как было.
                $stuck = New-Object System.Collections.Generic.List[string]
                foreach ($n in $runningBefore) {
                    if ($n -eq 'wlidsvc') { continue }
                    $touched.Add($n)
                    if (-not (Stop-ServiceWait $n)) { $stuck.Add($n) }
                }
                if ($stuck.Count -gt 0) {
                    Write-Log ("   [!] служба не остановилась: {0}. Она держит номер устройства и вернула бы его на место. Ничего не стёрто -- повторите позже или после перезагрузки." -f ($stuck.ToArray() -join ', '))
                    $aborted = 'stop'
                }
            }
            $res.stages['stop'] = $(if ($aborted) { 'Failed' } else { 'ok' })
        }
        if (-not $aborted) {
            # 1. учётные данные «личности» устройства — у пользователей и у системы
            $cu = Clear-GdidUserCreds
            $res.stages['userCredentials'] = $cu.state
            $fails += [int]$cu.fails
            $sysCmd = (@($script:GdidCredSystem | ForEach-Object { 'cmdkey /delete:' + $_ + ' >nul 2>&1' }) -join ' & ') + ' & ' + (Get-CredCheckCmd $script:GdidCredSystem)
            if (Invoke-OneShotTask 'Win11Privacy GDID system' $sysCmd -AsSystem) { Write-Log '   [+] учётные данные устройства у системы убраны'; $res.stages['systemCredentials'] = 'Clean' }
            else { Write-Log '   [!] учётные данные устройства у системы убрать не удалось'; $fails++; $res.stages['systemCredentials'] = 'Failed' }
            # 2. копии номера в реестре — ровно найденные записи
            $reg = Remove-GdidRegistryCopies
            $res.stages['registry'] = $reg.state
            if ([int]$reg.denied -gt 0 -or [int]$reg.kept -gt 0) { $fails++ }
            # 3. кэш платформы подключённых устройств
            $cdp = Clear-GdidCdpCache
            $res.stages['cdp'] = $cdp.state
            if ($cdp.state -notin @('Clean', 'NotFound')) { $fails++ }
            # 4. проверка — пока службы стоят и вернуть номер некому
            $verify = Get-GdidScan
            $res.stages['verify'] = $verify.state
        }
    } catch {
        $aborted = 'exception'
        $res.errors.Add("$($_.Exception.Message)")
        Write-Log ("   [!] стирание прервалось: {0}" -f $_.Exception.Message)
    } finally {
        # 5. службы — как были, что бы ни случилось выше
        $back = @($touched.ToArray() | Where-Object { $runningBefore -contains $_ })
        try { $restore = Restore-GdidServices $back $wlid $snap }
        catch { $restore = @{ notBack = @(('службы (возврат прервался: {0})' -f $_.Exception.Message)); states = @() } }
        $res.notBack = @($restore.notBack)
        if (@($restore.states).Count -gt 0) { $res.serviceStates = @($restore.states) }
        $res.stages['restore'] = $(if (@($restore.notBack).Count -gt 0) { 'Failed' } else { 'ok' })
        if (@($restore.notBack).Count -gt 0) { Write-Log ($notBackMsg -f (@($restore.notBack) -join ', ')) }
    }
    $res.removed = [int]$reg.removed; $res.denied = [int]$reg.denied
    if (@($res.notBack).Count -gt 0) { $fails++ }
    if ($aborted -in @('refused', 'stop')) {
        $res.failed = $fails + 1
        Set-GdidResultState $res 'Failed'; $script:Failures++; return $false
    }
    if ($aborted -eq 'exception') {
        # что успело стереться до сбоя, неизвестно наверняка
        $res.failed = $fails + 1
        Set-GdidResultState $res $(if ($res.removed -gt 0) { 'Partial' } else { 'Failed' })
        Write-Log '   [!] стирание прошло не полностью -- повторите его; службы возвращены, как были'
        $script:Failures++; return $false
    }

    $after = @($verify.copies)
    $unread = @($verify.unreadable)
    $unchecked = [int]$verify.unchecked + [int]$cdp.others
    $profUnverified = [bool]$verify.profiles.unverified
    $res.after = $after.Count; $res.remaining = $after.Count
    $res.unreadable = $unread.Count; $res.unverified = $unread.Count
    $res.unchecked = $unchecked; $res.uncheckedProfiles = $unchecked
    $res.failed = $fails
    if ($after.Count -gt 0) { Write-Log ("   [!] осталось копий номера: {0} -- Windows их не отдала" -f $after.Count) }
    if ($unread.Count -gt 0) {
        # «не нашли» там, куда не пустили, — не то же самое, что «стёрто»
        Write-Log ("   [!] не удалось проверить мест: {0} (нет доступа) -- стёрто ли там, неизвестно" -f $unread.Count)
        foreach ($u in @($unread | Select-Object -First 3)) { Write-Log ("       {0}" -f ($u -replace '^Microsoft\.PowerShell\.Core\\Registry::', '')) }
    }
    if ([int]$verify.unchecked -gt 0) {
        Write-Log ("   [i] профили пользователей, которые сейчас не вошли в Windows, не проверялись: {0}. У тех из них, кто входит через учётную запись Microsoft, может остаться прежний номер." -f $verify.unchecked)
        $res.warnings.Add(("профили пользователей вне Windows не проверялись: {0} -- в них может остаться прежний номер" -f $verify.unchecked))
    }
    # Успех — только когда прошло всё: копий нет, учётные данные убраны, кэш
    # пуст, службы вернулись и проверено всё, включая список профилей.
    $state = $(if ($fails -eq 0 -and $after.Count -eq 0 -and $unread.Count -eq 0 -and $unchecked -eq 0 -and -not $profUnverified) { if ($before.Count -eq 0 -and $res.removed -eq 0) { 'NotFound' } else { 'Clean' } }
               elseif ($fails -eq 0 -and $after.Count -eq 0) { 'Unverified' }
               elseif ($after.Count -gt 0 -and $res.removed -eq 0 -and $res.denied -gt 0) { 'AccessDenied' }
               else { 'Partial' })
    Set-GdidResultState $res $state
    if ($state -eq 'Clean') { Write-Log '   [+] номер устройства стёрт отовсюду, где программа его ищет'; $script:Changes++ }
    elseif ($state -eq 'NotFound') { Write-Log '   [+] копий номера не нашлось -- проверено всё, где программа его ищет' }
    else {
        if ($state -eq 'Unverified') { Write-Log '   [!] там, где программа смогла проверить, копий номера не осталось, но проверено не всё -- см. выше' }
        elseif ($after.Count -eq 0) { Write-Log '   [!] копий номера в реестре не осталось, но стирание прошло не полностью -- см. выше' }
        if ($res.removed -gt 0) { $script:Changes++ }
        $script:Failures++
    }
    return [bool]$res.success
}

# «Вернуть как было», службы: тип запуска — из журнала отката, ровно для тех
# служб, которые меняла программа (wlidsvc — если её оставило отключённой
# прерванное стирание). result:
#   restored     — возвращён, и тип запуска сверен с журналом;
#   notChanged   — программа её не меняла (записи в журнале нет);
#   notFound     — запись есть, а службы на этой системе больше нет: возвращать
#                  некуда, запись в журнале остаётся (это не ошибка);
#   accessDenied — тип запуска не читается или Windows не дала его записать;
#   failed       — не вернулся (или журналу нельзя верить).
# Запись журнала убирается только после сверки (это делает Restore-ChangeKey).
# Раньше любой отказ — журналу нельзя верить, тип запуска не вернулся —
# назывался «программа её не меняла» и ошибкой не считался, а пропавшая
# служба — «возвращена».
function Restore-GdidServiceStarts {
    $out = New-Object System.Collections.Generic.List[object]
    $jf = Read-JournalFile -ReadOnly
    $first = @{}
    if ($jf.trusted) {
        foreach ($it in @($jf.items)) {
            $f = ConvertTo-Fields $it
            $k = Get-JournalKey $f
            if (-not $first.ContainsKey($k)) { $first[$k] = $f }
        }
    }
    foreach ($n in @($script:GdidSvcNames + 'wlidsvc')) {
        $key = $(if ($n -eq 'wlidsvc') { 'svc|wlidsvc' } else { ("reg|HKLM:\SYSTEM\CurrentControlSet\Services\{0}|Start" -f $n).ToLowerInvariant() })
        if (-not $jf.trusted) { $out.Add(@{ name = $n; result = 'failed'; error = 'журналу отката нельзя верить: подпись не сошлась или он не прочитался' }); continue }
        if (-not $first.ContainsKey($key)) { $out.Add(@{ name = $n; result = 'notChanged'; error = '' }); continue }
        $want = "$($first[$key]['old'])"
        $now = Get-SvcStartInfo $n
        if ("$($now.state)" -eq 'Missing') { $out.Add(@{ name = $n; result = 'notFound'; error = 'службы на этой системе больше нет' }); continue }
        if ("$($now.state)" -eq 'ReadError') { $out.Add(@{ name = $n; result = 'accessDenied'; error = ("тип запуска не читается: {0}" -f $now.error) }); continue }
        $r = Restore-ChangeKey $key
        if (-not $r.ok) {
            $out.Add(@{ name = $n; result = $(if ($r.denied) { 'accessDenied' } elseif ($r.missing) { 'notFound' } else { 'failed' }); error = "$($r.error)" })
            continue
        }
        if ($r.missing) { $out.Add(@{ name = $n; result = 'notFound'; error = 'службы на этой системе больше нет' }); continue }
        # сверка: тип запуска — тот, что был до программы
        $chk = Get-SvcStartInfo $n
        if ($want -match '^[0-4]$' -and "$($chk.start)" -ne $want) {
            $out.Add(@{ name = $n; result = 'failed'; error = ("после возврата тип запуска {0}, а было {1}" -f (Get-StartName "$($chk.start)"), (Get-StartName $want)) })
            continue
        }
        $out.Add(@{ name = $n; result = 'restored'; error = '' })
    }
    return $out.ToArray()
}

# Сколько блоков этого вида в hosts (вместе с осиротевшими метками);
# -1 — hosts не прочитался
function Get-GdidHostsFound {
    param([string]$Kind)
    try { return [int](Get-HostsLinesWithout (Read-HostsLines) $Kind).found } catch { return -1 }
}

# После возврата типа запуска в реестре диспетчер служб до перезагрузки
# помнит «отключена» (службы отключались прямо в реестре) — и не запустит её.
# Поэтому тип запуска передаётся и ему (Set-Service; DoSvc Windows не даёт и
# администратору), службы с автоматическим запуском запускаются, копии
# CDPUserSvc, заведённые отключёнными, получают тип запуска шаблона.
# Чего сразу не вышло, так и названо: pending — после перезагрузки или
# выхода из Windows (это не ошибка), failed — не запустилась (ошибка).
function Sync-GdidRestoredServices {
    param([string[]]$Names)
    $pending = New-Object System.Collections.Generic.List[string]
    $failed = New-Object System.Collections.Generic.List[string]
    $toScm = { param($n) switch ((Get-SvcStartInfo $n).start) { 2 { 'Automatic' } 3 { 'Manual' } default { '' } } }
    # Код ошибки Windows в исключении (по цепочке InnerException); 0 — нет кода
    $winCode = {
        param($Ex)
        for ($x = $Ex; $null -ne $x; $x = $x.InnerException) {
            if ($x -is [System.ComponentModel.Win32Exception]) { return [int]$x.NativeErrorCode }
        }
        if ("$($Ex.Message)" -match '\b1058\b') { return 1058 }
        return 0
    }
    $bring = {
        param([string]$Svc, [string]$Want, [string]$Later)
        $v = Get-SvcScmView $Svc
        if (-not $v.found) { return }
        # Тип запуска передаётся диспетчеру служб всегда. Спрашивать его, какой
        # тип запуска он помнит, бесполезно: Get-Service и sc qc отвечают по
        # реестру («автоматически»), а сам диспетчер до перезагрузки держит
        # «отключена» и не запускает службу (ошибка 1058). Раньше Set-Service
        # звался, только когда Get-Service говорил «отключена», — и после
        # перезагрузки с отключёнными службами CDPSvc не запускалась (VM,
        # 2026-11-16).
        $setOk = $true
        try { Set-Service -Name $Svc -StartupType $Want -ErrorAction Stop } catch { $setOk = $false }
        $v = Get-SvcScmView $Svc
        if ($v.start -eq 'Disabled') { $pending.Add(("{0} ({1})" -f $Svc, $Later)); return }
        if ($Want -ne 'Automatic' -or $v.running) {
            # не запускаем (вручную) — но если диспетчер не принял тип запуска
            # (DoSvc Windows не даёт менять и администратору), он может помнить
            # «отключена» до перезагрузки: так и сказано
            if (-not $setOk -and -not $v.running) { $pending.Add(("{0} ({1})" -f $Svc, $Later)) }
            return
        }
        try {
            Start-Service -Name $Svc -ErrorAction Stop -WarningAction SilentlyContinue
            (Get-Service -Name $Svc -ErrorAction Stop).WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
        } catch {
            # 1058 — диспетчер помнит «отключена», а передать ему тип запуска
            # Windows не дала: служба заработает после перезагрузки. Это не сбой.
            if (-not $setOk -and (& $winCode $_.Exception) -eq 1058) { $pending.Add(("{0} ({1})" -f $Svc, $Later)); return }
            $failed.Add(("{0}: {1}" -f $Svc, $_.Exception.Message))
        }
    }
    foreach ($n in @($Names)) {
        $want = & $toScm $n
        if (-not $want) { continue }
        if ($n -eq 'CDPUserSvc') {
            # сам шаблон не запускается — запускаются его копии у пользователей
            # и ему тип запуска — диспетчеру служб всегда (см. выше): по нему заводятся новые копии
            $v = Get-SvcScmView $n
            if ($v.found) { try { Set-Service -Name $n -StartupType $want -ErrorAction Stop } catch { } }
            foreach ($inst in @((Get-GdidUserSvcInstances).names)) { & $bring $inst $want 'после выхода из Windows и нового входа' }
            continue
        }
        & $bring $n $want 'после перезагрузки'
    }
    return @{ pending = $pending.ToArray(); failed = $failed.ToArray() }
}

# Состояние для вкладки «Номер устройства». Только чтение.
function Get-GdidStatus {
    $scan = Get-GdidScan
    $copies = @($scan.copies)
    $tx = Get-GdidTransmitState
    $userLid = Get-RegValue 'HKCU:\SOFTWARE\Microsoft\IdentityCRL\ExtendedProperties' 'LID'
    $svcs = New-Object System.Collections.Generic.List[object]
    foreach ($s in @($tx.services)) { $svcs.Add($s) }
    $svcs.Add((Get-GdidSvcEntry 'wlidsvc'))
    $nums = @($copies | ForEach-Object { "$($_.puid)" } | Where-Object { $_ -match $script:DevicePuidRegex } | Select-Object -Unique)
    # Номер для плитки: свой, а если своего нет — из любого найденного хранилища.
    # Раньше брался только свой, и рядом с «Копий на диске: 3» стояло «нет».
    # По хранилищам номера отдаются отдельно — они могут различаться.
    $ids = @()
    foreach ($who in @('user', 'system', 'other')) {
        foreach ($n in @($copies | Where-Object { $_.who -eq $who -and "$($_.puid)" -match $script:DevicePuidRegex } | ForEach-Object { "$($_.puid)" } | Select-Object -Unique)) {
            $ids += @{ who = $who; gdid = (ConvertTo-Gdid $n) }
        }
    }
    $mainGdid = $(if ("$userLid") { ConvertTo-Gdid "$userLid" } elseif ($ids.Count -gt 0) { $ids[0].gdid } else { '' })
    return @{
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        gdid = $mainGdid
        gdidFrom = $(if ("$userLid") { 'user' } elseif ($ids.Count -gt 0) { $ids[0].who } else { '' })
        ids = $ids
        copies = $copies.Count; numbers = $nums.Count
        userCopies = @($copies | Where-Object { $_.who -eq 'user' }).Count
        systemCopies = @($copies | Where-Object { $_.who -eq 'system' }).Count
        otherCopies = @($copies | Where-Object { $_.who -eq 'other' }).Count
        unreadable = @($scan.unreadable).Count
        uncheckedProfiles = [int]$scan.unchecked
        # Found, NotFound или Unverified: «копий 0» при непроверенных местах — не «нет»
        scanState = $scan.state
        # Передача — одной проверкой (Get-GdidTransmitState): Off, Pending, On, Unknown
        transmitOff = [bool]$tx.off; transmitState = $tx.state; transmitPending = [bool]$tx.pending; transmitKnown = [bool]$tx.known
        transmitProblems = $tx.problems
        # Блок считается стоящим, только если он цел и в нём ровно нужный список;
        # *Present — метка блока есть (он задуман), даже если побит или устарел
        ddsBlocked = (Test-HostsBlockCurrent -Kind 'gdid'); ddsPresent = (Test-HostsBlock -Kind 'gdid')
        locked = (Test-HostsBlockCurrent -Kind 'lock'); lockPresent = (Test-HostsBlock -Kind 'lock')
        wlidBlocked = (Test-FwRule 'svc' 'wlidsvc')
        msaLogon = (Test-MsaLogon); managed = (Get-ManagedReason)
        # вид принадлежности организации (Get-GdidManagement): domain, entra,
        # hybrid, mdm, workAccount, unknown или ''; учётные записи — по людям
        managedKind = "$((Get-GdidManagement).kind)"
        workAccount = [bool](Get-GdidManagement).workAccount
        accounts = @(Get-GdidAccounts)
        profiles = $scan.profiles
        unknownIdentities = @($scan.unknown).Count
        admin = (Test-Admin)
        services = $svcs.ToArray()
    }
}

# --- аудит соединений (монитор) -------------------------------------------- #
# Монитор считается включённым, когда журнал пишет и разрешённые соединения
# (5156), и отклонённые (5157). Раньше включались только отказы, и список «кто
# отправляет», который строится по разрешённым, в живой системе был пуст.
# Значение подкатегории аудита числом: 0 — нет, 1 — успех, 2 — отказ, 3 — оба;
# -1 — прочитать не удалось. Текстовый вывод auditpol переведён на язык
# Windows («Успех и сбой», «Erfolg und Fehler»), и проверка по словам на
# немецкой Windows считала бы монитор выключенным всегда. Резервная копия
# политики (/backup) пишет то же самое числом — по нему и сверяемся.
function Get-AuditSetting {
    param([string]$Guid = $script:AuditGuid)
    # auditpol пишет копию политики в файл, а читаем мы её с правами
    # администратора. Пишем в защищённый корень, если он уже есть (его завело
    # окно или применение), а не во временную папку пользователя: туда он мог
    # бы подложить на наш путь ссылку. Корня ещё нет — случайное имя во
    # временной папке (чтение политики не должно заводить корень само).
    $dir = $(if ($script:SafeRoot -and (Test-Path -LiteralPath $script:SafeRoot -PathType Container)) { $script:SafeRoot } else { [IO.Path]::GetTempPath() })
    $tmp = Join-Path $dir ('w11p-audit-' + [guid]::NewGuid().ToString('N') + '.csv')
    try {
        if ((Test-Path -LiteralPath $tmp) -and ((Get-Item -LiteralPath $tmp -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { return -1 }
        $null = & auditpol.exe /backup /file:$tmp 2>&1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tmp)) { return -1 }
        # Заголовки столбцов в копии тоже бывают переведены («GUID подкатегории»,
        # «значение параметра» — проверено на русской Windows), поэтому читаем
        # по положению: порядок столбцов у /backup постоянный. Первая строка —
        # заголовок, её пропускаем.
        $rows = @(Import-Csv -LiteralPath $tmp -Header 'pc', 'target', 'sub', 'guid', 'inc', 'exc', 'val' | Select-Object -Skip 1)
        # ни одного GUID на своём месте — формат не тот, не гадаем
        if (@($rows | Where-Object { "$($_.guid)" -match '^\{[0-9A-Fa-f-]{36}\}$' }).Count -eq 0) { return -1 }
        foreach ($row in $rows) {
            if ("$($row.guid)" -eq $Guid) { return [int]("0" + "$($row.val)".Trim()) }
        }
        return 0      # строки нет — подкатегория не настроена, а это «нет аудита»
    } catch { return -1 }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

function Get-MonitorEnabled {
    $v = Get-AuditSetting
    if ($v -ge 0) { return ($v -eq 3) }
    # запасной путь — по словам, как раньше
    try {
        $out = & auditpol.exe /get /subcategory:$script:AuditGuid /r 2>$null
        $csv = $out | Where-Object { $_ -and $_ -notmatch '^Machine Name' -and $_ -notmatch '^Имя компьютера' } | Select-Object -Last 1
        if (-not $csv) { return $false }
        return (($csv -match 'Success|Успех|Успешн') -and ($csv -match 'Failure|Отказ|Сбой'))
    } catch { return $false }
}

function Set-AuditSetting {
    param([string]$Guid, [int]$Value)
    $s = $(if ($Value -band 1) { 'enable' } else { 'disable' })
    $f = $(if ($Value -band 2) { 'enable' } else { 'disable' })
    $out = & auditpol.exe /set /subcategory:$Guid /success:$s /failure:$f 2>&1
    return @{ ok = ($LASTEXITCODE -eq 0); code = $LASTEXITCODE; out = (($out | ForEach-Object { "$_" }) -join ' ').Trim() }
}

# Журнал безопасности по умолчанию — 20 МБ: с записью всех соединений он
# переписывал бы себя за часы. Под монитор он растёт до 128 МБ — через журнал
# изменений, чтобы откат вернул прежний размер.
$script:SecurityLogKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Security'
$script:SecurityLogMin = 134217728

# Раньше результат auditpol не проверялся: команда могла не сработать, а
# функция всё равно говорила «включён». Теперь проверяется и код выхода, и то,
# что политика действительно стала нужной. Прежнее значение уходит в журнал
# отката — откат вернёт ровно его, а не «выключено».
function Set-MonitorEnabled {
    param([bool]$On)
    try {
        $before = Get-AuditSetting
        if (-not $On) {
            # Выключение возвращает ту политику аудита, что была до программы,
            # если программа её меняла. Раньше ставился «нет аудита» всегда, и
            # прежняя настройка (например, «только успешные») пропадала вместе
            # с нашей. Возврат — той же функцией, что и полный откат. (Сначала
            # здесь стояла Restore-ChangeKey, но она описана в файле ниже, а
            # движок выполняется сверху вниз: на живой системе её ещё не было.)
            $jf = Read-JournalFile -ReadOnly
            $ae = $null
            if ($jf.trusted) { $ae = @($jf.items | Where-Object { "$($_.kind)" -eq 'audit' -and "$($_.guid)" -eq $script:AuditGuid }) | Select-Object -First 1 }
            if ($ae -and (Test-JournalEntryShape $ae)) { $ae = $null }   # запись не по форме — не исполняется
            if ($ae) {
                $want = [int]("0" + "$($ae.old)")
                $rk = Restore-JournalEntry $ae
                if (-not $rk.ok) { Write-Log ("   [!] прежняя политика аудита не вернулась: {0}" -f $rk.error); $script:Failures++; return $false }
                if ((Get-AuditSetting) -ne $want) {
                    Write-Log '   [!] auditpol отработал, но политика аудита не та, что была до программы -- возможно, её задаёт групповая политика организации'
                    $script:Failures++; return $false
                }
                try { Remove-JournalKey (Get-JournalKey (ConvertTo-Fields $ae)) }
                catch { Write-Log ("   [!] политика аудита возвращена, но запись о ней из журнала отката не убралась: {0}" -f $_.Exception.Message); $script:Failures++ }
                Write-Log ("   [+] журнал соединений брандмауэра: политика аудита возвращена к прежней ({0})" -f (Get-AuditName "$want"))
                return $true
            }
            if ($before -eq 3) { Write-Log '   [i] программа политику аудита не меняла (или журналу нельзя верить) -- выключаем по вашей просьбе' }
        }
        if ($On -and $before -lt 0) {
            # Какой политика была, не прочиталось — значит, и вернуть её
            # потом было бы нечем. Раньше аудит включался всё равно.
            Write-Log '   [!] не удалось прочитать нынешнюю политику аудита -- включать не будем: потом её нечем было бы вернуть'
            $script:Failures++; return $false
        }
        # «Как было» — в журнал раньше изменения, как у всех остальных
        # изменений (Write-AheadEntry). Раньше запись шла после auditpol, и
        # обрыв между ними оставлял политику изменённой без пути назад.
        $ahead = $null
        if ($On -and $before -ne 3) {
            $ahead = @{ kind = 'audit'; guid = $script:AuditGuid; old = "$before"; newValue = '3' }
            if (-not (Write-AheadEntry $ahead)) {
                Write-Log '   [!] журнал отката сейчас не пишется -- политику аудита не меняем'
                $script:Failures++; return $false
            }
        }
        $r = Set-AuditSetting $script:AuditGuid $(if ($On) { 3 } else { 0 })
        $why = ''
        if (-not $r.ok) { $why = ("   [!] auditpol не изменил политику аудита (код {0}): {1}" -f $r.code, $r.out) }
        elseif ((Get-MonitorEnabled) -ne $On) { $why = '   [!] auditpol отработал, но политика аудита осталась прежней -- возможно, её задаёт групповая политика организации' }
        if ($why) {
            # политика осталась прежней — изменения не было, запись отзывается;
            # не прочиталась или стала другой — запись остаётся для отката
            if ($ahead -and (Get-AuditSetting) -eq $before) { Undo-AheadEntry $ahead }
            Write-Log $why
            $script:Failures++
            return $false
        }
        Write-Log ("   [+] журнал соединений брандмауэра: {0}" -f $(if ($On) { 'включён' } else { 'выключен' }))
        if ($On) {
            $size = Get-RegValue $script:SecurityLogKey 'MaxSize'
            if ($null -eq $size -or [long]$size -lt $script:SecurityLogMin) {
                Set-Reg -Path $script:SecurityLogKey -Name 'MaxSize' -Value $script:SecurityLogMin -Type 'DWord' -Comment 'журнал безопасности — 128 МБ, чтобы монитор не вытеснял другие записи'
                Save-JournalEntries -Quiet
            }
        }
        return $true
    } catch { Write-Log "   [!] auditpol: $($_.Exception.Message)"; return $false }
}

# --------------------------------------------------------------------------- #
#  Новые программы в сети. Разрешённые исходящие соединения (5156) берутся из
#  журнала аудита брандмауэра, программа сравнивается со списком известных.
#  Первый час после включения — обучение: всё, что выходит в сеть, считается
#  своим, иначе первое же уведомление перечислило бы полсистемы.
# --------------------------------------------------------------------------- #
$script:NetTask = 'Win11Privacy Network'

function Get-NetAppKey {
    param([string]$Raw)
    $p = ConvertFrom-DevicePath $Raw
    if (-not $p) { $p = $Raw }
    return $p.ToLowerInvariant()
}

# Чтение журнала безопасности: «событий нет» и «журнал не читается» — разные
# вещи. Раньше любая ошибка давала пустой список, и монитор показывал «никто
# ничего не отправлял», когда на деле не мог прочитать журнал.
function Read-SecurityEvents {
    param([int[]]$Ids, [datetime]$Since, [int]$Max, [string]$LogName = 'Security')
    try {
        $ev = @(Get-WinEvent -FilterHashtable @{ LogName = $LogName; Id = $Ids; StartTime = $Since } -MaxEvents $Max -ErrorAction Stop)
        return @{ events = $ev; error = '' }
    } catch {
        if ("$($_.FullyQualifiedErrorId)" -like 'NoMatchingEventsFound*') { return @{ events = @(); error = '' } }
        return @{ events = @(); error = "$($_.Exception.Message)" }
    }
}

function Get-NetAppsSince {
    param([datetime]$Since, [int]$Max = 20000)
    $apps = @{}
    $rd = Read-SecurityEvents -Ids 5156 -Since $Since -Max $Max
    $events = @($rd.events)
    # ошибку чтения видит тот, кто вызвал: слежение, его установка, монитор
    $script:NetReadError = $rd.error
    foreach ($ev in $events) {
        try {
            $x = [xml]$ev.ToXml()
            $data = @{}
            foreach ($n in $x.Event.EventData.Data) { $data[[string]$n.Name] = [string]$n.'#text' }
            if ($data['Direction'] -ne '%%14593') { continue }              # только исходящие
            if (-not (Test-PublicIp $data['DestAddress'])) { continue }
            $raw = [string]$data['Application']
            if (-not $raw) { continue }
            $key = Get-NetAppKey $raw
            if ($apps.ContainsKey($key)) { $apps[$key].count++; continue }
            $apps[$key] = @{ key = $key; name = ($raw -split '\\')[-1]; path = (ConvertFrom-DevicePath $raw); count = 1
                             ip = $data['DestAddress']; time = $ev.TimeCreated.ToString('yyyy-MM-dd HH:mm') }
        } catch { }
    }
    return $apps
}

function Invoke-NetGuard {
    param([switch]$Quiet)
    $state = Load-Json 'net-apps.json'
    $known = @{}
    if ($state -and $state.known) { foreach ($k in @($state.known)) { $known["$k"] = $true } }
    $recent = New-Object System.Collections.Generic.List[object]
    if ($state -and $state.recent) { foreach ($r in @($state.recent)) { $recent.Add($r) } }
    $learnUntil = $(if ($state -and $state.learnUntil) { [datetime]$state.learnUntil } else { (Get-Date).AddHours(1) })
    $since = $(if ($state -and $state.last) { ([datetime]$state.last).AddMinutes(-1) } else { (Get-Date).AddMinutes(-20) })
    $now = Get-Date
    $fresh = @()
    foreach ($a in @((Get-NetAppsSince -Since $since).Values)) {
        if ($known.ContainsKey($a.key)) { continue }
        $known[$a.key] = $true
        if ($now -lt $learnUntil) { continue }                              # обучение: молча запоминаем
        $fresh += $a
        $recent.Insert(0, @{ name = $a.name; path = $a.path; time = $a.time; ip = $a.ip })
    }
    while ($recent.Count -gt 30) { $recent.RemoveAt($recent.Count - 1) }
    # Журнал не прочитался — отметку «проверено до» не двигаем, иначе эти
    # минуты выпали бы из слежения навсегда; а ошибку запоминаем для монитора.
    $err = "$script:NetReadError"
    # и при самом первом запуске: отметки ещё нет — остаётся начало окна, а не «сейчас»
    $last = $(if ($err) { if ($state -and $state.last) { "$($state.last)" } else { $since.ToString('s') } } else { $now.ToString('s') })
    Save-Json 'net-apps.json' @{ known = @($known.Keys); recent = $recent.ToArray(); learnUntil = $learnUntil.ToString('s'); last = $last
                                 readError = $err; readErrorTime = $(if ($err) { $now.ToString('yyyy-MM-dd HH:mm') } else { '' }) }
    if ($fresh.Count -gt 0 -and -not $Quiet) {
        $msg = (@($fresh | Select-Object -First 3 | ForEach-Object { $_.name }) -join ', ')
        if ($fresh.Count -gt 3) { $msg += (' и ещё ' + ($fresh.Count - 3)) }
        Show-Toast 'Новая программа вышла в сеть' ($msg + '. Запретить ей выход — на странице «Монитор».')
    }
    return $fresh
}

# Публичный ли адрес — по диапазонам, а не по началу строки. Прежние шаблоны
# считали публичными общие адреса провайдеров (100.64.0.0/10, за ними сидят
# целые районы), тестовые и зарезервированные сети (198.18.0.0/15,
# 240.0.0.0/4), многоадресные IPv6 вне ff0x, адрес IPv4 внутри IPv6
# (::ffff:10.0.0.1) — и вообще любую строку, даже не адрес. От этого зависят
# наблюдение за сетью и проверка утечек: частный адрес в отчёте — ложная тревога.
function Test-PublicIp {
    param([string]$Ip)
    if (-not $Ip) { return $false }
    $s = $Ip.Trim()
    # события журнала повторяют одни и те же адреса тысячами
    if ($null -eq $script:PublicIpSeen) { $script:PublicIpSeen = @{} }
    if ($script:PublicIpSeen.ContainsKey($s)) { return $script:PublicIpSeen[$s] }
    $res = $false
    $parsed = $null
    # TryParse принимает и «1.2.3», и «0x7f.1» — адрес IPv4 только из четырёх чисел
    if ([System.Net.IPAddress]::TryParse($s, [ref]$parsed) -and
        ($parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or $s -match '^\d{1,3}(\.\d{1,3}){3}$')) {
        $res = Test-PublicIpAddress $parsed
    }
    if ($script:PublicIpSeen.Count -lt 50000) { $script:PublicIpSeen[$s] = $res }
    return $res
}

function Test-PublicIpAddress {
    param([System.Net.IPAddress]$A)
    $addr = $A
    if ($addr.IsIPv4MappedToIPv6) { $addr = $addr.MapToIPv4() }
    if ($null -eq $script:NonPublicNets) {
        # особые сети из реестров IANA, которые в интернет не выходят
        $script:NonPublicNets = @(foreach ($n in @(
                '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16', '172.16.0.0/12',
                '192.0.0.0/24', '192.0.2.0/24', '192.88.99.0/24', '192.168.0.0/16', '198.18.0.0/15',
                '198.51.100.0/24', '203.0.113.0/24', '224.0.0.0/4', '240.0.0.0/4',
                '::/128', '::1/128', '64:ff9b:1::/48', '100::/64', '2001:db8::/32',
                'fc00::/7', 'fe80::/10', 'fec0::/10', 'ff00::/8')) {
            $p = $n.Split('/')
            @{ b = [System.Net.IPAddress]::Parse($p[0]).GetAddressBytes(); len = [int]$p[1] }
        })
    }
    $b = $addr.GetAddressBytes()
    foreach ($net in $script:NonPublicNets) {
        if ($net.b.Length -ne $b.Length) { continue }
        $full = [int][math]::Floor($net.len / 8); $rest = $net.len % 8; $in = $true
        for ($i = 0; $i -lt $full; $i++) { if ($b[$i] -ne $net.b[$i]) { $in = $false; break } }
        if ($in -and $rest -gt 0) {
            $mask = (0xFF -shl (8 - $rest)) -band 0xFF
            if (($b[$full] -band $mask) -ne ($net.b[$full] -band $mask)) { $in = $false }
        }
        if ($in) { return $false }
    }
    return $true
}

# Журнал брандмауэра называет программу путём ядра: \device\harddiskvolume4\...
# Правилу брандмауэра нужен обычный путь с буквой диска — подбираем её перебором.
function ConvertFrom-DevicePath {
    param([string]$P)
    if (-not $P) { return '' }
    if ($P -match '^[A-Za-z]:\\') { return $P }
    $m = [regex]::Match($P, '^\\device\\harddiskvolume\d+\\(.+)$', 'IgnoreCase')
    if (-not $m.Success) { return '' }
    $rest = $m.Groups[1].Value
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        try {
            if (-not $d.IsReady -or $d.DriveType -ne 'Fixed') { continue }
            $cand = Join-Path $d.Name $rest
            if (Test-Path -LiteralPath $cand) { return $cand }
        } catch { }
    }
    return ''
}

function Get-MonitorStats {
    param([int]$Hours)
    $since = (Get-Date).AddHours(-$Hours)
    $events = @()
    # 5156 — брандмауэр РАЗРЕШИЛ соединение, 5157 — заблокировал. Раньше читались
    # только 5157, поэтому «кто отправляет» показывал одни отказы, а настоящие
    # исходящие соединения в список не попадали вовсе.
    $rd = Read-SecurityEvents -Ids @(5156, 5157) -Since $since -Max 8000
    $events = @($rd.events)
    $dns = @{}
    try { Get-DnsClientCache -ErrorAction SilentlyContinue | ForEach-Object { if ($_.Data -and -not $dns.ContainsKey($_.Data)) { $dns[$_.Data] = $_.Entry } } } catch { }
    $byProc = @{}; $byDest = @{}; $total = 0; $telemetryHits = 0; $blockedTotal = 0
    foreach ($ev in $events) {
        try {
            $x = [xml]$ev.ToXml()
            $data = @{}
            foreach ($n in $x.Event.EventData.Data) { $data[[string]$n.Name] = [string]$n.'#text' }
            if ($data['Direction'] -ne '%%14593') { continue }          # только исходящие
            $ip = $data['DestAddress']
            if (-not (Test-PublicIp $ip)) { continue }
            if ($ev.Id -eq 5157) { $blockedTotal++; continue }          # отказы считаем отдельно
            $full = [string]$data['Application']
            $app = if ($full) { ($full -split '\\')[-1] } else { '?' }
            $total++
            if ($byProc.ContainsKey($app)) { $byProc[$app].count++ } else {
                $byProc[$app] = @{ name=$app; count=1; raw=$full }
            }
            $key = $ip
            if ($byDest.ContainsKey($key)) { $byDest[$key].count++ } else {
                $dom = if ($dns.ContainsKey($ip)) { $dns[$ip] } else { '' }
                $byDest[$key] = @{ ip=$ip; domain=$dom; count=1; port=$data['DestPort'] }
            }
            if ($byDest[$key].domain -match $script:TelemetryDnsRegex) { $telemetryHits++ }
        } catch { }
    }
    # путь и состояние запрета выясняем только для тех, кого покажем
    $procList = @()
    foreach ($p in @($byProc.Values | Sort-Object { $_.count } -Descending | Select-Object -First 12)) {
        $path = ConvertFrom-DevicePath ([string]$p.raw)
        $procList += @{ name = $p.name; count = $p.count; path = $path
                        blocked = [bool]($path -and (Test-FwRule 'app' $path)) }
    }
    $destList = @($byDest.Values | Sort-Object { $_.count } -Descending | Select-Object -First 25)
    # впервые вышедшие в сеть — из записей слежения за сетью
    $newList = @()
    $ns = Load-Json 'net-apps.json'
    if ($ns -and $ns.recent) {
        foreach ($r in @($ns.recent | Select-Object -First 12)) {
            $newList += @{ name = "$($r.name)"; path = "$($r.path)"; time = "$($r.time)"; ip = "$($r.ip)"
                           blocked = [bool]("$($r.path)" -and (Test-FwRule 'app' "$($r.path)")) }
        }
    }
    return @{ enabled=(Get-MonitorEnabled); hours=$Hours; since=$since.ToString('yyyy-MM-dd HH:mm'); total=$total;
              telemetryHits=$telemetryHits; events=$events.Count; blocked=$blockedTotal
              byProcess=$procList; byDest=$destList; newApps=$newList
              netGuard=[bool](Get-ScheduledTask -TaskName $script:NetTask -ErrorAction SilentlyContinue)
              readError=$rd.error
              netGuardError=$(if ($ns -and $ns.readError) { "{0} ({1})" -f $ns.readError, $ns.readErrorTime } else { '' })
              firewallRules=@(Get-NetFirewallRule -Group $script:FwGroup -ErrorAction SilentlyContinue).Count }
}

# --- DNS-кэш: свидетельства обращений -------------------------------------- #
function Get-DnsEvidence {
    $list = @()
    try {
        $seen = @{}
        foreach ($r in (Get-DnsClientCache -ErrorAction SilentlyContinue)) {
            if ($r.Entry -match $script:TelemetryDnsRegex -and -not $seen.ContainsKey($r.Entry)) {
                $seen[$r.Entry] = $true
                $blocked = ($r.Data -eq '0.0.0.0' -or $r.Data -eq '::')
                $list += @{ name=$r.Entry; data=[string]$r.Data; blocked=$blocked }
            }
        }
    } catch { }
    return $list
}

# --- буфер телеметрии ------------------------------------------------------- #
# Что считается неотправленной телеметрией: очередь событий (EventStore.db и
# его журналы; у приложений — свой в TenantStorage), старые очереди *.rbs и
# трассировки *.etl. Скачанные настройки и папки не трогаем.
# ВАЖНО: в PowerShell 5.1 -Include вместе с -LiteralPath молча не работает.
# Раньше сюда попадало всё содержимое папки, включая сами папки: удалялись
# и настройки, а Remove-Item на непустой папке задавал вопрос «удалить с
# содержимым?» и без окна (файл «Для других ПК») ждал ответа вечно.
$script:BufferFileRx = '\.(rbs|etl)$|^EventStore\.db(-wal|-shm)?$'
function Get-BufferFiles {
    param([switch]$Strict)
    $ea = $(if ($Strict) { 'Stop' } else { 'SilentlyContinue' })
    return @(Get-ChildItem -LiteralPath $script:DiagDir -Recurse -Force -File -ErrorAction $ea |
             Where-Object { $_.Name -match $script:BufferFileRx })
}

function Get-BufferInfo {
    $size = -1; $files = 0
    try {
        $items = @(Get-BufferFiles -Strict)
        $files = $items.Count
        $sum = ($items | Measure-Object -Property Length -Sum).Sum
        $size = if ($sum) { [math]::Round($sum / 1MB, 2) } else { 0 }
    } catch { $size = -1 }
    return @{ mb=$size; files=$files; path=$script:DiagDir }
}

# Раньше перед удалением программа забирала себе всю системную папку
# Diagnosis (takeown /R) и давала администраторам полный доступ ко всему
# внутри (icacls /T) — и так это и оставалось: исходные владелец и права
# папки, которой распоряжается служба телеметрии, не возвращались. Теперь
# права не трогаются вовсе. Что администратор удалить может, удаляется
# сразу; остальное удаляет короткая задача от имени системы, у которой
# доступ к этой папке и так есть. Итог проверяется: что осталось, сказано.
$script:DiagDirExpected = Join-Path $env:ProgramData 'Microsoft\Diagnosis'

# Что делает задача от имени системы: удаляет те же файлы, что
# Get-BufferFiles, и пишет итог в файл — сколько нашла, удалила, не смогла
# удалить и сколько осталось, а если папку не прочитала — почему. Код
# завершения задачи сам по себе ничего не доказывает: прежняя проверка через
# dir при ошибке доступа выглядела бы как «файлов не осталось».
function Get-BufferSystemScript {
    param([string]$Dir, [string]$ResultFile)
    $q = { param($s) "'" + ("$s" -replace "'", "''") + "'" }
    return (@(
        "`$ErrorActionPreference = 'Stop'"
        ("`$d = {0}; `$rx = {1}; `$out = {2}" -f (& $q $Dir), (& $q $script:BufferFileRx), (& $q $ResultFile))
        "`$res = @{ found = 0; deleted = 0; failed = 0; left = -1; listError = ''; errors = @() }"
        "try { `$fs = @(Get-ChildItem -LiteralPath `$d -Recurse -Force -File | Where-Object { `$_.Name -match `$rx }) } catch { `$fs = @(); `$res.listError = `"`$(`$_.Exception.Message)`" }"
        "`$res.found = `$fs.Count"
        # какие файлы не удалились и почему — только имя, без пути, и не больше десяти
        "foreach (`$f in `$fs) { try { Remove-Item -LiteralPath `$f.FullName -Force -ErrorAction Stop; `$res.deleted++ } catch { `$res.failed++; if (`$res.errors.Count -lt 10) { `$res.errors += @{ file = `$f.Name; error = `"`$(`$_.Exception.Message)`" } } } }"
        "if (-not `$res.listError) { try { `$res.left = @(Get-ChildItem -LiteralPath `$d -Recurse -Force -File | Where-Object { `$_.Name -match `$rx }).Count } catch { `$res.listError = `"`$(`$_.Exception.Message)`" } }"
        "Set-Content -LiteralPath `$out -Value (`$res | ConvertTo-Json -Compress -Depth 4) -Encoding UTF8"
        "if (`$res.left -eq 0 -and -not `$res.listError) { exit 0 } else { exit 1 }"
    ) -join "`r`n")
}

# Задача от имени системы и её итог: success — файлов не осталось; partial —
# часть удалена, часть осталась; failed — не удалила ничего, папку не
# прочитала или итога не оставила. Итог кладётся в защищённую папку
# программы: писать туда могут только система и администраторы.
function Invoke-BufferSystemPurge {
    param([string]$Dir)
    if (-not (Assert-SafeRoot)) { return @{ status = 'failed'; found = 0; deleted = 0; failed = 0; left = -1; why = 'папка ProgramData\Win11Privacy не защищена — итогу задачи там не место' } }
    # Сценарий кладётся файлом в ту же защищённую папку: подменить его до
    # запуска может только администратор, а аргументы задачи остаются короткими
    # (раньше весь сценарий шёл в них строкой на две с половиной тысячи знаков).
    $id = [guid]::NewGuid().ToString('N')
    $rf = Join-Path $script:SafeRoot ('buffer-result-' + $id + '.json')
    $sf = Join-Path $script:SafeRoot ('buffer-purge-' + $id + '.ps1')
    $res = $null
    try {
        Set-Content -LiteralPath $sf -Value (Get-BufferSystemScript $Dir $rf) -Encoding UTF8 -ErrorAction Stop
        $null = Invoke-OneShotTask 'Win11Privacy buffer' -Execute $script:PsExe -Arguments ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $sf + '"') -AsSystem -Minutes 5
        if (Test-Path -LiteralPath $rf) { $res = Get-Content -LiteralPath $rf -Raw -Encoding UTF8 | ConvertFrom-Json }
    } catch { $res = $null }
    finally { Remove-Item -LiteralPath $rf, $sf -Force -ErrorAction SilentlyContinue }
    if (-not $res) { return @{ status = 'failed'; found = 0; deleted = 0; failed = 0; left = -1; why = 'задача от имени системы не оставила итога' } }
    $left = [int]$res.left
    $st = $(if ("$($res.listError)" -or $left -lt 0) { 'failed' } elseif ($left -eq 0) { 'success' } elseif ([int]$res.deleted -gt 0) { 'partial' } else { 'failed' })
    $errs = @(@($res.errors) | Where-Object { $_ } | ForEach-Object { @{ file = "$($_.file)"; error = "$($_.error)" } })
    return @{ status = $st; found = [int]$res.found; deleted = [int]$res.deleted; failed = [int]$res.failed; left = $left; why = "$($res.listError)"; errors = $errs }
}

function Purge-Buffer {
    Write-Section 'Неотправленная телеметрия'
    # чистится только эта папка: путь сверяется, а не берётся на веру
    $dir = [IO.Path]::GetFullPath($script:DiagDir).TrimEnd('\')
    if ($dir -ne [IO.Path]::GetFullPath($script:DiagDirExpected).TrimEnd('\')) {
        Write-Log ("   [!] папка буфера не та, что ожидалась ({0}) -- ничего не удалено" -f $dir); $script:Failures++; return
    }
    $info = Get-BufferInfo
    if ($info.mb -eq 0 -and $info.files -eq 0) { Write-Log '   [-] буфер пуст'; return }
    if ($DryRun) { Write-Log ("   [тест] будет стёрто ~{0} МБ ({1} файлов)" -f $info.mb, $info.files); return }
    $svc = Get-Service -Name DiagTrack -ErrorAction SilentlyContinue
    $wasRunning = ($svc -and $svc.Status -eq 'Running')
    if ($wasRunning) { Stop-Service -Name DiagTrack -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 800 }
    # Сначала — с правами администратора. Чего он удалить не может, тех
    # файлов не перечисляем по одному как ошибки: их следом удаляет система,
    # и итог говорится один раз, ниже.
    $denied = 0
    foreach ($f in @(Get-BufferFiles)) {
        try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop } catch { $denied++ }
    }
    $sys = $null
    if ($info.mb -lt 0 -or @(Get-BufferFiles).Count -gt 0) {
        if ($denied -gt 0) { Write-Log ("   [i] файлов, которые администратору не отдали: {0} -- их удаляет задача от имени системы" -f $denied) }
        else { Write-Log '   [i] папку буфера администратору не дали даже просмотреть -- её очищает задача от имени системы' }
        $sys = Invoke-BufferSystemPurge $dir
    }
    if ($wasRunning -and $svc.StartType -ne 'Disabled') { Start-Service -Name DiagTrack -ErrorAction SilentlyContinue }
    $after = Get-BufferInfo
    if ($after.mb -ge 0 -and $info.mb -ge 0) {
        # папку видно — итог считаем сами, а не со слов задачи
        $gone = $info.files - $after.files
        if ($gone -gt 0) { Write-Log ("   [+] стёрто файлов: {0}, {1} МБ" -f $gone, [math]::Round([math]::Max(0, $info.mb - $after.mb), 2)); $script:Changes++ }
        if ($after.files -gt 0) { Write-Log ("   [!] осталось файлов: {0} -- Windows их держит; после перезагрузки можно повторить" -f $after.files); $script:Failures++ }
    } elseif ($sys) {
        switch ($sys.status) {
            'success' { Write-Log ("   [+] буфер очищен от имени системы: удалено файлов {0}, не осталось ни одного" -f $sys.deleted); $script:Changes++ }
            'partial' { Write-Log ("   [!] от имени системы удалено файлов {0}, осталось {1} -- Windows их держит" -f $sys.deleted, $sys.left); $script:Failures++ }
            default   { Write-Log ("   [!] очистить буфер от имени системы не удалось: {0}" -f $(if ($sys.why) { $sys.why } else { "удалено {0} из {1}, осталось {2}" -f $sys.deleted, $sys.found, $sys.left })); $script:Failures++ }
        }
    } else {
        Write-Log '   [!] очистить буфер не удалось или проверить это нечем (нет доступа)'; $script:Failures++
    }
    # что именно не удалилось у системы и почему — для разбора на разных сборках
    if ($sys -and @($sys.errors).Count -gt 0) {
        foreach ($e in @(@($sys.errors) | Select-Object -First 3)) { Write-Log ("       {0}: {1}" -f $e.file, $e.error) }
    }
}
