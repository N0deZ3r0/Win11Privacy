
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

        $action = New-ScheduledTaskAction -Execute $script:PsExe -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $engineDst + '" -WatcherNotify' + $script:DataArg)
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
    $rt = Remove-OwnTask $script:WatcherTask 'живые уведомления'
    Write-Log '###DONE###'
    exit $(if ($rt -eq 'failed') { 1 } else { 0 })
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
