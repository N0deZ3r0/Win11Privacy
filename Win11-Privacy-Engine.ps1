#Requires -Version 5.1
<#
    Win11-Privacy-Engine.ps1  (v3)
    Исполнительный модуль для Win11Privacy.exe. Может работать и сам по себе:

      -Modules telemetry,ads,cleanup        применить модули
      -Audit -Modules ...                   проверить реальное состояние (JSON)
      -Detect                               определить систему, установленные программы, статусы (JSON)
      -Monitor [-MonitorHours 24]           статистика перехваченных отправок (JSON)
      -EnableMonitor / -DisableMonitor      журнал аудита заблокированных соединений
      -InstallGuard -Modules ... / -RemoveGuard / -GuardNow
      -PurgeBuffer                          стереть неотправленную телеметрию
      -Revert                               откат всего

    Структурированные ответы печатаются строкой  ###JSON### {...}
#>

[CmdletBinding()]
param(
    [string[]]$Modules = @(),
    [switch]$DryRun,
    [switch]$NoBackup,
    [switch]$NoRestorePoint,
    [switch]$Revert,
    [string]$BackupRoot = '',
    [switch]$Detect,
    [switch]$Audit,
    [switch]$WithProof,
    [switch]$Monitor,
    [int]$MonitorHours = 24,
    [switch]$EnableMonitor,
    [switch]$DisableMonitor,
    [switch]$InstallGuard,
    [switch]$RemoveGuard,
    [switch]$Guard,
    [switch]$GuardNow,
    [switch]$PurgeBuffer,
    # --- рентген телеметрии ---
    [switch]$XrayStatus,
    [switch]$XrayEnable,
    [switch]$XrayDisable,
    [switch]$XrayScan,
    [int]$XrayHours = 24,
    [switch]$XrayBaseline,
    [switch]$XrayWipe,
    [int]$XrayMax = 20000,
    # --- машина времени ---
    [switch]$Snapshot,
    [switch]$SnapshotList,
    [string]$SnapshotDiff = '',
    # --- живые уведомления ---
    [switch]$InstallWatcher,
    [switch]$RemoveWatcher,
    [switch]$WatcherNotify,
    # --- досье: кто подглядывал и цифровой след ---
    [switch]$Spy,
    [switch]$Footprint,
    [switch]$FootprintWipe,
    [string[]]$WipeItems = @(),
    # --- слежение за датчиками: уведомление о новой программе ---
    [switch]$InstallSensorGuard,
    [switch]$RemoveSensorGuard,
    [switch]$SensorGuard,
    # --- слежение за сетью: уведомление о новой программе ---
    [switch]$InstallNetGuard,
    [switch]$RemoveNetGuard,
    [switch]$NetGuard,
    [switch]$SelfTest,
    # --- отдельные настройки внутри модулей ---
    [switch]$ListDefs,
    [string[]]$SkipItems = @(),
    # --- доступ программ к датчикам ---
    [switch]$SensorSet,
    [string]$SensorKey = '',
    [string]$SensorValue = 'Deny',
    # --- предустановленные приложения ---
    [switch]$ListApps,
    [switch]$RemoveApps,
    [string[]]$AppItems = @(),
    [switch]$AllUsers,
    # --- полный откат и все разрешения ---
    [switch]$RestoreAll,
    [switch]$ChangeLog,
    [switch]$SpyAll,
    # --- доказательство результата ---
    [switch]$Proof,
    [switch]$ProofSave,
    # --- автозагрузка ---
    [switch]$ListStartup,
    [switch]$StartupSet,
    [string[]]$StartupItems = @(),
    [string]$StartupValue = 'Off',
    # --- запрет выхода в сеть отдельной программе ---
    [switch]$BlockApp,
    [switch]$UnblockApp,
    [string]$AppPath = '',
    # --- журнал изменений и данные программы ---
    [switch]$RestoreItems,
    [string[]]$ChangeItems = @(),
    [switch]$DataInfo,
    [switch]$PurgeData,
    # --- как часто проверяет страж ---
    [switch]$GuardDaily,
    # --- уборка мусора от версий со сломанным Def ---
    [switch]$CleanJunk,
    # --- где хранить данные: рядом с exe вместо ProgramData ---
    [string]$DataRoot = '',
    # --- хронология и резервные копии ---
    [switch]$Timeline,
    [int]$TimelineDays = 30,
    [switch]$ListBackups,
    [switch]$RestoreBackup,
    [string]$BackupPath = '',
    # --- номер устройства в учётной записи Microsoft (GDID) ---
    [switch]$GdidStatus,
    # --- настройки пользователя — ещё и в другие профили и в профиль по умолчанию ---
    [switch]$AllProfiles,
    # --- проверка утечек: доходит ли соединение до серверов сбора ---
    [switch]$LeakTest,
    [switch]$GdidReissue,
    [switch]$GdidRestore
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# --------------------------------------------------------------------------- #
#  Ограниченный языковой режим PowerShell. На компьютерах с политикой
#  устройства (Device Guard/WDAC, AppLocker) PowerShell запускается в режиме
#  ConstrainedLanguage: почти все вызовы .NET, на которых держится движок,
#  в нём запрещены. Раньше скрипт падал посреди работы непонятной ошибкой —
#  теперь говорит прямо, что дело в политике, а не в программе.
# --------------------------------------------------------------------------- #
$script:LangMode = 'FullLanguage'
try { $script:LangMode = [string]$ExecutionContext.SessionState.LanguageMode } catch { }
if ($script:LangMode -ne 'FullLanguage') {
    Write-Host ('PowerShell на этом компьютере работает в ограниченном режиме: ' + $script:LangMode + '.')
    Write-Host 'Так его настроила политика устройства -- Device Guard (WDAC) или AppLocker. Обычно это рабочий компьютер организации.'
    Write-Host 'В таком режиме программа не может ни прочитать состояние системы, ни изменить его: запрещены сами средства, которыми она работает.'
    Write-Host ('###JSON### {"error":"languageMode","languageMode":"' + $script:LangMode + '"}')
    Write-Host '###DONE###'
    exit 3
}

# --------------------------------------------------------------------------- #
#  Списки модулей приходят из интерфейса одной строкой «a,b,c»: powershell.exe
#  с ключом -File не разбивает аргументы по запятым и отдаёт массив из одного
#  элемента. Разворачиваем сами, иначе ни один модуль не совпадёт по имени.
# --------------------------------------------------------------------------- #
function Expand-List {
    param([string[]]$Items)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($i in $Items) {
        if ($null -eq $i) { continue }
        foreach ($p in ([string]$i -split ',')) {
            $t = $p.Trim()
            if ($t) { $out.Add($t) }
        }
    }
    return $out.ToArray()
}
$Modules   = Expand-List $Modules
$WipeItems = Expand-List $WipeItems
$SkipItems = Expand-List $SkipItems
$AppItems  = Expand-List $AppItems
$StartupItems = Expand-List $StartupItems
$ChangeItems  = Expand-List $ChangeItems

# =========================================================================== #
#  Константы
# =========================================================================== #
# Версия. Должна совпадать с AppInfo.Version в интерфейсе -- сборка это
# проверяет, чтобы вшитый движок и окно не рассказывали о себе разное.
$script:EngineVersion  = '1.10.2'
# Метки блока в hosts — только латиницей. Раньше они были по-русски, а hosts
# пишется в ASCII: кириллица превращалась в «?», и своего блока программа
# потом не узнавала — дописывала его заново при каждом применении, а откат
# его не убирал. По шаблону узнаются и новые метки, и прежние, уже побитые.
$script:HostsMarkStart = '# --- Win11Privacy: telemetry block (begin) ---'
$script:HostsMarkEnd   = '# --- Win11Privacy: telemetry block (end) ---'
$script:HostsMarkRegex = '^# --- Win11Privacy: .+ ---\s*$'
$script:FwGroup        = 'Win11Privacy'
# Обычно данные лежат в ProgramData. В переносимом режиме интерфейс
# передаёт -DataRoot, и всё остаётся рядом с exe — на чужом компьютере
# программа не оставляет следов.
$script:DataDir        = $(if ($DataRoot) { $DataRoot } else { Join-Path $env:ProgramData 'Win11Privacy' })
# Задачам планировщика путь к данным надо передать явно: они запускаются
# сами по себе и о переносимом режиме иначе не узнают.
$script:DataArg        = $(if ($DataRoot) { ' -DataRoot "' + $DataRoot + '"' } else { '' })
# Корень в ProgramData. Здесь копия движка, которую задачи планировщика
# запускают с правами администратора, — и в переносимом режиме тоже: рядом с
# exe писать может любая программа пользователя, и подменённый скрипт молча
# выполнился бы с повышенными правами при следующем входе в систему.
$script:SafeRoot       = Join-Path $env:ProgramData 'Win11Privacy'
$script:TaskEngine     = Join-Path $script:SafeRoot 'engine.ps1'
$script:RootState      = $null        # защищён ли корень: $null — ещё не проверяли
# Владельцы, которым можно верить: система, администраторы, TrustedInstaller
$script:TrustedSids    = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
$script:JournalFailed  = $false       # журнал отката не записался — дальше ничего не меняем
$script:JournalLockTries = 6          # по 10 секунд: другой запуск может писать журнал долго
$script:JournalLockWaitMs = 10000
$script:GuardTask      = 'Win11Privacy Guard'
$script:SensorTask     = 'Win11Privacy Sensor'
$script:AuditGuid      = '{0CCE9226-69AE-11D9-BED3-505054503030}'   # Filtering Platform Connection
$script:DiagDir        = Join-Path $env:ProgramData 'Microsoft\Diagnosis'
# Все виды определений, которые пишут в реестр. Список один, потому что
# забыть про новый вид в резервной копии или уборке — тихая потеря данных.
$script:RegTypes = @('reg', 'regif', 'regpol', 'regsvc')
# Номер сборки Windows: по нему настройки, которых на этой версии нет вовсе
# (Copilot, Recall, виджеты — их не было до Windows 11), не считаются
# «не применёнными». Иначе на Windows 10 индекс был бы низким без вины
# пользователя.
$script:OsBuild = 0
try { $script:OsBuild = [int](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'CurrentBuildNumber' -ErrorAction Stop).CurrentBuildNumber } catch { }
$script:Changes = 0
$script:Failures = 0
$script:Already = 0
$script:Blocked = 0
# Настройки, которые Windows не отдала при применении. Запоминаются в
# blocked.json, чтобы проверка не считала их «не применёнными» вечно:
# индекс на Home иначе никогда не дошёл бы до 100 %.
$script:BlockedIds = @{}
$script:UnblockedIds = @{}
# Журнал изменений реестра: что было до нашего вмешательства.
# Без него откат требовал ручного импорта .reg-файлов.
$script:Journal = New-Object System.Collections.Generic.List[object]
$script:TelemetryDnsRegex = 'telemetry|vortex|events\.data\.microsoft|pipe\.aria|watson|settings-win\.data|ceipdata|telecommand|sqm\.|nexusrules|nexus\.officeapps|data\.microsoft\.com|activity\.windows\.com|licensing\.mp\.microsoft|browser\.events|dds\.microsoft\.com|cdpcs\.access\.microsoft|\.do\.dsp\.mp\.microsoft'

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

function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord', [string]$Comment = '',
          [switch]$Policy, [string]$DefId = '')
    $label = if ($Comment) { $Comment } else { "$Path -> $Name" }
    if ($DryRun) { Write-Log "   [тест] $label"; return }

    # Если параметр уже такой, как нужно — не трогаем его: часть значений
    # панели задач Windows защищает от перезаписи даже тем же самым числом.
    $cur = Get-RegValue $Path $Name
    if ($null -ne $cur -and "$cur" -eq "$Value") { Write-Log "   [в] $label -- уже настроено"; $script:Already++; return }

    # ВАЖНО: в журнал отката пишем только после удачной записи. Раньше запись
    # добавлялась заранее, и неудавшиеся попытки оседали в журнале как
    # «изменения», которых на самом деле не было.
    Ensure-Backup          # копию делаем перед первым изменением, а не «всегда»
    $existed = [bool]($null -ne $cur)
    $oldValue = $(if ($existed) { $cur } else { '' })
    $done = $false
    $why = ''
    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        $done = $true
    } catch {
        $why = ("{0}: {1}" -f $_.Exception.GetType().Name, $_.Exception.Message)
        $after = Get-RegValue $Path $Name
        if ($null -ne $after -and "$after" -eq "$Value") { Write-Log "   [в] $label -- уже настроено"; $script:Already++; return }
        $retry = Set-RegDirect -Path $Path -Name $Name -Value $Value -Type $Type
        if ($retry.ok) { $done = $true } else { $why += " / вторая попытка: $($retry.error)" }
    }

    if ($done) {
        if ($Policy -and $DefId) { $script:UnblockedIds[$DefId] = $true }   # отдала — снимаем пометку
        try {
            $script:Journal.Add(@{ kind = 'reg'; path = $Path; name = $Name; type = $Type
                                   existed = $existed; old = $oldValue
                                   newValue = "$Value"; time = (Get-Date).ToString('s') })
            if ($script:Journal.Count -ge 10) { Save-JournalEntries -Quiet }
        } catch { }
        Write-Log "   [+] $label"; $script:Changes++
        return
    }

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

function Clear-FolderContents {
    param([string]$FolderPath, [string]$Label, [string]$Step = '')
    if (-not (Test-Path -LiteralPath $FolderPath)) {
        if ($Step) { Write-Log ("   {0} {1} -- нечего чистить" -f $Step, $Label) }
        return 0.0
    }
    # Большую папку посчитать и вычистить — это минуты, а строка шага
    # появлялась только в конце, и чистка выглядела зависшей.
    if ($Step) { Write-Log ("   {0} {1}..." -f $Step, $Label) }
    $before = Get-FolderSizeMB $FolderPath
    if ($DryRun) { Write-Log ("   {0} [тест] {1} -- можно освободить ~{2} МБ" -f $Step, $Label, $before); return 0.0 }
    Get-ChildItem -LiteralPath $FolderPath -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $freed = [math]::Max(0, [math]::Round($before - (Get-FolderSizeMB $FolderPath), 1))
    if ($Step) { Write-Log ("   {0} {1} -- освобождено {2} МБ" -f $Step, $Label, $freed) }
    else { Write-Log ("   [+] {0} -- освобождено {1} МБ" -f $Label, $freed) }
    return [double]$freed
}

function Split-TaskPath {
    param([string]$Full)
    $name = Split-Path $Full -Leaf
    $path = (Split-Path $Full -Parent)
    if (-not $path.EndsWith('\')) { $path += '\' }
    return @($path, $name)
}

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

function Protect-DataRoot {
    param([string]$Dir)
    if (-not (Test-Admin)) { return (Test-DirSecure $Dir) }
    try {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        if (Test-Path -LiteralPath $Dir) {
            $it = Get-Item -LiteralPath $Dir -Force
            if (($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($script:TrustedSids -notcontains (Get-OwnerSid $Dir))) {
                # папку завёл не администратор — ничему внутри верить нельзя
                [IO.Directory]::Move($Dir, "$Dir.untrusted-$stamp")
                Write-Log ("   [!] папку данных завёл не администратор -- она отложена как {0}" -f (Split-Path "$Dir.untrusted-$stamp" -Leaf))
            }
        }
        if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
        if (Test-DirSecure $Dir) { return $true }
        # Папка прежних версий: права наследовались от ProgramData. Всё, что в
        # ней создал не администратор, и любые ссылки уносим в карантин рядом.
        $aside = "$Dir.untrusted-$stamp"
        foreach ($c in @(Get-ChildItem -LiteralPath $Dir -Force -ErrorAction SilentlyContinue)) {
            $bad = ($c.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($script:TrustedSids -notcontains (Get-OwnerSid $c.FullName))
            if (-not $bad) { continue }
            if (-not (Test-Path -LiteralPath $aside)) { New-Item -ItemType Directory -Path $aside -Force | Out-Null }
            $to = Join-Path $aside $c.Name
            if ($c.PSIsContainer) { [IO.Directory]::Move($c.FullName, $to) } else { [IO.File]::Move($c.FullName, $to) }
            Write-Log ("   [!] в папке данных лежал чужой файл, он отложен: {0}" -f $c.Name)
        }
        $sec = New-Object System.Security.AccessControl.DirectorySecurity
        $sec.SetAccessRuleProtection($true, $false)
        $inh = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        foreach ($p in @(@('S-1-5-18', 'FullControl'), @('S-1-5-32-544', 'FullControl'), @('S-1-5-32-545', 'ReadAndExecute'))) {
            $sid = New-Object Security.Principal.SecurityIdentifier($p[0])
            $sec.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, $p[1], $inh, 'None', 'Allow')))
        }
        $sec.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
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

# Журнал читается и пишется только из защищённой папки. В переносимом режиме
# данные лежат рядом с exe и защищены ровно так же, как сам exe.
function Test-DataTrusted {
    if ($script:DataDir -ne $script:SafeRoot) { return $true }
    return (Assert-SafeRoot)
}

function Ensure-DataDir {
    if ($script:DataDir -eq $script:SafeRoot) {
        if (-not (Assert-SafeRoot)) { throw 'папка данных программы не защищена от подмены' }
        return
    }
    if (-not (Test-Path -LiteralPath $script:DataDir)) { New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null }
}

# Копия движка для задач планировщика: всегда в защищённом корне, пишется
# рядом и подменяет прежнюю одним движением, а перед этим сверяется с
# оригиналом по SHA-256.
function Install-TaskEngine {
    if (-not (Assert-SafeRoot)) { throw 'папка ProgramData\Win11Privacy не защищена — копию движка для задач туда класть нельзя' }
    $dst = $script:TaskEngine
    if ($PSCommandPath -eq $dst) { return $dst }
    $tmp = $dst + '.new'
    Copy-Item -LiteralPath $PSCommandPath -Destination $tmp -Force -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw 'копия движка для задач не совпала с оригиналом'
    }
    Move-Item -LiteralPath $tmp -Destination $dst -Force -ErrorAction Stop
    # прежние версии в переносимом режиме клали копию рядом с данными
    if ($script:DataDir -ne $script:SafeRoot) { Remove-Item -LiteralPath (Join-Path $script:DataDir 'engine.ps1') -Force -ErrorAction SilentlyContinue }
    return $dst
}

# Файл пишется рядом и подменяет прежний одним движением: обрыв на середине
# записи (выключили питание, прервали движок) не оставит от журнала отката
# половину — а журнал единственный путь назад.
function Save-Json {
    param([string]$Name, $Object)
    Ensure-DataDir
    $path = Join-Path $script:DataDir $Name
    $tmp = $path + '.tmp'
    ($Object | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $path -Force
}
# --- Резервная копия и точка восстановления --------------------------------- #
#  Делаются не «на всякий случай» при каждом запуске, а ровно перед первым
#  настоящим изменением. Если всё уже настроено, на рабочем столе не появится
#  очередная пустая папка, а система не потратит минуту на точку отката.
$script:BackupDir = ''
$script:BackupTried = $false
# Копию и точку восстановления делает только ручное применение. Страж чинит
# сбитые настройки сам по расписанию — ему незачем сорить папками на рабочем
# столе и тратить минуту на точку отката при каждой мелкой правке.
$script:BackupEnabled = $false

function Ensure-Backup {
    if (-not $script:BackupEnabled -or $script:BackupTried -or $DryRun) { return }
    $script:BackupTried = $true

    if (-not $NoBackup) {
        Write-Section 'Резервная копия реестра'
        $root = if ($BackupRoot) { $BackupRoot } else { [Environment]::GetFolderPath('Desktop') }
        $dir = Join-Path $root ('Win11Privacy-Backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $keys = @($script:Defs | Where-Object { $script:RegTypes -contains $_.T -and $Modules -contains $_.M } | ForEach-Object { $_.P } | Select-Object -Unique)
        try {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $saved = 0
            $missed = @()
            foreach ($k in $keys) {
                if (-not (Test-Path -LiteralPath $k)) { continue }
                $native = $k -replace '^HKLM:\\','HKLM\' -replace '^HKCU:\\','HKCU\'
                $file = Join-Path $dir ((($k -replace '[:\\ ]','_')) + '.reg')
                # ВАЖНО: reg.exe зовём через cmd, а не с «2>&1». В PowerShell 5.1
                # поток ошибок родной программы превращается в терминирующую
                # ошибку, и одна нечитаемая ветка обрывала всю копию целиком.
                try { $null = & cmd.exe /c "reg export `"$native`" `"$file`" /y >nul 2>&1" } catch { }
                # считаем только то, что действительно легло на диск: раньше
                # счётчик прибавлял на каждую попытку, и в журнале стояло
                # «сохранено веток: 35», даже если часть выгрузить не удалось
                if (Test-Path -LiteralPath $file) { $saved++ } else { $missed += $k }
            }
            if ($saved -gt 0) {
                $script:BackupDir = $dir
                Write-Log ("   [+] сохранено веток: {0} -> {1}" -f $saved, $dir)
            } else {
                Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log '   [-] сохранять нечего: ни одна ветка не выгрузилась'
            }
            if ($missed.Count -gt 0) {
                Write-Log ("   [-] не выгрузились ветки: {0} (Windows не отдаёт их даже на чтение)" -f $missed.Count)
                foreach ($k in $missed) { Write-Log ("       {0}" -f $k) }
            }
        } catch { Write-Log "   [!] не удалось создать резервную копию: $($_.Exception.Message)" }
    }

    if (-not $NoRestorePoint) {
        Write-Section 'Точка восстановления системы'
        try {
            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
            New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
            Checkpoint-Computer -Description 'Win11Privacy: до изменений' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
            Write-Log '   [+] точка восстановления создана'
        } catch { Write-Log "   [!] точку восстановления создать не удалось: $($_.Exception.Message)" }
    }
}

# Журнал отката сбрасывается на диск по ходу работы: раньше он писался
# единственный раз в самом конце, и обрыв прогона (закрыли окно, выключили
# питание) оставлял изменения в системе, а вернуть их было нечем.
# Журнал читается и переписывается целиком, поэтому два одновременно
# работающих экземпляра затирали правки друг друга — а журнал единственный
# путь назад. Общесистемный замок делает запись неделимой.
# Не дождались замка — не пишем вовсе: раньше после 10 секунд ожидания тело
# выполнялось без замка, и два запуска снова затирали друг другу журнал.
function Use-JournalLock {
    param([scriptblock]$Body)
    $mx = New-Object System.Threading.Mutex($false, 'Global\Win11Privacy-Journal')
    $held = $false
    try {
        for ($i = 0; $i -lt $script:JournalLockTries -and -not $held; $i++) {
            try { $held = $mx.WaitOne($script:JournalLockWaitMs) }
            catch {
                # прежний владелец завершился, не отпустив замок: замок наш
                if ("$($_.Exception)" -match 'AbandonedMutex') { $held = $true } else { throw }
            }
        }
        if (-not $held) { throw 'журнал отката занят другим запуском программы' }
        & $Body
    } finally {
        if ($held) { try { $mx.ReleaseMutex() } catch { } }
        try { $mx.Dispose() } catch { }
    }
}

# Журнал на диске. Повреждённый файл не затирается молча новыми записями —
# раньше Load-Json возвращал пустоту, и вся история «как было» терялась при
# следующей же записи. Теперь он откладывается рядом под своим именем.
function Read-JournalFile {
    $p = Join-Path $script:DataDir 'changes.json'
    $res = @{ items = @(); legacy = $false; exists = $false }
    if (-not (Test-Path -LiteralPath $p)) { return $res }
    $res.exists = $true
    try { $j = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch {
        $bad = Join-Path $script:DataDir ('changes.broken-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
        Move-Item -LiteralPath $p -Destination $bad -Force -ErrorAction Stop
        Write-Log ("   [!] журнал отката был повреждён и отложен как {0}" -f (Split-Path $bad -Leaf))
        $res.exists = $false
        $res.legacy = $true
        return $res
    }
    if ($j -and $j.PSObject.Properties['items'] -and $j.items) { $res.items = @($j.items) }
    # Журнал прежних версий: в нём нет служб, задач и переменных среды. Пометка
    # остаётся с ним навсегда — полный откат для них ведёт себя по-старому.
    $res.legacy = [bool](($j.PSObject.Properties['legacy'] -and $j.legacy) -or
                         (-not $j.PSObject.Properties['schema'] -and $res.items.Count -gt 0))
    return $res
}

function Write-JournalFile {
    param($Items, [bool]$Legacy)
    Save-Json 'changes.json' @{ schema = 2; legacy = $Legacy; items = @($Items); updated = (Get-Date).ToString('s') }
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
    if ($DryRun -or $script:Journal.Count -eq 0) { return }
    $mine = $script:Journal.Count
    try {
        if (-not (Test-DataTrusted)) { throw 'папка данных программы не защищена от подмены' }
        Use-JournalLock {
            $prev = Read-JournalFile
            $all = New-Object System.Collections.Generic.List[object]
            foreach ($e in @($prev.items)) { $all.Add($e) }
            foreach ($e in $script:Journal) { $all.Add($e) }
            Write-JournalFile (Compress-Journal $all.ToArray()) $prev.legacy
            $script:Journal.Clear()
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
function Load-Json { param([string]$Name) $p = Join-Path $script:DataDir $Name; if (Test-Path -LiteralPath $p) { try { return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null } } return $null }

# --- Службы, задачи и переменные среды в журнале отката --------------------- #
#  Раньше журнал помнил только реестр, а полный откат включал службы и задачи
#  «по умолчанию»: DiagTrack — автоматически, все задачи из списка — включить.
#  Задача, которую человек выключил сам задолго до программы, после отката
#  включалась. Теперь у каждой записано, какой она была до нас.
function Add-JournalEntry {
    param($Entry)
    if ($DryRun) { return }
    $Entry['time'] = (Get-Date).ToString('s')
    $script:Journal.Add($Entry)
    if ($script:Journal.Count -ge 10) { Save-JournalEntries -Quiet }
}

function Get-SvcJournalState {
    param([string]$Name, $Svc)
    $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    $start = Get-RegValue $k 'Start'
    $delayed = Get-RegValue $k 'DelayedAutostart'
    return @{ kind = 'svc'; name = $Name
              old = $(if ($null -ne $start) { "$start" } else { '' })
              delayed = $(if ($null -ne $delayed) { "$delayed" } else { '' })
              running = [bool]($Svc -and $Svc.Status -eq 'Running')
              newValue = '4' }
}

# Задачу программа гасит, только если она была включена, — это и запоминаем
function Add-TaskJournal {
    param([string]$Path)
    Add-JournalEntry @{ kind = 'task'; path = $Path; old = 'Enabled'; newValue = 'Disabled' }
}

# Тип запуска службы словами — для страницы «Журнал изменений»
function Get-StartName {
    param([string]$Start, [string]$Delayed = '')
    switch ("$Start") {
        '0' { return 'при загрузке системы' }
        '1' { return 'системная' }
        '2' { if ("$Delayed" -eq '1') { return 'автоматически (отложенный запуск)' } return 'автоматически' }
        '3' { return 'вручную' }
        '4' { return 'отключена' }
    }
    return 'не было'
}

# Возвращает одну запись журнала (реестр, служба, задача, переменная среды).
# Записи автозагрузки и чужих профилей возвращаются своими функциями.
function Restore-JournalEntry {
    param($e)
    try {
        switch ("$($e.kind)") {
            'svc' {
                $name = "$($e.name)"
                if (-not (Get-Service -Name $name -ErrorAction SilentlyContinue)) { return @{ ok = $true; note = 'службы больше нет' } }
                $start = "$($e.old)"
                $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
                $type = switch ($start) { '2' { 'Automatic' } '3' { 'Manual' } '4' { 'Disabled' } default { '' } }
                if ($type) { Set-Service -Name $name -StartupType $type -ErrorAction Stop }
                elseif ($start -ne '') { Set-ItemProperty -LiteralPath $k -Name 'Start' -Value ([int]$start) -Type DWord -ErrorAction Stop }
                if ("$($e.delayed)" -ne '') { Set-ItemProperty -LiteralPath $k -Name 'DelayedAutostart' -Value ([int]"$($e.delayed)") -Type DWord -ErrorAction SilentlyContinue }
                # работала до нас — запускаем снова, чтобы не ждать перезагрузки
                if ($e.running -and $start -ne '4') { Start-Service -Name $name -ErrorAction SilentlyContinue }
                return @{ ok = $true }
            }
            'task' {
                if ("$($e.old)" -ne 'Enabled') { return @{ ok = $true } }
                $r = Set-TaskEnabled "$($e.path)" $true
                if ($r -in @('ok', 'system', 'missing')) { return @{ ok = $true } }
                return @{ ok = $false; error = 'Windows не дала включить задачу' }
            }
            'env' {
                $v = $(if ($e.existed) { "$($e.old)" } else { $null })
                [Environment]::SetEnvironmentVariable("$($e.name)", $v, 'User')
                return @{ ok = $true }
            }
            default {
                if ($e.existed) {
                    if (-not (Test-Path -LiteralPath $e.path)) { New-Item -Path $e.path -Force -ErrorAction Stop | Out-Null }
                    New-ItemProperty -LiteralPath $e.path -Name $e.name -Value $e.old -PropertyType $e.type -Force -ErrorAction Stop | Out-Null
                } else {
                    Remove-ItemProperty -LiteralPath $e.path -Name $e.name -Force -ErrorAction SilentlyContinue
                }
                return @{ ok = $true }
            }
        }
    } catch { return @{ ok = $false; error = $_.Exception.Message } }
}

# =========================================================================== #
#  Определение системы
# =========================================================================== #
function Get-Edition {
    $ed = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'EditionID'
    if (-not $ed) { $ed = '' }
    $kind = 'other'
    if ($ed -match '^Core') { $kind = 'home' }
    elseif ($ed -match '^Professional') { $kind = 'pro' }
    elseif ($ed -match 'Enterprise|Education|Server') { $kind = 'enterprise' }
    return @{ id = $ed; kind = $kind }
}

function Test-Exe { param([string[]]$Paths) foreach ($p in $Paths) { if ($p -and (Test-Path -LiteralPath $p)) { return $true } } return $false }

function Detect-Apps {
    $pf   = $env:ProgramFiles
    $pf86 = ${env:ProgramFiles(x86)}
    $la   = $env:LOCALAPPDATA
    $apps = @()

    # NVIDIA
    $nvSvc  = Get-Service -Name 'NvTelemetryContainer' -ErrorAction SilentlyContinue
    $nvTask = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'NvTm*' -or $_.TaskName -like 'NvProfileUpdater*' -or $_.TaskName -like 'NvDriverUpdateCheck*' })
    $nvReg  = Test-Path 'HKLM:\SOFTWARE\NVIDIA Corporation'
    $apps += @{ id='app_nvidia'; name='NVIDIA (драйвер и GeForce)'; found=[bool]($nvSvc -or $nvTask.Count -gt 0 -or $nvReg);
                detail = "служба: $([bool]$nvSvc), задач: $($nvTask.Count)" }

    # VS Code
    $vsSettings = Join-Path $env:APPDATA 'Code\User\settings.json'
    $vsExe = Test-Exe @((Join-Path $la 'Programs\Microsoft VS Code\Code.exe'), (Join-Path $pf 'Microsoft VS Code\Code.exe'))
    $apps += @{ id='app_vscode'; name='Visual Studio Code'; found=[bool]($vsExe -or (Test-Path -LiteralPath $vsSettings)); detail=$vsSettings }

    # Chrome
    $chrome = Test-Exe @((Join-Path $pf 'Google\Chrome\Application\chrome.exe'), (Join-Path $pf86 'Google\Chrome\Application\chrome.exe'), (Join-Path $la 'Google\Chrome\Application\chrome.exe'))
    $apps += @{ id='app_chrome'; name='Google Chrome'; found=[bool]$chrome; detail='' }

    # Firefox
    $ffDir = @((Join-Path $pf 'Mozilla Firefox'), (Join-Path $pf86 'Mozilla Firefox')) | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'firefox.exe') } | Select-Object -First 1
    $apps += @{ id='app_firefox'; name='Mozilla Firefox'; found=[bool]$ffDir; detail=("$ffDir") }

    # Office
    $office = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun') -or (Test-Exe @((Join-Path $pf 'Microsoft Office\root\Office16\WINWORD.EXE'), (Join-Path $pf86 'Microsoft Office\root\Office16\WINWORD.EXE')))
    $apps += @{ id='app_office'; name='Microsoft Office'; found=[bool]$office; detail='' }

    # Средства разработки: PowerShell 7 / .NET SDK
    $pwsh = Test-Exe @((Join-Path $pf 'PowerShell\7\pwsh.exe'))
    $dotnet = Test-Exe @((Join-Path $pf 'dotnet\dotnet.exe'))
    $apps += @{ id='app_devtools'; name='PowerShell 7 / .NET SDK'; found=[bool]($pwsh -or $dotnet); detail="pwsh: $pwsh, dotnet: $dotnet" }

    # Visual Studio
    $vs = (Test-Path 'HKLM:\SOFTWARE\Microsoft\VisualStudio\Setup') -or (Test-Path (Join-Path $pf 'Microsoft Visual Studio')) -or (Test-Path (Join-Path $pf86 'Microsoft Visual Studio'))
    $apps += @{ id='app_vs'; name='Visual Studio'; found=[bool]$vs; detail='' }

    return $apps
}

# --- OEM: компоненты сбора данных производителя ---------------------------- #
$script:OemVendorRegex  = 'Huawei|Honor|Hihonor|\bHP\b|Hewlett|Lenovo|\bDell\b|ASUS|Acer|\bMSI\b|Samsung|Xiaomi|Realme'
$script:OemKeywordRegex = 'Telemetry|Analytic|Report|Usage|Experience|Feedback|Metric|Diagnos|Collect|Survey|Statistic|Insight|Tracking|SupportAssist|TouchPoint|Improvement|UEIP|Beacon'
$script:OemExcludeRegex = 'Update|Driver|Audio|Bluetooth|Camera|Display|Power|Battery|Keyboard|Touchpad|Fingerprint|Hotkey|\bFn\b|Thermal|Fan|Network|WLAN|Wifi|Print|Scan|Backup|Recovery|Security|Antivirus'

function Detect-Oem {
    $found = @()
    $manu = ''
    try { $manu = (Get-CimInstance Win32_ComputerSystem).Manufacturer } catch { }
    $model = ''
    try { $model = (Get-CimInstance Win32_ComputerSystem).Model } catch { }

    $svcs = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue
    foreach ($s in $svcs) {
        $blob = "$($s.Name) $($s.DisplayName) $($s.PathName)"
        if ($blob -match $script:OemVendorRegex -and $blob -match $script:OemKeywordRegex -and ($s.Name + ' ' + $s.DisplayName) -notmatch $script:OemExcludeRegex) {
            $found += @{ type='svc'; name=$s.Name; display=$s.DisplayName; state=$s.StartMode }
        }
    }
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue
    foreach ($t in $tasks) {
        $blob = "$($t.TaskPath) $($t.TaskName) $($t.Description)"
        if ($blob -match $script:OemVendorRegex -and $blob -match $script:OemKeywordRegex -and $t.TaskName -notmatch $script:OemExcludeRegex) {
            $found += @{ type='task'; name=($t.TaskPath + $t.TaskName); display=$t.TaskName; state=[string]$t.State }
        }
    }
    return @{ manufacturer=$manu; model=$model; items=$found }
}

# =========================================================================== #
#  Декларативные определения настроек
# =========================================================================== #
$script:Defs = New-Object System.Collections.Generic.List[object]
$script:DefSeq = @{}
# У каждой настройки есть свой номер вида telemetry#3 — по нему интерфейс
# может отключить отдельный пункт внутри модуля.
function Def {
    # ОСТОРОЖНО: имена переменных в PowerShell регистронезависимы. Счётчик
    # раньше звался $n и затирал параметр $N — в реестр вместо AllowTelemetry
    # писалось значение с именем «0». Любая локальная переменная здесь обязана
    # отличаться от имён параметров не только регистром.
    param($M, $T, $P, $N, $V, $Type = 'DWord', $C = '', $Min = 0)
    $seq = 0
    if ($script:DefSeq.ContainsKey($M)) { $seq = [int]$script:DefSeq[$M] }
    $script:DefSeq[$M] = $seq + 1
    # Повтор в одном разделе (две задачи Proxy и DmClientOnScenarioDownload
    # в списке служб) давал две одинаковые строки и считался дважды. Номер
    # всё равно занимаем: по номерам профили помнят снятые пункты, и сдвиг
    # переставил бы их на соседей.
    foreach ($x in $script:Defs) {
        if ($x.M -eq $M -and $x.T -eq $T -and "$($x.P)" -eq "$P" -and "$($x.N)" -eq "$N") { return }
    }
    $script:Defs.Add(@{ M=$M; T=$T; P=$P; N=$N; V=$V; Type=$Type; C=$C; Min=[int]$Min
                        Id=("{0}#{1}" -f $M, $seq) })
}

$dc  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
Def 'telemetry' 'reg' $dc 'AllowTelemetry' 0 'DWord' 'уровень телеметрии — минимальный'
Def 'telemetry' 'reg' $dc 'MaxTelemetryAllowed' 1 'DWord' 'потолок телеметрии'
Def 'telemetry' 'reg' $dc 'AllowDeviceNameInTelemetry' 0 'DWord' 'не отправлять имя устройства'
Def 'telemetry' 'reg' $dc 'DoNotShowFeedbackNotifications' 1 'DWord' 'не запрашивать отзывы'
Def 'telemetry' 'reg' $dc 'LimitDiagnosticLogCollection' 1 'DWord' 'не собирать диагностические логи'
Def 'telemetry' 'reg' $dc 'LimitDumpCollection' 1 'DWord' 'не собирать дампы памяти'
Def 'telemetry' 'reg' $dc 'DisableOneSettingsDownloads' 1 'DWord' 'отключить загрузку конфигураций OneSettings'
Def 'telemetry' 'reg' $dc 'AllowCommercialDataPipeline' 0 'DWord' 'отключить коммерческий канал данных'
Def 'telemetry' 'reg' $dc 'AllowUpdateComplianceProcessing' 0 'DWord' 'отключить Update Compliance'
Def 'telemetry' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 'DWord' 'без рекомендаций на основе диагностики'
Def 'telemetry' 'reg' 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0 'DWord' 'опросы Центра отзывов — выкл'
Def 'telemetry' 'reg' 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Settings\AllowExperimentation' 'value' 0 'DWord' 'эксперименты Microsoft — выкл'
# Телеметрия совместимости живёт отдельно от DiagTrack: опись программ,
# оценщик совместимости и запись действий пользователя шлют свои данные.
Def 'telemetry' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0 'DWord' 'программа улучшения качества (CEIP) — выкл'
Def 'telemetry' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'AITEnable' 0 'DWord' 'телеметрия совместимости приложений — выкл'
Def 'telemetry' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1 'DWord' 'опись установленных программ — выкл'
Def 'telemetry' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableUAR' 1 'DWord' 'запись действий пользователя (Steps Recorder) — выкл'
Def 'telemetry' 'reg' 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1 'DWord' 'персонализация по диагностике — запрет политикой'

Def 'errors' 'reg' 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1 'DWord' 'отправка отчётов об ошибках — выкл'
Def 'errors' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1 'DWord' 'то же, политикой'
Def 'errors' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'DontSendAdditionalData' 1 'DWord' 'не отправлять дополнительные данные'

$cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$cc  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
Def 'ads' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 'DWord' 'рекламный ID — выкл'
Def 'ads' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1 'DWord' 'рекламный ID заблокирован политикой'
Def 'ads' 'reg' $cdm 'SystemPaneSuggestionsEnabled' 0 'DWord' 'реклама приложений в меню Пуск'
Def 'ads' 'reg' $cdm 'SilentInstalledAppsEnabled' 0 'DWord' 'тихая установка рекламных приложений'
Def 'ads' 'reg' $cdm 'PreInstalledAppsEnabled' 0 'DWord' 'предустановка партнёрских приложений'
Def 'ads' 'reg' $cdm 'OemPreInstalledAppsEnabled' 0 'DWord' 'предустановка приложений OEM'
Def 'ads' 'reg' $cdm 'SoftLandingEnabled' 0 'DWord' 'всплывающие подсказки-реклама'
Def 'ads' 'reg' $cdm 'RotatingLockScreenOverlayEnabled' 0 'DWord' 'реклама на экране блокировки'
Def 'ads' 'reg' $cdm 'SubscribedContent-338388Enabled' 0 'DWord' 'предложения в меню Пуск'
Def 'ads' 'reg' $cdm 'SubscribedContent-338389Enabled' 0 'DWord' 'советы и подсказки Windows'
Def 'ads' 'reg' $cdm 'SubscribedContent-338393Enabled' 0 'DWord' 'предложения в Параметрах'
Def 'ads' 'reg' $cdm 'SubscribedContent-353694Enabled' 0 'DWord' 'предложения в Параметрах (2)'
Def 'ads' 'reg' $cdm 'SubscribedContent-353696Enabled' 0 'DWord' 'предложения в Параметрах (3)'
Def 'ads' 'reg' $cdm 'SubscribedContent-310093Enabled' 0 'DWord' 'приветственные экраны после обновлений'
Def 'ads' 'reg' $cdm 'ContentDeliveryAllowed' 0 'DWord' 'доставка рекламного контента'
Def 'ads' 'reg' $cc 'DisableWindowsConsumerFeatures' 1 'DWord' 'авто-установка игр и промо-приложений'
Def 'ads' 'reg' $cc 'DisableCloudOptimizedContent' 1 'DWord' 'облачный «оптимизированный» контент'
Def 'ads' 'reg' $cc 'DisableConsumerAccountStateContent' 1 'DWord' 'реклама подписок Microsoft'
Def 'ads' 'reg' $cc 'DisableSoftLanding' 1 'DWord' 'подсказки Windows'
Def 'ads' 'reg' $cc 'DisableWindowsSpotlightFeatures' 1 'DWord' 'Windows Spotlight'
Def 'ads' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0 'DWord' 'рекомендации в меню Пуск'
Def 'ads' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0 'DWord' 'реклама OneDrive в Проводнике'
Def 'ads' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0 'DWord' '«Получите больше от Windows» после обновлений — выкл'
# Найдены в каталоге политик Windows (PolicyManager): реклама и «интересное»,
# которые программа раньше не трогала. Пользовательские — в HKCU.
$ccu = 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent'
Def 'ads' 'reg' $ccu 'DisableThirdPartySuggestions' 1 'DWord' 'предложения сторонних приложений в «интересном» — выкл'
Def 'ads' 'reg' $ccu 'DisableWindowsSpotlightOnActionCenter' 1 'DWord' '«интересное» в центре уведомлений — выкл'
Def 'ads' 'reg' $ccu 'DisableWindowsSpotlightOnSettings' 1 'DWord' '«интересное» в Параметрах — выкл'
Def 'ads' 'reg' $ccu 'DisableWindowsSpotlightWindowsWelcomeExperience' 1 'DWord' 'приветственная реклама после обновлений — выкл'
Def 'ads' 'reg' $ccu 'DisableSpotlightCollectionOnDesktop' 1 'DWord' 'обои «Windows: интересное» на рабочем столе — выкл'
# Экран «Закрепите Copilot» при входе (ShellAppRuntime.exe, рекламные блоки 88000325/88000326)
Def 'ads' 'reg' $cc 'DisableCopilotPinScreen' 1 'DWord' 'экран «Закрепите Copilot» при входе — выкл'
# Реклама приложений в окне «Поделиться» (SharePickerUI.dll)
Def 'ads' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\ShareSheet' 'DisableShareAppPromotions' 1 'DWord' 'реклама приложений в окне «Поделиться» — выкл'
# Блок «Справка из интернета» в «Параметрах»: при открытии страницы приложение
# отправляет POST на www.bing.com/RelatedSearch с тем, какую страницу вы
# смотрите. Найдено записью Windows 11 с программой на максимуме.
Def 'ads' 'regpol' 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'AllowOnlineTips' 0 'DWord' 'советы из интернета в «Параметрах» (запросы к Bing) — выкл'

$sys = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
Def 'activity' 'reg' $sys 'EnableActivityFeed' 0 'DWord' 'лента активности — выкл'
Def 'activity' 'reg' $sys 'PublishUserActivities' 0 'DWord' 'не публиковать активность'
Def 'activity' 'reg' $sys 'UploadUserActivities' 0 'DWord' 'не выгружать активность в облако'
Def 'activity' 'reg' $sys 'AllowClipboardHistory' 0 'DWord' 'история буфера обмена — выкл'
Def 'activity' 'reg' $sys 'AllowCrossDeviceClipboard' 0 'DWord' 'синхронизация буфера между устройствами — выкл'
Def 'activity' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0 'DWord' 'Пуск: не отслеживать запуск программ'
Def 'activity' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SmartActionPlatform\SmartClipboard' 'Disabled' 1 'DWord' 'буфер обмена: «предлагаемые действия» — выкл'

Def 'input' 'reg' 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1 'DWord' 'не собирать набранный текст'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1 'DWord' 'не собирать рукописный ввод'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0 'DWord' 'не собирать контакты'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0 'DWord' 'персонализация ввода — отказ'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0 'DWord' 'облачное распознавание речи — выкл'
Def 'input' 'reg' 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1 'DWord' 'не отдавать сайтам список языков'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\appDiagnostics' 'Value' 'Deny' 'String' 'приложениям запрещена диагностика других приложений'
Def 'input' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC' 'PreventHandwritingDataSharing' 1 'DWord' 'не отправлять образцы рукописного ввода'
Def 'input' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports' 'PreventHandwritingErrorReports' 1 'DWord' 'не отправлять отчёты об ошибках распознавания рукописи'

$su = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
$sm = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
Def 'search' 'reg' $su 'BingSearchEnabled' 0 'DWord' 'поиск Bing в меню Пуск — выкл'
Def 'search' 'reg' $su 'CortanaConsent' 0 'DWord' 'согласие Cortana снято'
Def 'search' 'reg' $su 'DeviceHistoryEnabled' 0 'DWord' 'история поиска на устройстве — выкл'
Def 'search' 'reg' $su 'HistoryViewEnabled' 0 'DWord' 'показ истории поиска — выкл'
Def 'search' 'reg' $sm 'AllowCortana' 0 'DWord' 'Cortana — выкл'
Def 'search' 'reg' $sm 'DisableWebSearch' 1 'DWord' 'веб-поиск из Пуска — выкл'
Def 'search' 'reg' $sm 'ConnectedSearchUseWeb' 0 'DWord' 'не обращаться к вебу при поиске'
Def 'search' 'reg' $sm 'AllowSearchToUseLocation' 0 'DWord' 'поиск не использует геолокацию'
Def 'search' 'reg' $sm 'AllowCloudSearch' 0 'DWord' 'облачный поиск по OneDrive/Outlook — выкл'
Def 'search' 'reg' $sm 'EnableDynamicContentInWSB' 0 'DWord' 'рекламные подсказки в поле поиска — выкл'
Def 'search' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDeviceSearchHistoryEnabled' 0 'DWord' 'история поиска на устройстве (Параметры) — выкл'

$ai = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
Def 'copilot' 'reg' 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 'DWord' 'Windows Copilot — выкл' 22000
Def 'copilot' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 'DWord' 'Windows Copilot — выкл для всех' 22000
Def 'copilot' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0 'DWord' 'кнопка Copilot на панели задач — убрать' 22000
Def 'copilot' 'reg' $ai 'DisableAIDataAnalysis' 1 'DWord' 'Recall (снимки экрана) — выкл' 26100
Def 'copilot' 'reg' $ai 'AllowRecallEnablement' 0 'DWord' 'запрет включения Recall' 26100
Def 'copilot' 'reg' 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1 'DWord' 'Recall — выкл для пользователя' 26100
Def 'copilot' 'reg' $ai 'AllowRecallExport' 0 'DWord' 'Recall: выгрузка снимков — запрещена' 26100

# Весь ИИ Windows
Def 'ai' 'reg' $ai 'DisableClickToDo' 1 'DWord' 'Click to Do — выкл' 26100
Def 'ai' 'reg' $ai 'TurnOffSavingSnapshots' 1 'DWord' 'сохранение снимков экрана — выкл' 26100
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Notepad' 'DisableAIFeatures' 1 'DWord' 'Copilot в Блокноте — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Paint' 'DisableCocreator' 1 'DWord' 'Paint Cocreator — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Paint' 'DisableGenerativeFill' 1 'DWord' 'Paint: генеративная заливка — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Paint' 'DisableImageCreator' 1 'DWord' 'Paint Image Creator — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'CopilotPageContext' 0 'DWord' 'Edge: Copilot не читает страницы'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'CopilotCDPPageContext' 0 'DWord' 'Edge: Copilot без контекста вкладок'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'ComposeInlineEnabled' 0 'DWord' 'Edge: ИИ-подсказки при наборе — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'EdgeHistoryAISearchEnabled' 0 'DWord' 'Edge: ИИ-поиск по истории — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'EdgeEntityExtractionEnabled' 0 'DWord' 'Edge: извлечение сущностей — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'Microsoft365CopilotChatIconEnabled' 0 'DWord' 'Edge: значок Copilot — убрать'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableGraphRecentItems' 1 'DWord' 'Проводник: облачные «недавние» — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'HideRecommendedSection' 1 'DWord' 'Пуск: раздел «Рекомендуем» — скрыть' 22000
Def 'ai' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowRecommendations' 0 'DWord' 'Проводник: рекомендации в «Главной» — выкл' 22000
# Политика выключает сам Click to Do, но задача по-прежнему скачивает его
# модели ИИ. Администратору Windows её не отдаёт — отключается от SYSTEM.
Def 'ai' 'task' '\Microsoft\Windows\WindowsAI\ClickToDo\ModelCachingUpdate' '' 'Disabled' '' 'Click to Do: скачивание моделей ИИ — выкл' 26100
# ИИ-агенты работают с Windows через MCP-«коннекторы» (служба McpManagementService,
# доступ выдаёт CapabilityAccessManager). 2 — запретить (шаблон CAM_AI.admx).
Def 'ai' 'reg' $ai 'ConfigureAgentConnectors' 2 'DWord' 'ИИ-агенты: доступ к файлам и настройкам через MCP — запрещён' 26100
Def 'ai' 'reg' $ai 'DisableSettingsAgent' 1 'DWord' 'ИИ-агент в Параметрах — выкл' 26100

$e = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
Def 'edge' 'reg' $e 'MetricsReportingEnabled' 0 'DWord' 'статистика использования — выкл'
Def 'edge' 'reg' $e 'DiagnosticData' 0 'DWord' 'диагностические данные — выкл'
Def 'edge' 'reg' $e 'SendSiteInfoToImproveServices' 0 'DWord' 'не отправлять адреса сайтов'
Def 'edge' 'reg' $e 'PersonalizationReportingEnabled' 0 'DWord' 'персонализация рекламы — выкл'
Def 'edge' 'reg' $e 'UserFeedbackAllowed' 0 'DWord' 'отзывы — выкл'
Def 'edge' 'reg' $e 'EdgeShoppingAssistantEnabled' 0 'DWord' 'шопинг-ассистент — выкл'
Def 'edge' 'reg' $e 'AlternateErrorPagesEnabled' 0 'DWord' 'не отправлять ошибочные адреса'
Def 'edge' 'reg' $e 'SearchSuggestEnabled' 0 'DWord' 'подсказки поиска (отправка ввода) — выкл'
Def 'edge' 'reg' $e 'HubsSidebarEnabled' 0 'DWord' 'боковая панель Copilot — выкл'
Def 'edge' 'reg' $e 'TrackingPrevention' 2 'DWord' 'блокировка отслеживания — сбалансированная'

Def 'delivery' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0 'DWord' 'не раздавать обновления в интернет'

$loc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'
Def 'location' 'reg' $loc 'DisableLocation' 1 'DWord' 'служба геолокации — выкл'
Def 'location' 'reg' $loc 'DisableWindowsLocationProvider' 1 'DWord' 'поставщик местоположения Windows — выкл'
Def 'location' 'reg' 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String' 'доступ приложений к местоположению — запрещён'
Def 'location' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice' 'AllowFindMyDevice' 0 'DWord' '«Поиск устройства» (отправка координат) — выкл'
Def 'location' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsAccessLocation' 2 'DWord' 'приложениям запрещено местоположение (политика)'

# Разрешения приложений — политикой, а не переключателями. Переключатель в
# ConsentStore может вернуть кто угодно: Windows после обновления, установщик,
# сам человек одним щелчком. Политика AppPrivacy стоит насмерть. Сюда же входит
# доступ к сведениям учётной записи — через него приложения узнают возраст
# пользователя (Windows Age API): без этого права вызов падает с E_ACCESSDENIED.
$ap = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
Def 'apppriv' 'reg' $ap 'LetAppsAccessAccountInfo' 2 'DWord' 'сведения учётной записи и возраст (Age API) — запрещены'
Def 'apppriv' 'reg' $ap 'LetAppsAccessContacts' 2 'DWord' 'контакты — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessCalendar' 2 'DWord' 'календарь — запрещён приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessCallHistory' 2 'DWord' 'журнал звонков — запрещён приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessEmail' 2 'DWord' 'почта — запрещена приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessMessaging' 2 'DWord' 'сообщения — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessPhone' 2 'DWord' 'звонки — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessTasks' 2 'DWord' 'задачи и планы — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessNotifications' 2 'DWord' 'чтение уведомлений — запрещено приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessMotion' 2 'DWord' 'данные о движении — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessRadios' 2 'DWord' 'управление радиомодулями — запрещено приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsSyncWithDevices' 2 'DWord' 'обмен с устройствами — запрещён приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessTrustedDevices' 2 'DWord' 'доверенные устройства — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsGetDiagnosticInfo' 2 'DWord' 'диагностика других приложений — запрещена'
Def 'apppriv' 'reg' $ap 'LetAppsActivateWithVoice' 2 'DWord' 'голосовая активация приложений — запрещена'
Def 'apppriv' 'reg' $ap 'LetAppsActivateWithVoiceAboveLock' 2 'DWord' 'голосовая активация на экране блокировки — запрещена'
Def 'apppriv' 'reg' $ap 'LetAppsAccessSystemAIModels' 2 'DWord' 'встроенные ИИ-модели Windows — запрещены приложениям' 26100

# Камера, микрофон и фоновая работа — отдельно: без них приложения из магазина
# теряют эти функции. Обычных программ (браузеров, мессенджеров) не касается.
Def 'apphw' 'reg' $ap 'LetAppsAccessCamera' 2 'DWord' 'камера — запрещена приложениям из магазина'
Def 'apphw' 'reg' $ap 'LetAppsAccessMicrophone' 2 'DWord' 'микрофон — запрещён приложениям из магазина'
Def 'apphw' 'reg' $ap 'LetAppsRunInBackground' 2 'DWord' 'фоновая работа приложений из магазина — запрещена'

# Что Windows скачивает и отправляет сама, без вашего запроса. Всё — из
# официального списка Microsoft «Manage connections from Windows operating
# system components to Microsoft services», только безопасные пункты.
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1 'DWord' 'не скачивать метаданные устройств'
Def 'network' 'reg' $sys 'EnableFontProviders' 0 'DWord' 'не скачивать шрифты по требованию'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds' 'AllowBuildPreview' 0 'DWord' 'сборки Insider — запрет'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Maps' 'AutoDownloadAndUpdateMapData' 0 'DWord' 'офлайн-карты: не обновлять сами'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Maps' 'AllowUntriggeredNetworkTrafficOnSettingsPage' 0 'DWord' 'офлайн-карты: без трафика на странице настроек'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Microsoft\OneDrive' 'PreventNetworkTrafficPreUserSignIn' 1 'DWord' 'OneDrive: не выходить в сеть до входа в систему'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Speech' 'AllowSpeechModelUpdate' 0 'DWord' 'не обновлять речевые модели'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageHealth' 'AllowDiskHealthModelUpdates' 0 'DWord' 'не скачивать модели здоровья дисков'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Messaging' 'AllowMessageSync' 0 'DWord' 'не синхронизировать сообщения с облаком'
Def 'network' 'reg' 'HKCU:\SOFTWARE\Microsoft\Messaging' 'CloudServiceSyncEnabled' 0 'DWord' 'облачная синхронизация сообщений — выкл'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TCPIP\v6Transition' 'Teredo_State' 'Disabled' 'String' 'Teredo (туннель IPv6 через Microsoft) — выкл'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config' 'AutoConnectAllowedOEM' 0 'DWord' 'Wi-Fi Sense — выкл'
Def 'network' 'task' '\Microsoft\Windows\Sustainability\PowerGridForecastTask' '' 'Disabled' '' 'не скачивать прогноз нагрузки энергосети'
# Магазин умеет ставить приложения на этот ПК по команде с сайта, без
# действий за компьютером (служба PushToInstall, pti.store.microsoft.com).
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\PushToInstall' 'DisablePushToInstall' 1 'DWord' 'установка приложений на этот ПК по команде с сайта — выкл'
# «Рекомендуемое устранение неполадок»: MitigationClient получает от
# Microsoft «исправления» (troubleshooting.microsoft.com/api/Mitigation)
# и применяет их сам. UserPreference = 1 — «не запускать».
Def 'network' 'reg' 'HKLM:\SOFTWARE\Microsoft\WindowsMitigation' 'UserPreference' 1 'DWord' 'не применять «исправления», присланные Microsoft'
Def 'network' 'task' '\Microsoft\Windows\Diagnosis\RecommendedTroubleshootingScanner' '' 'Disabled' '' 'задача RecommendedTroubleshootingScanner (поиск «исправлений» Microsoft)'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\ScriptedDiagnosticsProvider\Policy' 'EnableQueryRemoteServer' 0 'DWord' 'средства устранения неполадок не обращаются к серверам Microsoft'

# Облачная синхронизация и копия. Windows 11 без вопроса выгружает в облако
# Microsoft список ваших приложений («Архивация Windows»), сети Wi-Fi, язык,
# тему, настройки пера — и даже ваши ответы на вопросы о конфиденциальности.
# Всё найдено на чистой Windows 11 25H2; задачи отключаются и включаются
# обратно без последствий для системы.
$ss = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync'
Def 'cloudsync' 'reg' $ss 'DisableSettingSync' 2 'DWord' 'синхронизация параметров между устройствами — выкл'
Def 'cloudsync' 'reg' $ss 'DisableSettingSyncUserOverride' 1 'DWord' 'синхронизацию параметров не включить обратно в Параметрах'
Def 'cloudsync' 'task' '\Microsoft\Windows\AppListBackup\Backup' '' 'Disabled' '' 'копия списка приложений в облако — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\AppListBackup\BackupNonMaintenance' '' 'Disabled' '' 'внеплановая копия списка приложений — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\CloudRestore\Backup' '' 'Disabled' '' 'архивация Windows в облако — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\ConsentUX\UnifiedConsent\UnifiedConsentSyncTask' '' 'Disabled' '' 'синхронизация ваших согласий на сбор данных — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\WlanSvc\CDSSync' '' 'Disabled' '' 'синхронизация сетей Wi-Fi между устройствами — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\International\Synchronize Language Settings' '' 'Disabled' '' 'синхронизация языковых настроек — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\Shell\ThemesSyncedImageDownload' '' 'Disabled' '' 'скачивание обоев с других ваших устройств — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\input\syncpensettings' '' 'Disabled' '' 'синхронизация настроек пера — выкл'
# Само приложение «Архивация Windows» (CloudRestoreLauncher.dll, SyncSettings.dll)
Def 'cloudsync' 'reg' $ss 'EnableWindowsBackup' 0 'DWord' 'приложение «Архивация Windows» — выкл'

Def 'widgets' 'regpol' 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 'DWord' 'виджеты и лента новостей MSN — выкл' 22000
Def 'widgets' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 0 'DWord' 'кнопка виджетов на панели задач — убрать' 22000
Def 'widgets' 'regpol' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0 'DWord' 'лента новостей и интересов — выкл (запасной ключ)'
Def 'widgets' 'regpol' 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'DisableWidgetsBoard' 1 'DWord' 'панель виджетов — выкл' 22000
Def 'widgets' 'regpol' 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'DisableWidgetsOnLockScreen' 1 'DWord' 'виджеты на экране блокировки — выкл' 22000

$dfn = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'
Def 'defender' 'reg' $dfn 'SpyNetReporting' 0 'DWord' 'Защитник: облачная отправка MAPS — выкл'
Def 'defender' 'reg' $dfn 'SubmitSamplesConsent' 2 'DWord' 'Защитник: отправка образцов файлов — никогда'
# Служба ядра Защитника (MDCoreSvc) раз в час забирает с ecs.office.com около
# 130 удалённых настроек: включение функций, проверку запросов к ИИ-агентам,
# уведомления Microsoft 365. Проверено в виртуалке: с этой политикой обращения
# к ECS пропадают. Её же DisableCoreService1DSTelemetry отправку телеметрии
# не остановил — её закрывает hosts (mobile.events.data.microsoft.com).
Def 'defender' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Features' 'DisableCoreServiceECSIntegration' 1 'DWord' 'Защитник: удалённые настройки и эксперименты (ECS) — выкл'

Def 'services' 'svc' 'DiagTrack' '' 'Disabled' '' 'служба DiagTrack (телеметрия)'
Def 'services' 'svc' 'dmwappushservice' '' 'Disabled' '' 'служба dmwappushservice (WAP push)'
foreach ($tp in @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraisal',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
    '\Microsoft\Windows\Application Experience\PcaPatchDbTask',
    '\Microsoft\Windows\Application Experience\StartupAppTask',
    '\Microsoft\Windows\Application Experience\MareBackup',
    '\Microsoft\Windows\Application Experience\AitAgent',
    '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask',
    '\Microsoft\Windows\Customer Experience Improvement Program\BthSQM',
    '\Microsoft\Windows\Customer Experience Improvement Program\Uploader',
    '\Microsoft\Windows\Device Information\Device',
    '\Microsoft\Windows\Device Information\Device User',
    '\Microsoft\Windows\DiskFootprint\Diagnostics',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver',
    '\Microsoft\Windows\Maintenance\WinSAT',
    '\Microsoft\Windows\NetTrace\GatherNetworkInfo',
    '\Microsoft\Windows\PI\Sqm-Tasks',
    '\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem',
    '\Microsoft\Windows\Windows Error Reporting\ProcessQueuedCallHomeReports',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
    '\Microsoft\Windows\Clip\License Validation',
    '\Microsoft\Windows\CloudExperienceHost\CreateObjectTask',
    '\Microsoft\Windows\Shell\FamilySafetyMonitor',
    '\Microsoft\Windows\Shell\FamilySafetyRefreshTask',
    '\Microsoft\Windows\Speech\SpeechModelDownloadTask',
    '\Microsoft\Windows\Autochk\Proxy',
    # Появились в Windows 11 24H2–25H2. Оценщик совместимости «Exp» запускает
    # compattelrunner с DoScheduledTelemetryRun — старую задачу «Appraisal»
    # движок закрывал, а эта шла мимо. FeatureConfig\UsageData* — отчёты о том,
    # какими функциями вы пользуетесь.
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp',
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReporting',
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReceiver',
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing',
    '\Microsoft\Windows\Flighting\FeatureConfig\BootstrapUsageDataReporting',
    '\Microsoft\Windows\Flighting\FeatureConfig\GovernedFeatureUsageProcessing',
    '\Microsoft\Windows\Flighting\OneSettings\RefreshCache',
    '\Microsoft\Windows\Sustainability\SustainabilityTelemetry',
    '\Microsoft\Windows\PerformanceTrace\ShowFeedbackToast',
    '\Microsoft\Windows\Maps\MapsToastTask')) {
    Def 'services' 'task' $tp '' 'Disabled' '' ('задача ' + (Split-Path $tp -Leaf))
}
# Тоже из Windows 11 24H2–25H2, нашлись на чистой системе. InventorySvc
# работает постоянно и составляет опись установленных программ и
# оборудования для оценки совместимости и телеметрии. Usage and Quality
# Insights копит на диске «факты» о том, какими функциями вы пользуетесь,
# и выгружает их через телеметрию; её задача закрыта от администратора.
Def 'services' 'svc' 'InventorySvc' '' 'Disabled' '' 'служба InventorySvc (опись программ и оборудования)' 26100
Def 'services' 'task' '\Microsoft\Windows\UsageAndQualityInsights\UsageAndQualityInsights-MaintenanceTask' '' 'Disabled' '' 'задача UsageAndQualityInsights (сбор сведений об использовании)' 26100

$od = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
Def 'onedrive' 'reg' $od 'DisableFileSyncNGSC' 1 'DWord' 'OneDrive: синхронизация файлов — выкл'
Def 'onedrive' 'reg' $od 'DisableFileSync' 1 'DWord' 'OneDrive: старая синхронизация — выкл'
Def 'onedrive' 'reg' $od 'DisableMeteredNetworkFileSync' 1 'DWord' 'OneDrive: не синхронизировать по лимитной сети'
Def 'onedrive' 'reg' 'HKCU:\Software\Microsoft\OneDrive' 'DisablePersonalSync' 1 'DWord' 'OneDrive: личная синхронизация — выкл'
Def 'onedrive' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0 'DWord' 'OneDrive: реклама в Проводнике — выкл'
Def 'onedrive' 'taskglob' 'OneDrive*' '' 'Disabled' '' 'OneDrive: задачи обновления — выкл'

# Сессии трассировки запускаются при загрузке самой Windows и пишут телеметрию
# независимо от службы DiagTrack. Start = 0 отключает сборщик.
$al = 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger'
Def 'etw' 'regif' "$al\AutoLogger-Diagtrack-Listener" 'Start' 0 'DWord' 'главный сборщик телеметрии (Diagtrack-Listener)'
Def 'etw' 'regif' "$al\Diagtrack-Listener" 'Start' 0 'DWord' 'сборщик Diagtrack (второй вариант)'
Def 'etw' 'regif' "$al\SQMLogger" 'Start' 0 'DWord' 'сборщик программы улучшения качества (SQM)'
Def 'etw' 'regif' "$al\WiFiSession" 'Start' 0 'DWord' 'трассировка сеансов Wi-Fi'
Def 'etw' 'regif' "$al\CloudExperienceHostOobe" 'Start' 0 'DWord' 'трассировка первоначальной настройки'
Def 'etw' 'regif' "$al\DiagLog" 'Start' 0 'DWord' 'диагностический журнал DiagLog'
Def 'etw' 'regif' "$al\UBPM" 'Start' 0 'DWord' 'трассировка планировщика (UBPM)'
Def 'etw' 'regif' "$al\Microsoft-Windows-AssignedAccess-Trace" 'Start' 0 'DWord' 'трассировка AssignedAccess'
Def 'etw' 'regif' "$al\AppModel" 'Start' 0 'DWord' 'трассировка запуска приложений (AppModel)'
Def 'etw' 'reg' 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener' 'Enabled' 0 'DWord' 'запрет включения сборщика телеметрии'

Def 'hosts' 'hosts' '' '' '' '' 'блок телеметрийных доменов в hosts'

# Номер устройства в учётной записи Microsoft (GDID). Его выдаёт login.live.com
# при входе, CDPSvc регистрирует компьютер в каталоге устройств Microsoft, а
# DoSvc (Delivery Optimization) сообщает номер обратно. Смена IP и VPN на него
# не влияют; DiagTrack в этой цепочке не участвует, поэтому отключённая
# телеметрия его не останавливает. Стирать номер бесполезно: он привязан к
# учётной записи и возвращается с серверов тем же самым. Остаётся не дать ему
# уходить. DoSvc диспетчер служб не отдаёт даже администратору («Отказано в
# доступе»), поэтому службы отключаются там, где диспетчер хранит их
# настройку, — в реестре: запись идёт в журнал и откатывается как обычная.
# Разбор цепочки: github.com/SmtimesIWndr/gdid-reversal и github.com/Korben00/no-gdid.
$svcRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services'
Def 'gdid' 'regsvc' "$svcRoot\CDPSvc" 'Start' 4 'DWord' 'служба CDPSvc: регистрация компьютера в каталоге устройств Microsoft — выкл'
Def 'gdid' 'regsvc' "$svcRoot\CDPUserSvc" 'Start' 4 'DWord' 'служба CDPUserSvc: то же для каждого пользователя — выкл'
Def 'gdid' 'regsvc' "$svcRoot\DoSvc" 'Start' 4 'DWord' 'служба DoSvc (Delivery Optimization): передача номера устройства — выкл'
Def 'gdid' 'gdidhosts' '' '' '' '' 'серверы каталога устройств и Delivery Optimization — в hosts'

# Запрет выдачи номера. Новый номер выдаёт login.live.com при первом же
# обращении устройства — пока сервер открыт, стёртый номер сменяется новым.
# Закрыв его, можно стереть номер насовсем. Цена — учётная запись Microsoft:
# вход в неё, Магазин, Xbox и OneDrive перестают работать, поэтому при входе
# в Windows через неё модуль не применяется. Что и где стирается — разбор
# github.com/yegors/deGDID (проверено на Windows 11 25H2, сборка 26200).
Def 'gdidlock' 'gdidlockhosts' '' '' '' '' 'сервер выдачи номера (login.live.com, account.live.com) — в hosts'
Def 'gdidlock' 'fwsvc' 'wlidsvc' '' '' '' 'исходящие службы учётных записей Microsoft (wlidsvc) — блок'
Def 'gdidlock' 'gdidwipe' '' '' '' '' 'номер устройства стёрт отовсюду, где Windows его хранит'

# Блокировка самих адресов: hosts телеметрия обходит через шифрованный DNS
# и зашитые IP, поэтому адреса блокируются правилом брандмауэра.
Def 'fwips' 'fwips' '' '' '' '' 'блокировка адресов сбора телеметрии'

# Шифрованный DNS (DoH) позволяет обойти hosts и блокировку по доменам
Def 'doh' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'DoHPolicy' 1 'DWord' 'Windows: шифрованный DNS — запретить'
Def 'doh' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DnsOverHttpsMode' 'off' 'String' 'Edge: шифрованный DNS — выкл'
Def 'doh' 'reg' 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'DnsOverHttpsMode' 'off' 'String' 'Chrome: шифрованный DNS — выкл'

# Брандмауэр: исходящие соединения служб и программ телеметрии
Def 'firewall' 'fwsvc' 'DiagTrack' '' '' '' 'исходящие DiagTrack — блок'
Def 'firewall' 'fwsvc' 'dmwappushservice' '' '' '' 'исходящие dmwappushservice — блок'
Def 'firewall' 'fwsvc' 'WerSvc' '' '' '' 'исходящие Windows Error Reporting — блок'
Def 'firewall' 'fwapp' "$env:SystemRoot\System32\CompatTelRunner.exe" '' '' '' 'исходящие CompatTelRunner — блок'
Def 'firewall' 'fwapp' "$env:SystemRoot\System32\DeviceCensus.exe" '' '' '' 'исходящие DeviceCensus — блок'
Def 'firewall' 'fwapp' "$env:SystemRoot\System32\wsqmcons.exe" '' '' '' 'исходящие wsqmcons (CEIP) — блок'

# --- Сторонние программы ---------------------------------------------------- #
Def 'app_nvidia' 'reg' 'HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2\Client' 'OptInOrOutPreference' 0 'DWord' 'NVIDIA: участие в сборе данных — отказ'
Def 'app_nvidia' 'reg' 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS' 'EnableRID44231' 0 'DWord' 'NVIDIA: телеметрия FTS (1) — выкл'
Def 'app_nvidia' 'reg' 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS' 'EnableRID64640' 0 'DWord' 'NVIDIA: телеметрия FTS (2) — выкл'
Def 'app_nvidia' 'reg' 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS' 'EnableRID66610' 0 'DWord' 'NVIDIA: телеметрия FTS (3) — выкл'
Def 'app_nvidia' 'svcopt' 'NvTelemetryContainer' '' 'Disabled' '' 'NVIDIA: служба NvTelemetryContainer'
Def 'app_nvidia' 'taskglob' 'NvTm*' '' 'Disabled' '' 'NVIDIA: задачи телеметрии NvTm*'

Def 'app_vscode' 'vscode' 'telemetry.telemetryLevel' '' 'off' '' 'VS Code: телеметрия — выкл'
Def 'app_vscode' 'vscode' 'workbench.enableExperiments' '' $false '' 'VS Code: эксперименты — выкл'
Def 'app_vscode' 'vscode' 'telemetry.feedback.enabled' '' $false '' 'VS Code: опросы — выкл'

$ch = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
Def 'app_chrome' 'reg' $ch 'MetricsReportingEnabled' 0 'DWord' 'Chrome: статистика использования — выкл'
Def 'app_chrome' 'reg' $ch 'UrlKeyedAnonymizedDataCollectionEnabled' 0 'DWord' 'Chrome: отправка адресов сайтов — выкл'
Def 'app_chrome' 'reg' $ch 'AlternateErrorPagesEnabled' 0 'DWord' 'Chrome: не отправлять ошибочные адреса'
Def 'app_chrome' 'reg' $ch 'SpellCheckServiceEnabled' 0 'DWord' 'Chrome: облачная проверка орфографии — выкл'
Def 'app_chrome' 'reg' $ch 'PrivacySandboxAdMeasurementEnabled' 0 'DWord' 'Chrome: измерение рекламы — выкл'
Def 'app_chrome' 'reg' $ch 'PrivacySandboxAdTopicsEnabled' 0 'DWord' 'Chrome: рекламные темы — выкл'
Def 'app_chrome' 'reg' $ch 'PrivacySandboxSiteEnabledAdsEnabled' 0 'DWord' 'Chrome: реклама по сайтам — выкл'
Def 'app_chrome' 'reg' $ch 'PrivacySandboxPromptEnabled' 0 'DWord' 'Chrome: окно Privacy Sandbox — выкл'

Def 'app_firefox' 'firefox' 'DisableTelemetry' '' $true '' 'Firefox: телеметрия — выкл'
Def 'app_firefox' 'firefox' 'DisableFirefoxStudies' '' $true '' 'Firefox: исследования — выкл'

$of = 'HKCU:\Software\Policies\Microsoft\office\16.0\common'
Def 'app_office' 'reg' "$of\clienttelemetry" 'SendTelemetry' 3 'DWord' 'Office: телеметрия — ни базовой, ни расширенной'
Def 'app_office' 'reg' 'HKCU:\Software\Policies\Microsoft\office\common\clienttelemetry' 'DisableTelemetry' 1 'DWord' 'Office: телеметрия клиента — выкл'
Def 'app_office' 'reg' $of 'sendcustomerdata' 0 'DWord' 'Office: данные клиента — не отправлять'
Def 'app_office' 'reg' "$of\feedback" 'enabled' 0 'DWord' 'Office: отзывы — выкл'
Def 'app_office' 'reg' "$of\feedback" 'includescreenshot' 0 'DWord' 'Office: снимки экрана в отзывах — выкл'

Def 'app_devtools' 'env' 'POWERSHELL_TELEMETRY_OPTOUT' '' '1' '' 'PowerShell 7: телеметрия — выкл'
Def 'app_devtools' 'env' 'POWERSHELL_UPDATECHECK' '' 'Off' '' 'PowerShell 7: проверка обновлений — выкл'
Def 'app_devtools' 'env' 'DOTNET_CLI_TELEMETRY_OPTOUT' '' '1' '' '.NET SDK: телеметрия — выкл'

Def 'app_vs' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\VisualStudio\SQM' 'OptIn' 0 'DWord' 'Visual Studio: программа улучшения качества — отказ'
Def 'app_vs' 'reg' 'HKCU:\Software\Microsoft\VisualStudio\Telemetry' 'TurnOffSwitch' 1 'DWord' 'Visual Studio: телеметрия — выкл'
Def 'app_vs' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\VisualStudio\Feedback' 'DisableFeedbackDialog' 1 'DWord' 'Visual Studio: окно отзывов — выкл'

$script:ModuleOrder = @('telemetry','errors','activity','input','edge','delivery','location','apppriv','network','cloudsync','ads','widgets','search','copilot','ai',
                        'defender','apphw','onedrive','services','etw','hosts','gdid','gdidlock','firewall','fwips','doh','buffer','app_nvidia','app_vscode','app_chrome','app_firefox',
                        'app_office','app_devtools','app_vs','oem','cleanup','startup')
$script:ModuleTitles = @{
    telemetry='Телеметрия и диагностика'; errors='Отчёты об ошибках'; activity='История активности и буфер обмена';
    input='Персонализация ввода, рукописный ввод, речь'; edge='Microsoft Edge'; delivery='Раздача обновлений другим ПК';
    location='Геолокация и поиск устройства'; apppriv='Разрешения приложений (запрет политикой)';
    network='Фоновые обращения Windows в сеть'; cloudsync='Облачная синхронизация и копия'; apphw='Камера, микрофон и фоновая работа приложений'; ads='Рекламный ID и реклама в интерфейсе'; widgets='Виджеты и лента новостей';
    search='Поиск: Bing, Cortana, облако'; copilot='Copilot и Recall';
    ai='ИИ-функции Windows'; defender='Защитник: облако и образцы'; etw='Сессии трассировки телеметрии'; onedrive='OneDrive: синхронизация и реклама'; services='Службы и задачи телеметрии'; hosts='Блокировка телеметрийных доменов (hosts)';
    gdid='Номер устройства в учётной записи Microsoft (GDID)'; gdidlock='Запрет выдачи номера устройства';
    firewall='Брандмауэр: блокировка служб телеметрии'; fwips='Брандмауэр: адреса сбора телеметрии'; doh='Шифрованный DNS (обход блокировки)'; buffer='Неотправленная телеметрия'; app_nvidia='NVIDIA';
    app_vscode='Visual Studio Code'; app_chrome='Google Chrome'; app_firefox='Mozilla Firefox'; app_office='Microsoft Office';
    app_devtools='PowerShell 7 / .NET SDK'; app_vs='Visual Studio'; oem='Компоненты сбора данных производителя';
    cleanup='Чистка временных файлов'; startup='Автозагрузка (отчёт)'
}

# --------------------------------------------------------------------------- #
#  Цена каждой настройки. Уровень: safe — ничего заметного не ломается,
#  limited — какая-то функция Windows перестанет работать, caution — может
#  задеть то, что вам нужно. По умолчанию уровень — как у модуля; отдельные
#  пункты уточнены ниже, вместе с тем, что именно перестанет работать.
#  Ключ — название настройки, как в Def.
# --------------------------------------------------------------------------- #
$script:ModuleRisk = @{
    location = 'limited'; apppriv = 'limited'; apphw = 'limited'; onedrive = 'limited'; services = 'limited'
    hosts = 'limited'; firewall = 'limited'; fwips = 'caution'; doh = 'limited'; defender = 'caution'
    gdid = 'limited'; gdidlock = 'caution'; oem = 'limited'; cloudsync = 'limited'
}
$script:DefRisk = @{
    'уровень телеметрии — минимальный' = 'safe'
    'служба DiagTrack (телеметрия)' = 'safe'
    'задача License Validation' = 'caution'
    'Teredo (туннель IPv6 через Microsoft) — выкл' = 'limited'
    'история буфера обмена — выкл' = 'limited'
    'не скачивать прогноз нагрузки энергосети' = 'safe'
    'Click to Do: скачивание моделей ИИ — выкл' = 'safe'
    'задача UsageAndQualityInsights (сбор сведений об использовании)' = 'safe'
    'синхронизация ваших согласий на сбор данных — выкл' = 'safe'
    'скачивание обоев с других ваших устройств — выкл' = 'safe'
    'не применять «исправления», присланные Microsoft' = 'limited'
    'средства устранения неполадок не обращаются к серверам Microsoft' = 'limited'
    'Защитник: удалённые настройки и эксперименты (ECS) — выкл' = 'limited'
    'обои «Windows: интересное» на рабочем столе — выкл' = 'limited'
    'ИИ-агенты: доступ к файлам и настройкам через MCP — запрещён' = 'limited'
    'приложение «Архивация Windows» — выкл' = 'limited'
    'облачное распознавание речи — выкл' = 'limited'
}
$script:DefNotes = @{
    'уровень телеметрии — минимальный' = 'На Home и Pro Windows всё равно оставит «обязательные данные»: полностью выключает только Enterprise и Education.'
    'история буфера обмена — выкл' = 'Win+V перестанет показывать историю скопированного.'
    'синхронизация буфера между устройствами — выкл' = 'Буфер обмена не будет общим с телефоном и другими компьютерами.'
    'облачное распознавание речи — выкл' = 'Голосовой ввод и диктовка через облако Microsoft перестанут работать.'
    'веб-поиск из Пуска — выкл' = 'Поиск в Пуске будет искать только на компьютере, без результатов из интернета.'
    'служба геолокации — выкл' = 'Карты, погода и автоматический часовой пояс не узнают, где вы.'
    '«Поиск устройства» (отправка координат) — выкл' = 'Потерянный ноутбук нельзя будет найти через «Поиск устройства».'
    'сведения учётной записи и возраст (Age API) — запрещены' = 'Приложения из Магазина не узнают ваше имя, аватар и возраст.'
    'почта — запрещена приложениям' = 'Почта из Магазина не увидит ваши письма, пока вы не разрешите её вручную.'
    'календарь — запрещён приложениям' = 'Календарь из Магазина не увидит ваши события, пока вы не разрешите его вручную.'
    'обмен с устройствами — запрещён приложениям' = 'Приложения не смогут связываться с телефоном и устройствами Bluetooth без вашего разрешения.'
    'камера — запрещена приложениям из магазина' = 'Камера перестанет работать в приложениях Магазина. В браузерах и обычных программах — работает.'
    'микрофон — запрещён приложениям из магазина' = 'Микрофон перестанет работать в приложениях Магазина. В браузерах и обычных программах — работает.'
    'фоновая работа приложений из магазина — запрещена' = 'Приложения из Магазина не будут присылать уведомления и обновляться, пока закрыты.'
    'Teredo (туннель IPv6 через Microsoft) — выкл' = 'Сетевые игры Xbox, которым нужен Teredo, могут не подключаться.'
    'OneDrive: синхронизация файлов — выкл' = 'OneDrive перестанет синхронизировать файлы. Сами файлы на диске остаются.'
    'служба dmwappushservice (WAP push)' = 'Нужна, если компьютером управляет организация (MDM). Дома не используется.'
    'задача License Validation' = 'Проверяет лицензии приложений Магазина. Если купленные приложения перестанут запускаться — снимите этот пункт.'
    'задача FamilySafetyMonitor' = 'Родительский контроль Microsoft Family перестанет работать.'
    'Защитник: облачная отправка MAPS — выкл' = 'Защитник теряет облачную проверку: новые угрозы он будет узнавать позже.'
    'Защитник: отправка образцов файлов — никогда' = 'Подозрительные файлы не уйдут на анализ в Microsoft.'
    'Windows: шифрованный DNS — запретить' = 'Ваши DNS-запросы снова видит провайдер. Зато hosts работает для всех программ.'
    'блок телеметрийных доменов в hosts' = 'Windows Update и Магазин не затрагиваются. Изредка перестают уходить отчёты об ошибках.'
    'блокировка адресов сбора телеметрии' = 'На тех же адресах иногда живут другие службы Microsoft — если что-то отвалится, снимите пункт.'
    'служба CDPSvc: регистрация компьютера в каталоге устройств Microsoft — выкл' = '«Связь с телефоном» и обмен с устройствами поблизости перестанут работать.'
    'служба DoSvc (Delivery Optimization): передача номера устройства — выкл' = 'Если Магазин перестанет скачивать приложения — снимите этот пункт.'
    'сервер выдачи номера (login.live.com, account.live.com) — в hosts' = 'Вход в учётную запись Microsoft, Магазин, Xbox и OneDrive перестанут работать.'
    'служба InventorySvc (опись программ и оборудования)' = 'Перед крупным обновлением Windows проверка совместимости будет знать о ваших программах меньше.'
    'синхронизация параметров между устройствами — выкл' = 'Тема, язык и другие настройки не переедут на новый компьютер сами — их придётся задать заново.'
    'копия списка приложений в облако — выкл' = 'На новом компьютере Windows не предложит заново поставить ваши приложения.'
    'архивация Windows в облако — выкл' = 'Копия в OneDrive перестанет обновляться сама. Если рассчитываете на неё при переезде — снимите пункт.'
    'синхронизация сетей Wi-Fi между устройствами — выкл' = 'Пароли Wi-Fi не будут переезжать на другие ваши компьютеры.'
    'установка приложений на этот ПК по команде с сайта — выкл' = 'Кнопка «Установить на устройство» на сайте Магазина перестанет работать. В самом Магазине всё ставится как обычно.'
    'не применять «исправления», присланные Microsoft' = 'Windows перестанет сама чинить известные сбои по указанию Microsoft. Средства устранения неполадок можно запускать вручную.'
    'средства устранения неполадок не обращаются к серверам Microsoft' = 'Средства устранения неполадок будут работать только с тем, что есть на компьютере.'
    'Защитник: удалённые настройки и эксперименты (ECS) — выкл' = 'Новые функции и усиления защиты Защитник будет получать только с обновлениями, а не с сервера экспериментов. Базы угроз обновляются как обычно.'
    'обои «Windows: интересное» на рабочем столе — выкл' = 'Картинки «Windows: интересное» на рабочем столе перестанут меняться сами.'
    'ИИ-агенты: доступ к файлам и настройкам через MCP — запрещён' = 'ИИ-помощники не смогут сами работать с вашими файлами и настройками Windows.'
    'приложение «Архивация Windows» — выкл' = 'Приложение «Архивация Windows» перестанет сохранять копию в OneDrive. Файлы на диске не трогаются.'
    'встроенные ИИ-модели Windows — запрещены приложениям' = 'Приложения из Магазина не смогут пользоваться ИИ-моделями Windows на компьютере.'
}

function Get-DefRisk {
    param($Def)
    if ($script:DefRisk.ContainsKey("$($Def.C)")) { return $script:DefRisk["$($Def.C)"] }
    if ($script:ModuleRisk.ContainsKey("$($Def.M)")) { return $script:ModuleRisk["$($Def.M)"] }
    return 'safe'
}

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

# =========================================================================== #
#  Применение / проверка одного определения
# =========================================================================== #
# --------------------------------------------------------------------------- #
#  УБОРКА ЗА СТАРЫМИ ВЕРСИЯМИ
#  В версиях 1.1.0–1.5.0 счётчик внутри Def затирал имя параметра, и настройки
#  писались в реестр под числовыми именами: «0», «1», «2» вместо AllowTelemetry.
#  Они ничего не настраивали. Находим ровно свои: имя — число, оно совпадает с
#  номером определения по этому пути, а значение — с тем, что мы бы записали.
# --------------------------------------------------------------------------- #
function Find-JunkValues {
    $byIdx = @{}
    $paths = @{}
    foreach ($d in $script:Defs) {
        if ($script:RegTypes -notcontains $d.T) { continue }
        $paths["$($d.P)"] = $true
        $parts = "$($d.Id)" -split '#'
        if ($parts.Count -ne 2) { continue }
        $k = "$($d.P)|$([int]$parts[1])"
        if (-not $byIdx.ContainsKey($k)) { $byIdx[$k] = $d }
    }
    $junk = @()
    foreach ($path in @($paths.Keys)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $names = @()
        # без -ErrorAction Stop отказ доступа не ловится try/catch и сыплется в вывод
        try { $names = @((Get-Item -LiteralPath $path -ErrorAction Stop).GetValueNames()) } catch { continue }
        foreach ($nm in $names) {
            if ($nm -notmatch '^[0-9]{1,3}$') { continue }
            $k = "$path|$([int]$nm)"
            if (-not $byIdx.ContainsKey($k)) { continue }
            $cur = Get-RegValue $path $nm
            if ($null -eq $cur) { continue }
            if ("$cur" -ne "$($byIdx[$k].V)") { continue }      # значение чужое — не наше
            $junk += @{ path = $path; name = $nm; title = "$($byIdx[$k].C)" }
        }
    }
    return @($junk)
}

function Remove-JunkValues {
    $junkList = @(Find-JunkValues)
    if ($junkList.Count -eq 0) { return 0 }
    $gone = 0
    foreach ($j in $junkList) {
        if ($DryRun) { Write-Log ("   [тест] мусор от старой версии: {0} -> {1}" -f $j.path, $j.name); continue }
        try {
            Remove-ItemProperty -LiteralPath $j.path -Name $j.name -Force -ErrorAction Stop
            Write-Log ("   [+] убран мусорный параметр {0} ({1})" -f $j.name, $j.title)
            $gone++
        } catch { Write-Log ("   [!] не удалось убрать {0} -> {1}" -f $j.path, $j.name) }
    }
    return $gone
}

# Останавливает службу, отключённую через реестр, и её копии для каждого
# пользователя (CDPUserSvc_1a2b3): запись в реестре вступает в силу только
# после перезагрузки, а до неё служба продолжила бы работать.
function Stop-ServiceInstances {
    param([string]$Name)
    foreach ($s in @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $Name -or $_.Name -like ($Name + '_*') })) {
        if ($s.Status -ne 'Running') { continue }
        try { Stop-Service -Name $s.Name -Force -ErrorAction Stop; Write-Log ("       остановлена: {0}" -f $s.Name) }
        catch { Write-Log ("       {0} остановится после перезагрузки" -f $s.Name) }
    }
}

function Apply-Def {
    param($d)
    # журнал отката не пишется — больше ничего не меняем (причина уже в журнале работы)
    if ($script:JournalFailed -and -not $DryRun) { return }
    switch ($d.T) {
        'reg' { Set-Reg -Path $d.P -Name $d.N -Value $d.V -Type $d.Type -Comment $d.C }
        'regsvc' {
            # служба есть не на каждой редакции Windows — чего нет, то не создаём
            if (-not (Test-Path -LiteralPath $d.P)) { Write-Log ("   [-] {0} -- нет на этой системе" -f $d.C); return }
            Set-Reg -Path $d.P -Name $d.N -Value $d.V -Type $d.Type -Comment $d.C
            # останавливаем, только если отключение действительно записалось:
            # иначе служба тут же запустилась бы снова
            if (-not $DryRun -and "$($d.V)" -eq '4' -and "$(Get-RegValue $d.P $d.N)" -eq '4') { Stop-ServiceInstances (Split-Path $d.P -Leaf) }
        }
        'regpol' { Set-Reg -Path $d.P -Name $d.N -Value $d.V -Type $d.Type -Comment $d.C -Policy -DefId $d.Id }
        'regif' {
            # сессия трассировки есть не на каждой сборке Windows — чего нет, то не создаём
            if (Test-Path -LiteralPath $d.P) { Set-Reg -Path $d.P -Name $d.N -Value $d.V -Type $d.Type -Comment $d.C }
            else { Write-Log ("   [-] {0} -- нет на этой системе" -f $d.C) }
        }
        'svc' {
            if ($DryRun) { Write-Log "   [тест] $($d.C) -- отключить"; return }
            try {
                $s = Get-Service -Name $d.P -ErrorAction Stop
                if ($s.StartType -eq 'Disabled' -and $s.Status -ne 'Running') {
                    Write-Log "   [в] $($d.C) -- уже настроено"; $script:Already++; return
                }
                Ensure-Backup
                $was = Get-SvcJournalState $d.P $s
                if ($s.Status -eq 'Running') { Stop-Service -Name $d.P -Force -ErrorAction SilentlyContinue }
                Set-Service -Name $d.P -StartupType Disabled -ErrorAction Stop
                Add-JournalEntry $was
                Write-Log "   [+] $($d.C) -- остановлена и отключена"; $script:Changes++
            } catch { Write-Log "   [-] $($d.C) -- недоступна" }
        }
        'svcopt' {
            $s = Get-Service -Name $d.P -ErrorAction SilentlyContinue
            if (-not $s) { return }
            if ($DryRun) { Write-Log "   [тест] $($d.C) -- отключить"; return }
            try {
                if ($s.StartType -eq 'Disabled' -and $s.Status -ne 'Running') {
                    Write-Log "   [в] $($d.C) -- уже настроено"; $script:Already++; return
                }
                Ensure-Backup
                $was = Get-SvcJournalState $d.P $s
                if ($s.Status -eq 'Running') { Stop-Service -Name $d.P -Force -ErrorAction SilentlyContinue }
                Set-Service -Name $d.P -StartupType Disabled -ErrorAction Stop
                Add-JournalEntry $was
                Write-Log "   [+] $($d.C) -- отключена"; $script:Changes++
            } catch { Write-Log "   [-] $($d.C) -- не удалось" }
        }
        'task' {
            $pp = Split-TaskPath $d.P
            if ($DryRun) { Write-Log "   [тест] $($d.C) -- отключить"; return }
            $st = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction SilentlyContinue
            if (-not $st) { Write-Log "   [-] $($d.C) -- нет на этой системе"; return }
            if ($st.State -eq 'Disabled') { Write-Log "   [в] $($d.C) -- уже настроено"; $script:Already++; return }
            Ensure-Backup
            switch (Set-TaskEnabled $d.P $false) {
                'ok'      { Add-TaskJournal $d.P; Write-Log "   [+] $($d.C) -- отключена"; $script:Changes++ }
                'system'  { Add-TaskJournal $d.P; Write-Log "   [+] $($d.C) -- отключена от имени системы (администратору Windows её не отдаёт)"; $script:Changes++ }
                'missing' { Write-Log "   [-] $($d.C) -- нет на этой системе" }
                default   { Write-Log "   [!] $($d.C) -- Windows не дала отключить задачу"; $script:Failures++ }
            }
        }
        'taskglob' {
            $ts = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like $d.P })
            if ($ts.Count -eq 0) { return }
            foreach ($t in $ts) {
                if ($DryRun) { Write-Log "   [тест] задача $($t.TaskName) -- отключить"; continue }
                if ($t.State -eq 'Disabled') { Write-Log "   [в] задача $($t.TaskName) -- уже отключена"; $script:Already++; continue }
                Ensure-Backup
                try { Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null; Add-TaskJournal ($t.TaskPath + $t.TaskName); Write-Log "   [+] задача $($t.TaskName) -- отключена"; $script:Changes++ }
                catch { Write-Log "   [-] задача $($t.TaskName) -- не удалось" }
            }
        }
        'env' {
            if ($DryRun) { Write-Log "   [тест] $($d.C)"; return }
            if ([string][Environment]::GetEnvironmentVariable($d.P, 'User') -eq [string]$d.V) {
                Write-Log "   [в] $($d.C) -- уже настроено"; $script:Already++; return
            }
            Ensure-Backup
            $prevEnv = [Environment]::GetEnvironmentVariable($d.P, 'User')
            try {
                [Environment]::SetEnvironmentVariable($d.P, [string]$d.V, 'User')
                Add-JournalEntry @{ kind = 'env'; name = $d.P; existed = [bool]($null -ne $prevEnv)
                                    old = $(if ($null -ne $prevEnv) { [string]$prevEnv } else { '' }); newValue = [string]$d.V }
                Write-Log "   [+] $($d.C)"; $script:Changes++
            }
            catch { Write-Log "   [!] не удалось: $($d.C)"; $script:Failures++ }
        }
        'vscode'  { Set-VsCodeValue -Key $d.P -Value $d.V -Comment $d.C }
        'firefox' { Set-FirefoxPolicy -Key $d.P -Value $d.V -Comment $d.C }
        'hosts'   { Apply-Hosts }
        'gdidhosts' { Apply-Hosts -Kind 'gdid' }
        'gdidlockhosts' { Apply-Hosts -Kind 'lock' }
        'gdidwipe' {
            # Пока сервер выдачи открыт, стёртый номер сразу сменится новым —
            # это смена номера, а не запрет. Без закрытого сервера не стираем.
            if (-not $DryRun -and -not (Test-HostsBlock -Kind 'lock')) {
                Write-Log ("   [-] {0} -- пропущено: сервер выдачи номера не закрыт" -f $d.C); return
            }
            $null = Invoke-GdidWipe
        }
        'fwsvc'   { Apply-FwRule -Kind 'svc' -Target $d.P -Comment $d.C }
        'fwapp'   { Apply-FwRule -Kind 'app' -Target $d.P -Comment $d.C }
        'fwips'   { Apply-FwIpBlock }
    }
}

# Настройки, которой на этой версии Windows не существует, не бывает
# «не применённой»: помечаем na и не считаем ни в плюс, ни в минус.
function Test-DefApplicable {
    param($d)
    $minB = 0
    try { $minB = [int]$d.Min } catch { }
    if ($minB -le 0 -or $script:OsBuild -le 0) { return $true }
    return ($script:OsBuild -ge $minB)
}

function Check-Def {
    param($d)
    $ok = $false; $actual = ''
    if (-not (Test-DefApplicable $d)) {
        return @{ module=$d.M; name=$d.C; ok=$false; na=$true
                  expected="$($d.V)"; actual='нет на этой версии Windows' }
    }
    # Запрет выдачи номера при входе через учётную запись Microsoft недоступен
    # вовсе — индекс за него не снижается, как и за то, чего нет в этой Windows.
    if ($d.M -eq 'gdidlock' -and (Get-GdidLockRefusal)) {
        return @{ module=$d.M; name=$d.C; ok=$false; na=$true
                  expected="$($d.V)"; actual=$(if ((Get-GdidLockRefusal) -eq 'msa') { 'недоступно при входе через учётную запись Microsoft' } else { 'недоступно на компьютере организации' }) }
    }
    switch ($d.T) {
        { $_ -in @('regif', 'regsvc') } {
            if (-not (Test-Path -LiteralPath $d.P)) { $ok = $true; $actual = 'нет на этой системе' }
            else {
                $v = Get-RegValue $d.P $d.N
                $actual = if ($null -eq $v) { 'не задано' } else { "$v" }
                $ok = ($null -ne $v) -and ("$v" -eq "$($d.V)")
            }
        }
        'regpol' {
            # Проверяем как обычный параметр. «Windows не разрешает» — это факт,
            # известный только после неудачной записи, и подставляется он в
            # -Audit по журналу отказов; здесь догадок не строим.
            $v = Get-RegValue $d.P $d.N
            $actual = if ($null -eq $v) { 'не задано' } else { "$v" }
            $ok = ($null -ne $v) -and ("$v" -eq "$($d.V)")
        }
        'reg' {
            $v = Get-RegValue $d.P $d.N
            $actual = if ($null -eq $v) { 'не задано' } else { "$v" }
            $ok = ($null -ne $v) -and ("$v" -eq "$($d.V)")
        }
        'svc' {
            $s = Get-Service -Name $d.P -ErrorAction SilentlyContinue
            if (-not $s) { $ok = $true; $actual = 'нет службы' }
            else { $actual = "$($s.StartType) / $($s.Status)"; $ok = ($s.StartType -eq 'Disabled') }
        }
        'svcopt' {
            $s = Get-Service -Name $d.P -ErrorAction SilentlyContinue
            if (-not $s) { $ok = $true; $actual = 'нет службы' }
            else { $actual = "$($s.StartType)"; $ok = ($s.StartType -eq 'Disabled') }
        }
        'task' {
            $pp = Split-TaskPath $d.P
            $t = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction SilentlyContinue
            if (-not $t) { $ok = $true; $actual = 'нет задачи' }
            else { $actual = [string]$t.State; $ok = ($t.State -eq 'Disabled') }
        }
        'taskglob' {
            $ts = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like $d.P })
            $bad = @($ts | Where-Object { $_.State -ne 'Disabled' })
            $ok = ($bad.Count -eq 0); $actual = "всего $($ts.Count), активных $($bad.Count)"
        }
        'env' {
            $v = [Environment]::GetEnvironmentVariable($d.P, 'User')
            $actual = if ($v) { $v } else { 'не задано' }
            $ok = ("$v" -eq "$($d.V)")
        }
        'vscode' {
            $v = Get-VsCodeValue $d.P
            $actual = if ($null -eq $v) { 'не задано' } else { "$v" }
            $ok = ($null -ne $v) -and ("$v".ToLower() -eq "$($d.V)".ToLower())
        }
        'firefox' {
            $v = Get-FirefoxPolicy $d.P
            $actual = if ($null -eq $v) { 'не задано' } else { "$v" }
            $ok = ($null -ne $v) -and ("$v".ToLower() -eq "$($d.V)".ToLower())
        }
        { $_ -in @('hosts', 'gdidhosts', 'gdidlockhosts') } {
            $hk = $(switch ($d.T) { 'gdidhosts' { 'gdid' } 'gdidlockhosts' { 'lock' } default { 'telemetry' } })
            $ok = Test-HostsBlockCurrent -Kind $hk
            $actual = if ($ok) { 'блок установлен' } elseif (Test-HostsBlock -Kind $hk) { 'блок устарел' } else { 'нет блока' }
        }
        'gdidwipe' {
            $ok = (@(Get-GdidCopies).Count -eq 0); $actual = if ($ok) { 'номера нет' } else { 'номер на месте' }
        }
        'fwips' {
            $ok = Test-FwIpRule -Fresh
            $actual = if ($ok) { 'адреса заблокированы' } elseif (Test-FwIpRule) { 'адреса устарели' } else { 'нет правила' }
        }
        'fwsvc' { $ok = Test-FwRule -Kind 'svc' -Target $d.P; $actual = if ($ok) { 'правило есть' } else { 'нет правила' } }
        'fwapp' { $ok = Test-FwRule -Kind 'app' -Target $d.P; $actual = if ($ok) { 'правило есть' } else { 'нет правила' } }
    }
    return @{ module=$d.M; name=$d.C; ok=[bool]$ok; expected="$($d.V)"; actual=$actual }
}

# --- hosts ------------------------------------------------------------------ #
$script:HostsDomains = @(
    'vortex.data.microsoft.com','vortex-win.data.microsoft.com','telecommand.telemetry.microsoft.com',
    'telemetry.microsoft.com','watson.telemetry.microsoft.com','oca.telemetry.microsoft.com',
    'sqm.telemetry.microsoft.com','df.telemetry.microsoft.com','wes.df.telemetry.microsoft.com',
    'reports.wes.df.telemetry.microsoft.com','services.wes.df.telemetry.microsoft.com','sqm.df.telemetry.microsoft.com',
    'telemetry.urs.microsoft.com','choice.microsoft.com','v10.events.data.microsoft.com','v20.events.data.microsoft.com',
    'us-v10.events.data.microsoft.com','eu-v10.events.data.microsoft.com','self.events.data.microsoft.com',
    'functional.events.data.microsoft.com','browser.pipe.aria.microsoft.com','mobile.pipe.aria.microsoft.com',
    'telemetry.appex.bing.net','nexus.officeapps.live.com','nexusrules.officeapps.live.com',
    'eu-mobile.events.data.microsoft.com','us-mobile.events.data.microsoft.com',
    'jp.events.data.microsoft.com','uk.events.data.microsoft.com',
    'in.events.data.microsoft.com','au.events.data.microsoft.com',
    'ca.events.data.microsoft.com','br.events.data.microsoft.com',
    'de.events.data.microsoft.com','fr.events.data.microsoft.com',
    'asia.events.data.microsoft.com','tb.events.data.microsoft.com',
    'v10.vortex-win.data.microsoft.com','v10c.events.data.microsoft.com',
    'events-sandbox.data.microsoft.com','events.data.microsoft.com',
    'watson.events.data.microsoft.com','umwatson.events.data.microsoft.com',
    'settings-win.data.microsoft.com','settings-sandbox.data.microsoft.com',
    'ceuswatcab01.blob.core.windows.net','ceuswatcab02.blob.core.windows.net',
    'eaus2watcab01.blob.core.windows.net','eaus2watcab02.blob.core.windows.net',
    'weus2watcab01.blob.core.windows.net','weus2watcab02.blob.core.windows.net',
    'oca.telemetry.microsoft.com.nsatc.net','sqm.telemetry.microsoft.com.nsatc.net',
    'telecommand.telemetry.microsoft.com.nsatc.net','vortex-sandbox.data.microsoft.com',
    'cs11.wpc.v0cdn.net','cs1137.wpc.gammacdn.net','modern.watson.data.microsoft.com',
    'browser.events.data.msn.com',
    # Найдены разбором чистой Windows 11 25H2 (сборка 26300): адреса прямой
    # отправки 1DS, зашитые в системные файлы и в скачанную настройку UTC.
    # mobile.events — главный из них: на него шлют Защитник (MDCoreSvc),
    # оболочка (AriaSDKWrapper.dll), Copilot, «Архивация» и «История файлов»,
    # минуя службу DiagTrack. Региональные v20 UTC выбирает по стране.
    'mobile.events.data.microsoft.com','au-mobile.events.data.microsoft.com',
    'jp-mobile.events.data.microsoft.com','uk-mobile.events.data.microsoft.com',
    'pf.events.data.microsoft.com','eu-office.events.data.microsoft.com',
    'browser.events.data.microsoft.com','nw-umwatson.events.data.microsoft.com',
    'au-v10.events.data.microsoft.com','in-v10.events.data.microsoft.com','jp-v10.events.data.microsoft.com',
    'au-v20.events.data.microsoft.com','eu-v20.events.data.microsoft.com','in-v20.events.data.microsoft.com',
    'jp-v20.events.data.microsoft.com','uk-v20.events.data.microsoft.com','us-v20.events.data.microsoft.com',
    'us4-v20.events.data.microsoft.com','us5-v20.events.data.microsoft.com',
    'au.vortex-win.data.microsoft.com','uk.vortex-win.data.microsoft.com','web.vortex.data.microsoft.com',
    'settings.data.microsoft.com','evrsettings-win.data.microsoft.com',
    'activity.windows.com','licensing.mp.microsoft.com',
    # Найдено записью Windows 11 с программой на максимуме: эти адреса всё ещё
    # получали данные. bat.bing.com — рекламный счётчик Bing в Магазине;
    # nelreports.net — отчёты Edge и других программ о сетевых ошибках
    # (Network Error Logging); default.exp-tas.com — раздача экспериментов
    # приложениям («Фотографии», VS Code). Без них всё работает как прежде.
    'bat.bing.com','deff.nelreports.net','aefd.nelreports.net','default.exp-tas.com')
$script:HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"

# Серверы, через которые компьютер регистрируется в каталоге устройств Microsoft
# и сообщает номер устройства. login.live.com здесь нет и быть не должно: без
# него перестанет работать вход в учётную запись Microsoft. Первые три имени
# публично не разрешаются, но Windows их спрашивает — блокировать есть что.
# cs.dds.microsoft.com — нынешний адрес каталога: остальные имена каталога
# публично не разрешаются, но Windows их спрашивает.
$script:GdidHosts = @('cs.dds.microsoft.com', 'dds.microsoft.com', 'fd.dds.microsoft.com', 'aad.cs.dds.microsoft.com',
                      'cdpcs.access.microsoft.com', 'geo.prod.do.dsp.mp.microsoft.com')

# Сервер, который выдаёт номер новому устройству. Его закрывает только запрет
# выдачи (модуль gdidlock) и только у тех, кто входит в Windows без учётной
# записи Microsoft: без него эта учётная запись не работает вовсе.
$script:GdidLockHosts = @('login.live.com', 'account.live.com')

# У блоков номера устройства свои метки: блок телеметрии и они ставятся и
# проверяются порознь. Общий шаблон $script:HostsMarkRegex узнаёт все — откат
# убирает всё, что программа дописала в hosts.
$script:HostsMarkGdidStart = '# --- Win11Privacy: device id block (begin) ---'
$script:HostsMarkGdidEnd   = '# --- Win11Privacy: device id block (end) ---'
$script:HostsMarkLockStart = '# --- Win11Privacy: device id lock (begin) ---'
$script:HostsMarkLockEnd   = '# --- Win11Privacy: device id lock (end) ---'

# Блок телеметрии — любая метка программы, кроме меток номера устройства:
# так узнаются и метки прежних версий, побитые в «?».
function Test-HostsBlock {
    param([string]$Kind = 'telemetry')
    try { $lines = @(Get-Content -LiteralPath $script:HostsPath -ErrorAction Stop) } catch { return $false }
    if ($Kind -eq 'gdid') { return [bool]($lines -contains $script:HostsMarkGdidStart) }
    if ($Kind -eq 'lock') { return [bool]($lines -contains $script:HostsMarkLockStart) }
    return [bool](@(@($lines -match $script:HostsMarkRegex) | Where-Object { $_ -notlike '*device id*' }).Count -gt 0)
}

# Принадлежит ли открывающая метка блоку этого вида
function Test-HostsMarkKind {
    param([string]$Line, [string]$Kind)
    switch ($Kind) {
        'all'  { return $true }
        'gdid' { return ($Line -eq $script:HostsMarkGdidStart) }
        'lock' { return ($Line -eq $script:HostsMarkLockStart) }
        default { return ($Line -notlike '*device id*') }
    }
}

# Строка «0.0.0.0» отвечает только на запрос IPv4. Если у сервера есть адрес
# IPv6, Windows спросит его у DNS и соединится мимо блока — поэтому на каждое
# имя пишется и строка «::».
function Get-HostsWanted {
    param([string]$Kind = 'telemetry')
    $domains = $(switch ($Kind) { 'gdid' { $script:GdidHosts } 'lock' { $script:GdidLockHosts } default { $script:HostsDomains } })
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($d in @($domains)) { $out.Add('0.0.0.0 ' + $d); $out.Add(':: ' + $d) }
    return $out.ToArray()
}

function Get-HostsBlockLines {
    param([string]$Kind = 'telemetry')
    $out = New-Object System.Collections.Generic.List[string]
    try { $lines = @(Get-Content -LiteralPath $script:HostsPath -ErrorAction Stop) } catch { return @() }
    $inside = $false; $mine = $false
    foreach ($l in $lines) {
        if ($l -match $script:HostsMarkRegex) {
            if (-not $inside) { $inside = $true; $mine = (Test-HostsMarkKind $l $Kind) } else { $inside = $false }
            continue
        }
        if ($inside -and $mine -and $l -match '^\s*(0\.0\.0\.0|::)\s+(\S+)\s*$') { $out.Add($Matches[1] + ' ' + $Matches[2]) }
    }
    return $out.ToArray()
}

# Блок стоит и в нём ровно нужный список. Раньше хватало самой метки, и
# домены, добавленные в новых версиях, до уже поставленного блока не доходили.
function Test-HostsBlockCurrent {
    param([string]$Kind = 'telemetry')
    if (-not (Test-HostsBlock -Kind $Kind)) { return $false }
    $have = @(Get-HostsBlockLines -Kind $Kind | Select-Object -Unique)
    $want = @(Get-HostsWanted -Kind $Kind | Select-Object -Unique)
    if ($have.Count -ne $want.Count) { return $false }
    $set = @{}
    foreach ($h in $have) { $set[$h] = $true }
    foreach ($w in $want) { if (-not $set.ContainsKey($w)) { return $false } }
    return $true
}

function Apply-Hosts {
    param([string]$Kind = 'telemetry')
    $wanted = @(Get-HostsWanted -Kind $Kind)
    $count = [int]($wanted.Count / 2)
    $present = Test-HostsBlock -Kind $Kind
    if ($present -and (Test-HostsBlockCurrent -Kind $Kind)) { Write-Log '   [-] блок уже присутствует'; return }
    if ($DryRun) {
        Write-Log $(if ($present) { "   [тест] блок будет обновлён до доменов: $count" } else { "   [тест] будет заблокировано доменов: $count" })
        return
    }
    try {
        if ($script:BackupDir -and (Test-Path -LiteralPath $script:BackupDir)) {
            $copy = Join-Path $script:BackupDir 'hosts.original'
            # копия нужна та, что была до программы, а не после первого блока
            if (-not (Test-Path -LiteralPath $copy)) { Copy-Item -LiteralPath $script:HostsPath -Destination $copy -Force -ErrorAction SilentlyContinue }
        }
        # устаревший блок переписывается целиком: так он не обрастает повторами
        if ($present) { Remove-HostsBlock -Kind $Kind -Quiet }
        $block = @('') + $(switch ($Kind) { 'gdid' { $script:HostsMarkGdidStart } 'lock' { $script:HostsMarkLockStart } default { $script:HostsMarkStart } })
        $block += $wanted
        $block += $(switch ($Kind) { 'gdid' { $script:HostsMarkGdidEnd } 'lock' { $script:HostsMarkLockEnd } default { $script:HostsMarkEnd } })
        # Сразу после записи антивирус ненадолго держит hosts открытым, и
        # второй блок подряд падал с «файл занят другим процессом».
        for ($try = 1; ; $try++) {
            try { Add-Content -LiteralPath $script:HostsPath -Value $block -Encoding ASCII -ErrorAction Stop; break }
            catch [System.IO.IOException] { if ($try -ge 5) { throw }; Start-Sleep -Milliseconds (400 * $try) }
        }
        ipconfig /flushdns | Out-Null
        if ($present) { Write-Log ("   [+] список доменов обновлён, теперь их: {0}" -f $count) }
        else { Write-Log ("   [+] заблокировано доменов: {0}" -f $count) }
        $script:Changes++
    } catch { Write-Log "   [!] не удалось изменить hosts: $($_.Exception.Message) (возможно, защищён антивирусом)"; $script:Failures++ }
}

# Kind = all убирает все блоки программы (общий откат); telemetry, gdid и
# lock — только блок своего вида, остальные остаются на месте.
function Remove-HostsBlock {
    param([string]$Kind = 'all', [switch]$Quiet)
    try {
        $lines = @(Get-Content -LiteralPath $script:HostsPath -ErrorAction Stop)
        $keep = New-Object System.Collections.Generic.List[string]
        $inside = $false; $found = 0
        foreach ($l in $lines) {
            if ($l -match $script:HostsMarkRegex) {
                if (-not $inside) {
                    if (-not (Test-HostsMarkKind $l $Kind)) { $keep.Add($l); continue }
                    $found++
                    # пустую строку перед блоком ставили мы сами
                    if ($keep.Count -gt 0 -and $keep[$keep.Count - 1] -eq '') { $keep.RemoveAt($keep.Count - 1) }
                    $inside = $true
                } else { $inside = $false }
                continue
            }
            # Внутри блока убираем только свои строки. Чужая строка значит, что
            # закрывающую метку кто-то стёр: дальше идёт уже не наше.
            if ($inside -and $l -notmatch '^\s*((0\.0\.0\.0|::)\s+\S+)?\s*$') { $inside = $false }
            if (-not $inside) { $keep.Add($l) }
        }
        if ($found -gt 0) {
            # Default, а не ASCII: чужие строки с нелатинскими буквами остаются как были
            Set-Content -LiteralPath $script:HostsPath -Value $keep.ToArray() -Encoding Default -Force -ErrorAction Stop
            ipconfig /flushdns | Out-Null
            if (-not $Quiet) { Write-Log '   [+] блок блокировки доменов удалён' }
        } elseif (-not $Quiet) { Write-Log '   [-] блока в hosts нет' }
    } catch { Write-Log "   [!] hosts: $($_.Exception.Message)" }
}

# --- брандмауэр ------------------------------------------------------------- #
function Get-FwRuleName { param([string]$Kind, [string]$Target) if ($Kind -eq 'svc') { return "Win11Privacy: служба $Target" } return ("Win11Privacy: " + (Split-Path $Target -Leaf)) }

function Test-FwRule {
    param([string]$Kind, [string]$Target)
    $r = Get-NetFirewallRule -DisplayName (Get-FwRuleName $Kind $Target) -ErrorAction SilentlyContinue
    return [bool]($r -and $r.Enabled -eq 'True')
}

function Apply-FwRule {
    param([string]$Kind, [string]$Target, [string]$Comment)
    if ($DryRun) { Write-Log "   [тест] $Comment"; return }
    $name = Get-FwRuleName $Kind $Target
    try {
        if (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue) { Write-Log "   [-] $Comment -- уже есть"; return }
        if ($Kind -eq 'svc') {
            New-NetFirewallRule -DisplayName $name -Group $script:FwGroup -Direction Outbound -Action Block -Service $Target -Profile Any -Enabled True -ErrorAction Stop | Out-Null
        } else {
            New-NetFirewallRule -DisplayName $name -Group $script:FwGroup -Direction Outbound -Action Block -Program $Target -Profile Any -Enabled True -ErrorAction Stop | Out-Null
        }
        Write-Log "   [+] $Comment"; $script:Changes++
    } catch { Write-Log "   [!] не удалось: $Comment -- $($_.Exception.Message)"; $script:Failures++ }
}

# Адреса телеметрии: часть известна давно, часть узнаём разбором имён
# перед самой блокировкой — так список не устаревает.
$script:FwIpRuleName = 'Win11Privacy: адреса телеметрии'
$script:TelemetryIps = @(
    '13.64.90.137','13.68.31.193','13.68.82.8','13.69.109.130','13.69.239.72',
    '13.73.26.107','20.44.86.43','40.79.85.125','51.104.136.2',
    '65.52.100.7','65.52.100.9','65.52.100.11','65.55.252.43','65.55.252.63',
    '65.55.252.70','65.55.252.71','65.55.252.92','65.55.252.93',
    '66.119.144.157','168.61.24.141','168.61.146.25','168.62.187.13',
    '191.232.139.2','191.232.80.58','191.239.52.100'
)

# Имена спрашиваются все сразу, а не по одному. Части адресов из списка давно
# нет, и на каждый такой запрос Windows ждёт ответа DNS: за VPN или при
# молчащем DNS роутера — по 10–15 секунд. По очереди шаг тянулся минутами без
# единой строки в журнале и выглядел зависшим. Кто не ответил за отведённое
# время, в правило не попадёт — известные адреса выше в нём есть всегда.
# Имена спрашиваются у DNS-сервера В ОБХОД hosts. Раньше разрешение шло через
# системный резолвер, а он сначала смотрит в hosts: при стоящем блоке каждое
# имя «разрешалось» в 0.0.0.0, отсеивалось, и в правило попадали только
# зашитые адреса. Имена спрашиваются все сразу, в пуле потоков: по одному шаг
# тянулся минутами, пока мёртвые имена ждали ответа. Берутся и адреса IPv6.
function Get-TelemetryIpList {
    param([int]$TimeoutMs = 10000)
    $set = @{}
    foreach ($ip in $script:TelemetryIps) { $set[$ip] = $true }
    $names = @($script:HostsDomains | Select-Object -Unique)
    $pool = [runspacefactory]::CreateRunspacePool(1, 32)
    $pool.Open()
    $jobs = New-Object System.Collections.Generic.List[object]
    foreach ($nm in $names) {
        $parsed = $null
        if ([System.Net.IPAddress]::TryParse($nm, [ref]$parsed)) { if (Test-PublicIp $nm) { $set[$nm] = $true }; continue }
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        # -DnsOnly: мёртвое имя не уходит искать себя по локальной сети (LLMNR, NetBIOS)
        $null = $ps.AddScript('param($n) @(Resolve-DnsName -Name $n -Type A_AAAA -NoHostsFile -DnsOnly -QuickTimeout -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress } | ForEach-Object { [string]$_.IPAddress })').AddArgument($nm)
        $jobs.Add(@{ ps = $ps; h = $ps.BeginInvoke() })
    }
    $until = (Get-Date).AddMilliseconds($TimeoutMs)
    $answered = 0
    foreach ($j in $jobs) {
        $left = [int][math]::Max(0, ($until - (Get-Date)).TotalMilliseconds)
        if ($j.h.AsyncWaitHandle.WaitOne($left)) {
            try {
                $res = @($j.ps.EndInvoke($j.h))
                if ($res.Count -gt 0) { $answered++ }
                foreach ($a in $res) { if (Test-PublicIp "$a") { $set["$a"] = $true } }
            } catch { }
            $j.ps.Dispose()
        } else {
            # Не ответившее имя не ждём: синхронная остановка висела бы, пока
            # DNS не сдастся сам. Хвосты уйдут вместе с процессом движка.
            try { $null = $j.ps.BeginStop($null, $null) } catch { }
        }
    }
    try { $null = $pool.BeginClose($null, $null) } catch { }
    return @{ ips = @($set.Keys); answered = $answered; asked = $names.Count }
}

# Правило помнит дату обновления в описании. Адреса серверов меняются, и
# старше двух недель правило считается устаревшим — страж его обновит.
function Test-FwIpRule {
    param([switch]$Fresh)
    $r = Get-NetFirewallRule -DisplayName $script:FwIpRuleName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $r) { return $false }
    if (-not $Fresh) { return $true }
    if ("$($r.Description)" -match '(\d{4}-\d{2}-\d{2})') { try { return ([datetime]$Matches[1]) -gt (Get-Date).AddDays(-14) } catch { } }
    return $false
}

function Apply-FwIpBlock {
    if ($DryRun) { Write-Log '   [тест] будут заблокированы адреса сбора телеметрии'; return }
    try {
        Write-Log '   узнаю текущие адреса серверов сбора — не дольше 10 секунд'
        $found = Get-TelemetryIpList
        $ips = @($found.ips)
        Write-Log ("   ответили DNS имён: {0} из {1}" -f $found.answered, $found.asked)
        if ($ips.Count -eq 0) { Write-Log '   [-] адреса не определились'; return }
        Get-NetFirewallRule -DisplayName $script:FwIpRuleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName $script:FwIpRuleName -Group $script:FwGroup -Direction Outbound -Action Block `
            -RemoteAddress $ips -Profile Any -Enabled True -Description ('Win11Privacy: updated ' + (Get-Date).ToString('yyyy-MM-dd')) -ErrorAction Stop | Out-Null
        Write-Log ("   [+] заблокировано адресов: {0}" -f $ips.Count)
        Write-Log '   [-] если что-то перестанет работать — снимите этот пункт и нажмите «Откат»'
        $script:Changes++
    } catch { Write-Log "   [!] не удалось заблокировать адреса: $($_.Exception.Message)"; $script:Failures++ }
}

# Шифрованный DNS в системе и браузерах — через него hosts не работает
function Get-DohStatus {
    $win = $false
    try {
        $root = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters'
        foreach ($k in @(Get-ChildItem -LiteralPath $root -Recurse -ErrorAction SilentlyContinue)) {
            if ($k.PSChildName -match '^\d+\.' -or $k.PSPath -match 'DohInterfaceSettings') {
                $v = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).DohFlags
                if ($null -ne $v -and [int64]$v -ne 0) { $win = $true }
            }
        }
    } catch { }
    $policy = (Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'DoHPolicy')
    $edge = (Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DnsOverHttpsMode')
    $chrome = (Get-RegValue 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'DnsOverHttpsMode')
    return @{ windows = $win; policy = "$policy"; edge = "$edge"; chrome = "$chrome"
              blocked = ("$policy" -eq '1' -and "$edge" -eq 'off' -and "$chrome" -eq 'off') }
}

# --------------------------------------------------------------------------- #
#  Проверка утечек «в бою». Имя каждого сервера сбора разрешается так, как его
#  разрешит любая программа — с учётом hosts, — и к нему пробуется соединение
#  на порт 443. Данных не уходит: соединение сразу закрывается. Отвечает на
#  вопрос, которого не задаёт проверка настроек: дойдёт ли отправка на деле.
# --------------------------------------------------------------------------- #
function Invoke-LeakTest {
    param([int]$TimeoutMs = 8000)
    $names = @(@($script:HostsDomains) + @($script:GdidHosts) | Select-Object -Unique)
    # Имя, закрытое в hosts строками «0.0.0.0» и «::», Windows отдаёт как «нет
    # данных» — без этого списка оно попадало бы в «имя не отвечает».
    $sunk = @{}
    try {
        foreach ($l in @(Get-Content -LiteralPath $script:HostsPath -ErrorAction Stop)) {
            if ($l -match '^\s*(0\.0\.0\.0|::)\s+(\S+)') { $sunk[$Matches[2].ToLowerInvariant()] = $true }
        }
    } catch { }
    $w = 0; $io = 0
    [System.Threading.ThreadPool]::GetMinThreads([ref]$w, [ref]$io)
    if ($w -lt 64) { $null = [System.Threading.ThreadPool]::SetMinThreads(64, $io) }
    $dns = @{}
    $dnsTasks = New-Object System.Collections.Generic.List[System.Threading.Tasks.Task]
    foreach ($nm in $names) { try { $t = [System.Net.Dns]::GetHostAddressesAsync($nm); $dns[$nm] = $t; $dnsTasks.Add($t) } catch { } }
    # WaitAll бросает, если какое-то имя не существует, — это не ошибка
    if ($dnsTasks.Count -gt 0) { try { $null = [System.Threading.Tasks.Task]::WaitAll($dnsTasks.ToArray(), $TimeoutMs) } catch { } }

    $items = New-Object System.Collections.Generic.List[object]
    $conn = @{}
    $connTasks = New-Object System.Collections.Generic.List[System.Threading.Tasks.Task]
    foreach ($nm in $names) {
        $t = $dns[$nm]; $state = 'none'; $ip = ''
        if ($sunk.ContainsKey($nm.ToLowerInvariant())) { $state = 'hosts' }
        elseif ($t -and $t.Status -eq 'RanToCompletion') {
            $addrs = @($t.Result)
            $pub = @($addrs | Where-Object { Test-PublicIp $_.IPAddressToString })
            if ($addrs.Count -gt 0 -and $pub.Count -eq 0) { $state = 'hosts' }
            elseif ($pub.Count -gt 0) {
                $a = @($pub | Where-Object { "$($_.AddressFamily)" -eq 'InterNetwork' } | Select-Object -First 1)
                $a = $(if ($a.Count -gt 0) { $a[0] } else { $pub[0] })
                $ip = $a.IPAddressToString
                try {
                    $cl = New-Object System.Net.Sockets.TcpClient($a.AddressFamily)
                    $ct = $cl.ConnectAsync($a, 443)
                    $conn[$nm] = @{ client = $cl; task = $ct }; $connTasks.Add($ct)
                    $state = 'pending'
                } catch { $state = 'blocked' }
            }
        }
        $items.Add(@{ name = $nm; state = $state; ip = $ip })
    }
    if ($connTasks.Count -gt 0) { try { $null = [System.Threading.Tasks.Task]::WaitAll($connTasks.ToArray(), 4000) } catch { } }
    foreach ($it in $items) {
        if ($it.state -ne 'pending') { continue }
        $cn = $conn[$it.name]
        $it.state = $(if ("$($cn.task.Status)" -eq 'RanToCompletion' -and $cn.client.Connected) { 'open' } else { 'blocked' })
        try { $cn.client.Close() } catch { }
    }
    $count = { param($s) @($items | Where-Object { $_.state -eq $s }).Count }
    return @{ time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); total = $items.Count
              open = (& $count 'open'); blocked = (& $count 'blocked'); hosts = (& $count 'hosts'); none = (& $count 'none')
              doh = (Get-DohStatus); items = $items.ToArray() }
}

function Remove-FwRules {
    try {
        $rules = @(Get-NetFirewallRule -Group $script:FwGroup -ErrorAction SilentlyContinue)
        if ($rules.Count -gt 0) { $rules | Remove-NetFirewallRule -ErrorAction SilentlyContinue; Write-Log "   [+] удалено правил брандмауэра: $($rules.Count)" }
        else { Write-Log '   [-] правил брандмауэра нет' }
    } catch { Write-Log "   [!] брандмауэр: $($_.Exception.Message)" }
}

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

function Get-SvcStart {
    param([string]$Name)
    $v = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" 'Start'
    if ($null -eq $v) { return -1 }
    return [int]$v
}

# Где лежат копии номера. Только чтение.
function Get-GdidCopies {
    $found = New-Object System.Collections.Generic.List[object]
    $seenSystem = $false
    foreach ($r in $script:IdCrlRoots) {
        if (-not (Test-Path -LiteralPath $r.path)) { continue }
        # .DEFAULT и S-1-5-18 — один и тот же куст SYSTEM: считаем его один раз
        if ($r.who -eq 'system') { if ($seenSystem) { continue }; $seenSystem = $true }
        $lidVal = Get-RegValue "$($r.path)\ExtendedProperties" 'LID'
        if ("$lidVal") { $found.Add(@{ who = $r.who; place = 'lid'; puid = "$lidVal" }) }
        try {
            $pk = Get-Item -LiteralPath "$($r.path)\Immersive\production\Property" -ErrorAction Stop
            foreach ($vn in @($pk.GetValueNames())) {
                if ($vn -match $script:DevicePuidRegex) { $found.Add(@{ who = $r.who; place = 'property'; puid = $vn }) }
            }
        } catch { }
        foreach ($tk in @(Get-ChildItem -LiteralPath "$($r.path)\Immersive\production\Token" -ErrorAction SilentlyContinue)) {
            $tn = @($tk.GetValueNames())
            if ($tn -contains 'DeviceId' -or $tn -contains 'DeviceTicket') {
                $found.Add(@{ who = $r.who; place = 'token'; puid = "$(Get-RegValue $tk.PSPath 'DeviceId')" })
            }
        }
        foreach ($sk in @(Get-ChildItem -LiteralPath "$($r.path)\DeviceIdentities\production" -ErrorAction SilentlyContinue)) {
            if ($sk.PSChildName -eq 'Logs') { continue }
            foreach ($ik in @(Get-ChildItem -LiteralPath $sk.PSPath -ErrorAction SilentlyContinue)) {
                $found.Add(@{ who = $(if ($sk.PSChildName -like 'S-1-5-21-*') { 'user' } else { 'system' })
                              place = 'identity'; puid = "$(Get-RegValue $ik.PSPath 'DeviceId')" })
            }
        }
    }
    foreach ($nk in @(Get-ChildItem -LiteralPath $script:IdCrlNegCache -ErrorAction SilentlyContinue)) {
        if ($nk.PSChildName -match '^(0018[0-9A-Fa-f]{12})_') { $found.Add(@{ who = 'system'; place = 'cache'; puid = $Matches[1] }) }
    }
    return $found.ToArray()
}

function Test-MsaLogon {
    try { return ("$((Get-LocalUser -Name $env:USERNAME -ErrorAction Stop).PrincipalSource)" -eq 'MicrosoftAccount') } catch { }
    # Модуля учётных записей нет — судим осторожно: есть учётная запись
    # Microsoft хоть где-то в профиле, значит, считаем, что вход через неё.
    return (@(Get-ChildItem 'HKCU:\SOFTWARE\Microsoft\IdentityCRL\UserExtendedProperties' -ErrorAction SilentlyContinue).Count -gt 0)
}

# Компьютер организации: там номер устройства связан с её учётной записью,
# и трогать его — сломать вход на работе. Встроенные «поставщики» Local, Deploy
# и Cloud Authority есть на любом домашнем компьютере — их не считаем.
function Get-ManagedReason {
    try { if ((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain) { return 'компьютер в домене организации' } } catch { }
    if (@(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo' -ErrorAction SilentlyContinue).Count -gt 0) { return 'компьютер подключён к Entra ID организации' }
    if (@(Get-ChildItem 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin\JoinInfo' -ErrorAction SilentlyContinue).Count -gt 0) { return 'в Windows добавлена рабочая или учебная учётная запись' }
    foreach ($ek in @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue)) {
        $prov = "$(Get-RegValue $ek.PSPath 'ProviderID')"
        if ($prov -and $prov -notin @('Local Authority', 'Deploy Authority', 'Cloud Authority') -and "$(Get-RegValue $ek.PSPath 'EnrollmentState')" -eq '1') {
            return 'компьютер под управлением организации (MDM)'
        }
    }
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

function Stop-ServiceWait {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -eq 'Stopped') { return $true }
    for ($i = 1; $i -le 3; $i++) {
        try { Stop-Service -Name $Name -Force -ErrorAction Stop; $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(10)); return $true }
        catch { Start-Sleep -Milliseconds (500 * $i) }
    }
    return $false
}

# Короткая задача планировщика: команда от имени пользователя без повышения
# или от имени SYSTEM. Учётные данные устройства лежат в хранилище каждого из
# них, а у повышенного сеанса своё пространство — отсюда их не видно.
function Invoke-OneShotTask {
    param([string]$TaskName, [string]$CmdLine, [switch]$AsSystem)
    try {
        $act = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\cmd.exe" -Argument ('/d /c ' + $CmdLine)
        $who = $(if ($AsSystem) { New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest }
                 else { New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited })
        $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
        Register-ScheduledTask -TaskName $TaskName -Action $act -Principal $who -Settings $set -Force -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        # 267011 — ещё не запускалась, 267009 — выполняется
        $until = (Get-Date).AddSeconds(30)
        do {
            Start-Sleep -Milliseconds 400
            $res = (Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue).LastTaskResult
        } while (($res -eq 267009 -or $res -eq 267011) -and (Get-Date) -lt $until)
        return $true
    } catch { return $false }
    finally { try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue } catch { } }
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
    try {
        if ($Enabled) { Enable-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop | Out-Null }
        else { Disable-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop | Out-Null }
        return 'ok'
    } catch { }
    $flag = $(if ($Enabled) { '/enable' } else { '/disable' })
    $null = Invoke-OneShotTask -TaskName 'Win11Privacy Task' -CmdLine ('schtasks.exe /change /tn "{0}" {1}' -f $Full, $flag) -AsSystem
    $t = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction SilentlyContinue
    if ($t -and (($t.State -eq 'Disabled') -ne $Enabled)) { return 'system' }
    return 'fail'
}

# Стирает «личность» устройства и все известные копии номера. Пока сервер
# выдачи открыт, Windows при следующем обращении получит новый номер — это
# смена. Под запретом выдачи — номера не станет вовсе.
function Invoke-GdidWipe {
    $why = Get-ManagedReason
    if ($why) {
        Write-Log ("   [!] номер устройства не тронут: {0}. На таком компьютере он связан с учётной записью организации." -f $why)
        $script:Failures++; return $false
    }
    $before = @(Get-GdidCopies)
    if ($DryRun) { Write-Log ("   [тест] копий номера устройства: {0} -- будут стёрты вместе с «личностью» устройства" -f $before.Count); return $true }
    Write-Log ("   найдено копий номера: {0}" -f $before.Count)

    # Службы держат номер в памяти и вернули бы его на место. wlidsvc на время
    # стирания ещё и запрещаем запускать: её поднимает любой запрос Магазина.
    $wasRunning = @(Get-Service -ErrorAction SilentlyContinue |
                    Where-Object { ($_.Name -in @('wlidsvc', 'CDPSvc') -or $_.Name -like 'CDPUserSvc_*') -and $_.Status -eq 'Running' } |
                    ForEach-Object { $_.Name })
    $wlidType = $null
    try { $wlidType = (Get-Service wlidsvc -ErrorAction Stop).StartType; Set-Service wlidsvc -StartupType Disabled -ErrorAction Stop } catch { $wlidType = $null }
    if (-not (Stop-ServiceWait 'wlidsvc')) {
        if ($null -ne $wlidType) { try { Set-Service wlidsvc -StartupType $wlidType -ErrorAction SilentlyContinue } catch { } }
        Write-Log '   [!] служба учётных записей Microsoft (wlidsvc) занята и не остановилась. Закройте Магазин и Параметры и повторите или перезагрузите компьютер. Ничего не стёрто.'
        $script:Failures++; return $false
    }
    foreach ($n in $wasRunning) { if ($n -ne 'wlidsvc') { $null = Stop-ServiceWait $n } }

    $fails = 0
    # 1. учётные данные «личности» устройства
    foreach ($t in $script:GdidCredUser) { $null = & cmdkey.exe "/delete:$t" 2>&1 }
    $userCmd = (@($script:GdidCredUser | ForEach-Object { 'cmdkey /delete:' + $_ }) -join ' & ')
    $sysCmd  = (@($script:GdidCredSystem | ForEach-Object { 'cmdkey /delete:' + $_ }) -join ' & ')
    if (Invoke-OneShotTask 'Win11Privacy GDID user' $userCmd) { Write-Log '   [+] учётные данные устройства у пользователя убраны' }
    else { Write-Log '   [!] учётные данные устройства у пользователя убрать не удалось'; $fails++ }
    if (Invoke-OneShotTask 'Win11Privacy GDID system' $sysCmd -AsSystem) { Write-Log '   [+] учётные данные устройства у системы убраны' }
    else { Write-Log '   [!] учётные данные устройства у системы убрать не удалось'; $fails++ }

    # 2. копии номера в реестре: сам номер, его метка, билеты приложений, личности
    foreach ($r in $script:IdCrlRoots) {
        if (-not (Test-Path -LiteralPath $r.path)) { continue }
        Remove-ItemProperty -LiteralPath "$($r.path)\ExtendedProperties" -Name 'LID' -Force -ErrorAction SilentlyContinue
        $pk = "$($r.path)\Immersive\production\Property"
        try {
            foreach ($vn in @((Get-Item -LiteralPath $pk -ErrorAction Stop).GetValueNames())) {
                if ($vn -match $script:DevicePuidRegex) { Remove-ItemProperty -LiteralPath $pk -Name $vn -Force -ErrorAction SilentlyContinue }
            }
        } catch { }
        foreach ($tk in @(Get-ChildItem -LiteralPath "$($r.path)\Immersive\production\Token" -ErrorAction SilentlyContinue)) {
            foreach ($vn in @('DeviceId', 'DeviceTicket')) { Remove-ItemProperty -LiteralPath $tk.PSPath -Name $vn -Force -ErrorAction SilentlyContinue }
        }
        $ids = "$($r.path)\DeviceIdentities\production"
        if (Test-Path -LiteralPath $ids) { Remove-Item -LiteralPath $ids -Recurse -Force -ErrorAction SilentlyContinue }
    }
    foreach ($nk in @(Get-ChildItem -LiteralPath $script:IdCrlNegCache -ErrorAction SilentlyContinue)) {
        if ($nk.PSChildName -match '^0018[0-9A-Fa-f]{12}_') { Remove-Item -LiteralPath $nk.PSPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
    # 3. кэш платформы подключённых устройств: в нём регистрация в каталоге
    $null = Clear-FolderContents (Join-Path $env:LOCALAPPDATA 'ConnectedDevicesPlatform') 'кэш платформы подключённых устройств'

    # 4. службы — как были
    if ($null -ne $wlidType) {
        try { Set-Service wlidsvc -StartupType $wlidType -ErrorAction Stop }
        catch { Write-Log '   [!] тип запуска службы wlidsvc вернуть не удалось'; $fails++ }
    }
    foreach ($n in $wasRunning) { try { Start-Service -Name $n -ErrorAction Stop } catch { } }

    $after = @(Get-GdidCopies)
    if ($after.Count -eq 0) { Write-Log '   [+] номер устройства стёрт отовсюду, где Windows его хранит'; $script:Changes++ }
    else { Write-Log ("   [!] осталось копий номера: {0} -- Windows их не отдала" -f $after.Count); $script:Failures++ }
    return ($after.Count -eq 0 -and $fails -eq 0)
}

# Состояние для вкладки «Номер устройства». Только чтение.
function Get-GdidStatus {
    $copies = @(Get-GdidCopies)
    $userLid = Get-RegValue 'HKCU:\SOFTWARE\Microsoft\IdentityCRL\ExtendedProperties' 'LID'
    $svcs = @()
    foreach ($n in @('CDPSvc', 'CDPUserSvc', 'DoSvc', 'wlidsvc')) {
        $run = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { ($_.Name -eq $n -or $_.Name -like ($n + '_*')) -and $_.Status -eq 'Running' }).Count -gt 0
        $svcs += @{ name = $n; start = (Get-SvcStart $n); running = $run }
    }
    $nums = @($copies | ForEach-Object { "$($_.puid)" } | Where-Object { $_ -match $script:DevicePuidRegex } | Select-Object -Unique)
    return @{
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        gdid = (ConvertTo-Gdid "$userLid")
        copies = $copies.Count; numbers = $nums.Count
        userCopies = @($copies | Where-Object { $_.who -eq 'user' }).Count
        systemCopies = @($copies | Where-Object { $_.who -eq 'system' }).Count
        transmitOff = ((Get-SvcStart 'CDPSvc') -eq 4 -and (Get-SvcStart 'DoSvc') -eq 4)
        ddsBlocked = (Test-HostsBlock -Kind 'gdid')
        locked = (Test-HostsBlock -Kind 'lock'); wlidBlocked = (Test-FwRule 'svc' 'wlidsvc')
        msaLogon = (Test-MsaLogon); managed = (Get-ManagedReason)
        admin = (Test-Admin)
        services = $svcs
    }
}

# --- аудит соединений (монитор) -------------------------------------------- #
# Монитор считается включённым, когда журнал пишет и разрешённые соединения
# (5156), и отклонённые (5157). Раньше включались только отказы, и список «кто
# отправляет», который строится по разрешённым, в живой системе был пуст.
function Get-MonitorEnabled {
    try {
        $out = & auditpol.exe /get /subcategory:$script:AuditGuid /r 2>$null
        $csv = $out | Where-Object { $_ -and $_ -notmatch '^Machine Name' -and $_ -notmatch '^Имя компьютера' } | Select-Object -Last 1
        if (-not $csv) { return $false }
        return (($csv -match 'Success|Успех|Успешн') -and ($csv -match 'Failure|Отказ|Сбой'))
    } catch { return $false }
}

# Журнал безопасности по умолчанию — 20 МБ: с записью всех соединений он
# переписывал бы себя за часы. Под монитор он растёт до 128 МБ — через журнал
# изменений, чтобы откат вернул прежний размер.
$script:SecurityLogKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Security'
$script:SecurityLogMin = 134217728

function Set-MonitorEnabled {
    param([bool]$On)
    $flag = if ($On) { 'enable' } else { 'disable' }
    try {
        $null = & auditpol.exe /set /subcategory:$script:AuditGuid /success:$flag /failure:$flag 2>&1
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

function Get-NetAppsSince {
    param([datetime]$Since, [int]$Max = 20000)
    $apps = @{}
    $events = @()
    try { $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 5156; StartTime = $Since } -MaxEvents $Max -ErrorAction Stop) } catch { }
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
    Save-Json 'net-apps.json' @{ known = @($known.Keys); recent = $recent.ToArray(); learnUntil = $learnUntil.ToString('s'); last = $now.ToString('s') }
    if ($fresh.Count -gt 0 -and -not $Quiet) {
        $msg = (@($fresh | Select-Object -First 3 | ForEach-Object { $_.name }) -join ', ')
        if ($fresh.Count -gt 3) { $msg += (' и ещё ' + ($fresh.Count - 3)) }
        Show-Toast 'Новая программа вышла в сеть' ($msg + '. Запретить ей выход — на странице «Монитор».')
    }
    return $fresh
}

function Test-PublicIp {
    param([string]$Ip)
    if (-not $Ip) { return $false }
    if ($Ip -match '^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|22[4-9]\.|23\d\.|255\.|0\.)') { return $false }
    if ($Ip -match '^(fe80|ff0|::1|fc|fd)') { return $false }
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
    try { $events = @(Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=@(5156, 5157); StartTime=$since } -MaxEvents 8000 -ErrorAction Stop) } catch { }
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

function Purge-Buffer {
    Write-Section 'Неотправленная телеметрия'
    $info = Get-BufferInfo
    if ($info.mb -eq 0 -and $info.files -eq 0) { Write-Log '   [-] буфер пуст'; return }
    if ($DryRun) { Write-Log ("   [тест] будет стёрто ~{0} МБ ({1} файлов)" -f $info.mb, $info.files); return }
    $svc = Get-Service -Name DiagTrack -ErrorAction SilentlyContinue
    $wasRunning = ($svc -and $svc.Status -eq 'Running')
    if ($wasRunning) { Stop-Service -Name DiagTrack -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 800 }
    try {
        $null = & takeown.exe /F "$script:DiagDir" /R /A /D Y 2>&1
        $null = & icacls.exe "$script:DiagDir" /grant '*S-1-5-32-544:(OI)(CI)F' /T /C /Q 2>&1
    } catch { }
    $deleted = 0; $bytes = 0
    foreach ($f in @(Get-BufferFiles)) {
        try { $len = $f.Length; Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $deleted++; $bytes += $len } catch { }
    }
    if ($wasRunning -and $svc.StartType -ne 'Disabled') { Start-Service -Name DiagTrack -ErrorAction SilentlyContinue }
    if ($deleted -gt 0) { Write-Log ("   [+] стёрто файлов: {0}, {1} МБ" -f $deleted, [math]::Round($bytes / 1MB, 2)); $script:Changes++ }
    else { Write-Log '   [!] не удалось удалить файлы буфера (доступ запрещён)'; $script:Failures++ }
}

# =========================================================================== #
#  Detect
# =========================================================================== #
if ($Detect) {
    $ed = Get-Edition
    $os = Get-CimInstance Win32_OperatingSystem
    $apps = Detect-Apps
    $oem = Detect-Oem
    $guardTask = Get-ScheduledTask -TaskName $script:GuardTask -ErrorAction SilentlyContinue
    $guardLast = Load-Json 'guard-last.json'
    $guardProfile = Load-Json 'profile.json'
    $result = @{
        os = $os.Caption; build = [System.Environment]::OSVersion.Version.Build; edition = $ed.id; editionKind = $ed.kind
        admin = (Test-Admin); user = $env:USERNAME
        engineVersion = $script:EngineVersion; languageMode = $script:LangMode
        apps = $apps; oem = $oem
        guardInstalled = [bool]$guardTask
        watcherInstalled = [bool](Get-ScheduledTask -TaskName 'Win11Privacy Watcher' -ErrorAction SilentlyContinue)
        sensorGuardInstalled = [bool](Get-ScheduledTask -TaskName $script:SensorTask -ErrorAction SilentlyContinue)
        netGuardInstalled = [bool](Get-ScheduledTask -TaskName $script:NetTask -ErrorAction SilentlyContinue)
        guardLast = $guardLast
        guardModules = $(if ($guardProfile) { @($guardProfile.modules) } else { @() })
        monitorEnabled = (Get-MonitorEnabled)
        firewallRules = @(Get-NetFirewallRule -Group $script:FwGroup -ErrorAction SilentlyContinue).Count
        hostsBlocked = (Test-HostsBlock)
        buffer = (Get-BufferInfo)
        diagTrack = $(try { [string](Get-Service DiagTrack -ErrorAction Stop).StartType } catch { 'нет' })
    }
    Emit-Json $result
    exit 0
}

# =========================================================================== #
#  Monitor
# =========================================================================== #
if ($Monitor) {
    if (-not (Test-Admin)) { Emit-Json @{ error='нужны права администратора' }; exit 1 }
    Emit-Json (Get-MonitorStats -Hours $MonitorHours)
    exit 0
}

# --------------------------------------------------------------------------- #
#  Запрет выхода в сеть отдельной программе. Видно, кто стучится, — и тут же
#  можно закрыть ему выход. Правило попадает в группу Win11Privacy, поэтому
#  общий откат снимает его вместе с остальными.
# --------------------------------------------------------------------------- #
if ($BlockApp -or $UnblockApp) {
    if (-not (Test-Admin)) { Emit-Json @{ error='нужны права администратора' }; Write-Log '###DONE###'; exit 1 }
    if (-not $AppPath) { Emit-Json @{ error='не указана программа' }; Write-Log '###DONE###'; exit 1 }
    Write-Section $(if ($BlockApp) { 'Запрет выхода в сеть' } else { 'Возврат доступа в сеть' })
    $leaf = Split-Path $AppPath -Leaf
    if ($BlockApp) {
        if (-not (Test-Path -LiteralPath $AppPath)) { Write-Log ("   [!] файл не найден: {0}" -f $AppPath) }
        Apply-FwRule 'app' $AppPath ("выход в сеть запрещён: " + $leaf)
    } else {
        $rule = Get-FwRuleName 'app' $AppPath
        try {
            Remove-NetFirewallRule -DisplayName $rule -ErrorAction Stop
            Write-Log ("   [+] выход в сеть разрешён обратно: {0}" -f $leaf); $script:Changes++
        } catch { Write-Log ("   [-] запрета и не было: {0}" -f $leaf) }
    }
    Emit-Json @{ path = $AppPath; blocked = (Test-FwRule 'app' $AppPath) }
    Write-Log '###DONE###'
    exit 0
}

if ($EnableMonitor) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Монитор утечек'
    foreach ($d in $script:Defs) { if ($d.M -eq 'firewall') { Apply-Def $d } }
    $ok = Set-MonitorEnabled $true
    Write-Log 'Перехваченные попытки отправки теперь считаются. Статистика — на странице «Монитор».'
    Write-Log '###DONE###'
    exit $(if ($ok) { 0 } else { 1 })
}

if ($DisableMonitor) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Монитор утечек'
    $ok = Set-MonitorEnabled $false
    Write-Log 'Правила брандмауэра оставлены (они — часть модуля «Брандмауэр»); удалить их можно через «Откат».'
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  Guard (страж)
# =========================================================================== #
function Show-Toast {
    param([string]$Title, [string]$Message)
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        $t = [System.Security.SecurityElement]::Escape($Title); $m = [System.Security.SecurityElement]::Escape($Message)
        $xml = "<toast><visual><binding template='ToastGeneric'><text>$t</text><text>$m</text></binding></visual></toast>"
        $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $doc.LoadXml($xml)
        $toast = New-Object Windows.UI.Notifications.ToastNotification $doc
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
    } catch { }
}

function Get-RecentHotfixes {
    param([datetime]$Since)
    $list = @()
    try {
        foreach ($h in (Get-HotFix -ErrorAction SilentlyContinue)) {
            if ($h.InstalledOn -and $h.InstalledOn -ge $Since.Date) { $list += [string]$h.HotFixID }
        }
    } catch { }
    return @($list | Select-Object -Unique)
}

# =========================================================================== #
#  АВТОЗАГРУЗКА
#  Что стартует вместе с Windows: обновляторы, агенты телеметрии, помощники
#  производителя. Отключение делается ровно так же, как в диспетчере задач —
#  отметкой в StartupApproved, а не удалением записи: включить обратно можно
#  одной кнопкой, и Windows после обновления ничего не «чинит» обратно.
# =========================================================================== #
$script:StartupRuns = @(
    @{ id = 'HKLM'
       run = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
       ok  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
       scope = 'реестр, все пользователи' },
    @{ id = 'HKLM32'
       run = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run'
       ok  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
       scope = 'реестр, все пользователи' },
    @{ id = 'HKCU'
       run = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
       ok  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
       scope = 'реестр, этот пользователь' },
    @{ id = 'HKCU32'
       run = 'HKCU:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run'
       ok  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
       scope = 'реестр, этот пользователь' }
)
$script:StartupFolders = @(
    @{ id = 'user';   folder = [Environment]::GetFolderPath('Startup')
       ok = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
       scope = 'папка автозагрузки, этот пользователь' },
    @{ id = 'common'; folder = [Environment]::GetFolderPath('CommonStartup')
       ok = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
       scope = 'папка автозагрузки, все пользователи' }
)

# Кого узнаём в лицо: зачем эта запись здесь и стоит ли её гасить.
$script:StartupKnown = @(
    @{ re = 'googleupdate|google update|gupdate|chromeautolaunch'; note = 'обновлятор Google: работает постоянно и шлёт статистику' },
    @{ re = 'edgeupdate|microsoftedgeautolaunch|msedgeautolaunch';  note = 'автозапуск и обновлятор Edge' },
    @{ re = 'adobeaamupdater|adobegcinvoker|adobe arm|acrotray|creative cloud'; note = 'служба обновлений Adobe' },
    @{ re = 'nvbackend|nvidia (web helper|geforce)|nvtmmon|nvnodelauncher'; note = 'спутник драйвера NVIDIA: телеметрия и вход в аккаунт' },
    @{ re = 'onedrive'; note = 'OneDrive: синхронизация в облако' },
    @{ re = 'teams|skype'; note = 'мессенджер Microsoft: висит в фоне ради уведомлений' },
    @{ re = 'spotify|steam|epicgames|discord|telegram|whatsapp|viber'; note = 'программа сама себя запускает при входе' },
    @{ re = 'dropbox|yandex\.?disk|mail\.?ru|cloud@mail|amigo|guard\.?mail'; note = 'облако или спутник, который стартует без спроса' },
    @{ re = 'jusched|java update|itunes|applesyncnotifier|quicktime|bonjour'; note = 'проверка обновлений в фоне' },
    @{ re = 'ccleaner|driver ?booster|advanced ?systemcare|iobit|wondershare|reimage'; note = 'фоновый «оптимизатор» с рекламой платной версии' },
    @{ re = 'honor|huawei|pcmanager|lenovo|vantage|hpnotifications|hp support|dellsupport|asus|armoury|acer ?care|msi ?center'; note = 'программа производителя: собирает сведения о ноутбуке' },
    @{ re = 'teamviewer|anydesk|rustdesk|radmin'; note = 'удалённый доступ: ждёт подключения при каждом входе' },
    @{ re = 'utorrent|bittorrent|qbittorrent'; note = 'торрент-клиент стартует вместе с Windows' },
    @{ re = 'cortana|copilot|widgets'; note = 'помощник Microsoft' }
)
# Эти лучше не гасить: тачпад, звук, хоткеи и защита. Пометим и не предложим.
$script:StartupKeepRe = 'securityhealth|windowsdefender|msmpeng|syntpenh|etdctrl|elan|touchpad|hotkey|hcontrol|atkosd|onekey|smartaudio|rtkaud|rthdvcpl|realtek|waves|nahimic|igfxtray|hkcmd|iastoricon|dptf|synaptics|logi(options|tune)|kbd'

# Опознавательный код записи. Имена значений в Run бывают с пробелами и
# запятыми, поэтому в командную строку идёт base64 — но без «+», «/» и «-»,
# чтобы PowerShell не принял код за имя параметра.
function ConvertTo-StartupId {
    param([string]$Raw)
    $b = [Text.Encoding]::UTF8.GetBytes($Raw)
    return ([Convert]::ToBase64String($b)).Replace('+', '.').Replace('/', '_').TrimEnd('=')
}
function ConvertFrom-StartupId {
    param([string]$Id)
    $s = ([string]$Id).Replace('.', '+').Replace('_', '/')
    while (($s.Length % 4) -ne 0) { $s += '=' }
    try { return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s)) } catch { return '' }
}

# В StartupApproved первый байт: чётный — запись работает, нечётный — погашена.
function Test-StartupApproved {
    param([string]$Key, [string]$Name)
    $v = Get-RegValue $Key $Name
    if ($null -eq $v) { return $true }
    try {
        $bytes = [byte[]]$v
        if ($bytes.Length -lt 1) { return $true }
        return (($bytes[0] -band 1) -eq 0)
    } catch { return $true }
}

function Set-StartupApproved {
    param([string]$Key, [string]$Name, [bool]$Enabled)
    $bytes = New-Object byte[] 12
    if ($Enabled) { $bytes[0] = 2 }
    else {
        $bytes[0] = 3
        $ft = [BitConverter]::GetBytes((Get-Date).ToFileTime())
        [Array]::Copy($ft, 0, $bytes, 4, 8)
    }
    if (-not (Test-Path -LiteralPath $Key)) { New-Item -Path $Key -Force -ErrorAction Stop | Out-Null }
    New-ItemProperty -LiteralPath $Key -Name $Name -Value $bytes -PropertyType Binary -Force -ErrorAction Stop | Out-Null
}

function Get-StartupExe {
    param([string]$Cmd)
    if (-not $Cmd) { return '' }
    $c = ([string]$Cmd).Trim()
    if ($c.StartsWith('"')) {
        $i = $c.IndexOf('"', 1)
        if ($i -gt 1) { return $c.Substring(1, $i - 1) }
        return $c.Trim('"')
    }
    $m = [regex]::Match($c, '^(.+?\.(exe|com|bat|cmd|scr))(\s|$)', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    $sp = $c.IndexOf(' ')
    if ($sp -gt 0) { return $c.Substring(0, $sp) }
    return $c
}

function Get-StartupPublisher {
    param([string]$Exe)
    if (-not $Exe) { return '' }
    try {
        $p = [Environment]::ExpandEnvironmentVariables($Exe)
        if (-not (Test-Path -LiteralPath $p)) { return '' }
        $vi = [Diagnostics.FileVersionInfo]::GetVersionInfo($p)
        $c = [string]$vi.CompanyName
        return $c.Trim()
    } catch { return '' }
}

function Get-StartupNote {
    param([string]$Name, [string]$Cmd)
    $hay = ("$Name $Cmd").ToLowerInvariant()
    foreach ($k in $script:StartupKnown) { if ($hay -match $k.re) { return $k.note } }
    return ''
}
function Test-StartupKeep {
    param([string]$Name, [string]$Cmd)
    return (("$Name $Cmd").ToLowerInvariant() -match $script:StartupKeepRe)
}

function New-StartupItem {
    param([string]$Raw, [string]$Name, [string]$Cmd, [string]$Scope, [string]$Kind, [bool]$Enabled)
    $exe  = Get-StartupExe $Cmd
    $note = Get-StartupNote $Name $Cmd
    $keep = Test-StartupKeep $Name $Cmd
    return @{
        id        = (ConvertTo-StartupId $Raw)
        name      = $Name
        cmd       = $Cmd
        exe       = $exe
        source    = $Scope
        kind      = $Kind
        enabled   = [bool]$Enabled
        publisher = (Get-StartupPublisher $exe)
        note      = $note
        keep      = [bool]$keep
        advise    = [bool]($note -and -not $keep)
    }
}

function Get-StartupList {
    $list = @()

    foreach ($src in $script:StartupRuns) {
        $props = $null
        try { $props = Get-ItemProperty -LiteralPath $src.run -ErrorAction Stop } catch { }
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -in @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) { continue }
            $cmd = [string]$p.Value
            if (-not $cmd) { continue }
            $on = Test-StartupApproved $src.ok $p.Name
            $list += (New-StartupItem ('run|' + $src.id + '|' + $p.Name) $p.Name $cmd $src.scope 'run' $on)
        }
    }

    foreach ($src in $script:StartupFolders) {
        if (-not $src.folder -or -not (Test-Path -LiteralPath $src.folder)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $src.folder -File -Force -ErrorAction SilentlyContinue)) {
            if ($f.Name -eq 'desktop.ini') { continue }
            $target = $f.FullName
            if ($f.Extension -eq '.lnk') {
                try {
                    $sh = New-Object -ComObject WScript.Shell
                    $lnk = $sh.CreateShortcut($f.FullName)
                    if ($lnk.TargetPath) { $target = [string]$lnk.TargetPath }
                } catch { }
            }
            $on = Test-StartupApproved $src.ok $f.Name
            $list += (New-StartupItem ('folder|' + $src.id + '|' + $f.Name) `
                       ([IO.Path]::GetFileNameWithoutExtension($f.Name)) $target $src.scope 'folder' $on)
        }
    }

    $tasks = @()
    try { $tasks = @(Get-ScheduledTask -ErrorAction Stop) } catch { }
    foreach ($t in $tasks) {
        $full = [string]$t.TaskPath + [string]$t.TaskName
        if ($full -like '\Microsoft\*') { continue }          # системные не показываем
        if ($t.TaskName -like 'Win11Privacy*') { continue }   # свои задачи тоже
        $atLogon = $false
        try {
            foreach ($g in @($t.Triggers)) {
                $cn = ''
                try { $cn = [string]$g.CimClass.CimClassName } catch { }
                if ($cn -eq 'MSFT_TaskLogonTrigger' -or $cn -eq 'MSFT_TaskBootTrigger') { $atLogon = $true }
            }
        } catch { }
        if (-not $atLogon) { continue }
        $cmd = ''
        try {
            foreach ($a in @($t.Actions)) { if ($a.Execute) { $cmd = [string]$a.Execute; break } }
        } catch { }
        $list += (New-StartupItem ('task|' + $full) ([string]$t.TaskName) $cmd 'планировщик задач, при входе' 'task' ($t.State -ne 'Disabled'))
    }

    return @($list | Sort-Object @{ Expression = { -[int][bool]$_.advise } }, @{ Expression = { $_.name } })
}

# Возвращает @{ ok = ...; error = ... } — включает или гасит одну запись.
function Set-StartupState {
    param([string]$Raw, [bool]$Enabled)
    $parts = ([string]$Raw) -split '\|', 3
    if ($parts.Count -lt 2) { return @{ ok = $false; error = 'непонятная запись' } }
    try {
        if ($parts[0] -eq 'run') {
            $src = $null
            foreach ($s in $script:StartupRuns) { if ($s.id -eq $parts[1]) { $src = $s } }
            if (-not $src) { return @{ ok = $false; error = 'неизвестный раздел реестра' } }
            if ($null -eq (Get-RegValue $src.run $parts[2])) { return @{ ok = $false; error = 'записи больше нет' } }
            Set-StartupApproved $src.ok $parts[2] $Enabled
            return @{ ok = $true }
        }
        if ($parts[0] -eq 'folder') {
            $src = $null
            foreach ($s in $script:StartupFolders) { if ($s.id -eq $parts[1]) { $src = $s } }
            if (-not $src) { return @{ ok = $false; error = 'неизвестная папка автозагрузки' } }
            Set-StartupApproved $src.ok $parts[2] $Enabled
            return @{ ok = $true }
        }
        if ($parts[0] -eq 'task') {
            $full = ($Raw.Substring(5))
            $sp = Split-TaskPath $full
            if ($Enabled) { Enable-ScheduledTask  -TaskPath $sp[0] -TaskName $sp[1] -ErrorAction Stop | Out-Null }
            else          { Disable-ScheduledTask -TaskPath $sp[0] -TaskName $sp[1] -ErrorAction Stop | Out-Null }
            return @{ ok = $true }
        }
        return @{ ok = $false; error = 'непонятный вид записи' }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

function Run-Guard {
    param([bool]$Verbose)
    $profile = Load-Json 'profile.json'
    if (-not $profile -or -not $profile.modules) { Write-Log 'Профиль стража не найден.'; return @{ error='нет профиля' } }
    $mods = @($profile.modules)
    # Запрет выдачи номера ставится со своей вкладки, а не со страницы
    # настроек: пока он стоит, страж следит и за ним.
    if ($mods -notcontains 'gdidlock' -and (Test-HostsBlock -Kind 'lock')) { $mods += 'gdidlock' }
    $skipped = @($(if ($profile.PSObject.Properties['skip']) { @($profile.skip) } else { @() }) | ForEach-Object { "$_" })
    $last = Load-Json 'guard-last.json'
    $lastTime = if ($last -and $last.time) { [datetime]$last.time } else { (Get-Date).AddDays(-30) }

    $drifted = @()
    foreach ($d in $script:Defs) {
        if ($mods -notcontains $d.M) { continue }
        if ($skipped -contains $d.Id) { continue }
        if ($d.T -in @('taskglob','svcopt')) { continue }
        $r = Check-Def $d
        if ($r.na) { continue }                      # чего нет на этой Windows — не сбито
        if (-not $r.ok) { $drifted += $r }
    }
    $driftModules = @($drifted | ForEach-Object { $_.module } | Select-Object -Unique)
    $fixed = 0
    # чинить, не имея куда записать «как было», страж не берётся
    if ($driftModules.Count -gt 0 -and -not (Test-JournalWritable)) {
        Write-Log '   [!] страж ничего не чинит: журнал отката не записывается'
        $driftModules = @()
    }
    if ($driftModules.Count -gt 0) {
        $script:Modules = $driftModules
        foreach ($m in $driftModules) {
            if ($m -in @('cleanup','startup','buffer','oem')) { continue }
            if ($m -eq 'gdidlock' -and (Get-GdidLockRefusal)) { continue }
            Write-Section ($script:ModuleTitles[$m])
            foreach ($d in $script:Defs) { if ($d.M -eq $m -and $skipped -notcontains $d.Id) { Apply-Def $d; $fixed++ } }
        }
    }
    $kbs = Get-RecentHotfixes -Since $lastTime
    $newStartup = @(Find-NewStartup)
    # Номер устройства: страж замечает, что Windows его сменила, и что номер
    # снова появился под запретом выдачи. Сам номер не хранится — только хеш.
    $gNow = ConvertTo-Gdid "$(Get-RegValue 'HKCU:\SOFTWARE\Microsoft\IdentityCRL\ExtendedProperties' 'LID')"
    $gHash = ''
    if ($gNow) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $gHash = (@($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($gNow)) | ForEach-Object { $_.ToString('x2') }) -join '')
        $sha.Dispose()
    }
    $gPrev = $(if ($last -and $last.PSObject.Properties['gdidHash']) { "$($last.gdidHash)" } else { $null })
    if ($driftModules -contains 'gdidlock') {
        Show-Toast 'Номер устройства появился снова' 'Под запретом выдачи Windows снова получила номер — страж его стёр. Проверьте, не снят ли блок в hosts.'
    } elseif ($gHash -and $gPrev -and $gPrev -ne $gHash) {
        Show-Toast 'Номер устройства сменился' 'Windows получила новый номер устройства. Подробности — на вкладке «Номер устройства».'
    }
    # дневной замер телеметрии для хронологии — если запись рентгена включена
    try {
        if ((Test-XrayModule) -and (Get-XrayViewingEnabled)) {
            $xs = Invoke-XrayScan -Hours 24 -Max 4000
            if ($xs -and -not $xs.error) {
                Save-XrayDay $xs
                Save-Json 'xray-last.json' @{ time = $xs.time; perDay = $xs.perDay; mbPerDay = $xs.mbPerDay }
            }
        }
    } catch { }
    $summary = @{
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); checked = $mods; drifted = @($drifted | ForEach-Object { $_.name })
        driftModules = @($driftModules | ForEach-Object { $script:ModuleTitles[$_] }); fixed = $fixed; hotfixes = $kbs
        newStartup = @($newStartup | ForEach-Object { $_.name }); gdidHash = $gHash
    }
    Save-Json 'guard-last.json' $summary
    $line = "{0}  проверено модулей: {1}, сбито: {2}, исправлено: {3}, обновления: {4}" -f $summary.time, $mods.Count, $drifted.Count, $fixed, ($kbs -join ' ')
    try { Ensure-DataDir; Add-Content -LiteralPath (Join-Path $script:DataDir 'guard.log') -Value $line -Encoding UTF8 } catch { }
    if ($drifted.Count -gt 0) {
        $kbText = if ($kbs.Count -gt 0) { " После обновлений: " + ($kbs -join ', ') + "." } else { '' }
        Show-Toast 'Страж приватности' ("Windows вернула настроек: {0}. Исправлено.{1}" -f $drifted.Count, $kbText)
    }
    if ($newStartup.Count -gt 0) {
        $names = @($newStartup | Select-Object -First 3 | ForEach-Object { $_.name })
        $msg = ($names -join ', ')
        if ($newStartup.Count -gt 3) { $msg += (' и ещё ' + ($newStartup.Count - 3)) }
        Show-Toast 'Новая программа в автозагрузке' $msg
        Write-Log ("   [!] новых записей автозагрузки: {0} -- {1}" -f $newStartup.Count, $msg)
    }
    Write-Log $line
    return $summary
}

# --------------------------------------------------------------------------- #
#  Кто прописался в автозагрузку с прошлой проверки. Первый вызов только
#  запоминает то, что уже есть, — иначе страж отрапортует обо всей системе.
# --------------------------------------------------------------------------- #
function Find-NewStartup {
    $fresh = @()
    try {
        $now = @(Get-StartupList)
        $saved = Load-Json 'startup-known.json'
        $first = ($null -eq $saved)
        $known = @{}
        if ($saved -and $saved.items) { foreach ($k in @($saved.items)) { $known["$k"] = $true } }
        foreach ($it in $now) {
            $key = [string]$it.id
            if ($known.ContainsKey($key)) { continue }
            $known[$key] = $true
            if (-not $first -and $it.enabled) { $fresh += @{ name = [string]$it.name; source = [string]$it.source } }
        }
        $keys = @($known.Keys)
        Save-Json 'startup-known.json' @{ items = $keys; updated = (Get-Date).ToString('s') }
    } catch { }
    return $fresh
}

if ($InstallGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Страж приватности'
    try {
        Ensure-DataDir
        $engineDst = Install-TaskEngine
        $mods = @($Modules | Where-Object { $_ -notin @('cleanup','startup','buffer') })
        # Снятые внутри модуля пункты страж тоже помнит: иначе он «чинил» бы
        # то, что человек оставил нарочно, — например, DoSvc ради Магазина.
        Save-Json 'profile.json' @{ version=1; modules=$mods; skip=@($SkipItems); created=(Get-Date).ToString('s') }
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $engineDst + '" -Guard' + $script:DataArg)
        $t1 = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $t1.Delay = 'PT3M'
        # по умолчанию раз в неделю; -GuardDaily — каждый день в то же время
        $t2 = if ($GuardDaily) { New-ScheduledTaskTrigger -Daily -At 12:00 }
              else { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 12:00 }
        # Настройки сбивает обновление, а расписание могло ждать до воскресенья.
        # Третий триггер — сама установка обновления: страж приходит следом.
        $triggers = @($t1, $t2)
        try {
            $t3 = New-CimInstance -CimClass (Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler) -ClientOnly
            $t3.Enabled = $true
            $t3.Delay = 'PT5M'
            $t3.Subscription = '<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name=''Microsoft-Windows-WindowsUpdateClient''] and (EventID=19 or EventID=43)]]</Select></Query></QueryList>'
            $triggers += $t3
        } catch { }
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $script:GuardTask -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log ("   [+] страж установлен: проверка через 3 минуты после входа в систему и {0}" -f $(if ($GuardDaily) { 'каждый день в 12:00' } else { 'по воскресеньям в 12:00' }))
        if ($triggers.Count -gt 2) { Write-Log '   [+] и через 5 минут после каждого установленного обновления Windows' }
        else { Write-Log '   [-] пробуждение после обновлений недоступно на этой системе' }
        Write-Log ("   [+] отслеживается модулей: {0}" -f $mods.Count)
        Write-Log ("   [+] журнал: {0}" -f (Join-Path $script:DataDir 'guard.log'))
    } catch { Write-Log "   [!] не удалось установить стража: $($_.Exception.Message)" }
    Write-Log '###DONE###'
    exit 0
}

if ($RemoveGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Страж приватности'
    try { Unregister-ScheduledTask -TaskName $script:GuardTask -Confirm:$false -ErrorAction Stop; Write-Log '   [+] задача стража удалена' } catch { Write-Log '   [-] задача стража не найдена' }
    Write-Log '###DONE###'
    exit 0
}


# =========================================================================== #
#  Purge buffer (отдельная команда)
# =========================================================================== #
if ($PurgeBuffer) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Purge-Buffer
    Emit-Json (Get-BufferInfo)
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  РЕНТГЕН ТЕЛЕМЕТРИИ
#  Читает реальные события диагностики, которые Windows собрала о компьютере,
#  через встроенный модуль Microsoft.DiagnosticDataViewer.
# =========================================================================== #
$script:XrayDbDir = Join-Path $env:ProgramData 'Microsoft\Diagnosis\EventTranscript'

# Правила расшифровки: имя события -> человеческая категория
$script:XrayRules = @(
    @{ rx = 'Inventory\.(Core|Application)|InventoryApplication|AppInv|InstalledApplication';
       cat = 'Список установленных программ'; what = 'Какие программы стоят на компьютере, их версии и издатели' },
    @{ rx = 'Census|SystemInfo|Hardware|Processor|Memory|Storage|Battery|Firmware|Bios|Chassis';
       cat = 'Инвентаризация железа'; what = 'Модель ноутбука, процессор, память, диски, серийные номера' },
    @{ rx = 'AppInteractivity|AppLaunch|AppUsage|Win32kTraceLogging|AppActivity|ProcessStart|FocusTime';
       cat = 'Какие программы ты запускал'; what = 'Что открывал, сколько времени провёл, как часто' },
    @{ rx = 'PnP|DeviceConfig|DeviceInventory|USB|Bluetooth|Peripheral|Driver';
       cat = 'Подключённые устройства'; what = 'Флешки, наушники, принтеры, мыши — что и когда подключал' },
    @{ rx = 'WER|Fault|AppCrash|Watson|Hang|Reliability|BugCheck|Crash';
       cat = 'Сбои и падения программ'; what = 'Какие программы падали, с какими ошибками, имена файлов' },
    @{ rx = 'Edge|Browser|WebView|Chromium|SmartScreen';
       cat = 'Браузер'; what = 'Активность в браузере, посещения, проверки сайтов' },
    @{ rx = 'Search|Cortana|Bing|Suggest';
       cat = 'Поиск'; what = 'Что искал в меню Пуск и как использовался поиск' },
    @{ rx = 'Store|AppXDeployment|Purchase|License|Xbox|Game';
       cat = 'Магазин, игры и лицензии'; what = 'Установки из магазина, покупки, игровая активность' },
    @{ rx = 'Defender|Antivirus|Antimalware|Security|Firewall|Tpm|SecureBoot';
       cat = 'Безопасность'; what = 'Состояние защиты, проверки, обнаружения' },
    @{ rx = 'Update|WindowsUpdate|SIH|WUFB|Servicing|Setup360|UpdateAgent|Delivery';
       cat = 'Обновления'; what = 'Установка обновлений, версии, ошибки установки' },
    @{ rx = 'Location|Geolocation|Position|Wifi.*Scan|Sensor';
       cat = 'Местоположение и датчики'; what = 'Где находится компьютер, окружающие сети' },
    @{ rx = 'Logon|Login|Account|AAD|MSA|Identity|User\.|Profile|Credential';
       cat = 'Учётная запись'; what = 'Входы в систему, привязка к учётной записи Microsoft' },
    @{ rx = 'Network|Dns|Tcp|Connectivity|Ndis|Wlan|Ethernet';
       cat = 'Сеть'; what = 'Сетевые подключения, качество связи' },
    @{ rx = 'Power|Sleep|Resume|Boot|Shutdown|Uptime|Kernel\.Process';
       cat = 'Питание и загрузка'; what = 'Когда включал и выключал, время работы' },
    @{ rx = 'Office|Word|Excel|Outlook|OneDrive|Teams';
       cat = 'Office и OneDrive'; what = 'Работа с документами и облаком' },
    @{ rx = 'Heartbeat|Diagtrack|Telemetry|Utc\.|SelfHost|OneSettings|Aria';
       cat = 'Служебное телеметрии'; what = 'Служебные события самой системы сбора данных' }
)

function Get-XrayCategory {
    param([string]$Name)
    foreach ($r in $script:XrayRules) { if ($Name -match $r.rx) { return $r } }
    return @{ cat = 'Прочее'; what = 'События, не попавшие в известные категории' }
}

function Test-XrayModule {
    if (Get-Command Get-DiagnosticData -ErrorAction SilentlyContinue) { return $true }
    Import-Module Microsoft.DiagnosticDataViewer -ErrorAction SilentlyContinue
    return [bool](Get-Command Get-DiagnosticData -ErrorAction SilentlyContinue)
}

function Get-XrayViewingEnabled {
    try {
        if (Get-Command Get-DiagnosticDataViewingSetting -ErrorAction SilentlyContinue) {
            $s = Get-DiagnosticDataViewingSetting
            if ($null -ne $s) {
                foreach ($p in @('DiagnosticDataViewingEnabled','Enabled','IsEnabled')) {
                    if ($s.PSObject.Properties.Name -contains $p) { return [bool]$s.$p }
                }
                return [bool]$s
            }
        }
    } catch { }
    $v = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\EventTranscript' 'EnableEventTranscript'
    return ($v -eq 1)
}

function Get-XrayDbInfo {
    $mb = 0; $found = $false
    try {
        $items = @(Get-ChildItem -LiteralPath $script:XrayDbDir -Force -ErrorAction Stop)
        if ($items.Count -gt 0) {
            $found = $true
            $sum = ($items | Measure-Object -Property Length -Sum).Sum
            if ($sum) { $mb = [math]::Round($sum / 1MB, 2) }
        }
    } catch { }
    return @{ exists = $found; mb = $mb; path = $script:XrayDbDir }
}

function Get-XrayStatusObject {
    return @{
        moduleAvailable = (Test-XrayModule)
        recording       = (Get-XrayViewingEnabled)
        db              = (Get-XrayDbInfo)
        baseline        = (Load-Json 'xray-baseline.json')
    }
}

# --- Основное сканирование ------------------------------------------------- #
# --------------------------------------------------------------------------- #
#  ЧТО ИМЕННО О ВАС УЗНАЛИ
#  Рентген уже читает настоящие события. Здесь их содержимое превращается в
#  человеческие факты: не «1420 событий инвентаризации», а «названия 47 ваших
#  программ, модель ноутбука, серийный номер диска». Правило, которое ничего
#  не нашло, просто не показывается — выдумывать нечего.
# --------------------------------------------------------------------------- #
$script:FactRules = @(
    @{ id = 'apps';    title = 'Названия установленных программ'
       what = 'Windows перечисляет, что у вас стоит: имя, издатель и версия каждой программы.'
       re = '"(?:ProgramName|AppName|PackageFullName|ProductName)"\s*:\s*"([^"]{2,90})"' },
    @{ id = 'files';   title = 'Имена запускавшихся файлов'
       what = 'В событиях видно, какие исполняемые файлы вы открывали.'
       re = '"(?:FileName|BinaryName|ImageName|ExeName)"\s*:\s*"([^"]{2,90})"' },
    @{ id = 'device';  title = 'Модель и производитель компьютера'
       what = 'Точная модель железа — по ней устройство узнаётся среди прочих.'
       re = '"(?:deviceMake|deviceModel|SystemManufacturer|SystemProductName|Model|Manufacturer)"\s*:\s*"([^"]{2,80})"' },
    @{ id = 'ids';     title = 'Идентификаторы, которыми вас метят'
       what = 'Постоянные номера устройства и учётной записи: по ним события связываются в один профиль.'
       # номер устройства в учётной записи (GDID) событие несёт полем device.id: «g:» и цифры
       re = '(?:"(?:localId|deviceId|machineId|userId|globalDeviceId|sqmId)"\s*:\s*"|"id"\s*:\s*"(?=g:\d{6}))([^"]{6,120})' },
    @{ id = 'serial';  title = 'Серийные номера железа'
       what = 'Серийный номер не меняется никогда — это самая надёжная метка устройства.'
       re = '"(?:SerialNumber|BaseBoardSerial|BiosSerial|DiskSerial)"\s*:\s*"([^"]{4,80})"' },
    @{ id = 'hw';      title = 'Начинка компьютера'
       what = 'Процессор, память, диски и видеокарта — подробная опись железа.'
       re = '"(?:ProcessorIdentifier|ProcessorManufacturer|TotalPhysicalRAM|PrimaryDiskType|GraphicsAdapter|CpuFamily)"\s*:\s*"?([^",]{2,80})"?' },
    @{ id = 'net';     title = 'Сетевые адреса и имена сетей'
       what = 'MAC-адрес и названия сетей говорят, где физически стоит компьютер.'
       re = '"(?:MacAddress|SSID|NetworkName|BSSID)"\s*:\s*"([^"]{4,80})"' },
    @{ id = 'user';    title = 'Учётная запись и язык'
       what = 'Имя пользователя, страна, часовой пояс и раскладка.'
       re = '"(?:UserName|AccountName|CountryRegion|TimeZone|Locale|UserLocale|KeyboardLayout)"\s*:\s*"([^"]{2,80})"' },
    @{ id = 'devices'; title = 'Подключённые устройства'
       what = 'Всё, что вы подключали: принтеры, флешки, наушники, телефоны.'
       re = '"(?:DeviceName|FriendlyName|DeviceInstanceId|ContainerId)"\s*:\s*"([^"]{4,90})"' },
    @{ id = 'errors';  title = 'Сбои программ с их именами'
       what = 'Имена упавших программ и модулей — заодно видно, чем вы пользуетесь.'
       re = '"(?:FaultingApplicationName|CrashingProcess|ExceptionModule)"\s*:\s*"([^"]{2,90})"' }
)

function Add-FactValue {
    param($Store, [string]$Id, [string]$Value)
    $v = $Value.Trim()
    if (-not $v) { return }
    if ($v -match '^[\{\[]') { return }               # GUID-ы и структуры пропускаем
    if ($v -match '^(?:0|1|true|false|null|unknown|n/a)$') { return }
    if (-not $Store.ContainsKey($Id)) { $Store[$Id] = @{} }
    if ($Store[$Id].Count -ge 400) { return }           # памяти ради
    if ($Store[$Id].ContainsKey($v)) { $Store[$Id][$v]++ } else { $Store[$Id][$v] = 1 }
}

function Invoke-XrayScan {
    param([int]$Hours, [int]$Max)

    if (-not (Test-XrayModule)) {
        return @{ error = 'Модуль Microsoft.DiagnosticDataViewer недоступен на этой системе.' }
    }
    if (-not (Get-XrayViewingEnabled)) {
        return @{ error = 'Запись диагностики выключена. Нажмите «Включить запись», подождите — и повторите.'; recording = $false }
    }

    $start = (Get-Date).AddHours(-$Hours)
    $events = @()
    try { $events = @(Get-DiagnosticData -StartTime $start -RecordCount $Max -ErrorAction Stop) }
    catch { return @{ error = ("Не удалось прочитать данные: " + $_.Exception.Message) } }

    if ($events.Count -eq 0) {
        return @{ error = 'Событий за выбранный период нет. Если запись включена только что — подождите час-другой.'; total = 0; recording = $true }
    }

    $cats = @{}
    $names = @{}
    $bytes = 0
    $ids = @{}
    $apps = @{}
    $samples = @{}
    $facts = @{}

    foreach ($ev in $events) {
        $n = [string]$ev.Name
        $p = [string]$ev.Payload
        $bytes += $p.Length

        $rule = Get-XrayCategory $n
        $c = $rule.cat
        if (-not $cats.ContainsKey($c)) { $cats[$c] = @{ count = 0; bytes = 0; what = $rule.what; names = @{} } }
        $cats[$c].count++
        $cats[$c].bytes += $p.Length
        if ($cats[$c].names.ContainsKey($n)) { $cats[$c].names[$n]++ } else { $cats[$c].names[$n] = 1 }

        if ($names.ContainsKey($n)) { $names[$n]++ } else { $names[$n] = 1 }

        if (-not $samples.ContainsKey($c) -and $p.Length -gt 40) {
            $txt = $p
            if ($txt.Length -gt 1800) { $txt = $txt.Substring(0, 1800) + ' …' }
            $samples[$c] = @{ name = $n; time = $ev.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'); payload = $txt }
        }

        # что именно о вас узнали — по тем же событиям
        foreach ($rule in $script:FactRules) {
            foreach ($m in [regex]::Matches($p, $rule.re)) { Add-FactValue $facts $rule.id $m.Groups[1].Value }
        }

        # идентификаторы, которыми помечены события
        foreach ($m in [regex]::Matches($p, '"(localId|deviceId|machineId|userId|sessionId|deviceClass|osVer|deviceMake|deviceModel)"\s*:\s*"([^"]{2,120})"')) {
            $k = $m.Groups[1].Value; $v = $m.Groups[2].Value
            if (-not $ids.ContainsKey($k)) { $ids[$k] = @{} }
            if (-not $ids[$k].ContainsKey($v)) { $ids[$k][$v] = 0 }
            $ids[$k][$v]++
        }
        # названия программ, попавшие в инвентаризацию
        if ($n -match 'Inventory|AppInv|AppInteractivity|AppLaunch') {
            foreach ($m in [regex]::Matches($p, '"(?:ProgramName|AppName|Name|PackageFullName|FileName)"\s*:\s*"([^"]{2,90})"')) {
                $v = $m.Groups[1].Value
                if ($v -match '^[\{\d]' ) { continue }
                if ($apps.ContainsKey($v)) { $apps[$v]++ } else { $apps[$v] = 1 }
            }
        }
    }

    $span = [math]::Max(0.05, $Hours)
    $perDay  = [math]::Round($events.Count * 24.0 / $span, 0)
    $mbTotal = $bytes / 1MB
    $mbDay   = [math]::Round($mbTotal * 24.0 / $span, 2)

    $catList = @()
    foreach ($k in ($cats.Keys | Sort-Object { -$cats[$_].count })) {
        $topNames = @($cats[$k].names.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 |
                      ForEach-Object { @{ name = $_.Key; count = $_.Value } })
        $catList += @{
            name = $k; count = $cats[$k].count
            mb = [math]::Round($cats[$k].bytes / 1MB, 3)
            what = $cats[$k].what
            share = [math]::Round(100.0 * $cats[$k].count / $events.Count, 1)
            topNames = $topNames
            sample = $(if ($samples.ContainsKey($k)) { $samples[$k] } else { $null })
        }
    }

    $idList = @()
    foreach ($k in $ids.Keys) {
        $vals = @($ids[$k].GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3 |
                  ForEach-Object { @{ value = $_.Key; count = $_.Value } })
        $idList += @{ key = $k; distinct = $ids[$k].Count; values = $vals }
    }

    $appList = @($apps.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 25 |
                 ForEach-Object { @{ name = $_.Key; count = $_.Value } })

    $factList = @()
    foreach ($rule in $script:FactRules) {
        if (-not $facts.ContainsKey($rule.id)) { continue }
        $vals = @($facts[$rule.id].GetEnumerator() | Sort-Object Value -Descending)
        if ($vals.Count -eq 0) { continue }
        $factList += @{
            id = $rule.id; title = $rule.title; what = $rule.what
            distinct = $vals.Count
            examples = @($vals | Select-Object -First 6 | ForEach-Object { [string]$_.Key })
        }
    }

    $result = @{
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); hours = $Hours; recording = $true
        total = $events.Count; distinctNames = $names.Count
        mb = [math]::Round($mbTotal, 2); perDay = $perDay; mbPerDay = $mbDay
        perYear = [math]::Round($perDay * 365, 0); mbPerYear = [math]::Round($mbDay * 365, 1)
        categories = $catList; identifiers = $idList; apps = $appList; facts = $factList
        topNames = @($names.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15 |
                     ForEach-Object { @{ name = $_.Key; count = $_.Value } })
        db = (Get-XrayDbInfo)
    }

    $base = Load-Json 'xray-baseline.json'
    if ($base -and $base.perDay) {
        $result.baselinePerDay = $base.perDay
        $result.baselineTime = $base.time
        $result.deltaPercent = $(if ([double]$base.perDay -gt 0) { [math]::Round(100.0 * (1.0 - ($perDay / [double]$base.perDay)), 1) } else { 0 })
    }
    return $result
}

if ($XrayStatus) { Emit-Json (Get-XrayStatusObject); exit 0 }

if ($XrayEnable) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Рентген: включение записи'
    if (-not (Test-XrayModule)) { Write-Log '   [!] модуль Microsoft.DiagnosticDataViewer недоступен' }
    else {
        try {
            Enable-DiagnosticDataViewing -ErrorAction Stop
            Write-Log '   [+] запись диагностики включена'
        } catch {
            Write-Log "   [!] $($_.Exception.Message)"
            Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\EventTranscript' 'EnableEventTranscript' 1 -Comment 'запись событий диагностики (резервный способ)'
        }
    }
    Write-Log ''
    Write-Log 'Windows теперь ведёт ЛОКАЛЬНУЮ копию своих диагностических событий,'
    Write-Log 'чтобы их можно было прочитать. Объём отправки при этом не растёт.'
    Write-Log 'Дайте системе поработать хотя бы час, затем нажмите «Сканировать».'
    Write-Log '###DONE###'
    exit 0
}

if ($XrayDisable) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Рентген: выключение записи'
    try { Disable-DiagnosticDataViewing -ErrorAction Stop; Write-Log '   [+] запись выключена' }
    catch { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\EventTranscript' 'EnableEventTranscript' 0 -Comment 'запись событий диагностики — выкл' }
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  ХРОНОЛОГИЯ ПРИВАТНОСТИ
#  Программа копит историю: сколько событий телеметрии уходило в день, кто
#  трогал датчики, что она сама меняла, что возвращал страж и когда приезжали
#  обновления Windows. Собранные на одной оси, эти ряды показывают то, чего не
#  видно в моменте: как система отыгрывает настройки назад после обновлений.
# =========================================================================== #
function Save-XrayDay {
    param($Scan)
    if (-not $Scan -or -not $Scan.perDay) { return }
    try {
        $hist = Load-Json 'xray-history.json'
        $days = @{}
        if ($hist -and $hist.days) {
            foreach ($d in @($hist.days)) { $days["$($d.date)"] = $d }
        }
        $today = (Get-Date).ToString('yyyy-MM-dd')
        $days[$today] = @{ date = $today; perDay = [int]$Scan.perDay; mbPerDay = "$($Scan.mbPerDay)" }
        $list = @($days.Values | Sort-Object { "$($_.date)" } | Select-Object -Last 400)
        Save-Json 'xray-history.json' @{ days = $list; updated = (Get-Date).ToString('s') }
    } catch { }
}

function Get-GuardDays {
    $byDay = @{}
    $log = Join-Path $script:DataDir 'guard.log'
    if (-not (Test-Path -LiteralPath $log)) { return $byDay }
    try {
        foreach ($line in @(Get-Content -LiteralPath $log -Encoding UTF8 -ErrorAction Stop)) {
            $m = [regex]::Match($line, '^(\d{4}-\d{2}-\d{2}).*?сбито:\s*(\d+).*?исправлено:\s*(\d+)')
            if (-not $m.Success) { continue }
            $ds = $m.Groups[1].Value
            if (-not $byDay.ContainsKey($ds)) { $byDay[$ds] = @{ drifted = 0; fixed = 0; checks = 0 } }
            $byDay[$ds].drifted += [int]$m.Groups[2].Value
            $byDay[$ds].fixed += [int]$m.Groups[3].Value
            $byDay[$ds].checks++
        }
    } catch { }
    return $byDay
}

function Get-Timeline {
    param([int]$Days = 30)
    if ($Days -lt 7) { $Days = 7 }
    if ($Days -gt 180) { $Days = 180 }

    # рентген по дням
    $xray = @{}
    $xh = Load-Json 'xray-history.json'
    if ($xh -and $xh.days) { foreach ($d in @($xh.days)) { $xray["$($d.date)"] = [int]$d.perDay } }

    # датчики по дням
    $sensors = @{}
    $hist = Load-Json 'sensor-history.json'
    if ($hist -and $hist.events) {
        foreach ($e in @($hist.events)) {
            $ds = "$($e.time)"
            if ($ds.Length -lt 10) { continue }
            $ds = $ds.Substring(0, 10)
            if (-not $sensors.ContainsKey($ds)) { $sensors[$ds] = 0 }
            $sensors[$ds]++
        }
    }

    # что меняла сама программа
    $changes = @{}
    $j = Load-Json 'changes.json'
    if ($j -and $j.items) {
        foreach ($e in @($j.items)) {
            $ds = "$($e.time)"
            if ($ds.Length -lt 10) { continue }
            $ds = $ds.Substring(0, 10)
            if (-not $changes.ContainsKey($ds)) { $changes[$ds] = 0 }
            $changes[$ds]++
        }
    }

    $guard = Get-GuardDays

    # обновления Windows
    $updates = @{}
    try {
        foreach ($h in @(Get-HotFix -ErrorAction SilentlyContinue)) {
            if (-not $h.InstalledOn) { continue }
            $ds = ([datetime]$h.InstalledOn).ToString('yyyy-MM-dd')
            if (-not $updates.ContainsKey($ds)) { $updates[$ds] = @() }
            $updates[$ds] += [string]$h.HotFixID
        }
    } catch { }

    $rows = @()
    $peak = 0
    for ($i = $Days - 1; $i -ge 0; $i--) {
        $d = (Get-Date).Date.AddDays(-$i)
        $ds = $d.ToString('yyyy-MM-dd')
        $ev = $(if ($xray.ContainsKey($ds)) { $xray[$ds] } else { 0 })
        if ($ev -gt $peak) { $peak = $ev }
        $g = $(if ($guard.ContainsKey($ds)) { $guard[$ds] } else { $null })
        $rows += @{
            date     = $ds
            label    = $d.ToString('dd.MM')
            events   = $ev
            sensors  = $(if ($sensors.ContainsKey($ds)) { $sensors[$ds] } else { 0 })
            changes  = $(if ($changes.ContainsKey($ds)) { $changes[$ds] } else { 0 })
            drifted  = $(if ($g) { [int]$g.drifted } else { 0 })
            fixed    = $(if ($g) { [int]$g.fixed } else { 0 })
            updates  = @($(if ($updates.ContainsKey($ds)) { $updates[$ds] } else { @() }))
        }
    }

    # что из этого стоит сказать словами
    $notes = @()
    for ($i = 1; $i -lt $rows.Count; $i++) {
        $prev = $rows[$i - 1]; $cur = $rows[$i]
        # ВАЖНО: словами это становится в интерфейсе — движок отдаёт числа,
        # иначе в английской версии заметки остались бы русскими
        if ($cur.updates.Count -gt 0) {
            $notes += @{ date = $cur.label; kind = 'update'; a = 0; b = 0; list = (@($cur.updates) -join ', ') }
        }
        if ($cur.drifted -gt 0) {
            $notes += @{ date = $cur.label; kind = 'drift'; a = [int]$cur.drifted; b = [int]$cur.fixed; list = '' }
        }
        if ($prev.events -gt 0 -and $cur.events -gt ($prev.events * 1.5) -and $cur.events -gt 100) {
            $notes += @{ date = $cur.label; kind = 'grow'; a = [int]$prev.events; b = [int]$cur.events; list = '' }
        }
    }

    return @{
        days = $rows; peak = $peak; count = $rows.Count
        notes = @($notes | Select-Object -Last 12)
        hasXray = [bool]($xray.Count -gt 0)
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    }
}

if ($Timeline) {
    Emit-Json (Get-Timeline -Days $TimelineDays)
    exit 0
}

if ($XrayScan) {
    $r = Invoke-XrayScan -Hours $XrayHours -Max $XrayMax
    if (-not $r.error) {
        try { Save-Json 'xray-last.json' @{ time = $r.time; perDay = $r.perDay; mbPerDay = $r.mbPerDay } } catch { }
        Save-XrayDay $r      # дневной замер для хронологии
    }
    if ($XrayBaseline -and -not $r.error) {
        Save-Json 'xray-baseline.json' @{ time = $r.time; perDay = $r.perDay; mbPerDay = $r.mbPerDay; total = $r.total; hours = $r.hours }
        $r.savedBaseline = $true
    }
    Emit-Json $r
    exit 0
}

if ($XrayWipe) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Рентген: стирание локальной копии'
    $before = (Get-XrayDbInfo).mb
    $svc = Get-Service -Name DiagTrack -ErrorAction SilentlyContinue
    $was = ($svc -and $svc.Status -eq 'Running')
    if ($was) { Stop-Service DiagTrack -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 800 }
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $script:XrayDbDir -Force -ErrorAction SilentlyContinue)) {
        try { Remove-Item -LiteralPath $f.FullName -Force -Recurse -ErrorAction Stop; $n++ } catch { }
    }
    if ($was -and $svc.StartType -ne 'Disabled') { Start-Service DiagTrack -ErrorAction SilentlyContinue }
    Write-Log ("   [+] удалено файлов: {0} (было {1} МБ)" -f $n, $before)
    Emit-Json (Get-XrayDbInfo)
    Write-Log '###DONE###'
    exit 0
}

# --- Страж запускается после объявления рентгена: он делает дневной замер --- #
if ($Guard) {
    if (-not (Test-Admin)) { exit 1 }
    $null = Run-Guard -Verbose $false
    exit 0
}

if ($GuardNow) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Страж: проверка сейчас'
    $s = Run-Guard -Verbose $true
    Emit-Json $s
    Write-Log '###DONE###'
    exit 0
}

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

# =========================================================================== #
#  ЖИВЫЕ УВЕДОМЛЕНИЯ О ПЕРЕХВАТЕ
# =========================================================================== #
$script:WatcherTask = 'Win11Privacy Watcher'

if ($InstallWatcher) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Живые уведомления'
    try {
        Ensure-DataDir
        $engineDst = Install-TaskEngine
        if (-not (Get-MonitorEnabled)) { Set-MonitorEnabled $true | Out-Null }
        foreach ($d in $script:Defs) { if ($d.M -eq 'firewall') { Apply-Def $d } }

        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $engineDst + '" -WatcherNotify' + $script:DataArg)
        $cls = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
        $trigger = New-CimInstance -CimClass $cls -ClientOnly
        $trigger.Subscription = '<QueryList><Query Id="0" Path="Security"><Select Path="Security">*[System[(EventID=5157)]]</Select></Query></QueryList>'
        $trigger.Enabled = $true
        $trigger.Delay = 'PT5S'
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 3)
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $script:WatcherTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log '   [+] уведомления включены: всплывашка при перехвате отправки телеметрии'
        Write-Log '   [+] чтобы не мешать, одно уведомление не чаще чем раз в 10 минут'
    } catch { Write-Log "   [!] не удалось: $($_.Exception.Message)" }
    Write-Log '###DONE###'
    exit 0
}

if ($RemoveWatcher) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Живые уведомления'
    try { Unregister-ScheduledTask -TaskName $script:WatcherTask -Confirm:$false -ErrorAction Stop; Write-Log '   [+] уведомления выключены' }
    catch { Write-Log '   [-] задача уведомлений не найдена' }
    Write-Log '###DONE###'
    exit 0
}

if ($WatcherNotify) {
    # антидребезг: не чаще одного уведомления в 10 минут
    Ensure-DataDir
    $stamp = Join-Path $script:DataDir 'watcher-last.txt'
    if (Test-Path -LiteralPath $stamp) {
        try {
            $last = [datetime]::ParseExact((Get-Content -LiteralPath $stamp -Raw).Trim(), 'yyyy-MM-dd HH:mm:ss', $null)
            if ((Get-Date) -lt $last.AddMinutes(10)) { exit 0 }
        } catch { }
    }
    $since = (Get-Date).AddMinutes(-11)
    $stats = Get-MonitorStats -Hours 1
    $tele = @($stats.byDest | Where-Object { $_.domain -match $script:TelemetryDnsRegex })
    if ($tele.Count -eq 0) { exit 0 }
    $top = $tele | Sort-Object { $_.count } -Descending | Select-Object -First 1
    $procs = @($stats.byProcess | Select-Object -First 1)
    $who = if ($procs.Count -gt 0) { $procs[0].name } else { 'системная служба' }
    Show-Toast 'Перехвачена отправка данных' ("{0} пытался отправить данные на {1} — заблокировано." -f $who, $top.domain)
    (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') | Set-Content -LiteralPath $stamp -Encoding UTF8
    exit 0
}

# =========================================================================== #
#  ДОСЬЕ, часть 1: кто включал камеру, микрофон, геолокацию
#  Windows сама ведёт журнал обращений к датчикам (ConsentStore) —
#  мы его читаем и показываем человеку. Только чтение.
# =========================================================================== #
$script:SpyCaps = @(
    @{ id='webcam';                 title='Камера' },
    @{ id='microphone';             title='Микрофон' },
    @{ id='location';               title='Местоположение' },
    @{ id='graphicsCaptureProgrammatic'; title='Снимки экрана' },
    @{ id='graphicsCaptureWithoutBorder'; title='Захват экрана без рамки' },
    @{ id='userNotificationListener'; title='Чтение уведомлений' },
    @{ id='documentsLibrary';       title='Документы' },
    @{ id='picturesLibrary';        title='Изображения' },
    @{ id='videosLibrary';          title='Видео' },
    @{ id='broadFileSystemAccess';  title='Весь диск' },
    @{ id='contacts';               title='Контакты' },
    @{ id='appointments';           title='Календарь' },
    @{ id='email';                  title='Почта' },
    @{ id='chat';                   title='Сообщения' },
    @{ id='phoneCall';              title='Звонки' },
    @{ id='phoneCallHistory';       title='Журнал звонков' },
    @{ id='userDataTasks';          title='Задачи и планы' },
    @{ id='userAccountInformation'; title='Данные учётной записи' },
    @{ id='activity';               title='Сведения об активности' },
    @{ id='bluetoothSync';          title='Обмен с устройствами' },
    @{ id='radios';                 title='Управление радиомодулями' },
    @{ id='sensors.custom';         title='Датчики устройства' },
    @{ id='humanInterfaceDevice';   title='Устройства ввода' },
    @{ id='cellularData';           title='Сотовая связь' },
    @{ id='appDiagnostics';         title='Диагностика других программ' },
    # Эти категории Windows завела позже: ИИ-модели системы, ключи доступа,
    # периферия. Раньше «Досье» их просто не показывало.
    @{ id='systemAIModels';         title='ИИ-модели Windows' },
    @{ id='passkeys';               title='Ключи доступа (passkeys)' },
    @{ id='passkeysEnumeration';    title='Перечень ключей доступа' },
    @{ id='bluetooth';              title='Bluetooth' },
    @{ id='usb';                    title='USB-устройства' },
    @{ id='serialCommunication';    title='COM-порты' },
    @{ id='wiFiDirect';             title='Wi-Fi Direct' },
    @{ id='wifiData';               title='Данные о сетях Wi-Fi' },
    @{ id='gazeInput';              title='Отслеживание взгляда' }
)

function ConvertTo-FriendlyAppName {
    param([string]$Key)
    if ($Key -match '#') {
        $p = $Key -replace '#','\'
        $leaf = Split-Path $p -Leaf
        if ($leaf) { return $leaf }
        return $Key
    }
    $i = $Key.IndexOf('_')
    if ($i -gt 0) { return $Key.Substring(0, $i) }
    return $Key
}

function Get-SpyReport {
    $caps = @(); $activeNow = 0; $week = 0
    $since7 = (Get-Date).AddDays(-7)
    foreach ($cap in $script:SpyCaps) {
        $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\' + $cap.id
        $global = Get-RegValue $root 'Value'
        $keys = @()
        if (Test-Path -LiteralPath $root) {
            foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                if ($k.PSChildName -eq 'NonPackaged') { $keys += @(Get-ChildItem -LiteralPath $k.PSPath -ErrorAction SilentlyContinue) }
                else { $keys += $k }
            }
        }
        $items = @()
        foreach ($k in $keys) {
            $start = 0L; $stop = 0L
            try {
                $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop
                if ($null -ne $p.LastUsedTimeStart) { $start = [long]$p.LastUsedTimeStart }
                if ($null -ne $p.LastUsedTimeStop)  { $stop  = [long]$p.LastUsedTimeStop }
            } catch { }
            if ($start -le 0 -and -not $SpyAll) { continue }
            $active = ($stop -le 0 -or $stop -lt $start)
            $lastTicks = [Math]::Max($start, $stop)
            $last = $null
            if ($lastTicks -gt 0) { try { $last = [DateTime]::FromFileTime($lastTicks) } catch { } }
            $never = ($null -eq $last)
            if ($never) { $last = [datetime]'1900-01-01' }
            $minutes = 0.0
            if (-not $active -and $stop -gt $start) { $minutes = [math]::Round(($stop - $start) / 600000000.0, 1) }
            if ($active -and -not $never) { $activeNow++ } else { $active = $false }
            if (-not $never -and $last -ge $since7) { $week++ }
            $rel = ($k.PSPath -replace '^.*\\ConsentStore\\', '')
            $allow = 'Allow'
            try { $vv = (Get-ItemProperty -LiteralPath $k.PSPath -Name 'Value' -ErrorAction Stop).Value; if ($vv) { $allow = "$vv" } } catch { }
            $items += @{ app = (ConvertTo-FriendlyAppName $k.PSChildName); key = $rel; value = $allow
                         last = $(if ($never) { '' } else { $last.ToString('yyyy-MM-dd HH:mm') })
                         minutes = $minutes; active = [bool]$active; never = [bool]$never
                         sort = $last.Ticks }
        }
        # один и тот же exe может числиться под несколькими ключами — оставляем самое свежее
        $seen = @{}; $dedup = @()
        foreach ($it in @($items | Sort-Object { $_.sort } -Descending)) {
            $k = $it.app.ToLowerInvariant()
            if ($seen.ContainsKey($k)) {
                if ($it.minutes -gt $dedup[$seen[$k]].minutes) { $dedup[$seen[$k]].minutes = $it.minutes }
                continue
            }
            $seen[$k] = $dedup.Count; $dedup += $it
        }
        $items = @($dedup | Select-Object -First 40)
        foreach ($it in $items) { $it.Remove('sort') }
        $caps += @{ id = $cap.id; title = $cap.title
                    global = $(if ("$global") { "$global" } else { 'Allow' })
                    count = $items.Count; items = $items }
    }
    return @{ time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); activeNow = $activeNow; week = $week; caps = $caps }
}

# --- Накопленная история обращений к датчикам ------------------------------ #
# ConsentStore хранит только последнее использование, поэтому при каждом
# сборе досье и каждой проверке слежения новые метки складываются в журнал —
# из него строится график по дням.
function Update-SensorHistory {
    param($Report)
    $hist = Load-Json 'sensor-history.json'
    $known = @{}
    $events = @()
    if ($hist -and $hist.events) {
        foreach ($e in @($hist.events)) {
            $events += $e
            $known[("{0}|{1}|{2}" -f $e.cap, $e.app, $e.time)] = $true
        }
    }
    $new = @()
    foreach ($c in @($Report.caps)) {
        foreach ($it in @($c.items)) {
            $k = "{0}|{1}|{2}" -f $c.id, $it.app, $it.last
            if ($known.ContainsKey($k)) { continue }
            $ev = @{ cap = $c.id; app = $it.app; time = $it.last; minutes = $it.minutes }
            $events += $ev; $new += $ev; $known[$k] = $true
        }
    }
    if ($new.Count -gt 0 -or -not $hist) {
        if ($events.Count -gt 2000) { $events = @($events | Sort-Object { "$($_.time)" } | Select-Object -Last 2000) }
        Save-Json 'sensor-history.json' @{ events = $events; updated = (Get-Date).ToString('s') }
    }
    return ,$new
}

function Get-SensorDays {
    $hist = Load-Json 'sensor-history.json'
    $byDay = @{}
    if ($hist -and $hist.events) {
        foreach ($e in @($hist.events)) {
            $ds = "$($e.time)"
            if ($ds.Length -lt 10) { continue }
            $ds = $ds.Substring(0, 10)
            if (-not $byDay.ContainsKey($ds)) { $byDay[$ds] = @{ cam=0; mic=0; loc=0; other=0 } }
            switch ("$($e.cap)") {
                'webcam'     { $byDay[$ds].cam++ }
                'microphone' { $byDay[$ds].mic++ }
                'location'   { $byDay[$ds].loc++ }
                default      { $byDay[$ds].other++ }
            }
        }
    }
    $days = @()
    for ($i = 13; $i -ge 0; $i--) {
        $d = (Get-Date).Date.AddDays(-$i)
        $ds = $d.ToString('yyyy-MM-dd')
        $rec = if ($byDay.ContainsKey($ds)) { $byDay[$ds] } else { @{ cam=0; mic=0; loc=0; other=0 } }
        $days += @{ date = $d.ToString('dd.MM'); cam = $rec.cam; mic = $rec.mic; loc = $rec.loc; other = $rec.other }
    }
    return $days
}

# =========================================================================== #
#  ДОСЬЕ, часть 2: цифровой след на диске
# =========================================================================== #
function Get-FileCount { param([string]$P, [string]$Filter = '*')
    if (-not (Test-Path -LiteralPath $P)) { return 0 }
    return @(Get-ChildItem -LiteralPath $P -Filter $Filter -Force -ErrorAction SilentlyContinue).Count
}

# Журналы событий, где Windows хранит следы работы с программами и доступа к
# данным. Раньше «Цифровой след» их не видел, а записей там тысячи.
$script:FootprintLogs = @(
    'Microsoft-Windows-Privacy-Auditing/Operational',
    'Microsoft-Windows-UniversalTelemetryClient/Operational',
    'Microsoft-Windows-Application-Experience/Program-Telemetry',
    'Microsoft-Windows-Application-Experience/Program-Compatibility-Assistant',
    'Microsoft-Windows-Shell-Core/Operational'
)

function Get-Footprint {
    $items = New-Object System.Collections.Generic.List[object]
    $add = { param($id, $title, $what, $value, $mb, $count, $canWipe, $warn)
        $items.Add(@{ id=$id; title=$title; what=$what; value="$value"; mb=[double]$mb; count=[int]$count; canWipe=[bool]$canWipe; warn="$warn" }) }

    # Рекламный ID
    $adOn = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled'
    $adId = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Id'
    $adVal = if ($adId) { "$adId" } elseif ($adOn -eq 0) { 'выключен, ID стёрт' } else { 'нет' }
    & $add 'adid' 'Рекламный идентификатор' 'Уникальный ID, по которому рекламные сети узнают вас во всех приложениях.' $adVal 0 $(if ($adId) { 1 } else { 0 }) $([bool]$adId) ''

    # Постоянные ID машины
    $mg  = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Cryptography' 'MachineGuid'
    $sqm = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\SQMClient' 'MachineId'
    & $add 'machineid' 'Постоянные метки компьютера' 'MachineGuid и SQM MachineId — метки, которыми помечается телеметрия. Нужны системе, стереть нельзя.' ("$mg " + "$sqm").Trim() 0 2 $false ''

    # Номер устройства в учётной записи Microsoft (GDID). Лежит открытым текстом
    # шестнадцатеричным числом; Microsoft знает его в десятичном виде с «g:».
    # Простое стирание бесполезно — работа с ним на своей вкладке.
    $gdid = ConvertTo-Gdid "$(Get-RegValue 'HKCU:\SOFTWARE\Microsoft\IdentityCRL\ExtendedProperties' 'LID')"
    $gdidOff = ((Get-SvcStart 'CDPSvc') -eq 4 -and (Get-SvcStart 'DoSvc') -eq 4)
    $gdidWarn = $(if ($gdid -and -not $gdidOff) { 'передаётся' } else { '' })
    & $add 'gdid' 'Номер устройства в учётной записи Microsoft (GDID)' 'По этому номеру Microsoft узнаёт компьютер даже через VPN и выдаёт его по запросу властей. Не передавать, сменить или запретить выдачу — на вкладке «Номер устройства».' $(if ($gdid) { $gdid } else { '—' }) 0 $(if ($gdid) { 1 } else { 0 }) $false $gdidWarn

    # История сетей
    $netNames = @()
    try {
        foreach ($k in @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles' -ErrorAction Stop)) {
            $n = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).ProfileName
            if ($n) { $netNames += "$n" }
        }
    } catch { }
    $netVal = if ($netNames.Count -gt 0) { (@($netNames | Select-Object -First 4) -join ', ') + $(if ($netNames.Count -gt 4) { ' …' } else { '' }) } else { 'пусто' }
    & $add 'networks' 'История сетей Wi-Fi и Ethernet' 'Список всех сетей, к которым подключался компьютер — по ним видно, где вы бывали. Пароли Wi-Fi не трогаются.' $netVal 0 $netNames.Count ($netNames.Count -gt 0) ''

    # История флешек и дисков
    $usb = @()
    try {
        foreach ($dev in @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR' -ErrorAction Stop)) {
            foreach ($inst in @(Get-ChildItem -LiteralPath $dev.PSPath -ErrorAction SilentlyContinue)) {
                $fn = (Get-ItemProperty -LiteralPath $inst.PSPath -ErrorAction SilentlyContinue).FriendlyName
                if ($fn -and $usb -notcontains "$fn") { $usb += "$fn" }
            }
        }
    } catch { }
    $usbVal = if ($usb.Count -gt 0) { (@($usb | Select-Object -First 3) -join ', ') + $(if ($usb.Count -gt 3) { ' …' } else { '' }) } else { 'пусто' }
    & $add 'usb' 'История подключённых флешек' 'Windows помнит каждую флешку и внешний диск. Запись системная, показываем для сведения.' $usbVal 0 $usb.Count $false ''

    # История активности (Timeline)
    $cdp = Join-Path $env:LOCALAPPDATA 'ConnectedDevicesPlatform'
    $cdpMb = Get-FolderSizeMB $cdp
    & $add 'activity' 'База истории активности' 'ActivitiesCache.db — какие программы и документы вы открывали, с точным временем.' ("{0} МБ" -f $cdpMb) $cdpMb (Get-FileCount $cdp) ($cdpMb -gt 0) ''

    # Недавние документы
    $recent = [Environment]::GetFolderPath('Recent')
    $recentCount = Get-FileCount $recent
    & $add 'recent' 'Недавние документы и папки' 'Ярлыки всего, что вы открывали, плюс списки переходов на панели задач.' ("{0} записей" -f $recentCount) (Get-FolderSizeMB $recent) $recentCount ($recentCount -gt 0) ''

    # Строка поиска Проводника
    $www = 0
    try { $k = Get-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery' -ErrorAction Stop; $www = @($k.GetValueNames() | Where-Object { $_ -ne 'MRUListEx' }).Count } catch { }
    & $add 'searchhistory' 'Что вы искали в Проводнике' 'История запросов в строке поиска Проводника.' ("{0} запросов" -f $www) 0 $www ($www -gt 0) ''

    # Адресная строка Проводника
    $tp = 0
    try { $k = Get-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths' -ErrorAction Stop; $tp = @($k.GetValueNames()).Count } catch { }
    & $add 'typedpaths' 'Введённые пути и адреса' 'Что вы вручную набирали в адресной строке Проводника.' ("{0} записей" -f $tp) 0 $tp ($tp -gt 0) ''

    # Буфер обмена
    $clipDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Clipboard'
    $clipMb = Get-FolderSizeMB $clipDir
    $clipOn = Get-RegValue 'HKCU:\Software\Microsoft\Clipboard' 'EnableClipboardHistory'
    & $add 'clipboard' 'История буфера обмена' 'Всё скопированное (Win+V) хранится на диске.' ($(if ($clipOn -eq 1) { 'включена, ' } else { 'выключена, ' }) + "$clipMb МБ") $clipMb (Get-FileCount $clipDir) ($clipMb -gt 0) ''

    # Отчёты об ошибках
    $wer1 = Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'
    $wer2 = Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'
    $wer3 = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER'
    $werMb = (Get-FolderSizeMB $wer1) + (Get-FolderSizeMB $wer2) + (Get-FolderSizeMB $wer3)
    $werCount = (Get-FileCount $wer1) + (Get-FileCount $wer2)
    & $add 'wer' 'Архив отчётов об ошибках' 'Дампы и отчёты о сбоях: содержат пути файлов, имена программ, куски памяти.' ("{0} отчётов, {1} МБ" -f $werCount, [math]::Round($werMb,1)) $werMb $werCount ($werMb -gt 0) ''

    # Словарь персонализации ввода
    $inp = Join-Path $env:APPDATA 'Microsoft\InputPersonalization'
    $inpMb = Get-FolderSizeMB $inp
    & $add 'inputpers' 'Личный словарь набора текста' 'Слова, собранные из вашего набора и рукописного ввода.' ("{0} МБ" -f $inpMb) $inpMb (Get-FileCount $inp) ($inpMb -gt 0) ''

    # Журналы Windows о работе с программами
    $evN = 0
    foreach ($lg in $script:FootprintLogs) {
        try { $evN += [int](Get-WinEvent -ListLog $lg -ErrorAction Stop).RecordCount } catch { }
    }
    & $add 'eventlogs' 'Журналы Windows о работе с программами' 'Какие программы обращались к данным и камере, что запускалось и что отправлял клиент телеметрии.' ("{0} записей" -f $evN) 0 $evN ($evN -gt 0) ''

    # Кэш DNS
    $dnsN = 0
    try { $dnsN = @(Get-DnsClientCache -ErrorAction Stop).Count } catch { }
    & $add 'dnscache' 'Кэш DNS (следы сайтов)' 'Адреса сайтов и служб, к которым недавно обращался компьютер.' ("{0} записей" -f $dnsN) 0 $dnsN ($dnsN -gt 0) ''

    $totalMb = 0.0; $wipeable = 0
    foreach ($it in $items) { $totalMb += [double]$it.mb; if ($it.canWipe) { $wipeable++ } }
    return @{ time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); items = $items.ToArray()
              totalMb = [math]::Round($totalMb, 1); wipeable = $wipeable }
}

function Invoke-FootprintWipe {
    param([string[]]$Ids)
    foreach ($id in $Ids) {
        switch ($id) {
            'adid' {
                if ($DryRun) { Write-Log '   [тест] рекламный ID — стереть'; break }
                try {
                    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 -Comment 'рекламный ID — выкл'
                    Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name 'Id' -Force -ErrorAction Stop
                    Write-Log '   [+] рекламный идентификатор стёрт'; $script:Changes++
                } catch { Write-Log '   [-] рекламный ID уже стёрт' }
            }
            'networks' {
                if ($DryRun) { Write-Log '   [тест] история сетей — очистить'; break }
                $n = 0
                foreach ($k in @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles' -ErrorAction SilentlyContinue)) {
                    try { Remove-Item -LiteralPath $k.PSPath -Recurse -Force -ErrorAction Stop; $n++ } catch { }
                }
                foreach ($sig in @('Unmanaged','Managed')) {
                    foreach ($k in @(Get-ChildItem ('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\' + $sig) -ErrorAction SilentlyContinue)) {
                        try { Remove-Item -LiteralPath $k.PSPath -Recurse -Force -ErrorAction Stop } catch { }
                    }
                }
                Write-Log ("   [+] история сетей очищена: {0} записей (пароли Wi-Fi не тронуты)" -f $n); $script:Changes++
            }
            'activity' {
                foreach ($svc in @(Get-Service -Name 'cdp*' -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' })) {
                    if (-not $DryRun) { Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue }
                }
                $null = Clear-FolderContents (Join-Path $env:LOCALAPPDATA 'ConnectedDevicesPlatform') 'база истории активности'
            }
            'recent' {
                $null = Clear-FolderContents ([Environment]::GetFolderPath('Recent')) 'недавние документы'
                if (-not $DryRun) {
                    try { Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs' -Recurse -Force -ErrorAction Stop; Write-Log '   [+] список RecentDocs в реестре очищен' } catch { }
                }
            }
            'searchhistory' {
                if ($DryRun) { Write-Log '   [тест] история поиска Проводника — очистить'; break }
                try { Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery' -Recurse -Force -ErrorAction Stop; Write-Log '   [+] история поиска Проводника очищена'; $script:Changes++ } catch { Write-Log '   [-] история поиска уже пуста' }
            }
            'typedpaths' {
                if ($DryRun) { Write-Log '   [тест] введённые пути — очистить'; break }
                try { Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths' -Recurse -Force -ErrorAction Stop; Write-Log '   [+] введённые пути очищены'; $script:Changes++ } catch { Write-Log '   [-] введённых путей нет' }
            }
            'clipboard' {
                $null = Clear-FolderContents (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Clipboard') 'история буфера обмена'
            }
            'wer' {
                $null = Clear-FolderContents (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive') 'архив отчётов об ошибках'
                $null = Clear-FolderContents (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue') 'очередь отчётов об ошибках'
                $null = Clear-FolderContents (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER') 'локальные отчёты об ошибках'
            }
            'inputpers' {
                $null = Clear-FolderContents (Join-Path $env:APPDATA 'Microsoft\InputPersonalization') 'личный словарь набора'
            }
            'dnscache' {
                if ($DryRun) { Write-Log '   [тест] кэш DNS — очистить'; break }
                try { Clear-DnsClientCache -ErrorAction Stop; Write-Log '   [+] кэш DNS очищен'; $script:Changes++ } catch { Write-Log '   [!] не удалось очистить кэш DNS' }
            }
            'eventlogs' {
                if ($DryRun) { Write-Log '   [тест] журналы Windows о работе с программами — очистить'; break }
                $cleared = 0
                foreach ($lg in $script:FootprintLogs) {
                    $null = & wevtutil.exe cl $lg 2>&1
                    if ($LASTEXITCODE -eq 0) { $cleared++ }
                }
                Write-Log ("   [+] очищено журналов: {0} из {1}" -f $cleared, $script:FootprintLogs.Count)
                if ($cleared -gt 0) { $script:Changes++ }
            }
            default { Write-Log ("   [-] неизвестный элемент следа: {0}" -f $id) }
        }
    }
}

# --- отозвать или вернуть доступ программы к датчику ---
if ($SensorSet) {
    $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\' + $SensorKey
    $r = @{ key = $SensorKey; value = $SensorValue; ok = $false }
    try {
        if (-not (Test-Path -LiteralPath $root)) { New-Item -Path $root -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $root -Name 'Value' -Value $SensorValue -PropertyType String -Force -ErrorAction Stop | Out-Null
        $r.ok = $true
    } catch { $r.error = $_.Exception.Message }
    Emit-Json $r
    exit 0
}

# --- список отдельных настроек внутри модулей ---
if ($ListDefs) {
    $groups = @()
    foreach ($m in $script:ModuleOrder) {
        $mi = @($script:Defs | Where-Object { $_.M -eq $m })
        if ($mi.Count -eq 0) { continue }
        $groups += @{ module = $m; title = $script:ModuleTitles[$m]
                      items = @($mi | ForEach-Object { @{ id = $_.Id; name = $_.C; kind = $_.T
                                                          target = "$($_.P)"; valueName = "$($_.N)"
                                                          risk = (Get-DefRisk $_)
                                                          note = $(if ($script:DefNotes.ContainsKey("$($_.C)")) { $script:DefNotes["$($_.C)"] } else { '' }) } }) }
    }
    Emit-Json @{ groups = $groups }
    exit 0
}

if ($Spy) {
    $r = Get-SpyReport
    try { $null = Update-SensorHistory $r } catch { }
    $r.days = Get-SensorDays
    $r.sensorGuard = [bool](Get-ScheduledTask -TaskName $script:SensorTask -ErrorAction SilentlyContinue)
    $r.doh = Get-DohStatus
    Emit-Json $r
    exit 0
}

if ($Footprint) { Emit-Json (Get-Footprint); exit 0 }

if ($LeakTest) { Emit-Json (Invoke-LeakTest); exit 0 }

if ($FootprintWipe) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Стирание цифрового следа'
    if ($WipeItems.Count -eq 0) { Write-Log '   [-] ничего не выбрано' }
    else { Invoke-FootprintWipe -Ids $WipeItems }
    Emit-Json (Get-Footprint)
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  СЛЕЖЕНИЕ ЗА ДАТЧИКАМИ
#  Каждые 30 минут сверяем журнал ConsentStore. Новая программа получила
#  доступ к камере/микрофону/геолокации -> всплывающее уведомление.
# =========================================================================== #
$script:SensorCapNames = @{
    webcam='камеру'; microphone='микрофон'; location='местоположение'
    contacts='контакты'; userAccountInformation='данные учётной записи'; userDataTasks='задачи и планы'
}

if ($InstallSensorGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Слежение за датчиками'
    try {
        Ensure-DataDir
        $engineDst = Install-TaskEngine

        # закладываем текущий список программ как известный — без уведомлений
        $r0 = Get-SpyReport
        try { $null = Update-SensorHistory $r0 } catch { }
        $pairs = @()
        foreach ($c in @($r0.caps)) { foreach ($it in @($c.items)) { $pairs += ($c.id + '|' + $it.app) } }
        Save-Json 'sensor-apps.json' @{ pairs = $pairs; updated = (Get-Date).ToString('s') }

        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $engineDst + '" -SensorGuard' + $script:DataArg)
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration (New-TimeSpan -Days 3650)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $script:SensorTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log '   [+] слежение включено: сверка журнала каждые 30 минут'
        Write-Log '   [+] новая программа получит доступ к камере, микрофону или геолокации — придёт уведомление'
        Write-Log ("   [+] сейчас программ в журнале: {0}" -f $pairs.Count)
        Write-Log '   [+] попутно накапливается история для графика на «Обзоре»'
    } catch { Write-Log "   [!] не удалось: $($_.Exception.Message)" }
    Write-Log '###DONE###'
    exit 0
}

if ($InstallNetGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Слежение за сетью'
    try {
        Ensure-DataDir
        $engineDst = Install-TaskEngine
        # без журнала разрешённых соединений слежению не из чего брать программы
        if (-not (Get-MonitorEnabled)) { $null = Set-MonitorEnabled $true }
        # Известными считаем всех, кто выходил в сеть за неделю, и тех, у кого
        # соединение открыто прямо сейчас; ещё час слежение учится молча.
        $known = @{}
        foreach ($k in @((Get-NetAppsSince -Since (Get-Date).AddDays(-7)).Keys)) { $known[$k] = $true }
        foreach ($c in @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue)) {
            try { $p = (Get-Process -Id $c.OwningProcess -ErrorAction Stop).Path; if ($p) { $known[$p.ToLowerInvariant()] = $true } } catch { }
        }
        Save-Json 'net-apps.json' @{ known = @($known.Keys); recent = @(); learnUntil = (Get-Date).AddHours(1).ToString('s'); last = (Get-Date).ToString('s') }
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $engineDst + '" -NetGuard' + $script:DataArg)
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 3650)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $script:NetTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log '   [+] слежение включено: сверка журнала брандмауэра каждые 15 минут'
        Write-Log ("   [+] известных программ: {0}; первый час слежение учится и молчит" -f $known.Count)
        Write-Log '   [+] новая программа выйдет в сеть — придёт уведомление, а на странице «Монитор» её можно отрезать'
    } catch { Write-Log "   [!] не удалось: $($_.Exception.Message)" }
    Write-Log '###DONE###'
    exit 0
}

if ($RemoveNetGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Слежение за сетью'
    try { Unregister-ScheduledTask -TaskName $script:NetTask -Confirm:$false -ErrorAction Stop; Write-Log '   [+] слежение отключено' }
    catch { Write-Log '   [-] задача слежения не найдена' }
    Write-Log '   [i] журнал соединений остаётся — он нужен монитору; выключается кнопкой монитора.'
    Write-Log '###DONE###'
    exit 0
}

# периодический запуск из планировщика: тихо, без вывода
if ($NetGuard) { $null = Invoke-NetGuard; exit 0 }

if ($RemoveSensorGuard) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Слежение за датчиками'
    try { Unregister-ScheduledTask -TaskName $script:SensorTask -Confirm:$false -ErrorAction Stop; Write-Log '   [+] слежение отключено' }
    catch { Write-Log '   [-] задача слежения не найдена' }
    Write-Log '###DONE###'
    exit 0
}

if ($SensorGuard) {
    # периодический запуск из планировщика: тихо, без вывода
    $r = Get-SpyReport
    try { $null = Update-SensorHistory $r } catch { }

    $saved = Load-Json 'sensor-apps.json'
    $first = ($null -eq $saved)
    $known = @{}
    if ($saved -and $saved.pairs) { foreach ($p in @($saved.pairs)) { $known["$p"] = $true } }

    $newApps = @()
    foreach ($c in @($r.caps)) {
        foreach ($it in @($c.items)) {
            $k = $c.id + '|' + $it.app
            if ($known.ContainsKey($k)) { continue }
            $known[$k] = $true
            if (-not $first) { $newApps += @{ cap = $c.id; app = $it.app; last = $it.last } }
        }
    }
    try { Save-Json 'sensor-apps.json' @{ pairs = @($known.Keys); updated = (Get-Date).ToString('s') } } catch { }

    if ($newApps.Count -gt 0) {
        $parts = @()
        foreach ($n in @($newApps | Select-Object -First 3)) {
            $t = $script:SensorCapNames["$($n.cap)"]
            if (-not $t) { $t = "$($n.cap)" }
            $parts += ("{0} — {1}" -f $n.app, $t)
        }
        $msg = ($parts -join '; ')
        if ($newApps.Count -gt 3) { $msg += (' и ещё ' + ($newApps.Count - 3)) }
        Show-Toast 'Новая программа получила доступ к датчикам' $msg
        Write-Log ("новых программ с доступом к датчикам: {0} -- {1}" -f $newApps.Count, $msg)
    }
    exit 0
}

# =========================================================================== #
#  ПРЕДУСТАНОВЛЕННЫЕ ПРИЛОЖЕНИЯ
#  Список того, что можно безопасно удалить, и само удаление.
# =========================================================================== #

# Трогать нельзя никогда — без этого система ломается
$script:AppxProtected = @(
    'Microsoft.WindowsStore','Microsoft.DesktopAppInstaller','Microsoft.StorePurchaseApp',
    'Microsoft.VCLibs','Microsoft.NET','Microsoft.UI.Xaml','Microsoft.Services.Store',
    'Microsoft.WindowsTerminal','Microsoft.SecHealthUI','Microsoft.Windows.Photos.Addon',
    'MicrosoftWindows.Client','Microsoft.AAD','Microsoft.AccountsControl','Microsoft.Win32WebViewHost',
    'Microsoft.CredDialogHost','Microsoft.ECApp','Microsoft.LockApp','Microsoft.Windows.ShellExperienceHost',
    'Microsoft.Windows.StartMenuExperienceHost','Microsoft.Windows.SecureAssessmentBrowser',
    'Microsoft.WindowsAppRuntime','Microsoft.HEIFImageExtension','Microsoft.HEVCVideoExtension',
    'Microsoft.WebpImageExtension','Microsoft.RawImageExtension','Microsoft.VP9VideoExtensions',
    'Microsoft.WebMediaExtensions','Microsoft.MicrosoftEdge'
)

# Что обычно ставят без спроса — помечаем как «можно убрать»
$script:AppxBloat = @{
    'MicrosoftWindows.Client.WebExperience' = 'Виджеты и лента Microsoft Start'
    'Microsoft.BingNews'                = 'Новости MSN'
    'Microsoft.BingWeather'             = 'Погода MSN'
    'Microsoft.BingSearch'              = 'Поиск Bing в Пуске'
    'Microsoft.BingFinance'             = 'Финансы MSN'
    'Microsoft.BingSports'              = 'Спорт MSN'
    'Clipchamp.Clipchamp'               = 'Видеоредактор Clipchamp'
    'Microsoft.GamingApp'               = 'Приложение Xbox'
    'Microsoft.XboxGameOverlay'         = 'Игровая панель Xbox'
    'Microsoft.XboxGamingOverlay'       = 'Игровая панель Xbox'
    'Microsoft.XboxIdentityProvider'    = 'Вход Xbox'
    'Microsoft.XboxSpeechToTextOverlay' = 'Субтитры Xbox'
    'Microsoft.MicrosoftSolitaireCollection' = 'Коллекция пасьянсов'
    'Microsoft.MicrosoftOfficeHub'      = 'Промо Microsoft 365'
    'Microsoft.Office.OneNote'          = 'OneNote из магазина'
    'MicrosoftTeams'                    = 'Teams (личный)'
    'MSTeams'                           = 'Teams (личный)'
    'Microsoft.SkypeApp'                = 'Skype'
    'Microsoft.YourPhone'               = 'Связь с телефоном'
    'Microsoft.People'                  = 'Люди'
    'Microsoft.WindowsMaps'             = 'Карты'
    'Microsoft.WindowsFeedbackHub'      = 'Центр отзывов'
    'Microsoft.GetHelp'                 = 'Справка'
    'Microsoft.Getstarted'              = 'Советы'
    'Microsoft.Microsoft3DViewer'       = 'Просмотр 3D'
    'Microsoft.MixedReality.Portal'     = 'Портал смешанной реальности'
    'Microsoft.ZuneMusic'               = 'Медиапроигрыватель'
    'Microsoft.ZuneVideo'               = 'Фильмы и ТВ'
    'Microsoft.Todos'                   = 'To Do'
    'Microsoft.PowerAutomateDesktop'    = 'Power Automate'
    'Microsoft.Windows.DevHome'         = 'Dev Home'
    'MicrosoftCorporationII.QuickAssist'= 'Быстрая помощь'
    'Microsoft.Copilot'                 = 'Copilot'
    'Microsoft.Windows.Ai.Copilot.Provider' = 'Copilot (компонент)'
    'Microsoft.OutlookForWindows'       = 'Новый Outlook'
    'Microsoft.MicrosoftStickyNotes'    = 'Записки'
    'Microsoft.549981C3F5F10'           = 'Cortana'
}

# Исключения из защищённых префиксов: сама «оболочка» MicrosoftWindows.Client
# трогать нельзя, а вот доска виджетов внутри неё удаляется безболезненно —
# на Home это единственный способ убрать её совсем.
$script:AppxAllowed = @('MicrosoftWindows.Client.WebExperience')

function Test-AppxProtected {
    param([string]$Name)
    foreach ($a in $script:AppxAllowed) { if ($Name -eq $a) { return $false } }
    foreach ($p in $script:AppxProtected) { if ($Name -like ($p + '*')) { return $true } }
    return $false
}

function Get-AppxList {
    $list = @()
    $pkgs = @()
    try { $pkgs = @(Get-AppxPackage -ErrorAction Stop | Where-Object { -not $_.IsFramework }) } catch { }
    foreach ($p in $pkgs) {
        $name = [string]$p.Name
        if (Test-AppxProtected $name) { continue }
        $bloat = $script:AppxBloat.ContainsKey($name)
        $title = if ($bloat) { $script:AppxBloat[$name] } else { $name }
        $list += @{ name = $name; title = $title; publisher = [string]$p.Publisher
                    version = [string]$p.Version; bloat = [bool]$bloat
                    system = [bool]($p.SignatureKind -eq 'System') }
    }
    return @($list | Sort-Object { -[int][bool]$_.bloat }, { $_.title })
}

if ($ListApps) {
    $appList = @(Get-AppxList)      # через переменную — иначе один элемент уедет объектом
    Emit-Json @{ apps = $appList; time = (Get-Date).ToString('yyyy-MM-dd HH:mm') }
    exit 0
}

if ($RemoveApps) {
    Write-Section 'Удаление предустановленных приложений'
    if ($AppItems.Count -eq 0) { Write-Log '   [-] ничего не выбрано'; Write-Log '###DONE###'; exit 0 }
    $done = 0
    foreach ($name in $AppItems) {
        if (Test-AppxProtected $name) { Write-Log ("   [-] {0} — системный компонент, пропущен" -f $name); continue }
        if ($DryRun) { Write-Log ("   [тест] {0} — будет удалён" -f $name); continue }
        $pkgs = @(Get-AppxPackage -Name $name -ErrorAction SilentlyContinue)
        if ($pkgs.Count -eq 0) { Write-Log ("   [-] {0} — не найден" -f $name); continue }
        foreach ($p in $pkgs) {
            try {
                Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop
                Write-Log ("   [+] удалён: {0}" -f $name); $done++; $script:Changes++
            } catch { Write-Log ("   [!] {0} -- {1}" -f $name, $_.Exception.Message); $script:Failures++ }
        }
        if ($AllUsers -and (Test-Admin)) {
            try {
                $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $name })
                foreach ($pp in $prov) {
                    Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null
                    Write-Log ("   [+] больше не ставится новым пользователям: {0}" -f $name)
                }
            } catch { }
        }
    }
    Write-Log ("   удалено приложений: {0}" -f $done)
    Emit-Json @{ removed = $done }
    Write-Log '###DONE###'
    exit 0
}

if ($CleanJunk) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Emit-Json @{ error='нужны права администратора' }; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Уборка за старыми версиями'
    $before = @(Find-JunkValues).Count
    $gone = Remove-JunkValues
    if ($before -eq 0) { Write-Log '   [-] мусорных параметров нет' }
    Emit-Json @{ found = $before; removed = $gone }
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  РЕЗЕРВНЫЕ КОПИИ: показать и вернуть
#  Копии .reg программа делала и раньше, но импортировать их приходилось
#  руками. Теперь круг замкнут: снимок -> откат по журналу -> импорт копии.
# =========================================================================== #
function Get-BackupList {
    $roots = @()
    if ($BackupRoot) { $roots += $BackupRoot }
    $roots += [Environment]::GetFolderPath('Desktop')
    $roots += $script:DataDir
    $seen = @{}
    $list = @()
    foreach ($root in $roots) {
        if (-not $root -or $seen.ContainsKey($root) -or -not (Test-Path -LiteralPath $root)) { continue }
        $seen[$root] = $true
        foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -Filter 'Win11Privacy-Backup-*' -ErrorAction SilentlyContinue)) {
            $files = @(Get-ChildItem -LiteralPath $dir.FullName -File -Filter '*.reg' -ErrorAction SilentlyContinue)
            if ($files.Count -eq 0) { continue }
            $size = 0
            foreach ($f in $files) { $size += $f.Length }
            $list += @{ path = $dir.FullName; name = $dir.Name
                        when = $dir.CreationTime.ToString('yyyy-MM-dd HH:mm')
                        branches = $files.Count; kb = [math]::Round($size / 1KB, 1) }
        }
    }
    return @($list | Sort-Object { $_.when } -Descending)
}

if ($ListBackups) {
    $bkList = @(Get-BackupList)
    Emit-Json @{ items = $bkList; count = $bkList.Count }
    exit 0
}

if ($RestoreBackup) {
    if (-not (Test-Admin)) { Emit-Json @{ error = 'нужны права администратора' }; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Восстановление из резервной копии'
    if (-not $BackupPath -or -not (Test-Path -LiteralPath $BackupPath)) {
        Write-Log '   [!] папка копии не найдена'
        Emit-Json @{ error = 'папка копии не найдена' }; Write-Log '###DONE###'; exit 1
    }
    $regFiles = @(Get-ChildItem -LiteralPath $BackupPath -File -Filter '*.reg' -ErrorAction SilentlyContinue)
    if ($regFiles.Count -eq 0) {
        Write-Log '   [!] в этой папке нет файлов .reg'
        Emit-Json @{ error = 'в папке нет файлов .reg' }; Write-Log '###DONE###'; exit 1
    }
    Write-Log ("   найдено файлов: {0}" -f $regFiles.Count)
    $ok = 0; $bad = 0
    foreach ($f in $regFiles) {
        if ($DryRun) { Write-Log ("   [тест] {0}" -f $f.Name); continue }
        # через cmd: у reg.exe свой поток ошибок, и в PowerShell 5.1 он умеет
        # обрываться терминирующей ошибкой на первом же отказе
        try { $null = & cmd.exe /c "reg import `"$($f.FullName)`" >nul 2>&1" } catch { }
        if ($LASTEXITCODE -eq 0) { Write-Log ("   [+] вернули: {0}" -f $f.Name); $ok++; $script:Changes++ }
        else { Write-Log ("   [!] не удалось: {0}" -f $f.Name); $bad++; $script:Failures++ }
    }
    Write-Log ("   возвращено веток: {0}" -f $ok)
    if ($bad -gt 0) { Write-Log ("   не удалось вернуть: {0}" -f $bad) }
    Write-Log '   Значения вернулись к состоянию на момент копии. Перезагрузите компьютер.'
    Emit-Json @{ restored = $ok; failed = $bad; path = $BackupPath }
    Write-Log '###DONE###'
    exit 0
}

if ($ListStartup) {
    $stList = @(Get-StartupList)
    $stOn   = @($stList | Where-Object { $_.enabled })
    Emit-Json @{ items = $stList; total = $stList.Count; on = $stOn.Count
                 advise = @($stOn | Where-Object { $_.advise }).Count
                 time = (Get-Date).ToString('yyyy-MM-dd HH:mm') }
    exit 0
}

if ($StartupSet) {
    $wantOn = ($StartupValue -eq 'On')
    Write-Section $(if ($wantOn) { 'Автозагрузка: вернуть записи' } else { 'Автозагрузка: отключить записи' })
    if ($StartupItems.Count -eq 0) { Write-Log '   [-] ничего не выбрано'; Emit-Json @{ changed = 0 }; Write-Log '###DONE###'; exit 0 }
    $known = @{}
    foreach ($it in @(Get-StartupList)) { $known[[string]$it.id] = $it }
    $done = 0
    foreach ($id in $StartupItems) {
        $raw = ConvertFrom-StartupId $id
        if (-not $raw) { Write-Log ("   [!] непонятная запись: {0}" -f $id); $script:Failures++; continue }
        $it = $known[[string]$id]
        $label = $(if ($it) { [string]$it.name } else { $raw })
        if ($it -and ([bool]$it.enabled) -eq $wantOn) { Write-Log ("   [в] {0} -- уже так" -f $label); $script:Already++; continue }
        if ($DryRun) { Write-Log ("   [тест] {0}" -f $label); continue }
        $r = Set-StartupState $raw $wantOn
        if ($r.ok) {
            Write-Log ("   [+] {0} -- {1}" -f $label, $(if ($wantOn) { 'снова запускается' } else { 'больше не запускается' }))
            $done++; $script:Changes++
            try {
                $script:Journal.Add(@{ kind = 'startup'; id = $raw; name = $label
                                       old = $(if ($wantOn) { 'Off' } else { 'On' })
                                       newValue = $(if ($wantOn) { 'On' } else { 'Off' })
                                       time = (Get-Date).ToString('s') })
            } catch { }
        } else {
            Write-Log ("   [!] {0} -- {1}" -f $label, $r.error); $script:Failures++
        }
    }
    Save-JournalEntries
    Write-Log ("   изменено записей: {0}" -f $done)
    Emit-Json @{ changed = $done; failures = $script:Failures }
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  ДОКАЗАТЕЛЬСТВО РЕЗУЛЬТАТА
#  Индекс говорит лишь «настройки на месте». Здесь собирается то, что можно
#  сравнить «до» и «после»: сколько событий уходило, сколько доменов молчит,
#  сколько сборщиков осталось включёнными и сколько телеметрии ждёт отправки.
# =========================================================================== #
# $Checked — уже посчитанные результаты Check-Def (их отдаёт -Audit). Без них
# снимок сам обходит все определения; с ними страница «Проверка» открывается
# вдвое быстрее, потому что 191 проверка выполняется один раз, а не дважды.
function Get-ProofSnapshot {
    param($Checked = $null, $Dns = $null)
    $ok = 0; $tot = 0; $etwOff = 0; $etwTotal = 0
    if ($null -ne $Checked) {
        foreach ($r in @($Checked)) {
            if ($r.module -in @('cleanup', 'startup', 'buffer', 'oem')) { continue }
            if ($r.blocked -or $r.na) { continue }
            $tot++
            if ($r.ok) { $ok++ }
            if ($r.module -eq 'etw') { $etwTotal++; if ($r.ok) { $etwOff++ } }
        }
    } else {
        foreach ($d in $script:Defs) {
            if ($d.M -in @('cleanup', 'startup', 'buffer', 'oem')) { continue }
            $r = Check-Def $d
            $tot++
            if ($r.ok) { $ok++ }
            if ($d.M -eq 'etw') { $etwTotal++; if ($r.ok) { $etwOff++ } }
        }
    }
    $dnsEvidence = $(if ($null -ne $Dns) { @($Dns) } else { @(Get-DnsEvidence) })
    $buf = Get-BufferInfo
    $fw = @(Get-NetFirewallRule -Group $script:FwGroup -ErrorAction SilentlyContinue).Count
    $startOn = 0; $startBad = 0
    try {
        $stAll = @(Get-StartupList)
        $startOn  = @($stAll | Where-Object { $_.enabled }).Count
        $startBad = @($stAll | Where-Object { $_.enabled -and $_.advise }).Count
    } catch { }
    $base = Load-Json 'xray-baseline.json'
    $tasks = 0
    try {
        foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
            if (($t.TaskPath + $t.TaskName) -match 'Appraiser|Consolidator|UsbCeip|DmClient|QueueReporting|ProgramDataUpdater|KernelCeip|Sqm-Tasks|GatherNetworkInfo|Device Information') {
                if ($t.State -ne 'Disabled') { $tasks++ }
            }
        }
    } catch { }
    return @{
        time       = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        ok         = $ok
        total      = $tot
        dnsBlocked = @($dnsEvidence | Where-Object { $_.blocked }).Count
        dnsOpen    = @($dnsEvidence | Where-Object { -not $_.blocked }).Count
        bufferMb   = $buf.mb
        bufferFiles= $buf.files
        fwRules    = $fw
        etwOff     = $etwOff
        etwTotal   = $etwTotal
        tasksLive  = $tasks
        startupOn  = $startOn
        startupBad = $startBad
        xrayPerDay = $(if ($base -and $base.perDay) { [int]$base.perDay } else { 0 })
        diagTrack  = $(try { [string](Get-Service DiagTrack -ErrorAction Stop).StartType } catch { 'нет' })
    }
}

if ($ProofSave) {
    $snap = Get-ProofSnapshot
    Save-Json 'proof-before.json' $snap
    Emit-Json $snap
    exit 0
}

if ($Proof) {
    $before = Load-Json 'proof-before.json'
    $after = Get-ProofSnapshot
    $xrayNow = 0
    $xr = Load-Json 'xray-last.json'
    if ($xr -and $xr.perDay) { $xrayNow = [int]$xr.perDay }
    Emit-Json @{ before = $before; after = $after; xrayNow = $xrayNow
                 has = [bool]$before }
    exit 0
}

# =========================================================================== #
#  САМОПРОВЕРКА: может ли программа реально менять настройки на этом ПК
# =========================================================================== #
if ($SelfTest) {
    Write-Section 'Самопроверка: может ли программа менять настройки'
    $r = @{}
    $r.admin = Test-Admin
    Write-Log ("   пользователь          : {0}" -f $env:USERNAME)
    Write-Log ("   права администратора  : {0}" -f $(if ($r.admin) { 'ЕСТЬ' } else { 'НЕТ  <-- изменения невозможны' }))
    Write-Log ("   PowerShell            : {0}" -f $PSVersionTable.PSVersion)
    Write-Log ("   политика выполнения   : {0}" -f (Get-ExecutionPolicy))
    Write-Log ("   файл движка           : {0}" -f $PSCommandPath)
    Write-Log ''

    # --- реестр пользователя (HKCU) ---
    $r.hkcu = $false
    try {
        $k = 'HKCU:\Software\Win11Privacy\SelfTest'
        if (-not (Test-Path -LiteralPath $k)) { New-Item -Path $k -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $k -Name 'Probe' -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        $r.hkcu = ((Get-ItemProperty -LiteralPath $k -Name 'Probe' -ErrorAction Stop).Probe -eq 1)
        Remove-Item -LiteralPath 'HKCU:\Software\Win11Privacy' -Recurse -Force -ErrorAction SilentlyContinue
    } catch { Write-Log ("   [!] {0}" -f $_.Exception.Message) }
    Write-Log ("   [{0}] запись в реестр пользователя (HKCU)" -f $(if ($r.hkcu) { '+' } else { '!' }))

    # --- реестр системы (HKLM) ---
    $r.hklm = $false
    try {
        $k = 'HKLM:\SOFTWARE\Win11Privacy\SelfTest'
        if (-not (Test-Path -LiteralPath $k)) { New-Item -Path $k -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $k -Name 'Probe' -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        $r.hklm = ((Get-ItemProperty -LiteralPath $k -Name 'Probe' -ErrorAction Stop).Probe -eq 1)
        Remove-Item -LiteralPath 'HKLM:\SOFTWARE\Win11Privacy' -Recurse -Force -ErrorAction SilentlyContinue
    } catch { Write-Log ("   [!] {0}" -f $_.Exception.Message) }
    Write-Log ("   [{0}] запись в реестр системы (HKLM) — сюда идут политики" -f $(if ($r.hklm) { '+' } else { '!' }))

    # --- резервная копия на рабочий стол ---
    $r.backup = $false
    $root = if ($BackupRoot) { $BackupRoot } else { [Environment]::GetFolderPath('Desktop') }
    Write-Log ("   папка для копий       : {0}" -f $root)
    try {
        $probeDir = Join-Path $root ('Win11Privacy-SelfTest-' + (Get-Date -Format 'HHmmss'))
        New-Item -ItemType Directory -Path $probeDir -Force -ErrorAction Stop | Out-Null
        $probeFile = Join-Path $probeDir 'probe.reg'
        $null = & reg.exe export 'HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' "$probeFile" /y 2>&1
        $r.backup = (Test-Path -LiteralPath $probeDir)
        Remove-Item -LiteralPath $probeDir -Recurse -Force -ErrorAction SilentlyContinue
    } catch { Write-Log ("   [!] {0}" -f $_.Exception.Message) }
    Write-Log ("   [{0}] создание папки резервной копии" -f $(if ($r.backup) { '+' } else { '!' }))

    # --- службы, задачи, брандмауэр, hosts ---
    $r.services = $false
    try { $null = Get-Service -Name 'DiagTrack' -ErrorAction Stop; $r.services = $true } catch { }
    Write-Log ("   [{0}] доступ к службам" -f $(if ($r.services) { '+' } else { '-' }))

    $r.tasks = $false
    try { $null = Get-ScheduledTask -ErrorAction Stop | Select-Object -First 1; $r.tasks = $true } catch { }
    Write-Log ("   [{0}] доступ к планировщику задач" -f $(if ($r.tasks) { '+' } else { '!' }))

    $r.firewall = [bool](Get-Command New-NetFirewallRule -ErrorAction SilentlyContinue)
    Write-Log ("   [{0}] управление брандмауэром" -f $(if ($r.firewall) { '+' } else { '!' }))

    $r.hosts = $false
    try {
        $fs = [IO.File]::Open($script:HostsPath, 'Open', 'ReadWrite', 'ReadWrite')
        $fs.Close(); $r.hosts = $true
    } catch { Write-Log ("   [!] hosts: {0}" -f $_.Exception.Message) }
    Write-Log ("   [{0}] файл hosts доступен для записи" -f $(if ($r.hosts) { '+' } else { '!' }))

    Write-Log ''
    $bad = @()
    if (-not $r.admin)  { $bad += 'нет прав администратора' }
    if (-not $r.hklm)   { $bad += 'нельзя писать в реестр системы' }
    if (-not $r.backup) { $bad += 'нельзя создать папку резервной копии' }
    if ($bad.Count -eq 0) {
        Write-Log 'ИТОГ: всё работает — программа может применять настройки на этом компьютере.'
        Write-Log 'Если изменения всё равно не применяются, пришлите этот журнал целиком.'
    } else {
        Write-Log ('ИТОГ: мешает — ' + ($bad -join '; ') + '.')
        Write-Log 'Скорее всего программу блокирует антивирус или она запущена без прав администратора.'
    }
    Emit-Json $r
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  Audit
# =========================================================================== #
if ($Audit) {
    if ($Modules.Count -eq 0) { $Modules = $script:ModuleOrder }
    # Проверка идёт до полуминуты и раньше молчала до самого ответа: окно
    # показывало бегущую полосу, по которой не понять, идёт работа или нет.
    $planned = @($script:Defs | Where-Object { ($Modules -contains $_.M) -and ($SkipItems -notcontains $_.Id) })
    $script:AuditTotal = $planned.Count
    $script:AuditDone = 0
    $items = @()
    $oemInfo = $null
    $blockedSet = @{}
    $bj = Load-Json 'blocked.json'
    if ($bj -and $bj.ids) { foreach ($i in @($bj.ids)) { $blockedSet["$i"] = $true } }
    foreach ($d in $script:Defs) {
        if ($Modules -notcontains $d.M) { continue }
        if ($SkipItems -contains $d.Id) { continue }
        $r = Check-Def $d
        $script:AuditDone++
        # интерфейс читает эти строки и показывает честный ход работы
        if ($script:AuditTotal -gt 0 -and ($script:AuditDone % 5 -eq 0 -or $script:AuditDone -eq $script:AuditTotal)) {
            Write-Host ("###PROGRESS### {0}/{1} {2}" -f $script:AuditDone, $script:AuditTotal, $script:ModuleTitles[$d.M])
        }
        $r.id = $d.Id
        # Windows не отдала этот параметр при применении — это не «не применено»
        # «нет на этой версии Windows» важнее записанного отказа: это причина
        # честнее и не зависит от того, что когда-то не отдалось
        $r.blocked = [bool]((-not $r.ok) -and (-not $r.na) -and $blockedSet.ContainsKey($d.Id))
        if ($r.blocked) { $r.actual = 'Windows не разрешает' }
        if (-not $r.ContainsKey('na')) { $r.na = $false }
        $items += $r
    }
    if ($Modules -contains 'oem') {
        $oemInfo = Detect-Oem
        foreach ($it in $oemInfo.items) {
            $ok = ($it.state -match 'Disabled')
            $items += @{ module='oem'; name=("{0}: {1}" -f $(if ($it.type -eq 'svc') { 'служба' } else { 'задача' }), $it.display); ok=$ok; expected='Disabled'; actual=$it.state }
        }
    }
    $counted = @($items | Where-Object { (-not $_.blocked) -and (-not $_.na) })
    $okCount = @($counted | Where-Object { $_.ok }).Count
    $blockedCount = @($items | Where-Object { $_.blocked }).Count
    $naCount = @($items | Where-Object { $_.na }).Count
    $groups = @()
    foreach ($m in $script:ModuleOrder) {
        $mi = @($items | Where-Object { $_.module -eq $m })
        if ($mi.Count -eq 0) { continue }
        $mc = @($mi | Where-Object { (-not $_.blocked) -and (-not $_.na) })
        $groups += @{ module=$m; title=$script:ModuleTitles[$m]; ok=@($mc | Where-Object { $_.ok }).Count; total=$mc.Count
                      blocked=@($mi | Where-Object { $_.blocked }).Count; items=$mi }
    }
    $dnsList = @(Get-DnsEvidence)
    $result = @{
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); ok = $okCount; total = $counted.Count
        blocked = $blockedCount; notApplicable = $naCount; groups = $groups
        dns = $dnsList; buffer = (Get-BufferInfo); edition = (Get-Edition); doh = (Get-DohStatus)
        monitorEnabled = (Get-MonitorEnabled); hostsBlocked = (Test-HostsBlock)
        junk = @(Find-JunkValues).Count
    }
    # Доказательство результата в том же прогоне: интерфейсу больше не нужно
    # звать -Proof отдельно, а значит все проверки выполняются один раз.
    if ($WithProof) {
        $proofItems = New-Object System.Collections.Generic.List[object]
        foreach ($it in $items) { $proofItems.Add($it) }
        foreach ($d in $script:Defs) {
            if (($Modules -contains $d.M) -and ($SkipItems -notcontains $d.Id)) { continue }   # уже посчитан выше
            $proofItems.Add((Check-Def $d))
        }
        $xr = Load-Json 'xray-last.json'
        $result.proof = @{
            before  = (Load-Json 'proof-before.json')
            after   = (Get-ProofSnapshot -Checked $proofItems.ToArray() -Dns $dnsList)
            has     = [bool](Load-Json 'proof-before.json')
            xrayNow = $(if ($xr -and $xr.perDay) { [int]$xr.perDay } else { 0 })
        }
    }
    Emit-Json $result
    exit 0
}

# =========================================================================== #
#  ОТКАТ ПО ЖУРНАЛУ
#  Возвращает каждый параметр реестра в то значение, которое было до нас.
# =========================================================================== #
# --------------------------------------------------------------------------- #
#  Другие пользователи и профиль по умолчанию. Настройки из HKCU касаются
#  только вошедшего. С -AllProfiles они ложатся и в кусты других профилей
#  этого компьютера, и в профиль Default — его копию получает каждый новый
#  пользователь. Не загруженный куст подключается на время записи.
# --------------------------------------------------------------------------- #
function Get-OtherProfiles {
    $me = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $out = New-Object System.Collections.Generic.List[object]
    $out.Add(@{ name = 'Default'; sid = ''; file = (Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT') })
    foreach ($p in @(Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue)) {
        if ($p.Special -or -not $p.LocalPath -or "$($p.SID)" -eq $me -or "$($p.SID)" -notlike 'S-1-5-21-*') { continue }
        $out.Add(@{ name = (Split-Path $p.LocalPath -Leaf); sid = "$($p.SID)"; file = (Join-Path $p.LocalPath 'NTUSER.DAT') })
    }
    return @($out | Where-Object { Test-Path -LiteralPath $_.file })
}

# Выполняет $Body с корнем куста профиля. Вошедший пользователь — его куст уже
# загружен; иначе файл NTUSER.DAT подключается под временным именем и
# отключается обратно.
function Use-ProfileHive {
    param($Prof, [scriptblock]$Body)
    if ($Prof.sid -and (Test-Path -LiteralPath ('Registry::HKEY_USERS\' + $Prof.sid))) {
        $null = & $Body ('Registry::HKEY_USERS\' + $Prof.sid); return $true
    }
    $mount = 'W11P_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $null = & reg.exe load "HKU\$mount" "$($Prof.file)" 2>&1
    if ($LASTEXITCODE -ne 0) { return $false }
    try { $null = & $Body ('Registry::HKEY_USERS\' + $mount) }
    finally {
        # пока живы ссылки на ключи, куст не отключится
        for ($i = 0; $i -lt 6; $i++) {
            [gc]::Collect(); [gc]::WaitForPendingFinalizers()
            $null = & reg.exe unload "HKU\$mount" 2>&1
            if ($LASTEXITCODE -eq 0) { break }
            Start-Sleep -Milliseconds 500
        }
    }
    return $true
}

function Apply-ProfilesHives {
    $defs = @($script:Defs | Where-Object { ($Modules -contains $_.M) -and ($SkipItems -notcontains $_.Id) -and
                                            ($script:RegTypes -contains $_.T) -and "$($_.P)" -like 'HKCU:\*' -and (Test-DefApplicable $_) })
    if ($defs.Count -eq 0) { return }
    Write-Section 'Другие пользователи и профиль по умолчанию'
    foreach ($pr in @(Get-OtherProfiles)) {
        if ($DryRun) { Write-Log ("   [тест] профиль {0}: настроек {1}" -f $pr.name, $defs.Count); continue }
        $cnt = @{ changed = 0; failed = 0 }
        $mounted = Use-ProfileHive $pr {
            param($root)
            foreach ($d in $defs) {
                $sub = ("$($d.P)" -replace '^HKCU:\\', '')
                $kp = "$root\$sub"
                $cur = Get-RegValue $kp $d.N
                if ($null -ne $cur -and "$cur" -eq "$($d.V)") { continue }
                try {
                    if (-not (Test-Path -LiteralPath $kp)) { New-Item -Path $kp -Force -ErrorAction Stop | Out-Null }
                    New-ItemProperty -LiteralPath $kp -Name $d.N -Value $d.V -PropertyType $d.Type -Force -ErrorAction Stop | Out-Null
                    $script:Journal.Add(@{ kind = 'hive'; file = $pr.file; sid = $pr.sid; profile = $pr.name; sub = $sub
                                           name = $d.N; type = $d.Type; existed = ($null -ne $cur)
                                           old = $(if ($null -ne $cur) { $cur } else { '' }); newValue = "$($d.V)"; time = (Get-Date).ToString('s') })
                    $cnt.changed++
                } catch { $cnt.failed++ }
            }
        }
        if (-not $mounted) { Write-Log ("   [!] профиль {0}: куст не подключился (пользователь занят или файл недоступен)" -f $pr.name); $script:Failures++; continue }
        Write-Log ("   [+] профиль {0}: изменено настроек {1}{2}" -f $pr.name, $cnt.changed, $(if ($cnt.failed) { ", не удалось $($cnt.failed)" } else { '' }))
        $script:Changes += $cnt.changed; $script:Failures += $cnt.failed
    }
    Save-JournalEntries -Quiet
}

# Возвращает одну запись другого профиля в то, что было до программы
function Restore-HiveEntry {
    param($Entry)
    $res = @{ ok = $false; error = '' }
    $mounted = Use-ProfileHive @{ name = "$($Entry.profile)"; sid = "$($Entry.sid)"; file = "$($Entry.file)" } {
        param($root)
        $kp = "$root\$($Entry.sub)"
        try {
            if ($Entry.existed) {
                if (-not (Test-Path -LiteralPath $kp)) { New-Item -Path $kp -Force -ErrorAction Stop | Out-Null }
                New-ItemProperty -LiteralPath $kp -Name $Entry.name -Value $Entry.old -PropertyType $Entry.type -Force -ErrorAction Stop | Out-Null
            } else { Remove-ItemProperty -LiteralPath $kp -Name $Entry.name -Force -ErrorAction SilentlyContinue }
            $res.ok = $true
        } catch { $res.error = $_.Exception.Message }
    }
    if (-not $mounted) { $res.error = 'куст профиля не подключился' }
    return $res
}

function Restore-Journal {
    if (-not (Test-DataTrusted)) {
        Write-Log '   [!] папка данных программы не защищена от подмены -- журналу отката сейчас нельзя верить, ничего не возвращаем'
        $script:Failures++
        return @{ restored = 0; failed = 0 }
    }
    $jf = Read-JournalFile
    if ($jf.items.Count -eq 0) { Write-Log '   [-] журнал пуст — возвращать нечего'; return @{ restored = 0; failed = 0; legacy = $jf.legacy } }
    # Журнал идёт от старых записей к новым, и про каждый параметр нужна
    # первая: она помнит состояние до нас. Раньше список переворачивался, и у
    # журнала с повторами (версии до схлопывания) возвращалось то значение,
    # которое программа сама же записала в прошлый раз.
    $ok = 0; $seen = @{}; $startBack = 0; $svcBack = 0
    $failed = New-Object System.Collections.Generic.List[object]
    foreach ($e in @($jf.items)) {
        # записи автозагрузки возвращаем тем же способом, каким гасили
        if ("$($e.kind)" -eq 'startup') {
            $key = "startup|$($e.id)"
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $r = Set-StartupState ([string]$e.id) ("$($e.old)" -eq 'On')
            if ($r.ok) { $startBack++ } else { $failed.Add($e) }
            continue
        }
        if ("$($e.kind)" -eq 'hive') {
            $key = Get-JournalKey (ConvertTo-Fields $e)
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $r = Restore-HiveEntry $e
            if ($r.ok) { $ok++ } else { $failed.Add($e) }
            continue
        }
        $kind = "$($e.kind)"
        if ($kind -notin @('reg', 'svc', 'task', 'env')) { continue }
        $key = Get-JournalKey (ConvertTo-Fields $e)
        if ($seen.ContainsKey($key)) { continue }      # только самое раннее состояние
        $seen[$key] = $true
        $r = Restore-JournalEntry $e
        if (-not $r.ok) { $failed.Add($e); Write-Log ("   [!] не вернулось: {0} -- {1}" -f $key, $r.error); continue }
        if ($kind -eq 'reg') { $ok++ } else { $svcBack++ }
    }
    $bad = $failed.Count
    Write-Log ("   [+] возвращено параметров реестра: {0}" -f $ok)
    if ($svcBack -gt 0) { Write-Log ("   [+] возвращено служб, задач и переменных среды: {0}" -f $svcBack) }
    if ($startBack -gt 0) { Write-Log ("   [+] возвращено записей автозагрузки: {0}" -f $startBack) }
    # Что вернуть не удалось, остаётся в журнале: раньше он стирался целиком,
    # даже когда откат прошёл не весь, и вторая попытка была невозможна.
    # Пустой журнал остаётся файлом: по нему видно, что он нового образца.
    if ($bad -gt 0) { Write-Log ("   [!] не удалось вернуть: {0} -- эти записи остались в журнале" -f $bad) }
    try { Use-JournalLock { Write-JournalFile $failed.ToArray() $jf.legacy } }
    catch { Write-Log ("   [!] журнал отката не переписался: {0}" -f $_.Exception.Message); $script:Failures++ }
    return @{ restored = $ok + $svcBack; startup = $startBack; failed = $bad; legacy = $jf.legacy }
}

# --------------------------------------------------------------------------- #
#  Журнал изменений в человеческом виде. Записи группируются по ключу: важно
#  самое раннее состояние — именно его вернёт откат. Название берём из
#  описания настройки, чтобы в списке было «уровень телеметрии», а не путь.
# --------------------------------------------------------------------------- #
function Get-ChangeGroups {
    $j = Load-Json 'changes.json'
    if (-not $j -or -not $j.items) { return @() }
    $byPath = @{}
    foreach ($d in $script:Defs) {
        if ($script:RegTypes -notcontains $d.T) { continue }
        $k = ("{0}|{1}" -f $d.P, $d.N).ToLowerInvariant()
        if (-not $byPath.ContainsKey($k)) { $byPath[$k] = @{ title = [string]$d.C; module = [string]$d.M } }
    }
    $order = New-Object System.Collections.Generic.List[string]
    $groups = @{}
    foreach ($e in @($j.items)) {
        $kind = "$($e.kind)"
        if ($kind -eq 'startup') {
            $key = 'startup|' + "$($e.id)"
            $title = $(if ("$($e.name)") { "$($e.name)" } else { "$($e.id)" })
            $where = 'автозагрузка'
            $was = $(if ("$($e.old)" -eq 'On') { 'запускалась' } else { 'была отключена' })
            $now = $(if ("$($e.newValue)" -eq 'On') { 'запускается' } else { 'отключена' })
        } elseif ($kind -eq 'hive') {
            # настройка другого профиля: называется так же, как своя, а где — видно по профилю
            $key = Get-JournalKey (ConvertTo-Fields $e)
            $pk = ("HKCU:\{0}|{1}" -f "$($e.sub)", "$($e.name)").ToLowerInvariant()
            $title = $(if ($byPath.ContainsKey($pk)) { $byPath[$pk].title } else { "$($e.name)" })
            $where = ("профиль {0}: {1}" -f "$($e.profile)", "$($e.sub)")
            $was = $(if ($e.existed) { "$($e.old)" } else { 'не было' })
            $now = "$($e.newValue)"
        } elseif ($kind -in @('svc', 'task', 'env')) {
            $key = Get-JournalKey (ConvertTo-Fields $e)
            $target = $(if ($kind -eq 'task') { "$($e.path)" } else { "$($e.name)" })
            $def = @($script:Defs | Where-Object { "$($_.P)" -eq $target -and (
                        ($kind -eq 'svc' -and $_.T -in @('svc', 'svcopt')) -or ($kind -eq 'task' -and $_.T -eq 'task') -or ($kind -eq 'env' -and $_.T -eq 'env')) } | Select-Object -First 1)
            $title = $(if ($def.Count -gt 0) { [string]$def[0].C } elseif ($kind -eq 'task') { Split-Path $target -Leaf } else { $target })
            if ($kind -eq 'svc') {
                $where = 'службы Windows'
                $was = Get-StartName "$($e.old)" "$($e.delayed)"
                $now = Get-StartName "$($e.newValue)"
            } elseif ($kind -eq 'task') {
                $where = 'планировщик задач'
                $was = 'включена'; $now = 'отключена'
            } else {
                $where = 'переменные среды'
                $was = $(if ($e.existed) { "$($e.old)" } else { 'не было' })
                $now = "$($e.newValue)"
            }
        } else {
            $key = ("reg|{0}|{1}" -f "$($e.path)", "$($e.name)").ToLowerInvariant()
            $pk = ("{0}|{1}" -f "$($e.path)", "$($e.name)").ToLowerInvariant()
            $title = $(if ($byPath.ContainsKey($pk)) { $byPath[$pk].title } else { "$($e.name)" })
            $where = "$($e.path)"
            $was = $(if ($e.existed) { "$($e.old)" } else { 'не было' })
            $now = "$($e.newValue)"
        }
        # у схлопнутой записи число правок лежит в ней самой
        $times = [int]$(if ($e.PSObject.Properties['count'] -and [int]$e.count -gt 0) { $e.count } else { 1 })
        $when = $(if ($e.PSObject.Properties['lastTime'] -and "$($e.lastTime)") { "$($e.lastTime)" } else { "$($e.time)" })
        if (-not $groups.ContainsKey($key)) {
            $order.Add($key)
            $groups[$key] = @{ id = (ConvertTo-StartupId $key); kind = $kind; title = $title
                               where = $where; was = $was; now = $now
                               time = $when; count = $times }
        } else {
            # самое раннее «было» уже записано, обновляем только текущее значение
            $groups[$key].now = $now
            $groups[$key].time = $when
            $groups[$key].count = [int]$groups[$key].count + $times
        }
    }
    $out = @()
    foreach ($k in $order) { $out += $groups[$k] }
    [array]::Reverse($out)          # свежие изменения сверху
    return $out
}

# Возвращает одну запись журнала и убирает её из changes.json
function Restore-ChangeKey {
    param([string]$Key)
    if (-not (Test-DataTrusted)) { return @{ ok = $false; error = 'папка данных программы не защищена от подмены' } }
    $jf = Read-JournalFile
    if ($jf.items.Count -eq 0) { return @{ ok = $false; error = 'журнал пуст' } }
    $mine = @(); $rest = @()
    foreach ($e in $jf.items) {
        $k = Get-JournalKey (ConvertTo-Fields $e)
        if ($k -eq $Key) { $mine += $e } else { $rest += $e }
    }
    if ($mine.Count -eq 0) { return @{ ok = $false; error = 'запись не найдена' } }
    $first = $mine[0]              # самое раннее состояние
    if ("$($first.kind)" -eq 'startup') {
        $r = Set-StartupState ([string]$first.id) ("$($first.old)" -eq 'On')
    } elseif ("$($first.kind)" -eq 'hive') {
        $r = Restore-HiveEntry $first
    } else {
        $r = Restore-JournalEntry $first
    }
    if (-not $r.ok) { return @{ ok = $false; error = "$($r.error)" } }
    try { Use-JournalLock { Write-JournalFile $rest $jf.legacy } }
    catch { return @{ ok = $false; error = ('возвращено, но журнал не переписался: ' + $_.Exception.Message) } }
    return @{ ok = $true }
}

if ($ChangeLog) {
    $chg = @(Get-ChangeGroups)
    $j = Load-Json 'changes.json'
    Emit-Json @{ items = $chg; count = $chg.Count
                 raw = $(if ($j -and $j.items) { @($j.items).Count } else { 0 })
                 updated = $(if ($j) { "$($j.updated)" } else { '' }) }
    exit 0
}

if ($RestoreItems) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Emit-Json @{ error='нужны права администратора' }; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Возврат выбранных изменений'
    if ($ChangeItems.Count -eq 0) { Write-Log '   [-] ничего не выбрано'; Emit-Json @{ restored = 0 }; Write-Log '###DONE###'; exit 0 }
    $done = 0
    foreach ($id in $ChangeItems) {
        $key = ConvertFrom-StartupId $id
        if (-not $key) { Write-Log ("   [!] непонятная запись: {0}" -f $id); $script:Failures++; continue }
        $r = Restore-ChangeKey $key
        if ($r.ok) { Write-Log ("   [+] возвращено: {0}" -f $key); $done++; $script:Changes++ }
        else { Write-Log ("   [!] {0} -- {1}" -f $key, $r.error); $script:Failures++ }
    }
    Write-Log ("   возвращено записей: {0}" -f $done)
    Emit-Json @{ restored = $done; failures = $script:Failures }
    Write-Log '###DONE###'
    exit 0
}

# --------------------------------------------------------------------------- #
#  Номер устройства: состояние, смена, возврат как было
# --------------------------------------------------------------------------- #
if ($GdidStatus) { Emit-Json (Get-GdidStatus); exit 0 }

if ($GdidReissue) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Смена номера устройства'
    $lockedNow = Test-HostsBlock -Kind 'lock'
    if ($lockedNow) { Write-Log '   [i] сервер выдачи закрыт: после стирания нового номера Windows не получит' }
    $wiped = Invoke-GdidWipe
    if ($wiped -and -not $lockedNow) {
        Write-Log '   [i] Новый номер Windows получит при следующем обращении к учётной записи Microsoft (Магазин, Параметры) или после перезагрузки.'
        Write-Log '   [i] Магазин, Xbox и OneDrive могут попросить войти заново.'
    }
    Emit-Json (Get-GdidStatus)
    Write-Log '###DONE###'
    exit 0
}

if ($GdidRestore) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Номер устройства: вернуть как было'
    # тип запуска служб — по журналу: ровно то, что было до программы
    foreach ($n in @('CDPSvc', 'CDPUserSvc', 'DoSvc')) {
        $r = Restore-ChangeKey (("reg|HKLM:\SYSTEM\CurrentControlSet\Services\{0}|Start" -f $n).ToLowerInvariant())
        if ($r.ok) { Write-Log ("   [+] служба {0}: тип запуска возвращён" -f $n); $script:Changes++ }
        else { Write-Log ("   [-] служба {0}: программа её не меняла" -f $n) }
    }
    Remove-HostsBlock -Kind 'gdid'
    Remove-HostsBlock -Kind 'lock'
    try { Remove-NetFirewallRule -DisplayName (Get-FwRuleName 'svc' 'wlidsvc') -ErrorAction Stop; Write-Log '   [+] правило брандмауэра для wlidsvc снято' }
    catch { Write-Log '   [-] правила брандмауэра для wlidsvc не было' }
    # иначе страж тут же поставил бы всё обратно
    $prof = Load-Json 'profile.json'
    if ($prof -and $prof.modules -and @(@($prof.modules) | Where-Object { $_ -in @('gdid', 'gdidlock') }).Count -gt 0) {
        $profSkip = @($(if ($prof.PSObject.Properties['skip']) { @($prof.skip) } else { @() }))
        Save-Json 'profile.json' @{ version = 1; modules = @(@($prof.modules) | Where-Object { $_ -notin @('gdid', 'gdidlock') })
                                    skip = $profSkip; created = "$($prof.created)" }
        Write-Log '   [+] страж больше не следит за номером устройства'
    }
    if ((Get-SvcStart 'CDPSvc') -ne 4) { try { Start-Service CDPSvc -ErrorAction Stop } catch { } }
    Write-Log '   [i] Стёртый раньше номер не вернётся: Windows получит новый при следующем обращении к учётной записи Microsoft.'
    Emit-Json (Get-GdidStatus)
    Write-Log '###DONE###'
    exit 0
}

# --------------------------------------------------------------------------- #
#  Что программа накопила о вас у себя. Для программы про приватность честно
#  показывать и свои файлы — и уметь их стереть.
# --------------------------------------------------------------------------- #
$script:DataFiles = @(
    @{ file = 'sensor-history.json'; title = 'История датчиков по дням: кто включал камеру, микрофон и геолокацию' },
    @{ file = 'sensor-apps.json';    title = 'Список программ, которым доступ к датчикам уже известен' },
    @{ file = 'startup-known.json';  title = 'Известные записи автозагрузки — по ним страж замечает новые' },
    @{ file = 'changes.json';        title = 'Журнал изменений: что программа поменяла и что было до неё' },
    @{ file = 'proof-before.json';   title = 'Снимок «до»: состояние системы перед первым применением' },
    @{ file = 'xray-last.json';      title = 'Последний результат рентгена телеметрии' },
    @{ file = 'xray-baseline.json';  title = 'Эталон рентгена: сколько событий уходило до настройки' },
    @{ file = 'profile.json';        title = 'Профиль стража: какие разделы он сторожит' },
    @{ file = 'guard-last.json';     title = 'Последняя проверка стража' },
    @{ file = 'guard.log';           title = 'Журнал работы стража' },
    @{ file = 'net-apps.json';       title = 'Программы, выходившие в сеть, — по ним слежение замечает новые' }
)

function Get-DataFiles {
    $out = @()
    $seen = @{}
    foreach ($d in $script:DataFiles) {
        $seen[$d.file] = $true
        $full = Join-Path $script:DataDir $d.file
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $fi = Get-Item -LiteralPath $full -ErrorAction SilentlyContinue
        if (-not $fi) { continue }
        $out += @{ file = $d.file; title = $d.title; kb = [math]::Round($fi.Length / 1KB, 1)
                   changed = $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }
    }
    # снимки состояния и всё прочее, что могло появиться рядом
    if (Test-Path -LiteralPath $script:DataDir) {
        foreach ($fi in @(Get-ChildItem -LiteralPath $script:DataDir -File -ErrorAction SilentlyContinue)) {
            if ($seen.ContainsKey($fi.Name)) { continue }
            if ($fi.Name -like 'engine*.ps1') { continue }   # это сам движок для стража, не данные
            $out += @{ file = $fi.Name; title = 'Снимок состояния или служебный файл'
                       kb = [math]::Round($fi.Length / 1KB, 1)
                       changed = $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }
        }
    }
    return @($out | Sort-Object { -[double]$_.kb })
}

if ($DataInfo) {
    $dataList = @(Get-DataFiles)
    $sum = 0.0
    foreach ($d in $dataList) { $sum += [double]$d.kb }
    Emit-Json @{ items = $dataList; count = $dataList.Count; kb = [math]::Round($sum, 1)
                 folder = $script:DataDir }
    exit 0
}

if ($PurgeData) {
    Write-Section 'Удаление данных программы'
    $dataList = @(Get-DataFiles)
    if ($dataList.Count -eq 0) { Write-Log '   [-] программа ничего о вас не хранит'; Emit-Json @{ removed = 0 }; Write-Log '###DONE###'; exit 0 }
    $gone = 0
    foreach ($d in $dataList) {
        $full = Join-Path $script:DataDir $d.file
        if ($DryRun) { Write-Log ("   [тест] {0}" -f $d.file); continue }
        try { Remove-Item -LiteralPath $full -Force -ErrorAction Stop; Write-Log ("   [+] удалён: {0}" -f $d.file); $gone++ }
        catch { Write-Log ("   [!] не удалось удалить {0} -- {1}" -f $d.file, $_.Exception.Message); $script:Failures++ }
    }
    Write-Log ("   удалено файлов: {0}" -f $gone)
    Write-Log '   Журнал отката тоже стёрт — вернуть настройки «как было» программа больше не сможет.'
    Emit-Json @{ removed = $gone }
    Write-Log '###DONE###'
    exit 0
}

if ($RestoreAll) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Возврат настроек реестра по журналу'
    $r = Restore-Journal
    Emit-Json $r
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  Revert (откат)
# =========================================================================== #
if ($Revert) {
    Write-Log 'ОТКАТ ИЗМЕНЕНИЙ'
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Write-Log '###DONE###'; exit 1 }

    Write-Section 'Настройки реестра, службы, задачи'; $rj = Restore-Journal
    # Журнал прежних версий (или его нет вовсе) не знает, какими были службы,
    # задачи и переменные среды до программы. Только для него — прежний откат
    # «по умолчанию», и только для того, что сейчас выключено.
    $legacyRevert = [bool]$rj.legacy -or -not (Test-Path -LiteralPath (Join-Path $script:DataDir 'changes.json'))
    Write-Section 'Файл hosts'; Remove-HostsBlock
    Write-Section 'Брандмауэр'; Remove-FwRules
    Write-Section 'Монитор'; if (Get-MonitorEnabled) { Set-MonitorEnabled $false | Out-Null } else { Write-Log '   [-] журнал аудита не включён' }
    Write-Section 'Страж'
    try { Unregister-ScheduledTask -TaskName $script:GuardTask -Confirm:$false -ErrorAction Stop; Write-Log '   [+] задача стража удалена' } catch { Write-Log '   [-] стража нет' }
    try { Unregister-ScheduledTask -TaskName $script:SensorTask -Confirm:$false -ErrorAction Stop; Write-Log '   [+] слежение за датчиками удалено' } catch { Write-Log '   [-] слежения за датчиками нет' }
    try { Unregister-ScheduledTask -TaskName $script:NetTask -Confirm:$false -ErrorAction Stop; Write-Log '   [+] слежение за сетью удалено' } catch { Write-Log '   [-] слежения за сетью нет' }
    try { Unregister-ScheduledTask -TaskName 'Win11Privacy Watcher' -Confirm:$false -ErrorAction Stop; Write-Log '   [+] живые уведомления удалены' } catch { Write-Log '   [-] живых уведомлений нет' }

    if ($legacyRevert) {
        Write-Section 'Службы (журнал прежней версии)'
        foreach ($svc in @(@{N='DiagTrack';S='Automatic'}, @{N='dmwappushservice';S='Manual'}, @{N='NvTelemetryContainer';S='Automatic'}, @{N='InventorySvc';S='Automatic'})) {
            try {
                $s = Get-Service -Name $svc.N -ErrorAction Stop
                if ($s.StartType -ne 'Disabled') { continue }       # не выключена — не трогаем
                Set-Service -Name $svc.N -StartupType $svc.S -ErrorAction Stop; Write-Log "   [+] $($svc.N) -> $($svc.S)"
            } catch { Write-Log "   [-] $($svc.N) -- пропущено" }
        }
        Write-Section 'Задачи планировщика (журнал прежней версии)'
        foreach ($d in $script:Defs) {
            if ($d.T -eq 'task') {
                $pp = Split-TaskPath $d.P
                $st = Get-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction SilentlyContinue
                if (-not $st) { continue }
                if ($st.State -ne 'Disabled') { continue }
                if ((Set-TaskEnabled $d.P $true) -in @('ok', 'system')) { Write-Log "   [+] включена: $($pp[1])" } else { Write-Log "   [-] пропущена: $($pp[1])" }
            } elseif ($d.T -eq 'taskglob') {
                foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like $d.P -and $_.State -eq 'Disabled' })) {
                    try { Enable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null; Write-Log "   [+] включена: $($t.TaskName)" } catch { }
                }
            }
        }
    }
    Write-Section 'Компоненты производителя'
    $oemSaved = Load-Json 'oem-disabled.json'
    if ($oemSaved) {
        foreach ($it in @($oemSaved)) {
            try {
                if ($it.type -eq 'svc') { Set-Service -Name $it.name -StartupType $(if ($it.state -match 'Auto') { 'Automatic' } else { 'Manual' }) -ErrorAction Stop; Write-Log "   [+] служба $($it.name) -> $($it.state)" }
                else { $pp = Split-TaskPath $it.name; Enable-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop | Out-Null; Write-Log "   [+] задача $($pp[1]) включена" }
            } catch { Write-Log "   [-] $($it.name) -- пропущено" }
        }
        Remove-Item -LiteralPath (Join-Path $script:DataDir 'oem-disabled.json') -Force -ErrorAction SilentlyContinue
    } else { Write-Log '   [-] ничего не отключалось' }

    Write-Section 'Сторонние программы'
    # Переменные среды возвращает журнал. Журнал прежней версии их не знает:
    # тогда убираем только то, что стоит ровно в нашем значении.
    if ($legacyRevert) {
        foreach ($d in @($script:Defs | Where-Object { $_.T -eq 'env' })) {
            if ([string][Environment]::GetEnvironmentVariable($d.P, 'User') -ne [string]$d.V) { continue }
            try { [Environment]::SetEnvironmentVariable($d.P, $null, 'User'); Write-Log "   [+] переменная $($d.P) удалена" } catch { }
        }
    }
    foreach ($f in @((Get-VsCodeSettingsPath), (Get-FirefoxPoliciesPath))) {
        if ($f -and (Test-Path -LiteralPath "$f.win11privacy.bak")) {
            try { Copy-Item -LiteralPath "$f.win11privacy.bak" -Destination $f -Force -ErrorAction Stop; Remove-Item -LiteralPath "$f.win11privacy.bak" -Force -ErrorAction SilentlyContinue; Write-Log "   [+] восстановлен: $f" } catch { }
        }
    }
    # Политики Chrome, Office и Visual Studio раньше удалялись целыми ветками —
    # вместе с корпоративными, которых программа не ставила. Это обычные
    # параметры реестра, и журнал уже вернул каждый из них как было.

    if ($legacyRevert) {
        # Самые старые версии ставили это без журнала. Снимаем, только если
        # стоит ровно наше значение.
        Write-Section 'Геолокация, Защитник, виджеты (журнал прежней версии)'
        foreach ($rv in @(
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'; N='DisableLocation'; V='1' },
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'; N='DisableWindowsLocationProvider'; V='1' },
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice'; N='AllowFindMyDevice'; V='0' },
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'; N='SpyNetReporting'; V='0' },
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'; N='SubmitSamplesConsent'; V='2' },
            @{ P='HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; N='AllowNewsAndInterests'; V='0' })) {
            if ("$(Get-RegValue $rv.P $rv.N)" -ne $rv.V) { continue }
            try { Remove-ItemProperty -LiteralPath $rv.P -Name $rv.N -Force -ErrorAction Stop; Write-Log "   [+] снято: $($rv.N)" } catch { }
        }
        $locKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
        if ("$(Get-RegValue $locKey 'Value')" -eq 'Deny') {
            try { New-ItemProperty -LiteralPath $locKey -Name 'Value' -Value 'Allow' -PropertyType String -Force -ErrorAction Stop | Out-Null; Write-Log '   [+] доступ к местоположению возвращён (Allow)' } catch { }
        }
    }

    Write-Section 'Данные программы'
    $left = @(Get-DataFiles)
    # копия движка для стража больше не нужна — задача уже удалена
    try { Remove-Item -LiteralPath $script:TaskEngine -Force -ErrorAction SilentlyContinue } catch { }
    try { Remove-Item -LiteralPath (Join-Path $script:DataDir 'engine.ps1') -Force -ErrorAction SilentlyContinue } catch { }
    if ($left.Count -eq 0) { Write-Log '   [-] программа ничего о вас не хранит' }
    else {
        foreach ($d in $left) {
            # что вернуть не удалось, остаётся в журнале для второй попытки
            if ($d.file -eq 'changes.json' -and [int]$rj.failed -gt 0) { Write-Log '   [-] журнал отката оставлен: в нём то, что вернуть не удалось'; continue }
            try { Remove-Item -LiteralPath (Join-Path $script:DataDir $d.file) -Force -ErrorAction Stop; Write-Log ("   [+] удалён: {0}" -f $d.file) }
            catch { Write-Log ("   [!] не удалось удалить {0}" -f $d.file) }
        }
    }

    Write-Log ''
    Write-Log 'Настройки реестра возвращены по журналу изменений — ручной импорт .reg больше не нужен.'
    Write-Log 'Папка резервной копии на рабочем столе остаётся как запасной вариант.'
    Write-Log 'Готово. Перезагрузите компьютер.'
    Write-Log '###DONE###'
    exit 0
}

# =========================================================================== #
#  ПРИМЕНЕНИЕ
# =========================================================================== #
if (-not (Test-Admin)) { Write-Log 'ОШИБКА: требуются права администратора.'; Write-Log '###DONE###'; exit 1 }

$osInfo = (Get-CimInstance Win32_OperatingSystem).Caption
$edInfo = Get-Edition
Write-Log "Система : $osInfo (сборка $([System.Environment]::OSVersion.Version.Build), редакция $($edInfo.id))"
Write-Log "Модули  : $($Modules -join ', ')"
if ($DryRun) { Write-Log 'РЕЖИМ ТЕСТА: изменения не применяются.' }
if ($edInfo.kind -ne 'enterprise' -and (Use-Module 'telemetry')) {
    Write-Log 'Примечание: на редакциях Home/Pro минимальный уровень телеметрии — «Обязательные данные»; полное отключение доступно только в Enterprise/Education.'
}

# --- Снимок «до» для доказательства результата -------------------------- #
if (-not $DryRun -and -not (Load-Json 'proof-before.json')) {
    try { Save-Json 'proof-before.json' (Get-ProofSnapshot); Write-Log 'Состояние «до» запомнено — потом покажем разницу.' } catch { }
}

$script:BackupEnabled = $true    # дальше идёт ручное применение

# Журнал отката должен писаться до первого изменения, а не выясниться в конце
if (-not (Test-JournalWritable)) {
    Write-Log 'ПРИМЕНЕНИЕ ОТМЕНЕНО: журнал отката не записывается, а без него изменения нельзя было бы вернуть. Система не тронута.'
    Write-Log '###DONE###'
    exit 1
}

# --- Уборка за старыми версиями --------------------------------------------- #
$junkFound = @(Find-JunkValues)
if ($junkFound.Count -gt 0) {
    Write-Section 'Уборка за старыми версиями программы'
    Write-Log ("   найдено параметров, записанных под числовыми именами: {0}" -f $junkFound.Count)
    $null = Remove-JunkValues
}

# Что делать, если настройки модуля не поддались: обходной путь тем же результатом
$script:ModuleHints = @{
    widgets = 'Ключи политики виджетов Windows не отдаёт. Тот же результат даёт удаление пакета «Виджеты и лента Microsoft Start» на странице «Приложения».'
}

# --- Модули по определениям ------------------------------------------------- #
foreach ($m in $script:ModuleOrder) {
    if (-not (Use-Module $m)) { continue }
    if ($m -in @('cleanup','startup','buffer','oem')) { continue }
    # ВАЖНО: имя переменной не должно совпадать с $script:Defs — в PowerShell
    # регистр не различается, и фильтрация затёрла бы весь список определений.
    $modDefs = @($script:Defs | Where-Object { $_.M -eq $m })
    if ($modDefs.Count -eq 0) { continue }
    Write-Section $script:ModuleTitles[$m]
    # Без сервера выдачи номера учётная запись Microsoft не работает вовсе —
    # при входе в Windows через неё запрет не ставим, а объясняем почему.
    if ($m -eq 'gdidlock' -and (Get-GdidLockRefusal)) {
        if ((Get-GdidLockRefusal) -eq 'msa') {
            Write-Log '   [!] не применено: вы входите в Windows через учётную запись Microsoft, а без сервера выдачи номера она перестанет работать.'
            Write-Log '       Сначала перейдите на локальную учётную запись: Параметры > Учётные записи > Ваши данные.'
        } else { Write-Log ("   [!] не применено: {0}" -f (Get-ManagedReason)) }
        $script:Failures++
        continue
    }
    $failBefore = $script:Failures + $script:Blocked
    foreach ($d in $modDefs) {
        if ($SkipItems -contains $d.Id) { Write-Log ("   [п] {0} -- пропущено по вашему выбору" -f $d.C); continue }
        if (-not (Test-DefApplicable $d)) { Write-Log ("   [-] {0} -- нет на этой версии Windows" -f $d.C); continue }
        Apply-Def $d
    }
    if (($script:Failures + $script:Blocked) -gt $failBefore -and $script:ModuleHints.ContainsKey($m)) {
        Write-Log ("   [i] {0}" -f $script:ModuleHints[$m])
    }
}

# --- Компоненты производителя ---------------------------------------------- #
if ((Use-Module 'oem') -and -not $script:JournalFailed) {
    Write-Section 'Компоненты сбора данных производителя'
    $oem = Detect-Oem
    Write-Log ("   производитель: {0} {1}" -f $oem.manufacturer, $oem.model)
    if ($oem.items.Count -eq 0) { Write-Log '   [-] компонентов сбора данных не найдено' }
    $disabledList = @()
    foreach ($it in $oem.items) {
        if ($DryRun) { Write-Log ("   [тест] {0} {1} -- отключить" -f $it.type, $it.display); continue }
        try {
            if ($it.type -eq 'svc') {
                $s = Get-Service -Name $it.name -ErrorAction Stop
                if ($s.Status -eq 'Running') { Stop-Service -Name $it.name -Force -ErrorAction SilentlyContinue }
                Set-Service -Name $it.name -StartupType Disabled -ErrorAction Stop
            } else {
                $pp = Split-TaskPath $it.name
                Disable-ScheduledTask -TaskPath $pp[0] -TaskName $pp[1] -ErrorAction Stop | Out-Null
            }
            $disabledList += $it
            Write-Log ("   [+] отключено: {0}" -f $it.display); $script:Changes++
        } catch { Write-Log ("   [!] не удалось: {0} -- {1}" -f $it.display, $_.Exception.Message); $script:Failures++ }
    }
    if ($disabledList.Count -gt 0) {
        $prev = Load-Json 'oem-disabled.json'
        $all = @(); if ($prev) { $all += @($prev) }; $all += $disabledList
        Save-Json 'oem-disabled.json' $all
    }
}

# --- Другие пользователи и профиль по умолчанию ----------------------------- #
if ($AllProfiles -and -not $script:JournalFailed) { Apply-ProfilesHives }

# --- Буфер телеметрии ------------------------------------------------------- #
if ((Use-Module 'buffer') -and -not $script:JournalFailed) { Purge-Buffer }

# --- Чистка ----------------------------------------------------------------- #
if ((Use-Module 'cleanup') -and -not $script:JournalFailed) {
    Write-Section 'Чистка временных файлов'
    $total = 0.0
    $wu = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    $wuWasRunning = ($wu -and $wu.Status -eq 'Running')
    if ($wuWasRunning -and -not $DryRun) { Stop-Service wuauserv -Force -ErrorAction SilentlyContinue }
    $targets = @(
        @{ P = $env:TEMP;                                            L = 'временные файлы пользователя' },
        @{ P = "$env:SystemRoot\Temp";                               L = 'временные файлы Windows' },
        @{ P = "$env:SystemRoot\SoftwareDistribution\Download";      L = 'кэш загруженных обновлений' },
        @{ P = "$env:SystemRoot\Logs\CBS";                           L = 'логи обслуживания компонентов' },
        @{ P = "$env:LOCALAPPDATA\Microsoft\Windows\WER";            L = 'локальные отчёты об ошибках' },
        @{ P = "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"; L = 'очередь отчётов об ошибках' },
        @{ P = "$env:LOCALAPPDATA\CrashDumps";                       L = 'дампы аварийных завершений' },
        @{ P = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache";      L = 'кэш интернет-файлов' },
        @{ P = "$env:LOCALAPPDATA\D3DSCache";                        L = 'кэш шейдеров DirectX' }
    )
    $steps = $targets.Count + 3
    $n = 0
    Write-Log ("   шагов всего: {0}" -f $steps)
    foreach ($t in $targets) {
        $n++
        $tag = '[{0,3}%] ({1}/{2})' -f [int](100.0 * $n / $steps), $n, $steps
        $total += (Clear-FolderContents -FolderPath $t.P -Label $t.L -Step $tag)
    }
    if (-not $DryRun) {
        $thumbs = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
        if (Test-Path -LiteralPath $thumbs) {
            $before = Get-FolderSizeMB $thumbs
            Get-ChildItem -LiteralPath $thumbs -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            $f = [math]::Max(0, [math]::Round($before - (Get-FolderSizeMB $thumbs), 1)); $total += $f
            Write-Log ("   {0} кэш эскизов -- освобождено {1} МБ" -f ('[{0,3}%] ({1}/{2})' -f [int](100.0 * ($n + 1) / $steps), ($n + 1), $steps), $f)
        }
        $n++   # шаг «кэш эскизов» засчитан
        $n++   # следующий шаг — корзина
        $tag = '[{0,3}%] ({1}/{2})' -f [int](100.0 * $n / $steps), $n, $steps
        try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Log ("   {0} корзина очищена" -f $tag) } catch { Write-Log ("   {0} корзина уже пуста" -f $tag) }
        $n++
        $tag = '[{0,3}%] ({1}/{2})' -f [int](100.0 * $n / $steps), $n, $steps
        try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop | Out-Null; Write-Log ("   {0} кэш Delivery Optimization очищен" -f $tag) } catch { Write-Log ("   {0} кэш Delivery Optimization пропущен" -f $tag) }
    }
    if ($wuWasRunning -and -not $DryRun) { Start-Service wuauserv -ErrorAction SilentlyContinue }
    Write-Log '   [100%] чистка завершена'
    Write-Log ('   ИТОГО освобождено: ~{0} МБ' -f [math]::Round($total, 1))
}

# --- Автозагрузка ----------------------------------------------------------- #
if (Use-Module 'startup') {
    Write-Section 'Автозагрузка (только отчёт, ничего не отключается)'
    $stItems = @(Get-StartupList)
    if ($stItems.Count -gt 0) {
        foreach ($s in $stItems) {
            Write-Log ("   {0} {1}" -f $(if ($s.enabled) { '*' } else { '-' }), $s.name)
            Write-Log ("       команда : {0}" -f $s.cmd)
            Write-Log ("       источник: {0}" -f $s.source)
            if ($s.note) { Write-Log ("       это     : {0}" -f $s.note) }
        }
        Write-Log ''
        Write-Log ("   Всего записей: {0}, из них работает: {1}, лишних: {2}" -f $stItems.Count,
                   @($stItems | Where-Object { $_.enabled }).Count,
                   @($stItems | Where-Object { $_.enabled -and $_.advise }).Count)
    } else { Write-Log '   (записей не найдено)' }
    Write-Log ''; Write-Log '   Отключить лишнее: страница «Автозагрузка» или -StartupSet -StartupItems <id> -StartupValue Off.'
}

# --- Итог ------------------------------------------------------------------- #
Write-Section 'Итог'
# журнал для отката — дописываем к тому, что было раньше
Save-JournalEntries
if ($script:JournalFailed) {
    Write-Log '[!] Применение остановлено на середине: журнал отката перестал записываться. Что успело измениться до остановки, видно выше.'
}
# что Windows не отдала — запоминаем для проверки; что отдала — забываем
if (-not $DryRun -and ($script:BlockedIds.Count -gt 0 -or $script:UnblockedIds.Count -gt 0)) {
    try {
        $prevB = Load-Json 'blocked.json'
        $setB = @{}
        if ($prevB -and $prevB.ids) { foreach ($i in @($prevB.ids)) { $setB["$i"] = $true } }
        foreach ($i in $script:BlockedIds.Keys) { $setB[$i] = $true }
        foreach ($i in $script:UnblockedIds.Keys) { $setB.Remove($i) }
        Save-Json 'blocked.json' @{ ids = @($setB.Keys); updated = (Get-Date).ToString('s') }
    } catch { }
}

Write-Log ("Изменений применено : {0}" -f $script:Changes)
Write-Log ("Было уже настроено : {0}" -f $script:Already)
Write-Log ("Ошибок              : {0}" -f $script:Failures)
if ($script:Blocked -gt 0) { Write-Log ("Windows не разрешила: {0} (см. пометки [-] выше)" -f $script:Blocked) }
if ($script:BackupDir) { Write-Log ("Резервная копия     : {0}" -f $script:BackupDir) }
Write-Log ''
if ($script:Changes -gt 0) { Write-Log 'Перезагрузите компьютер, чтобы всё вступило в силу. Нажмите «Проверить» — программа прочитает реальное состояние системы.' }
else { Write-Log 'Менять было нечего — всё уже настроено. Нажмите «Проверить», чтобы увидеть состояние системы.' }
Emit-Json @{ changes=$script:Changes; already=$script:Already; failures=$script:Failures
             blocked=$script:Blocked; backup=$script:BackupDir }
Write-Log '###DONE###'
