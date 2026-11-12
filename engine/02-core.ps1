
# =========================================================================== #
#  Служебные функции
# =========================================================================== #
function Write-Log { param([string]$Message = '') Write-Host $Message }
function Write-Section { param([string]$Title) Save-JournalEntries -Quiet; Write-Log ''; Write-Log ('--- ' + $Title + ' ' + ('-' * [Math]::Max(3, 60 - $Title.Length))) }
function Emit-Json { param($Object) Write-Host ('###JSON### ' + ($Object | ConvertTo-Json -Compress -Depth 8)) }
function Use-Module { param([string]$Name) return ($Modules -contains $Name) }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try { $p = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop; return $p.$Name } catch { return $null }
}

# Запасная запись мимо провайдера PowerShell: обычный API реестра просит
# ровно те права, которые нужны, и иногда справляется там, где New-ItemProperty
# уже получил отказ. Заодно рассказывает, чем именно кончилась попытка.
function Set-RegDirect {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    try {
        $hive = $null; $sub = ''
        if ($Path -match '^HKLM:\\(.+)$')      { $hive = [Microsoft.Win32.Registry]::LocalMachine; $sub = $Matches[1] }
        elseif ($Path -match '^HKCU:\\(.+)$')  { $hive = [Microsoft.Win32.Registry]::CurrentUser;  $sub = $Matches[1] }
        elseif ($Path -match '^HKCR:\\(.+)$')  { $hive = [Microsoft.Win32.Registry]::ClassesRoot;  $sub = $Matches[1] }
        elseif ($Path -match '^HKU:\\(.+)$')   { $hive = [Microsoft.Win32.Registry]::Users;        $sub = $Matches[1] }
        else { return @{ ok = $false; error = 'неизвестный куст реестра' } }
        $key = $hive.CreateSubKey($sub, $true)
        if ($null -eq $key) { return @{ ok = $false; error = 'ключ не открылся на запись' } }
        try {
            switch ($Type) {
                'DWord'        { $key.SetValue($Name, [int]$Value,  [Microsoft.Win32.RegistryValueKind]::DWord) }
                'QWord'        { $key.SetValue($Name, [long]$Value, [Microsoft.Win32.RegistryValueKind]::QWord) }
                'Binary'       { $key.SetValue($Name, [byte[]]$Value, [Microsoft.Win32.RegistryValueKind]::Binary) }
                'ExpandString' { $key.SetValue($Name, [string]$Value, [Microsoft.Win32.RegistryValueKind]::ExpandString) }
                'MultiString'  { $key.SetValue($Name, [string[]]$Value, [Microsoft.Win32.RegistryValueKind]::MultiString) }
                default        { $key.SetValue($Name, [string]$Value, [Microsoft.Win32.RegistryValueKind]::String) }
            }
        } finally { $key.Close() }
        return @{ ok = $true }
    } catch { return @{ ok = $false; error = ("{0}: {1}" -f $_.Exception.GetType().Name, $_.Exception.Message) } }
}

# Пишет во временный параметр рядом и сразу его убирает. Так видно, закрыт
# ли ключ целиком или Windows держит только один конкретный параметр.
function Test-RegKeyWritable {
    param([string]$Path)
    $probe = '_Win11PrivacyProbe'
    $r = Set-RegDirect -Path $Path -Name $probe -Value 1 -Type 'DWord'
    if (-not $r.ok) { return $false }
    try { Remove-ItemProperty -LiteralPath $Path -Name $probe -Force -ErrorAction SilentlyContinue } catch { }
    return $true
}

# Значение реестра в виде, который можно сравнить с задуманным: DWORD больше
# 0x7FFFFFFF читается отрицательным числом, расширяемая строка — уже
# раскрытой, двоичное и многострочное — массивами.
function ConvertTo-RegComparable {
    param($Value, [string]$Type)
    if ($null -eq $Value) { return $null }
    switch ($Type) {
        'DWord' { try { $n = [decimal]"$Value"; if ($n -lt 0) { $n += [decimal]4294967296 }; return "$n" } catch { return "$Value" } }
        'QWord' { try { $n = [decimal]"$Value"; if ($n -lt 0) { $n += [decimal]::Parse('18446744073709551616') }; return "$n" } catch { return "$Value" } }
        'ExpandString' { return [Environment]::ExpandEnvironmentVariables("$Value") }
        'Binary' { return ((@($Value) | ForEach-Object { '{0:x2}' -f [byte]$_ }) -join '') }
        'MultiString' { return (@($Value) -join "`n") }
    }
    return "$Value"
}

function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord', [string]$Comment = '',
          [switch]$Policy, [string]$DefId = '')
    $label = if ($Comment) { $Comment } else { "$Path -> $Name" }
    if ($DryRun) { Write-Log "   [тест] $label"; return }

    # Если параметр уже такой, как нужно — не трогаем его: часть значений
    # панели задач Windows защищает от перезаписи даже тем же самым числом.
    $cur = Get-RegValue $Path $Name
    if ($null -ne $cur -and (ConvertTo-RegComparable $cur $Type) -eq (ConvertTo-RegComparable $Value $Type)) { Write-Log "   [в] $label -- уже настроено"; $script:Already++; return }

    # Менять можно, только пока пишется журнал отката, — в том числе при
    # прямых вызовах (монитор, чистка), а не только из применения модулей.
    if (-not (Test-CanModify $label)) { return }
    Ensure-Backup          # копию делаем перед первым изменением, а не «всегда»
    $existed = [bool]($null -ne $cur)
    $oldValue = $(if ($existed) { $cur } else { '' })
    # «Как было» — на диск раньше изменения (см. Write-AheadEntry). Если
    # изменение не пройдёт, запись отзывается: изменения ведь не было.
    $entry = @{ kind = 'reg'; path = $Path; name = $Name; type = $Type; existed = $existed; old = $oldValue; newValue = "$Value" }
    if (-not (Write-AheadEntry $entry)) {
        Write-Log "   [!] $label -- не меняется: «как было» не легло в журнал отката"
        $script:Failures++; return
    }
    $done = $false
    $why = ''
    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        $done = $true
    } catch {
        $why = ("{0}: {1}" -f $_.Exception.GetType().Name, $_.Exception.Message)
        $after = Get-RegValue $Path $Name
        if ($null -ne $after -and (ConvertTo-RegComparable $after $Type) -eq (ConvertTo-RegComparable $Value $Type)) {
            Undo-AheadEntry $entry
            Write-Log "   [в] $label -- уже настроено"; $script:Already++; return
        }
        $retry = Set-RegDirect -Path $Path -Name $Name -Value $Value -Type $Type
        if ($retry.ok) { $done = $true } else { $why += " / вторая попытка: $($retry.error)" }
    }

    if ($done) {
        # «Команда прошла» — ещё не «значение такое»: читаем обратно и сверяем.
        # Запись в журнале остаётся в любом случае: значение уже не прежнее.
        $now = Get-RegValue $Path $Name
        $want = ConvertTo-RegComparable $Value $Type
        $got = ConvertTo-RegComparable $now $Type
        if ($null -eq $now -or $got -ne $want) {
            Write-Log ("   [!] {0} -- записано, но читается другое: ожидалось {1}, сейчас {2}" -f $label, $want, $(if ($null -eq $now) { 'нет значения' } else { $got }))
            $script:Failures++
            return
        }
        if ($Policy -and $DefId) { $script:UnblockedIds[$DefId] = $true }   # отдала — снимаем пометку
        Write-Log "   [+] $label"; $script:Changes++
        return
    }

    # изменения не было — заранее положенная запись отзывается
    Undo-AheadEntry $entry
    if ($why -like '*UnauthorizedAccessException*' -or $why -like '*SecurityException*') {
        # Часть политик Windows держит сама и не отдаёт даже администратору —
        # это не поломка программы, а решение системы, и в ошибки оно не идёт.
        if ($Policy) {
            Write-Log "   [-] $label -- Windows этой редакции не разрешает менять этот параметр"
            $script:Blocked++
            if ($DefId) { $script:BlockedIds[$DefId] = $true }
            return
        }
        Write-Log "   [!] $label -- Windows не отдаёт этот параметр даже администратору"
        Write-Log "       ключ: $Path -> $Name"
        Write-Log "       права администратора у программы: $(if (Test-Admin) { 'есть' } else { 'НЕТ' })"
        if (Test-RegKeyWritable $Path) {
            Write-Log "       ключ пишется, но именно этот параметр Windows защищает"
        } else {
            Write-Log "       ключ закрыт целиком: менять его может только сама система"
        }
        Write-Log "       подробности: $why"
    } else {
        Write-Log "   [!] не удалось: $label -- $why"
    }
    $script:Failures++
}

function Get-FolderSizeMB {
    param([string]$FolderPath)
    if (-not (Test-Path -LiteralPath $FolderPath)) { return 0 }
    # только файлы: у каталогов нет Length, и Measure-Object сыпал ошибкой в журнал
    $sum = (Get-ChildItem -LiteralPath $FolderPath -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    if (-not $sum) { return 0 }
    return [math]::Round($sum / 1MB, 1)
}

# Удаление дерева, которое не заходит внутрь ссылок. Remove-Item -Recurse в
# PowerShell 5.1 проходит по junction и символическим ссылкам и удаляет то,
# куда они ведут: ссылка во временной папке на «Документы» стёрла бы
# документы. Здесь ссылка удаляется сама, как запись, — её цель не трогается.
# $Stats — @{ deleted; failed; errors }: что удалено, что нет и почему.
function Remove-TreeNoFollow {
    param([string]$Path, $Stats)
    try { $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop } catch { return }
    try {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            if ($item.PSIsContainer) { [IO.Directory]::Delete($item.FullName, $false) } else { [IO.File]::Delete($item.FullName) }
            $Stats.deleted++
            return
        }
        if ($item.PSIsContainer) {
            foreach ($c in @(Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue)) { Remove-TreeNoFollow $c.FullName $Stats }
            # папка уходит, только если опустела: что внутри не удалилось, уже посчитано
            if (@(Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0) { [IO.Directory]::Delete($item.FullName, $false) }
            return
        }
        if ($item.Attributes -band [IO.FileAttributes]::ReadOnly) { $item.Attributes = $item.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly) }
        [IO.File]::Delete($item.FullName)
        $Stats.deleted++
    } catch {
        $Stats.failed++
        if ($Stats.errors.Count -lt 3) { $Stats.errors.Add(("{0}: {1}" -f $item.Name, $_.Exception.Message)) }
    }
}

# Папки, которые очищать нельзя ни при каком пути: корень диска и системные корни
function Test-ClearForbidden {
    param([string]$Full)
    $f = $Full.TrimEnd('\')
    if ($f -eq ([IO.Path]::GetPathRoot($Full)).TrimEnd('\')) { return $true }
    foreach ($p in @($env:SystemRoot, "$env:SystemRoot\System32", $env:ProgramData, $env:ProgramFiles, ${env:ProgramFiles(x86)},
                     $env:USERPROFILE, [Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('Desktop'), (Split-Path $env:USERPROFILE -Parent))) {
        if ($p -and $f -eq ([IO.Path]::GetFullPath($p)).TrimEnd('\')) { return $true }
    }
    return $false
}

function Clear-FolderContents {
    param([string]$FolderPath, [string]$Label, [string]$Step = '')
    if (-not (Test-Path -LiteralPath $FolderPath)) {
        if ($Step) { Write-Log ("   {0} {1} -- нечего чистить" -f $Step, $Label) }
        return 0.0
    }
    $full = [IO.Path]::GetFullPath($FolderPath)
    # Сама папка — ссылка (например, временную папку подменили junction на
    # «Документы») или корень, который чистить нельзя: отказ, а не удаление.
    $dirItem = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if (($dirItem -and ($dirItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) -or (Test-ClearForbidden $full)) {
        Write-Log ("   [!] {0} -- папка {1} ведёт не туда (ссылка или системная папка) -- не очищается" -f $Label, $full)
        $script:Failures++
        return 0.0
    }
    # Большую папку посчитать и вычистить — это минуты, а строка шага
    # появлялась только в конце, и чистка выглядела зависшей.
    if ($Step) { Write-Log ("   {0} {1}..." -f $Step, $Label) }
    $before = Get-FolderSizeMB $full
    if ($DryRun) { Write-Log ("   {0} [тест] {1} -- можно освободить ~{2} МБ" -f $Step, $Label, $before); return 0.0 }
    $st = @{ deleted = 0; failed = 0; errors = (New-Object System.Collections.Generic.List[string]) }
    foreach ($c in @(Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue)) { Remove-TreeNoFollow $c.FullName $st }
    $freed = [math]::Max(0, [math]::Round($before - (Get-FolderSizeMB $full), 1))
    if ($Step) { Write-Log ("   {0} {1} -- освобождено {2} МБ" -f $Step, $Label, $freed) }
    else { Write-Log ("   [+] {0} -- освобождено {1} МБ" -f $Label, $freed) }
    # Что не удалилось, называется: раньше ошибки глушились, и «освобождено»
    # выглядело полным. Занятые файлы — обычное дело, это сведения, а не сбой.
    if ($st.failed -gt 0) {
        Write-Log ("       не удалено (заняты или нет доступа): {0}" -f $st.failed)
        foreach ($e in $st.errors) { Write-Log ("       {0}" -f $e) }
    }
    $script:LastClear = $st
    return [double]$freed
}

# Задачи по маске имени (OneDrive*, NvTm*) — только в своих папках
# планировщика. Раньше проверялось одно имя: задача с подходящим именем
# годилась в любой папке, и откат журнала прежней версии мог включить чужую.
# OneDrive и NVIDIA кладут эти задачи в корень библиотеки.
$script:TaskGlobFolders = @{ 'OneDrive*' = @('\'); 'NvTm*' = @('\') }

function Get-TaskGlobFolders {
    param([string]$Glob)
    if ($script:TaskGlobFolders -and $script:TaskGlobFolders[$Glob]) { return @($script:TaskGlobFolders[$Glob]) }
    return @('\')
}

# полный путь задачи («\папка\имя») подходит под маску и её папки
function Test-TaskGlobPath {
    param([string]$Full, [string]$Glob)
    $pp = Split-TaskPath $Full
    return (((Get-TaskGlobFolders $Glob) -contains $pp[0]) -and ($pp[1] -like $Glob))
}

# -AnyFolder — только для прежнего отката: версии до 1.11 отключали задачи по
# маске в любой папке и в журнал их не писали; вернуть их можно лишь тем же
# поиском. Маски тут — свои, из списка программы, а не данные из журнала.
function Get-TaskGlobTasks {
    param([string]$Glob, [switch]$AnyFolder)
    $folders = @(Get-TaskGlobFolders $Glob)
    return @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { ($AnyFolder -or ($folders -contains $_.TaskPath)) -and ($_.TaskName -like $Glob) })
}

function Split-TaskPath {
    param([string]$Full)
    $name = Split-Path $Full -Leaf
    $path = (Split-Path $Full -Parent)
    if (-not $path.EndsWith('\')) { $path += '\' }
    return @($path, $name)
}

