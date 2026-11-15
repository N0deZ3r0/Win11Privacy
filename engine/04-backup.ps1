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

# reg.exe напрямую, по полному пути, без cmd.exe: вывод читается, но не
# превращается в ошибки PowerShell. Ответ — код выхода и текст ошибки
# (code = -1 — не запустился или не уложился во время).
function Invoke-RegExe {
    param([string]$Arguments, [int]$TimeoutMs = 300000)
    $p = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = Join-Path $env:SystemRoot 'System32\reg.exe'
        $psi.Arguments = $Arguments
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        # Оба потока — асинхронно: синхронное чтение ждало бы конца процесса,
        # и ограничение по времени ниже не сработало бы никогда.
        $errText = $p.StandardError.ReadToEndAsync()
        $null = $p.StandardOutput.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutMs)) { try { $p.Kill() } catch { }; return @{ code = -1; error = 'reg.exe не закончил за отведённое время' } }
        return @{ code = $p.ExitCode; error = ("$($errText.Result)" -replace '\s+', ' ').Trim() }
    } catch { return @{ code = -1; error = $_.Exception.Message } }
    finally { if ($null -ne $p) { $p.Dispose() } }
}

# Подпись файла резервной копии — тем же ключом, что и журнал отката
# (HMAC-SHA256), с отдельной приставкой: подпись журнала за подпись файла не
# сойдёт. В подпись входят имя папки копии и имя файла: файл из другой копии
# или под другим именем не подойдёт. Подписываются ровно те байты, что будут
# записаны или импортированы (W11P-001): не файл по имени, который можно
# подменить между чтением и подписью, а уже прочитанное в память содержимое.
function Get-BackupBytesSig {
    param([byte[]]$Bytes, [string]$Folder, [string]$Name, [switch]$Create)
    $h = [System.Security.Cryptography.HMACSHA256]::new([byte[]](Get-SignKey -Create:$Create))
    try {
        $head = [Text.Encoding]::UTF8.GetBytes(('w11p-backup|{0}|{1}|' -f $Folder.ToLowerInvariant(), $Name.ToLowerInvariant()))
        $null = $h.TransformBlock($head, 0, $head.Length, $null, 0)
        $null = $h.TransformFinalBlock($Bytes, 0, $Bytes.Length)
        return (($h.Hash | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally { $h.Dispose() }
}

# --------------------------------------------------------------------------- #
#  Подписанный список файлов копии (backup-sig.json, версия 2). В версии 1
#  был только список «файл -> подпись»: удалив из него строку вместе с файлом,
#  можно было незаметно сократить копию. Теперь у списка своя подпись (тем же
#  ключом, с отдельной приставкой): в неё входят имя папки и все пары
#  «файл:подпись». Поле files осталось тем же — прежние версии программы
#  такую копию тоже читают.
# --------------------------------------------------------------------------- #
$script:BackupManifestName = 'backup-sig.json'
# Имена файлов копии — путь ветки, где «:», «\» и пробелы заменены на «_»
$script:BackupFileRx = '^[A-Za-z0-9_.(){}+-]{1,200}\.reg$'

function Get-BackupManifestSig {
    param([string]$Folder, [hashtable]$Files, [switch]$Create)
    $lines = @($Files.Keys | ForEach-Object { ([string]$_).ToLowerInvariant() + ':' + ([string]$Files[$_]).ToLowerInvariant() } | Sort-Object)
    $text = 'w11p-backup-manifest|' + $Folder.ToLowerInvariant() + '|' + ($lines -join "`n")
    $h = [System.Security.Cryptography.HMACSHA256]::new([byte[]](Get-SignKey -Create:$Create))
    try {
        $b = [Text.Encoding]::UTF8.GetBytes($text)
        return (($h.ComputeHash($b) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally { $h.Dispose() }
}

# Текст списка: только ASCII, ключи по порядку — его читает строгий разбор
# (ConvertFrom-EngineRequest), который отвергает повторы полей
function ConvertTo-BackupManifestText {
    param([string]$Folder, [hashtable]$Files, [string]$Sig)
    $parts = @($Files.Keys | Sort-Object | ForEach-Object { '"' + $_ + '":"' + $Files[$_] + '"' })
    return ('{"version":2,"folder":"' + $Folder + '","files":{' + ($parts -join ',') + '},"sig":"' + $Sig + '"}')
}

# Рабочие папки внутри защищённого корня, оставшиеся от оборванных запусков
# (backup-*, restore-*): удаляются через час, обходом без ссылок
function Remove-StaleWorkDirs {
    param([string]$Prefix)
    if (-not $script:SafeRoot -or -not (Test-Path -LiteralPath $script:SafeRoot)) { return }
    $cut = (Get-Date).AddHours(-1)
    foreach ($d in @(Get-ChildItem -LiteralPath $script:SafeRoot -Directory -Force -Filter ($Prefix + '*') -ErrorAction SilentlyContinue)) {
        if ($d.LastWriteTime -gt $cut) { continue }
        $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
        Remove-TreeNoFollow $d.FullName $st
    }
}

# Новая пустая рабочая папка внутри защищённого корня: имя со случайным
# хвостом, не ссылка, владелец — система или администраторы, чужим не открыта
# на запись. Не вышло — исключение: работать с копией негде.
function New-SafeWorkDir {
    param([string]$Prefix)
    if (-not (Assert-SafeRoot)) { throw 'папка ProgramData\Win11Privacy не защищена' }
    $dir = Join-Path $script:SafeRoot ($Prefix + [guid]::NewGuid().ToString('N').Substring(0, 12))
    if (Test-Path -LiteralPath $dir) { throw 'рабочая папка уже есть' }
    $null = [IO.Directory]::CreateDirectory($dir)
    $item = Get-Item -LiteralPath $dir -Force
    if (-not (Test-ItemTrusted $item)) {
        $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
        Remove-TreeNoFollow $dir $st
        throw 'рабочая папка не защищена (ссылка или чужие права)'
    }
    return $dir
}

# --------------------------------------------------------------------------- #
#  Резервная копия веток реестра (W11P-001, W11P-005). Раньше reg.exe
#  выгружал ветки прямо в папку на рабочем столе, куда пишет любая программа
#  пользователя, а подпись снималась с файла уже там: между выгрузкой и
#  подписью файл можно было подменить; к тому же движок с правами
#  администратора писал по пути, где пользователь мог подложить ссылку.
#  Теперь движок с этими правами не пишет в папки пользователя вовсе:
#    1. ветки выгружаются в рабочую папку внутри защищённого корня
#       ProgramData\Win11Privacy (пишут только система и администраторы,
#       путь до корня проверен целиком — Assert-SafeRoot);
#    2. каждый файл читается один раз в память, проверяется (Test-RegExportFile)
#       и подписывается ровно этими байтами; рядом — подписанный список;
#    3. готовая подписанная копия одним переименованием (тот же том, тот же
#       корень) становится копией в хранилище ProgramData\Win11Privacy\backups —
#       менять её могут только администраторы, обычные программы только читают.
#  Копия на рабочий стол больше не кладётся: вернуть копию можно из окна
#  («Изменения» -> «Из резервной копии»), а папку хранилища открывает пункт
#  «Открыть папку резервных копий». Копии прежних версий на рабочем столе и
#  в -BackupRoot по-прежнему видны в списке и возвращаются после проверки.
#  Оборванный запуск оставляет рабочую папку только внутри защищённого корня
#  (её уберёт следующий); в хранилище копия появляется только целиком.
# --------------------------------------------------------------------------- #
$script:BackupStoreKeep = 20

function Get-BackupStoreDir { return (Join-Path $script:SafeRoot 'backups') }

# Старые копии в хранилище: остаются самая первая (состояние до программы —
# самое ценное) и $BackupStoreKeep последних. Имя папки начинается с даты —
# порядок по имени и есть порядок по времени.
function Limit-BackupStore {
    $store = Get-BackupStoreDir
    $all = @(Get-ChildItem -LiteralPath $store -Directory -Force -Filter 'Win11Privacy-Backup-*' -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($all.Count -le ($script:BackupStoreKeep + 1)) { return }
    foreach ($old in @($all[1..($all.Count - $script:BackupStoreKeep - 1)])) {
        $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
        Remove-TreeNoFollow $old.FullName $st
    }
}

function New-RegBackup {
    param([string[]]$Keys)
    $res = @{ dir = ''; saved = 0; signed = 0; missed = @(); error = '' }
    Remove-StaleWorkDirs 'backup-'
    $leaf = 'Win11Privacy-Backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
    $stage = $null
    try {
        $stage = New-SafeWorkDir 'backup-'
        # хранилище — внутри того же защищённого корня: перенос в него — одно
        # переименование на одном томе
        $store = Get-BackupStoreDir
        if (-not (Test-Path -LiteralPath $store)) { $null = [IO.Directory]::CreateDirectory($store) }
        if (-not (Test-ItemTrusted (Get-Item -LiteralPath $store -Force))) { throw 'хранилище копий не защищено (ссылка или чужие права)' }
        $final = Join-Path $store $leaf
        if (Test-Path -LiteralPath $final) { throw 'копия с таким именем уже есть' }
        $sigs = @{}
        foreach ($k in $Keys) {
            if (-not (Test-Path -LiteralPath $k)) { continue }
            $native = $k -replace '^HKLM:\\','HKLM\' -replace '^HKCU:\\','HKCU\'
            $name = (($k -replace '[:\\ ]','_')) + '.reg'
            if ($name -cnotmatch $script:BackupFileRx -or $sigs.ContainsKey($name)) { $res.missed += ("{0} -- имя файла копии не годится или повторяется" -f $k); continue }
            $file = Join-Path $stage $name
            # Считаем только то, что выгрузилось целиком (см. Export-RegKey).
            # Недописанный файл удаляется: восстановить из него нельзя.
            $why = Export-RegKey $native $file
            if ($why) {
                Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
                $res.missed += ("{0} -- {1}" -f $k, $why)
                continue
            }
            # Один раз в память: проверяются и подписываются одни и те же байты
            # (рабочая папка закрыта для чужой записи — эти байты и остаются в файле)
            $bytes = [IO.File]::ReadAllBytes($file)
            $sigs[$name] = Get-BackupBytesSig $bytes $leaf $name -Create
            $res.saved++
        }
        if ($res.saved -eq 0) { return $res }
        $msig = Get-BackupManifestSig $leaf $sigs -Create
        [IO.File]::WriteAllBytes((Join-Path $stage $script:BackupManifestName), [Text.Encoding]::ASCII.GetBytes((ConvertTo-BackupManifestText $leaf $sigs $msig)))
        $res.signed = $sigs.Count
        # Готовая копия — в хранилище одним действием
        [IO.Directory]::Move($stage, $final)
        $stage = $null
        $res.dir = $final
        Limit-BackupStore
    } catch { $res.error = $_.Exception.Message }
    finally {
        if ($stage -and (Test-Path -LiteralPath $stage)) {
            $st = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
            Remove-TreeNoFollow $stage $st
        }
    }
    return $res
}

# Выгружает ветку реестра в .reg и проверяет, что выгрузилась: reg.exe
# закончил с кодом 0, а файл начинается с заголовка, который понимает импорт.
# Раньше успехом считалось само появление файла — а reg.exe, упавший на
# середине, оставляет недописанный. Пустая строка — выгрузилось, иначе — почему нет.
function Export-RegKey {
    param([string]$Key, [string]$File)
    # в пути ветки и файла кавычек не бывает; обратная косая в конце
    # экранировала бы закрывающую кавычку — её убираем
    $r = Invoke-RegExe ('export "{0}" "{1}" /y' -f $Key.TrimEnd('\'), $File)
    if ($r.code -eq -1) { return $r.error }
    if ($r.code -ne 0) { return ("reg.exe, код {0}: {1}" -f $r.code, $r.error) }
    if (-not (Test-Path -LiteralPath $File)) { return 'reg.exe закончил без ошибки, но файла нет' }
    return (Test-RegExportFile $File $Key)
}

# Выгрузка целая: UTF-16 с меткой FF FE и чётной длиной, заголовок, сразу за
# ним — сама выгруженная ветка, а в конце — пустая строка, которой reg.exe
# заканчивает каждую запись. Файл, оборванный посередине записи, не пройдёт.
# Пустая строка — целая, иначе — почему нет.
function Test-RegExportFile {
    param([string]$File, [string]$Key)
    try { $b = [IO.File]::ReadAllBytes($File) } catch { return ("файл не читается: {0}" -f $_.Exception.Message) }
    if ($b.Length -lt 4 -or $b[0] -ne 0xFF -or $b[1] -ne 0xFE -or ($b.Length % 2) -ne 0) { return 'файл не в том виде, в каком его пишет reg.exe (UTF-16)' }
    $t = [Text.Encoding]::Unicode.GetString($b, 2, $b.Length - 2)
    $full = ($Key.TrimEnd('\') -replace '^HKLM\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKCU\\', 'HKEY_CURRENT_USER\')
    $start = "Windows Registry Editor Version 5.00`r`n`r`n[" + $full + "]`r`n"
    if (-not $t.StartsWith($start, [StringComparison]::OrdinalIgnoreCase)) { return 'в начале файла нет заголовка выгрузки и самой ветки' }
    if (-not $t.EndsWith("`r`n`r`n")) { return 'файл оборван: последняя запись не закончена' }
    return ''
}

function Ensure-Backup {
    if (-not $script:BackupEnabled -or $script:BackupTried -or $DryRun) { return }
    $script:BackupTried = $true

    if (-not $NoBackup) {
        Write-Section 'Резервная копия реестра'
        $keys = @($script:Defs | Where-Object { $script:RegTypes -contains $_.T -and $Modules -contains $_.M } | ForEach-Object { $_.P } | Select-Object -Unique)
        # Выгрузка, проверка и подпись — в защищённой рабочей папке, затем
        # готовая подписанная копия — в хранилище программы (New-RegBackup)
        $bk = New-RegBackup $keys
        if ($bk.dir) {
            $script:BackupDir = $bk.dir
            Write-Log ("   [+] сохранено веток: {0} -> {1}" -f $bk.saved, $bk.dir)
            Write-Log '   [i] вернуть копию: «Изменения» -> «Из резервной копии»'
        } elseif ($bk.error) {
            Write-Log "   [!] не удалось создать резервную копию: $($bk.error)"
        } else {
            Write-Log '   [-] сохранять нечего: ни одна ветка не выгрузилась'
        }
        if ($bk.missed.Count -gt 0) {
            Write-Log ("   [-] не выгрузились ветки: {0} (обычно Windows не отдаёт их даже на чтение; почему -- в каждой строке)" -f $bk.missed.Count)
            foreach ($k in $bk.missed) { Write-Log ("       {0}" -f $k) }
        }
    }

    if (-not $NoRestorePoint) {
        Write-Section 'Точка восстановления системы'
        # Чтобы Windows не отказала «точка уже была сегодня», частота создания
        # точек на время ставится в 0. Раньше так и оставалась — системная
        # настройка менялась навсегда и мимо журнала. Теперь возвращается.
        $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $srOld = Get-RegValue $srKey 'SystemRestorePointCreationFrequency'
        try {
            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
            New-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
            Checkpoint-Computer -Description 'Win11Privacy: до изменений' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
            Write-Log '   [+] точка восстановления создана'
        } catch { Write-Log "   [!] точку восстановления создать не удалось: $($_.Exception.Message)" }
        finally {
            try {
                if ($null -ne $srOld) { New-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -Value $srOld -PropertyType DWord -Force -ErrorAction Stop | Out-Null }
                else { Remove-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -Force -ErrorAction SilentlyContinue }
            } catch { Write-Log "   [!] частота точек восстановления не вернулась: $($_.Exception.Message)"; $script:Failures++ }
        }
    }
}

