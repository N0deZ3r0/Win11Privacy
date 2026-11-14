
# =========================================================================== #
#  Константы
# =========================================================================== #
# Версия. Должна совпадать с AppInfo.Version в интерфейсе -- сборка это
# проверяет, чтобы вшитый движок и окно не рассказывали о себе разное.
$script:EngineVersion  = '2.0.0'
# Метки блока в hosts — только латиницей. Раньше они были по-русски, а hosts
# пишется в ASCII: кириллица превращалась в «?», и своего блока программа
# потом не узнавала — дописывала его заново при каждом применении, а откат
# его не убирал. По шаблону узнаются и новые метки, и прежние, уже побитые.
$script:HostsMarkStart = '# --- Win11Privacy: telemetry block (begin) ---'
$script:HostsMarkEnd   = '# --- Win11Privacy: telemetry block (end) ---'
$script:HostsMarkRegex = '^# --- Win11Privacy: .+ ---\s*$'
$script:FwGroup        = 'Win11Privacy'
# Обычно данные лежат в ProgramData. В переносимом режиме интерфейс
# передаёт -DataRoot, и всё остаётся рядом с exe — на чужом компьютере
# программа не оставляет следов.
$script:DataDir        = $(if ($DataRoot) { $DataRoot } else { Join-Path $env:ProgramData 'Win11Privacy' })
# Задачам планировщика путь к данным надо передать явно: они запускаются
# сами по себе и о переносимом режиме иначе не узнают.
# Обратная косая в конце пути (D:\) экранировала бы закрывающую кавычку в
# командной строке задачи; по правилам разбора её удваивают.
$script:DataArg        = $(if ($DataRoot) { ' -DataRoot "' + ($DataRoot -replace '\\$', '\\') + '"' } else { '' })
# Запуск из планировщика: страж, наблюдение за датчиками и сетью. Такие запуски
# идут сами, без человека, и с правами администратора.
$script:TaskRun        = [bool]($Guard -or $SensorGuard -or $NetGuard -or $WatcherNotify)
$script:PortableTaskState = $null    # можно ли задачам верить переносимой папке: $null — ещё не проверяли
# Корень в ProgramData. Здесь копия движка, которую задачи планировщика
# запускают с правами администратора, — и в переносимом режиме тоже: рядом с
# exe писать может любая программа пользователя, и подменённый скрипт молча
# выполнился бы с повышенными правами при следующем входе в систему.
$script:SafeRoot       = Join-Path $env:ProgramData 'Win11Privacy'
$script:TaskEngine     = Join-Path $script:SafeRoot 'engine.ps1'
# Задачи стража и наблюдения запускают PowerShell по полному пути: по одному
# имени Windows ищет программу и в рабочей папке задачи.
$script:PsExe          = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
# Ключ подписи журнала отката: всегда в защищённом корне, читать его могут
# только система и администраторы
$script:SignKeyFile    = Join-Path $script:SafeRoot 'journal.key'
$script:SignKey        = $null
$script:RootState      = $null        # защищён ли корень: $null — ещё не проверяли
# Владельцы, которым можно верить: система, администраторы, TrustedInstaller
$script:TrustedSids    = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
$script:JournalFailed  = $false       # журнал отката не записался — дальше ничего не меняем
$script:JournalLockTries = 6          # по 10 секунд: другой запуск может писать журнал долго
$script:JournalLockWaitMs = 10000
$script:GuardTask      = 'Win11Privacy Guard'
$script:SensorTask     = 'Win11Privacy Sensor'
$script:AuditGuid      = '{0CCE9226-69AE-11D9-BED3-505054503030}'   # Filtering Platform Connection
$script:DiagDir        = Join-Path $env:ProgramData 'Microsoft\Diagnosis'
# Все виды определений, которые пишут в реестр. Список один, потому что
# забыть про новый вид в резервной копии или уборке — тихая потеря данных.
$script:RegTypes = @('reg', 'regif', 'regpol', 'regsvc')
# Номер сборки Windows: по нему настройки, которых на этой версии нет вовсе
# (Copilot, Recall, виджеты — их не было до Windows 11), не считаются
# «не применёнными». Иначе на Windows 10 индекс был бы низким без вины
# пользователя.
$script:OsBuild = 0
try { $script:OsBuild = [int](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'CurrentBuildNumber' -ErrorAction Stop).CurrentBuildNumber } catch { }
# Сколько часов во временной папке не трогать свежие файлы: ими ещё
# пользуются запущенные программы, а чистка однажды стёрла рабочие файлы.
$script:TempKeepHours = 24
$script:Changes = 0
$script:Failures = 0
$script:Already = 0
$script:Blocked = 0
# Настройки, которые Windows не отдала при применении. Запоминаются в
# blocked.json, чтобы проверка не считала их «не применёнными» вечно:
# индекс на Home иначе никогда не дошёл бы до 100 %.
$script:BlockedIds = @{}
$script:UnblockedIds = @{}
# Журнал изменений реестра: что было до нашего вмешательства.
# Без него откат требовал ручного импорта .reg-файлов.
$script:Journal = New-Object System.Collections.Generic.List[object]
# Метка этого запуска в записях журнала и ключи записей, которые этот запуск
# положил заранее, а изменение потом не прошло: их убирает следующая запись.
$script:RunId = [guid]::NewGuid().ToString('N')
$script:JournalRetract = New-Object 'System.Collections.Generic.HashSet[string]'
$script:TelemetryDnsRegex = 'telemetry|vortex|events\.data\.microsoft|pipe\.aria|watson|settings-win\.data|ceipdata|telecommand|sqm\.|nexusrules|nexus\.officeapps|data\.microsoft\.com|activity\.windows\.com|licensing\.mp\.microsoft|browser\.events|dds\.microsoft\.com|cdpcs\.access\.microsoft|\.do\.dsp\.mp\.microsoft'
