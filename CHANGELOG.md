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

**Приватность: 282 настройки вместо 244**
- Новая вкладка «Номер устройства» (GDID) — номер, по которому Microsoft узнаёт компьютер сквозь VPN. Три действия: не передавать, сменить номер, запретить выдачу.
- Новый раздел «Облачная синхронизация и копия»: список приложений, сети Wi-Fi, язык, тема, настройки пера и ответы на вопросы о конфиденциальности больше не уходят в облако. Сюда же служба InventorySvc и сборщик «Usage and Quality Insights».
- Скрытые каналы, найденные разбором чистой Windows 11: эксперименты Защитника (около 130 настроек с сервера раз в час), телеметрия 1DS мимо службы DiagTrack (24 новых адреса в hosts), установка приложений из Магазина по команде с сайта, «исправления» от рекомендуемого устранения неполадок.
- Задачи планировщика, которые Windows не отдаёт администратору, отключаются от имени системы.

**Безопасность и надёжный откат**
- Папка данных `C:\ProgramData\Win11Privacy` закрыта на запись для всех, кроме системы и администраторов. Раньше обычный пользователь мог заранее подложить туда файл и через журнал отката или копию движка для стража получить права администратора. Подложенное откладывается в сторону.
- Копия движка, которую запускает страж, всегда лежит в защищённой папке и сверяется по SHA-256 — в переносимом режиме тоже.
- Откат возвращает службы (тип запуска, отложенный старт, работала ли), задачи планировщика и переменные среды ровно такими, какими застал. Задача, выключенная вами до программы, остаётся выключенной; корпоративные политики Chrome, Office и Visual Studio больше не удаляются целыми ветками.
- Журнал отката: ошибка записи больше не проглатывается — программа говорит о ней и останавливает изменения; перед применением журнал проверяется заранее; без замка журнал не пишется; повреждённый журнал откладывается, а не затирается.

**Исправления**
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

**Privacy: 282 settings instead of 244**
- A new Device ID tab (GDID) — the number Microsoft recognises the PC by through a VPN. Three actions: stop sending it, change it, forbid issuing a new one.
- A new Cloud sync and backup section: your app list, Wi-Fi networks, language, theme, pen settings and privacy answers no longer go to the cloud. Also the InventorySvc service and the "Usage and Quality Insights" collector.
- Hidden channels found by taking a clean Windows 11 apart: Defender experiments (about 130 settings pulled every hour), 1DS telemetry bypassing DiagTrack (24 new hosts entries), Store installs on command from the website, "mitigations" from recommended troubleshooting.
- Scheduled tasks that Windows keeps from administrators are switched off as SYSTEM.

**Security and a faithful rollback**
- The data folder `C:\ProgramData\Win11Privacy` can only be written by SYSTEM and administrators. Before, an ordinary user could plant a file there in advance and gain administrator rights through the undo journal or the guard's copy of the engine. Planted items are moved aside.
- The copy of the engine the guard runs always lives in the protected folder and is checked by SHA-256, in portable mode too.
- The rollback returns services (startup type, delayed start, whether it was running), scheduled tasks and environment variables exactly as it found them. A task you had switched off yourself stays off; company Chrome, Office and Visual Studio policies are no longer deleted as whole keys.
- Undo journal: a write error is no longer swallowed — the program reports it and stops changing anything; the journal is checked before applying; it is never written without its lock; a damaged journal is set aside instead of being overwritten.

**Fixes**
- Clearing the unsent telemetry removes only the queue and the traces. Before, it also took the diagnostics settings and could hang on a folder.
- On first start the Overview showed empty sections until a manual check.
- After collapsing and expanding the sidebar the settings list kept a horizontal scrollbar; sidebar items jerked during the animation; a focus frame stayed around the menu button after a click.
