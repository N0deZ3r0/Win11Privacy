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
# или под другим именем не подойдёт.
function Get-BackupFileSig {
    param([string]$File, [string]$Folder, [string]$Name, [switch]$Create)
    $h = [System.Security.Cryptography.HMACSHA256]::new([byte[]](Get-SignKey -Create:$Create))
    try {
        $head = [Text.Encoding]::UTF8.GetBytes(('w11p-backup|{0}|{1}|' -f $Folder.ToLowerInvariant(), $Name.ToLowerInvariant()))
        $data = [IO.File]::ReadAllBytes($File)
        $null = $h.TransformBlock($head, 0, $head.Length, $null, 0)
        $null = $h.TransformFinalBlock($data, 0, $data.Length)
        return (($h.Hash | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally { $h.Dispose() }
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
        $root = if ($BackupRoot) { $BackupRoot } else { [Environment]::GetFolderPath('Desktop') }
        # Папка лежит там, куда пишет любая программа пользователя, а reg.exe
        # пишет в неё с правами администратора. Имя с случайным хвостом
        # заранее не угадать — раньше по метке времени с точностью до секунды
        # можно было подложить на её место ссылку на чужую папку.
        $dir = Join-Path $root ('Win11Privacy-Backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $keys = @($script:Defs | Where-Object { $script:RegTypes -contains $_.T -and $Modules -contains $_.M } | ForEach-Object { $_.P } | Select-Object -Unique)
        try {
            if (Test-Path -LiteralPath $dir) { throw 'папка копии уже есть -- её завёл не этот запуск' }
            $null = [IO.Directory]::CreateDirectory($dir)
            if ((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'на месте папки копии оказалась ссылка' }
            $saved = 0
            $missed = @()
            foreach ($k in $keys) {
                if (-not (Test-Path -LiteralPath $k)) { continue }
                $native = $k -replace '^HKLM:\\','HKLM\' -replace '^HKCU:\\','HKCU\'
                $file = Join-Path $dir ((($k -replace '[:\\ ]','_')) + '.reg')
                # Считаем только то, что выгрузилось целиком (см. Export-RegKey).
                # Недописанный файл удаляется: восстановить из него нельзя, а
                # лежащий рядом с целыми он выглядел бы такой же копией.
                $why = Export-RegKey $native $file
                if (-not $why) { $saved++ }
                else {
                    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
                    $missed += ("{0} -- {1}" -f $k, $why)
                }
            }
            if ($saved -gt 0) {
                $script:BackupDir = $dir
                Write-Log ("   [+] сохранено веток: {0} -> {1}" -f $saved, $dir)
                # Подписи файлов: копия лежит там, куда пишет любая программа
                # пользователя, а возвращается с правами администратора
                # (см. Restore-BackupFolder). Без подписи программа её не вернёт.
                try {
                    $sigs = @{}
                    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Filter '*.reg')) {
                        $sigs[$f.Name] = Get-BackupFileSig $f.FullName (Split-Path $dir -Leaf) $f.Name -Create
                    }
                    (@{ version = 1; files = $sigs } | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath (Join-Path $dir 'backup-sig.json') -Encoding UTF8 -ErrorAction Stop
                } catch {
                    Write-Log ("   [-] копия не подписана ({0}) -- вернуть её кнопкой программы будет нельзя, только вручную" -f $_.Exception.Message)
                }
            } else {
                # Remove-Item -Recurse в PowerShell 5.1 идёт по ссылкам: папку
                # убираем тем же обходом без ссылок, что и при чистке
                $rmStat = @{ deleted = 0; failed = 0; skipped = 0; errors = (New-Object System.Collections.Generic.List[string]) }
                Remove-TreeNoFollow $dir $rmStat
                Write-Log '   [-] сохранять нечего: ни одна ветка не выгрузилась'
            }
            if ($missed.Count -gt 0) {
                Write-Log ("   [-] не выгрузились ветки: {0} (обычно Windows не отдаёт их даже на чтение; почему -- в каждой строке)" -f $missed.Count)
                foreach ($k in $missed) { Write-Log ("       {0}" -f $k) }
            }
        } catch { Write-Log "   [!] не удалось создать резервную копию: $($_.Exception.Message)" }
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

