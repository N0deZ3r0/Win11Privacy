
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

function Get-IdCrlRoots {
    $roots = New-Object System.Collections.Generic.List[object]
    foreach ($r in $script:IdCrlRoots) { $roots.Add($r) }
    $me = ''
    try { $me = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value } catch { }
    # Список подключённых кустов не прочитался — копии номера у других
    # вошедших пользователей не искались, и это записано. Раньше ошибка
    # глоталась, и «копий нет» говорилось, не заглянув к ним.
    $names = @()
    try { $names = @(Get-GdidHiveNames) } catch { $script:GdidUnreadable.Add('Registry::HKEY_USERS') }
    foreach ($sid in $names) {
        if ($sid -notmatch '^S-1-5-21-[\d-]+$' -or $sid -eq $me) { continue }
        $roots.Add(@{ who = 'other'; path = "Registry::HKEY_USERS\$sid\Software\Microsoft\IdentityCRL" })
    }
    return $roots.ToArray()
}

# Профили пользователей, которые сейчас не вошли в Windows: их копии номера
# не проверяются (куст не подключён). Не прочитался список профилей или
# кустов — сколько их, неизвестно: место записывается как непрочитанное
# (раньше ответ был «0», то есть «проверены все»).
function Get-UncheckedProfiles {
    $loaded = @()
    try { $loaded = @(Get-GdidHiveNames) } catch { $script:GdidUnreadable.Add('Registry::HKEY_USERS'); return 0 }
    $plPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $listed = @()
    $pl = $null
    try {
        $pl = Open-RegKeyRead $plPath
        if ($null -eq $pl) { $script:GdidUnreadable.Add($plPath); return 0 }
        $listed = @($pl.GetSubKeyNames())
    } catch { $script:GdidUnreadable.Add($plPath); return 0 }
    finally { if ($null -ne $pl) { $pl.Close() } }
    $n = 0
    foreach ($sid in $listed) {
        if ($sid -match '^S-1-5-21-[\d-]+$' -and $loaded -notcontains $sid) { $n++ }
    }
    return $n
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
        return 'removed'
    } catch { return 'denied' } finally { if ($key) { $key.Close() } }
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
        if ($errs.Count -eq 0) { return @{ ok = $true; found = $false; running = $false; start = ''; error = '' } }
        return @{ ok = $false; found = $false; running = $false; start = ''; error = "$($errs[0])" }
    }
    $s = @($s)[0]
    $run = ("$($s.Status)" -ne 'Stopped')
    try { $st = "$($s.StartType)" }
    catch { return @{ ok = $false; found = $true; running = $run; start = ''; error = $_.Exception.Message } }
    return @{ ok = $true; found = $true; running = $run; start = $st; error = '' }
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
        param($Info)
        $v = Get-SvcScmView $Info.name
        $Info['running'] = [bool]$v.running
        $Info['scmStart'] = "$($v.start)"
        if (-not $v.ok) { $problems.Add(("{0}: диспетчер служб не ответил ({1})" -f $Info.name, $v.error)) }
        if ($Info.state -eq 'ReadError') { $problems.Add(("{0}: тип запуска не прочитался ({1})" -f $Info.name, $Info.error)) }
        $Info
    }
    $out = New-Object System.Collections.Generic.List[object]
    $allOff = $true; $settled = $true; $on = $false
    foreach ($n in $script:GdidSvcNames) {
        $i = & $look (Get-SvcStartInfo $n)
        if ($i.state -in @('Boot', 'System', 'Automatic', 'Manual')) { $on = $true }
        if ($i.state -notin @('Disabled', 'Missing')) { $allOff = $false }
        if ($i.running) { $settled = $false }
        if ($i.state -eq 'Disabled' -and $i.scmStart -and $i.scmStart -ne 'Disabled') { $settled = $false }
        if ($n -eq 'CDPUserSvc') {
            $inst = Get-GdidUserSvcInstances
            if (-not $inst.ok) { $problems.Add(("копии CDPUserSvc не перечислились: {0}" -f $inst.error)) }
            $il = New-Object System.Collections.Generic.List[object]
            foreach ($nm in @($inst.names)) {
                $ii = & $look (Get-SvcStartInfo $nm)
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

# Где лежат копии номера. Только чтение.
function Get-GdidCopies {
    $found = New-Object System.Collections.Generic.List[object]
    $script:GdidUnreadable.Clear()
    $seenSystem = $false
    $me = ''
    try { $me = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value } catch { }
    # Каждое место, куда Windows не пустила, записывается само по себе: «не
    # нашли» там — не то же самое, что «нет». Раньше так отмечалось только всё
    # хранилище целиком, а закрытые ключи внутри (свойства, личности, кэш)
    # молча считались пустыми.
    $open = {
        param($path)
        try { return (Get-Item -LiteralPath $path -ErrorAction Stop) }
        catch [System.Management.Automation.ItemNotFoundException] { return $null }
        catch { $script:GdidUnreadable.Add("$path"); return $null }
    }
    $list = {
        param($path)
        $ev = $null
        $items = @(Get-ChildItem -LiteralPath $path -ErrorAction SilentlyContinue -ErrorVariable ev)
        foreach ($e in @($ev)) {
            if ($e.Exception -is [System.Management.Automation.ItemNotFoundException]) { continue }
            # закрытый подключ называет себя сам; иначе — то, что перечисляли
            $script:GdidUnreadable.Add($(if ($e.TargetObject -is [string] -and $e.TargetObject) { "$($e.TargetObject)" } else { "$path" }))
        }
        $items
    }
    foreach ($r in (Get-IdCrlRoots)) {
        if (-not (& $open $r.path)) { continue }
        # .DEFAULT и S-1-5-18 — один и тот же куст SYSTEM: считаем его один раз
        if ($r.who -eq 'system') { if ($seenSystem) { continue }; $seenSystem = $true }
        $ek = & $open "$($r.path)\ExtendedProperties"
        if ($ek -and "$($ek.GetValue('LID'))") { $found.Add(@{ who = $r.who; place = 'lid'; puid = "$($ek.GetValue('LID'))" }) }
        $pk = & $open "$($r.path)\Immersive\production\Property"
        if ($pk) {
            foreach ($vn in @($pk.GetValueNames())) {
                if ($vn -match $script:DevicePuidRegex) { $found.Add(@{ who = $r.who; place = 'property'; puid = $vn }) }
            }
        }
        foreach ($tk in @(& $list "$($r.path)\Immersive\production\Token")) {
            $tn = @($tk.GetValueNames())
            if ($tn -contains 'DeviceId' -or $tn -contains 'DeviceTicket') {
                $found.Add(@{ who = $r.who; place = 'token'; puid = "$($tk.GetValue('DeviceId'))" })
            }
        }
        foreach ($sk in @(& $list "$($r.path)\DeviceIdentities\production")) {
            if ($sk.PSChildName -eq 'Logs') { continue }
            # Чья личность: в кусте пользователя — его; в системном — по SID
            # раздела. Раньше любая S-1-5-21-* шла как «своя», и копии другого
            # пользователя считались копиями того, кто смотрит.
            $idWho = $(if ($r.who -ne 'system') { $r.who } elseif ($sk.PSChildName -notlike 'S-1-5-21-*') { 'system' }
                       elseif ($sk.PSChildName -eq $me) { 'user' } else { 'other' })
            foreach ($ik in @(& $list $sk.PSPath)) {
                $found.Add(@{ who = $idWho; place = 'identity'; puid = "$($ik.GetValue('DeviceId'))" })
            }
        }
    }
    foreach ($nk in @(& $list $script:IdCrlNegCache)) {
        if ($nk.PSChildName -match '^(0018[0-9A-Fa-f]{12})_') { $found.Add(@{ who = 'system'; place = 'cache'; puid = $Matches[1] }) }
    }
    return $found.ToArray()
}

# Опись копий номера с ответом, можно ли ей верить. state: Found — копии есть;
# NotFound — копий нет и проверено всё; Unverified — копий не нашлось, но часть
# мест не прочиталась или профили других пользователей не проверялись. «Не
# нашли» там, куда не пустили, — не то же самое, что «нет».
function Get-GdidScan {
    $copies = @(Get-GdidCopies)
    $unchecked = [int](Get-UncheckedProfiles)
    $unread = @($script:GdidUnreadable | Select-Object -Unique)
    $state = $(if ($copies.Count -gt 0) { 'Found' } elseif ($unread.Count -gt 0 -or $unchecked -gt 0) { 'Unverified' } else { 'NotFound' })
    return @{ copies = $copies; unreadable = $unread; unchecked = $unchecked; state = $state }
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

# Учётная запись с этим SID — учётная запись Microsoft. Не локальная (домен,
# Entra ID) или модуля учётных записей нет — судим по профилю: есть в нём
# учётная запись Microsoft — считаем, что вход через неё. Не прочиталось —
# тоже «да»: осторожная сторона, запрет выдачи тогда не ставится.
function Test-MsaAccount {
    param([string]$Sid, [string]$Root)
    try {
        $u = Get-LocalUser -SID $Sid -ErrorAction Stop
        return ("$($u.PrincipalSource)" -eq 'MicrosoftAccount')
    } catch { }
    $has = Test-GdidKeyHasChildren "$Root\SOFTWARE\Microsoft\IdentityCRL\UserExtendedProperties"
    return ($has -ne $false)
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
function Get-OtherMsaAccounts {
    $skip = @(@(Get-GdidUserHiveRoots) | ForEach-Object { "$($_.sid)" })
    try { return @(Get-LocalUser -ErrorAction Stop | Where-Object { "$($_.PrincipalSource)" -eq 'MicrosoftAccount' -and $skip -notcontains "$($_.SID)" } | ForEach-Object { "$($_.Name)" }) }
    catch { return @() }
}

# Компьютер организации: там номер устройства связан с её учётной записью,
# и трогать его — сломать вход на работе. Встроенные «поставщики» Local, Deploy
# и Cloud Authority есть на любом домашнем компьютере — их не считаем.
# Не удалось проверить — тоже отказ: раньше ошибка WMI или чтения реестра
# глоталась, и компьютер организации с неисправным WMI считался домашним.
# Считается один раз за запуск.
$script:GdidManagedCache = $null
function Get-ManagedReason {
    if ($null -ne $script:GdidManagedCache) { return $script:GdidManagedCache }
    $script:GdidManagedCache = Get-ManagedReasonNow
    return $script:GdidManagedCache
}

function Get-ManagedReasonNow {
    $unknown = 'не удалось проверить, принадлежит ли компьютер организации'
    try { if ((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain) { return 'компьютер в домене организации' } }
    catch { return $unknown }
    $aad = Test-GdidKeyHasChildren 'HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo'
    if ($null -eq $aad) { return $unknown }
    if ($aad) { return 'компьютер подключён к Entra ID организации' }
    # рабочая или учебная учётная запись — у того, кто сидит за компьютером,
    # и у самого движка (раньше смотрелся только HKCU движка)
    foreach ($h in @(Get-GdidUserHiveRoots)) {
        $wp = Test-GdidKeyHasChildren "$($h.root)\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin\JoinInfo"
        if ($null -eq $wp) { return $unknown }
        if ($wp) { return 'в Windows добавлена рабочая или учебная учётная запись' }
    }
    $en = $null
    try {
        $en = Open-RegKeyRead 'HKLM:\SOFTWARE\Microsoft\Enrollments'
        if ($null -eq $en) { return '' }
        foreach ($sub in @($en.GetSubKeyNames())) {
            $ek = $en.OpenSubKey($sub, $false)
            if ($null -eq $ek) { continue }
            try {
                $prov = "$($ek.GetValue('ProviderID'))"
                if ($prov -and $prov -notin @('Local Authority', 'Deploy Authority', 'Cloud Authority') -and "$($ek.GetValue('EnrollmentState'))" -eq '1') {
                    return 'компьютер под управлением организации (MDM)'
                }
            } finally { $ek.Close() }
        }
    } catch { return $unknown }
    finally { if ($null -ne $en) { $en.Close() } }
    return ''
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
        # тип запуска не прочитался — вернуть его потом было бы нечем
        if ("$($entry.old)" -notmatch '^[0-4]$') { return @{ ok = $true; changed = $false; entry = $null; why = 'тип запуска wlidsvc не прочитался -- на время стирания она не отключается' } }
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
# стирание всё равно считалось успешным. Возвращает то, что не вернулось.
# $Wlid — ответ Disable-GdidWlid.
function Restore-GdidServices {
    param([string[]]$Running, $Wlid)
    $bad = New-Object System.Collections.Generic.List[string]
    $w = Restore-GdidWlid $Wlid
    if (-not $w.ok) { $bad.Add('wlidsvc (тип запуска)'); Write-Log ("   [!] тип запуска wlidsvc не вернулся: {0}" -f $w.why) }
    foreach ($n in @($Running)) {
        if (-not $n) { continue }
        try {
            Start-Service -Name $n -ErrorAction Stop -WarningAction SilentlyContinue
            (Get-Service -Name $n -ErrorAction Stop).WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
        } catch { $bad.Add($n) }
    }
    return $bad.ToArray()
}

function Stop-ServiceWait {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
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

# Шаг «реестр»: сам номер, его метка, билеты приложений, личности, кэш. У
# каждой записи свой ответ: убрана, не было или Windows не дала.
# state: Clean (что было — убрано), NotFound (ничего не было), Partial,
# AccessDenied (не убрано ничего, Windows не дала).
function Remove-GdidRegistryCopies {
    $st = @{ removed = 0; absent = 0; denied = 0; deniedAt = (New-Object System.Collections.Generic.List[string]) }
    $note = { param($res, $where) $st[$res]++; if ($res -eq 'denied') { $st.deniedAt.Add($where) } }
    foreach ($r in (Get-IdCrlRoots)) {
        if (-not (Test-Path -LiteralPath $r.path)) { continue }
        & $note (Remove-RegStatus "$($r.path)\ExtendedProperties" 'LID') "$($r.path)\ExtendedProperties"
        $pk = "$($r.path)\Immersive\production\Property"
        try {
            foreach ($vn in @((Get-Item -LiteralPath $pk -ErrorAction Stop).GetValueNames())) {
                if ($vn -match $script:DevicePuidRegex) { & $note (Remove-RegStatus $pk $vn) $pk }
            }
        } catch [System.Management.Automation.ItemNotFoundException] { }
        catch { & $note 'denied' $pk }
        $tev = $null
        $tks = @(Get-ChildItem -LiteralPath "$($r.path)\Immersive\production\Token" -ErrorAction SilentlyContinue -ErrorVariable tev)
        foreach ($e in @($tev)) {
            if (-not ($e.Exception -is [System.Management.Automation.ItemNotFoundException])) { & $note 'denied' "$($r.path)\Immersive\production\Token"; break }
        }
        foreach ($tk in $tks) {
            foreach ($vn in @('DeviceId', 'DeviceTicket')) { & $note (Remove-RegStatus $tk.PSPath $vn) "$($tk.PSPath)" }
        }
        & $note (Remove-RegStatus "$($r.path)\DeviceIdentities\production") "$($r.path)\DeviceIdentities"
    }
    # Кэш, который не перечислился, — тоже «не дала»: раньше ошибка здесь
    # глоталась, и закрытые записи кэша выглядели отсутствующими
    $nev = $null
    $negs = @(Get-ChildItem -LiteralPath $script:IdCrlNegCache -ErrorAction SilentlyContinue -ErrorVariable nev)
    foreach ($e in @($nev)) {
        if (-not ($e.Exception -is [System.Management.Automation.ItemNotFoundException])) { & $note 'denied' $script:IdCrlNegCache; break }
    }
    foreach ($nk in $negs) {
        if ($nk.PSChildName -match '^0018[0-9A-Fa-f]{12}_') { & $note (Remove-RegStatus $nk.PSPath) "$($nk.PSPath)" }
    }
    Write-Log ("   [+] записи номера в реестре: убрано {0}, не было {1}" -f $st.removed, $st.absent)
    if ($st.denied -gt 0) {
        Write-Log ("   [!] Windows не дала убрать: {0}" -f $st.denied)
        foreach ($w in @($st.deniedAt | Select-Object -Unique -First 5)) { Write-Log ("       {0}" -f ($w -replace '^Microsoft\.PowerShell\.Core\\Registry::', '')) }
    }
    $st['state'] = $(if ($st.denied -eq 0) { if ($st.removed -gt 0) { 'Clean' } else { 'NotFound' } } elseif ($st.removed -gt 0) { 'Partial' } else { 'AccessDenied' })
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
function Clear-GdidCdpCache {
    $dir = Convert-ToSessionPath $script:CdpCache
    $others = @(@(Get-GdidCredUsers) | Where-Object { -not $_.session }).Count
    if ($others -gt 0) { Write-Log ("   [i] кэш платформы подключённых устройств других пользователей, которые сейчас в Windows, не чистится: {0}" -f $others) }
    $null = Clear-Folder $dir 'кэш платформы подключённых устройств'
    if (-not (Test-Path -LiteralPath $dir)) { return @{ state = 'NotFound'; left = 0; dir = $dir; others = $others } }
    $cev = $null
    $left = @(Get-ChildItem -LiteralPath $dir -Force -Recurse -File -ErrorAction SilentlyContinue -ErrorVariable cev)
    if ($left.Count -gt 0) {
        Write-Log ("   [!] в кэше платформы подключённых устройств осталось файлов: {0} -- Windows их не отдала" -f $left.Count)
        foreach ($f in @($left | Select-Object -First 3)) { Write-Log ("       {0}" -f $f.FullName) }
        return @{ state = 'Partial'; left = $left.Count; dir = $dir; others = $others }
    }
    if (@($cev | Where-Object { $_ -and -not ($_.Exception -is [System.Management.Automation.ItemNotFoundException]) }).Count -gt 0) {
        Write-Log '   [!] кэш платформы подключённых устройств не удалось проверить (нет доступа) -- очищен ли он, неизвестно'
        return @{ state = 'Unverified'; left = 0; dir = $dir; others = $others }
    }
    return @{ state = 'Clean'; left = 0; dir = $dir; others = $others }
}

# Стирает «личность» устройства и все известные копии номера. Пока сервер
# выдачи открыт, Windows при следующем обращении получит новый номер — это
# смена. Под запретом выдачи — номера не станет вовсе.
#
# Порядок: ограничения → как были службы (wlidsvc — в журнал отката) →
# остановка служб → учётные данные у пользователей → у системы → реестр →
# кэш платформы подключённых устройств → проверка → службы как были → итог.
# Проверка — пока службы стоят: раньше она шла после их возврата, и
# поднявшаяся wlidsvc успевала завести новый номер, а он считался «копией,
# которую Windows не отдала». Службы возвращаются в finally: исключение
# посреди стирания раньше оставляло их остановленными, а wlidsvc — отключённой.
# Итог каждого шага и общий — в $script:GdidWipeResult; state: Clean,
# NotFound (копий и не было), Partial, Failed (ничего не стёрто), AccessDenied
# (Windows не дала убрать ни одной копии), Unverified (копий не нашлось, но
# проверено не всё). Успех ($true) — только Clean и NotFound.
$script:GdidWipeResult = $null

function Invoke-GdidWipe {
    $res = @{ state = 'Failed'; before = 0; after = 0; removed = 0; denied = 0; unreadable = 0; unchecked = 0
              stages = [ordered]@{}; notBack = @(); errors = (New-Object System.Collections.Generic.List[string]) }
    $script:GdidWipeResult = $res
    $why = Get-ManagedReason
    if ($why) {
        Write-Log ("   [!] номер устройства не тронут: {0}. На таком компьютере он связан с учётной записью организации." -f $why)
        $res.stages['restrictions'] = 'refused'
        $script:Failures++; return $false
    }
    $res.stages['restrictions'] = 'ok'
    $before = @((Get-GdidScan).copies)
    $res.before = $before.Count
    if ($DryRun) {
        Write-Log ("   [тест] копий номера устройства: {0} -- будут стёрты вместе с «личностью» устройства" -f $before.Count)
        $res.state = 'DryRun'; return $true
    }
    Write-Log ("   найдено копий номера: {0}" -f $before.Count)

    # Службы держат номер в памяти и вернули бы его на место. DoSvc тоже:
    # именно она сообщает номер, и посреди стирания могла его держать
    $wasRunning = @(Get-Service -ErrorAction SilentlyContinue |
                    Where-Object { ($_.Name -in @('wlidsvc', 'CDPSvc', 'DoSvc') -or $_.Name -like 'CDPUserSvc_*') -and $_.Status -eq 'Running' } |
                    ForEach-Object { $_.Name })
    $wlid = $null
    try { $wlid = Disable-GdidWlid } catch { $wlid = @{ ok = $false; changed = $false; entry = $null; why = $_.Exception.Message } }
    if (-not $wlid.ok) {
        Write-Log ("   [!] номер устройства не тронут: {0} -- службу учётных записей Microsoft нельзя отключить на время стирания, не записав, как было." -f $wlid.why)
        $res.stages['services'] = 'refused'
        $script:Failures++; return $false
    }
    if ($wlid.why) { Write-Log ("   [i] {0}" -f $wlid.why) }
    $res.stages['services'] = 'saved'
    $notBackMsg = '   [!] службы не вернулись в прежнее состояние: {0}. Перезагрузка компьютера вернёт их.'
    $fails = 0
    $aborted = ''
    $verify = $null
    $reg = @{ removed = 0; denied = 0 }
    $cdp = @{ others = 0 }
    try {
        if (-not (Stop-ServiceWait 'wlidsvc')) {
            Write-Log '   [!] служба учётных записей Microsoft (wlidsvc) занята и не остановилась. Закройте Магазин и Параметры и повторите или перезагрузите компьютер. Ничего не стёрто.'
            $aborted = 'stop'
        } else {
            # Служба, которая не остановилась, держит номер в памяти и записала
            # бы его обратно посреди стирания. Тогда не стираем ничего и
            # возвращаем всё как было.
            $stuck = @($wasRunning | Where-Object { $_ -ne 'wlidsvc' -and -not (Stop-ServiceWait $_) })
            if ($stuck.Count -gt 0) {
                Write-Log ("   [!] служба не остановилась: {0}. Она держит номер устройства и вернула бы его на место. Ничего не стёрто -- повторите позже или после перезагрузки." -f ($stuck -join ', '))
                $aborted = 'stop'
            }
        }
        $res.stages['stop'] = $(if ($aborted) { 'Failed' } else { 'ok' })
        if (-not $aborted) {
            # 1. учётные данные «личности» устройства — у пользователей и у системы
            $cu = Clear-GdidUserCreds
            $res.stages['userCredentials'] = $cu.state
            $fails += [int]$cu.fails
            $sysCmd = (@($script:GdidCredSystem | ForEach-Object { 'cmdkey /delete:' + $_ + ' >nul 2>&1' }) -join ' & ') + ' & ' + (Get-CredCheckCmd $script:GdidCredSystem)
            if (Invoke-OneShotTask 'Win11Privacy GDID system' $sysCmd -AsSystem) { Write-Log '   [+] учётные данные устройства у системы убраны'; $res.stages['systemCredentials'] = 'Clean' }
            else { Write-Log '   [!] учётные данные устройства у системы убрать не удалось'; $fails++; $res.stages['systemCredentials'] = 'Failed' }
            # 2. копии номера в реестре
            $reg = Remove-GdidRegistryCopies
            $res.stages['registry'] = $reg.state
            if ([int]$reg.denied -gt 0) { $fails++ }
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
        $notBack = @()
        try { $notBack = @(Restore-GdidServices $wasRunning $wlid) }
        catch { $notBack = @(('службы (возврат прервался: {0})' -f $_.Exception.Message)) }
        $res.notBack = $notBack
        $res.stages['restore'] = $(if ($notBack.Count -gt 0) { 'Failed' } else { 'ok' })
        if ($notBack.Count -gt 0) { Write-Log ($notBackMsg -f ($notBack -join ', ')) }
    }
    $res.removed = [int]$reg.removed; $res.denied = [int]$reg.denied
    if ($aborted -eq 'stop') { $res.state = 'Failed'; $script:Failures++; return $false }
    if ($aborted -eq 'exception') {
        # что успело стереться до сбоя, неизвестно наверняка
        $res.state = $(if ($res.removed -gt 0) { 'Partial' } else { 'Failed' })
        Write-Log '   [!] стирание прошло не полностью -- повторите его; службы возвращены, как были'
        $script:Failures++; return $false
    }
    if ($notBack.Count -gt 0) { $fails++ }

    $after = @($verify.copies)
    $unread = @($verify.unreadable)
    $unchecked = [int]$verify.unchecked + [int]$cdp.others
    $res.after = $after.Count; $res.unreadable = $unread.Count; $res.unchecked = $unchecked
    if ($after.Count -gt 0) { Write-Log ("   [!] осталось копий номера: {0} -- Windows их не отдала" -f $after.Count) }
    if ($unread.Count -gt 0) {
        # «не нашли» там, куда не пустили, — не то же самое, что «стёрто»
        Write-Log ("   [!] не удалось проверить мест: {0} (нет доступа) -- стёрто ли там, неизвестно" -f $unread.Count)
        foreach ($u in @($unread | Select-Object -First 3)) { Write-Log ("       {0}" -f ($u -replace '^Microsoft\.PowerShell\.Core\\Registry::', '')) }
    }
    if ([int]$verify.unchecked -gt 0) {
        Write-Log ("   [i] профили пользователей, которые сейчас не вошли в Windows, не проверялись: {0}. У тех из них, кто входит через учётную запись Microsoft, может остаться прежний номер." -f $verify.unchecked)
    }
    # Успех — только когда прошло всё: копий нет, учётные данные убраны, кэш
    # пуст, службы вернулись и проверено всё. Раньше «стёрт отовсюду» писалось
    # и тогда, когда что-то из этого не вышло, а непроверенные профили и места
    # без доступа успеху не мешали.
    $state = $(if ($fails -eq 0 -and $after.Count -eq 0 -and $unread.Count -eq 0 -and $unchecked -eq 0) { if ($before.Count -eq 0 -and $res.removed -eq 0) { 'NotFound' } else { 'Clean' } }
               elseif ($fails -eq 0 -and $after.Count -eq 0) { 'Unverified' }
               elseif ($after.Count -gt 0 -and $res.removed -eq 0 -and $res.denied -gt 0) { 'AccessDenied' }
               else { 'Partial' })
    $res.state = $state
    $ok = ($state -in @('Clean', 'NotFound'))
    if ($state -eq 'Clean') { Write-Log '   [+] номер устройства стёрт отовсюду, где программа его ищет'; $script:Changes++ }
    elseif ($state -eq 'NotFound') { Write-Log '   [+] копий номера не нашлось -- проверено всё, где программа его ищет' }
    else {
        if ($state -eq 'Unverified') { Write-Log '   [!] там, где программа смогла проверить, копий номера не осталось, но проверено не всё -- см. выше' }
        elseif ($after.Count -eq 0) { Write-Log '   [!] копий номера в реестре не осталось, но стирание прошло не полностью -- см. выше' }
        $script:Failures++
    }
    return $ok
}

# «Вернуть как было», службы: тип запуска — из журнала отката, ровно для тех
# служб, которые меняла программа (wlidsvc — если её оставило отключённой
# прерванное стирание). result: restored, notChanged (программа не меняла),
# failed. Раньше любой отказ — журналу нельзя верить, тип запуска не
# вернулся — назывался «программа её не меняла» и ошибкой не считался.
function Restore-GdidServiceStarts {
    $out = New-Object System.Collections.Generic.List[object]
    $jf = Read-JournalFile -ReadOnly
    $have = @{}
    if ($jf.trusted) { foreach ($it in @($jf.items)) { $have[(Get-JournalKey (ConvertTo-Fields $it))] = $true } }
    foreach ($n in @($script:GdidSvcNames + 'wlidsvc')) {
        $key = $(if ($n -eq 'wlidsvc') { 'svc|wlidsvc' } else { ("reg|HKLM:\SYSTEM\CurrentControlSet\Services\{0}|Start" -f $n).ToLowerInvariant() })
        if (-not $jf.trusted) { $out.Add(@{ name = $n; result = 'failed'; error = 'журналу отката нельзя верить: подпись не сошлась или он не прочитался' }); continue }
        if (-not $have.ContainsKey($key)) { $out.Add(@{ name = $n; result = 'notChanged'; error = '' }); continue }
        $r = Restore-ChangeKey $key
        if ($r.ok) { $out.Add(@{ name = $n; result = 'restored'; error = '' }) }
        else { $out.Add(@{ name = $n; result = 'failed'; error = "$($r.error)" }) }
    }
    return $out.ToArray()
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
    $bring = {
        param([string]$Svc, [string]$Want, [string]$Later)
        $v = Get-SvcScmView $Svc
        if (-not $v.found) { return }
        if ($v.start -eq 'Disabled') {
            try { Set-Service -Name $Svc -StartupType $Want -ErrorAction Stop } catch { }
            $v = Get-SvcScmView $Svc
        }
        if ($v.start -eq 'Disabled') { $pending.Add(("{0} ({1})" -f $Svc, $Later)); return }
        if ($Want -ne 'Automatic' -or $v.running) { return }
        try {
            Start-Service -Name $Svc -ErrorAction Stop -WarningAction SilentlyContinue
            (Get-Service -Name $Svc -ErrorAction Stop).WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
        } catch { $failed.Add(("{0}: {1}" -f $Svc, $_.Exception.Message)) }
    }
    foreach ($n in @($Names)) {
        $want = & $toScm $n
        if (-not $want) { continue }
        if ($n -eq 'CDPUserSvc') {
            # сам шаблон не запускается — запускаются его копии у пользователей
            $v = Get-SvcScmView $n
            if ($v.found -and $v.start -eq 'Disabled') { try { Set-Service -Name $n -StartupType $want -ErrorAction Stop } catch { } }
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
    $w = Get-SvcStartInfo 'wlidsvc'
    $wv = Get-SvcScmView 'wlidsvc'
    $w['running'] = [bool]$wv.running; $w['scmStart'] = "$($wv.start)"
    $svcs.Add($w)
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
