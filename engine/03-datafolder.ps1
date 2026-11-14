# --- Защита папки данных ------------------------------------------------------ #
#  Из ProgramData\Win11Privacy журнал отката читается с правами администратора
#  (по нему пишется реестр), а копию движка оттуда запускают задачи стража.
#  Права ProgramData по умолчанию позволяют обычному пользователю создавать
#  файлы и папки во всех её подпапках, и подложенный заранее changes.json.tmp
#  или engine.ps1 остался бы его собственностью: он мог бы дописать в журнал
#  что угодно, а откат записал бы это в реестр от имени администратора.
#  Поэтому права корня задаются явно — писать могут только система и
#  администраторы, — а всё, что завёл кто-то другой, уходит в карантин.
function Get-OwnerSid {
    param([string]$Path)
    try { return (Get-Acl -LiteralPath $Path -ErrorAction Stop).GetOwner([Security.Principal.SecurityIdentifier]).Value } catch { return '' }
}

function Test-DirSecure {
    param([string]$Dir)
    try {
        if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return $false }
        if ((Get-Item -LiteralPath $Dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        $acl = Get-Acl -LiteralPath $Dir -ErrorAction Stop
        if ($script:TrustedSids -notcontains $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value) { return $false }
        if (-not $acl.AreAccessRulesProtected) { return $false }
        # запись, удаление, смена прав или владельца — в том числе общими правами
        $writeMask = 0x2 -bor 0x4 -bor 0x10 -bor 0x40 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x40000000 -bor 0x10000000
        foreach ($r in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ("$($r.AccessControlType)" -ne 'Allow') { continue }
            if ($script:TrustedSids -contains $r.IdentityReference.Value) { continue }
            if (([int64]$r.FileSystemRights -band $writeMask) -ne 0) { return $false }
        }
        return $true
    } catch { return $false }
}

# Можно ли верить файлу или папке внутри папки данных: не ссылка, владелец —
# система или администраторы, и никому чужому явным правом не открыт на запись
# (унаследованные права заменит новый корень).
function Test-ItemTrusted {
    param($Item)
    if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    try { $acl = Get-Acl -LiteralPath $Item.FullName -ErrorAction Stop } catch { return $false }
    if ($script:TrustedSids -notcontains $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value) { return $false }
    $writeMask = 0x2 -bor 0x4 -bor 0x10 -bor 0x40 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x40000000 -bor 0x10000000
    foreach ($r in $acl.GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier])) {
        if ("$($r.AccessControlType)" -ne 'Allow') { continue }
        if ($script:TrustedSids -contains $r.IdentityReference.Value) { continue }
        if (([int64]$r.FileSystemRights -band $writeMask) -ne 0) { return $false }
    }
    return $true
}

# Всё недоверенное на любой глубине. Внутрь ссылок и чужих папок не заходим:
# они уходят в карантин целиком.
# Путь внутри собирается из имён: отрезать начало полного пути нельзя — у
# временной папки бывает короткое имя 8.3, а у найденного — длинное.
function Get-UntrustedItems {
    param([string]$Dir, [string]$Rel = '')
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($c in @(Get-ChildItem -LiteralPath $Dir -Force -ErrorAction SilentlyContinue)) {
        $r = $(if ($Rel) { Join-Path $Rel $c.Name } else { $c.Name })
        if (-not (Test-ItemTrusted $c)) { $out.Add([pscustomobject]@{ Item = $c; Rel = $r }); continue }
        if ($c.PSIsContainer) { foreach ($x in @(Get-UntrustedItems $c.FullName $r)) { $out.Add($x) } }
    }
    return $out.ToArray()
}

# Свежая пустая папка карантина рядом с корнем: имя со случайным хвостом,
# которого заранее не угадать, и мы сами её создаём. Предсказуемый путь
# «<корень>.untrusted-<время>» обычный пользователь мог завести заранее —
# папкой или junction, — и перенос «чужого» с правами администратора ушёл бы
# по ссылке в защищённую папку. Создать не вышло или на месте оказалась
# ссылка — пустая строка, карантин не делается.
function New-QuarantineDir {
    param([string]$Dir)
    for ($i = 0; $i -lt 20; $i++) {
        $cand = "$Dir.untrusted-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        if (Test-Path -LiteralPath $cand) { continue }
        try { $null = [IO.Directory]::CreateDirectory($cand) } catch { continue }
        if ((Get-Item -LiteralPath $cand -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            try { [IO.Directory]::Delete($cand, $true) } catch { }
            continue
        }
        return $cand
    }
    return ''
}

function Protect-DataRoot {
    param([string]$Dir)
    if (-not (Test-Admin)) { return (Test-DirSecure $Dir) }
    try {
        if (Test-Path -LiteralPath $Dir) {
            $it = Get-Item -LiteralPath $Dir -Force
            if (($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($script:TrustedSids -notcontains (Get-OwnerSid $Dir))) {
                # папку завёл не администратор — ничему внутри верить нельзя.
                # Переносим в свежесозданный карантин: Move на уже существующий
                # путь не идёт, а предсказуемый путь можно было занять заранее.
                $aside0 = New-QuarantineDir $Dir
                if (-not $aside0) { Write-Log '   [!] не удалось завести папку карантина -- папка данных не тронута'; return $false }
                # Move не умеет в существующую пустую папку — кладём внутрь неё
                [IO.Directory]::Move($Dir, (Join-Path $aside0 (Split-Path $Dir -Leaf)))
                Write-Log ("   [!] папку данных завёл не администратор -- она отложена как {0}" -f (Split-Path $aside0 -Leaf))
            }
        }
        $sec = New-Object System.Security.AccessControl.DirectorySecurity
        $sec.SetAccessRuleProtection($true, $false)
        $inh = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        foreach ($p in @(@('S-1-5-18', 'FullControl'), @('S-1-5-32-544', 'FullControl'), @('S-1-5-32-545', 'ReadAndExecute'))) {
            $sid = New-Object Security.Principal.SecurityIdentifier($p[0])
            $sec.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, $p[1], $inh, 'None', 'Allow')))
        }
        $sec.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
        # Новая папка — сразу с правами: раньше она создавалась с правами,
        # унаследованными от ProgramData, и закрывалась вторым шагом, а между
        # ними обычный пользователь успел бы завести в ней свой файл.
        if (-not (Test-Path -LiteralPath $Dir)) { $null = [IO.Directory]::CreateDirectory($Dir, $sec) }
        if (Test-DirSecure $Dir) { return $true }
        # Папка прежних версий: права наследовались от ProgramData, и обычный
        # пользователь мог завести файлы и папки на любой глубине — раньше
        # проверялось только то, что лежит прямо в корне. Всё, что создал не
        # администратор, любые ссылки и всё, что чужим явным правом открыто
        # на запись, уносим в карантин рядом — с тем же путём внутри.
        $untrusted = @(Get-UntrustedItems $Dir)
        if ($untrusted.Count -gt 0) {
            $aside = New-QuarantineDir $Dir
            if (-not $aside) { Write-Log '   [!] не удалось завести папку карантина -- чужое в папке данных не тронуто'; return $false }
            foreach ($u in $untrusted) {
                $to = Join-Path $aside $u.Rel
                $toDir = Split-Path $to -Parent
                if (-not (Test-Path -LiteralPath $toDir)) { New-Item -ItemType Directory -Path $toDir -Force | Out-Null }
                if ($u.Item.PSIsContainer) { [IO.Directory]::Move($u.Item.FullName, $to) } else { [IO.File]::Move($u.Item.FullName, $to) }
                Write-Log ("   [!] в папке данных лежал чужой файл, он отложен: {0}" -f $u.Rel)
            }
        }
        [IO.Directory]::SetAccessControl($Dir, $sec)
        return (Test-DirSecure $Dir)
    } catch {
        Write-Log ("   [!] не удалось защитить папку данных {0}: {1}" -f $Dir, $_.Exception.Message)
        return $false
    }
}

function Assert-SafeRoot {
    if ($null -eq $script:RootState) { $script:RootState = [bool](Protect-DataRoot $script:SafeRoot) }
    return $script:RootState
}

# Тома без прав доступа (FAT, exFAT) и сетевые папки: закрыть папку там нечем.
function Test-AclVolume {
    param([string]$Dir)
    try {
        $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Dir))
        if ($root -like '\\*') { return $false }
        return ((New-Object IO.DriveInfo($root)).DriveFormat -in @('NTFS', 'ReFS'))
    } catch { return $false }
}

# Может ли кто-то, кроме системы и администраторов, подменить папку — то
# есть удалить или переименовать её или любую папку выше, сменить им права
# или владельца. Закрыть одну папку данных мало: если её родитель открыт на
# запись, папку можно переименовать и положить на её место свою — между
# проверкой и чтением.
function Test-DirChainSecure {
    param([string]$Dir)
    try {
        $self  = 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000   # удаление, права, владелец, общие
        $child = 0x40 -bor 0x10000000 -bor 0x40000000                                # удаление вложенного
        $cur = [IO.Path]::GetFullPath($Dir).TrimEnd('\')
        while ($cur) {
            $parent = [IO.Path]::GetDirectoryName($cur)
            $isRoot = (-not $parent)
            $node = $(if ($isRoot) { $cur.TrimEnd('\') + '\' } else { $cur })
            $it = Get-Item -LiteralPath $node -Force -ErrorAction Stop
            if (-not $isRoot -and ($it.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
            $acl = Get-Acl -LiteralPath $node -ErrorAction Stop
            if ($script:TrustedSids -notcontains $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value) { return $false }
            $mask = $(if ($isRoot) { $child } else { $self -bor $child })
            foreach ($r in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
                if ("$($r.AccessControlType)" -ne 'Allow') { continue }
                # «создатель-владелец» и прочие шаблоны для вложенного к самой папке не относятся
                if ($r.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
                if ($script:TrustedSids -contains $r.IdentityReference.Value) { continue }
                if (([int64]$r.FileSystemRights -band $mask) -ne 0) { return $false }
            }
            if ($isRoot) { break }
            $cur = $parent
        }
        return $true
    } catch { return $false }
}

# Переносимая папка данных лежит рядом с exe, и права ей достаются от папки
# exe. Окну этого достаточно: кто может писать в эту папку, может подменить и
# сам exe, который человек запускает. Но страж и наблюдение — задачи
# планировщика: они сами, без человека, запускают защищённую копию движка с
# правами администратора и читают эту папку. Раньше она считалась доверенной
# без проверки — подложенный журнал или ссылка на месте папки сработали бы с
# правами администратора. Задачам переносимая папка годится, только если
# подменить её нельзя: том с правами доступа, путь до неё закрыт от записи
# (как Program Files), а сама она закрыта так же, как ProgramData\Win11Privacy.
function Test-PortableTaskTrust {
    if ($null -eq $script:PortableTaskState) {
        $script:PortableTaskState = [bool]((Test-AclVolume $script:DataDir) -and
                                           (Test-DirChainSecure (Split-Path $script:DataDir -Parent)) -and
                                           (Protect-DataRoot $script:DataDir))
    }
    return $script:PortableTaskState
}

# Журнал читается и пишется только из защищённой папки.
function Test-DataTrusted {
    if ($script:DataDir -eq $script:SafeRoot) { return (Assert-SafeRoot) }
    if ($script:TaskRun) { return (Test-PortableTaskTrust) }
    return $true
}

function Ensure-DataDir {
    if (-not (Test-DataTrusted)) { throw 'папка данных программы не защищена от подмены' }
    if (-not (Test-Path -LiteralPath $script:DataDir)) { New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null }
}

# -DataRoot — только переносимая папка Win11Privacy-Data (так её называет
# окно рядом с exe, так она описана в README), по полному пути. В папку
# данных программа пишет файлы с обычными именами (profile.json), меняет её
# права, откладывает «чужое» в карантин, а по -PurgeData и при полном откате
# стирает свои файлы. -DataRoot, по ошибке указывающий на «Документы», папку
# программы или корень диска, затёр бы или стёр там чужое.
function Test-DataRootAllowed {
    param([string]$Path)
    try {
        if (-not [IO.Path]::IsPathRooted($Path)) { return $false }
        $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
        return ([IO.Path]::GetFileName($full) -ieq 'Win11Privacy-Data')
    } catch { return $false }
}

if ($DataRoot -and -not (Test-DataRootAllowed $DataRoot)) {
    Write-Log ("[!] -DataRoot ""{0}"": папкой данных может быть только папка Win11Privacy-Data, по полному пути (например, D:\Win11Privacy\Win11Privacy-Data). В другой папке программа ничего не пишет и не удаляет." -f $DataRoot)
    Write-Log '###DONE###'
    exit 1
}

# Задача планировщика данным из папки, которую можно подменить, не верит и
# ничего не делает.
if ($script:TaskRun -and -not (Test-DataTrusted)) { exit 1 }

# Копия движка для задач планировщика: всегда в защищённом корне, пишется
# рядом и подменяет прежнюю одним движением, а перед этим сверяется с
# оригиналом по SHA-256.
function Install-TaskEngine {
    if (-not (Assert-SafeRoot)) { throw 'папка ProgramData\Win11Privacy не защищена — копию движка для задач туда класть нельзя' }
    $dst = $script:TaskEngine
    if ($PSCommandPath -ne $dst) {
        $tmp = $dst + '.new'
        Copy-Item -LiteralPath $PSCommandPath -Destination $tmp -Force -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            throw 'копия движка для задач не совпала с оригиналом'
        }
        Move-Item -LiteralPath $tmp -Destination $dst -Force -ErrorAction Stop
        # прежние версии в переносимом режиме клали копию рядом с данными
        if ($script:DataDir -ne $script:SafeRoot) { Remove-Item -LiteralPath (Join-Path $script:DataDir 'engine.ps1') -Force -ErrorAction SilentlyContinue }
    }
    # Переносимую папку проверяем после того, как копия обновлена: задачи,
    # поставленные прежними версиями, запускают именно её — и теперь сами
    # откажутся работать с папкой, которую можно подменить. Новую задачу на
    # такой папке не ставим: задача, которая потом молча не работает, хуже
    # честного отказа сейчас.
    if ($script:DataDir -ne $script:SafeRoot -and -not (Test-PortableTaskTrust)) {
        throw (('переносимую папку программы ({0}) может подменить любая программа пользователя, а страж и наблюдение работают с правами администратора сами по себе. ' +
                'В переносимом режиме они ставятся, только если программа лежит в защищённой папке на диске NTFS — например, в Program Files.') -f $script:DataDir)
    }
    return $dst
}

# Файл пишется рядом и подменяет прежний одним движением: обрыв на середине
# записи (выключили питание, прервали движок) не оставит от журнала отката
# половину — а журнал единственный путь назад.
#
# Файлы данных читают и другие запуски (окно, страж), и антивирус. Замене
# одним действием мешает тот, кто держит файл открытым без права на удаление:
# раньше первая же такая встреча давала «журнал отката не записался», и
# применение останавливалось. Теперь замена ждёт и пробует снова; сами мы
# читаем с правом на удаление (Read-TextShared) и чужую замену не держим.
function Save-Json {
    param([string]$Name, $Object)
    Ensure-DataDir
    $path = Join-Path $script:DataDir $Name
    $tmp = $path + '.tmp'
    ($Object | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $tmp -Encoding UTF8 -ErrorAction Stop
    # Замена одним действием системы (ReplaceFile). Move-Item -Force делал
    # «удалить старый, переименовать новый» — между ними журнала не было
    # вовсе, и обрыв в этот миг оставлял программу без пути назад.
    Replace-FileAtomic $tmp $path
}

# Готовый файл $Tmp встаёт на место $Path одним действием системы
# (ReplaceFile: права и атрибуты прежнего файла сохраняются; файла ещё нет —
# переименование). Держит кто-то другой (антивирус, чужое чтение без права
# на удаление) — ждём и пробуем снова, до трёх секунд.
function Replace-FileAtomic {
    param([string]$Tmp, [string]$Path)
    for ($try = 1; ; $try++) {
        try {
            if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($Tmp, $Path, [NullString]::Value) }
            else { [IO.File]::Move($Tmp, $Path) }
            return
        } catch [System.IO.IOException] {
            if ($try -ge 30) { throw }
            Start-Sleep -Milliseconds 100
        }
    }
}

# Текст файла данных. Открывается с правом на чтение, запись и удаление для
# других: замена файла другим запуском (ReplaceFile) не упрётся в нас, а мы
# прочитаем либо прежний файл, либо новый — целиком. Занят без права на
# чтение (антивирус) — ждём и пробуем снова; не вышло — ошибка, а не «пусто».
# Файла нет — $null.
function Read-TextShared {
    param([string]$Path)
    for ($try = 1; ; $try++) {
        try {
            $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
                                         ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            try {
                $sr = New-Object System.IO.StreamReader($fs, (New-Object System.Text.UTF8Encoding $false), $true)
                return $sr.ReadToEnd()
            } finally { $fs.Dispose() }
        } catch [System.IO.FileNotFoundException] { return $null }
        catch [System.IO.DirectoryNotFoundException] { return $null }
        catch [System.IO.IOException] {
            if ($try -ge 30) { throw }
            Start-Sleep -Milliseconds 100
        }
    }
}
