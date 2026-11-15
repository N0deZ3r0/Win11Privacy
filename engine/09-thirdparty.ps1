
# =========================================================================== #
#  Файлы конфигурации сторонних программ
# =========================================================================== #
# Файл настроек того, кто сидит за компьютером (см. Convert-ToSessionPath)
function Get-VsCodeSettingsPath { return (Convert-ToSessionPath (Join-Path $env:APPDATA 'Code\User\settings.json')) }

function Get-VsCodeValue {
    param([string]$Key)
    $p = Get-VsCodeSettingsPath
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $txt = Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue
    if (-not $txt) { return $null }
    $rx = '"' + [regex]::Escape($Key) + '"\s*:\s*("(?<s>[^"]*)"|(?<b>true|false)|(?<n>-?[\d.]+))'
    $m = [regex]::Match($txt, $rx)
    if (-not $m.Success) { return $null }
    if ($m.Groups['s'].Success) { return $m.Groups['s'].Value }
    if ($m.Groups['b'].Success) { return ($m.Groups['b'].Value -eq 'true') }
    return $m.Groups['n'].Value
}

# Значение ключа как оно написано в файле («off», true, 14) — его и вернёт
# откат. @{ fileExists; exists; token }. Раньше откат возвращал не ключи, а
# весь файл копией, снятой при первом применении: всё, что человек поменял в
# настройках позже, пропадало (проверено на VM).
function Get-VsCodeRaw {
    param([string]$Key)
    $p = Get-VsCodeSettingsPath
    $out = @{ fileExists = $false; exists = $false; token = '' }
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $out }
    $out.fileExists = $true
    $txt = Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue
    if (-not $txt) { return $out }
    $m = [regex]::Match($txt, '"' + [regex]::Escape($Key) + '"\s*:\s*("[^"]*"|true|false|-?[\d.]+)')
    if ($m.Success) { $out.exists = $true; $out.token = $m.Groups[1].Value }
    return $out
}

# Значение для JSON: строка — в кавычках, да/нет — словом, число — как есть
function ConvertTo-JsonToken {
    param($Value)
    if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }
    if ($Value -is [string]) { return ('"' + ($Value -replace '([\\"])', '\$1') + '"') }
    return "$Value"
}

# Обратно: из записи журнала — значение того же вида, что было в файле
function ConvertFrom-JsonToken {
    param([string]$Token)
    $t = "$Token".Trim()
    if ($t -eq 'true') { return $true }
    if ($t -eq 'false') { return $false }
    if ($t.StartsWith('"')) { return ($t.Substring(1, [Math]::Max(0, $t.Length - 2)) -replace '\\([\\"])', '$1') }
    $n = 0.0
    if ([double]::TryParse($t, [ref]$n)) { if ($t -notmatch '\.') { return [int]$n }; return $n }
    return $t
}

# Сценарий для задачи от имени пользователя: правит settings.json в его
# профиле. Писать туда с правами администратора нельзя — в папку профиля
# пишет любая его программа, и подменённый ссылкой settings.json увёл бы
# запись с этими правами в чужой файл. token = '' — ключ убрать.
# removeFileIfEmpty — если после этого в файле не осталось ни одного ключа и
# файл завела сама программа, он удаляется.
function Get-VsCodeWriteScript {
    return @'
param([string]$InputFile, [string]$ResultFile)
$in = (Get-Content -LiteralPath $InputFile -Raw -Encoding UTF8) | ConvertFrom-Json
$p = "$($in.path)"
$res = @{ ok = $false; why = ''; removedFile = $false }
try {
  $dir = Split-Path $p -Parent
  foreach ($d in @($dir, $p)) {
    if ((Test-Path -LiteralPath $d) -and ((Get-Item -LiteralPath $d -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
      throw 'на пути к файлу настроек стоит ссылка'
    }
  }
  if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
  $txt = $(if (Test-Path -LiteralPath $p -PathType Leaf) { Get-Content -LiteralPath $p -Raw -ErrorAction Stop } else { '' })
  if (-not $txt -or $txt.Trim() -eq '') { $txt = "{`r`n}" }
  $key = "$($in.key)"
  if ($key -eq '') {
    # без ключа — только «удалить файл, если он пуст»; ничего не переписывается
    if ($in.removeFileIfEmpty -and (Test-Path -LiteralPath $p -PathType Leaf) -and (($txt -replace '\s', '') -eq '{}')) {
      [IO.File]::Delete($p); $res.removedFile = $true
    }
    $res.ok = $true
    ConvertTo-Json -InputObject $res -Depth 4 -Compress | Set-Content -LiteralPath $ResultFile -Encoding UTF8
    return
  }
  $rx = '(\s*)"' + [regex]::Escape($key) + '"(\s*):(\s*)("[^"]*"|true|false|-?[\d.]+)(\s*,?)'
  $tok = "$($in.token)"
  if ($tok -eq '') {
    $m = [regex]::Match($txt, $rx)
    if ($m.Success) {
      $before = $txt.Substring(0, $m.Index); $after = $txt.Substring($m.Index + $m.Length)
      # наш ключ был последним (запятой после него нет) — запятая, оставшаяся
      # на предыдущем, сделала бы файл негодным; больше ничего в файле не трогаем
      $tail = $m.Groups[5].Value
      if (-not $tail.Contains(',')) { $before = [regex]::Replace($before, ',(\s*)$', '$1'); $after = $tail + $after }
      $txt = $before + $after
    }
  } elseif ([regex]::IsMatch($txt, $rx)) {
    $txt = [regex]::Replace($txt, $rx, ('${1}"' + $key + '"${2}:${3}' + $tok.Replace('$', '$$') + '${5}'), 1)
  } else {
    $i = $txt.IndexOf('{')
    if ($i -lt 0) { $txt = "{`r`n}"; $i = 0 }
    $rest = $txt.Substring($i + 1)
    $ins = "`r`n    `"$key`": $tok,"
    if ($rest.Trim() -eq '}') { $ins = $ins.TrimEnd(',') + "`r`n" }
    $txt = $txt.Substring(0, $i + 1) + $ins + $rest
  }
  $empty = ($txt -replace '\s', '') -eq '{}'
  if ($empty -and $in.removeFileIfEmpty -and (Test-Path -LiteralPath $p -PathType Leaf)) {
    [IO.File]::Delete($p); $res.removedFile = $true
  } else {
    [IO.File]::WriteAllText($p, $txt, (New-Object System.Text.UTF8Encoding($false)))
  }
  $res.ok = $true
} catch { $res.why = "$($_.Exception.Message)" }
ConvertTo-Json -InputObject $res -Depth 4 -Compress | Set-Content -LiteralPath $ResultFile -Encoding UTF8
'@
}

# Правка settings.json: ключ ставится или убирается задачей от имени
# пользователя. $Token — готовое значение для JSON, '' — убрать ключ.
function Write-VsCodeKey {
    param([string]$Key, [string]$Token, [switch]$RemoveFileIfEmpty)
    $r = Invoke-AsUser 'vscode' (Get-VsCodeWriteScript) @{
            path = (Get-VsCodeSettingsPath); key = $Key; token = $Token
            removeFileIfEmpty = [bool]$RemoveFileIfEmpty } -Minutes 3
    if (-not $r.ok) { return @{ ok = $false; why = $r.why } }
    if (-not $r.result.ok) { return @{ ok = $false; why = "$($r.result.why)" } }
    return @{ ok = $true; why = ''; removedFile = [bool]$r.result.removedFile }
}

# После отката всех ключей: файл настроек, который завела сама программа и в
# котором ничего не осталось, удаляется. Решается один раз в конце, а не на
# каждой записи: у первой записи файл ещё полон остальных наших ключей.
function Remove-CreatedAppFile {
    param([string]$App)
    if ($App -eq 'vscode') {
        if (-not (Test-Path -LiteralPath (Get-VsCodeSettingsPath) -PathType Leaf)) { return }
        $w = Write-VsCodeKey '' '' -RemoveFileIfEmpty
        if (-not $w.ok) { Write-Log ("   [i] файл настроек VS Code, созданный программой, не проверен на пустоту: {0}" -f $w.why); return }
        if ($w.removedFile) { Write-Log '   [+] файл настроек VS Code создала программа и он опустел -- удалён' }
    }
}

function Set-VsCodeValue {
    param([string]$Key, $Value, [string]$Comment)
    if ($DryRun) { Write-Log "   [тест] $Comment"; return }
    # файл настроек не переписываем, если там уже стоит нужное
    $curVal = Get-VsCodeValue $Key
    if ($null -ne $curVal -and "$curVal".ToLower() -eq "$Value".ToLower()) {
        Write-Log "   [в] $Comment -- уже настроено"; $script:Already++; return
    }
    if (-not (Test-CanModify $Comment)) { return }
    Ensure-Backup
    # «Как было» — по ключу и в журнал, раньше самой правки: откат вернёт
    # ровно этот ключ и не тронет того, что человек поменял потом сам.
    $raw = Get-VsCodeRaw $Key
    $entry = @{ kind = 'appcfg'; app = 'vscode'; name = $Key; existed = [bool]$raw.exists
                old = "$($raw.token)"; newValue = (ConvertTo-JsonToken $Value)
                created = [bool](-not $raw.fileExists) }
    if (-not (Write-AheadEntry $entry)) {
        Write-Log "   [!] $Comment -- не меняется: «как было» не легло в журнал отката"; $script:Failures++; return
    }
    $w = Write-VsCodeKey $Key $entry.newValue
    if (-not $w.ok) {
        Undo-AheadEntry $entry
        Write-Log ("   [!] не удалось: {0} -- {1}" -f $Comment, $w.why); $script:Failures++; return
    }
    # «задача отработала» — ещё не «значение такое»: читаем обратно
    $now = Get-VsCodeRaw $Key
    if (-not $now.exists -or $now.token -ne $entry.newValue) {
        Write-Log ("   [!] {0} -- записано, но читается другое: {1}" -f $Comment, $(if ($now.exists) { $now.token } else { 'ключа нет' }))
        $script:Failures++; return
    }
    Write-Log "   [+] $Comment"; $script:Changes++
}

function Get-FirefoxPoliciesPath {
    foreach ($d in @((Join-Path $env:ProgramFiles 'Mozilla Firefox'), (Join-Path ${env:ProgramFiles(x86)} 'Mozilla Firefox'))) {
        if ($d -and (Test-Path -LiteralPath (Join-Path $d 'firefox.exe'))) { return (Join-Path $d 'distribution\policies.json') }
    }
    return $null
}

# Текст файла в UTF-8 (с меткой или без) — строго: файл в другой кодировке
# не «перекодируется» молча, а даёт ошибку. Раньше Get-Content без метки
# читал policies.json в кодировке ANSI, и при записи обратно кириллица в
# чужих политиках (адреса, названия закладок) превращалась в мусор.
function Read-Utf8Strict {
    param([string]$Path)
    $b = [IO.File]::ReadAllBytes($Path)
    $off = $(if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { 3 } else { 0 })
    return (New-Object System.Text.UTF8Encoding($false, $true)).GetString($b, $off, $b.Length - $off)
}

function Get-FirefoxPolicy {
    param([string]$Key)
    $p = Get-FirefoxPoliciesPath
    if (-not $p -or -not (Test-Path -LiteralPath $p)) { return $null }
    try { $j = Read-Utf8Strict $p | ConvertFrom-Json; return $j.policies.$Key } catch { return $null }
}

# --------------------------------------------------------------------------- #
#  Запись файла JSON одним действием (W11P-002). Раньше Set-Content писал
#  policies.json прямо на месте: оборванная запись (сбой, нехватка места,
#  выключение) оставляла файл пустым или недописанным — и с ним пропадали все
#  политики Firefox, в том числе корпоративные. Теперь:
#    1. текст проверяется разбором ещё в памяти;
#    2. пишется во временный файл с уникальным именем в той же папке (только
#       новым — CreateNew: на месте чужого файла или ссылки запись не идёт),
#       UTF-8 без метки, со сбросом на диск;
#    3. записанное читается обратно и разбирается ещё раз;
#    4. встаёт на место одним действием системы (Replace-FileAtomic:
#       ReplaceFile, если файл есть, — права и атрибуты прежнего сохраняются;
#       иначе переименование);
#    5. при любой ошибке прежний файл не тронут, временный удаляется.
# --------------------------------------------------------------------------- #
function Write-JsonFileAtomic {
    param([string]$Path, [string]$Json)
    $null = $Json | ConvertFrom-Json -ErrorAction Stop
    $dir = Split-Path $Path -Parent
    $tmp = Join-Path $dir ('.' + (Split-Path $Path -Leaf) + '.w11p-' + [guid]::NewGuid().ToString('N').Substring(0, 12) + '.tmp')
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Json)
    try {
        $fs = [IO.File]::Open($tmp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush($true) } finally { $fs.Dispose() }
        $back = Read-Utf8Strict $tmp
        if ($back -cne $Json) { throw 'записанный временный файл не совпадает с подготовленным' }
        $null = $back | ConvertFrom-Json -ErrorAction Stop
        Replace-FileAtomic $tmp $Path
        $tmp = $null
    } finally {
        if ($tmp -and (Test-Path -LiteralPath $tmp)) { try { [IO.File]::Delete($tmp) } catch { } }
    }
}

function Set-FirefoxPolicy {
    param([string]$Key, $Value, [string]$Comment)
    $p = Get-FirefoxPoliciesPath
    if (-not $p) { Write-Log "   [-] Firefox не найден"; return }
    if ($DryRun) { Write-Log "   [тест] $Comment"; return }
    $curVal = Get-FirefoxPolicy $Key
    if ($null -ne $curVal -and "$curVal".ToLower() -eq "$Value".ToLower()) {
        Write-Log "   [в] $Comment -- уже настроено"; $script:Already++; return
    }
    if (-not (Test-CanModify $Comment)) { return }
    Ensure-Backup
    # policies.json лежит в Program Files — туда пишет только администратор,
    # и записи по пути тут опасаться нечего. В журнал, как и у VS Code, идёт
    # один ключ: откат вернёт его, а не весь файл копией.
    $had = (Test-Path -LiteralPath $p -PathType Leaf)
    $prev = Get-FirefoxPolicy $Key
    $entry = @{ kind = 'appcfg'; app = 'firefox'; name = $Key; existed = [bool]($null -ne $prev)
                old = $(if ($null -ne $prev) { ConvertTo-JsonToken $prev } else { '' })
                newValue = (ConvertTo-JsonToken $Value); created = [bool](-not $had) }
    if (-not (Write-AheadEntry $entry)) {
        Write-Log "   [!] $Comment -- не меняется: «как было» не легло в журнал отката"; $script:Failures++; return
    }
    $w = Write-FirefoxKey $Key $Value
    if (-not $w.ok) {
        Undo-AheadEntry $entry
        Write-Log ("   [!] не удалось: {0} -- {1}" -f $Comment, $w.why); $script:Failures++; return
    }
    $now = Get-FirefoxPolicy $Key
    if ($null -eq $now -or "$now".ToLower() -ne "$Value".ToLower()) {
        Write-Log ("   [!] {0} -- записано, но читается другое: {1}" -f $Comment, $(if ($null -eq $now) { 'ключа нет' } else { "$now" }))
        $script:Failures++; return
    }
    Write-Log "   [+] $Comment"; $script:Changes++
}

# Ставит или убирает один ключ в policies.json. $Remove — убрать; если после
# этого в policies ничего не осталось и файл завела программа, он удаляется.
# Глубина JSON — 20: при 6 глубокие корпоративные политики обрезались.
function Write-FirefoxKey {
    param([string]$Key, $Value, [switch]$Remove)
    $p = Get-FirefoxPoliciesPath
    if (-not $p) { return @{ ok = $false; why = 'Firefox не найден' } }
    # Папка Firefox должна быть закрыта на запись для всех, кроме системы и
    # администраторов (так в Program Files по умолчанию): иначе между
    # проверками и заменой файла в ней мог бы подложить ссылку кто угодно.
    # W11P-006: проверяются и унаследованные права, и весь путь до папки —
    # её родителя тоже нельзя давать переименовать чужому.
    $ffPath = Split-Path (Split-Path $p -Parent) -Parent
    if (-not (Test-Path -LiteralPath $ffPath -PathType Container)) { return @{ ok = $false; why = 'папка Firefox не читается' } }
    if (-not (Test-PathTrusted $ffPath)) { return @{ ok = $false; why = 'папка Firefox (или папка выше) открыта на запись не только администраторам -- policies.json не трогаем' } }
    # Уже существующие distribution и policies.json — тоже только «свои»:
    # если их завела или может менять обычная программа, файл между чтением и
    # заменой подменили бы, а замена шла бы с правами администратора.
    foreach ($x in @((Split-Path $p -Parent), $p)) {
        if (-not (Test-Path -LiteralPath $x)) { continue }
        $xi = $null
        try { $xi = Get-Item -LiteralPath $x -Force -ErrorAction Stop } catch { }
        if (-not (Test-ItemTrusted $xi)) { return @{ ok = $false; why = ("{0} заведён не администратором или открыт на запись -- policies.json не трогаем" -f (Split-Path $x -Leaf)) } }
    }
    return (Update-FirefoxPoliciesFile $p $Key $Value -Remove:$Remove)
}

# Замок policies.json — общий для всех, кто его пишет: окно (движок с правами
# администратора в сеансе пользователя), страж и откат (задачи от имени
# системы в сеансе 0). Только Global\: раньше при ошибке открытия замок молча
# брался в Local\ — у каждого сеанса свой, и окно с задачей стража могли
# писать одновременно, теряя правки друг друга. Теперь не открылся — отказ.
#  * Новый замок заводится с правами только для системы, администраторов и
#    самого создателя — замок, заведённый задачей от имени системы, откроет и
#    движок окна (с правами по умолчанию системный замок администраторам
#    недоступен, и раньше это и уводило в Local\).
#  * Уже существующий замок годится, только если его владелец — система,
#    администраторы или мы сами. Замок, заранее заведённый обычной программой,
#    не используется: она могла бы держать его или отпускать, когда ей нужно.
function Test-MutexOwnerTrusted {
    param([string]$Sid)
    if (-not $Sid) { return $false }
    if (@('S-1-5-18', 'S-1-5-32-544') -contains $Sid) { return $true }
    try { return ($Sid -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) } catch { return $false }
}

function Open-FirefoxMutex {
    $name = 'Global\Win11Privacy-FirefoxPolicies'
    $sec = New-Object System.Security.AccessControl.MutexSecurity
    $sec.SetAccessRuleProtection($true, $false)
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User
    foreach ($sid in @((New-Object Security.Principal.SecurityIdentifier('S-1-5-18')), (New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')), $me)) {
        $sec.AddAccessRule((New-Object System.Security.AccessControl.MutexAccessRule($sid, [System.Security.AccessControl.MutexRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow)))
    }
    $created = $false
    try { $m = [System.Threading.Mutex]::new($false, $name, [ref]$created, $sec) }
    catch { throw ('замок policies.json не открылся ({0}) -- его мог заранее занять кто-то чужой' -f $_.Exception.Message) }
    if (-not $created) {
        $owner = ''
        try { $owner = $m.GetAccessControl().GetOwner([Security.Principal.SecurityIdentifier]).Value } catch { }
        if (-not (Test-MutexOwnerTrusted $owner)) { $m.Dispose(); throw 'замок policies.json заведён чужой программой -- не пишем' }
    }
    return $m
}

# Сам ключ в файле по явному пути (его же проверяют тесты на временной папке).
# Чтение, правка и запись — под общим замком всех запусков программы
# (окно, страж, откат): два писателя одновременно теряли бы правку друг друга.
function Update-FirefoxPoliciesFile {
    param([string]$Path, [string]$Key, $Value, [switch]$Remove)
    $mtx = $null; $got = $false
    try {
        $mtx = Open-FirefoxMutex
        try { $got = $mtx.WaitOne(30000) } catch [System.Threading.AbandonedMutexException] { $got = $true }
        if (-not $got) { return @{ ok = $false; why = 'policies.json сейчас меняет другой запуск программы' } }
        $dir = Split-Path $Path -Parent
        foreach ($d in @($dir, $Path)) {
            if ((Test-Path -LiteralPath $d) -and ((Get-Item -LiteralPath $d -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                return @{ ok = $false; why = 'на пути к policies.json стоит ссылка' }
            }
        }
        if (-not (Test-Path -LiteralPath $dir)) {
            $null = [IO.Directory]::CreateDirectory($dir)
            if ((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return @{ ok = $false; why = 'на пути к policies.json стоит ссылка' } }
        }
        # Свои временные файлы, оставшиеся от оборванной записи, — через час
        foreach ($old in @(Get-ChildItem -LiteralPath $dir -File -Force -Filter ('.' + (Split-Path $Path -Leaf) + '.w11p-*.tmp') -ErrorAction SilentlyContinue)) {
            if ($old.LastWriteTime -lt (Get-Date).AddHours(-1) -and -not ($old.Attributes -band [IO.FileAttributes]::ReparsePoint)) { try { [IO.File]::Delete($old.FullName) } catch { } }
        }
        $obj = $null
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $ff = $null
            try { $ff = Read-Utf8Strict $Path } catch { return @{ ok = $false; why = 'policies.json не в кодировке UTF-8 -- не трогаем, чтобы не испортить чужие политики' } }
            if ("$ff".Trim()) {
                try { $obj = $ff | ConvertFrom-Json -ErrorAction Stop } catch { $obj = $null }
                # Файл есть, но не разобрался (комментарий, политика, с которой
                # не справился разбор PowerShell 5.1). Не перезаписываем: иначе
                # пропали бы уже стоящие там политики, в том числе корпоративные.
                if ($null -eq $obj) { return @{ ok = $false; why = 'policies.json есть, но не разбирается как JSON -- не трогаем, чтобы не стереть чужие политики' } }
            }
        }
        if (-not $obj) { $obj = New-Object PSObject }
        if (-not ($obj.PSObject.Properties.Name -contains 'policies')) { $obj | Add-Member -NotePropertyName 'policies' -NotePropertyValue (New-Object PSObject) }
        if ($Remove) {
            if ($obj.policies.PSObject.Properties.Name -contains $Key) { $obj.policies.PSObject.Properties.Remove($Key) }
            if (@($obj.policies.PSObject.Properties).Count -eq 0 -and @($obj.PSObject.Properties).Count -eq 1) {
                if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::Delete($Path) }
                return @{ ok = $true; why = ''; removedFile = $true }
            }
        } elseif ($obj.policies.PSObject.Properties.Name -contains $Key) { $obj.policies.$Key = $Value }
        else { $obj.policies | Add-Member -NotePropertyName $Key -NotePropertyValue $Value }
        Write-JsonFileAtomic $Path ($obj | ConvertTo-Json -Depth 20)
        return @{ ok = $true; why = '' }
    } catch { return @{ ok = $false; why = $_.Exception.Message } }
    finally {
        if ($got) { try { $mtx.ReleaseMutex() } catch { } }
        if ($null -ne $mtx) { $mtx.Dispose() }
    }
}
