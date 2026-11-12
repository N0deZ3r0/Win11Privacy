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
