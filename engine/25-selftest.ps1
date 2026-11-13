
# =========================================================================== #
#  САМОПРОВЕРКА: может ли программа реально менять настройки на этом ПК
# =========================================================================== #
# Пробная запись в реестр. Убирается ровно то, что создала сама проверка:
# своё значение (имя у каждого запуска своё — чужое «Probe» не затрётся) и
# ключи, которых до проверки не было, — если в них ничего не осталось.
# Раньше самопроверка стирала всю ветку Software\Win11Privacy со всем, что в
# ней лежало до неё.
function Test-RegWriteProbe {
    param([string]$Key)
    $res = @{ ok = $false; error = '' }
    $name = 'Probe-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    # верхний из ключей, которых нет (неизвестно — значит «есть»): удалить
    # потом можно только его и только пустым
    $created = Get-TopMissingKey $Key
    try {
        # New-Item -Force по существующему ключу пересоздал бы его пустым
        if ($created) { New-Item -Path $Key -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $Key -Name $name -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        $res.ok = ((Get-ItemProperty -LiteralPath $Key -Name $name -ErrorAction Stop).$name -eq 1)
    } catch { $res.error = $_.Exception.Message }
    if ((Get-RegRaw $Key $name).exists) {
        try { Remove-ItemProperty -LiteralPath $Key -Name $name -Force -ErrorAction Stop }
        catch { Write-Log ("   [!] пробное значение {0}\{1} не удалилось: {2}" -f $Key, $name, $_.Exception.Message) }
    }
    if ($created -and (Test-RegKeyExists $created) -and (Test-KeyTreeEmpty $created)) {
        try { Remove-Item -LiteralPath $created -Recurse -Force -ErrorAction Stop }
        catch { Write-Log ("   [!] пробный ключ {0} не удалился: {1}" -f $created, $_.Exception.Message) }
    }
    return $res
}

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
    $p = Test-RegWriteProbe 'HKCU:\Software\Win11Privacy\SelfTest'
    $r.hkcu = [bool]$p.ok
    if ($p.error) { Write-Log ("   [!] {0}" -f $p.error) }
    Write-Log ("   [{0}] запись в реестр пользователя (HKCU)" -f $(if ($r.hkcu) { '+' } else { '!' }))

    # --- реестр системы (HKLM) ---
    $p = Test-RegWriteProbe 'HKLM:\SOFTWARE\Win11Privacy\SelfTest'
    $r.hklm = [bool]$p.ok
    if ($p.error) { Write-Log ("   [!] {0}" -f $p.error) }
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
