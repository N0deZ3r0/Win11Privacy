
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
    $p = Get-VsCodeSettingsPath
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

function Get-FirefoxPolicy {
    param([string]$Key)
    $p = Get-FirefoxPoliciesPath
    if (-not $p -or -not (Test-Path -LiteralPath $p)) { return $null }
    try { $j = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json; return $j.policies.$Key } catch { return $null }
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
    try {
        $dir = Split-Path $p -Parent
        foreach ($d in @($dir, $p)) {
            if ((Test-Path -LiteralPath $d) -and ((Get-Item -LiteralPath $d -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                return @{ ok = $false; why = 'на пути к policies.json стоит ссылка' }
            }
        }
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
        $obj = $null
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            try { $obj = Get-Content -LiteralPath $p -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $obj = $null }
        }
        if (-not $obj) { $obj = New-Object PSObject }
        if (-not ($obj.PSObject.Properties.Name -contains 'policies')) { $obj | Add-Member -NotePropertyName 'policies' -NotePropertyValue (New-Object PSObject) }
        if ($Remove) {
            if ($obj.policies.PSObject.Properties.Name -contains $Key) { $obj.policies.PSObject.Properties.Remove($Key) }
            if (@($obj.policies.PSObject.Properties).Count -eq 0 -and @($obj.PSObject.Properties).Count -eq 1) {
                if (Test-Path -LiteralPath $p -PathType Leaf) { [IO.File]::Delete($p) }
                return @{ ok = $true; why = ''; removedFile = $true }
            }
        } elseif ($obj.policies.PSObject.Properties.Name -contains $Key) { $obj.policies.$Key = $Value }
        else { $obj.policies | Add-Member -NotePropertyName $Key -NotePropertyValue $Value }
        ($obj | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $p -Encoding UTF8 -ErrorAction Stop
        return @{ ok = $true; why = '' }
    } catch { return @{ ok = $false; why = $_.Exception.Message } }
}
