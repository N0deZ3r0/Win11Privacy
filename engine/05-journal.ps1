# Журнал отката сбрасывается на диск по ходу работы: раньше он писался
# единственный раз в самом конце, и обрыв прогона (закрыли окно, выключили
# питание) оставлял изменения в системе, а вернуть их было нечем.
# Журнал читается и переписывается целиком, поэтому два одновременно
# работающих экземпляра затирали правки друг друга — а журнал единственный
# путь назад. Общесистемный замок делает запись неделимой.
# Не дождались замка — не пишем вовсе: раньше после 10 секунд ожидания тело
# выполнялось без замка, и два запуска снова затирали друг другу журнал.
#
# Замок — файл journal.lock в защищённом корне ProgramData\Win11Privacy,
# открытый без совместного доступа. Раньше это был именованный мьютекс
# Global\Win11Privacy-Journal, а его может создать и держать любой процесс,
# даже от имени службы без прав: пока он держал, не работали ни применение,
# ни откат (проверено на VM). У файла права только для системы и
# администраторов — ни на запись, ни на чтение, — так что занять его без прав
# администратора нельзя ни как, в том числе открыв «просто на чтение».
# Процесс завершился, не отпустив замок, — Windows закрывает файл сама.
# Замок повторно входимый: запись, которая читает журнал под замком, не ждёт
# сама себя.
$script:JournalLockDepth = 0
function Get-JournalLockPath { return (Join-Path $script:SafeRoot 'journal.lock') }

function Open-JournalLockFile {
    $p = Get-JournalLockPath
    $dir = Split-Path $p -Parent
    if (Test-Admin) {
        # Корень заводится и проверяется до замка: корень, который успел
        # завести кто-то другой, отложен в сторону вместе с его «замком»
        if (-not (Assert-SafeRoot)) { throw 'папка ProgramData\Win11Privacy не защищена от подмены — замка журнала отката нет' }
    } elseif (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        # заводить корень без прав администратора нельзя: он был бы ничей
        throw (New-Object System.UnauthorizedAccessException 'защищённой папки программы нет, а завести её может только администратор')
    }
    # ссылка на месте замка увела бы его открытие в чужой файл
    if ((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'на месте замка журнала лежит ссылка'
    }
    if (-not (Test-Admin)) {
        # без прав администратора замок не взять: файл закрыт и на запись, и
        # на чтение (см. ниже), открытие кончится отказом в доступе
        return [IO.File]::Open($p, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    }
    # Права замка — только система и администраторы, на чтение тоже, и
    # задаются при создании файла. Унаследованные от папки данных права
    # («Пользователи: чтение») позволили бы любому процессу открыть замок на
    # чтение без совместного доступа и держать: тогда ни применение, ни откат
    # не получили бы замок — тот же отказ в работе, что был у общего мьютекса.
    $sec = New-Object System.Security.AccessControl.FileSecurity
    $sec.SetAccessRuleProtection($true, $false)
    foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
        $sec.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', 'Allow')))
    }
    $sec.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    # права открытия включают смену прав и владельца: ими исправляется замок,
    # оставшийся с широкими правами (SetAccessControl на открытом дескрипторе)
    $fs = New-Object System.IO.FileStream($p, [IO.FileMode]::OpenOrCreate,
                                          ([Security.AccessControl.FileSystemRights]'ReadData, WriteData, ReadPermissions, ChangePermissions, TakeOwnership'),
                                          [IO.FileShare]::None, 4096, [IO.FileOptions]::None, $sec)
    # замок, оставшийся с более широкими правами (создан до этой защиты),
    # исправляется, пока он у нас в руках
    if (-not (Test-KeyFileSecure $p)) {
        try { $fs.SetAccessControl($sec) } catch { $fs.Dispose(); throw }
    }
    return $fs
}

function Use-JournalLock {
    param([scriptblock]$Body)
    if ($script:JournalLockDepth -gt 0) {
        $script:JournalLockDepth++
        try { & $Body } finally { $script:JournalLockDepth-- }
        return
    }
    $fs = $null
    $until = (Get-Date).AddMilliseconds([double]$script:JournalLockTries * [double]$script:JournalLockWaitMs)
    while ($null -eq $fs) {
        try { $fs = Open-JournalLockFile }
        catch [System.UnauthorizedAccessException] {
            throw (New-Object System.UnauthorizedAccessException 'замок журнала отката открывается только с правами администратора')
        } catch [System.IO.IOException] {
            # занят другим запуском (или антивирус проверяет файл) — ждём
            if ((Get-Date) -ge $until) { throw 'журнал отката занят другим запуском программы' }
            Start-Sleep -Milliseconds 200
        }
    }
    $script:JournalLockDepth = 1
    try { & $Body }
    finally {
        $script:JournalLockDepth = 0
        try { $fs.Dispose() } catch { }
    }
}

# Журнал на диске. Повреждённый файл не затирается молча новыми записями —
# раньше Load-Json возвращал пустоту, и вся история «как было» терялась при
# следующей же записи. Теперь он откладывается рядом под своим именем.
#  Журнал отката — готовая инструкция для администратора: какие значения
#  записать в реестр, какие службы, задачи и автозагрузку вернуть. В
#  переносимом режиме он лежит рядом с exe, куда может писать любая программа
#  пользователя, — и дописанная туда запись (скажем, своя программа в
#  автозагрузке всех пользователей) выполнилась бы при следующем откате с
#  правами администратора. Поэтому журнал подписывается HMAC-SHA256. Ключ
#  лежит в ProgramData\Win11Privacy, и читать его могут только система и
#  администраторы: без него подпись не подделать.
function Test-KeyFileSecure {
    param([string]$Path)
    try {
        $it = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        if ($script:TrustedSids -notcontains $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value) { return $false }
        if (-not $acl.AreAccessRulesProtected) { return $false }
        # даже читать — только своим
        foreach ($r in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ("$($r.AccessControlType)" -ne 'Allow') { continue }
            if ($script:TrustedSids -notcontains $r.IdentityReference.Value) { return $false }
        }
        return $true
    } catch { return $false }
}

# Ключ заводится (или заменяется испорченный) только при записи журнала,
# -Create. Проверка подписи ключ лишь читает: завести новый при проверке —
# значит наверняка «не сойтись» с журналом, подписанным прежним, и молча
# лишить человека отката. Без ключа журнал просто непроверяем.
function Get-SignKey {
    param([switch]$Create)
    if ($null -ne $script:SignKey) { return $script:SignKey }
    if (-not (Assert-SafeRoot)) { throw 'папка ProgramData\Win11Privacy не защищена — ключа подписи журнала нет' }
    $p = $script:SignKeyFile
    if (Test-Path -LiteralPath $p) {
        $b = $null
        if (Test-KeyFileSecure $p) { try { $b = [IO.File]::ReadAllBytes($p) } catch { $b = $null } }
        if ($null -ne $b -and $b.Length -eq 32) { $script:SignKey = $b; return $b }
        if (-not $Create) { throw 'ключ подписи журнала испорчен или открыт не только администраторам' }
        if (-not (Test-Admin)) { throw 'ключ подписи журнала недоступен' }
        # ключ мог прочитать кто-то чужой — он больше ничего не доказывает
        Move-Item -LiteralPath $p -Destination ($p + '.untrusted-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force -ErrorAction Stop
        Write-Log '   [!] ключ подписи журнала был открыт не только администраторам или повреждён -- он заменён новым'
    }
    if (-not $Create) { throw 'ключа подписи журнала нет' }
    if (-not (Test-Admin)) { throw 'ключа подписи журнала нет, а создать его можно только с правами администратора' }
    $b = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($b) } finally { $rng.Dispose() }
    # права — сразу при создании файла: между созданием и сменой прав ключ
    # успели бы прочитать
    $sec = New-Object System.Security.AccessControl.FileSecurity
    $sec.SetAccessRuleProtection($true, $false)
    foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
        $sec.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', 'Allow')))
    }
    $sec.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    $fs = [IO.File]::Create($p, 64, [IO.FileOptions]::WriteThrough, $sec)
    try { $fs.Write($b, 0, $b.Length) } finally { $fs.Dispose() }
    $script:SignKey = $b
    return $b
}

# Подпись — по тексту, который даёт разбор самого файла: у хэш-таблиц и у
# прочитанных из файла объектов поля идут в разном порядке.
function Get-JournalSig {
    param($Items, [bool]$Legacy, [switch]$ForWrite)
    $canon = ('w11p-journal|{0}|' -f [int]$Legacy) + (ConvertTo-Json -InputObject @($Items) -Depth 8 -Compress)
    $h = [System.Security.Cryptography.HMACSHA256]::new([byte[]](Get-SignKey -Create:$ForWrite))
    try { return (($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($canon)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $h.Dispose() }
}

# Запись журнала прежней версии без подписи, которой можно верить и в
# переносимой папке: она про настройку самой программы — тот же параметр
# реестра, служба, задача или переменная среды, что в её списке. Запись про
# что-то другое (автозагрузка, чужие профили, произвольный ключ реестра)
# могли дописать, и без подписи её не возвращаем.
function Test-JournalEntryKnown {
    param($Entry)
    if ($null -eq $script:KnownJournal) {
        $k = @{}; $globs = New-Object System.Collections.Generic.List[string]
        foreach ($d in @($script:Defs)) {
            if ($null -eq $d) { continue }
            if ($script:RegTypes -contains $d.T) { $k[(Get-JournalKey @{ kind = 'reg'; path = $d.P; name = $d.N })] = $true }
            elseif ($d.T -in @('svc', 'svcopt')) { $k[(Get-JournalKey @{ kind = 'svc'; name = $d.P })] = $true }
            elseif ($d.T -eq 'task') { $k[(Get-JournalKey @{ kind = 'task'; path = $d.P })] = $true }
            elseif ($d.T -eq 'taskglob') { $globs.Add("$($d.P)") }
            elseif ($d.T -eq 'env') { $k[(Get-JournalKey @{ kind = 'env'; name = $d.P })] = $true }
            elseif ($d.T -in @('vscode', 'firefox')) { $k[(Get-JournalKey @{ kind = 'appcfg'; app = $d.T; name = $d.P })] = $true }
        }
        $k[(Get-JournalKey @{ kind = 'audit'; guid = $script:AuditGuid })] = $true
        $script:KnownJournal = $k; $script:KnownTaskGlobs = $globs.ToArray()
    }
    $f = ConvertTo-Fields $Entry
    $kind = "$($f['kind'])"
    if ($kind -notin @('reg', 'svc', 'task', 'env', 'audit', 'appcfg')) { return $false }
    if ($script:KnownJournal.ContainsKey((Get-JournalKey $f))) { return $true }
    if ($kind -eq 'task') {
        # по маске — только в её папках, а не любая задача с подходящим именем
        foreach ($g in $script:KnownTaskGlobs) { if (Test-TaskGlobPath "$($f['path'])" $g) { return $true } }
    }
    return $false
}

# -ReadOnly — для показа журнала: ничего не откладывать и не писать.
# Журнал читается под тем же замком, под которым его пишут: у подмены файла
# (ReplaceFile) есть миг, когда его нет под этим именем, и чтение без замка
# в этот миг видело «журнала нет» — откат сказал бы «возвращать нечего».
# Замок повторно входимый: запись, которая читает журнал под замком, не ждёт сама себя.
function Read-JournalFile {
    param([switch]$ReadOnly)
    $box = @{ r = $null }
    try { Use-JournalLock { $box.r = Read-JournalFileUnlocked -ReadOnly:$ReadOnly } }
    catch [System.UnauthorizedAccessException] {
        # Без прав администратора замок не взять. Показать журнал можно и
        # без него: чтение ничего не меняет, а миг подмены файла другим
        # запуском Read-JournalFileUnlocked пережидает сам.
        if ($ReadOnly) { return (Read-JournalFileUnlocked -ReadOnly) }
        return @{ items = @(); legacy = $false; exists = $true; signed = $false; trusted = $false; state = 'unreadable'; updated = ''; dropped = 0 }
    }
    catch {
        if (-not $ReadOnly) { Write-Log ("   [!] журнал отката сейчас не читается ({0}) -- файл не тронут, повторите позже" -f $_.Exception.Message) }
        return @{ items = @(); legacy = $false; exists = $true; signed = $false; trusted = $false; state = 'unreadable'; updated = ''; dropped = 0 }
    }
    return $box.r
}

function Read-JournalFileUnlocked {
    param([switch]$ReadOnly)
    # state: none — журнала нет; valid — ему можно верить; legacy — можно
    # верить, но он прежнего образца (не знает служб и задач); untrusted —
    # нельзя: повреждён, подпись не сошлась или её нечем проверить. Раньше
    # отложенный недоверенный журнал выглядел просто «отсутствующим», и
    # полный откат переходил к прежнему откату «по умолчанию».
    $p = Join-Path $script:DataDir 'changes.json'
    $res = @{ items = @(); legacy = $false; exists = $false; signed = $false; trusted = $true; state = 'none'; updated = ''; dropped = 0 }
    if (-not (Test-Path -LiteralPath $p)) { return $res }
    $res.exists = $true
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    # Недоверенный журнал откладывается рядом, а не затирается: следующая
    # запись иначе пошла бы поверх, и прочитать его потом было бы нечем.
    $setAside = {
        param([string]$Prefix, [string]$Why)
        $res.trusted = $false; $res.state = 'untrusted'
        if ($ReadOnly) { return }
        $bad = Join-Path $script:DataDir ($Prefix + $stamp + '.json')
        Move-Item -LiteralPath $p -Destination $bad -Force -ErrorAction Stop
        Write-Log ("   [!] {0} По нему ничего не возвращается; файл отложен как {1}" -f $Why, (Split-Path $bad -Leaf))
        $res.exists = $false
    }
    # Не прочитался (занят другим процессом) — это не повреждение и не «пусто».
    # Раньше ошибка чтения Get-Content не прерывала разбор: журнал выглядел
    # пустым и достоверным, и откат в этот миг сказал бы «возвращать нечего».
    # Файл был, а при открытии его нет: другой запуск как раз подменяет его
    # (у ReplaceFile есть миг без файла под этим именем). Это не «журнала нет»
    # — ждём и читаем снова; раньше такой миг читался как пустой журнал.
    $txt = $null
    for ($k = 1; $k -le 20; $k++) {
        try { $txt = Read-TextShared $p }
        catch {
            $res.trusted = $false; $res.state = 'unreadable'
            if (-not $ReadOnly) { Write-Log ("   [!] журнал отката сейчас не читается ({0}) -- файл не тронут, повторите позже" -f $_.Exception.Message) }
            return $res
        }
        if ($null -ne $txt) { break }
        Start-Sleep -Milliseconds 50
    }
    if ($null -eq $txt) { $res.exists = $false; return $res }      # и правда удалён
    $j = $null
    try { if ("$txt".Trim()) { $j = $txt | ConvertFrom-Json -ErrorAction Stop } } catch { $j = $null }
    if ($null -eq $j) {
        & $setAside 'changes.broken-' 'журнал отката повреждён.'
        return $res
    }
    $items = @()
    if ($j -and $j.PSObject.Properties['items'] -and $null -ne $j.items) { $items = @($j.items) }
    # Журнал прежних версий: в нём нет служб, задач и переменных среды. Пометка
    # остаётся с ним навсегда — полный откат для них ведёт себя по-старому.
    $res.legacy = [bool](($j.PSObject.Properties['legacy'] -and $j.legacy) -or
                         (-not $j.PSObject.Properties['schema'] -and $items.Count -gt 0))
    if ($j.PSObject.Properties['updated']) { $res.updated = "$($j.updated)" }

    if ($j.PSObject.Properties['sig'] -and "$($j.sig)") {
        # Ключ здесь только читается: заводить новый при проверке — значит
        # наверняка «не сойтись» с журналом, подписанным прежним.
        $want = $null
        try { $want = Get-JournalSig $items $res.legacy } catch { $want = $null }
        if ($null -eq $want) {
            & $setAside 'changes.unverifiable-' 'подпись журнала отката проверить нечем: ключа подписи нет или он испорчен.'
            return $res
        }
        if ($want -ne "$($j.sig)") {
            & $setAside 'changes.unverified-' 'подпись журнала отката не сошлась: его правила не эта программа или он с другого компьютера.'
            return $res
        }
        $res.signed = $true; $res.items = $items
        $res.state = $(if ($res.legacy) { 'legacy' } else { 'valid' })
        return $res
    }
    # Без подписи — журнал прежней версии. В защищённой папке подменить его
    # было некому. В переносимой — могли: из него остаются только записи о
    # настройках самой программы.
    $res.state = $(if ($res.legacy) { 'legacy' } else { 'valid' })
    if ($script:DataDir -eq $script:SafeRoot) { $res.items = $items; return $res }
    $keep = @($items | Where-Object { Test-JournalEntryKnown $_ })
    $res.dropped = $items.Count - $keep.Count
    $res.items = $keep
    if ($res.dropped -gt 0 -and -not $ReadOnly) {
        Write-Log ("   [!] журнал отката прежней версии без подписи лежит в папке, которую может изменить любая программа. Из него взяты только записи о настройках программы: {0} из {1}; остальные (автозагрузка, другие профили, сторонние ключи) пропущены." -f $keep.Count, $items.Count)
    }
    return $res
}

function Write-JournalFile {
    param($Items, [bool]$Legacy)
    $arr = @($Items)
    $parsed = @()
    if ($arr.Count -gt 0) {
        # ConvertFrom-Json отдаёт массив одним объектом: @(...) вокруг вызова
        # завернул бы его ещё раз, и журнал стал бы {"value": [...], "Count": N}
        $back = ConvertFrom-Json (ConvertTo-Json -InputObject $arr -Depth 8 -Compress)
        $parsed = @($back)
    }
    $sig = Get-JournalSig $parsed $Legacy -ForWrite
    Save-Json 'changes.json' ([ordered]@{ schema = 3; legacy = $Legacy; updated = (Get-Date).ToString('s'); items = $parsed; sig = $sig })
}

# Перед применением: журнал должен писаться, иначе ни одно изменение не
# смогло бы вернуться. Проверяем заранее, пока ничего не тронуто.
function Test-JournalWritable {
    if ($DryRun) { return $true }
    try {
        if (-not (Test-DataTrusted)) { throw 'папка данных программы не защищена от подмены' }
        Use-JournalLock {
            Save-Json 'journal-check.json' @{ time = (Get-Date).ToString('s') }
            Remove-Item -LiteralPath (Join-Path $script:DataDir 'journal-check.json') -Force -ErrorAction Stop
        }
        return $true
    } catch {
        Write-Log ("   [!] журнал отката не записывается: {0}" -f $_.Exception.Message)
        return $false
    }
}

# Для отката нужна САМАЯ РАННЯЯ запись про каждый параметр — та, что помнит
# состояние до нас. Остальные повторы держать незачем: раньше журнал рос без
# предела и на каждой записи переписывался целиком.
# Записи журнала бывают двух видов: свежие -- хэш-таблицы, прочитанные из
# файла -- PSCustomObject. У хэш-таблицы PSObject.Properties перечисляет
# свойства самой таблицы, а не её ключи, поэтому читать поля надо по-разному.
function ConvertTo-Fields {
    param($Entry)
    $h = @{}
    if ($null -eq $Entry) { return $h }
    if ($Entry -is [System.Collections.IDictionary]) {
        foreach ($k in @($Entry.Keys)) { $h["$k"] = $Entry[$k] }
    } else {
        foreach ($p in $Entry.PSObject.Properties) { $h[$p.Name] = $p.Value }
    }
    return $h
}

# Ключ записи журнала: про каждый параметр важна самая ранняя запись. Записи
# других профилей (hive) различаются файлом куста — у каждого пользователя свой.
function Get-JournalKey {
    param($F)
    $k = "$($F['kind'])"
    if ($k -eq 'startup') { return "startup|$($F['id'])" }
    if ($k -eq 'hive') { return ("hive|{0}|{1}|{2}" -f "$($F['file'])", "$($F['sub'])", "$($F['name'])").ToLowerInvariant() }
    if ($k -eq 'svc')  { return ("svc|{0}" -f "$($F['name'])").ToLowerInvariant() }
    if ($k -eq 'task') { return ("task|{0}" -f "$($F['path'])").ToLowerInvariant() }
    if ($k -eq 'env')  { return ("env|{0}" -f "$($F['name'])").ToLowerInvariant() }
    if ($k -eq 'audit') { return ("audit|{0}" -f "$($F['guid'])").ToLowerInvariant() }
    # настройка сторонней программы: ключ в её файле (VS Code, Firefox)
    if ($k -eq 'appcfg') { return ("appcfg|{0}|{1}" -f "$($F['app'])", "$($F['name'])").ToLowerInvariant() }
    return ("reg|{0}|{1}" -f "$($F['path'])", "$($F['name'])").ToLowerInvariant()
}

function Compress-Journal {
    param($Items)
    $order = New-Object System.Collections.Generic.List[string]
    $first = @{}
    foreach ($e in @($Items)) {
        $f = ConvertTo-Fields $e
        if ($f.Count -eq 0) { continue }
        $key = Get-JournalKey $f
        if (-not $first.ContainsKey($key)) {
            if (-not $f.ContainsKey('count') -or [int]$f['count'] -lt 1) { $f['count'] = 1 }
            $first[$key] = $f
            $order.Add($key)
            continue
        }
        # повтор: помним только чем всё кончилось и сколько раз меняли
        $cur = $first[$key]
        $cur['count'] = [int]$cur['count'] + [int]$(if ($f.ContainsKey('count') -and [int]$f['count'] -gt 0) { $f['count'] } else { 1 })
        if ($f.ContainsKey('newValue')) { $cur['newValue'] = $f['newValue'] }
        if ($f.ContainsKey('time') -and "$($f['time'])") { $cur['lastTime'] = "$($f['time'])" }
    }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($k in $order) { $out.Add($first[$k]) }
    return $out.ToArray()
}

# Дописывает накопленный журнал «что было до нас» к changes.json. Раньше это
# делалось только в самом конце применения модулей — теперь любая команда,
# меняющая систему, может сохранить свой след для отката одной кнопкой.
# Ошибка записи больше не глотается: раньше программа сообщала об успехе,
# а «как было» на диск не попадало, и откат потом молча ничего не возвращал.
# Теперь она видна в журнале работы, а дальнейшие изменения останавливаются
# ($script:JournalFailed) — менять систему без записи для отката нельзя.
function Save-JournalEntries {
    param([switch]$Quiet)
    if ($DryRun -or ($script:Journal.Count -eq 0 -and $script:JournalRetract.Count -eq 0)) { return }
    $mine = $script:Journal.Count
    try {
        if (-not (Test-DataTrusted)) { throw 'папка данных программы не защищена от подмены' }
        Use-JournalLock {
            $prev = Read-JournalFile
            # Не прочитался (занят) — дописывать нельзя: новый файл из одних
            # свежих записей затёр бы всю историю «как было». Раньше ошибка
            # чтения выглядела пустым журналом, и так и происходило.
            if ($prev.state -eq 'unreadable') { throw 'журнал отката сейчас не читается -- дописать в него нельзя, не потеряв прежние записи' }
            $all = New-Object System.Collections.Generic.List[object]
            foreach ($e in @($prev.items)) {
                # Записи, положенные заранее этим же запуском, чьё изменение не
                # прошло: «было» там верное, но изменения не было — убираем.
                # Записи прежних запусков с тем же ключом не трогаются.
                if ($script:JournalRetract.Count -gt 0 -and "$($e.run)" -eq $script:RunId -and
                    $script:JournalRetract.Contains((Get-JournalKey (ConvertTo-Fields $e)))) { continue }
                $all.Add($e)
            }
            foreach ($e in $script:Journal) { $all.Add($e) }
            Write-JournalFile (Compress-Journal $all.ToArray()) $prev.legacy
            $script:Journal.Clear()
            $script:JournalRetract.Clear()
        }
    } catch {
        if (-not $script:JournalFailed) {
            Write-Log ("   [!] журнал отката не записался: {0}" -f $_.Exception.Message)
            Write-Log '       Дальше программа ничего не меняет: изменение без записи в журнале нельзя было бы вернуть.'
        }
        $script:JournalFailed = $true
        $script:Failures++
        return
    }
    if (-not $Quiet) { Write-Log ("Записано в журнал отката: {0}" -f $mine) }
}

# Убрать из журнала записи с этим ключом — после того как значение возвращено.
# Под замком и только из журнала, которому можно верить.
function Remove-JournalKey {
    param([string]$Key)
    Use-JournalLock {
        $jf = Read-JournalFile
        if (-not $jf.trusted) { throw 'журналу отката нельзя верить' }
        $rest = @($jf.items | Where-Object { (Get-JournalKey (ConvertTo-Fields $_)) -ne $Key })
        Write-JournalFile $rest $jf.legacy
    }
}

# Опознавательный знак записи журнала: ключ плюс когда и сколько раз её
# меняли. Запись, которую другой запуск успел дополнить (Compress-Journal
# прибавил count или lastTime), — уже другая и не считается обработанной.
function Get-JournalEntryId {
    param($Entry)
    $f = ConvertTo-Fields $Entry
    return ('{0}|{1}|{2}|{3}|{4}' -f (Get-JournalKey $f), "$($f['time'])", "$($f['lastTime'])", "$($f['count'])", "$($f['run'])")
}

# Убрать из журнала записи, с которыми откат закончил. Журнал перечитывается
# под замком: что за это время дописал другой запуск (страж, второе окно),
# остаётся. Раньше откат переписывал журнал тем, что прочитал в начале, и
# такие записи пропадали.
function Remove-JournalEntries {
    param($Handled)
    Use-JournalLock {
        $jf = Read-JournalFile
        if (-not $jf.trusted) { throw 'журналу отката нельзя верить' }
        $rest = @($jf.items | Where-Object { -not $Handled.Contains((Get-JournalEntryId $_)) })
        Write-JournalFile $rest $jf.legacy
    }
}
# Файлы данных читаются только из папки, которой можно верить, — так же, как
# пишутся (Save-Json). Раньше чтение не проверяло папку: подложенный файл
# (например, profile.json — какие модули страж держит включёнными) прочитался
# бы с правами администратора.
function Load-Json {
    param([string]$Name)
    if (-not (Test-DataTrusted)) { return $null }
    $p = Join-Path $script:DataDir $Name
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try {
        $txt = Read-TextShared $p
        if (-not "$txt".Trim()) { return $null }
        return ($txt | ConvertFrom-Json -ErrorAction Stop)
    } catch { Write-Log ("   [!] файл данных {0} не читается: {1}" -f $Name, $_.Exception.Message); return $null }
}

