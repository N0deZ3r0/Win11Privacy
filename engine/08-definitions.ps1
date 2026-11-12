
# =========================================================================== #
#  Декларативные определения настроек
# =========================================================================== #
$script:Defs = New-Object System.Collections.Generic.List[object]
$script:DefSeq = @{}
# У каждой настройки есть свой номер вида telemetry#3 — по нему интерфейс
# может отключить отдельный пункт внутри модуля.
function Def {
    # ОСТОРОЖНО: имена переменных в PowerShell регистронезависимы. Счётчик
    # раньше звался $n и затирал параметр $N — в реестр вместо AllowTelemetry
    # писалось значение с именем «0». Любая локальная переменная здесь обязана
    # отличаться от имён параметров не только регистром.
    param($M, $T, $P, $N, $V, $Type = 'DWord', $C = '', $Min = 0)
    $seq = 0
    if ($script:DefSeq.ContainsKey($M)) { $seq = [int]$script:DefSeq[$M] }
    $script:DefSeq[$M] = $seq + 1
    # Повтор в одном разделе (две задачи Proxy и DmClientOnScenarioDownload
    # в списке служб) давал две одинаковые строки и считался дважды. Номер
    # всё равно занимаем: по номерам профили помнят снятые пункты, и сдвиг
    # переставил бы их на соседей.
    foreach ($x in $script:Defs) {
        if ($x.M -eq $M -and $x.T -eq $T -and "$($x.P)" -eq "$P" -and "$($x.N)" -eq "$N") { return }
    }
    $script:Defs.Add(@{ M=$M; T=$T; P=$P; N=$N; V=$V; Type=$Type; C=$C; Min=[int]$Min
                        Id=("{0}#{1}" -f $M, $seq) })
}

$dc  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
Def 'telemetry' 'reg' $dc 'AllowTelemetry' 0 'DWord' 'уровень телеметрии — минимальный'
Def 'telemetry' 'reg' $dc 'MaxTelemetryAllowed' 1 'DWord' 'потолок телеметрии'
Def 'telemetry' 'reg' $dc 'AllowDeviceNameInTelemetry' 0 'DWord' 'не отправлять имя устройства'
Def 'telemetry' 'reg' $dc 'DoNotShowFeedbackNotifications' 1 'DWord' 'не запрашивать отзывы'
Def 'telemetry' 'reg' $dc 'LimitDiagnosticLogCollection' 1 'DWord' 'не собирать диагностические логи'
Def 'telemetry' 'reg' $dc 'LimitDumpCollection' 1 'DWord' 'не собирать дампы памяти'
Def 'telemetry' 'reg' $dc 'DisableOneSettingsDownloads' 1 'DWord' 'отключить загрузку конфигураций OneSettings'
Def 'telemetry' 'reg' $dc 'AllowCommercialDataPipeline' 0 'DWord' 'отключить коммерческий канал данных'
Def 'telemetry' 'reg' $dc 'AllowUpdateComplianceProcessing' 0 'DWord' 'отключить Update Compliance'
Def 'telemetry' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 'DWord' 'без рекомендаций на основе диагностики'
Def 'telemetry' 'reg' 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0 'DWord' 'опросы Центра отзывов — выкл'
Def 'telemetry' 'reg' 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Settings\AllowExperimentation' 'value' 0 'DWord' 'эксперименты Microsoft — выкл'
# Телеметрия совместимости живёт отдельно от DiagTrack: опись программ,
# оценщик совместимости и запись действий пользователя шлют свои данные.
Def 'telemetry' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0 'DWord' 'программа улучшения качества (CEIP) — выкл'
Def 'telemetry' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'AITEnable' 0 'DWord' 'телеметрия совместимости приложений — выкл'
Def 'telemetry' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1 'DWord' 'опись установленных программ — выкл'
Def 'telemetry' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableUAR' 1 'DWord' 'запись действий пользователя (Steps Recorder) — выкл'
Def 'telemetry' 'reg' 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1 'DWord' 'персонализация по диагностике — запрет политикой'

Def 'errors' 'reg' 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1 'DWord' 'отправка отчётов об ошибках — выкл'
Def 'errors' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1 'DWord' 'то же, политикой'
Def 'errors' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'DontSendAdditionalData' 1 'DWord' 'не отправлять дополнительные данные'

$cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$cc  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
Def 'ads' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 'DWord' 'рекламный ID — выкл'
Def 'ads' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1 'DWord' 'рекламный ID заблокирован политикой'
Def 'ads' 'reg' $cdm 'SystemPaneSuggestionsEnabled' 0 'DWord' 'реклама приложений в меню Пуск'
Def 'ads' 'reg' $cdm 'SilentInstalledAppsEnabled' 0 'DWord' 'тихая установка рекламных приложений'
Def 'ads' 'reg' $cdm 'PreInstalledAppsEnabled' 0 'DWord' 'предустановка партнёрских приложений'
Def 'ads' 'reg' $cdm 'OemPreInstalledAppsEnabled' 0 'DWord' 'предустановка приложений OEM'
Def 'ads' 'reg' $cdm 'SoftLandingEnabled' 0 'DWord' 'всплывающие подсказки-реклама'
Def 'ads' 'reg' $cdm 'RotatingLockScreenOverlayEnabled' 0 'DWord' 'реклама на экране блокировки'
Def 'ads' 'reg' $cdm 'SubscribedContent-338388Enabled' 0 'DWord' 'предложения в меню Пуск'
Def 'ads' 'reg' $cdm 'SubscribedContent-338389Enabled' 0 'DWord' 'советы и подсказки Windows'
Def 'ads' 'reg' $cdm 'SubscribedContent-338393Enabled' 0 'DWord' 'предложения в Параметрах'
Def 'ads' 'reg' $cdm 'SubscribedContent-353694Enabled' 0 'DWord' 'предложения в Параметрах (2)'
Def 'ads' 'reg' $cdm 'SubscribedContent-353696Enabled' 0 'DWord' 'предложения в Параметрах (3)'
Def 'ads' 'reg' $cdm 'SubscribedContent-310093Enabled' 0 'DWord' 'приветственные экраны после обновлений'
Def 'ads' 'reg' $cdm 'ContentDeliveryAllowed' 0 'DWord' 'доставка рекламного контента'
Def 'ads' 'reg' $cc 'DisableWindowsConsumerFeatures' 1 'DWord' 'авто-установка игр и промо-приложений'
Def 'ads' 'reg' $cc 'DisableCloudOptimizedContent' 1 'DWord' 'облачный «оптимизированный» контент'
Def 'ads' 'reg' $cc 'DisableConsumerAccountStateContent' 1 'DWord' 'реклама подписок Microsoft'
Def 'ads' 'reg' $cc 'DisableSoftLanding' 1 'DWord' 'подсказки Windows'
Def 'ads' 'reg' $cc 'DisableWindowsSpotlightFeatures' 1 'DWord' 'Windows Spotlight'
Def 'ads' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0 'DWord' 'рекомендации в меню Пуск'
Def 'ads' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0 'DWord' 'реклама OneDrive в Проводнике'
Def 'ads' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0 'DWord' '«Получите больше от Windows» после обновлений — выкл'
# Найдены в каталоге политик Windows (PolicyManager): реклама и «интересное»,
# которые программа раньше не трогала. Пользовательские — в HKCU.
$ccu = 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent'
Def 'ads' 'reg' $ccu 'DisableThirdPartySuggestions' 1 'DWord' 'предложения сторонних приложений в «интересном» — выкл'
Def 'ads' 'reg' $ccu 'DisableWindowsSpotlightOnActionCenter' 1 'DWord' '«интересное» в центре уведомлений — выкл'
Def 'ads' 'reg' $ccu 'DisableWindowsSpotlightOnSettings' 1 'DWord' '«интересное» в Параметрах — выкл'
Def 'ads' 'reg' $ccu 'DisableWindowsSpotlightWindowsWelcomeExperience' 1 'DWord' 'приветственная реклама после обновлений — выкл'
Def 'ads' 'reg' $ccu 'DisableSpotlightCollectionOnDesktop' 1 'DWord' 'обои «Windows: интересное» на рабочем столе — выкл'
# Экран «Закрепите Copilot» при входе (ShellAppRuntime.exe, рекламные блоки 88000325/88000326)
Def 'ads' 'reg' $cc 'DisableCopilotPinScreen' 1 'DWord' 'экран «Закрепите Copilot» при входе — выкл'
# Реклама приложений в окне «Поделиться» (SharePickerUI.dll)
Def 'ads' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\ShareSheet' 'DisableShareAppPromotions' 1 'DWord' 'реклама приложений в окне «Поделиться» — выкл'
# Блок «Справка из интернета» в «Параметрах»: при открытии страницы приложение
# отправляет POST на www.bing.com/RelatedSearch с тем, какую страницу вы
# смотрите. Найдено записью Windows 11 с программой на максимуме.
Def 'ads' 'regpol' 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'AllowOnlineTips' 0 'DWord' 'советы из интернета в «Параметрах» (запросы к Bing) — выкл'

$sys = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
Def 'activity' 'reg' $sys 'EnableActivityFeed' 0 'DWord' 'лента активности — выкл'
Def 'activity' 'reg' $sys 'PublishUserActivities' 0 'DWord' 'не публиковать активность'
Def 'activity' 'reg' $sys 'UploadUserActivities' 0 'DWord' 'не выгружать активность в облако'
Def 'activity' 'reg' $sys 'AllowClipboardHistory' 0 'DWord' 'история буфера обмена — выкл'
Def 'activity' 'reg' $sys 'AllowCrossDeviceClipboard' 0 'DWord' 'синхронизация буфера между устройствами — выкл'
Def 'activity' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0 'DWord' 'Пуск: не отслеживать запуск программ'
Def 'activity' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SmartActionPlatform\SmartClipboard' 'Disabled' 1 'DWord' 'буфер обмена: «предлагаемые действия» — выкл'

Def 'input' 'reg' 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1 'DWord' 'не собирать набранный текст'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1 'DWord' 'не собирать рукописный ввод'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0 'DWord' 'не собирать контакты'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0 'DWord' 'персонализация ввода — отказ'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0 'DWord' 'облачное распознавание речи — выкл'
Def 'input' 'reg' 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1 'DWord' 'не отдавать сайтам список языков'
Def 'input' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\appDiagnostics' 'Value' 'Deny' 'String' 'приложениям запрещена диагностика других приложений'
Def 'input' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC' 'PreventHandwritingDataSharing' 1 'DWord' 'не отправлять образцы рукописного ввода'
Def 'input' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports' 'PreventHandwritingErrorReports' 1 'DWord' 'не отправлять отчёты об ошибках распознавания рукописи'

$su = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
$sm = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
Def 'search' 'reg' $su 'BingSearchEnabled' 0 'DWord' 'поиск Bing в меню Пуск — выкл'
Def 'search' 'reg' $su 'CortanaConsent' 0 'DWord' 'согласие Cortana снято'
Def 'search' 'reg' $su 'DeviceHistoryEnabled' 0 'DWord' 'история поиска на устройстве — выкл'
Def 'search' 'reg' $su 'HistoryViewEnabled' 0 'DWord' 'показ истории поиска — выкл'
Def 'search' 'reg' $sm 'AllowCortana' 0 'DWord' 'Cortana — выкл'
Def 'search' 'reg' $sm 'DisableWebSearch' 1 'DWord' 'веб-поиск из Пуска — выкл'
Def 'search' 'reg' $sm 'ConnectedSearchUseWeb' 0 'DWord' 'не обращаться к вебу при поиске'
Def 'search' 'reg' $sm 'AllowSearchToUseLocation' 0 'DWord' 'поиск не использует геолокацию'
Def 'search' 'reg' $sm 'AllowCloudSearch' 0 'DWord' 'облачный поиск по OneDrive/Outlook — выкл'
Def 'search' 'reg' $sm 'EnableDynamicContentInWSB' 0 'DWord' 'рекламные подсказки в поле поиска — выкл'
Def 'search' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDeviceSearchHistoryEnabled' 0 'DWord' 'история поиска на устройстве (Параметры) — выкл'

$ai = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
Def 'copilot' 'reg' 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 'DWord' 'Windows Copilot — выкл' 22000
Def 'copilot' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 'DWord' 'Windows Copilot — выкл для всех' 22000
Def 'copilot' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0 'DWord' 'кнопка Copilot на панели задач — убрать' 22000
Def 'copilot' 'reg' $ai 'DisableAIDataAnalysis' 1 'DWord' 'Recall (снимки экрана) — выкл' 26100
Def 'copilot' 'reg' $ai 'AllowRecallEnablement' 0 'DWord' 'запрет включения Recall' 26100
Def 'copilot' 'reg' 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1 'DWord' 'Recall — выкл для пользователя' 26100
Def 'copilot' 'reg' $ai 'AllowRecallExport' 0 'DWord' 'Recall: выгрузка снимков — запрещена' 26100

# Весь ИИ Windows
Def 'ai' 'reg' $ai 'DisableClickToDo' 1 'DWord' 'Click to Do — выкл' 26100
Def 'ai' 'reg' $ai 'TurnOffSavingSnapshots' 1 'DWord' 'сохранение снимков экрана — выкл' 26100
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Notepad' 'DisableAIFeatures' 1 'DWord' 'Copilot в Блокноте — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Paint' 'DisableCocreator' 1 'DWord' 'Paint Cocreator — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Paint' 'DisableGenerativeFill' 1 'DWord' 'Paint: генеративная заливка — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Paint' 'DisableImageCreator' 1 'DWord' 'Paint Image Creator — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'CopilotPageContext' 0 'DWord' 'Edge: Copilot не читает страницы'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'CopilotCDPPageContext' 0 'DWord' 'Edge: Copilot без контекста вкладок'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'ComposeInlineEnabled' 0 'DWord' 'Edge: ИИ-подсказки при наборе — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'EdgeHistoryAISearchEnabled' 0 'DWord' 'Edge: ИИ-поиск по истории — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'EdgeEntityExtractionEnabled' 0 'DWord' 'Edge: извлечение сущностей — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'Microsoft365CopilotChatIconEnabled' 0 'DWord' 'Edge: значок Copilot — убрать'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableGraphRecentItems' 1 'DWord' 'Проводник: облачные «недавние» — выкл'
Def 'ai' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'HideRecommendedSection' 1 'DWord' 'Пуск: раздел «Рекомендуем» — скрыть' 22000
Def 'ai' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowRecommendations' 0 'DWord' 'Проводник: рекомендации в «Главной» — выкл' 22000
# Политика выключает сам Click to Do, но задача по-прежнему скачивает его
# модели ИИ. Администратору Windows её не отдаёт — отключается от SYSTEM.
Def 'ai' 'task' '\Microsoft\Windows\WindowsAI\ClickToDo\ModelCachingUpdate' '' 'Disabled' '' 'Click to Do: скачивание моделей ИИ — выкл' 26100
# ИИ-агенты работают с Windows через MCP-«коннекторы» (служба McpManagementService,
# доступ выдаёт CapabilityAccessManager). 2 — запретить (шаблон CAM_AI.admx).
Def 'ai' 'reg' $ai 'ConfigureAgentConnectors' 2 'DWord' 'ИИ-агенты: доступ к файлам и настройкам через MCP — запрещён' 26100
Def 'ai' 'reg' $ai 'DisableSettingsAgent' 1 'DWord' 'ИИ-агент в Параметрах — выкл' 26100

$e = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
Def 'edge' 'reg' $e 'MetricsReportingEnabled' 0 'DWord' 'статистика использования — выкл'
Def 'edge' 'reg' $e 'DiagnosticData' 0 'DWord' 'диагностические данные — выкл'
Def 'edge' 'reg' $e 'SendSiteInfoToImproveServices' 0 'DWord' 'не отправлять адреса сайтов'
Def 'edge' 'reg' $e 'PersonalizationReportingEnabled' 0 'DWord' 'персонализация рекламы — выкл'
Def 'edge' 'reg' $e 'UserFeedbackAllowed' 0 'DWord' 'отзывы — выкл'
Def 'edge' 'reg' $e 'EdgeShoppingAssistantEnabled' 0 'DWord' 'шопинг-ассистент — выкл'
Def 'edge' 'reg' $e 'AlternateErrorPagesEnabled' 0 'DWord' 'не отправлять ошибочные адреса'
Def 'edge' 'reg' $e 'SearchSuggestEnabled' 0 'DWord' 'подсказки поиска (отправка ввода) — выкл'
Def 'edge' 'reg' $e 'HubsSidebarEnabled' 0 'DWord' 'боковая панель Copilot — выкл'
Def 'edge' 'reg' $e 'TrackingPrevention' 2 'DWord' 'блокировка отслеживания — сбалансированная'

Def 'delivery' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0 'DWord' 'не раздавать обновления в интернет'

$loc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'
Def 'location' 'reg' $loc 'DisableLocation' 1 'DWord' 'служба геолокации — выкл'
Def 'location' 'reg' $loc 'DisableWindowsLocationProvider' 1 'DWord' 'поставщик местоположения Windows — выкл'
Def 'location' 'reg' 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String' 'доступ приложений к местоположению — запрещён'
Def 'location' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice' 'AllowFindMyDevice' 0 'DWord' '«Поиск устройства» (отправка координат) — выкл'
Def 'location' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsAccessLocation' 2 'DWord' 'приложениям запрещено местоположение (политика)'

# Разрешения приложений — политикой, а не переключателями. Переключатель в
# ConsentStore может вернуть кто угодно: Windows после обновления, установщик,
# сам человек одним щелчком. Политика AppPrivacy стоит насмерть. Сюда же входит
# доступ к сведениям учётной записи — через него приложения узнают возраст
# пользователя (Windows Age API): без этого права вызов падает с E_ACCESSDENIED.
$ap = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
Def 'apppriv' 'reg' $ap 'LetAppsAccessAccountInfo' 2 'DWord' 'сведения учётной записи и возраст (Age API) — запрещены'
Def 'apppriv' 'reg' $ap 'LetAppsAccessContacts' 2 'DWord' 'контакты — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessCalendar' 2 'DWord' 'календарь — запрещён приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessCallHistory' 2 'DWord' 'журнал звонков — запрещён приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessEmail' 2 'DWord' 'почта — запрещена приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessMessaging' 2 'DWord' 'сообщения — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessPhone' 2 'DWord' 'звонки — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessTasks' 2 'DWord' 'задачи и планы — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessNotifications' 2 'DWord' 'чтение уведомлений — запрещено приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessMotion' 2 'DWord' 'данные о движении — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessRadios' 2 'DWord' 'управление радиомодулями — запрещено приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsSyncWithDevices' 2 'DWord' 'обмен с устройствами — запрещён приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsAccessTrustedDevices' 2 'DWord' 'доверенные устройства — запрещены приложениям'
Def 'apppriv' 'reg' $ap 'LetAppsGetDiagnosticInfo' 2 'DWord' 'диагностика других приложений — запрещена'
Def 'apppriv' 'reg' $ap 'LetAppsActivateWithVoice' 2 'DWord' 'голосовая активация приложений — запрещена'
Def 'apppriv' 'reg' $ap 'LetAppsActivateWithVoiceAboveLock' 2 'DWord' 'голосовая активация на экране блокировки — запрещена'
Def 'apppriv' 'reg' $ap 'LetAppsAccessSystemAIModels' 2 'DWord' 'встроенные ИИ-модели Windows — запрещены приложениям' 26100

# Камера, микрофон и фоновая работа — отдельно: без них приложения из магазина
# теряют эти функции. Обычных программ (браузеров, мессенджеров) не касается.
Def 'apphw' 'reg' $ap 'LetAppsAccessCamera' 2 'DWord' 'камера — запрещена приложениям из магазина'
Def 'apphw' 'reg' $ap 'LetAppsAccessMicrophone' 2 'DWord' 'микрофон — запрещён приложениям из магазина'
Def 'apphw' 'reg' $ap 'LetAppsRunInBackground' 2 'DWord' 'фоновая работа приложений из магазина — запрещена'

# Что Windows скачивает и отправляет сама, без вашего запроса. Всё — из
# официального списка Microsoft «Manage connections from Windows operating
# system components to Microsoft services», только безопасные пункты.
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1 'DWord' 'не скачивать метаданные устройств'
Def 'network' 'reg' $sys 'EnableFontProviders' 0 'DWord' 'не скачивать шрифты по требованию'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds' 'AllowBuildPreview' 0 'DWord' 'сборки Insider — запрет'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Maps' 'AutoDownloadAndUpdateMapData' 0 'DWord' 'офлайн-карты: не обновлять сами'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Maps' 'AllowUntriggeredNetworkTrafficOnSettingsPage' 0 'DWord' 'офлайн-карты: без трафика на странице настроек'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Microsoft\OneDrive' 'PreventNetworkTrafficPreUserSignIn' 1 'DWord' 'OneDrive: не выходить в сеть до входа в систему'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Speech' 'AllowSpeechModelUpdate' 0 'DWord' 'не обновлять речевые модели'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageHealth' 'AllowDiskHealthModelUpdates' 0 'DWord' 'не скачивать модели здоровья дисков'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Messaging' 'AllowMessageSync' 0 'DWord' 'не синхронизировать сообщения с облаком'
Def 'network' 'reg' 'HKCU:\SOFTWARE\Microsoft\Messaging' 'CloudServiceSyncEnabled' 0 'DWord' 'облачная синхронизация сообщений — выкл'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TCPIP\v6Transition' 'Teredo_State' 'Disabled' 'String' 'Teredo (туннель IPv6 через Microsoft) — выкл'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config' 'AutoConnectAllowedOEM' 0 'DWord' 'Wi-Fi Sense — выкл'
Def 'network' 'task' '\Microsoft\Windows\Sustainability\PowerGridForecastTask' '' 'Disabled' '' 'не скачивать прогноз нагрузки энергосети'
# Магазин умеет ставить приложения на этот ПК по команде с сайта, без
# действий за компьютером (служба PushToInstall, pti.store.microsoft.com).
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\PushToInstall' 'DisablePushToInstall' 1 'DWord' 'установка приложений на этот ПК по команде с сайта — выкл'
# «Рекомендуемое устранение неполадок»: MitigationClient получает от
# Microsoft «исправления» (troubleshooting.microsoft.com/api/Mitigation)
# и применяет их сам. UserPreference = 1 — «не запускать».
Def 'network' 'reg' 'HKLM:\SOFTWARE\Microsoft\WindowsMitigation' 'UserPreference' 1 'DWord' 'не применять «исправления», присланные Microsoft'
Def 'network' 'task' '\Microsoft\Windows\Diagnosis\RecommendedTroubleshootingScanner' '' 'Disabled' '' 'задача RecommendedTroubleshootingScanner (поиск «исправлений» Microsoft)'
Def 'network' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\ScriptedDiagnosticsProvider\Policy' 'EnableQueryRemoteServer' 0 'DWord' 'средства устранения неполадок не обращаются к серверам Microsoft'

# Облачная синхронизация и копия. Windows 11 без вопроса выгружает в облако
# Microsoft список ваших приложений («Архивация Windows»), сети Wi-Fi, язык,
# тему, настройки пера — и даже ваши ответы на вопросы о конфиденциальности.
# Всё найдено на чистой Windows 11 25H2; задачи отключаются и включаются
# обратно без последствий для системы.
$ss = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync'
Def 'cloudsync' 'reg' $ss 'DisableSettingSync' 2 'DWord' 'синхронизация параметров между устройствами — выкл'
Def 'cloudsync' 'reg' $ss 'DisableSettingSyncUserOverride' 1 'DWord' 'синхронизацию параметров не включить обратно в Параметрах'
Def 'cloudsync' 'task' '\Microsoft\Windows\AppListBackup\Backup' '' 'Disabled' '' 'копия списка приложений в облако — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\AppListBackup\BackupNonMaintenance' '' 'Disabled' '' 'внеплановая копия списка приложений — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\CloudRestore\Backup' '' 'Disabled' '' 'архивация Windows в облако — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\ConsentUX\UnifiedConsent\UnifiedConsentSyncTask' '' 'Disabled' '' 'синхронизация ваших согласий на сбор данных — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\WlanSvc\CDSSync' '' 'Disabled' '' 'синхронизация сетей Wi-Fi между устройствами — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\International\Synchronize Language Settings' '' 'Disabled' '' 'синхронизация языковых настроек — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\Shell\ThemesSyncedImageDownload' '' 'Disabled' '' 'скачивание обоев с других ваших устройств — выкл'
Def 'cloudsync' 'task' '\Microsoft\Windows\input\syncpensettings' '' 'Disabled' '' 'синхронизация настроек пера — выкл'
# Само приложение «Архивация Windows» (CloudRestoreLauncher.dll, SyncSettings.dll)
Def 'cloudsync' 'reg' $ss 'EnableWindowsBackup' 0 'DWord' 'приложение «Архивация Windows» — выкл'

Def 'widgets' 'regpol' 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 'DWord' 'виджеты и лента новостей MSN — выкл' 22000
Def 'widgets' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 0 'DWord' 'кнопка виджетов на панели задач — убрать' 22000
Def 'widgets' 'regpol' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0 'DWord' 'лента новостей и интересов — выкл (запасной ключ)'
Def 'widgets' 'regpol' 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'DisableWidgetsBoard' 1 'DWord' 'панель виджетов — выкл' 22000
Def 'widgets' 'regpol' 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'DisableWidgetsOnLockScreen' 1 'DWord' 'виджеты на экране блокировки — выкл' 22000

$dfn = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'
Def 'defender' 'reg' $dfn 'SpyNetReporting' 0 'DWord' 'Защитник: облачная отправка MAPS — выкл'
Def 'defender' 'reg' $dfn 'SubmitSamplesConsent' 2 'DWord' 'Защитник: отправка образцов файлов — никогда'
# Служба ядра Защитника (MDCoreSvc) раз в час забирает с ecs.office.com около
# 130 удалённых настроек: включение функций, проверку запросов к ИИ-агентам,
# уведомления Microsoft 365. Проверено в виртуалке: с этой политикой обращения
# к ECS пропадают. Её же DisableCoreService1DSTelemetry отправку телеметрии
# не остановил — её закрывает hosts (mobile.events.data.microsoft.com).
Def 'defender' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Features' 'DisableCoreServiceECSIntegration' 1 'DWord' 'Защитник: удалённые настройки и эксперименты (ECS) — выкл'

Def 'services' 'svc' 'DiagTrack' '' 'Disabled' '' 'служба DiagTrack (телеметрия)'
Def 'services' 'svc' 'dmwappushservice' '' 'Disabled' '' 'служба dmwappushservice (WAP push)'
foreach ($tp in @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraisal',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
    '\Microsoft\Windows\Application Experience\PcaPatchDbTask',
    '\Microsoft\Windows\Application Experience\StartupAppTask',
    '\Microsoft\Windows\Application Experience\MareBackup',
    '\Microsoft\Windows\Application Experience\AitAgent',
    '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask',
    '\Microsoft\Windows\Customer Experience Improvement Program\BthSQM',
    '\Microsoft\Windows\Customer Experience Improvement Program\Uploader',
    '\Microsoft\Windows\Device Information\Device',
    '\Microsoft\Windows\Device Information\Device User',
    '\Microsoft\Windows\DiskFootprint\Diagnostics',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver',
    '\Microsoft\Windows\Maintenance\WinSAT',
    '\Microsoft\Windows\NetTrace\GatherNetworkInfo',
    '\Microsoft\Windows\PI\Sqm-Tasks',
    '\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem',
    '\Microsoft\Windows\Windows Error Reporting\ProcessQueuedCallHomeReports',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
    '\Microsoft\Windows\Clip\License Validation',
    '\Microsoft\Windows\CloudExperienceHost\CreateObjectTask',
    '\Microsoft\Windows\Shell\FamilySafetyMonitor',
    '\Microsoft\Windows\Shell\FamilySafetyRefreshTask',
    '\Microsoft\Windows\Speech\SpeechModelDownloadTask',
    '\Microsoft\Windows\Autochk\Proxy',
    # Появились в Windows 11 24H2–25H2. Оценщик совместимости «Exp» запускает
    # compattelrunner с DoScheduledTelemetryRun — старую задачу «Appraisal»
    # движок закрывал, а эта шла мимо. FeatureConfig\UsageData* — отчёты о том,
    # какими функциями вы пользуетесь.
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp',
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReporting',
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReceiver',
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing',
    '\Microsoft\Windows\Flighting\FeatureConfig\BootstrapUsageDataReporting',
    '\Microsoft\Windows\Flighting\FeatureConfig\GovernedFeatureUsageProcessing',
    '\Microsoft\Windows\Flighting\OneSettings\RefreshCache',
    '\Microsoft\Windows\Sustainability\SustainabilityTelemetry',
    '\Microsoft\Windows\PerformanceTrace\ShowFeedbackToast',
    '\Microsoft\Windows\Maps\MapsToastTask')) {
    Def 'services' 'task' $tp '' 'Disabled' '' ('задача ' + (Split-Path $tp -Leaf))
}
# Тоже из Windows 11 24H2–25H2, нашлись на чистой системе. InventorySvc
# работает постоянно и составляет опись установленных программ и
# оборудования для оценки совместимости и телеметрии. Usage and Quality
# Insights копит на диске «факты» о том, какими функциями вы пользуетесь,
# и выгружает их через телеметрию; её задача закрыта от администратора.
Def 'services' 'svc' 'InventorySvc' '' 'Disabled' '' 'служба InventorySvc (опись программ и оборудования)' 26100
Def 'services' 'task' '\Microsoft\Windows\UsageAndQualityInsights\UsageAndQualityInsights-MaintenanceTask' '' 'Disabled' '' 'задача UsageAndQualityInsights (сбор сведений об использовании)' 26100

$od = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
Def 'onedrive' 'reg' $od 'DisableFileSyncNGSC' 1 'DWord' 'OneDrive: синхронизация файлов — выкл'
Def 'onedrive' 'reg' $od 'DisableFileSync' 1 'DWord' 'OneDrive: старая синхронизация — выкл'
Def 'onedrive' 'reg' $od 'DisableMeteredNetworkFileSync' 1 'DWord' 'OneDrive: не синхронизировать по лимитной сети'
Def 'onedrive' 'reg' 'HKCU:\Software\Microsoft\OneDrive' 'DisablePersonalSync' 1 'DWord' 'OneDrive: личная синхронизация — выкл'
Def 'onedrive' 'reg' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0 'DWord' 'OneDrive: реклама в Проводнике — выкл'
Def 'onedrive' 'taskglob' 'OneDrive*' '' 'Disabled' '' 'OneDrive: задачи обновления — выкл'

# Сессии трассировки запускаются при загрузке самой Windows и пишут телеметрию
# независимо от службы DiagTrack. Start = 0 отключает сборщик.
$al = 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger'
Def 'etw' 'regif' "$al\AutoLogger-Diagtrack-Listener" 'Start' 0 'DWord' 'главный сборщик телеметрии (Diagtrack-Listener)'
Def 'etw' 'regif' "$al\Diagtrack-Listener" 'Start' 0 'DWord' 'сборщик Diagtrack (второй вариант)'
Def 'etw' 'regif' "$al\SQMLogger" 'Start' 0 'DWord' 'сборщик программы улучшения качества (SQM)'
Def 'etw' 'regif' "$al\WiFiSession" 'Start' 0 'DWord' 'трассировка сеансов Wi-Fi'
Def 'etw' 'regif' "$al\CloudExperienceHostOobe" 'Start' 0 'DWord' 'трассировка первоначальной настройки'
Def 'etw' 'regif' "$al\DiagLog" 'Start' 0 'DWord' 'диагностический журнал DiagLog'
Def 'etw' 'regif' "$al\UBPM" 'Start' 0 'DWord' 'трассировка планировщика (UBPM)'
Def 'etw' 'regif' "$al\Microsoft-Windows-AssignedAccess-Trace" 'Start' 0 'DWord' 'трассировка AssignedAccess'
Def 'etw' 'regif' "$al\AppModel" 'Start' 0 'DWord' 'трассировка запуска приложений (AppModel)'
Def 'etw' 'reg' 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener' 'Enabled' 0 'DWord' 'запрет включения сборщика телеметрии'

Def 'hosts' 'hosts' '' '' '' '' 'блок телеметрийных доменов в hosts'

# Номер устройства в учётной записи Microsoft (GDID). Его выдаёт login.live.com
# при входе, CDPSvc регистрирует компьютер в каталоге устройств Microsoft, а
# DoSvc (Delivery Optimization) сообщает номер обратно. Смена IP и VPN на него
# не влияют; DiagTrack в этой цепочке не участвует, поэтому отключённая
# телеметрия его не останавливает. Стирать номер бесполезно: он привязан к
# учётной записи и возвращается с серверов тем же самым. Остаётся не дать ему
# уходить. DoSvc диспетчер служб не отдаёт даже администратору («Отказано в
# доступе»), поэтому службы отключаются там, где диспетчер хранит их
# настройку, — в реестре: запись идёт в журнал и откатывается как обычная.
# Разбор цепочки: github.com/SmtimesIWndr/gdid-reversal и github.com/Korben00/no-gdid.
$svcRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services'
Def 'gdid' 'regsvc' "$svcRoot\CDPSvc" 'Start' 4 'DWord' 'служба CDPSvc: регистрация компьютера в каталоге устройств Microsoft — выкл'
Def 'gdid' 'regsvc' "$svcRoot\CDPUserSvc" 'Start' 4 'DWord' 'служба CDPUserSvc: то же для каждого пользователя — выкл'
Def 'gdid' 'regsvc' "$svcRoot\DoSvc" 'Start' 4 'DWord' 'служба DoSvc (Delivery Optimization): передача номера устройства — выкл'
Def 'gdid' 'gdidhosts' '' '' '' '' 'серверы каталога устройств и Delivery Optimization — в hosts'

# Запрет выдачи номера. Новый номер выдаёт login.live.com при первом же
# обращении устройства — пока сервер открыт, стёртый номер сменяется новым.
# Закрыв его, можно стереть номер насовсем. Цена — учётная запись Microsoft:
# вход в неё, Магазин, Xbox и OneDrive перестают работать, поэтому при входе
# в Windows через неё модуль не применяется. Что и где стирается — разбор
# github.com/yegors/deGDID (проверено на Windows 11 25H2, сборка 26200).
Def 'gdidlock' 'gdidlockhosts' '' '' '' '' 'сервер выдачи номера (login.live.com, account.live.com) — в hosts'
Def 'gdidlock' 'fwsvc' 'wlidsvc' '' '' '' 'исходящие службы учётных записей Microsoft (wlidsvc) — блок'
Def 'gdidlock' 'gdidwipe' '' '' '' '' 'номер устройства стёрт отовсюду, где Windows его хранит'

# Блокировка самих адресов: hosts телеметрия обходит через шифрованный DNS
# и зашитые IP, поэтому адреса блокируются правилом брандмауэра.
Def 'fwips' 'fwips' '' '' '' '' 'блокировка адресов сбора телеметрии'

# Шифрованный DNS (DoH) позволяет обойти hosts и блокировку по доменам
Def 'doh' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'DoHPolicy' 1 'DWord' 'Windows: шифрованный DNS — запретить'
Def 'doh' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DnsOverHttpsMode' 'off' 'String' 'Edge: шифрованный DNS — выкл'
Def 'doh' 'reg' 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'DnsOverHttpsMode' 'off' 'String' 'Chrome: шифрованный DNS — выкл'

# Брандмауэр: исходящие соединения служб и программ телеметрии
Def 'firewall' 'fwsvc' 'DiagTrack' '' '' '' 'исходящие DiagTrack — блок'
Def 'firewall' 'fwsvc' 'dmwappushservice' '' '' '' 'исходящие dmwappushservice — блок'
Def 'firewall' 'fwsvc' 'WerSvc' '' '' '' 'исходящие Windows Error Reporting — блок'
Def 'firewall' 'fwapp' "$env:SystemRoot\System32\CompatTelRunner.exe" '' '' '' 'исходящие CompatTelRunner — блок'
Def 'firewall' 'fwapp' "$env:SystemRoot\System32\DeviceCensus.exe" '' '' '' 'исходящие DeviceCensus — блок'
Def 'firewall' 'fwapp' "$env:SystemRoot\System32\wsqmcons.exe" '' '' '' 'исходящие wsqmcons (CEIP) — блок'

# --- Сторонние программы ---------------------------------------------------- #
Def 'app_nvidia' 'reg' 'HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2\Client' 'OptInOrOutPreference' 0 'DWord' 'NVIDIA: участие в сборе данных — отказ'
Def 'app_nvidia' 'reg' 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS' 'EnableRID44231' 0 'DWord' 'NVIDIA: телеметрия FTS (1) — выкл'
Def 'app_nvidia' 'reg' 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS' 'EnableRID64640' 0 'DWord' 'NVIDIA: телеметрия FTS (2) — выкл'
Def 'app_nvidia' 'reg' 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS' 'EnableRID66610' 0 'DWord' 'NVIDIA: телеметрия FTS (3) — выкл'
Def 'app_nvidia' 'svcopt' 'NvTelemetryContainer' '' 'Disabled' '' 'NVIDIA: служба NvTelemetryContainer'
Def 'app_nvidia' 'taskglob' 'NvTm*' '' 'Disabled' '' 'NVIDIA: задачи телеметрии NvTm*'

Def 'app_vscode' 'vscode' 'telemetry.telemetryLevel' '' 'off' '' 'VS Code: телеметрия — выкл'
Def 'app_vscode' 'vscode' 'workbench.enableExperiments' '' $false '' 'VS Code: эксперименты — выкл'
Def 'app_vscode' 'vscode' 'telemetry.feedback.enabled' '' $false '' 'VS Code: опросы — выкл'

$ch = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
Def 'app_chrome' 'reg' $ch 'MetricsReportingEnabled' 0 'DWord' 'Chrome: статистика использования — выкл'
Def 'app_chrome' 'reg' $ch 'UrlKeyedAnonymizedDataCollectionEnabled' 0 'DWord' 'Chrome: отправка адресов сайтов — выкл'
Def 'app_chrome' 'reg' $ch 'AlternateErrorPagesEnabled' 0 'DWord' 'Chrome: не отправлять ошибочные адреса'
Def 'app_chrome' 'reg' $ch 'SpellCheckServiceEnabled' 0 'DWord' 'Chrome: облачная проверка орфографии — выкл'
Def 'app_chrome' 'reg' $ch 'PrivacySandboxAdMeasurementEnabled' 0 'DWord' 'Chrome: измерение рекламы — выкл'
Def 'app_chrome' 'reg' $ch 'PrivacySandboxAdTopicsEnabled' 0 'DWord' 'Chrome: рекламные темы — выкл'
Def 'app_chrome' 'reg' $ch 'PrivacySandboxSiteEnabledAdsEnabled' 0 'DWord' 'Chrome: реклама по сайтам — выкл'
Def 'app_chrome' 'reg' $ch 'PrivacySandboxPromptEnabled' 0 'DWord' 'Chrome: окно Privacy Sandbox — выкл'

Def 'app_firefox' 'firefox' 'DisableTelemetry' '' $true '' 'Firefox: телеметрия — выкл'
Def 'app_firefox' 'firefox' 'DisableFirefoxStudies' '' $true '' 'Firefox: исследования — выкл'

$of = 'HKCU:\Software\Policies\Microsoft\office\16.0\common'
Def 'app_office' 'reg' "$of\clienttelemetry" 'SendTelemetry' 3 'DWord' 'Office: телеметрия — ни базовой, ни расширенной'
Def 'app_office' 'reg' 'HKCU:\Software\Policies\Microsoft\office\common\clienttelemetry' 'DisableTelemetry' 1 'DWord' 'Office: телеметрия клиента — выкл'
Def 'app_office' 'reg' $of 'sendcustomerdata' 0 'DWord' 'Office: данные клиента — не отправлять'
Def 'app_office' 'reg' "$of\feedback" 'enabled' 0 'DWord' 'Office: отзывы — выкл'
Def 'app_office' 'reg' "$of\feedback" 'includescreenshot' 0 'DWord' 'Office: снимки экрана в отзывах — выкл'

Def 'app_devtools' 'env' 'POWERSHELL_TELEMETRY_OPTOUT' '' '1' '' 'PowerShell 7: телеметрия — выкл'
Def 'app_devtools' 'env' 'POWERSHELL_UPDATECHECK' '' 'Off' '' 'PowerShell 7: проверка обновлений — выкл'
Def 'app_devtools' 'env' 'DOTNET_CLI_TELEMETRY_OPTOUT' '' '1' '' '.NET SDK: телеметрия — выкл'

Def 'app_vs' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\VisualStudio\SQM' 'OptIn' 0 'DWord' 'Visual Studio: программа улучшения качества — отказ'
Def 'app_vs' 'reg' 'HKCU:\Software\Microsoft\VisualStudio\Telemetry' 'TurnOffSwitch' 1 'DWord' 'Visual Studio: телеметрия — выкл'
Def 'app_vs' 'reg' 'HKLM:\SOFTWARE\Policies\Microsoft\VisualStudio\Feedback' 'DisableFeedbackDialog' 1 'DWord' 'Visual Studio: окно отзывов — выкл'

$script:ModuleOrder = @('telemetry','errors','activity','input','edge','delivery','location','apppriv','network','cloudsync','ads','widgets','search','copilot','ai',
                        'defender','apphw','onedrive','services','etw','hosts','gdid','gdidlock','firewall','fwips','doh','buffer','app_nvidia','app_vscode','app_chrome','app_firefox',
                        'app_office','app_devtools','app_vs','oem','cleanup','startup')
$script:ModuleTitles = @{
    telemetry='Телеметрия и диагностика'; errors='Отчёты об ошибках'; activity='История активности и буфер обмена';
    input='Персонализация ввода, рукописный ввод, речь'; edge='Microsoft Edge'; delivery='Раздача обновлений другим ПК';
    location='Геолокация и поиск устройства'; apppriv='Разрешения приложений (запрет политикой)';
    network='Фоновые обращения Windows в сеть'; cloudsync='Облачная синхронизация и копия'; apphw='Камера, микрофон и фоновая работа приложений'; ads='Рекламный ID и реклама в интерфейсе'; widgets='Виджеты и лента новостей';
    search='Поиск: Bing, Cortana, облако'; copilot='Copilot и Recall';
    ai='ИИ-функции Windows'; defender='Защитник: облако и образцы'; etw='Сессии трассировки телеметрии'; onedrive='OneDrive: синхронизация и реклама'; services='Службы и задачи телеметрии'; hosts='Блокировка телеметрийных доменов (hosts)';
    gdid='Номер устройства в учётной записи Microsoft (GDID)'; gdidlock='Запрет выдачи номера устройства';
    firewall='Брандмауэр: блокировка служб телеметрии'; fwips='Брандмауэр: адреса сбора телеметрии'; doh='Шифрованный DNS (обход блокировки)'; buffer='Неотправленная телеметрия'; app_nvidia='NVIDIA';
    app_vscode='Visual Studio Code'; app_chrome='Google Chrome'; app_firefox='Mozilla Firefox'; app_office='Microsoft Office';
    app_devtools='PowerShell 7 / .NET SDK'; app_vs='Visual Studio'; oem='Компоненты сбора данных производителя';
    cleanup='Чистка временных файлов'; startup='Автозагрузка (отчёт)'
}

# --------------------------------------------------------------------------- #
#  Цена каждой настройки. Уровень: safe — ничего заметного не ломается,
#  limited — какая-то функция Windows перестанет работать, caution — может
#  задеть то, что вам нужно. По умолчанию уровень — как у модуля; отдельные
#  пункты уточнены ниже, вместе с тем, что именно перестанет работать.
#  Ключ — название настройки, как в Def.
# --------------------------------------------------------------------------- #
$script:ModuleRisk = @{
    location = 'limited'; apppriv = 'limited'; apphw = 'limited'; onedrive = 'limited'; services = 'limited'
    hosts = 'limited'; firewall = 'limited'; fwips = 'caution'; doh = 'limited'; defender = 'caution'
    gdid = 'limited'; gdidlock = 'caution'; oem = 'limited'; cloudsync = 'limited'
}
$script:DefRisk = @{
    'уровень телеметрии — минимальный' = 'safe'
    'служба DiagTrack (телеметрия)' = 'safe'
    'задача License Validation' = 'caution'
    'Teredo (туннель IPv6 через Microsoft) — выкл' = 'limited'
    'история буфера обмена — выкл' = 'limited'
    'не скачивать прогноз нагрузки энергосети' = 'safe'
    'Click to Do: скачивание моделей ИИ — выкл' = 'safe'
    'задача UsageAndQualityInsights (сбор сведений об использовании)' = 'safe'
    'синхронизация ваших согласий на сбор данных — выкл' = 'safe'
    'скачивание обоев с других ваших устройств — выкл' = 'safe'
    'не применять «исправления», присланные Microsoft' = 'limited'
    'средства устранения неполадок не обращаются к серверам Microsoft' = 'limited'
    'Защитник: удалённые настройки и эксперименты (ECS) — выкл' = 'limited'
    'обои «Windows: интересное» на рабочем столе — выкл' = 'limited'
    'ИИ-агенты: доступ к файлам и настройкам через MCP — запрещён' = 'limited'
    'приложение «Архивация Windows» — выкл' = 'limited'
    'облачное распознавание речи — выкл' = 'limited'
}
$script:DefNotes = @{
    'уровень телеметрии — минимальный' = 'На Home и Pro Windows всё равно оставит «обязательные данные»: полностью выключает только Enterprise и Education.'
    'история буфера обмена — выкл' = 'Win+V перестанет показывать историю скопированного.'
    'синхронизация буфера между устройствами — выкл' = 'Буфер обмена не будет общим с телефоном и другими компьютерами.'
    'облачное распознавание речи — выкл' = 'Голосовой ввод и диктовка через облако Microsoft перестанут работать.'
    'веб-поиск из Пуска — выкл' = 'Поиск в Пуске будет искать только на компьютере, без результатов из интернета.'
    'служба геолокации — выкл' = 'Карты, погода и автоматический часовой пояс не узнают, где вы.'
    '«Поиск устройства» (отправка координат) — выкл' = 'Потерянный ноутбук нельзя будет найти через «Поиск устройства».'
    'сведения учётной записи и возраст (Age API) — запрещены' = 'Приложения из Магазина не узнают ваше имя, аватар и возраст.'
    'почта — запрещена приложениям' = 'Почта из Магазина не увидит ваши письма, пока вы не разрешите её вручную.'
    'календарь — запрещён приложениям' = 'Календарь из Магазина не увидит ваши события, пока вы не разрешите его вручную.'
    'обмен с устройствами — запрещён приложениям' = 'Приложения не смогут связываться с телефоном и устройствами Bluetooth без вашего разрешения.'
    'камера — запрещена приложениям из магазина' = 'Камера перестанет работать в приложениях Магазина. В браузерах и обычных программах — работает.'
    'микрофон — запрещён приложениям из магазина' = 'Микрофон перестанет работать в приложениях Магазина. В браузерах и обычных программах — работает.'
    'фоновая работа приложений из магазина — запрещена' = 'Приложения из Магазина не будут присылать уведомления и обновляться, пока закрыты.'
    'Teredo (туннель IPv6 через Microsoft) — выкл' = 'Сетевые игры Xbox, которым нужен Teredo, могут не подключаться.'
    'OneDrive: синхронизация файлов — выкл' = 'OneDrive перестанет синхронизировать файлы. Сами файлы на диске остаются.'
    'служба dmwappushservice (WAP push)' = 'Нужна, если компьютером управляет организация (MDM). Дома не используется.'
    'задача License Validation' = 'Проверяет лицензии приложений Магазина. Если купленные приложения перестанут запускаться — снимите этот пункт.'
    'задача FamilySafetyMonitor' = 'Родительский контроль Microsoft Family перестанет работать.'
    'Защитник: облачная отправка MAPS — выкл' = 'Защитник теряет облачную проверку: новые угрозы он будет узнавать позже.'
    'Защитник: отправка образцов файлов — никогда' = 'Подозрительные файлы не уйдут на анализ в Microsoft.'
    'Windows: шифрованный DNS — запретить' = 'Ваши DNS-запросы снова видит провайдер. Зато hosts работает для всех программ.'
    'блок телеметрийных доменов в hosts' = 'Windows Update и Магазин не затрагиваются. Изредка перестают уходить отчёты об ошибках.'
    'блокировка адресов сбора телеметрии' = 'На тех же адресах иногда живут другие службы Microsoft — если что-то отвалится, снимите пункт.'
    'служба CDPSvc: регистрация компьютера в каталоге устройств Microsoft — выкл' = '«Связь с телефоном» и обмен с устройствами поблизости перестанут работать.'
    'служба DoSvc (Delivery Optimization): передача номера устройства — выкл' = 'Если Магазин перестанет скачивать приложения — снимите этот пункт.'
    'сервер выдачи номера (login.live.com, account.live.com) — в hosts' = 'Вход в учётную запись Microsoft, Магазин, Xbox и OneDrive перестанут работать.'
    'служба InventorySvc (опись программ и оборудования)' = 'Перед крупным обновлением Windows проверка совместимости будет знать о ваших программах меньше.'
    'синхронизация параметров между устройствами — выкл' = 'Тема, язык и другие настройки не переедут на новый компьютер сами — их придётся задать заново.'
    'копия списка приложений в облако — выкл' = 'На новом компьютере Windows не предложит заново поставить ваши приложения.'
    'архивация Windows в облако — выкл' = 'Копия в OneDrive перестанет обновляться сама. Если рассчитываете на неё при переезде — снимите пункт.'
    'синхронизация сетей Wi-Fi между устройствами — выкл' = 'Пароли Wi-Fi не будут переезжать на другие ваши компьютеры.'
    'установка приложений на этот ПК по команде с сайта — выкл' = 'Кнопка «Установить на устройство» на сайте Магазина перестанет работать. В самом Магазине всё ставится как обычно.'
    'не применять «исправления», присланные Microsoft' = 'Windows перестанет сама чинить известные сбои по указанию Microsoft. Средства устранения неполадок можно запускать вручную.'
    'средства устранения неполадок не обращаются к серверам Microsoft' = 'Средства устранения неполадок будут работать только с тем, что есть на компьютере.'
    'Защитник: удалённые настройки и эксперименты (ECS) — выкл' = 'Новые функции и усиления защиты Защитник будет получать только с обновлениями, а не с сервера экспериментов. Базы угроз обновляются как обычно.'
    'обои «Windows: интересное» на рабочем столе — выкл' = 'Картинки «Windows: интересное» на рабочем столе перестанут меняться сами.'
    'ИИ-агенты: доступ к файлам и настройкам через MCP — запрещён' = 'ИИ-помощники не смогут сами работать с вашими файлами и настройками Windows.'
    'приложение «Архивация Windows» — выкл' = 'Приложение «Архивация Windows» перестанет сохранять копию в OneDrive. Файлы на диске не трогаются.'
    'встроенные ИИ-модели Windows — запрещены приложениям' = 'Приложения из Магазина не смогут пользоваться ИИ-моделями Windows на компьютере.'
}

function Get-DefRisk {
    param($Def)
    if ($script:DefRisk.ContainsKey("$($Def.C)")) { return $script:DefRisk["$($Def.C)"] }
    if ($script:ModuleRisk.ContainsKey("$($Def.M)")) { return $script:ModuleRisk["$($Def.M)"] }
    return 'safe'
}
