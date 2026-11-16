# ASCII only (runs in Windows PowerShell 5.1 on the build agent and in the test VM).
#
# Checks the installer dist\Win11Privacy-Setup.exe for real: installs, upgrades,
# unpacks a portable copy and uninstalls - with and without the program data.
# It CHANGES THE SYSTEM (Program Files, Start menu, scheduled tasks, and it
# deletes C:\ProgramData\Win11Privacy in the "purge" case), so it runs only on
# a throwaway machine: the CI agent or the test VM, with WIN11_INSTALLER_TEST=1.
#
#   $env:WIN11_INSTALLER_TEST = '1'
#   .\tests\installer-tests.ps1 -Setup .\dist\Win11Privacy-Setup.exe -Exe .\Win11Privacy.exe
param(
    [Parameter(Mandatory = $true)][string]$Setup,
    [string]$Exe = ''
)
$ErrorActionPreference = 'Continue'
if ($env:WIN11_INSTALLER_TEST -ne '1') {
    Write-Host 'installer tests change the system: set WIN11_INSTALLER_TEST=1 (CI agent / test VM only)'
    exit 2
}
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'installer tests need administrator rights'
    exit 2
}
$Setup = (Resolve-Path -LiteralPath $Setup).Path

$script:pass = 0; $script:fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host "  [ok]   $name" }
    else { $script:fail++; Write-Host "  [FAIL] $name  $detail" }
}

$appId = '{D3C03EE2-3FF3-4F72-9976-D10B9424046B}_is1'
$uninstKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$appId"
$installDir = Join-Path $env:ProgramFiles 'Win11Privacy'
$dataDir = Join-Path $env:ProgramData 'Win11Privacy'
$startMenu = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
$tasks = @('Win11Privacy Guard', 'Win11Privacy Sensor', 'Win11Privacy Network', 'Win11Privacy Watcher')
$version = ''
$info = Join-Path (Split-Path $PSScriptRoot -Parent) 'src\App\AppInfo.cs'
if (Test-Path -LiteralPath $info) {
    $m = [regex]::Match((Get-Content -LiteralPath $info -Raw), 'Version\s*=\s*"([0-9.]+)"')
    if ($m.Success) { $version = $m.Groups[1].Value }
}
$logDir = Join-Path $env:TEMP ('w11p-setup-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $logDir | Out-Null

# Setup (and the uninstaller, which re-launches itself from %TEMP%) is waited
# for by the process tree; on top of that every check below polls for the end
# state instead of trusting the timing.
function Run-Setup([string[]]$argList, [string]$log) {
    $all = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/LOG="' + (Join-Path $logDir $log) + '"')) + $argList
    $p = Start-Process -FilePath $Setup -ArgumentList $all -Wait -PassThru
    return $p.ExitCode
}
function Run-Uninstall([string[]]$argList) {
    $u = Join-Path $installDir 'unins000.exe'
    if (-not (Test-Path -LiteralPath $u)) { return -1 }
    $p = Start-Process -FilePath $u -ArgumentList (@('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') + $argList) -Wait -PassThru
    # the real work happens in a copy started from %TEMP%: wait until it is done
    for ($i = 0; $i -lt 120; $i++) {
        if (-not (Test-Path -LiteralPath $uninstKey) -and -not (Test-Path -LiteralPath (Join-Path $installDir 'Win11Privacy.exe'))) { break }
        Start-Sleep -Milliseconds 500
    }
    Start-Sleep -Seconds 2
    return $p.ExitCode
}
function Shortcuts {
    $sh = New-Object -ComObject WScript.Shell
    $found = @()
    foreach ($dir in @($startMenu, [Environment]::GetFolderPath('CommonDesktopDirectory'))) {
        foreach ($l in @(Get-ChildItem -LiteralPath $dir -Filter *.lnk -ErrorAction SilentlyContinue)) {
            $t = $sh.CreateShortcut($l.FullName).TargetPath
            if ($t -and $t -like '*\Win11Privacy.exe') { $found += $l.FullName }
        }
    }
    return $found
}
function Task-Exists([string]$name) {
    & "$env:SystemRoot\System32\schtasks.exe" /Query /TN $name 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}
function Users-CanWrite([string]$path) {
    $acl = Get-Acl -LiteralPath $path
    foreach ($r in $acl.Access) {
        if ($r.AccessControlType -ne 'Allow') { continue }
        $sid = $null
        try { $sid = $r.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { }
        if ($sid -notin @('S-1-5-32-545', 'S-1-5-11', 'S-1-1-0')) { continue }   # Users, Authenticated Users, Everyone
        $bits = [int64]$r.FileSystemRights
        if (($bits -band (0x2 -bor 0x4 -bor 0x40000 -bor 0x80000 -bor 0x10000)) -ne 0) { return $true }
    }
    return $false
}

Write-Host "Installer: $Setup"
# "Launch" on the last page cannot be clicked in a silent run, so check the
# script: Inno starts postinstall entries as the original, non-elevated user
# unless told otherwise, and the program (requireAdministrator) then failed
# with CreateProcess error 740.
$iss = Join-Path (Split-Path $PSScriptRoot -Parent) 'installer\Win11Privacy.iss'
if (Test-Path -LiteralPath $iss) {
    $runLine = @(Get-Content -LiteralPath $iss | Where-Object { $_ -match '^\s*Filename:.*AppExe.*postinstall' })
    Check 'post-install launch keeps the setup rights (runascurrentuser)' (($runLine.Count -eq 1) -and ($runLine[0] -match 'runascurrentuser')) ($runLine -join ' / ')
}
$sig = Get-Item -LiteralPath $Setup
Check 'setup file is not suspiciously small' ($sig.Length -gt 1000000) ("{0:N0} bytes" -f $sig.Length)
if ($version) { Check 'setup carries the program version' ($sig.VersionInfo.ProductVersion -like "$version*") $sig.VersionInfo.ProductVersion }

# start from a clean machine state for this package
if (Test-Path -LiteralPath $uninstKey) { $null = Run-Uninstall @() }

Write-Host ''
Write-Host '1. Regular installation'
$code = Run-Setup @() 'install.log'
Check 'setup exit code 0' ($code -eq 0) "code $code"
$exePath = Join-Path $installDir 'Win11Privacy.exe'
Check 'Win11Privacy.exe in Program Files' (Test-Path -LiteralPath $exePath)
if ($Exe -and (Test-Path -LiteralPath $exePath)) {
    $want = (Get-FileHash -LiteralPath $Exe -Algorithm SHA256).Hash
    $got = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
    Check 'installed exe is the built one (SHA-256)' ($want -eq $got)
}
Check 'LICENSE.txt installed' (Test-Path -LiteralPath (Join-Path $installDir 'LICENSE.txt'))
Check 'no portable.txt in a regular installation' (-not (Test-Path -LiteralPath (Join-Path $installDir 'portable.txt')))
Check 'uninstaller present' (Test-Path -LiteralPath (Join-Path $installDir 'unins000.exe'))
Check 'entry in Settings > Apps (uninstall key)' (Test-Path -LiteralPath $uninstKey)
if (Test-Path -LiteralPath $uninstKey) {
    $k = Get-ItemProperty -LiteralPath $uninstKey
    if ($version) { Check 'uninstall entry shows the version' ($k.DisplayVersion -eq $version) $k.DisplayVersion }
    Check 'uninstall entry has the publisher' ($k.Publisher -eq 'N0deZ3r0') $k.Publisher
    Check 'uninstall entry has an icon' ([string]$k.DisplayIcon -like '*Win11Privacy.exe*') $k.DisplayIcon
}
Check 'Start menu shortcut to the program' (@(Shortcuts).Count -ge 1)
Check 'program folder is not writable by ordinary users' (-not (Users-CanWrite $installDir))

Write-Host ''
Write-Host '2. Installing the same version again (upgrade path)'
$code = Run-Setup @() 'reinstall.log'
Check 'setup exit code 0' ($code -eq 0) "code $code"
Check 'still exactly one uninstaller' (@(Get-ChildItem -LiteralPath $installDir -Filter 'unins*.exe').Count -eq 1)
Check 'still one Start menu shortcut' (@(Shortcuts).Count -eq 1) (@(Shortcuts) -join '; ')

Write-Host ''
Write-Host '3. Uninstall keeps the data unless asked, removes the scheduled tasks'
New-Item -ItemType Directory -Force $dataDir | Out-Null
$probe = Join-Path $dataDir 'installer-test-probe.txt'
Set-Content -LiteralPath $probe -Value 'probe' -Encoding ascii
foreach ($t in $tasks) {
    & "$env:SystemRoot\System32\schtasks.exe" /Create /TN $t /TR "$env:SystemRoot\System32\cmd.exe /c exit 0" /SC ONCE /ST 23:59 /RU SYSTEM /F 2>$null | Out-Null
}
Check 'test tasks created' ((@($tasks | Where-Object { Task-Exists $_ })).Count -eq $tasks.Count)
$code = Run-Uninstall @()
Check 'uninstaller exit code 0' ($code -eq 0) "code $code"
Check 'program removed' (-not (Test-Path -LiteralPath $exePath))
Check 'program folder removed' (-not (Test-Path -LiteralPath $installDir))
Check 'uninstall entry removed' (-not (Test-Path -LiteralPath $uninstKey))
Check 'Start menu shortcut removed' (@(Shortcuts).Count -eq 0)
foreach ($t in $tasks) { Check "task removed: $t" (-not (Task-Exists $t)) }
Check 'program data kept (no /PURGE)' (Test-Path -LiteralPath $probe)

Write-Host ''
Write-Host '4. Uninstall with /PURGE=1 removes the program data'
$code = Run-Setup @() 'install2.log'
Check 'setup exit code 0' ($code -eq 0) "code $code"
$code = Run-Uninstall @('/PURGE=1')
Check 'uninstaller exit code 0' ($code -eq 0) "code $code"
Check 'program data removed' (-not (Test-Path -LiteralPath $dataDir))

Write-Host ''
Write-Host '5. Portable version'
$portDir = Join-Path $env:TEMP ('w11p-portable-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$code = Run-Setup @('/PORTABLE=1', ('/DIR="' + $portDir + '"')) 'portable.log'
Check 'setup exit code 0' ($code -eq 0) "code $code"
$unpacked = Test-Path -LiteralPath (Join-Path $portDir 'Win11Privacy.exe')
Check 'Win11Privacy.exe unpacked into the given folder' $unpacked
if (-not $unpacked) {
    Get-Content -LiteralPath (Join-Path $logDir 'portable.log') -ErrorAction SilentlyContinue |
        Where-Object { $_ -match 'Mode:|Dest filename|Creating directory' } | ForEach-Object { Write-Host "         $_" }
}
Check 'portable.txt next to it' (Test-Path -LiteralPath (Join-Path $portDir 'portable.txt'))
Check 'LICENSE.txt next to it' (Test-Path -LiteralPath (Join-Path $portDir 'LICENSE.txt'))
Check 'no uninstaller in the portable folder' (@(Get-ChildItem -LiteralPath $portDir -Filter 'unins*' -ErrorAction SilentlyContinue).Count -eq 0)
Check 'nothing in Settings > Apps' (-not (Test-Path -LiteralPath $uninstKey))
Check 'no Start menu shortcut' (@(Shortcuts).Count -eq 0)
Check 'nothing put into Program Files' (-not (Test-Path -LiteralPath $installDir))
cmd /c rmdir /s /q "$portDir" 2>$null

Write-Host ''
Write-Host ("Installer checks: {0} passed, {1} failed" -f $script:pass, $script:fail)
Write-Host "Setup logs: $logDir"
if ($script:fail -gt 0) { exit 1 }
exit 0
