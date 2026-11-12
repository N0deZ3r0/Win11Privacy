
# =========================================================================== #
#  Файлы конфигурации сторонних программ
# =========================================================================== #
function Get-VsCodeSettingsPath { return (Join-Path $env:APPDATA 'Code\User\settings.json') }

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

function Set-VsCodeValue {
    param([string]$Key, $Value, [string]$Comment)
    $p = Get-VsCodeSettingsPath
    if ($DryRun) { Write-Log "   [тест] $Comment"; return }
    # файл настроек не переписываем, если там уже стоит нужное
    $curVal = Get-VsCodeValue $Key
    if ($null -ne $curVal -and "$curVal".ToLower() -eq "$Value".ToLower()) {
        Write-Log "   [в] $Comment -- уже настроено"; $script:Already++; return
    }
    Ensure-Backup
    try {
        $dir = Split-Path $p -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $txt = if (Test-Path -LiteralPath $p) { Get-Content -LiteralPath $p -Raw -ErrorAction Stop } else { '' }
        if (-not $txt -or $txt.Trim() -eq '') { $txt = "{`n}" }
        $bak = "$p.win11privacy.bak"
        if (-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $p -Destination $bak -Force -ErrorAction SilentlyContinue }
        $jsonVal = if ($Value -is [bool]) { $Value.ToString().ToLower() } elseif ($Value -is [string]) { '"' + $Value + '"' } else { "$Value" }
        $rx = '("' + [regex]::Escape($Key) + '"\s*:\s*)("[^"]*"|true|false|-?[\d.]+)'
        if ([regex]::IsMatch($txt, $rx)) {
            $txt = [regex]::Replace($txt, $rx, ('${1}' + $jsonVal), 1)
        } else {
            $idx = $txt.IndexOf('{')
            if ($idx -lt 0) { $txt = "{`n}"; $idx = 0 }
            $insert = "`n    `"$Key`": $jsonVal,"
            $rest = $txt.Substring($idx + 1)
            if ($rest.Trim() -eq '}') { $insert = $insert.TrimEnd(',') + "`n" }
            $txt = $txt.Substring(0, $idx + 1) + $insert + $rest
        }
        [IO.File]::WriteAllText($p, $txt, (New-Object System.Text.UTF8Encoding($false)))
        Write-Log "   [+] $Comment"; $script:Changes++
    } catch { Write-Log "   [!] не удалось: $Comment -- $($_.Exception.Message)"; $script:Failures++ }
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
    Ensure-Backup
    try {
        $dir = Split-Path $p -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $obj = $null
        if (Test-Path -LiteralPath $p) {
            $bak = "$p.win11privacy.bak"
            if (-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $p -Destination $bak -Force -ErrorAction SilentlyContinue }
            try { $obj = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json } catch { $obj = $null }
        }
        if (-not $obj) { $obj = New-Object PSObject }
        if (-not ($obj.PSObject.Properties.Name -contains 'policies')) { $obj | Add-Member -NotePropertyName 'policies' -NotePropertyValue (New-Object PSObject) }
        if ($obj.policies.PSObject.Properties.Name -contains $Key) { $obj.policies.$Key = $Value }
        else { $obj.policies | Add-Member -NotePropertyName $Key -NotePropertyValue $Value }
        ($obj | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $p -Encoding UTF8
        Write-Log "   [+] $Comment"; $script:Changes++
    } catch { Write-Log "   [!] не удалось: $Comment -- $($_.Exception.Message)"; $script:Failures++ }
}
