
# =========================================================================== #
#  ПРЕДУСТАНОВЛЕННЫЕ ПРИЛОЖЕНИЯ
#  Список того, что можно безопасно удалить, и само удаление.
# =========================================================================== #

# Трогать нельзя никогда — без этого система ломается
$script:AppxProtected = @(
    'Microsoft.WindowsStore','Microsoft.DesktopAppInstaller','Microsoft.StorePurchaseApp',
    'Microsoft.VCLibs','Microsoft.NET','Microsoft.UI.Xaml','Microsoft.Services.Store',
    'Microsoft.WindowsTerminal','Microsoft.SecHealthUI','Microsoft.Windows.Photos.Addon',
    'MicrosoftWindows.Client','Microsoft.AAD','Microsoft.AccountsControl','Microsoft.Win32WebViewHost',
    'Microsoft.CredDialogHost','Microsoft.ECApp','Microsoft.LockApp','Microsoft.Windows.ShellExperienceHost',
    'Microsoft.Windows.StartMenuExperienceHost','Microsoft.Windows.SecureAssessmentBrowser',
    'Microsoft.WindowsAppRuntime','Microsoft.HEIFImageExtension','Microsoft.HEVCVideoExtension',
    'Microsoft.WebpImageExtension','Microsoft.RawImageExtension','Microsoft.VP9VideoExtensions',
    'Microsoft.WebMediaExtensions','Microsoft.MicrosoftEdge'
)

# Что обычно ставят без спроса — помечаем как «можно убрать»
$script:AppxBloat = @{
    'MicrosoftWindows.Client.WebExperience' = 'Виджеты и лента Microsoft Start'
    'Microsoft.BingNews'                = 'Новости MSN'
    'Microsoft.BingWeather'             = 'Погода MSN'
    'Microsoft.BingSearch'              = 'Поиск Bing в Пуске'
    'Microsoft.BingFinance'             = 'Финансы MSN'
    'Microsoft.BingSports'              = 'Спорт MSN'
    'Clipchamp.Clipchamp'               = 'Видеоредактор Clipchamp'
    'Microsoft.GamingApp'               = 'Приложение Xbox'
    'Microsoft.XboxGameOverlay'         = 'Игровая панель Xbox'
    'Microsoft.XboxGamingOverlay'       = 'Игровая панель Xbox'
    'Microsoft.XboxIdentityProvider'    = 'Вход Xbox'
    'Microsoft.XboxSpeechToTextOverlay' = 'Субтитры Xbox'
    'Microsoft.MicrosoftSolitaireCollection' = 'Коллекция пасьянсов'
    'Microsoft.MicrosoftOfficeHub'      = 'Промо Microsoft 365'
    'Microsoft.Office.OneNote'          = 'OneNote из магазина'
    'MicrosoftTeams'                    = 'Teams (личный)'
    'MSTeams'                           = 'Teams (личный)'
    'Microsoft.SkypeApp'                = 'Skype'
    'Microsoft.YourPhone'               = 'Связь с телефоном'
    'Microsoft.People'                  = 'Люди'
    'Microsoft.WindowsMaps'             = 'Карты'
    'Microsoft.WindowsFeedbackHub'      = 'Центр отзывов'
    'Microsoft.GetHelp'                 = 'Справка'
    'Microsoft.Getstarted'              = 'Советы'
    'Microsoft.Microsoft3DViewer'       = 'Просмотр 3D'
    'Microsoft.MixedReality.Portal'     = 'Портал смешанной реальности'
    'Microsoft.ZuneMusic'               = 'Медиапроигрыватель'
    'Microsoft.ZuneVideo'               = 'Фильмы и ТВ'
    'Microsoft.Todos'                   = 'To Do'
    'Microsoft.PowerAutomateDesktop'    = 'Power Automate'
    'Microsoft.Windows.DevHome'         = 'Dev Home'
    'MicrosoftCorporationII.QuickAssist'= 'Быстрая помощь'
    'Microsoft.Copilot'                 = 'Copilot'
    'Microsoft.Windows.Ai.Copilot.Provider' = 'Copilot (компонент)'
    'Microsoft.OutlookForWindows'       = 'Новый Outlook'
    'Microsoft.MicrosoftStickyNotes'    = 'Записки'
    'Microsoft.549981C3F5F10'           = 'Cortana'
}

# Исключения из защищённых префиксов: сама «оболочка» MicrosoftWindows.Client
# трогать нельзя, а вот доска виджетов внутри неё удаляется безболезненно —
# на Home это единственный способ убрать её совсем.
$script:AppxAllowed = @('MicrosoftWindows.Client.WebExperience')

function Test-AppxProtected {
    param([string]$Name)
    foreach ($a in $script:AppxAllowed) { if ($Name -eq $a) { return $false } }
    foreach ($p in $script:AppxProtected) { if ($Name -like ($p + '*')) { return $true } }
    return $false
}

function Get-AppxList {
    $list = @()
    $pkgs = @()
    try { $pkgs = @(Get-AppxPackage -ErrorAction Stop | Where-Object { -not $_.IsFramework }) } catch { }
    foreach ($p in $pkgs) {
        $name = [string]$p.Name
        if (Test-AppxProtected $name) { continue }
        $bloat = $script:AppxBloat.ContainsKey($name)
        $title = if ($bloat) { $script:AppxBloat[$name] } else { $name }
        $list += @{ name = $name; title = $title; publisher = [string]$p.Publisher
                    version = [string]$p.Version; bloat = [bool]$bloat
                    system = [bool]($p.SignatureKind -eq 'System') }
    }
    return @($list | Sort-Object { -[int][bool]$_.bloat }, { $_.title })
}

if ($ListApps) {
    $appList = @(Get-AppxList)      # через переменную — иначе один элемент уедет объектом
    Emit-Json @{ apps = $appList; time = (Get-Date).ToString('yyyy-MM-dd HH:mm') }
    exit 0
}

if ($RemoveApps) {
    Write-Section 'Удаление предустановленных приложений'
    if ($AppItems.Count -eq 0) { Write-Log '   [-] ничего не выбрано'; Write-Log '###DONE###'; exit 0 }
    $done = 0
    foreach ($name in $AppItems) {
        if (Test-AppxProtected $name) { Write-Log ("   [-] {0} — системный компонент, пропущен" -f $name); continue }
        if ($DryRun) { Write-Log ("   [тест] {0} — будет удалён" -f $name); continue }
        $pkgs = @(Get-AppxPackage -Name $name -ErrorAction SilentlyContinue)
        if ($pkgs.Count -eq 0) { Write-Log ("   [-] {0} — не найден" -f $name); continue }
        foreach ($p in $pkgs) {
            try {
                Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop
                Write-Log ("   [+] удалён: {0}" -f $name); $done++; $script:Changes++
            } catch { Write-Log ("   [!] {0} -- {1}" -f $name, $_.Exception.Message); $script:Failures++ }
        }
        if ($AllUsers -and (Test-Admin)) {
            try {
                $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $name })
                foreach ($pp in $prov) {
                    Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null
                    Write-Log ("   [+] больше не ставится новым пользователям: {0}" -f $name)
                }
            } catch {
                # раньше молча: приложение удалялось у вас, но возвращалось каждому новому пользователю
                Write-Log ("   [!] {0} -- для новых пользователей не убрано: {1}" -f $name, $_.Exception.Message); $script:Failures++
            }
        }
    }
    Write-Log ("   удалено приложений: {0}" -f $done)
    Emit-Json @{ removed = $done }
    Write-Log '###DONE###'
    exit 0
}

if ($CleanJunk) {
    if (-not (Test-Admin)) { Write-Log 'Нужны права администратора.'; Emit-Json @{ error='нужны права администратора' }; Write-Log '###DONE###'; exit 1 }
    Write-Section 'Уборка за старыми версиями'
    $before = @(Find-JunkValues).Count
    $gone = Remove-JunkValues
    if ($before -eq 0) { Write-Log '   [-] мусорных параметров нет' }
    Emit-Json @{ found = $before; removed = $gone }
    Write-Log '###DONE###'
    exit 0
}
