# Security model and rollback guarantees

**English** · [Русский](#модель-безопасности-и-гарантии-отката)

This page describes what the engine (`Win11-Privacy-Engine.ps1`, built from
`engine/`) actually guarantees, how each guarantee is checked, and where the
limits are. It is kept in step with the code: if a statement here stops being
true, that is a bug.

## Trust boundaries

| Who | Runs as | Trusted with |
|---|---|---|
| The window (`Win11Privacy.exe`) | Administrator (the manifest requires it) | Everything the user asks for |
| The engine started by the window | Administrator, from `C:\ProgramData\Win11Privacy\bin` | Same as the window |
| Guard, sensor watch, network watch, notifications | Scheduled tasks, administrator/SYSTEM, without the user | Only data that nobody but SYSTEM and administrators could have written |
| Any other program of the same user | Medium integrity, no elevation | Nothing. It must not be able to influence what the elevated engine does |

**Data folder.** `C:\ProgramData\Win11Privacy` is created with an explicit ACL:
SYSTEM and Administrators — full control, Users — read. A folder created
earlier by someone else is set aside (`*.untrusted-<time>`), foreign files and
links inside an older folder are moved to quarantine at any depth. The engine
copy that scheduled tasks run lives there and is compared with the embedded one
by SHA-256 before it is replaced.

**Portable mode** (`-DataRoot` next to the exe). The window trusts that folder
the way it trusts its own exe: whoever can write there could replace the exe
too. Scheduled tasks do not: they use a portable folder only if it is on an NTFS
/ReFS volume, no folder above it can be renamed or re-permissioned by
non-administrators (`Test-DirChainSecure`), and the folder itself is locked down
like ProgramData. Otherwise the task exits without doing anything.

**Reading data files.** `Load-Json` and `Save-Json` both refuse a data folder
that fails the checks above, so an elevated run never consumes a planted
`profile.json`, journal or state file.

## Undo journal (`changes.json`)

* **Signed.** Schema 3, HMAC-SHA256 over the items. The 32-byte key is created
  with `RandomNumberGenerator` and stored in `C:\ProgramData\Win11Privacy\journal.key`
  with an admin-only ACL; it is created only when the journal is written. A journal
  that is damaged, has a wrong signature or cannot be checked (no key) is set
  aside intact and nothing from it is executed — and no "default rollback" is
  done in its place.
* **Shape-checked.** A valid signature says the entry was not altered, not that
  it is allowed. Before an entry is executed: registry paths must be in
  HKLM/HKCU/HKU, value kinds known, service/task/variable names of a valid form,
  hive files `X:\...\NTUSER.DAT` without quotes, the audit GUID our own.
* **Locked.** Every write *and every read* takes the machine-wide mutex
  `Global\Win11Privacy-Journal`: ReplaceFile has a moment when the file is not
  there under its name, and a reader without the lock saw "no journal". Data
  files are opened with `FILE_SHARE_DELETE`, so a reader never blocks another
  process's replace; a replace blocked by someone else (an antivirus) waits and
  retries. A journal that cannot be read right now is *unreadable* — never
  "empty" — and nothing is appended to it (that would overwrite the history).
* **Atomic.** The file is written next to the old one and swapped in with one
  system call (`File.Replace` / ReplaceFile); there is no moment without a journal.
* **Older journals.** An unsigned journal of an older version in a portable
  folder restores only entries about the program's own settings.

## Write-ahead logging

Every reversible change follows the same sequence:

1. read the current state — for registry values the **kind and raw data**
   (`Get-RegRaw`: no `%VAR%` expansion);
2. append "how it was" to the journal and write it to disk (`Write-AheadEntry`);
   if that fails, the change is not made, and no further change is made in this
   run (`$script:JournalFailed`);
3. make the change;
4. read the result back and compare it with what was intended;
5. if the change did not happen, withdraw the entry (`Undo-AheadEntry`, written
   to disk at once). If it happened but reads differently, the entry stays —
   the value is no longer the original one.

This covers registry values (`Set-Reg`), other users' hives (`Apply-ProfilesHives`:
the whole plan goes to disk before the first write), services, scheduled tasks,
environment variables, startup entries, vendor components and the audit policy
(`Set-MonitorEnabled`). A static test checks that only `Write-AheadEntry` and
`Apply-ProfilesHives` put entries into the journal queue.

A value of a kind the rollback could not restore (`REG_NONE`, `REG_LINK`…) or a
value that could not be read in full is **not changed** at all. Keys are opened
through the registry API: "no such key" (a null handle) and "access denied" (an
exception) are different answers, and an unreadable state is never recorded as
"did not exist".

If the write command throws, the outcome is decided by what is there now, not
by the error: the original value — nothing changed, the record is withdrawn;
the target value — the change happened, the record stays; anything else or
unreadable — the record stays and it is an error.

## Rollback

* Each entry is restored from its earliest record ("before the program").
* A registry key the program had to create is recorded (the topmost created
  one) and removed after the rollback if no value is left anywhere under it; a
  key someone else has written into stays.
* Services come back with their start type **and delayed start**, both verified;
  a delayed start that did not exist before is removed if it appeared.
* Registry values come back with **the same kind and the same data**, including
  `REG_EXPAND_SZ` with unexpanded `%VAR%`, `REG_BINARY` and `REG_MULTI_SZ` from
  JSON. A value that did not exist is removed; an already removed one counts as
  restored (rollback is idempotent).
* **Every restore is verified** by reading back (`Restore-RegValue`; services:
  start type; tasks: state; variables: value). An entry counts as restored only
  after the check.
* Entries that could not be restored **stay in the journal** for a retry, and the
  run says which and why. The journal is re-read under the lock and only the
  entries this run finished with are removed: entries written meanwhile by
  another run (guard, a second window) are kept.
* Other users' profiles are restored one hive mount per profile. A hive that is
  in use (signed-in user loaded elsewhere, file locked) fails honestly and its
  entries stay. A signed-in user's hive `HKU\<SID>` is used live.
* The guard and watch tasks are removed **before** the journal is restored, and
  a running task is stopped first: a guard run in the middle of a rollback used
  to put settings back.

## Crash consistency

| Interrupted… | Result | Evidence |
|---|---|---|
| before the journal write | nothing changed | unit test: journal failure blocks the change |
| during the journal write | old journal intact (atomic replace) | static test + `Save-Json` code |
| after the journal write, before/while changing | entry on disk, rollback restores (or finds the value already original) | unit test: entry is on disk at the moment of `New-ItemProperty` |
| after the change, before verification | entry stays; rollback restores | by construction (entry is never removed on this path) |
| during rollback | entries are removed only at the end, under the lock; a re-run restores again and verifies | unit test: only finished entries are removed |
| while another user's hive is mounted | the next run unloads hives `W11P_<pid>_*` whose process is gone | unit test + VM test (`guest-hives.ps1`) |
| while `hosts` is being rewritten | `hosts` is replaced atomically; the old file stays | unit test (read-only `hosts`: file unchanged, no temp file left) |
| while another process rewrites the journal | reads wait for the lock and see the whole journal; nothing is set aside | test with a second writer process (100 writes while reading and cleaning up) |

Crash tests above that say "unit test" kill a real child PowerShell process
(`[Environment]::Exit`) with the engine's own functions at the boundary, then
recover from what is on disk; registry changes there go to `HKCU:\Software\W11P*`
test keys, and `auditpol` is a stub. Hive and firewall cases also run on a real
Windows 11 VM (`guest-hives.ps1`, `guest-fw.ps1`).

Not proven: power loss during NTFS metadata updates beyond what ReplaceFile
guarantees; kill during `reg.exe load/unload` itself.

## Backups

* The registry backup on the desktop is made right before the first real change
  of a manual apply, never by the guard.
* A branch counts as saved only if `reg.exe export` exits with 0 **and** the file
  starts with `Windows Registry Editor Version 5.00`. A partial file is deleted;
  every branch that was not exported is listed with the reason.
* The restore point temporarily sets `SystemRestorePointCreationFrequency` to 0
  and puts the previous value back.
* **Restoring a backup.** The backup folder is on the desktop, where any program
  of the user can write, while the import runs as administrator. Every `.reg`
  file is therefore signed when the backup is made (`backup-sig.json`, HMAC-SHA256
  with the journal key, bound to the backup folder name and the file name). On
  restore each file is copied into the protected folder, its signature is checked
  on that copy, and the copy is imported — the file cannot be swapped between the
  check and the import. A changed, added or unsigned file is not imported; a
  backup made by an older version (no signatures) can only be imported by hand.
  Importing a backup is the fallback path and is not written to the undo journal.

## Firewall and hosts

* The telemetry address rule is replaced in stages: the new rule is created next
  to the old one, checked (enabled, block, outbound, and exactly the intended set
  of addresses — compared as normalized sets, not counts), and only then is the
  old one removed. A failed creation or check keeps the old rule.
* `hosts` is rewritten as a whole in one swap, both when a block is removed and
  when it is added or updated: the copy is written next to it, read back and
  compared line by line, then swapped in (encoding, ACL and attributes kept).
* `hosts` blocks are marked; only the program's own lines inside its markers are
  removed. A block with a deleted end marker stops at the first foreign line.

## Native commands and scheduled tasks

* PowerShell is started only by its full system path. Short-lived SYSTEM tasks get
  a random name, are checked (command and SID) before they start, run `schtasks`
  and PowerShell directly without `cmd.exe`; constant `cmd` lines may not contain
  `%` or line breaks. A task that does not finish in time is stopped and removed;
  one that could not be removed is reported.
* `reg.exe export/import` is started by its full path, without `cmd.exe`.
  `reg.exe load/unload`, `auditpol.exe` and `ipconfig.exe` are called by name:
  PowerShell resolves them through `PATH`, where `System32` comes first and the
  system part cannot be changed without administrator rights.
* Whether a task is disabled is read from its settings (`Settings.Enabled`), not
  from `State`: Task Scheduler reports `Disabled` only while no instance is
  running.

## Supported environment

Windows 11 (Home, Pro, Enterprise, Education), Windows PowerShell 5.1 in
FullLanguage mode, 64-bit. In ConstrainedLanguage mode (WDAC/AppLocker) the
engine stops at once with an explicit message. Edition-specific policies that
Windows refuses are reported as "Windows does not allow" (`[-]`), not as success
and not as an error of the program. Localized Windows: audit policy is read by
number and CSV columns by position (checked on a Russian VM).

## Known limitations

* Read-only pages (dossier, timeline, some counters) treat an unreadable source
  as "nothing found" in a few places. They change nothing.
* `hosts` encoding: the file is read and written in the system ANSI code page;
  lines in other encodings round-trip byte for byte only if the code page maps
  them.
* Windows Defender may flag a `hosts` file that blocks Microsoft domains
  (`SettingsModifier:Win32/HostsFileHijack`); that is Defender's decision.
* A rollback cannot bring back apps that were removed; they can be installed
  from the Microsoft Store.
* Windows itself may re-register a scheduled task at boot (seen with
  `PcaPatchDbTask`: its task file was rewritten at boot time and the task was
  enabled again). The check reports it as not done and the guard disables it again.
* No replay protection in portable mode: whoever can write the portable folder
  can put back an *older* journal signed by this machine. It contains only
  genuine records of the program, so it cannot inject foreign values — at most
  a rollback returns settings to an earlier "before" state.
* The journal mutex lives in the global namespace; another program could create
  it first and hold it. The engine then refuses to change anything (a denial of
  service, not a bypass).

## How it is tested

* `tests/engine-tests.ps1` — read-only behaviour tests with stubs for every
  dangerous operation (firewall, auditpol, scheduler, reg load); registry writes
  only under `HKCU:\Software\W11P*` test keys, removed afterwards. Run in CI.
* `tests/engine.Tests.ps1` — Pester tests for the six review areas (works with
  the in-box Pester 3.4 and Pester 5; run in CI).
* `tests/roundtrip.ps1` — apply, verify and revert for real, then compare every
  value; CI only, on a disposable runner.
* VM tests (not in the repository, need a disposable Windows 11): data folder
  trust, monitor/audit policy, one-shot SYSTEM tasks, device ID, other users'
  hives (`guest-hives.ps1`: kind preservation, stale mount, locked hive,
  signed-in user).
* PSScriptAnalyzer is run on the engine parts during audits; see the audit
  report for the remaining, justified warnings.

---

# Модель безопасности и гарантии отката

[English](#security-model-and-rollback-guarantees) · **Русский**

Здесь сказано, что движок (`Win11-Privacy-Engine.ps1`, собирается из `engine/`)
действительно гарантирует, чем это проверено и где пределы. Если что-то из этого
перестанет быть правдой — это ошибка.

## Границы доверия

| Кто | С какими правами | Чему можно верить |
|---|---|---|
| Окно (`Win11Privacy.exe`) | администратор (так требует манифест) | всему, что просит человек |
| Движок, запущенный окном | администратор, из `C:\ProgramData\Win11Privacy\bin` | тому же, что и окно |
| Страж, слежение, уведомления | задачи планировщика, администратор/SYSTEM, без человека | только данным, которые мог записать лишь SYSTEM или администратор |
| Любая другая программа того же пользователя | обычные права | ничему: она не должна влиять на то, что делает движок с правами администратора |

**Папка данных.** `C:\ProgramData\Win11Privacy` создаётся с явными правами:
SYSTEM и администраторы — полный доступ, пользователи — чтение. Папка, заведённая
кем-то другим, откладывается (`*.untrusted-<время>`), чужие файлы и ссылки в
прежней папке уходят в карантин на любой глубине. Копия движка для задач лежит
там же и перед заменой сверяется со встроенной по SHA-256.

**Переносимый режим** (`-DataRoot` рядом с exe). Окно верит этой папке так же,
как своему exe: кто может писать туда, может подменить и exe. Задачи — нет: они
работают с переносимой папкой, только если она на томе NTFS/ReFS, ни одну папку
выше неё нельзя переименовать или перенастроить без прав администратора
(`Test-DirChainSecure`), а сама она закрыта так же, как ProgramData. Иначе задача
выходит, ничего не делая.

**Чтение файлов данных.** `Load-Json` и `Save-Json` одинаково отказываются от
папки, не прошедшей эти проверки: движок с правами администратора не прочитает
подложенный `profile.json`, журнал или файл состояния.

## Журнал отката (`changes.json`)

* **Подписан.** Схема 3, HMAC-SHA256 по записям. Ключ — 32 байта из
  `RandomNumberGenerator`, лежит в `C:\ProgramData\Win11Privacy\journal.key` с
  правами только для администраторов и заводится только при записи журнала.
  Повреждённый журнал, журнал с несошедшейся подписью или без ключа для проверки
  откладывается целым, и из него не исполняется ничего — и «откат по умолчанию»
  вместо него тоже не делается.
* **Проверка формы.** Подпись говорит, что запись не меняли, но не то, что она
  допустима. Перед исполнением: пути реестра — только в HKLM/HKCU/HKU, вид
  значения — известный, имена служб, задач и переменных — допустимые, файл куста
  — `X:\...\NTUSER.DAT` без кавычек, GUID аудита — наш.
* **Под замком.** Каждая запись *и каждое чтение* берут общесистемный мьютекс
  `Global\Win11Privacy-Journal`: у ReplaceFile есть миг, когда файла под этим
  именем нет, и чтение без замка видело «журнала нет». Файлы данных
  открываются с `FILE_SHARE_DELETE`, поэтому чтение не мешает подмене файла
  другим процессом; подмена, которой мешает кто-то другой (антивирус), ждёт и
  пробует снова. Журнал, который сейчас не прочитался, — *не читается*, а не
  «пуст», и дописывать в него нельзя (это затёрло бы историю).
* **Целиком или никак.** Файл пишется рядом и подменяет прежний одним действием
  системы (`File.Replace` / ReplaceFile): момента без журнала нет.
* **Журналы прежних версий.** Неподписанный журнал прежней версии в переносимой
  папке возвращает только записи о настройках самой программы.

## Журнал раньше изменения (write-ahead)

Каждое обратимое изменение идёт одним порядком:

1. прочитать, как есть сейчас, — у значений реестра **вид и данные как лежат**
   (`Get-RegRaw`, без раскрытия `%переменных%`);
2. дописать «как было» в журнал и записать его на диск (`Write-AheadEntry`); не
   записалось — изменения нет, и до конца запуска ничего не меняется
   (`$script:JournalFailed`);
3. изменить;
4. прочитать результат и сверить с задуманным;
5. изменения не случилось — запись отзывается (`Undo-AheadEntry`, на диск сразу);
   случилось, но читается другое — запись остаётся: значение уже не прежнее.

Так устроены значения реестра (`Set-Reg`), кусты других пользователей
(`Apply-ProfilesHives`: весь план — на диск до первой записи), службы, задачи
планировщика, переменные среды, автозагрузка, компоненты производителя и
политика аудита (`Set-MonitorEnabled`). Статическая проверка следит, чтобы в
очередь журнала писали только `Write-AheadEntry` и `Apply-ProfilesHives`.

Значение вида, который откат вернуть не сумеет (`REG_NONE`, `REG_LINK`…), или
значение, которое не прочиталось целиком, **не меняется вовсе**. Ключи
открываются средствами самого реестра: «ключа нет» (пустой ответ) и «нет
доступа» (исключение) — разные ответы, и непрочитанное состояние никогда не
записывается как «не было».

Если команда записи бросила исключение, исход решает то, что лежит сейчас, а
не ответ команды: прежнее значение — изменения не было, запись отзывается;
задуманное — изменение было, запись остаётся; что-то третье или не читается —
запись остаётся, и это ошибка.

## Откат

* Каждая запись возвращается по самой ранней («до программы»).
* Ключ реестра, который программе пришлось создать, запоминается (самый верхний
  из созданных) и после отката убирается, если под ним не осталось ни одного
  значения; ключ, в который записал кто-то ещё, остаётся.
* Службы возвращаются с типом запуска **и отложенным запуском**, оба сверяются;
  отложенный запуск, которого до программы не было, убирается, если появился.
* Значения реестра возвращаются **того же вида и с теми же данными**, включая
  `REG_EXPAND_SZ` с нераскрытыми `%переменными%`, `REG_BINARY` и `REG_MULTI_SZ`
  из JSON. Значение, которого не было, убирается; уже убранное — тоже успех
  (повторный откат ничего не портит).
* **Каждый возврат сверяется** чтением (`Restore-RegValue`; у служб — тип запуска,
  у задач — состояние, у переменных — значение). Запись считается вернувшейся
  только после сверки.
* Что вернуть не удалось, **остаётся в журнале** для второй попытки, и запуск
  говорит, что и почему. Журнал перечитывается под замком, и убираются только
  записи, с которыми этот запуск закончил: дописанное за это время другим
  запуском (страж, второе окно) остаётся.
* Профили других пользователей возвращаются одним подключением куста на
  профиль. Занятый куст (файл открыт, человек вошёл в систему и куст подключён
  в другом месте) — честная неудача, записи остаются. Куст вошедшего
  пользователя `HKU\<SID>` используется как есть.
* Задачи стража и слежения удаляются **до** возврата журнала, а работающая —
  сначала останавливается: страж, сработавший посреди отката, раньше ставил
  настройки обратно.

## Обрыв посередине

| Оборвалось… | Что будет | Чем проверено |
|---|---|---|
| до записи журнала | ничего не изменено | тест: отказ журнала запрещает изменение |
| во время записи журнала | прежний журнал цел (подмена одним действием) | статическая проверка и код `Save-Json` |
| после записи журнала, до или во время изменения | запись на диске, откат вернёт (или увидит, что значение и так прежнее) | тест: в момент `New-ItemProperty` запись уже на диске |
| после изменения, до сверки | запись остаётся, откат вернёт | по устройству: на этом пути запись не убирается |
| во время отката | записи убираются только в конце, под замком; повторный откат вернёт снова и сверит | тест: убираются только обработанные записи |
| пока подключён куст другого пользователя | следующий запуск отключает кусты `W11P_<pid>_*`, процесса которых больше нет | тест и проверка на VM (`guest-hives.ps1`) |
| пока переписывается `hosts` | `hosts` подменяется одним действием, прежний остаётся | тест (`hosts` только для чтения: файл прежний, временного не осталось) |
| пока другой процесс переписывает журнал | чтение ждёт замка и видит журнал целиком; ничего не откладывается | тест со вторым процессом-писателем (100 записей, пока идут чтение и уборка) |

Проверки обрыва из таблицы, где сказано «тест», по-настоящему обрывают
дочерний процесс PowerShell (`[Environment]::Exit`) с функциями самого движка
ровно на границе, а потом восстанавливаются по тому, что на диске; реестр там
— пробные ключи `HKCU:\Software\W11P*`, `auditpol` — заглушка. Случаи с кустами
и брандмауэром проверяются ещё и на настоящей Windows 11 в VM
(`guest-hives.ps1`, `guest-fw.ps1`).

Не доказано: отключение питания во время обновления метаданных NTFS сверх того,
что гарантирует ReplaceFile; обрыв внутри самих `reg.exe load/unload`.

## Резервные копии

* Копия реестра на рабочем столе делается прямо перед первым настоящим
  изменением при ручном применении и никогда — стражем.
* Ветка считается сохранённой, только если `reg.exe export` закончил с кодом 0
  **и** файл начинается с `Windows Registry Editor Version 5.00`. Недописанный
  файл удаляется; каждая невыгруженная ветка называется вместе с причиной.
* Точка восстановления на время ставит `SystemRestorePointCreationFrequency` в 0
  и возвращает прежнее значение.
* **Возврат из копии.** Папка копии лежит на рабочем столе, куда пишет любая
  программа пользователя, а импорт идёт с правами администратора. Поэтому каждый
  `.reg` подписывается при создании копии (`backup-sig.json`, HMAC-SHA256 ключом
  журнала, с привязкой к имени папки копии и имени файла). При возврате файл
  копируется в защищённую папку, подпись сверяется на этой копии, и
  импортируется она — подменить файл между сверкой и импортом нельзя.
  Изменённый, добавленный или неподписанный файл не импортируется; копию прежней
  версии (без подписей) можно импортировать только вручную. Возврат из копии —
  запасной путь, в журнал отката он не пишется.

## Брандмауэр и hosts

* Правило адресов телеметрии заменяется по шагам: новое создаётся рядом со
  старым, проверяется (включено, блокирует, исходящее и ровно задуманный набор
  адресов — сравниваются наборы в каноническом виде, а не число), и только
  потом старое убирается. Не создалось или не прошло проверку — старое остаётся.
* `hosts` переписывается целиком одной подменой — и когда блок убирается, и
  когда добавляется или обновляется: копия пишется рядом, читается обратно и
  сверяется построчно, затем подменяет файл (кодировка, права и атрибуты
  сохраняются).
* Блоки в `hosts` помечены; убираются только строки программы внутри её меток.
  Блок со стёртой закрывающей меткой заканчивается на первой чужой строке.

## Родные команды и задачи планировщика

* PowerShell запускается только по полному системному пути. Короткие задачи
  SYSTEM получают случайное имя, перед запуском сверяются (команда и SID),
  запускают `schtasks` и PowerShell напрямую, без `cmd.exe`; в постоянных строках
  для `cmd` не бывает `%` и переводов строк. Недождавшаяся задача
  останавливается и удаляется; неудалившаяся — называется.
* `reg.exe export/import` запускается по полному пути, без `cmd.exe`.
  `reg.exe load/unload`, `auditpol.exe` и `ipconfig.exe` вызываются по имени:
  PowerShell ищет их по `PATH`, где `System32` стоит первым, а системную часть
  без прав администратора не изменить.
* Выключена ли задача, читается из её настроек (`Settings.Enabled`), а не из
  `State`: планировщик показывает `Disabled`, только пока у задачи нет
  работающего экземпляра.

## Где работает

Windows 11 (Домашняя, Pro, Корпоративная, для образовательных учреждений),
Windows PowerShell 5.1 в режиме FullLanguage, 64 бита. В режиме
ConstrainedLanguage (WDAC/AppLocker) движок сразу останавливается с понятным
сообщением. Политики, которые Windows этой редакции не отдаёт, называются
«Windows не разрешает» (`[-]`) — не успехом и не ошибкой программы. Windows на
других языках: политика аудита читается числом, столбцы CSV — по положению
(проверено на русской VM).

## Известные ограничения

* Страницы только для чтения (досье, хронология, часть счётчиков) кое-где
  считают недоступный источник «ничего не найдено». Они ничего не меняют.
* Кодировка `hosts`: файл читается и пишется в системной кодировке ANSI; строки в
  других кодировках сохраняются байт в байт, только если кодовая страница их
  отображает.
* Защитник Windows может пометить `hosts`, закрывающий домены Microsoft
  (`SettingsModifier:Win32/HostsFileHijack`), — это решение Защитника.
* Удалённые приложения откат не возвращает — их можно поставить из Microsoft Store.
* Windows может сама заново зарегистрировать задачу при загрузке (так было с
  `PcaPatchDbTask`: её файл переписан во время загрузки, и задача снова
  включена). Проверка показывает её несделанной, страж отключает снова.
* Защиты от повтора в переносимом режиме нет: кто может писать в переносимую
  папку, может вернуть туда *прежний* журнал, подписанный на этом компьютере. В
  нём только настоящие записи программы, чужого значения так не подставить —
  самое большее откат вернёт настройки к более раннему «до».
* Мьютекс журнала — в общем пространстве имён; другая программа может завести
  его первой и держать. Тогда движок отказывается что-либо менять (отказ в
  работе, а не обход защиты).

## Как проверяется

* `tests/engine-tests.ps1` — проверки поведения только на чтение, с заглушками
  на каждое опасное действие (брандмауэр, auditpol, планировщик, reg load); в
  реестр пишут только пробные ключи `HKCU:\Software\W11P*`, которые потом
  убираются. Идут в CI.
* `tests/engine.Tests.ps1` — Pester-проверки шести мест из ревью (работают со
  встроенным Pester 3.4 и с Pester 5; идут в CI).
* `tests/roundtrip.ps1` — применить, проверить и откатить по-настоящему, затем
  сверить каждое значение; только в CI, на одноразовой машине.
* Проверки на VM (не в репозитории, нужна одноразовая Windows 11): доверие к
  папке данных, монитор и политика аудита, короткие задачи SYSTEM, номер
  устройства, кусты других пользователей (`guest-hives.ps1`: вид значений,
  оставшийся куст, занятый куст, вошедший пользователь).
* PSScriptAnalyzer прогоняется по частям движка при аудите; оставшиеся
  предупреждения и почему они оставлены — в отчёте аудита.
