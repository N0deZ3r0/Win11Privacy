
# =========================================================================== #
#  МАШИНА ВРЕМЕНИ: снимки состояния и разница
# =========================================================================== #
$script:SnapDir = Join-Path $script:DataDir 'snapshots'

function Get-SnapshotState {
    $items = @{}
    foreach ($d in $script:Defs) {
        if ($d.T -in @('taskglob')) { continue }
        $r = Check-Def $d
        $items[($d.M + '|' + $d.C)] = @{ ok = $r.ok; actual = $r.actual }
    }
    return $items
}

function New-Snapshot {
    if (-not (Test-Path -LiteralPath $script:SnapDir)) { New-Item -ItemType Directory -Path $script:SnapDir -Force | Out-Null }
    $state = Get-SnapshotState
    $ok = @($state.Values | Where-Object { $_.ok }).Count
    $obj = @{
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        build = [System.Environment]::OSVersion.Version.Build
        ok = $ok; total = $state.Count
        hotfixes = @(Get-RecentHotfixes -Since (Get-Date).AddDays(-30))
        items = $state
    }
    $file = Join-Path $script:SnapDir ('snap-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    ($obj | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $file -Encoding UTF8
    return @{ file = (Split-Path $file -Leaf); time = $obj.time; ok = $ok; total = $state.Count }
}

function Get-SnapshotList {
    $list = @()
    if (Test-Path -LiteralPath $script:SnapDir) {
        foreach ($f in (Get-ChildItem -LiteralPath $script:SnapDir -Filter 'snap-*.json' | Sort-Object Name -Descending)) {
            try {
                $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $list += @{ file = $f.Name; time = $j.time; ok = $j.ok; total = $j.total; build = $j.build; hotfixes = @($j.hotfixes) }
            } catch { }
        }
    }
    return $list
}

if ($Snapshot) {
    $s = New-Snapshot
    Write-Section 'Снимок состояния'
    Write-Log ("   [+] сохранён снимок: {0} из {1} настроек на месте" -f $s.ok, $s.total)
    Emit-Json $s
    Write-Log '###DONE###'
    exit 0
}

if ($SnapshotList) {
    # ВАЖНО: список кладём через переменную. Если писать @{ x = (Функция) }, то
    # массив из одного элемента разворачивается, ConvertTo-Json пишет объект
    # вместо списка — и интерфейс показывает «пусто» на первом же снимке.
    $snapList = @(Get-SnapshotList)
    Emit-Json @{ snapshots = $snapList; count = $snapList.Count }
    exit 0
}

if ($SnapshotDiff) {
    $parts = $SnapshotDiff -split '\|'
    if ($parts.Count -ne 2) { Emit-Json @{ error = 'нужны два снимка' }; exit 1 }
    try {
        $a = Get-Content -LiteralPath (Join-Path $script:SnapDir $parts[0]) -Raw -Encoding UTF8 | ConvertFrom-Json
        $b = Get-Content -LiteralPath (Join-Path $script:SnapDir $parts[1]) -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch { Emit-Json @{ error = 'не удалось прочитать снимки' }; exit 1 }
    $diffChanges = @()
    foreach ($p in $a.items.PSObject.Properties) {
        $k = $p.Name
        $av = $p.Value
        $bp = $b.items.PSObject.Properties[$k]
        if (-not $bp) { continue }
        $bv = $bp.Value
        if ($av.ok -ne $bv.ok) {
            $parts2 = $k -split '\|', 2
            $diffChanges += @{ module = $parts2[0]; name = $parts2[1]
                           was = $(if ($av.ok) { 'на месте' } else { 'сбито' })
                           now = $(if ($bv.ok) { 'на месте' } else { 'сбито' })
                           broke = ($av.ok -and -not $bv.ok)
                           wasValue = [string]$av.actual; nowValue = [string]$bv.actual }
        }
    }
    Emit-Json @{ from = $a.time; to = $b.time; fromOk = $a.ok; toOk = $b.ok; total = $a.total
                 hotfixes = @($b.hotfixes); changes = $diffChanges
                 broke = @($diffChanges | Where-Object { $_.broke }).Count }
    exit 0
}
