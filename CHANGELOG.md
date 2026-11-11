# Изменения / Changelog

Описание каждого релиза берётся отсюда: сборка по тегу `vX.Y.Z` ищет раздел
`## X.Y.Z` и кладёт его в описание релиза на GitHub. Новое пишется в раздел
«Не выпущено»; перед выпуском он переименовывается в номер версии.

The text of every release comes from this file: a build of tag `vX.Y.Z` looks for
the `## X.Y.Z` section and puts it into the GitHub release. New entries go under
«Не выпущено» (Unreleased), which is renamed to the version number before release.

## Не выпущено

### Что нового

**Новый интерфейс**
- Строгий вид «консоли безопасности»: графитовая палитра, один синий акцент, цвет — только у состояний (норма, внимание, проблема).
- Восемь разделов вместо четырнадцати. Родственные страницы собраны под одним пунктом и переключаются вкладками: «Наблюдение» (сбор данных, следы на компьютере, сеть, хронология), «Проверка» (проверка и изменения), «О программе» (о программе и журнал).
- «Обзор» без метрик: общее состояние, «Требует внимания» и защита по разделам. Проверка запускается сама при первом открытии.
- «Настройки»: профиль переключателем (Базовый / Строгий / Максимум / Свой), «Что изменится», «Ещё» и «Применить» в шапке.
- Новый значок программы, перерисованные переключатели, плавное сворачивание боковой панели, пояснение в пустом журнале.
- Язык интерфейса по умолчанию — язык Windows, и он проверяется при каждом запуске. На странице «О программе» можно закрепить русский или английский.

**Приватность: 283 настройки вместо 244**
- Новая вкладка «Номер устройства» (GDID) — номер, по которому Microsoft узнаёт компьютер сквозь VPN. Три действия: не передавать, сменить номер, запретить выдачу.
- Новый раздел «Облачная синхронизация и копия»: список приложений, сети Wi-Fi, язык, тема, настройки пера и ответы на вопросы о конфиденциальности больше не уходят в облако. Сюда же служба InventorySvc и сборщик «Usage and Quality Insights».
- Скрытые каналы, найденные разбором чистой Windows 11: эксперименты Защитника (около 130 настроек с сервера раз в час), телеметрия 1DS мимо службы DiagTrack (24 новых адреса в hosts), установка приложений из Магазина по команде с сайта, «исправления» от рекомендуемого устранения неполадок.
- Что осталось, когда программа уже стоит на максимуме (вторая запись с имитацией работы пользователя): «Параметры» отправляют в Bing, какую страницу вы открыли (блок «Справка из интернета»), — его выключает новая настройка; в hosts добавлены рекламный счётчик Bing в Магазине, отчёты о сетевых ошибках (nelreports.net) и сервер экспериментов для приложений (exp-tas.com).
- Задачи планировщика, которые Windows не отдаёт администратору, отключаются от имени системы.

**Безопасность и надёжный откат**
- Папка данных `C:\ProgramData\Win11Privacy` закрыта на запись для всех, кроме системы и администраторов. Раньше обычный пользователь мог заранее подложить туда файл и через журнал отката или копию движка для стража получить права администратора. Подложенное откладывается в сторону.
- Копия движка, которую запускает страж, всегда лежит в защищённой папке и сверяется по SHA-256 — в переносимом режиме тоже.
- Откат возвращает службы (тип запуска, отложенный старт, работала ли), задачи планировщика и переменные среды ровно такими, какими застал. Задача, выключенная вами до программы, остаётся выключенной; корпоративные политики Chrome, Office и Visual Studio больше не удаляются целыми ветками.
- Журнал отката: ошибка записи больше не проглатывается — программа говорит о ней и останавливает изменения; перед применением журнал проверяется заранее; без замка журнал не пишется; повреждённый журнал откладывается, а не затирается.
- Журнал отката подписывается (HMAC-SHA256). Ключ лежит в `C:\ProgramData\Win11Privacy`, и читать его могут только система и администраторы. Журнал, изменённый или дописанный кем-то другим, не применяется и откладывается. Журнал прежней версии без подписи, лежащий в переносимой папке, возвращает только записи о настройках самой программы.
- Переносимый режим: страж и наблюдение — задачи, которые сами запускаются с правами администратора, — ставятся, только если папку программы нельзя подменить (например, в Program Files на диске NTFS). Папка данных тогда закрывается так же, как `ProgramData\Win11Privacy`. Раньше переносимая папка считалась доверенной без всякой проверки.
- Если защищённую папку для движка подготовить не удалось, движок больше не запускается из временной папки пользователя: там его могла бы подменить любая программа.
- Папка данных прежних версий проверяется на любой глубине, а не только в корне: чужие файлы, ссылки и то, что открыто на запись чужим явным правом, уходят в карантин.
- Короткие задачи планировщика (номер устройства, закрытые задачи) получают случайное имя и перед запуском сверяются: та ли команда и от чьего имени.

**Исправления**
- Номер устройства: стирание честнее говорит о результате. Учётные данные «личности» устройства считаются убранными, только если после `cmdkey` их действительно нет в хранилище (раньше успехом считался сам запуск задачи). У каждой записи в реестре свой итог — убрана, не было или Windows не дала; запись, закрытая от чтения, больше не засчитывается как «не было». Места, которые не удалось прочитать, — хранилище целиком или закрытый ключ внутри него — не выдаются за «стёрто». На время стирания останавливается и служба DoSvc; если хоть одна из служб не остановилась, стирание не начинается и службы возвращаются как были. Успехом стирание считается, только если службы, работавшие до него, снова запущены, а кэш платформы подключённых устройств действительно пуст. Копии номера ищутся и в профилях пользователей, которые сейчас вошли в Windows; про профили остальных программа прямо пишет, что их не проверяла. Плитка «Номер» берёт номер из любого найденного хранилища, а не только из профиля текущего пользователя.
- Наблюдение за сетью: включено ли оно, теперь определяется по числу в политике аудита, а не по словам — на немецкой или французской Windows оно считалось выключенным всегда. Сбой `auditpol` больше не выдаётся за успех, а откат возвращает ту политику аудита, что была до программы, а не просто выключает её.
- Публичный ли адрес, теперь решается по диапазонам IANA, а не по началу строки: общие адреса провайдеров (100.64.0.0/10), тестовые и зарезервированные сети, многоадресные IPv6 и IPv4 внутри IPv6 больше не считаются в наблюдении за сетью и проверке утечек «публичными».
- Очистка неотправленной телеметрии удаляет только очередь и трассировки. Раньше она цепляла и настройки диагностики, а на папке могла зависнуть.
- «Обзор» при первом запуске показывал пустые разделы до ручной проверки.
- После сворачивания и разворачивания боковой панели в списке настроек оставалась горизонтальная прокрутка; пункты панели дёргались во время анимации; вокруг кнопки меню оставалась рамка после щелчка.

### What's new

**New interface**
- A strict "security console" look: graphite palette, a single blue accent, colour only for states (fine, attention, problem).
- Eight sections instead of fourteen. Related pages live under one item and switch with tabs: Observation (data collection, traces on this PC, network, timeline), Verify (check and changes), About (about and log).
- The Overview has no metrics: overall state, "Needs attention" and protection by section. The check runs by itself the first time it opens.
- Settings: the profile is a switch (Basic / Strict / Maximum / Custom); "What will change", "More" and "Apply" sit in the header.
- A new app icon, redrawn toggle switches, smooth sidebar collapse, an explanation in the empty log.
- The interface language follows Windows by default and is checked on every start. Russian or English can be pinned on the About page.

**Privacy: 283 settings instead of 244**
- A new Device ID tab (GDID) — the number Microsoft recognises the PC by through a VPN. Three actions: stop sending it, change it, forbid issuing a new one.
- A new Cloud sync and backup section: your app list, Wi-Fi networks, language, theme, pen settings and privacy answers no longer go to the cloud. Also the InventorySvc service and the "Usage and Quality Insights" collector.
- Hidden channels found by taking a clean Windows 11 apart: Defender experiments (about 130 settings pulled every hour), 1DS telemetry bypassing DiagTrack (24 new hosts entries), Store installs on command from the website, "mitigations" from recommended troubleshooting.
- What was left with the program already at maximum (a second recording with simulated user activity): Settings tells Bing which page you opened (the "Help from the web" block) — a new setting turns it off; the hosts block now also covers the Bing ad counter in the Store, network error reports (nelreports.net) and the app experiments server (exp-tas.com).
- Scheduled tasks that Windows keeps from administrators are switched off as SYSTEM.

**Security and a faithful rollback**
- The data folder `C:\ProgramData\Win11Privacy` can only be written by SYSTEM and administrators. Before, an ordinary user could plant a file there in advance and gain administrator rights through the undo journal or the guard's copy of the engine. Planted items are moved aside.
- The copy of the engine the guard runs always lives in the protected folder and is checked by SHA-256, in portable mode too.
- The rollback returns services (startup type, delayed start, whether it was running), scheduled tasks and environment variables exactly as it found them. A task you had switched off yourself stays off; company Chrome, Office and Visual Studio policies are no longer deleted as whole keys.
- Undo journal: a write error is no longer swallowed — the program reports it and stops changing anything; the journal is checked before applying; it is never written without its lock; a damaged journal is set aside instead of being overwritten.
- The undo journal is signed (HMAC-SHA256). The key lives in `C:\ProgramData\Win11Privacy` and only SYSTEM and administrators can read it. A journal edited or extended by anyone else is not applied and is set aside. An unsigned journal from an older version in a portable folder restores only entries about the program's own settings.
- Portable mode: the guard and the monitors — tasks that start by themselves with administrator rights — are installed only if the program's folder cannot be swapped (for example under Program Files on an NTFS drive). The data folder is then locked down like `ProgramData\Win11Privacy`. Before, the portable folder was trusted without any check.
- If the protected folder for the engine cannot be prepared, the engine no longer runs from the user's temp folder, where any program could swap it.
- Data folders of older versions are checked at any depth, not only at the top: foreign files, links and anything open to writing by someone else's explicit right go to quarantine.
- Short-lived scheduled tasks (device ID, closed tasks) get a random name and are checked before they start: the right command, under the right account.

**Fixes**
- Device ID: wiping reports its result honestly. The device identity credentials count as removed only if they are really gone from the vault after `cmdkey` (before, merely starting the task counted as success). Every registry entry gets its own outcome — removed, not there, or refused by Windows; an entry closed to reading no longer counts as "not there". Places that could not be read — a whole store or a closed key inside one — are no longer reported as wiped. The DoSvc service is stopped during the wipe too; if any of the services does not stop, nothing is wiped and the services are put back as they were. The wipe counts as a success only if the services that were running before are running again and the Connected Devices Platform cache is really empty. Copies of the ID are also searched for in the profiles of other users who are signed in right now; for everyone else the program says plainly that it did not check them. The ID tile takes the number from any store found, not only from the current user's profile.
- Network watch: whether it is on is now read from the audit policy as a number, not from words — on a German or French Windows it always looked off. A failed `auditpol` is no longer reported as success, and the rollback restores the audit policy that was there before the program instead of simply turning it off.
- Whether an address is public is now decided by IANA ranges, not by how the string starts: carrier-grade NAT (100.64.0.0/10), test and reserved networks, IPv6 multicast and IPv4 inside IPv6 no longer count as "public" in network monitoring and the leak test.
- Clearing the unsent telemetry removes only the queue and the traces. Before, it also took the diagnostics settings and could hang on a folder.
- On first start the Overview showed empty sections until a manual check.
- After collapsing and expanding the sidebar the settings list kept a horizontal scrollbar; sidebar items jerked during the animation; a focus frame stayed around the menu button after a click.

## 1.10.2 — 2026-10-30

### Что нового

- Блок в `hosts` помечается латиницей. Раньше метки были кириллицей, файл пишется в ASCII — и они превращались в «?»: программа не узнавала свой блок, дописывала его при каждом применении, а откат его не убирал. Блоки прежних версий теперь узнаются и убираются, чужие строки `hosts` не портятся.
- Откат по журналу: что вернуть не удалось, остаётся в журнале для повторной попытки, а при повторах возвращается самое раннее значение. Файлы данных пишутся целиком или никак — обрыв не оставит половину журнала.
- Узкое окно: кнопки и текст не уезжают за край и не обрезаются; сборка проверяет и обычную, и самую маленькую ширину.
- «Прервать» и закрытие окна останавливают нужный запуск движка; коды возврата `--audit` и `--silent` больше не теряются; первый запуск с `--portable` действительно переносимый.
- Английский отчёт и описания категорий рентгена переведены полностью.
- Манифест winget по схеме 1.28, в README — установка через winget.

### What's new

- The block in `hosts` is marked in Latin letters. The markers used to be Cyrillic, and since the file is written in ASCII they turned into "?": the program did not recognise its own block, appended it again on every run, and the rollback did not remove it. Blocks from earlier versions are now recognised and removed, and other lines in `hosts` are left intact.
- Rollback from the journal: whatever could not be restored stays in the journal for another try, and with repeated entries the earliest value is restored. Data files are written whole or not at all, so an interrupted run never leaves half a journal.
- Narrow window: buttons and text no longer run off the edge or get cut; the build checks both the normal and the smallest width.
- Stop and closing the window stop the right engine run; the exit codes of `--audit` and `--silent` are no longer lost; the first start with `--portable` is really portable.
- The English report and the X-ray category descriptions are fully translated.
- winget manifest schema 1.28, and winget installation in the README.

## 1.10.1 — 2026-09-10

### Что нового

- Шаг «Брандмауэр: адреса сбора телеметрии» больше не выглядит зависшим: имена спрашиваются у DNS разом, ответа ждём не дольше 8 секунд. Раньше, особенно за VPN, шаг шёл до двух с половиной минут без единой строки в журнале.
- Чистка временных файлов показывает шаг в начале, а не по окончании.
- Отправка манифеста в каталог winget не падает, если форк каталога не синхронизировался.

### What's new

- The "Firewall: telemetry addresses" step no longer looks frozen: all names are resolved at once and the wait is capped at 8 seconds. Before, especially behind a VPN, the step could run for two and a half minutes without a single line in the log.
- Temporary file cleanup shows each step when it starts, not when it ends.
- Submitting the manifest to the winget catalogue no longer fails when the catalogue fork is out of sync.

## 1.10.0 — 2026-09-10

### Что нового

- 244 настройки вместо 191, 30 модулей: всё сверено с официальным списком Microsoft «Manage connections from Windows OS components to Microsoft services».
- Разрешения приложений политикой: 16 политик (контакты, календарь, звонки, почта, сообщения, задачи, уведомления, радио, голос…). Политику, в отличие от переключателя, не вернут ни приложение, ни обновление. Сюда же — сведения учётной записи: без них новые Windows Age API не отдают приложению возраст.
- Новые разделы: «Камера, микрофон и фон приложений» (по умолчанию выключен) и «Фоновые обращения в сеть» — 12 безопасных пунктов из списка Microsoft.
- Телеметрия совместимости (CEIP, опись программ, AIT, Steps Recorder, задача Compatibility Appraiser Exp) и 9 задач отчётов об использовании функций.
- «Досье» показывает ещё 9 категорий разрешений (ИИ-модели Windows, ключи доступа, USB, Bluetooth, COM-порты, Wi-Fi), «Цифровой след» видит и стирает 5 журналов Windows о работе с программами.
- Опасное из списка Microsoft (корневые сертификаты, синхронизация времени, лицензии, wlidsvc, KMS) сознательно не трогается.

### What's new

- 244 settings instead of 191, 30 modules: everything is checked against Microsoft's own list "Manage connections from Windows OS components to Microsoft services".
- App permissions by policy: 16 policies (contacts, calendar, calls, email, messages, tasks, notifications, radios, voice…). Unlike a switch, a policy cannot be turned back on by an app or an update. Account information is part of it: without it the new Windows Age APIs give an app nothing.
- New sections: "Camera, microphone and background apps" (off by default) and "Background network calls" — 12 safe items from Microsoft's list.
- Compatibility telemetry (CEIP, program inventory, AIT, Steps Recorder, the Compatibility Appraiser Exp task) and 9 feature-usage report tasks.
- The Dossier shows 9 more permission categories (Windows AI models, passkeys, USB, Bluetooth, COM ports, Wi-Fi); the digital trace finds and wipes 5 Windows logs about program activity.
- The risky items on Microsoft's list (root certificates, time sync, licensing, wlidsvc, KMS) are deliberately left alone.

## 1.9.2 — 2026-09-06

### Что нового

- Английский интерфейс перестал быть наполовину русским: переведены строки, которые приходят от движка данными, — факты рентгена, категории телеметрии, названия приложений, «было / стало» на «Изменениях». Проверка перевода теперь читает и движок.
- Манифест уходит в каталог winget сам, следом за релизом.
- Скриншоты в README пересняты на обоих языках.

### What's new

- The English interface is no longer half Russian: strings the engine sends as data are translated — X-ray facts, telemetry categories, app names, "was / now" on the Changes page. The translation check now reads the engine too.
- The manifest goes to the winget catalogue by itself, right after the release.
- README screenshots retaken in both languages.

## 1.9.1 — 2026-09-06

### Что нового

- **Важно для тех, кто поставил 1.9.0:** там откат не работал — схлопывание журнала теряло поля свежих записей. Исправлено и проверяется применением с откатом на живой системе.
- Программа запускается в одном экземпляре, журнал отката пишется под общесистемным замком и больше не растёт без предела.
- Страж проверяет систему через 5 минут после установки обновления Windows, а не ждёт расписания.
- Видно ход проверки («15 / 34» и раздел), журнал выполнения сохраняется в файл, по разделам можно ходить с клавиатуры, экранный диктор читает подписи.
- В свойствах файла — правильная версия (раньше было 5.0.0.0).

### What's new

- **Important if you installed 1.9.0:** its rollback did not work — compacting the journal lost the fields of fresh entries. Fixed, and now checked by applying and rolling back on a live system.
- A single instance: a second launch shows the open window; the undo journal is written under a system-wide lock and no longer grows without limit.
- The guard checks the system 5 minutes after a Windows update is installed instead of waiting for its schedule.
- Check progress is visible ("15 / 34" and the section), the run log can be saved to a file, the sections work from the keyboard, and the screen reader reads the controls.
- The file properties show the right version (it used to say 5.0.0.0).

## 1.9.0 — 2026-09-06

### Что нового

- Движок распаковывается в `ProgramData\Win11Privacy\bin` с правами только для администраторов и перед каждым запуском сверяется по SHA-256 с тем, что вшито в exe.
- Журнал отката пишется по ходу работы, а не один раз в конце: прерванный прогон больше не оставляет изменения без возможности вернуть.
- Кнопка «Прервать», вопрос при закрытии во время работы, понятное окно ошибки и `crash.log` вместо системного диалога.
- Окно первого запуска: один вопрос вместо тринадцати разделов; оно ничего не применяет, только отмечает набор.
- Группы в боковой панели, полоса внимания на «Обзоре», проверка обновления по кнопке — сама программа в сеть не выходит. Профиль помнит отдельные пункты внутри модулей.
- README на двух языках; к релизу прикладывается манифест winget.

### What's new

- The engine is unpacked into `ProgramData\Win11Privacy\bin`, writable by administrators only, and checked against the SHA-256 of what is embedded in the exe before every launch.
- The undo journal is written as the work goes, not once at the end: an interrupted run no longer leaves changes that cannot be reverted.
- A Stop button, a question when closing mid-run, a clear error window and `crash.log` instead of the system dialog.
- A first-run window: one question instead of thirteen sections; it applies nothing, it only ticks a set.
- Sidebar groups, an attention strip on the Overview, an update check on a button — the program never goes online by itself. A profile remembers individual items inside modules.
- A bilingual README; the winget manifest is attached to the release.

## 1.8.0 — 2026-09-04

### Что нового

- Честный индекс на любой Windows: 12 настроек, которых до Windows 11 нет (Copilot, Recall, Click to Do, виджеты), на Windows 10 не считаются ни в плюс, ни в минус.
- «Windows не разрешает» показывается только после настоящего отказа, а не всякий раз, когда значение не задано.
- Переносимый режим: файл `portable.txt` рядом с exe или ключ `--portable` — и всё хранится в папке рядом с программой.
- «Обзор»: карточки «Автозапуск» и «Хронология».
- Сборка ловит обрезанный текст, а не только вылезший за край.

### What's new

- An honest index on any Windows: 12 settings that do not exist before Windows 11 (Copilot, Recall, Click to Do, widgets) count neither way on Windows 10.
- "Windows does not allow it" appears only after a real refusal, not whenever a value is unset.
- Portable mode: a `portable.txt` file next to the exe or the `--portable` switch keeps everything in a folder beside the program.
- Overview: Startup and Timeline cards.
- The build catches cut-off text, not only text that spills over the edge.

## 1.7.2 — 2026-09-03

### Что нового

- Плитки на «Проверке» больше не обрезают подпись и не пропадают на узком окне: подпись переносится на две строки, а плитки в ряд сужаются, но остаются на месте.

### What's new

- The tiles on the Verify page no longer cut their captions or disappear in a narrow window: captions wrap to two lines, and tiles in a row shrink but stay in place.

## 1.7.1 — 2026-09-02

### Что нового

- Настройки, которые Windows не отдаёт даже администратору, больше не тянут индекс вниз: они показываются отдельно и в итог не входят. На Home индекс может честно дойти до 100 %.
- Страж сам делает дневной замер телеметрии — хронология заполняется без кнопки (раньше замер молча не сохранялся).
- HTML-отчёт: разделы «Что о вас узнали» и «Хронология».
- Журнал тише: без чужих английских строк и без «перезагрузите компьютер», когда ничего не менялось.

### What's new

- Settings that Windows withholds even from administrators no longer drag the index down: they are shown separately and left out of the total. On Home the index can honestly reach 100%.
- The guard takes the daily telemetry measurement itself, so the timeline fills without a button (before, the measurement was silently not saved).
- HTML report: "What they learned about you" and "Timeline" sections.
- A quieter log: no stray English lines, and no "restart your computer" when nothing changed.

## 1.7.0 — 2026-09-02

### Что нового

- «Что о вас узнали»: из событий телеметрии вытаскиваются факты — установленные программы, модель и серийные номера железа, подключённые устройства, метки, по которым события сводят в один профиль, часовой пояс.
- Хронология приватности: телеметрия по дням, обращения к датчикам, правки программы, возвраты стража и обновления Windows — на одной оси.
- Возврат из резервной копии реестра одной кнопкой: программа сама находит копии.
- «Что изменится»: список «сейчас → станет» до того, как нажать «Применить».

### What's new

- "What they learned about you": facts pulled out of the telemetry events — installed programs, hardware model and serial numbers, connected devices, the tags events are joined into one profile by, the time zone.
- Privacy timeline: telemetry by day, sensor access, the program's own changes, guard reversions and Windows updates — on one axis.
- Restore from a registry backup with one click: the program finds the backups itself.
- "What will change": a "now → after" list before you press Apply.

## 1.6.6 — 2026-09-01

### Что нового

- Резервная копия и точка восстановления делаются только перед первым настоящим изменением, а не на каждом запуске; страж копий не делает вовсе.
- Счёт веток в копии честный, невыгруженные ветки названы поимённо, а одна нечитаемая ветка больше не обрывает всю копию.

### What's new

- The registry backup and the restore point are made only right before the first real change, not on every run; the guard makes none at all.
- The count of backed-up keys is honest, keys that could not be exported are named, and one unreadable key no longer aborts the whole backup.

## 1.6.5 — 2026-09-01

### Что нового

- «Уже настроено» узнают все виды настроек: VS Code, переменные среды, службы, задачи. Раньше они переписывались при каждом запуске и выдавали себя за изменения.

### What's new

- Every kind of setting now recognises "already set": VS Code, environment variables, services, tasks. Before, they were rewritten on every run and showed up as changes.

## 1.6.4 — 2026-09-01

### Что нового

- Резервная копия реестра снова охватывает все ключи, которые программа меняет, включая политики виджетов и сессии трассировки.

### What's new

- The registry backup again covers every key the program changes, including widget policies and trace sessions.

## 1.6.3 — 2026-09-01

### Что нового

- Политика, которую Windows не отдаёт даже администратору (например, виджеты на Home), больше не считается ошибкой программы: она идёт отдельной строкой «Windows не разрешила», с подсказкой обходного пути — удалить пакет виджетов на странице «Приложения».

### What's new

- A policy that Windows withholds even from administrators (such as widgets on Home) is no longer counted as the program's error: it gets its own "Windows did not allow it" line with a workaround — remove the widgets package on the Apps page.

## 1.6.2 — 2026-09-01

### Что нового

- Отказ реестра объясняется до конца: программа проверяет, закрыт ключ целиком или Windows держит один параметр.
- У модулей появились подсказки обходного пути; чистка больше не сыпет ошибками на папках без файлов.

### What's new

- Registry refusals are explained in full: the program checks whether the whole key is locked or Windows holds on to one value.
- Modules got workaround hints; cleanup no longer spills errors on folders without files.

## 1.6.1 — 2026-09-01

### Что нового

- Неудачная запись больше не попадает в журнал отката как изменение.
- При отказе — вторая попытка обычным API реестра и понятное объяснение, что именно не так.
- Доску виджетов можно удалить на странице «Приложения» — на Home это единственный надёжный способ.

### What's new

- A failed write no longer lands in the undo journal as a change.
- On a refusal there is a second attempt through the plain registry API and a clear explanation of what went wrong.
- The widgets board can be removed on the Apps page — on Home that is the only reliable way.

## 1.6.0 — 2026-09-01

### Что нового

- **Важно:** начиная с 1.1.0 настройки реестра писались под числовыми именами («0», «1» вместо AllowTelemetry) и ничего не меняли. Исправлено; мусор прежних версий программа находит и убирает сама.
- Страница «Автозапуск»: что стартует вместе с Windows и зачем; отключение обратимо и попадает в общий откат.
- Запрет выхода в сеть отдельной программе прямо из «Монитора»; монитор учитывает и разрешённые соединения, а не только отказы.
- Наборы «Базовый / Строгий / Максимум».
- Страница «Изменения»: каждая правка с прежним значением и возврат отдельной строки.
- «О программе»: что программа хранит о вас, с кнопкой стереть; выбор темы и частоты проверок стража. HTML-отчёт переведён на английский.

### What's new

- **Important:** since 1.1.0 registry settings were written under numeric names ("0", "1" instead of AllowTelemetry) and changed nothing. Fixed; the program finds and removes the leftovers of earlier versions by itself.
- A Startup page: what launches with Windows and why; disabling is reversible and part of the general rollback.
- Block a single program from the network right from the Monitor; the monitor counts allowed connections, not only refusals.
- Basic / Strict / Maximum presets.
- A Changes page: every edit with its previous value, and reverting a single row.
- About: what the program keeps about you, with a button to erase it; theme choice and guard frequency. The HTML report is translated to English.

## 1.3.0 — 2026-09-01

### Что нового

- Отключение сессий трассировки (ETW), которые Windows запускает при загрузке помимо службы DiagTrack.
- Доказательство результата: что было до программы и что стало — сборщики, задачи, домены, правила брандмауэра, события в сутки.
- Полный английский перевод, включая названия всех 191 настройки.

### What's new

- Turning off the trace sessions (ETW) Windows starts at boot besides the DiagTrack service.
- Proof of the result: what it was before the program and what it is now — collectors, tasks, domains, firewall rules, events per day.
- A complete English translation, including the names of all 191 settings.

## 1.2.0 — 2026-09-01

### Что нового

- Откат одной кнопкой по журналу изменений — ручной импорт `.reg` больше не нужен.
- 25 категорий разрешений приложений вместо 6, в том числе у программ, которые разрешение имеют, но ещё не пользовались.
- 181 настройка вместо 147: 24 задачи планировщика, 40 доменов телеметрии, модуль OneDrive.
- Английский интерфейс; к релизу прикладываются контрольные суммы SHA-256.

### What's new

- One-click rollback from the change journal — no manual `.reg` import any more.
- 25 app permission categories instead of 6, including apps that hold a permission but have not used it yet.
- 181 settings instead of 147: 24 scheduled tasks, 40 telemetry domains, a OneDrive module.
- An English interface; SHA-256 checksums are attached to the release.

## 1.1.0 — 2026-09-01

### Что нового

- Запрет доступа к камере, микрофону и геолокации прямо в «Досье».
- Настройка по отдельным пунктам: модуль раскрывается в список, лишнее можно снять.
- Блокировка адресов сбора данных в брандмауэре и запрет шифрованного DNS (DoH) в Windows, Edge и Chrome — через него телеметрия обходит `hosts`.
- Удаление предустановленных приложений с защитой системных компонентов.

### What's new

- Revoking camera, microphone and location access right in the Dossier.
- Per-item settings: a module expands into a list and anything unwanted can be unticked.
- Blocking data-collection addresses in the firewall and turning off encrypted DNS (DoH) in Windows, Edge and Chrome — telemetry bypasses `hosts` through it.
- Removing preinstalled apps, with system components protected.

## 1.0.0 — 2026-09-01

### Что нового

- Первая версия. Отключает сбор данных Microsoft (реестр, службы, задачи, `hosts`, брандмауэр), показывает, что уже собрано (рентген телеметрии, досье по датчикам и цифровому следу), а страж возвращает настройки, сбитые обновлениями. Снимки состояния, чистка, светлая и тёмная темы. Ничего устанавливать не нужно.

### What's new

- The first version. Turns off Microsoft's data collection (registry, services, tasks, `hosts`, firewall), shows what has already been collected (telemetry X-ray, a dossier of sensors and the digital trace), and a guard puts back settings knocked out by updates. State snapshots, cleanup, light and dark themes. Nothing to install.
