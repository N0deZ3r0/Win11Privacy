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

# Можно ли верить файлу или папке: не ссылка, владелец — система,
# администраторы или TrustedInstaller, и никто другой не может его изменить,
# удалить, переименовать, сменить права или владельца (W11P-006).
#
# Раньше смотрелись только явные права (GetAccessRules($true, $false)):
# право на запись, доставшееся от родительской папки, проходило незамеченным.
# Теперь — все права, явные и унаследованные:
#   * к самому объекту относится всё, кроме «только для вложенного»;
#   * у папки ещё и то, что она передаст вложенному (её файлы и папки получат
#     эти права) — кроме «создатель-владелец» и «создатель-группа»: на месте
#     этих записей у вложенного окажется тот, кто его создал (сам движок);
#   * запрет вычитается, только если он явный, для «Все» (Everyone), список
#     прав в обычном порядке и запрет относится к самому объекту: такой
#     запрет проверяется раньше любого разрешения и касается любого. Запрет
#     одной группы не закрывает того, у кого право пришло через другую
#     (например, «Прошедшие проверку»), а унаследованный запрет стоит после
#     явных разрешений и их не отменяет. Для вложенного запреты не вычитаются
#     вовсе: у него могут быть свои явные разрешения, которые идут раньше.
# Права не читаются — не верим (отказ, а не «доступа нет»).
# -ExplicitOnly — только для переноса старой папки данных (Protect-DataRoot):
# там унаследованные права тут же заменяет новый корень, а после замены
# всё проверяется ещё раз полностью.
function Get-UntrustedRights {
    param($Acl, [bool]$Container, [switch]$ExplicitOnly)
    $self = [int64]0; $child = [int64]0; $deny = [int64]0
    $canonical = [bool]$Acl.AreAccessRulesCanonical
    $inh = [Security.AccessControl.InheritanceFlags]::ObjectInherit -bor [Security.AccessControl.InheritanceFlags]::ContainerInherit
    foreach ($r in $Acl.GetAccessRules($true, (-not $ExplicitOnly), [Security.Principal.SecurityIdentifier])) {
        $sid = $r.IdentityReference.Value
        $rights = [int64]$r.FileSystemRights
        $inheritOnly = [bool]($r.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly)
        # «не распространять дальше» всё равно достаётся прямым вложенным
        $toChildren = $Container -and [bool]($r.InheritanceFlags -band $inh)
        if ("$($r.AccessControlType)" -eq 'Deny') {
            if ($canonical -and -not $r.IsInherited -and -not $inheritOnly -and $sid -eq 'S-1-1-0') { $deny = $deny -bor $rights }
            continue
        }
        if ($script:TrustedSids -contains $sid) { continue }
        # «Права владельца» (OWNER RIGHTS) достаются владельцу, а он проверен
        if ($sid -eq 'S-1-3-4') { continue }
        if (-not $inheritOnly) { $self = $self -bor $rights }
        # «создатель-владелец» и «создатель-группа» у вложенного станут тем,
        # кто его создаст; остальное вложенное получит как есть
        if ($toChildren -and $sid -ne 'S-1-3-0' -and $sid -ne 'S-1-3-1') { $child = $child -bor $rights }
    }
    return (($self -band (-bnot $deny)) -bor $child)
}

function Test-ItemTrusted {
    param($Item, [switch]$ExplicitOnly)
    if ($null -eq $Item -or ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
    try { $acl = Get-Acl -LiteralPath $Item.FullName -ErrorAction Stop } catch { return $false }
    try {
        $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier])
        if ($null -eq $owner -or $script:TrustedSids -notcontains $owner.Value) { return $false }
        # запись, удаление (своё и вложенного), смена прав или владельца,
        # атрибутов — в том числе общими правами
        $writeMask = 0x2 -bor 0x4 -bor 0x10 -bor 0x40 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x40000000 -bor 0x10000000
        $open = Get-UntrustedRights $acl ([bool]$Item.PSIsContainer) -ExplicitOnly:$ExplicitOnly
        return (($open -band $writeMask) -eq 0)
    } catch { return $false }
}

# Объект и весь путь до него (W11P-006): сам он — Test-ItemTrusted, а ни одну
# папку выше чужой не может переименовать, удалить, перенастроить или
# вычистить вложенное (Test-DirChainSecure). Иначе папку с проверенными
# правами можно было бы подменить целиком, переименовав её родителя.
function Test-PathTrusted {
    param([string]$Path)
    try { $it = Get-Item -LiteralPath $Path -Force -ErrorAction Stop } catch { return $false }
    if (-not (Test-ItemTrusted $it)) { return $false }
    $parent = Split-Path -Path $it.FullName -Parent
    if (-not $parent) { return $true }
    return (Test-DirChainSecure $parent)
}

# Всё недоверенное на любой глубине. Внутрь ссылок и чужих папок не заходим:
# они уходят в карантин целиком.
# Путь внутри собирается из имён: отрезать начало полного пути нельзя — у
# временной папки бывает короткое имя 8.3, а у найденного — длинное.
function Get-UntrustedItems {
    param([string]$Dir, [string]$Rel = '', [switch]$ExplicitOnly)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($c in @(Get-ChildItem -LiteralPath $Dir -Force -ErrorAction SilentlyContinue)) {
        $r = $(if ($Rel) { Join-Path $Rel $c.Name } else { $c.Name })
        if (-not (Test-ItemTrusted $c -ExplicitOnly:$ExplicitOnly)) { $out.Add([pscustomobject]@{ Item = $c; Rel = $r }); continue }
        if ($c.PSIsContainer) { foreach ($x in @(Get-UntrustedItems $c.FullName $r -ExplicitOnly:$ExplicitOnly)) { $out.Add($x) } }
    }
    return $out.ToArray()
}

# Найденное недоверенное — в свежий карантин рядом, с тем же путём внутри.
function Move-UntrustedAside {
    param([string]$Dir, [object[]]$Untrusted)
    if (@($Untrusted).Count -eq 0) { return $true }
    $aside = New-QuarantineDir $Dir
    if (-not $aside) { Write-Log '   [!] не удалось завести папку карантина -- чужое в папке данных не тронуто'; return $false }
    foreach ($u in $Untrusted) {
        $to = Join-Path $aside $u.Rel
        $toDir = Split-Path $to -Parent
        if (-not (Test-Path -LiteralPath $toDir)) { New-Item -ItemType Directory -Path $toDir -Force | Out-Null }
        if ($u.Item.PSIsContainer) { [IO.Directory]::Move($u.Item.FullName, $to) } else { [IO.File]::Move($u.Item.FullName, $to) }
        Write-Log ("   [!] в папке данных лежал чужой файл, он отложен: {0}" -f $u.Rel)
    }
    return $true
}

# Свежая пустая папка карантина рядом с корнем: имя со случайным хвостом,
# которого заранее не угадать, и мы сами её создаём. Предсказуемый путь
# «<корень>.untrusted-<время>» обычный пользователь мог завести заранее —
# папкой или junction, — и перенос «чужого» с правами администратора ушёл бы
# по ссылке в защищённую папку. Создать не вышло или на месте оказалась
# ссылка — пустая строка, карантин не делается.
function New-QuarantineDir {
    param([string]$Dir)
    # Права карантину задаём сразу при создании — только система и
    # администраторы, наследование выключено. Раньше папка наследовала права
    # ProgramData, где обычный пользователь вправе заводить свои файлы и папки;
    # в карантин же «чужое» переносится с правами администратора. Права ставим
    # лишь под администратором: обычному процессу сменить владельца на
    # «Администраторы» система не даёт, а наяву карантин делает только
    # повышенный движок (Protect-DataRoot).
    $sec = $null
    $isAdmin = $false
    try { $isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { }
    if ($isAdmin) {
        try {
            $sec = New-Object System.Security.AccessControl.DirectorySecurity
            $sec.SetAccessRuleProtection($true, $false)
            $inh = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
            foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
                $sec.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', $inh, 'None', 'Allow')))
            }
            $sec.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
        } catch { $sec = $null }
    }
    for ($i = 0; $i -lt 20; $i++) {
        $cand = "$Dir.untrusted-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        if (Test-Path -LiteralPath $cand) { continue }
        try {
            if ($sec) { $null = [IO.Directory]::CreateDirectory($cand, $sec) }
            else { $null = [IO.Directory]::CreateDirectory($cand) }
        } catch {
            # не вышло задать права — создаём хотя бы саму папку: содержимому
            # карантина всё равно не верят, а отказ хуже слабых прав
            try { $null = [IO.Directory]::CreateDirectory($cand) } catch { continue }
        }
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
        # Унаследованные от ProgramData права тут не в счёт: их сейчас же
        # заменят права нового корня.
        if (-not (Move-UntrustedAside $Dir @(Get-UntrustedItems $Dir -ExplicitOnly))) { return $false }
        [IO.Directory]::SetAccessControl($Dir, $sec)
        if (-not (Test-DirSecure $Dir)) { return $false }
        # Новые права корня разошлись по вложенному — теперь проверяем всё
        # полностью, с унаследованным (W11P-006). Обычно здесь пусто; если
        # нет — в карантин и это.
        if (-not (Move-UntrustedAside $Dir @(Get-UntrustedItems $Dir))) { return $false }
        return (Test-DirSecure $Dir)
    } catch {
        Write-Log ("   [!] не удалось защитить папку данных {0}: {1}" -f $Dir, $_.Exception.Message)
        return $false
    }
}

# Корень защищён, и путь до него (ProgramData, корень диска) не даёт чужому
# переименовать или удалить его целиком (W11P-006): иначе закрытую папку
# можно было бы отодвинуть и положить на её место свою.
function Test-SafeRootChain {
    return [bool](Test-DirChainSecure (Split-Path $script:SafeRoot -Parent))
}

function Assert-SafeRoot {
    if ($null -eq $script:RootState) {
        $chain = [bool](Test-SafeRootChain)
        if (-not $chain) { Write-Log ("   [!] папку {0} может переименовать или удалить не администратор -- защищённой папке данных там не место" -f (Split-Path $script:SafeRoot -Parent)) }
        $script:RootState = $chain -and [bool](Protect-DataRoot $script:SafeRoot)
    }
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

# --------------------------------------------------------------------------- #
#  Личная рабочая папка для файла, который пишет системная утилита, а читает
#  движок с правами администратора (T-2: копия политики аудита, auditpol
#  /backup). Раньше, пока защищённого корня ещё не было, файл ложился во
#  временную папку пользователя: её может менять любая его программа, и
#  подменённая или недописанная копия читалась бы с правами администратора
#  (по ней — состояние монитора и «как было» в журнале отката), а сама
#  временная папка могла оказаться ссылкой (junction) — auditpol писал бы по ней.
#  Повышенный движок берёт только место, куда обычной программе не дотянуться:
#    * защищённый корень ProgramData\Win11Privacy, если он уже есть и проверен
#      вместе с путём (Test-PathTrusted). Без побочных действий: чтение
#      политики корень не заводит и не чинит (Assert-SafeRoot здесь не зовётся);
#    * иначе — системная временная папка Windows\Temp, если ни одну папку на
#      пути к ней чужой не может удалить, переименовать или перенастроить
#      (Test-DirChainSecure). Создавать в ней пользователи могут, а читать
#      её список и чужие файлы, удалять чужое — нет.
#  Там заводится новая папка со случайным именем и с правами с самого
#  создания: только система и администраторы, без наследования, владелец —
#  «Администраторы». Имя уже занято или папка после создания не прошла
#  проверку (ссылка, чужой владелец, чужие права, не пуста) — она не наша.
#  Без повышения границы прав нет (движок может то же, что любая программа
#  пользователя) — годится и обычная временная папка.
#  Ответ: путь новой пустой папки или '' — тогда файла не будет вовсе (отказ).
# --------------------------------------------------------------------------- #
function New-PrivateWorkDir {
    param([string]$Prefix)
    $leaf = $Prefix + [guid]::NewGuid().ToString('N')
    if (-not (Test-Admin)) {
        $dir = Join-Path ([IO.Path]::GetTempPath()) $leaf
        if (Test-Path -LiteralPath $dir) { return '' }
        try { $null = [IO.Directory]::CreateDirectory($dir) } catch { return '' }
        return $dir
    }
    $bases = New-Object System.Collections.Generic.List[string]
    if ($script:SafeRoot -and (Test-Path -LiteralPath $script:SafeRoot -PathType Container) -and (Test-PathTrusted $script:SafeRoot)) { $bases.Add($script:SafeRoot) }
    $sysTemp = Join-Path $env:SystemRoot 'Temp'
    if ((Test-Path -LiteralPath $sysTemp -PathType Container) -and (Test-DirChainSecure $sysTemp)) { $bases.Add($sysTemp) }
    foreach ($b in $bases.ToArray()) {
        Remove-StalePrivateDirs $b $Prefix
        $dir = Join-Path $b $leaf
        if (Test-Path -LiteralPath $dir) { continue }
        $sec = New-Object System.Security.AccessControl.DirectorySecurity
        $sec.SetAccessRuleProtection($true, $false)
        $inh = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
            $sec.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', $inh, 'None', 'Allow')))
        }
        $sec.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
        try { $null = [IO.Directory]::CreateDirectory($dir, $sec) } catch { continue }
        $ok = $false
        try {
            $it = Get-Item -LiteralPath $dir -Force -ErrorAction Stop
            $ok = (Test-ItemTrusted $it) -and (@(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop).Count -eq 0)
        } catch { $ok = $false }
        if ($ok) { return $dir }
        # Не прошла проверку. Свою (владелец доверенный) — убираем; чужую не
        # трогаем: по ссылкам Remove-TreeNoFollow не ходит, а чужое не удаляет.
        $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
        Remove-TreeNoFollow $dir $st -TrustedOwnerOnly
    }
    return ''
}

# Личные рабочие папки, оставшиеся от оборванного запуска, — через час.
# Только с доверенным владельцем и не ссылки: в Windows\Temp папку с таким
# же началом имени мог завести кто угодно.
function Remove-StalePrivateDirs {
    param([string]$Base, [string]$Prefix)
    $cut = (Get-Date).AddHours(-1)
    foreach ($d in @(Get-ChildItem -LiteralPath $Base -Directory -Force -Filter ($Prefix + '*') -ErrorAction SilentlyContinue)) {
        if ($d.LastWriteTime -gt $cut -or ($d.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
        Remove-TreeNoFollow $d.FullName $st -TrustedOwnerOnly
    }
}

# Файл из личной рабочей папки: в папке — ровно он один, это обычный файл (не
# ссылка и не папка), его владелец — система или администраторы (у
# повышенного движка), он не больше $MaxBytes и появился не раньше $Since.
# Читается один раз, открытым без права записи для других. Иначе — $null:
# такому файлу не верят, а не читают «что есть».
function Read-PrivateWorkFile {
    param([string]$Dir, [string]$Name, [datetime]$Since = [datetime]::MinValue, [int]$MaxBytes = 4194304)
    try {
        $all = @(Get-ChildItem -LiteralPath $Dir -Force -ErrorAction Stop)
        if ($all.Count -ne 1 -or $all[0].Name -cne $Name -or $all[0].PSIsContainer) { return $null }
        $it = $all[0]
        if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $null }
        if ($it.Length -gt $MaxBytes) { return $null }
        if ($it.CreationTimeUtc -lt $Since.ToUniversalTime()) { return $null }
        if ((Test-Admin) -and $script:TrustedSids -notcontains (Get-OwnerSid $it.FullName)) { return $null }
        $fs = [IO.File]::Open($it.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            $ms = New-Object System.IO.MemoryStream
            $fs.CopyTo($ms)
            return $ms.ToArray()
        } finally { $fs.Dispose() }
    } catch { return $null }
}

# Личная рабочая папка — прочь, обходом без ссылок
function Remove-PrivateWorkDir {
    param([string]$Dir)
    if (-not $Dir) { return }
    $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
    Remove-TreeNoFollow $Dir $st
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
        $busy = $false
        try {
            if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($Tmp, $Path, [NullString]::Value) }
            else { [IO.File]::Move($Tmp, $Path) }
            return
        } catch {
            # Вид ошибки — по самому исключению .NET (см. Test-IoBusy). Любая
            # ошибка ввода-вывода — повтор, как и раньше: файл на месте мог
            # появиться или пропасть между проверкой и заменой (Test-Path
            # смотрится заново).
            if (-not ($_.Exception.GetBaseException() -is [System.IO.IOException]) -or $try -ge 30) { throw }
            $busy = $true
        }
        if ($busy) { Start-Sleep -Milliseconds 100 }
    }
}

# Вид ошибки ввода-вывода — по самому исключению .NET, а не по фильтру
# catch [тип] (T-4). Windows PowerShell 5.1 в цикле с ожиданием начинал (на
# 18-м проходе, проверено) отдавать «файл занят другим процессом» —
# IOException, обёрнутую в MethodInvocationException, — ветке
# catch [DirectoryNotFoundException]: Read-TextShared отвечал «файла нет», и
# занятый журнал отката читался как отсутствующий. Любая программа
# пользователя может открыть журнал на чтение (права корня — «Пользователи:
# чтение») без совместного доступа и так подменить повышенному движку «журнал
# пуст»: откат сказал бы «возвращать нечего», а следующая запись затёрла бы
# историю «как было».
#   Test-IoMissing — файла или папки нет; Test-IoBusy — занят (повторить можно).
function Test-IoMissing {
    param($Exception)
    $ex = $Exception.GetBaseException()
    return ($ex -is [System.IO.FileNotFoundException] -or $ex -is [System.IO.DirectoryNotFoundException])
}
function Test-IoBusy {
    param($Exception)
    $ex = $Exception.GetBaseException()
    return ($ex -is [System.IO.IOException] -and -not (Test-IoMissing $Exception))
}

# Текст файла данных. Открывается с правом на чтение, запись и удаление для
# других: замена файла другим запуском (ReplaceFile) не упрётся в нас, а мы
# прочитаем либо прежний файл, либо новый — целиком. Занят без права на
# чтение (антивирус) — ждём и пробуем снова; не вышло — ошибка, а не «пусто».
# Файла нет — $null. Вид ошибки — Test-IoMissing / Test-IoBusy (T-4).
function Read-TextShared {
    param([string]$Path)
    for ($try = 1; ; $try++) {
        $busy = $false
        try {
            $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
                                         ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            try {
                $sr = New-Object System.IO.StreamReader($fs, (New-Object System.Text.UTF8Encoding $false), $true)
                return $sr.ReadToEnd()
            } finally { $fs.Dispose() }
        } catch {
            if (Test-IoMissing $_.Exception) { return $null }
            if (-not (Test-IoBusy $_.Exception) -or $try -ge 30) { throw }
            $busy = $true
        }
        if ($busy) { Start-Sleep -Milliseconds 100 }
    }
}
