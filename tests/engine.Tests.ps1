# Pester: точечные проверки мест из ревью (запись реестра и её сверка,
# исключение после записи, набор адресов брандмауэра, одна подмена hosts,
# откат отложенного запуска службы, «ключа нет» и «нет доступа», уборка
# самопроверки в реестре, данные программы и папка -DataRoot).
# Работает и со встроенным в Windows PowerShell 5.1 Pester 3.4, и с Pester 5
# на сборке GitHub: проверки — через throw, без Should, всё готовится в
# BeforeAll. Опасное подменено: реестр — только пробный ключ
# HKCU:\Software\W11PPester-*, брандмауэр, службы и hosts — заглушки и
# временные файлы. Запуск: Invoke-Pester -Script tests\engine.Tests.ps1 (3.4)
# или Invoke-Pester -Path tests\engine.Tests.ps1 (5).
Describe 'Движок Win11Privacy: точечные проверки' {
    BeforeAll {
        $enginePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Win11-Privacy-Engine.ps1'
        $engineAst = [System.Management.Automation.Language.Parser]::ParseFile($enginePath, [ref]$null, [ref]$null)
        foreach ($fn in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { Invoke-Expression $fn.Extent.Text }
        foreach ($a in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -like '$script:HostsMark*' }, $true)) { Invoke-Expression $a.Extent.Text }
        function Assert-True { param([bool]$Ok, [string]$Why) if (-not $Ok) { throw $Why } }
        function Reset-State {
            $script:Journal = New-Object System.Collections.Generic.List[object]
            $script:JournalRetract = New-Object 'System.Collections.Generic.HashSet[string]'
            $script:Failures = 0; $script:Changes = 0; $script:Already = 0; $script:Blocked = 0
            $script:BlockedIds = @{}; $script:UnblockedIds = @{}; $script:JournalFailed = $false; $script:RunId = 'pester'
            $script:Log = New-Object System.Collections.Generic.List[string]
        }
        function Write-Log { param($m) $script:Log.Add("$m") }
        function Ensure-Backup { }
        function Save-JournalEntries { param([switch]$Quiet) }
        function Get-LastLog { if ($script:Log.Count) { $script:Log[$script:Log.Count - 1] } else { '' } }
        $DryRun = $false
        $script:Probe = 'HKCU:\Software\W11PPester-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
        Reset-State
    }
    AfterAll { Remove-Item -LiteralPath $script:Probe -Recurse -Force -ErrorAction SilentlyContinue }

    Context '1. Set-Reg сверяет записанное: есть ли, какого вида, те ли данные' {
        It 'пустое двоичное значение записывается и сверяется как успех' {
            Reset-State
            Set-Reg -Path $script:Probe -Name 'EB' -Value ([byte[]]@()) -Type 'Binary' -Comment 'pester'
            $x = Get-RegRaw $script:Probe 'EB'
            Assert-True ($script:Changes -eq 1 -and $script:Failures -eq 0 -and $x.exists -and $x.kind -eq 'Binary' -and @($x.value).Count -eq 0) (Get-LastLog)
        }
        It 'пустой MultiString записывается и сверяется как успех' {
            Reset-State
            Set-Reg -Path $script:Probe -Name 'EM' -Value ([string[]]@()) -Type 'MultiString' -Comment 'pester'
            $x = Get-RegRaw $script:Probe 'EM'
            Assert-True ($script:Changes -eq 1 -and $script:Failures -eq 0 -and $x.exists -and $x.kind -eq 'MultiString') (Get-LastLog)
        }
        It 'те же данные, но не тот вид (строка «7» вместо числа) — не успех' {
            Reset-State
            function New-ItemProperty { param($LiteralPath, $Name, $Value, $PropertyType, [switch]$Force, $ErrorAction)
                Microsoft.PowerShell.Management\New-ItemProperty -LiteralPath $LiteralPath -Name $Name -Value "$Value" -PropertyType String -Force | Out-Null }
            Set-Reg -Path $script:Probe -Name 'KV' -Value 7 -Type 'DWord' -Comment 'pester'
            Assert-True ($script:Failures -eq 1 -and $script:Changes -eq 0 -and $script:Journal.Count -eq 1) (Get-LastLog)
        }
    }

    Context '2. Исключение при записи: решает то, что лежит сейчас' {
        It 'значение легло, а команда бросила исключение — запись «как было» остаётся' {
            Reset-State
            Microsoft.PowerShell.Management\New-Item -Path $script:Probe -Force | Out-Null
            Microsoft.PowerShell.Management\New-ItemProperty -LiteralPath $script:Probe -Name 'X' -Value 1 -PropertyType DWord -Force | Out-Null
            function New-ItemProperty { param($LiteralPath, $Name, $Value, $PropertyType, [switch]$Force, $ErrorAction)
                Microsoft.PowerShell.Management\New-ItemProperty -LiteralPath $LiteralPath -Name $Name -Value $Value -PropertyType $PropertyType -Force | Out-Null; throw 'после записи' }
            Set-Reg -Path $script:Probe -Name 'X' -Value 7 -Type 'DWord' -Comment 'pester'
            Assert-True ($script:Journal.Count -eq 1 -and $script:Changes -eq 1 -and $script:Already -eq 0 -and (Get-RegValue $script:Probe 'X') -eq 7) (Get-LastLog)
            Assert-True ("$($script:Journal[0]['old'])" -eq '1') 'в записи не прежнее значение'
        }
        It 'легло третье значение (обрыв на середине) — запись остаётся, это ошибка' {
            Reset-State
            function New-ItemProperty { param($LiteralPath, $Name, $Value, $PropertyType, [switch]$Force, $ErrorAction)
                Microsoft.PowerShell.Management\New-ItemProperty -LiteralPath $LiteralPath -Name $Name -Value 99 -PropertyType DWord -Force | Out-Null; throw 'обрыв' }
            function Set-RegDirect { param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') @{ ok = $false; error = 'заглушка' } }
            Set-Reg -Path $script:Probe -Name 'X' -Value 8 -Type 'DWord' -Comment 'pester'
            Assert-True ($script:Journal.Count -eq 1 -and $script:Failures -eq 1 -and $script:Changes -eq 0) (Get-LastLog)
        }
        It 'ничего не легло — изменения не было, запись отзывается' {
            Reset-State
            function New-ItemProperty { throw 'не записалось' }
            function Set-RegDirect { param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') @{ ok = $false; error = 'заглушка' } }
            $before = Get-RegValue $script:Probe 'X'
            Set-Reg -Path $script:Probe -Name 'X' -Value 5 -Type 'DWord' -Comment 'pester'
            Assert-True ($script:Journal.Count -eq 0 -and $script:Failures -eq 1 -and (Get-RegValue $script:Probe 'X') -eq $before) (Get-LastLog)
        }
    }

    Context '3. Брандмауэр: сверяется набор адресов, а не их число' {
        BeforeAll {
            $script:FwIpRuleName = 'Win11Privacy: pester'; $script:FwGroup = 'Win11Privacy'
            function New-FwStubs {
                $script:Rules = New-Object System.Collections.Generic.List[object]
                $script:Rules.Add([pscustomobject]@{ Name = 'old'; DisplayName = $script:FwIpRuleName; Enabled = 'True'; Action = 'Block'; Direction = 'Outbound'; Addr = @('192.0.2.9') })
            }
        }
        It '<Mode>: правило с не теми адресами отвергается, старое остаётся' -TestCases @(@{ Mode = 'swap' }, @{ Mode = 'extra' }, @{ Mode = 'missing' }) {
            param($Mode)
            Reset-State; New-FwStubs; $script:Mode = $Mode
            function Get-TelemetryIpList { @{ ips = @('192.0.2.1', '192.0.2.2', '2001:db8::1'); answered = 3; asked = 3 } }
            function Get-NetFirewallRule { param($DisplayName, $Name, $ErrorAction) if ($Name) { @($script:Rules | Where-Object { $_.Name -eq $Name }) } else { @($script:Rules | Where-Object { $_.DisplayName -eq $DisplayName }) } }
            function New-NetFirewallRule { param($Name, $DisplayName, $Group, $Direction, $Action, $RemoteAddress, [Alias('Profile')]$FwProfile, $Enabled, $Description, $ErrorAction)
                $script:Rules.Add([pscustomobject]@{ Name = $Name; DisplayName = $DisplayName; Enabled = 'True'; Action = $Action; Direction = $Direction; Addr = @($RemoteAddress) }) }
            function Get-NetFirewallAddressFilter { param($AssociatedNetFirewallRule, $ErrorAction)
                $a = @($AssociatedNetFirewallRule.Addr)
                switch ($script:Mode) { 'swap' { $a = @($a[0..($a.Count - 2)]) + '198.51.100.77' } 'extra' { $a = $a + '198.51.100.99' } 'missing' { $a = @($a[0..($a.Count - 2)]) } }
                [pscustomobject]@{ RemoteAddress = $a } }
            function Remove-NetFirewallRule { param($Name, $ErrorAction) foreach ($i in @($script:Rules | Where-Object { $_.Name -eq $Name })) { $null = $script:Rules.Remove($i) } }
            Apply-FwIpBlock
            Assert-True ((@($script:Rules | ForEach-Object Name) -join ',') -eq 'old' -and $script:Failures -eq 1) ((Get-LastLog) + ' | правила: ' + (@($script:Rules | ForEach-Object Name) -join ','))
        }
        It 'новое правило не создалось — старое на месте' {
            Reset-State; New-FwStubs
            function Get-TelemetryIpList { @{ ips = @('192.0.2.1'); answered = 1; asked = 1 } }
            function Get-NetFirewallRule { param($DisplayName, $Name, $ErrorAction) if ($Name) { @($script:Rules | Where-Object { $_.Name -eq $Name }) } else { @($script:Rules | Where-Object { $_.DisplayName -eq $DisplayName }) } }
            function New-NetFirewallRule { throw 'нет места в хранилище правил' }
            function Remove-NetFirewallRule { param($Name, $ErrorAction) foreach ($i in @($script:Rules | Where-Object { $_.Name -eq $Name })) { $null = $script:Rules.Remove($i) } }
            Apply-FwIpBlock
            Assert-True ((@($script:Rules | ForEach-Object Name) -join ',') -eq 'old' -and $script:Failures -eq 1) (Get-LastLog)
        }
        It 'повторы и разная запись IPv4/IPv6 сводятся к одному набору, и он принимается' {
            Reset-State; New-FwStubs
            function Get-TelemetryIpList { @{ ips = @('192.0.2.1', '192.0.2.1', '2001:DB8:0::1', '2001:db8::1'); answered = 2; asked = 2 } }
            function Get-NetFirewallRule { param($DisplayName, $Name, $ErrorAction) if ($Name) { @($script:Rules | Where-Object { $_.Name -eq $Name }) } else { @($script:Rules | Where-Object { $_.DisplayName -eq $DisplayName }) } }
            function New-NetFirewallRule { param($Name, $DisplayName, $Group, $Direction, $Action, $RemoteAddress, [Alias('Profile')]$FwProfile, $Enabled, $Description, $ErrorAction)
                $script:Asked = @($RemoteAddress)
                $script:Rules.Add([pscustomobject]@{ Name = $Name; DisplayName = $DisplayName; Enabled = 'True'; Action = $Action; Direction = $Direction; Addr = @($RemoteAddress) }) }
            # Windows пишет IPv6 по-своему — набор тот же
            function Get-NetFirewallAddressFilter { param($AssociatedNetFirewallRule, $ErrorAction) [pscustomobject]@{ RemoteAddress = @('192.0.2.1', '2001:0DB8:0000:0000:0000:0000:0000:0001') } }
            function Remove-NetFirewallRule { param($Name, $ErrorAction) foreach ($i in @($script:Rules | Where-Object { $_.Name -eq $Name })) { $null = $script:Rules.Remove($i) } }
            Apply-FwIpBlock
            Assert-True ($script:Failures -eq 0 -and (@($script:Asked) -join ',') -eq '192.0.2.1,2001:db8::1' -and $script:Rules.Count -eq 1) ((Get-LastLog) + ' | спрошено: ' + (@($script:Asked) -join ','))
        }
        It 'одно из прежних правил не удалилось — новое стоит, неудача названа и посчитана' {
            Reset-State; New-FwStubs
            $script:Rules.Add([pscustomobject]@{ Name = 'old2'; DisplayName = $script:FwIpRuleName; Enabled = 'True'; Action = 'Block'; Direction = 'Outbound'; Addr = @('192.0.2.8') })
            function Get-TelemetryIpList { @{ ips = @('192.0.2.1'); answered = 1; asked = 1 } }
            function Get-NetFirewallRule { param($DisplayName, $Name, $ErrorAction) if ($Name) { @($script:Rules | Where-Object { $_.Name -eq $Name }) } else { @($script:Rules | Where-Object { $_.DisplayName -eq $DisplayName }) } }
            function New-NetFirewallRule { param($Name, $DisplayName, $Group, $Direction, $Action, $RemoteAddress, [Alias('Profile')]$FwProfile, $Enabled, $Description, $ErrorAction)
                $script:Rules.Add([pscustomobject]@{ Name = $Name; DisplayName = $DisplayName; Enabled = 'True'; Action = $Action; Direction = $Direction; Addr = @($RemoteAddress) }) }
            function Get-NetFirewallAddressFilter { param($AssociatedNetFirewallRule, $ErrorAction) [pscustomobject]@{ RemoteAddress = @($AssociatedNetFirewallRule.Addr) } }
            function Remove-NetFirewallRule { param($Name, $ErrorAction) if ($Name -eq 'old2') { throw 'правило занято' }; foreach ($i in @($script:Rules | Where-Object { $_.Name -eq $Name })) { $null = $script:Rules.Remove($i) } }
            Apply-FwIpBlock
            $names = (@($script:Rules | ForEach-Object Name) | Sort-Object) -join ','
            Assert-True ($script:Failures -eq 1 -and $names -match '^old2,Win11Privacy-TelemetryIp-[0-9a-f]{8}$') ("правила: " + $names)
        }
    }

    Context '4. hosts: весь файл одной подменой' {
        BeforeAll {
            $script:HostsPath = Join-Path ([IO.Path]::GetTempPath()) ('w11p-pester-hosts-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
            $script:HostsDomains = @('telemetry.example', 'vortex.example'); $script:BackupDir = ''
            function ipconfig { }
        }
        AfterAll { Remove-Item -LiteralPath $script:HostsPath, ($script:HostsPath + '.w11p-new') -Force -ErrorAction SilentlyContinue }
        It 'устаревший блок заменяется новым за одну подмену файла, чужие строки на месте' {
            Reset-State
            [IO.File]::WriteAllLines($script:HostsPath, [string[]]@('# mine', '', $script:HostsMarkStart, '0.0.0.0 telemetry.example', $script:HostsMarkEnd, '10.0.0.5 nas'), [Text.Encoding]::Default)
            ${function:Replace-FileAtomicReal} = ${function:Replace-FileAtomic}
            $script:Replaces = 0
            function Replace-FileAtomic { param($Tmp, $Path) $script:Replaces++; Replace-FileAtomicReal $Tmp $Path }
            Apply-Hosts
            $l = @([IO.File]::ReadAllLines($script:HostsPath))
            Assert-True ($script:Replaces -eq 1 -and $script:Failures -eq 0) ("подмен: $($script:Replaces); " + (Get-LastLog))
            Assert-True (@($l | Where-Object { $_ -match $script:HostsMarkRegex }).Count -eq 2 -and ($l -contains '0.0.0.0 vortex.example') -and ($l -contains '# mine') -and ($l -contains '10.0.0.5 nas')) ($l -join ' | ')
            Assert-True (-not (Test-Path -LiteralPath ($script:HostsPath + '.w11p-new'))) 'копия осталась'
        }
        It 'подмена не прошла — hosts байт в байт прежний, копии не осталось, это ошибка' {
            Reset-State
            [IO.File]::WriteAllLines($script:HostsPath, [string[]]@('# mine', '', $script:HostsMarkStart, '0.0.0.0 telemetry.example', $script:HostsMarkEnd), [Text.Encoding]::Default)
            $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:HostsPath))
            function Replace-FileAtomic { param($Tmp, $Path) throw [System.UnauthorizedAccessException]::new('отказано') }
            Apply-Hosts
            $after = [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:HostsPath))
            Assert-True ($before -eq $after -and $script:Failures -eq 1 -and -not (Test-Path -LiteralPath ($script:HostsPath + '.w11p-new'))) (Get-LastLog)
        }
    }

    Context '5. Откат службы: тип запуска и отложенный запуск — со сверкой' {
        BeforeAll {
            function New-SvcStubs {
                $script:FakeStart = @{}; $script:FakeDelayed = @{}; $script:DelayedFails = $false; $script:DelayedIgnored = $false
            }
        }
        It '<Case>' -TestCases @(
            @{ Case = 'отложенный запуск возвращается и сверяется'; Delayed = '1'; Fails = $false; Ignored = $false; Pre = $null; WantOk = $true; WantNow = 1 },
            @{ Case = 'отказ при возврате отложенного запуска — откат не полный'; Delayed = '1'; Fails = $true; Ignored = $false; Pre = $null; WantOk = $false; WantNow = $null },
            @{ Case = 'отложенный запуск «не лёг» — сверка видит'; Delayed = '1'; Fails = $false; Ignored = $true; Pre = $null; WantOk = $false; WantNow = $null },
            @{ Case = 'не было до программы — появившийся убирается'; Delayed = ''; Fails = $false; Ignored = $false; Pre = 1; WantOk = $true; WantNow = $null }) {
            param($Case, $Delayed, $Fails, $Ignored, $Pre, $WantOk, $WantNow)
            New-SvcStubs; $script:DelayedFails = $Fails; $script:DelayedIgnored = $Ignored
            if ($null -ne $Pre) { $script:FakeDelayed['SvcP'] = $Pre }
            function Get-Service { param($Name, $ErrorAction) [pscustomobject]@{ Name = $Name } }
            function Set-Service { param($Name, $StartupType, $ErrorAction) $script:FakeStart[$Name] = @{ Automatic = 2; Manual = 3; Disabled = 4 }["$StartupType"] }
            function Get-RegValue { param($Path, $Name) if ($Name -eq 'Start') { return $script:FakeStart[(Split-Path $Path -Leaf)] } return $null }
            function Get-RegRaw { param($Path, $Name)
                $v = $(if ($Name -eq 'DelayedAutostart') { $script:FakeDelayed[(Split-Path $Path -Leaf)] } else { $null })
                if ($null -eq $v) { return @{ ok = $true; exists = $false; kind = ''; value = $null } }
                return @{ ok = $true; exists = $true; kind = 'DWord'; value = $v } }
            function Set-ItemProperty { param($LiteralPath, $Name, $Value, $Type, $ErrorAction)
                if ($Name -eq 'DelayedAutostart') { if ($script:DelayedFails) { throw 'Отказано в доступе.' }; if (-not $script:DelayedIgnored) { $script:FakeDelayed[(Split-Path $LiteralPath -Leaf)] = [int]$Value } } }
            function Remove-ItemProperty { param($LiteralPath, $Name, $ErrorAction) $script:FakeDelayed.Remove((Split-Path $LiteralPath -Leaf)) }
            function Start-Service { param($Name, $ErrorAction) }
            $x = Restore-JournalEntry ([pscustomobject]@{ kind = 'svc'; name = 'SvcP'; old = '2'; delayed = $Delayed; running = $false })
            Assert-True ([bool]$x.ok -eq $WantOk) ("ok=$($x.ok): $($x.error)")
            Assert-True ($script:FakeDelayed['SvcP'] -eq $WantNow) ("сейчас отложенный запуск: " + $script:FakeDelayed['SvcP'])
        }
    }

    Context '6. «Ключа нет» и «нет доступа» — разное' {
        It 'закрытый ключ (HKLM\SECURITY\Policy) — «не прочиталось, нет доступа»' {
            $x = Get-RegRaw 'HKLM:\SECURITY\Policy' 'W11PPester'
            Assert-True ((-not $x.ok) -and $x.denied -and -not $x.exists) ("ok=$($x.ok) denied=$($x.denied)")
            Assert-True ($null -eq (Test-RegKeyExists 'HKLM:\SECURITY\Policy')) 'о закрытом ключе сказано «есть» или «нет»'
        }
        It 'отсутствующий ключ — прочитано, значения нет' {
            $x = Get-RegRaw 'HKCU:\Software\W11PPester-Missing\Sub' 'x'
            Assert-True ($x.ok -and -not $x.exists) "ok=$($x.ok)"
            Assert-True ((Test-RegKeyExists 'HKCU:\Software\W11PPester-Missing\Sub') -eq $false) 'отсутствующий ключ назван существующим'
        }
        It 'значение в закрытом ключе не меняется, и в журнал не идёт «значения не было»' {
            Reset-State
            Set-Reg -Path 'HKLM:\SECURITY\Policy' -Name 'W11PPester' -Value 1 -Type 'DWord' -Comment 'pester'
            Assert-True ($script:Failures -eq 1 -and $script:Journal.Count -eq 0) (Get-LastLog)
        }
        It 'созданным программой не считается ключ, о котором неизвестно, есть ли он' {
            # сам закрытый ключ есть, но не читается — «создан программой» он не будет
            Assert-True ((Get-TopMissingKey 'HKLM:\SECURITY\Policy') -eq '') 'закрытый ключ записан бы как «создан программой»'
            # его отсутствующий подключ — да, но выше закрытого родителя не поднимается
            $top = Get-TopMissingKey 'HKLM:\SECURITY\Policy\W11PPester\Sub'
            Assert-True ($top -eq 'HKLM:\SECURITY\Policy\W11PPester') ("вышло: " + $top)
        }
    }

    Context '7. Самопроверка убирает за собой только своё' {
        It 'в ветке были свои значения и подключи — они на месте, пробного ключа нет' {
            Reset-State
            $root = "$script:Probe\ST1"
            Microsoft.PowerShell.Management\New-Item -Path "$root\Other" -Force | Out-Null
            Microsoft.PowerShell.Management\New-ItemProperty -LiteralPath $root -Name 'Keep' -Value 5 -PropertyType DWord -Force | Out-Null
            Microsoft.PowerShell.Management\New-ItemProperty -LiteralPath "$root\Other" -Name 'Also' -Value 'x' -PropertyType String -Force | Out-Null
            $x = Test-RegWriteProbe "$root\SelfTest"
            Assert-True ([bool]$x.ok) ("запись не прошла: " + $x.error)
            Assert-True ((Get-RegValue $root 'Keep') -eq 5 -and (Get-RegValue "$root\Other" 'Also') -eq 'x') 'стёрто то, что было в ветке до проверки'
            Assert-True (-not (Test-Path -LiteralPath "$root\SelfTest")) 'пробный ключ остался'
        }
        It 'ветки не было — после проверки её снова нет' {
            Reset-State
            $root = "$script:Probe\ST2"
            $x = Test-RegWriteProbe "$root\SelfTest"
            Assert-True ([bool]$x.ok) ("запись не прошла: " + $x.error)
            Assert-True (-not (Test-Path -LiteralPath $root)) 'созданная проверкой ветка осталась'
        }
        It 'ключ SelfTest был до проверки — он на месте со своим значением, пробного нет' {
            Reset-State
            $k = "$script:Probe\ST3\SelfTest"
            Microsoft.PowerShell.Management\New-Item -Path $k -Force | Out-Null
            Microsoft.PowerShell.Management\New-ItemProperty -LiteralPath $k -Name 'Probe' -Value 7 -PropertyType DWord -Force | Out-Null
            $x = Test-RegWriteProbe $k
            Assert-True ([bool]$x.ok) ("запись не прошла: " + $x.error)
            $names = @((Get-Item -LiteralPath $k).GetValueNames())
            Assert-True ((Get-RegValue $k 'Probe') -eq 7 -and $names.Count -eq 1) ('значения: ' + ($names -join ','))
        }
        It 'запись не прошла — созданное проверкой убрано, итог «нельзя»' {
            Reset-State
            $root = "$script:Probe\ST4"
            function New-ItemProperty { throw 'отказано' }
            $x = Test-RegWriteProbe "$root\SelfTest"
            Assert-True ((-not $x.ok) -and "$($x.error)" -like '*отказано*') ("ok=$($x.ok) error=$($x.error)")
            Assert-True (-not (Test-Path -LiteralPath $root)) 'созданная проверкой ветка осталась'
        }
    }

    Context '8. Данные программы — только её собственные файлы' {
        BeforeAll {
            foreach ($a in $engineAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -like '$script:DataFile*' }, $true)) { Invoke-Expression $a.Extent.Text }
            $script:DataDir = Join-Path ([IO.Path]::GetTempPath()) ('w11p-pester-data-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
            Microsoft.PowerShell.Management\New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null
        }
        AfterAll { Remove-Item -LiteralPath $script:DataDir -Recurse -Force -ErrorAction SilentlyContinue }
        It 'в списке только файлы программы; чужие файлы и папка с «нашим» именем не входят' {
            $own = @('profile.json', 'changes.json', 'xray-history.json', 'changes.broken-20261113-120000.json', 'changes.json.tmp')
            $foreign = @('Отчёт.docx', 'notes.txt', 'profile.json.bak', 'changes.old.json', 'changes.broken-x.json', 'other.tmp', 'engine.ps1', 'journal.key')
            foreach ($n in @($own + $foreign)) { [IO.File]::WriteAllText((Join-Path $script:DataDir $n), 'x') }
            Microsoft.PowerShell.Management\New-Item -ItemType Directory -Path (Join-Path $script:DataDir 'blocked.json') -Force | Out-Null
            $got = (@(Get-DataFiles | ForEach-Object { $_.file }) | Sort-Object) -join ','
            $want = (@($own) | Sort-Object) -join ','
            Assert-True ($got -eq $want) ("получено: " + $got)
            Assert-True (-not (Test-DataFileOwned (Get-Item -LiteralPath (Join-Path $script:DataDir 'blocked.json')))) 'папка с именем файла данных сочтена файлом программы'
        }
        It '-DataRoot «<Path>» — <Want>' -TestCases @(
            @{ Path = 'D:\Win11Privacy\Win11Privacy-Data'; Want = $true },
            @{ Path = 'D:\Win11Privacy\win11privacy-data\'; Want = $true },
            @{ Path = '\\nas\share\Win11Privacy-Data'; Want = $true },
            @{ Path = 'C:\Users\Someone\Documents'; Want = $false },
            @{ Path = 'D:\'; Want = $false },
            @{ Path = 'Win11Privacy-Data'; Want = $false },
            @{ Path = 'D:\Win11Privacy-Data-old'; Want = $false },
            @{ Path = 'D:\Win11Privacy-Data\..\Documents'; Want = $false }) {
            param($Path, $Want)
            Assert-True ((Test-DataRootAllowed $Path) -eq $Want) ("получено: " + (Test-DataRootAllowed $Path))
        }
    }
}
