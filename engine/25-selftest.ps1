
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
