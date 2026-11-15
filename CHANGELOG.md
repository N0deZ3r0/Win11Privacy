# Изменения / Changelog

Описание каждого релиза берётся отсюда: сборка по тегу `vX.Y.Z` ищет раздел
`## X.Y.Z` и кладёт его в описание релиза на GitHub. Новое пишется в раздел
«Не выпущено»; перед выпуском он переименовывается в номер версии.

The text of every release comes from this file: a build of tag `vX.Y.Z` looks for
the `## X.Y.Z` section and puts it into the GitHub release. New entries go under
«Не выпущено» (Unreleased), which is renamed to the version number before release.

## Не выпущено

### Что нового

**Номер устройства (GDID): аудит и исправления**
- «Передача номера» проверяется по всем трём службам, которые отключает модуль: CDPSvc, CDPUserSvc и DoSvc, — и по копиям CDPUserSvc у каждого вошедшего пользователя (`CDPUserSvc_…`). Раньше вкладка «Номер устройства» и «Цифровой след» смотрели только CDPSvc и DoSvc, а «службы нет» и «реестр не прочитался» не различали. Теперь у каждой службы — тип запуска словом (отключена, вручную, автоматически, нет на этой системе, не прочиталось), проверка одна на обе страницы, и «закрыта» говорится, только когда прочиталось всё. Если службы отключены, но ещё действует прежнее (служба не остановилась, копия CDPUserSvc заведена до отключения, Windows до перезагрузки помнит прежний тип запуска), плитка пишет «после перезагрузки», а при ошибке чтения — «не проверено».
- «Копий не нашлось» больше не выдаётся за «номера нет», если часть мест не прочиталась или профили пользователей, которые сейчас не вошли в Windows, не проверялись: и проверка модуля, и стирание отвечают «не проверено». Не прочитавшийся список профилей или подключённых кустов тоже учитывается — раньше это молча давало «проверены все». Автозащита «не проверено» сбитой настройкой не считает и не стирает номер при каждом запуске.
- Смена номера идёт по шагам с ответом каждого: службы → учётные данные у пользователей → у системы → реестр → кэш платформы подключённых устройств → проверка → службы как были. Проверка теперь идёт, пока службы ещё остановлены: раньше вернувшаяся служба учётных записей Microsoft успевала завести новый номер, и он считался «копией, которую Windows не отдала». Службы возвращаются, даже если посреди стирания случился сбой. Итог — одно из: стёрто, копий не было, частично, не стёрто, Windows не дала, не проверено; успехом считаются только первые два.
- Служба учётных записей Microsoft (wlidsvc) на время стирания отключается только после записи «как было» в журнал отката. Раньше её тип запуска помнил только сам движок: оборвись он посреди стирания — служба (а с ней вход в учётную запись Microsoft, Магазин, Xbox) осталась бы отключённой навсегда. Теперь её вернёт следующее стирание, «Вернуть как было» или общий откат.
- Учётные данные «личности» устройства убираются у того, кто сидит за компьютером, и у других пользователей, которые сейчас в Windows. Раньше, если пароль администратора вводил обычный пользователь, чистилось хранилище администратора, а его — нет. Кэш платформы подключённых устройств проверяется в той же папке, которую чистили (раньше — в папке учётной записи администратора).
- «Вернуть как было»: тип запуска возвращается из журнала только тем службам, которые меняла программа, и если вернуть не вышло (журналу нельзя верить, Windows не дала), это ошибка, а не «программа её не меняла». Службы с автоматическим запуском запускаются сразу; что Windows применит только после перезагрузки или нового входа (например, DoSvc), названо прямо. Автозащита перестаёт следить за номером до возврата, а не после. Возвращается и wlidsvc, оставленная отключённой прерванным стиранием. Повторный возврат ничего не ломает.
- Смена номера и «Вернуть как было» завершаются кодом 2 («Готово, с ошибками»), если что-то не прошло, — раньше всегда кодом 0. В ответе смены — итог каждого шага.
- hosts: блоки «серверы каталога устройств» и «запрет выдачи» узнаются по парным меткам. Блок со стёртой закрывающей меткой больше не уносит при снятии строки, которые человек вписал сам, а осиротевшая метка не «открывает» новый блок. Побитый, пустой или повторённый блок не считается стоящим: «Выдача нового: закрыта» говорится, только если блок цел и в нём сервер выдачи, а повторное применение оставляет ровно один блок. Что hosts записался, сверяется сразу: если его тут же изменил антивирус, это ошибка, а не «заблокировано».
- Запрет выдачи: вход через учётную запись Microsoft проверяется у того, кто сидит за компьютером (по SID), а не у учётной записи из переменной `USERNAME`. Если проверить, принадлежит ли компьютер организации, не удалось (WMI или реестр не ответили), номер не трогается. Перед запретом программа предупреждает, если на компьютере есть другие учётные записи Microsoft.
- Отчёт аудита: `docs/security/GDID_AUDIT.md`.
- Третий проход аудита. Смена номера начинается только после предварительной проверки, которая ничего не меняет: все места, где лежит номер, прочитались, список профилей пользователей прочитался, и о каждой службе, которую стирание трогает (wlidsvc, CDPSvc, DoSvc, CDPUserSvc и её копии у пользователей), известно, какой у неё тип запуска и работает ли она. Если чего-то из этого нет, не меняется ничего: ни службы, ни реестр. Раньше стирание начиналось и при местах без доступа, ошибки опроса служб глотались, а служба, о которой ничего не узнали, после стирания могла остаться остановленной.
- Службы на время стирания — как одна операция: запоминается, какими они были, останавливаются только работавшие, и после стирания (на любом пути, и при сбое тоже) запускаются ровно они. Итог сверяется с тем, что было: тип запуска и «работает» проверяются заново, а не считаются по ответу команды запуска. Если тип запуска wlidsvc не прочитался, стирание не начинается (раньше шло дальше с включённой службой).
- Реестр: стирается ровно то, что нашла опись, — каждое значение и каждая «личность» по отдельности, и каждое удаление проверяется. Раньше удалялась вся ветка `DeviceIdentities\production` — вместе с историей выдачи (`Logs`), счётчиками и всем, чего программа не знает. Теперь `Logs` и чужие значения остаются на месте, «личность» с незнакомым содержимым не удаляется (итог — «частично»), а кэш `NegativeCache` без доступа — «не проверено», а не «пусто».
- Кэш платформы подключённых устройств проверяется после чистки своим обходом: по ссылкам (junction) он не ходит, а сама ссылка считается оставшимся; папка без доступа — «не проверено», а не «пусто»; ссылка на месте самой папки не чистится.
- Пробный запуск смены номера больше не отвечает «успех» всегда: если часть мест не прочиталась или есть профили вне Windows, он говорит, что настоящий запуск полного «стёрто отовсюду» не даст.
- «Вернуть как было»: служба, которой больше нет, — «нет на этой системе», отказ Windows — «нет доступа», возврат, который не сошёлся, — ошибка; запись журнала остаётся, пока возврат не проверен. Снятие блоков hosts, правила брандмауэра и правка профиля автозащиты теперь тоже проверяются; если хоть одна стадия не прошла, итог — «частично» или «не вернулось», код 2.
- Смена номера и возврат отдают итог одной формы (`wipe` / `restore.result`: статус, сколько найдено, убрано, осталось, не проверено, службы до и после); код выхода берётся из того же итога — окно, журнал работы и код не расходятся.
- Учётные записи и организация: локальная учётная запись, у которой учётная запись Microsoft подключена только к приложениям, — не «вход через учётную запись Microsoft»; учётные записи Entra ID и профили `S-1-12-1-…` учитываются. Различаются домен, Entra ID, гибридное подключение (оба сразу), управление (MDM, в том числе OMA-DM) и рабочая учётная запись без управления устройством; что не прочиталось — отказ, а не «домашний компьютер».
- «Вернуть как было» после перезагрузки с отключёнными службами: тип запуска теперь всегда передаётся и диспетчеру служб. Раньше он менялся только в реестре, диспетчер до перезагрузки помнил «отключена», и CDPSvc не запускалась (ошибка 1058, найдено на тестовой машине). Если Windows не даёт его передать (DoSvc), служба названа «заработает после перезагрузки», а не сбоем.
- Отчёт третьего прохода: `docs/security/GDID_AUDIT_3.md`.

**Окно**
- «Хронология» в невысоком окне (например, экран 1024 × 768 или крупный масштаб) прокручивается целиком. Раньше график сплющивался так, что подписи оси наезжали друг на друга, а список «Что случилось» сжимался меньше чем до двух строк.

### What's new

**Device ID (GDID): audit and fixes**
- "Sending the ID" is checked on all three services the module disables — CDPSvc, CDPUserSvc and DoSvc — and on every signed-in user's copy of CDPUserSvc (`CDPUserSvc_…`). The Device ID tab and "Digital footprint" used to look at CDPSvc and DoSvc only, and could not tell "no such service" from "registry not readable". Each service now has a start type in words (disabled, manual, automatic, not on this system, could not be read), one check serves both pages, and "blocked" is shown only when everything was read. If the services are disabled but the old state still applies (a service did not stop, a CDPUserSvc copy was created before the change, Windows remembers the old start type until a restart), the tile says "after a restart", and on a read error "not verified".
- "No copies found" is no longer reported as "no ID" when some places could not be read or the profiles of users who are not signed in were not checked: both the module check and the wipe answer "not verified". An unreadable profile list or hive list counts too — it used to mean "all checked". Auto-protection does not treat "not verified" as a drifted setting and no longer wipes the ID on every run.
- Changing the ID runs in steps, each with its own result: services → users' credentials → system credentials → registry → Connected Devices Platform cache → verification → services back. Verification now happens while the services are still stopped: the Microsoft account service used to come back fast enough to get a new ID, which was then counted as "a copy Windows did not release". The services are restored even if the wipe fails half-way. The result is one of: wiped, nothing found, partial, not wiped, Windows refused, not verified; only the first two count as success.
- The Microsoft account service (wlidsvc) is disabled for the wipe only after its "before" state is written to the rollback journal. Its start type used to live only in the engine's memory: had the engine been killed mid-wipe, the service — and with it Microsoft account sign-in, the Store and Xbox — would have stayed disabled for good. Now the next wipe, "Restore" on the Device ID tab or a full rollback brings it back.
- The device identity's credentials are removed for the person at the computer and for other users who are signed in right now. If a standard user typed an administrator's password, the administrator's store used to be cleaned instead of theirs. The Connected Devices Platform cache is verified in the same folder that was cleaned (it used to be the administrator's).
- "Restore": start types are restored from the journal only for services the program changed, and a failure (journal not trusted, Windows refused) is an error, not "the program did not change it". Automatic services are started right away; what Windows will apply only after a restart or a new sign-in (for example DoSvc) is said plainly. Auto-protection stops watching the ID before the restore, not after. A wlidsvc left disabled by an interrupted wipe is restored too. Running it again breaks nothing.
- "Change the ID" and "Restore" end with exit code 2 ("Done, with errors") when something failed — they always returned 0. The change reports the result of every step.
- hosts: the "device directory servers" and "issuing lock" blocks are matched by paired markers. A block whose closing marker was deleted no longer takes the user's own lines with it on removal, and an orphaned marker no longer "opens" a new block. A damaged, empty or repeated block does not count as in place: "New ID issuing: blocked" is shown only when the block is intact and contains the issuing server, and applying it again leaves exactly one block. The written hosts file is checked right away: if an antivirus changed it at once, that is an error, not "blocked".
- Issuing lock: Microsoft account sign-in is checked for the person at the computer (by SID), not for the account in the `USERNAME` variable. If the program cannot tell whether the computer belongs to an organisation (WMI or the registry did not answer), the ID is left alone. Before the lock, the program warns when other Microsoft accounts exist on the computer.
- Audit report: `docs/security/GDID_AUDIT.md`.
- Third audit pass. Changing the ID starts only after a read-only preflight: every place the ID is stored was read, the user profile list was read, and for every service the wipe touches (wlidsvc, CDPSvc, DoSvc, CDPUserSvc and its per-user copies) the start type and running state are known. If any of that is missing, nothing changes — neither services nor the registry. The wipe used to start with unreadable places, errors from the service queries were swallowed, and a service nothing was learned about could stay stopped afterwards.
- Services during the wipe are one transaction: their state is recorded, only the running ones are stopped, and afterwards (on every path, failures included) exactly those are started again. The result is checked against the recorded state — start type and running are read again instead of trusting the start command. If wlidsvc's start type cannot be read, the wipe does not start (it used to go on with the service enabled).
- Registry: exactly what the inventory found is removed — each value and each device identity on its own, and every removal is verified. The whole `DeviceIdentities\production` branch used to be deleted, including the issuing history (`Logs`), counters and anything the program does not know. Now `Logs` and unrelated values stay, an identity with unknown content is left in place (result "partial"), and an unreadable `NegativeCache` is "not verified" rather than "empty".
- The Connected Devices Platform cache is verified after cleaning with a walk of its own that does not follow links (junctions); a link left inside counts as left over, an unreadable folder is "not verified" rather than "empty", and a link in place of the folder itself is not cleaned.
- A dry run of the ID change no longer always reports success: if some places could not be read or there are profiles of users who are not signed in, it says the real run will not reach "wiped everywhere".
- "Restore": a service that no longer exists is "not on this system", a Windows refusal is "access denied", a restore that does not verify is an error, and the journal entry stays until the restore is verified. Removing the hosts blocks, the firewall rule and the auto-protection profile change are now verified too; if any stage fails, the result is "partial" or "not restored" with exit code 2.
- Changing and restoring the ID return one result shape (`wipe` / `restore.result`: status, how much was found, removed, left, not verified, services before and after); the exit code comes from the same result, so the window, the log and the exit code cannot disagree.
- Accounts and organisations: a local account with a Microsoft account connected only to apps is not "signing in with a Microsoft account"; Entra ID accounts and `S-1-12-1-…` profiles are taken into account. Domain join, Entra ID join, hybrid join (both), management (MDM, including OMA-DM) and a work account without device management are told apart; anything that cannot be read means refusal, not "home computer".
- "Restore" after a restart with the services disabled: the start type is now always handed to the service manager too. It used to change only in the registry, the service manager remembered "disabled" until the next restart, and CDPSvc did not start (error 1058, found on the test machine). If Windows does not allow it (DoSvc), the service is reported as "will work after a restart", not as a failure.
- Third-pass report: `docs/security/GDID_AUDIT_3.md`.

**Window**
- "Timeline" scrolls as a whole in a short window (for example a 1024 × 768 screen or a large scale). The chart used to be squashed until its axis labels overlapped, and the "What happened" list shrank to less than two lines.

## 2.1.0 — 2026-11-15

### Что нового

**Исправления безопасности и надёжности (по итогам аудита)**
- Окно больше не собирает командную строку движка из данных. Раньше имя раздела реестра для запрета доступа к камере, микрофону или геолокации уходило в неё как есть, а в нём может быть кавычка (завести такой раздел в своём профиле может любая программа пользователя): остаток строки движок разбирал как свои команды и выполнял их с правами администратора. Так же уходил и путь к рабочему столу — при каждом запуске. Теперь командная строка движка постоянная, а операция и её данные идут ему отдельным запросом через стандартный ввод: движок сам проверяет запрос по белому списку операций и форму каждого значения и при любой ошибке не делает ничего. Кавычка или «-Ключ» внутри данных остаются данными. Те же запросы использует и тихий режим (`--profile`, `--audit`).
- Запрет доступа к датчику снова работает: движок принимает настоящие ключи ConsentStore — приложения из Store и обычные программы (`NonPackaged`), в том числе с кириллицей в пути, — и отвергает всё остальное (пустые сегменты, «..», корни реестра, сетевые пути), не трогая реестр.
- Резервная копия реестра больше не кладётся на рабочий стол: программа хранит её у себя, в `C:\ProgramData\Win11Privacy\backups`, где менять её могут только администраторы, а вернуть её можно на странице «Изменения» («Из резервной копии»); «Открыть папку резервных копий» открывает это хранилище. Копия выгружается, проверяется и подписывается в защищённой рабочей папке и переносится в хранилище целиком, одним переименованием. Раньше reg.exe писал прямо в папку на рабочем столе, и файл можно было подменить между выгрузкой и подписью. У списка подписей теперь своя подпись: убрать из копии файл незаметно нельзя. В хранилище остаются самая первая копия и 20 последних. Копии прежних версий на рабочем столе по-прежнему видны в списке и возвращаются.
- Возврат из копии: если в папке есть лишний, недостающий или изменённый файл, ссылка или чужая ветка реестра, не импортируется ничего — раньше импортировалось «всё, кроме подозрительного». Подпись сверяется ещё раз прямо перед импортом, пока файл открыт без права записи для других. Копии прежних версий со списком подписей возвращаются как раньше, а список подписей прежнего вида у копии, сделанной этой версией, считается подменой. Если reg.exe не принял часть файлов, окно пишет «Готово, с ошибками», а не «Готово».
- Политики Firefox (`policies.json`) записываются одним действием: во временный файл рядом, с проверкой и заменой целиком. Раньше оборванная запись могла оставить файл пустым и стереть все политики, в том числе корпоративные. Кириллица в чужих политиках больше не портится при записи, а двое пишущих одновременно не теряют правки друг друга: у окна и у задач автозащиты (от имени системы) теперь один общий замок — раньше при ошибке открытия замка каждый брал свой и они могли писать одновременно. Замок, заранее заведённый чужой программой, не используется: запись отменяется.
- Запрет доступа к датчику сообщает о неудаче честно: код выхода совпадает с ответом движка, и окно считает успехом только «ok» вместе с кодом 0.
- Запрет выхода в сеть отдельной программе учитывает полный путь к ней, а не только имя файла: две программы с одинаковым именем в разных папках больше не мешают друг другу.
- Честные коды возврата: «Вернуть всё» и установка стража, слежения и уведомлений сообщают об ошибке, если она была, а не всегда «Готово».
- Папка карантина создаётся сразу с правами только для системы и администраторов.
- Проверка прав папок и файлов учитывает и унаследованные права: раньше папка, открытая обычным пользователям через родительскую, считалась защищённой. Проверяются и запреты, право удалять вложенное, менять права и владельца, а для папки данных и папки Firefox — весь путь до них: если папку выше может переименовать не администратор, программа ей не доверяет.

**Журнал**
- Журнал на странице «О программе» читается легче: название действия и разделы движка — полужирными заголовками с пустой строкой перед ними, вместо полос из чёрточек; итог («Готово.» или ошибка) выделен; текст больше не прижат к левому краю поля.

**Окно при крупном масштабе Windows (125–200 %)**
- Окно всегда открывается одного вида под ваш экран — просторным, чтобы описания настроек и строки журнала помещались, но не больше экрана, — и всё в нём помещается: страницы перестраиваются под ширину окна. Размер из прошлого запуска больше не берётся: он хранился в пикселях и после смены масштаба Windows давал окно то такое, где всё сбивалось в кучу, то огромное.
- «Наблюдение → Сеть»: описание больше не обрезается — карточка растёт по тексту, кнопки переносятся под него, как на других страницах.
- Плитки со сводкой не разваливаются на 3 + 1: в узком окне они сужаются и остаются в одном ряду, а если не влезают и так — встают ровно, 2 × 2.
- «Сбор данных» и «Хронология» в невысоком окне (например, 1366 × 768 при 125 %): кнопка «Сохранить отчёт» стоит в общем ряду кнопок, а график делит высоту со списком — список под ними больше не сжимается в полоску. Боковая панель в узком окне сворачивается до значков раньше и оставляет место страницам.
- Кнопки компактнее — с полями, как у кнопок Windows 11, — и всегда в один ряд: на «Автозащите» все семь кнопок теперь умещаются в окне обычного размера. Если окно совсем узкое, кнопки, которым не хватило места, уходят в меню «Ещё ▾» в конце ряда, а не на вторую строку.
- «О программе»: кнопки стоят в один ряд (раньше переносились, хотя места хватало), полоса прокрутки тёмная, как на остальных страницах.
- Поиск на «Приложениях», «Автозагрузке» и «Изменениях» стоит вровень с карточками и одной ширины с поиском на «Настройках».
- В окне, сжатом почти до минимума, сводка из двух рядов плиток прячется — список под ней остаётся виден.
- Сборка проверяет все страницы ещё и с крупным шрифтом (как при 150 %) и ловит текст, обрезанный по высоте, и список, сжатый в полоску. Раньше страницы проверялись только при 100 %, и такие ошибки проходили.

**Установщик**
- Появился установщик `Win11Privacy-Setup.exe` на русском и английском (язык — по Windows). В мастере на выбор: обычная установка — в Program Files, с ярлыком в «Пуске» и удалением через «Параметры → Приложения» — или портативная версия: программа распаковывается в выбранную папку (например, на флешку) вместе с `portable.txt`, все её данные хранятся там же, а в системе ничего не регистрируется.
- При удалении задачи автозащиты и слежения убираются вместе с программой. Перед удалением установщик напоминает, что применённые настройки останутся в Windows и как вернуть всё как было, а после — спрашивает, стереть ли данные программы (по умолчанию — нет: без журнала изменений вернуть настройки будет нечем).
- Открытую программу установщик не меняет «на ходу» — попросит её закрыть.
- Лицензия в русском мастере — на русском (перевод; юридическую силу имеет английский текст, он ставится вместе с программой). Лишний значок в правом верхнем углу страниц мастера убран.
- Установщик собирается на GitHub вместе с релизом и там же проверяется по-настоящему: установка, установка поверх, удаление с данными и без, портативная версия. Компилятор Inno Setup закреплён по версии и SHA-256.
- winget теперь ставит программу установщиком (обычная установка в Program Files), а не отдельным exe. Кто ставил её через winget раньше, удалите старую копию и поставьте заново: `winget uninstall N0deZ3r0.Win11Privacy`, затем `winget install N0deZ3r0.Win11Privacy`. `Win11Privacy.exe` без установки по-прежнему лежит в каждом релизе.

### What's new

**Security and reliability fixes (from the audit)**
- The window no longer builds the engine's command line from data. The registry key name used to deny an app the camera, microphone or location went into it verbatim, and it can contain a quote (any program of the user can create such a key in their profile): the rest of the line was parsed as engine commands and run with administrator rights. The Desktop path went the same way, on every run. Now the engine's command line is constant, and the operation and its data go to it as a separate request on standard input: the engine checks the request against an allowlist of operations and the shape of every value itself, and does nothing if anything is off. A quote or a `-Switch` inside the data stays data. Silent mode (`--profile`, `--audit`) uses the same requests.
- Denying an app a sensor works again: the engine accepts real ConsentStore keys — Store apps and ordinary programs (`NonPackaged`), Cyrillic paths included — and rejects everything else (empty segments, "..", registry roots, network paths) without touching the registry.
- The registry backup is no longer put on the desktop: the program keeps it itself in `C:\ProgramData\Win11Privacy\backups`, where only administrators can change it, and it is restored from the "Changes" page ("From a backup"); "Open backup folder" opens that store. The backup is exported, checked and signed in a protected work folder and moved into the store whole, in a single rename. reg.exe used to write straight into the desktop folder, where a file could be swapped between export and signing. The signature list now has a signature of its own, so a file cannot be dropped from a backup unnoticed. The store keeps the very first backup and the 20 newest. Backups from earlier versions on the desktop are still listed and restore.
- Restoring a backup: an extra, missing or changed file, a link or a foreign registry branch in the folder means nothing is imported — it used to import "everything except the suspicious part". The signature is checked again right before the import, while the file is held open without write sharing. Backups from earlier versions with a signature list still restore, while an old-style signature list on a backup made by this version is treated as tampering. If reg.exe rejects some files, the window says "Done, with errors" instead of "Done".
- Firefox policies (`policies.json`) are written in one step: to a temporary file next to it, checked, then swapped in whole. An interrupted write could leave the file empty and wipe every policy, corporate ones included. Non-Latin text in other policies is no longer mangled on write, and two writers at once no longer lose each other's changes: the window and the auto-protection tasks (running as SYSTEM) now share one lock — before, when opening the lock failed, each took its own and both could write at the same time. A lock pre-created by another program is not used: the write is cancelled.
- Denying a sensor reports failure honestly: the exit code matches the engine's answer, and the window counts as success only "ok" together with exit code 0.
- Blocking a single program from the network now keys on its full path, not just the file name: two programs with the same name in different folders no longer collide.
- Honest exit codes: "Restore all" and installing the guard, the watches and the notifications report an error when one occurred, instead of always "Done".
- The quarantine folder is created with a system-and-administrators-only ACL from the start.
- The check of folder and file permissions now counts inherited rights too: a folder opened to ordinary users through its parent used to pass as protected. Deny entries, the right to delete children and to change permissions or the owner are checked as well, and for the data folder and the Firefox folder the whole path to them: if a folder above can be renamed by a non-administrator, the program does not trust it.

**Log**
- The log on the About page is easier to read: the action name and the engine's sections are bold headings with a blank line before them instead of dashed rules, the outcome ("Done." or the error) stands out, and the text no longer hugs the left edge.

**The window at large Windows scaling (125–200 %)**
- The window always opens with the same look for your screen — roomy enough for setting descriptions and log lines, but never larger than the screen — and everything in it fits: pages reflow to the window width. The size from the previous run is no longer reused: it was stored in pixels, and after a Windows scaling change it gave either a window with everything crammed together or a huge one.
- "Observation → Network": the description is no longer cut off — the card grows with the text and the buttons wrap below it, as on the other pages.
- Summary tiles no longer fall apart as 3 + 1: in a narrow window they get narrower and stay in one row, and if even that does not fit they line up evenly, 2 × 2.
- "Data collection" and "Timeline" in a short window (e.g. 1366 × 768 at 125 %): the "Save report" button sits in the common button row and the chart shares the height with the list, so the list below no longer shrinks to a strip. In a narrow window the sidebar collapses to icons sooner and leaves room for the pages.
- Buttons are more compact — with the padding of Windows 11 buttons — and always in one row: on "Auto-protection" all seven buttons now fit in a window of ordinary size. In a very narrow window the buttons that do not fit go into a "More ▾" menu at the end of the row instead of a second line.
- "About": the buttons stay in one row (they used to wrap although there was room), and the scroll bar is dark, as on the other pages.
- The search box on "Apps", "Startup" and "Changes" lines up with the cards and has the same width as on "Settings".
- In a window shrunk almost to its minimum, a two-row summary of tiles hides, so the list below it stays visible.
- The build now also checks every page with a large font (as at 150 %) and catches text clipped vertically and lists squeezed into a strip. Pages used to be checked at 100 % only, so such errors went through.

**Installer**
- A new installer, `Win11Privacy-Setup.exe`, in English and Russian (following the Windows language). The wizard offers a choice: a regular installation — into Program Files, with a Start menu shortcut and removal in Settings → Apps — or a portable copy: the program is unpacked into a folder of your choice (a USB stick, for example) together with `portable.txt`, all its data stays there, and nothing is registered in the system.
- Uninstalling removes the auto-protection and monitoring tasks together with the program. Before removal the uninstaller reminds you that the applied settings stay in Windows and how to put everything back, and afterwards it asks whether to wipe the program data (no by default: without the change journal the settings could no longer be restored).
- The installer does not change a running program under its feet — it asks you to close it.
- The Russian wizard shows the licence in Russian (a translation; the English text, installed with the program, is the binding one). The stray icon in the top-right corner of the wizard pages is gone.
- The installer is built on GitHub together with the release and checked there for real: install, reinstall, uninstall with and without the data, the portable copy. The Inno Setup compiler is pinned by version and SHA-256.
- winget now installs the program with the installer (a regular installation into Program Files) rather than as a bare exe. If you installed it with winget before, remove the old copy and install again: `winget uninstall N0deZ3r0.Win11Privacy`, then `winget install N0deZ3r0.Win11Privacy`. `Win11Privacy.exe` without installation is still attached to every release.

## 2.0.0 — 2026-11-14

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
- Журнал отката подписывается (HMAC-SHA256). Ключ лежит в `C:\ProgramData\Win11Privacy`, и читать его могут только система и администраторы. Журнал, изменённый или дописанный кем-то другим, не применяется и откладывается. Журнал прежней версии без подписи, лежащий в переносимой папке, возвращает только записи о настройках самой программы; задачи по маске (OneDrive, NVIDIA) — только из их папки планировщика, а не любые с подходящим именем. Недоверенный журнал (повреждён, подпись не сошлась или её нечем проверить) не запускает и прежний откат служб и задач «по умолчанию». Ключ заводится только при записи журнала: проверка без ключа не создаёт новый, а откладывает журнал целым. Полный откат больше не стирает отложенный журнал вместе с остальными данными и не пишет «настройки возвращены», если по журналу ничего не вернулось.
- Отключённые службы и задачи производителя записываются в тот же подписанный журнал и при откате возвращаются ровно такими, какими были. Список прежних версий (`oem-disabled.json`) при откате сверяется с тем, что программа сама узнаёт как компоненты производителя.
- PowerShell запускается только по полному системному пути — окном, в режимах `--audit` и `--silent` и задачами стража. Раньше в запасе было просто «powershell.exe», а такое имя Windows ищет и в папке программы.
- Переносимый режим: страж и наблюдение — задачи, которые сами запускаются с правами администратора, — ставятся, только если папку программы нельзя подменить (например, в Program Files на диске NTFS). Папка данных тогда закрывается так же, как `ProgramData\Win11Privacy`. Раньше переносимая папка считалась доверенной без всякой проверки.
- Если защищённую папку для движка подготовить не удалось, движок больше не запускается из временной папки пользователя: там его могла бы подменить любая программа.
- Папка данных прежних версий проверяется на любой глубине, а не только в корне: чужие файлы, ссылки и то, что открыто на запись чужим явным правом, уходят в карантин.
- Короткие задачи планировщика (номер устройства, закрытые задачи) получают случайное имя и перед запуском сверяются: та ли команда и от чьего имени.
- Откат возвращает значения реестра того же вида и с теми же данными. В журнал теперь пишется вид прежнего значения (раньше — нового, и строка «1» возвращалась числом), а раскрываемые строки — с нераскрытыми %переменными%. Значение вида, который откат не вернул бы, не меняется вовсе.
- Каждый возврат сверяется: параметр реестра читается обратно (вид и данные), переменная среды — тоже. Запись считается вернувшейся только после сверки; раньше успехом считался сам вызов команды.
- Откат убирает из журнала только то, с чем закончил: записи, которые за это время дописал страж или второе окно, остаются. Задачи стража и слежения удаляются до возврата настроек, а работающая — сначала останавливается: страж, сработавший посреди отката, раньше ставил настройки обратно.
- Журнал раньше изменения — теперь у всех изменений, в том числе у политики аудита для монитора (раньше она записывалась после auditpol).
- Профили других пользователей: в журнал идёт вид прежнего значения, записанное сверяется, куст подключается один раз на профиль, а куст, оставшийся подключённым после оборванного запуска, отключается при следующем — иначе Windows выдала бы этому человеку временный профиль.
- Файлы данных (profile.json и другие) читаются только из папки, которой можно верить, — так же, как пишутся.
- Описание модели безопасности и гарантий отката — docs/security-model.md.
- Самопроверка больше не стирает ветку `Software\Win11Privacy` в реестре целиком: она убирает только своё пробное значение и только те ключи, которых до неё не было, — и лишь пустыми.
- «Удалить данные программы» стирает только файлы, которые программа кладёт сама (список имён и строгие образцы); чужие файлы в той же папке не показываются и не удаляются. `-DataRoot` принимается, только если это папка `Win11Privacy-Data` по полному пути: указанный по ошибке, например, на «Документы», он позволил бы программе писать туда и стирать файлы с совпадающими именами.
- Возврат из резервной копии больше не импортирует с правами администратора то, что дописала в копию другая программа. Копия лежит на рабочем столе, куда пишет любая программа пользователя; теперь её файлы подписываются при создании, а при возврате копируются в защищённую папку, сверяются там и импортируются оттуда. Изменённый, подложенный или неподписанный файл не импортируется; копию прежней версии можно открыть только вручную.
- Движок с правами администратора больше не загружает модули PowerShell из «Документов» пользователя. Первым в списке модулей стояла эта папка, куда пишет любая программа без повышения, а команды планировщика, брандмауэра и DNS подгружаются по этому списку: подложенный модуль выполнился бы с правами администратора — у стража при каждом входе, без запроса UAC. Теперь первая команда движка сводит список к системным папкам, а пути Windows, ProgramData, Program Files и профиля берутся у самой системы, а не из переменных окружения. Окно запускает движок с теми же значениями.
- Замок журнала отката — файл в защищённой папке, а не общий мьютекс, который мог занять любой процесс без прав: пока он его держал, не работали ни применение, ни откат.
- Папки пользователя больше не чистятся и не правятся по пути с правами администратора. Профиль (`%TEMP%`, кэши, `settings.json` VS Code) обрабатывает короткая задача от имени самого пользователя без повышения; в общих папках Windows (`C:\Windows\Temp`, очередь отчётов об ошибках) удаляются только объекты, чей владелец система или администраторы, — подложенная ссылка пропускается. Раньше ссылка, подставленная между проверкой и удалением, могла увести удаление с правами администратора в другое место.
- Откат настроек VS Code и Firefox возвращает только то, что поменяла программа: в журнал идёт один ключ (как было), а не копия всего файла. Раньше откат копировал поверх `settings.json` снимок первого применения, и всё, что человек поменял потом, пропадало. Файл, который создала программа и который опустел, удаляется; политики Firefox больше не обрезаются по глубине.
- Папка резервной копии на рабочем столе получает случайный хвост в имени и проверяется на ссылку; пробная папка самопроверки — так же, а её удаление не идёт по ссылкам.
- Профильные настройки доходят и до пользователя, который вошёл в Windows, если пароль администратора ввёл он, а движок работает от имени администратора. Страж и слежение при этом остаются на учётной записи администратора (повышение есть только у неё) — программа говорит об этом при включении.
- Тихий режим `--silent --profile` проверяет имена модулей и пунктов из файла и отказывается от файла с чужим содержимым, а не склеивает его в командную строку движка.
- Новая папка данных создаётся сразу с защищёнными правами, а не в два шага.
- Релиз: сборка и тесты идут с правом только читать репозиторий, а публикация, секрет каталога winget и подпись происхождения — в отдельном задании только для тегов; сторонние действия закреплены хешем коммита; файлы релиза сверяются с контрольными суммами и получают аттестацию сборки.
- Карантин папки данных прежней версии больше не идёт в предсказуемую папку «...untrusted-<время>»: её обычный пользователь мог завести заранее ссылкой, и перенос чужих файлов с правами администратора ушёл бы по ней. Теперь папка карантина каждый раз новая, со случайным именем, и проверяется, что это не ссылка.
- Движок и окно перед запуском убирают переменные окружения, через которые .NET и оболочка подгружают в процесс чужой код (профайлер CLR, стартовые перехватчики, слой совместимости), — ни один процесс, который запускает движок с правами администратора, через них не перехватить.
- Копия политики аудита для монитора пишется в защищённую папку программы, а не во временную папку пользователя; итог задачи от имени пользователя сверяется по владельцу файла.
- winget: описание пакета и README велят ставить с ключом `--scope machine` — тогда самоповышающийся exe лежит в папке, куда пишут только администраторы, а не в профиле пользователя (сам portable-пакет winget выбрать область не даёт).

**Исправления**
- Проверка утечек честнее о своих пределах: она проверяет, отвечают ли известные серверы сбора на TCP 443, а не наблюдает трафик. «Ни один сервер не ответил» больше не подаётся как «телеметрия не дойдёт»; окно говорит, чего проверка не видит (новые адреса, другие порты, UDP/QUIC, сторонние службы), а в ответе движка доступность адресов (`endpointReachability`) отделена от наблюдения телеметрии (`telemetryObserved` — не измерялось).
- Применение и откат заканчиваются честным кодом выхода: 0 — всё прошло, 2 — закончено, но с ошибками. Раньше применение всегда отвечало нулём, а откат — тоже, и тихий режим не мог сообщить о неудаче профиля. Негодный файл профиля — код 4.
- Отказ при отключении службы больше не называется «недоступна». «Службы нет» и «Windows не дала» — разное: второе считается как «Windows не разрешает» (отказ в доступе) или как ошибка, и в итог попадает.
- «Уже настроено» учитывает вид значения: строка «1» на месте числа 1 больше не считается применённой — ни при применении, ни при проверке.
- Блокировка адресов телеметрии больше не закрывает по IP имена, которые живут на общих узлах (общее хранилище Azure, края e-msedge, вход Office): закрыв такой адрес, программа отрезала бы чужие службы. Они остаются закрыты по имени в hosts. `licensing.mp.microsoft.com` убран из hosts — через общий вход этого имени идут лицензии приложений Магазина.
- Чистка временных файлов выключена по умолчанию и не входит в готовые наборы; корзина очищается только после отдельного вопроса, а файлы моложе суток во временной папке не трогаются. Подпись модуля «Защитник» говорит прямо: облачная защита (MAPS) выключается, и защита от новых угроз заметно слабеет.
- Тексты каталога winget больше не обещают, что откатывается каждое изменение (удалённое не вернуть), а галочка «проверено winget validate» ставится, только если проверка действительно прошла.
- Firefox: уже лежащий `policies.json`, который не разбирается (например, с комментарием), больше не перезаписывается — раньше его политики, в том числе корпоративные, пропадали.
- Защитник: при включённой «Защите от подделки» программа прямо говорит, что облачную защиту и отправку образцов Windows не отдаёт даже политикой и параметры подействуют только после её ручного выключения.
- Номер устройства: стирание честнее говорит о результате. Учётные данные «личности» устройства считаются убранными, только если после `cmdkey` их действительно нет в хранилище (раньше успехом считался сам запуск задачи). У каждой записи в реестре свой итог — убрана, не было или Windows не дала; запись, закрытая от чтения, больше не засчитывается как «не было». Места, которые не удалось прочитать, — хранилище целиком или закрытый ключ внутри него — не выдаются за «стёрто». На время стирания останавливается и служба DoSvc; если хоть одна из служб не остановилась, стирание не начинается и службы возвращаются как были. Успехом стирание считается, только если службы, работавшие до него, снова запущены, а кэш платформы подключённых устройств действительно пуст. Копии номера ищутся и в профилях пользователей, которые сейчас вошли в Windows; про профили остальных программа прямо пишет, что их не проверяла. Плитка «Номер» берёт номер из любого найденного хранилища, а не только из профиля текущего пользователя.
- Наблюдение за сетью: включено ли оно, теперь определяется по числу в политике аудита, а не по словам — на немецкой или французской Windows оно считалось выключенным всегда. Сбой `auditpol` больше не выдаётся за успех, а откат возвращает ту политику аудита, что была до программы, а не просто выключает её.
- Публичный ли адрес, теперь решается по диапазонам IANA, а не по началу строки: общие адреса провайдеров (100.64.0.0/10), тестовые и зарезервированные сети, многоадресные IPv6 и IPv4 внутри IPv6 больше не считаются в наблюдении за сетью и проверке утечек «публичными».
- Очистка неотправленной телеметрии больше не меняет владельца и права системной папки `C:\ProgramData\Microsoft\Diagnosis`. Раньше она забирала себе всю папку (`takeown /R`) и открывала всё внутри администраторам (`icacls /T`), и так это и оставалось. Теперь что не удалилось сразу, удаляет короткая задача от имени системы. Её итог не берётся по коду завершения: задача пишет, сколько нашла, удалила и сколько осталось, какие файлы не удалились и почему, и программа называет это как есть — очищено, очищено не всё или не вышло.
- Выключение наблюдения за сетью возвращает ту политику аудита, что была до программы (например, «только успешные»), а не ставит «нет аудита» поверх неё. Включение не происходит, если нынешнюю политику прочитать не удалось (вернуть её потом было бы нечем), а если не записался журнал отката — политика сразу возвращается как была.
- Если журнал безопасности не читается, страница «Монитор» так и говорит, а не показывает пустой список «никто ничего не отправлял». Слежение за сетью в этом случае не пропускает непрочитанные минуты, а пробует снова.
- Запись в реестр проверяется: после записи значение читается обратно и сверяется с задуманным. Если читается другое, это ошибка, а не «[+]», но изменение всё равно попадает в журнал отката. Ошибка записи в журнал больше не глотается.
- Если файл NTUSER.DAT другого пользователя после настройки не отключился, программа говорит об этом и просит перезагрузить компьютер до его входа. Раньше это проходило молча, и при входе Windows выдала бы ему временный профиль.
- Короткая задача от имени системы ждётся столько, сколько ей разрешено работать (раньше — 30 секунд при двух минутах), а недождавшаяся останавливается, а не дорабатывает без программы. Сценарий очистки буфера передаётся ей файлом в защищённой папке, а не строкой в аргументах.
- Страница «Изменения» говорит, что журналу нельзя верить (подпись не сошлась или ключа нет), а не показывает «программа ещё ничего не меняла».
- Откат по журналу прежней версии снова включает задачи OneDrive и NVIDIA по маске в любой папке — там, где их отключали прежние версии.
- Журнал отката пишется раньше изменения (write-ahead): «как было» сначала ложится на диск, и только потом меняются реестр, службы, задачи, переменные среды, автозагрузка, компоненты производителя и чужие профили. Раньше запись шла после изменения и ложилась на диск пачками — обрыв процесса посередине оставлял изменение без пути назад. Не прошедшее изменение отзывает свою запись. После отказа журнала не меняется ничего, в том числе при прямых вызовах (монитор, чистка, датчики).
- Перед откатом проверяется форма каждой записи журнала: подпись говорит, что запись не меняли, но не то, что она допустима. Пути реестра — только в его ветках, имена служб, задач и переменных — допустимого вида, GUID аудита — свой; запись не по форме не исполняется. После возврата службы сверяется её тип запуска; что служба сейчас не запустилась или задачи больше нет — так и сказано.
- Файлы данных (журнал отката, состояние) заменяются одним действием системы, без промежутка, когда старого файла уже нет, а новый ещё не на месте.
- Очистка папок больше не заходит внутрь ссылок (junction, символические ссылки): раньше ссылка во временной папке на другую папку привела бы к удалению её содержимого. Папка, которая сама оказалась ссылкой, корень диска и системные папки не очищаются вовсе; что не удалилось (занято), называется.
- Изменения в обход журнала закрыты: разрешение датчиков (камера, микрофон) теперь пишется через журнал, а имя датчика проверяется; точка восстановления возвращает частоту создания точек, которую раньше меняла навсегда; чистка истории активности запускает остановленные службы обратно.
- Задачи от имени системы запускают schtasks и PowerShell напрямую, без cmd.exe; в постоянные команды через cmd не пропускаются % и переводы строк.
- Больше не молчат о неудачах: удаление приложения для новых пользователей, очистка истории сетей, стирание рекламного идентификатора (раньше «уже стёрт» писалось и при отказе в доступе), возврат веток реестра из резервной копии (неудача могла выглядеть успехом по коду прошлого файла), стирание локальной копии «рентгена» и запуск CDPSvc после снятия запрета номера устройства.
- Откат больше не молчит о неудачах: невключённая задача, неудалённая переменная, невосстановленный файл настроек или неснятый параметр называются и считаются ошибкой.
- Очистка неотправленной телеметрии удаляет только очередь и трассировки. Раньше она цепляла и настройки диагностики, а на папке могла зависнуть.
- «Обзор» при первом запуске показывал пустые разделы до ручной проверки.
- После сворачивания и разворачивания боковой панели в списке настроек оставалась горизонтальная прокрутка; пункты панели дёргались во время анимации; вокруг кнопки меню оставалась рамка после щелчка.
- Резервная копия реестра засчитывает ветку, только если reg.exe закончил без ошибки и файл начинается с заголовка выгрузки. Недописанный файл удаляется, у каждой невыгруженной ветки названа причина. Раньше хватало того, что файл появился.
- Правило брандмауэра с адресами телеметрии заменяется по шагам: новое создаётся рядом со старым и проверяется, старое убирается только потом. Раньше старое удалялось первым, и при неудаче не оставалось никакого.
- hosts переписывается через копию рядом и подменяется одним действием: обрыв посередине больше не оставляет его недописанным вместе со строками, вписанными вручную. Неудача — ошибка, и устаревший блок не дополняется вторым.
- Удаление стража, слежения и уведомлений отличает «задачи нет» от «задача не удалилась». Короткая задача от имени системы, которая не удалилась, называется.
- Включение и отключение задачи планировщика сверяется по её состоянию.
- Страж пишет «исправлено» по числу изменений, которые действительно прошли, а не по числу перебранных настроек.
- Откат прямо говорит, если вернулось не всё, и показывает число ошибок. Компоненты производителя, которые не вернулись по списку прежней версии, остаются в нём для второй попытки.
- Откат убирает ключи реестра, которых не было до программы, если в них не осталось значений. Раньше пустые ключи политик оставались.
- Выключена ли задача планировщика, программа узнаёт по её настройке, а не по состоянию. Выключенная задача, которая ещё доделывала свой запуск, выглядела включённой: проверка показывала её несделанной, а применение отключало снова.
- Задачи по маске (OneDrive, NVIDIA) отключаются тем же путём, что и остальные: со сверкой и от имени системы, если администратору отказано. Неудача — ошибка, а не «[-]».
- Запись в реестр сверяется и по виду значения, а не только по данным.
- Ограничение времени на выгрузку резервной копии действительно работает: раньше зависший reg.exe держал бы применение бесконечно.
- Журнал отката, который в этот миг подменял другой запуск или держал открытым антивирус, раньше читался пустым: откат мог сказать «возвращать нечего», а следующая запись — затереть всю историю «как было». Теперь журнал читается и пишется под одним замком, чтение не мешает подмене файла, а журнал, который сейчас не прочитался, — ошибка, и дописывать в него нельзя. Подмена файла данных, которую держит антивирус, ждёт, а не останавливает применение.
- Проверка резервной копии ловит и оборванную выгрузку: файл должен быть целым UTF-16, начинаться с выгруженной ветки и заканчиваться законченной записью.
- Если команда записи в реестр сообщила об ошибке, а значение всё-таки легло, запись «как было» больше не отзывается: изменение было. Легло что-то третье или прочитать не вышло — запись остаётся для отката, и это ошибка.
- Правило брандмауэра сверяется по полному набору адресов, а не по их числу; один и тот же адрес в разной записи (IPv6) считается одним.
- hosts при обновлении блока переписывается целиком за одну подмену. Раньше старый блок убирался отдельно, а новый дописывался следом, и между ними блока не было вовсе.
- Откат службы возвращает и сверяет отложенный запуск; не вернулся — ошибка, а не полный успех.
- «Ключа нет» и «нет доступа» в реестре различаются по ответу самого реестра: о ключе, который не прочитался, программа не записывает «значения не было».
- Куст профиля, оставшийся подключённым после оборванного запуска, отключается в начале каждого применения и отката. Раньше — только если в журнале были записи о профилях, а оборванный запуск мог не успеть их записать.

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
- The undo journal is signed (HMAC-SHA256). The key lives in `C:\ProgramData\Win11Privacy` and only SYSTEM and administrators can read it. A journal edited or extended by anyone else is not applied and is set aside. An unsigned journal from an older version in a portable folder restores only entries about the program's own settings; tasks matched by a name mask (OneDrive, NVIDIA) only from their own scheduler folder, not any task with a matching name. An untrusted journal (damaged, signature mismatch, or no key to check it) no longer triggers the old default rollback of services and tasks either. The key is created only when the journal is written: a check without the key does not make a new one, it sets the journal aside intact. A full rollback no longer deletes the set-aside journal along with the other data, and no longer says "settings restored" when nothing was restored from the journal.
- Vendor services and tasks that the program switches off go into the same signed journal and come back exactly as they were. The list kept by older versions (`oem-disabled.json`) is checked on rollback against what the program itself recognises as vendor components.
- PowerShell is started only by its full system path — by the window, in `--audit` and `--silent` modes and by the guard's tasks. Before, the fallback was a bare "powershell.exe", a name Windows also looks for in the program's own folder.
- Portable mode: the guard and the monitors — tasks that start by themselves with administrator rights — are installed only if the program's folder cannot be swapped (for example under Program Files on an NTFS drive). The data folder is then locked down like `ProgramData\Win11Privacy`. Before, the portable folder was trusted without any check.
- If the protected folder for the engine cannot be prepared, the engine no longer runs from the user's temp folder, where any program could swap it.
- Data folders of older versions are checked at any depth, not only at the top: foreign files, links and anything open to writing by someone else's explicit right go to quarantine.
- Short-lived scheduled tasks (device ID, closed tasks) get a random name and are checked before they start: the right command, under the right account.
- The rollback restores registry values with the same kind and the same data. The journal now records the kind of the previous value (before, the kind of the new one, so the string "1" came back as a number), and expandable strings keep their unexpanded %variables%. A value of a kind the rollback could not restore is not changed at all.
- Every restore is verified: a registry value is read back (kind and data), and so is an environment variable. An entry counts as restored only after the check; before, a successful command was taken as success.
- The rollback removes from the journal only what it finished with: entries written meanwhile by the guard or a second window stay. The guard and watch tasks are removed before settings are restored, and a running one is stopped first: a guard run in the middle of a rollback used to put settings back.
- Write-ahead journaling now covers every change, including the audit policy for the monitor (before, it was recorded after auditpol).
- Other users' profiles: the journal records the kind of the previous value, writes are verified, a hive is mounted once per profile, and a hive left mounted by an interrupted run is unloaded by the next one — otherwise Windows would give that user a temporary profile.
- Data files (profile.json and others) are read only from a folder that can be trusted, just as they are written.
- The security model and rollback guarantees are described in docs/security-model.md.
- The self-test no longer deletes the whole `Software\Win11Privacy` registry branch: it removes only its own probe value and only the keys that did not exist before it — and only when they are empty.
- "Delete program data" deletes only the files the program puts there itself (a list of names and strict patterns); other files in the same folder are neither shown nor deleted. `-DataRoot` is accepted only for a `Win11Privacy-Data` folder given by its full path: pointed by mistake at, say, Documents, it would have let the program write there and delete files with matching names.
- Restoring a backup no longer imports, as administrator, whatever another program added to it. The backup sits on the desktop, where any program of the user can write; its files are now signed when it is made, and on restore they are copied into the protected folder, checked there and imported from there. A changed, added or unsigned file is not imported; a backup made by an older version can only be opened by hand.
- The elevated engine no longer loads PowerShell modules from the user's Documents folder. That folder came first in the module path and any program can write to it without elevation, while the scheduler, firewall and DNS commands are loaded from that path: a planted module would have run as administrator — from the guard at every sign-in, without a UAC prompt. The first engine command now reduces the path to the system folders, and the Windows, ProgramData, Program Files and profile paths come from the system itself, not from environment variables. The window starts the engine with the same values.
- The undo-journal lock is a file in the protected folder, not a shared mutex that any process without privileges could create and hold: while it held it, neither apply nor rollback worked.
- The user's folders are no longer cleaned or edited by path as administrator. The profile (`%TEMP%`, caches, VS Code `settings.json`) is handled by a short task that runs as the user, without elevation; in the shared Windows folders (`C:\Windows\Temp`, the error-report queue) only objects owned by the system or administrators are deleted — a planted link is skipped. Before, a link swapped in between the check and the deletion could redirect an administrator's delete elsewhere.
- Rolling back VS Code and Firefox settings returns only what the program changed: the journal holds one key (how it was), not a copy of the whole file. Before, the rollback copied the snapshot of the first apply over `settings.json`, and everything the user changed afterwards was lost. A file the program created that ends up empty is deleted; Firefox policies are no longer cut by depth.
- The backup folder on the desktop gets a random suffix and is checked for a link; the self-test probe folder likewise, and its removal does not follow links.
- Profile settings also reach the user who is signed in to Windows when that user typed the administrator's password and the engine runs as that administrator. The guard and the watch tasks stay on the administrator account (only it has elevation) — the program says so when they are enabled.
- The silent mode `--silent --profile` checks module and item names from the file and refuses a file with foreign content instead of gluing it into the engine command line.
- A new data folder is created with the protected rights at once, not in two steps.
- Release: the build and tests run with read-only access to the repository, while publishing, the winget secret and build provenance are in a separate job for tags only; third-party actions are pinned by commit hash; the release files are checked against their checksums and get a build attestation.
- The quarantine of an older data folder no longer goes to the predictable «...untrusted-<time>» folder: a standard user could create it in advance as a link, and the administrator's move of foreign files would follow it. The quarantine folder is now new every time, with a random name, and checked not to be a link.
- Before starting, the engine and the window remove the environment variables through which .NET and the shell load foreign code into a process (the CLR profiler, startup hooks, the compatibility layer), so none of the processes the engine starts as administrator can be hijacked through them.
- The monitor's copy of the audit policy is written to the program's protected folder, not to the user's temp folder; the result of a task run as the user is checked by the file owner.
- winget: the package description and README say to install with `--scope machine`, so the self-elevating exe lies in a folder only administrators can write to, not in the user's profile (winget does not let a portable package choose its scope itself).

**Fixes**
- The leak test is honest about its limits: it checks whether known data-collection servers answer on TCP 443; it does not watch traffic. "No server answered" is no longer presented as "telemetry will not get through"; the window says what the test cannot see (new addresses, other ports, UDP/QUIC, third-party services), and the engine's answer keeps endpoint reachability (`endpointReachability`) apart from observed telemetry (`telemetryObserved` — not measured).
- Apply and rollback end with an honest exit code: 0 — everything went through, 2 — finished, but with errors. Before, apply always answered zero, and so did rollback, so the silent mode could not report a failed profile. A bad profile file gives code 4.
- A refusal while disabling a service is no longer called "unavailable". "No such service" and "Windows refused" are different: the second counts as "Windows does not allow" (access denied) or as an error, and it reaches the totals.
- "Already configured" takes the value kind into account: the string "1" in place of the number 1 is no longer treated as applied — neither on apply nor on check.
- The telemetry address block no longer closes by IP the names that live on shared endpoints (shared Azure Storage, e-msedge edges, the Office front door): closing such an address would cut other services off. They stay blocked by name in hosts. `licensing.mp.microsoft.com` is removed from hosts — the app licences of the Store go through the shared front door of that name.
- Temporary-file cleanup is off by default and not part of the ready-made sets; the recycle bin is emptied only after a separate question, and files younger than a day in the temp folder are left alone. The label of the Defender module says it plainly: cloud protection (MAPS) is switched off, and protection against new threats gets noticeably weaker.
- The winget texts no longer promise that every change can be reverted (what is deleted cannot be brought back), and the "validated with winget validate" box is ticked only if the validation really ran.
- Firefox: an existing `policies.json` that does not parse (for example, one with a comment) is no longer overwritten — its policies, corporate ones included, used to be lost.
- Defender: with Tamper Protection on, the program says plainly that Windows does not give up cloud protection and sample submission even to a policy, and that the settings take effect only after turning it off by hand.
- Device ID: wiping reports its result honestly. The device identity credentials count as removed only if they are really gone from the vault after `cmdkey` (before, merely starting the task counted as success). Every registry entry gets its own outcome — removed, not there, or refused by Windows; an entry closed to reading no longer counts as "not there". Places that could not be read — a whole store or a closed key inside one — are no longer reported as wiped. The DoSvc service is stopped during the wipe too; if any of the services does not stop, nothing is wiped and the services are put back as they were. The wipe counts as a success only if the services that were running before are running again and the Connected Devices Platform cache is really empty. Copies of the ID are also searched for in the profiles of other users who are signed in right now; for everyone else the program says plainly that it did not check them. The ID tile takes the number from any store found, not only from the current user's profile.
- Network watch: whether it is on is now read from the audit policy as a number, not from words — on a German or French Windows it always looked off. A failed `auditpol` is no longer reported as success, and the rollback restores the audit policy that was there before the program instead of simply turning it off.
- Whether an address is public is now decided by IANA ranges, not by how the string starts: carrier-grade NAT (100.64.0.0/10), test and reserved networks, IPv6 multicast and IPv4 inside IPv6 no longer count as "public" in network monitoring and the leak test.
- Clearing the unsent telemetry no longer changes the owner and permissions of the system folder `C:\ProgramData\Microsoft\Diagnosis`. Before, it took over the whole folder (`takeown /R`) and opened everything inside to administrators (`icacls /T`), and it stayed that way. Now whatever cannot be deleted right away is deleted by a short task running as SYSTEM. Its outcome is not taken from its exit code: the task writes how many files it found, deleted and left, which ones it could not delete and why, and the program says it as it is — cleared, partly cleared or failed.
- Turning network watch off restores the audit policy that was there before the program (for example "success only") instead of setting "no auditing" over it. It is not turned on if the current policy cannot be read (there would be nothing to restore later), and if the undo journal fails to write, the policy is put back at once.
- If the Security log cannot be read, the Monitor page says so instead of showing an empty "nobody sent anything" list. Network watch then does not skip the unread minutes; it tries again.
- Registry writes are verified: after writing, the value is read back and compared with the intended one. If it reads differently, that is an error rather than "[+]", but the change still goes into the undo journal. A failure to write the journal entry is no longer swallowed.
- If another user's NTUSER.DAT stays loaded after configuring it, the program says so and asks for a restart before that user signs in. Before, this went unnoticed, and Windows would have given that user a temporary profile.
- A short task running as SYSTEM is waited for as long as it is allowed to run (before: 30 seconds against two minutes), and one that is not done in time is stopped rather than left to finish without the program. The buffer cleanup script is handed to it as a file in the protected folder, not as a long argument string.
- The Changes page says the journal cannot be trusted (signature mismatch or no key) instead of showing "the program has not changed anything yet".
- Rollback from an older version's journal again re-enables OneDrive and NVIDIA mask tasks in any folder — where older versions switched them off.
- The undo journal is written before the change (write-ahead): "how it was" reaches the disk first, and only then are the registry, services, tasks, environment variables, startup entries, vendor components and other users' profiles changed. Before, the entry was written after the change and flushed in batches — a process crash in between left the change with no way back. A change that does not go through withdraws its entry. Once the journal has failed, nothing is changed, including direct calls (monitor, cleanup, sensors).
- Each journal entry's shape is checked before rollback: the signature says the entry was not altered, not that it is allowed. Registry paths only inside the registry hives, service, task and variable names of a valid form, the audit GUID our own; an entry that does not fit is not executed. After a service is restored its startup type is verified; if it did not start right away or the task no longer exists, the log says so.
- Data files (undo journal, state) are replaced in one system operation, with no moment where the old file is gone and the new one is not yet in place.
- Folder cleanup no longer follows links (junctions, symbolic links): before, a link inside a temp folder pointing elsewhere would have had its target's contents deleted. A folder that is itself a link, a drive root and system folders are not cleaned at all; whatever could not be deleted (in use) is named.
- Changes that bypassed the journal are closed: sensor permissions (camera, microphone) now go through the journal and the sensor name is validated; the restore point puts back the restore-point frequency it used to change for good; the activity-history cleanup restarts the services it stopped.
- Tasks running as SYSTEM start schtasks and PowerShell directly, without cmd.exe; constant commands that still go through cmd may not contain % or line breaks.
- No longer silent about failures: removing an app for new users, clearing the network history, erasing the advertising ID (before, "already erased" was also said on access denied), restoring registry branches from a backup (a failure could look like success through the previous file's exit code), wiping the local "X-ray" copy and starting CDPSvc after lifting the device ID block.
- Rollback no longer stays silent about failures: a task that did not come back on, a variable that was not removed, a settings file that was not restored or a value that was not removed is named and counted as an error.
- Clearing the unsent telemetry removes only the queue and the traces. Before, it also took the diagnostics settings and could hang on a folder.
- On first start the Overview showed empty sections until a manual check.
- After collapsing and expanding the sidebar the settings list kept a horizontal scrollbar; sidebar items jerked during the animation; a focus frame stayed around the menu button after a click.
- The registry backup counts a branch only if reg.exe exits without an error and the file starts with the export header. A partial file is deleted, and every branch that was not exported is named with the reason. Before, it was enough for the file to appear.
- The firewall rule with telemetry addresses is replaced in stages: the new rule is created next to the old one and checked, and only then is the old one removed. Before, the old rule went first, and a failure left none.
- hosts is rewritten through a copy next to it and swapped in one operation: an interruption no longer leaves it half-written along with lines added by hand. A failure is an error, and a stale block is not topped up with a second one.
- Removing the guard, watches and notifications tells "there is no task" from "the task was not removed". A short-lived SYSTEM task that could not be removed is named.
- Enabling and disabling a scheduled task is verified by its state.
- The guard reports "fixed" by the number of changes that really went through, not by the number of settings it went over.
- The rollback says plainly when not everything came back and shows the number of errors. Vendor components that did not come back from an older version's list stay in it for a retry.
- The rollback removes registry keys that did not exist before the program if no values are left in them. Before, empty policy keys stayed behind.
- Whether a scheduled task is disabled is read from its settings, not its state. A disabled task still finishing a run looked enabled: the check reported it as not done, and applying disabled it again.
- Mask-matched tasks (OneDrive, NVIDIA) are disabled the same way as the others: verified, and as SYSTEM if administrators are refused. A failure is an error, not "[-]".
- Registry writes are verified by the kind of the value too, not only by its data.
- The time limit on exporting the registry backup really works: before, a hung reg.exe would have held the apply forever.
- An undo journal that another run was replacing at that moment, or that an antivirus held open, used to read as empty: the rollback could say "nothing to restore", and the next write could overwrite the whole "how it was" history. The journal is now read and written under one lock, reading does not block a replace, and a journal that cannot be read right now is an error that nothing is appended to. A data-file replace held up by an antivirus waits instead of stopping the apply.
- The backup check also catches a cut-off export: the file must be whole UTF-16, start with the exported branch and end with a finished record.
- When a registry write command reports an error but the value did land, the "how it was" record is no longer withdrawn: the change happened. If something else landed, or the value cannot be read, the record stays for the rollback and it is an error.
- The firewall rule is verified by the full set of addresses, not by their number; the same address written differently (IPv6) counts once.
- When a hosts block is updated, the whole file is rewritten in one swap. Before, the old block was removed separately and the new one appended afterwards, with no block at all in between.
- Rolling back a service restores and verifies its delayed start; if it does not come back, that is an error, not a full success.
- "No such key" and "access denied" in the registry are told apart by the registry's own answer: for a key that could not be read the program does not record "the value did not exist".
- A profile hive left mounted by an interrupted run is unloaded at the start of every apply and rollback. Before, only when the journal had profile entries, and an interrupted run may not have written them yet.

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
