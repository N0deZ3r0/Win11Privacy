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
                # итог считается ниже по файлу на диске, а не по этому вызову
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

