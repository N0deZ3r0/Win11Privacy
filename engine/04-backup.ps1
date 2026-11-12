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

# Выгружает ветку реестра в .reg и проверяет, что выгрузилась: reg.exe
# закончил с кодом 0, а файл начинается с заголовка, который понимает импорт.
# Раньше успехом считалось само появление файла — а reg.exe, упавший на
# середине, оставляет недописанный. reg.exe запускается напрямую, по полному
# пути, без cmd.exe; вывод читается, но не превращается в ошибки PowerShell.
# Пустая строка — выгрузилось, иначе — почему нет.
function Export-RegKey {
    param([string]$Key, [string]$File)
    $p = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = Join-Path $env:SystemRoot 'System32\reg.exe'
        # в пути ветки и файла кавычек не бывает; обратная косая в конце
        # экранировала бы закрывающую кавычку — её убираем
        $psi.Arguments = ('export "{0}" "{1}" /y' -f $Key.TrimEnd('\'), $File)
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $errText = $p.StandardError.ReadToEndAsync()
        $null = $p.StandardOutput.ReadToEnd()
        if (-not $p.WaitForExit(300000)) { try { $p.Kill() } catch { }; return 'reg.exe не закончил выгрузку за пять минут' }
        if ($p.ExitCode -ne 0) { return ("reg.exe, код {0}: {1}" -f $p.ExitCode, ("$($errText.Result)" -replace '\s+', ' ').Trim()) }
    } catch { return $_.Exception.Message }
    finally { if ($null -ne $p) { $p.Dispose() } }
    if (-not (Test-Path -LiteralPath $File)) { return 'reg.exe закончил без ошибки, но файла нет' }
    $head = ''
    try {
        $sr = New-Object System.IO.StreamReader($File, $true)
        try { $head = $sr.ReadLine() } finally { $sr.Close() }
    } catch { return ("файл не читается: {0}" -f $_.Exception.Message) }
    if ("$head" -ne 'Windows Registry Editor Version 5.00') { return 'в файле нет заголовка выгрузки реестра' }
    return ''
}

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
            } else {
                Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
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

