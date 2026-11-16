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

**Window → engine requests.** The window starts the engine with a constant
command line — `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy
Bypass -File "<engine in ProgramData>" -Request` — and writes the operation and
its data to the engine's standard input as one JSON object
(`{"v":1,"op":"SensorSet","args":{...}}`, printable ASCII only, everything else
as `\uXXXX`). Values that other programs of the user can control (ConsentStore
key names under HKCU, the Desktop path from HKCU shell folders, backup folder
names, process paths) never reach the command line, so a quote or a `-Switch`
inside them cannot become another engine operation (F-08: a ConsentStore key
named `...\evil" -XrayStatus "` used to run `-XrayStatus` elevated). The engine
parses the request with its own strict parser (size limit, no duplicate keys,
no unknown fields, limited nesting), takes the operation only from an
allowlist, accepts per operation only its own arguments, checks each value's
type and shape itself, and refuses the whole request (exit code 64) before
doing anything if one check fails. Command-line switches remain for the
scheduled tasks and manual runs; `-Request` refuses any other switch next to it.

**Data folder.** `C:\ProgramData\Win11Privacy` is created with an explicit ACL:
SYSTEM and Administrators — full control, Users — read. The path to it
(`C:\ProgramData`, the drive root) must not let anybody else rename or delete it,
otherwise the protected folder is not used at all (W11P-006). An object is trusted
only if it is not a reparse point, its owner is SYSTEM, Administrators or
TrustedInstaller, and nobody else may write, append, delete it or its children,
change its rights, owner or attributes — counting explicit **and inherited**
entries (the earlier check saw only explicit ones), the rights a folder passes to
its children (except CREATOR OWNER), and subtracting only an explicit,
canonically ordered Deny for Everyone; rights that cannot be read mean "not
trusted". A folder created
earlier by someone else is set aside, foreign files and
links inside an older folder are moved to quarantine at any depth. The quarantine
folder is created fresh with a random, unguessable name (`*.untrusted-<time>-<rnd>`)
and checked not to be a reparse point: the old predictable `*.untrusted-<time>`
path could be pre-planted by a non-admin as a junction, and the admin move of
the foreign items would then follow it elsewhere. The engine
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
`profile.json`, journal or state file. A data file that another process holds
open is *busy*, never *missing* (T-4): on Windows PowerShell 5.1 a
`catch [DirectoryNotFoundException]` clause started to receive the
"file is used by another process" error after a few dozen checks, so
`Read-TextShared` answered "no such file". Any program of the user may open the
journal for reading (the data folder grants Users read) without sharing it, and
the elevated engine then saw "no journal": a rollback said "nothing to restore"
and the next journal write replaced the history. Error kinds are now decided
from the .NET exception itself (`Test-IoBusy`, `Test-IoMissing`), not by typed
catch filters; a busy journal is `unreadable`, and nothing is appended to it.

**Named locks (T-1).** `Global\Win11Privacy-FirefoxPolicies` (engine) and
`Global\Win11Privacy-App` (window) are kernel objects any process may create
first. A lock counts as the program's own only if its owner is SYSTEM or
Administrators and nobody else may wait on it (take and hold it), change its
permissions or owner, or delete it; the account's own SID counts only when the
code runs without elevation (an elevated engine shares that SID with every
ordinary program of the same user, which used to pass the owner check, and new
locks used to grant that SID full control). New locks are created owned by
Administrators with access for SYSTEM and Administrators only. The check runs on
the handle that is then waited on; the name is not reopened. A foreign Firefox
lock refuses the `policies.json` write at once. A foreign object on the window's
name is not "already running": the window starts anyway, because the data is
protected by the engine's own locks (journal, `policies.json`, backup work
folders), which already allow several runs at once (silent mode, the guard).
Pre-creating either name remains possible — a denial of service, not a way to
change data or gain rights.

**Environment and PowerShell modules.** An elevated process inherits the
environment of whoever started it, and the first folder in `PSModulePath` is the
user's `Documents\WindowsPowerShell\Modules`, which any program of the user can
write to. The commands the engine lives on (`Get-ScheduledTask`,
`Get-NetFirewallRule`, `Resolve-DnsName`…) are auto-loaded from that list, so a
planted module named like a system one would have run as administrator — from
the guard, at every sign-in, without a UAC prompt. The first statement after
`param(` therefore reduces `PSModulePath` to `$PSHOME\Modules`, and the engine
then rebuilds `SystemRoot`, `ProgramData`, `ProgramFiles`, `PATH` and the
profile folders from the system itself (`GetSystemDirectory`, HKLM, the
`ProfileList` key by the process SID) instead of trusting variables that
`HKCU\Environment` can override. The window starts the engine with the same
values (`EngineFile.Harden`) and a system working directory. A test runs the
engine with a planted `ScheduledTasks` module and a spoofed `ProgramData` and
checks that neither is used. The header also removes the environment variables
through which .NET or the shell load code into a process — the CLR profiler
(`COR_*`/`CORECLR_*`), .NET startup hooks (`DOTNET_STARTUP_HOOKS`,
`DOTNET_ADDITIONAL_DEPS`), and the application-compatibility layer
(`__COMPAT_LAYER`) — so that none of the children the elevated engine spawns
(`reg.exe`, `auditpol`, the task PowerShell, the de-elevated user task) can be
hijacked through an inherited variable; the window clears the same set before
launching the engine. The guard and watch tasks run as the administrator account
that installed them (whose `HKCU\Environment` a non-admin cannot write), not as a
standard logged-on user.

**Folders of the user (cleanup, VS Code).** Deleting or writing *by path* as
administrator in a folder the user's programs can write to cannot be tied to what
was checked: a path component can be replaced by a link between the check and the
action. So the engine never does that there.

* Folders of the user's profile (`%TEMP%`, `%LOCALAPPDATA%\…`, VS Code
  `settings.json`) are handled by a short task that runs **as the same user, without
  elevation** (`Invoke-AsUser`): it can do exactly what the user can already do.
  The task script is constant engine text stored in the protected folder; its
  input is JSON, its answer a small JSON file, and the engine reads only numbers
  and short strings from it. It refuses a link on the path and never follows one.
* Shared system folders (`C:\Windows\Temp`, `ProgramData\…\WER`) are cleaned by the
  engine itself, but only objects whose **owner** is SYSTEM, Administrators,
  TrustedInstaller or a system service, and it does not descend into anything
  else. A non-administrator cannot create an object owned by SYSTEM or
  Administrators (that needs the take-ownership or restore privilege), so a
  junction planted in `C:\Windows\Temp` is skipped, not deleted through.
* `%TEMP%` keeps files younger than 24 hours (running programs still use them);
  the recycle bin is emptied only after a separate question, and the cleanup module
  is off by default.

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
* **Locked.** Every write *and every read* takes a lock — the file
  `C:\ProgramData\Win11Privacy\journal.lock`, opened without sharing in the
  protected folder (re-entrant within one process; released by Windows if the
  process dies). It used to be the named mutex `Global\Win11Privacy-Journal`, which
  any process, even a service without privileges, could create and hold, stopping
  both apply and rollback (reproduced on the VM). The file has an explicit ACL set
  at creation — SYSTEM and Administrators only, *not even read* for Users (an ACL
  inherited from the folder would let any process open it for reading without
  sharing and hold it), and a lock left with wider rights is repaired when it is
  opened. Read-only display of the journal falls back to an unlocked read
  without administrator rights. ReplaceFile has a moment when the file is not
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
| while another process holds the journal open without sharing | the journal is `unreadable`, nothing is appended, the history stays (T-4) | test: a second process holds `changes.json`; read, write attempt, history compared byte for byte |
| during a restore from a backup | the progress record says which file was being imported; next run: `RecoveryRequired`; repeating the restore finishes it and verifies (T-3) | test: child process killed after `Prepared`, inside the first import, after the first file (real reg.exe); VM: real engine killed mid-import |
| during an ID wipe, after the services were stopped | the wipe record lists the services that were running; "Restore" and the next wipe start them again (GDID) | test: child process killed at each of 8 stages; VM: real wipe killed after CDPSvc stopped |

Crash tests above that say "unit test" kill a real child PowerShell process
(`[Environment]::Exit`) with the engine's own functions at the boundary, then
recover from what is on disk; registry changes there go to `HKCU:\Software\W11P*`
test keys, and `auditpol` is a stub. Hive and firewall cases also run on a real
Windows 11 VM (`guest-hives.ps1`, `guest-fw.ps1`).

Not proven: power loss during NTFS metadata updates beyond what ReplaceFile
guarantees; kill during `reg.exe load/unload` itself.

## Backups

* The registry backup is made right before the first real change of a manual
  apply, never by the guard. It is kept only in the program's protected store
  `C:\ProgramData\Win11Privacy\backups` (W11P-005): nothing is written to the
  desktop any more. It is restored from the window (*Changes → From a backup*);
  *Open backup folder* opens the store (everyone can read it, only administrators
  can change it). The first backup ever made and the 20 newest are kept, older
  ones are removed when a new one is stored.
* A branch counts as saved only if `reg.exe export` exits with 0 **and** the file
  starts with `Windows Registry Editor Version 5.00`. A partial file is deleted;
  every branch that was not exported is listed with the reason.
* The restore point temporarily sets `SystemRestorePointCreationFrequency` to 0
  and puts the previous value back.
* **Making a backup (W11P-001).** `reg.exe` exports into a fresh work folder
  inside `C:\ProgramData\Win11Privacy` (only SYSTEM and administrators can write
  there; the folder is checked not to be a link and to have a trusted owner),
  never into the user-writable desktop. Each file is read once into memory,
  checked and signed from exactly those bytes; the list of signatures
  (`backup-sig.json`, version 2) carries the folder name and its own signature,
  so a file cannot be dropped from the list unnoticed. Only the finished, signed
  backup is moved into the store, in one rename inside the same protected root
  (same volume, no copy). The engine running as administrator writes no backup
  file into any user-writable folder: the earlier same-volume move onto the
  desktop and the cross-volume copy with `CreateNew` are gone. Work folders left
  by an interrupted run stay inside the protected root and are removed after an
  hour.
* **Restoring a backup.** The signature list is parsed by the engine's strict
  parser (no duplicate keys, only known fields and plain file names), and for
  version 2 its own signature and folder name are checked. The folder must hold
  exactly the listed files — an extra `.reg`, a missing one, a link or a folder
  of that name refuses the whole backup. Each file is read once, its signature is
  checked on those bytes, its content is checked (a complete `reg.exe` export of a
  branch the program itself backs up, no key deletions, no keys outside that
  branch), and the same bytes are written into a protected work folder. Only when
  every file passed is anything imported; right before each import the staged
  file is opened without write sharing, its signature is checked again, and
  `reg.exe` reads it while it is held open. A backup made by an older version
  with a version 1 list (per-file signatures only) is still restored; a backup
  without signatures can only be imported by hand. **Downgrade protection:** a
  version 1 list is accepted only for a folder dated before version 2 existed
  (2026-11-15) and never for a folder in the store — the folder name, date
  included, is part of every file signature, so it cannot be back-dated. Backups
  of older versions on the desktop or in `-BackupRoot` are still listed and
  restored.
* **Restore in steps (T-3).** `reg.exe import` is not transactional — it writes
  values one by one and keeps what it wrote when it is killed — and the program
  does not pretend otherwise. Instead a restore holds its own lock
  (`restore.lock`, like the journal lock: a second restore is refused) and keeps
  a signed progress record `op-restore.json` in the data folder (written like the
  journal: replaced in one step, under the journal lock, HMAC with its own
  prefix). Before the first import the current state of the same branches is
  saved as an ordinary signed backup in the store ("snapshot before the
  restore"); if it cannot be saved, nothing is imported. Each file's stage goes
  to disk *before* reg.exe starts (`importing`); after the import the branch is
  exported again and every key and value of the backup must be there with the
  same data and kind — "reg.exe exited with 0" alone no longer counts as
  restored. States: `Prepared`, `InProgress`, `Restored` (record removed),
  `PartiallyRestored` (record kept), `Failed` (nothing imported, no record); the
  next run reports `RecoveryRequired` for a record left `InProgress` with a free
  lock (the process died) or `PartiallyRestored`. Exit codes: 0 restored and
  verified, 2 partly restored, 1 nothing imported. Nothing repeats an unfinished
  import by itself; the window tells the person, who chooses the same backup
  again (the snapshot taken first is kept) or the snapshot. `reg.exe import`
  never deletes, so "restored" means every saved value is back, not that the
  branch equals the backup, and going back to the snapshot leaves values the
  import added. Importing a backup is not written to the undo journal.

## Settings of other programs (VS Code, Firefox)

* The journal holds **one key** per entry (`appcfg`: program, key, the value as it
  was written in the file, whether the file existed), written before the change
  like every other entry. Rollback puts back exactly that key — the same text, or
  removes it if it was not there — and leaves everything else in the file alone,
  including what the user changed after the program did. A file the program created
  and that is empty after the rollback is deleted.
* Before, the first apply copied the whole `settings.json` to `*.win11privacy.bak`
  and the rollback copied it back over the file: everything the user had changed in
  between was lost (reproduced on the VM). Copies left by older versions are never
  applied, only mentioned.
* VS Code `settings.json` is in the user's profile, so it is written by the
  de-elevated task (see *Folders of the user*); a link on the path is refused.
  Firefox `policies.json` is in Program Files (administrators only) and written
  directly, with a JSON depth of 20 so that deep corporate policies are not cut.
  The Firefox folder and the whole path to it must be closed to non-administrators
  (`Test-PathTrusted`: inherited rights included, no parent that others may rename),
  and an existing `distribution` folder or `policies.json` must be owned by and
  writable only for SYSTEM/administrators. The file is replaced in one step under
  the lock `Global\Win11Privacy-FirefoxPolicies`, shared by the window's engine and
  the SYSTEM tasks: it is created owned by Administrators with rights for SYSTEM
  and administrators only, a lock pre-created by anybody else (owner or
  permissions, see *Named locks*) is refused, and there is no fallback to a
  per-session `Local\` lock (W11P-006, T-1).
  An existing `policies.json` that does not parse (a comment, another encoding) is
  left untouched instead of overwritten, so policies already there — corporate ones
  included — are not lost.
* Entries are shape-checked on rollback: known program, a valid key name, and the
  old value must be a single JSON scalar.

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
* `auditpol /backup` writes its copy of the audit policy only into a private
  work folder (T-2): a new folder with a random name, created with access for
  SYSTEM and Administrators only (owner Administrators, no inheritance) inside
  the protected root if that already exists and passes the full path check, or
  else inside `Windows\Temp` if nobody else can rename or re-permission any
  folder on the way. The user's `%TEMP%` is never used by an elevated engine
  (it used to be when the root did not exist yet). The copy is read once, opened
  without write sharing, and only if it is the one entry in the folder, a regular
  recent file owned by Administrators; otherwise the policy "could not be read".
  A non-elevated engine (nothing to protect) uses its own `%TEMP%`.
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
* Registry backups live only in `C:\ProgramData\Win11Privacy\backups`. A user who
  wants a copy elsewhere copies it by hand; a copy moved back or kept elsewhere is
  still verified in full before it is imported.
* A program of the user can pre-create the lock name
  `Global\Win11Privacy-FirefoxPolicies` (or `Global\Win11Privacy-App`). The engine
  then refuses to write Firefox policies — a denial of service, not a way to change
  data (T-1). The window starts anyway, but while the name is held by someone else
  a second window is not detected (two windows are safe for the data, see *Named
  locks*). The installer's "the program is running" check (Inno Setup `AppMutex`)
  only looks at the name and can be blocked the same way.
* A program of the user can hold `changes.json` or a progress record
  (`op-*.json`) open without sharing (the data folder grants Users read). The
  engine then refuses to write the journal or start the step that needs the
  record — a denial of service while the file is held; the history is not lost
  (T-4).
* **Elevation under another account.** A standard user may type an administrator's
  password. The engine then runs as that administrator while someone else is signed
  in. "Who is at the computer" is the owner of `explorer.exe` in the engine's own
  Windows session (another signed-in user's session is not considered; if Windows
  does not answer, the ID wipe does not start). Settings under `HKCU` still go to
  the signed-in user (his hive is written like the other profiles), but the guard
  and the watch tasks run with the highest privilege level, which only an
  administrator has: they are installed for the administrator account and work
  while it is signed in. The engine says so when they are enabled.
* Firewall rule by addresses: names that live on shared endpoints (shared Azure
  Storage, `e-msedge`, Office front door) are not resolved into the rule — blocking
  their addresses would cut other services. They stay blocked by name in `hosts`.
  Disabling Defender's cloud protection (MAPS) is a real reduction in protection
  against new threats, not a minor one.
* Deletions are not in the journal and cannot be undone: the cleanup module,
  the telemetry buffer wipe, the removal of apps and the footprint wipe.
* A release is built by CI with provenance attestation, but the exe is not
  Authenticode-signed and the compiler (`csc`) does not produce reproducible
  builds: two builds of the same sources give different exe hashes. The engine
  *is* reproducible, and CI compares it with the build from `engine/`. winget does
  not let a portable package choose its scope: installed without `--scope machine`,
  the self-elevating exe sits in the user's profile, where any program of that user
  could replace it before it is next run elevated. The package description and the
  README say to install with `--scope machine`, which puts it in the machine-wide
  winget folder that only administrators can write to.
* A few values are written to a store Windows does not document as a policy
  interface (`PolicyManager\default`, `MaxTelemetryAllowed` under `Policies`): Windows may
  rewrite them, and the guard puts them back. The program does not claim that
  every listed value changes behaviour on every build; the check reports what is
  actually set. Whether turning off Delivery Optimization (`DoSvc`) affects
  Windows Update on every edition has not been verified.
* CI runs the apply/revert round trip on `windows-latest` (Windows Server, not
  Windows 11) and only for part of the modules; Pro and Enterprise are not
  covered by any test, and neither is PowerShell 7 (the engine does not use it).

## How it is tested

* `tests/engine-tests.ps1` — read-only behaviour tests with stubs for every
  dangerous operation (firewall, auditpol, scheduler, reg load); registry writes
  only under `HKCU:\Software\W11P*` test keys, removed afterwards. Run in CI.
  It includes `tests/engine-remediation.ps1` (T-1…T-4 and the GDID context and
  interrupted-wipe checks: real mutexes and child processes, real `reg.exe` on
  test keys, processes killed at every stage).
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

**Запросы окна к движку.** Окно запускает движок с постоянной командной
строкой — `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass
-File "<движок в ProgramData>" -Request`, — а операцию и её данные пишет на
стандартный ввод одним JSON (`{"v":1,"op":"SensorSet","args":{...}}`, только
печатный ASCII, остальное — `\uXXXX`). Значения, которыми могут распоряжаться
другие программы пользователя (имена разделов ConsentStore в HKCU, путь к
рабочему столу из HKCU, имена папок резервных копий, пути программ), в
командную строку не попадают, и кавычка или «-Ключ» внутри них не превращается
в другую операцию движка (F-08: раздел ConsentStore с именем
`...\evil" -XrayStatus "` запускал `-XrayStatus` с правами администратора).
Движок разбирает запрос своим строгим разборщиком (предел размера, без повторов
ключей, без лишних полей, ограниченная вложенность), берёт операцию только из
белого списка, принимает у каждой операции только её аргументы, сам проверяет
тип и форму каждого значения и при любой ошибке отклоняет запрос целиком
(код 64), ничего не сделав. Ключи командной строки остались для задач
планировщика и ручного запуска; рядом с `-Request` других ключей движок не
принимает.

**Папка данных.** `C:\ProgramData\Win11Privacy` создаётся с явными правами:
SYSTEM и администраторы — полный доступ, пользователи — чтение. Путь до неё
(`C:\ProgramData`, корень диска) не должен давать никому другому переименовать
или удалить её — иначе защищённая папка не используется вовсе (W11P-006).
Объекту верят, только если он не ссылка, его владелец — система, администраторы
или TrustedInstaller и никто другой не может его писать, дописывать, удалять
(его самого и вложенное), менять права, владельца или атрибуты; учитываются
явные **и унаследованные** записи (прежняя проверка видела только явные), права,
которые папка передаст вложенному (кроме «создатель-владелец»), а вычитается
только явный запрет для «Все» в обычном порядке записей; права не читаются —
не верим. Папка, заведённая
кем-то другим, откладывается, чужие файлы и ссылки в
прежней папке уходят в карантин на любой глубине. Папка карантина создаётся
заново со случайным именем (`*.untrusted-<время>-<rnd>`) и проверяется, что это
не ссылка: прежний предсказуемый путь `*.untrusted-<время>` обычный пользователь
мог занять заранее junction'ом, и перенос чужого с правами администратора ушёл
бы по нему. Копия движка для задач лежит
там же и перед заменой сверяется со встроенной по SHA-256.

**Переносимый режим** (`-DataRoot` рядом с exe). Окно верит этой папке так же,
как своему exe: кто может писать туда, может подменить и exe. Задачи — нет: они
работают с переносимой папкой, только если она на томе NTFS/ReFS, ни одну папку
выше неё нельзя переименовать или перенастроить без прав администратора
(`Test-DirChainSecure`), а сама она закрыта так же, как ProgramData. Иначе задача
выходит, ничего не делая.

**Чтение файлов данных.** `Load-Json` и `Save-Json` одинаково отказываются от
папки, не прошедшей эти проверки: движок с правами администратора не прочитает
подложенный `profile.json`, журнал или файл состояния. Файл данных, который
держит открытым другой процесс, — *занят*, а не *отсутствует* (T-4): на Windows
PowerShell 5.1 ветка `catch [DirectoryNotFoundException]` после нескольких
десятков проверок начинала ловить ошибку «файл занят другим процессом», и
`Read-TextShared` отвечал «файла нет». Открыть журнал на чтение без совместного
доступа может любая программа пользователя (у папки данных «Пользователи:
чтение»), и повышенный движок видел «журнала нет»: откат говорил «возвращать
нечего», а следующая запись журнала затирала историю. Теперь вид ошибки
определяется по самому исключению .NET (`Test-IoBusy`, `Test-IoMissing`), а не
фильтрами `catch [тип]`; занятый журнал — «не читается», и в него ничего не
дописывается.

**Замки по имени (T-1).** `Global\Win11Privacy-FirefoxPolicies` (движок) и
`Global\Win11Privacy-App` (окно) — объекты ядра, которые первым может завести
любой процесс. Замок считается своим, только если его владелец — система или
администраторы и никто другой не может его ждать (то есть взять и держать),
менять права или владельца, удалить; SID самой учётной записи «свой», только
когда код работает без повышения (у повышенного движка этот SID есть у любой
обычной программы того же пользователя — она проходила проверку владельца, а
новый замок давал этому SID полный доступ). Новые замки заводятся с владельцем
«Администраторы» и правами только для системы и администраторов. Проверяется
тот дескриптор, который потом и ждётся, — имя заново не открывается. Чужой замок
Firefox — отказ записи `policies.json` сразу. Чужой объект на месте замка окна —
не «уже запущено»: окно открывается, потому что данные защищают замки самого
движка (журнал, `policies.json`, рабочие папки копий), а они и так рассчитаны на
несколько одновременных запусков (тихий режим, страж). Заранее занять любое из
имён по-прежнему можно — это отказ в работе, а не способ изменить данные или
получить права.

**Окружение и модули PowerShell.** Повышенный процесс получает окружение того,
кто его запустил, а первой папкой в `PSModulePath` стоит
`Документы\WindowsPowerShell\Modules` пользователя, куда пишет любая его
программа. Команды, на которых держится движок (`Get-ScheduledTask`,
`Get-NetFirewallRule`, `Resolve-DnsName`…), подгружаются по этому списку, и
подложенный модуль с именем системного выполнился бы с правами администратора —
у стража при каждом входе, без запроса UAC. Поэтому первой командой после
`param(` список сводится к `$PSHOME\Modules`, а `SystemRoot`, `ProgramData`,
`ProgramFiles`, `PATH` и папки профиля движок заново берёт у самой системы
(`GetSystemDirectory`, HKLM, ключ `ProfileList` по SID процесса), а не из
переменных, которые можно переопределить в `HKCU\Environment`. Окно запускает
движок с теми же значениями (`EngineFile.Harden`) и системной рабочей папкой.
Тест запускает движок с подложенным модулем `ScheduledTasks` и подменённой
`ProgramData` и проверяет, что ни то ни другое не используется. Шапка ещё
убирает переменные окружения, через которые .NET или оболочка грузят в процесс
код, — профайлер CLR (`COR_*`/`CORECLR_*`), стартовые перехватчики .NET
(`DOTNET_STARTUP_HOOKS`, `DOTNET_ADDITIONAL_DEPS`), слой совместимости
(`__COMPAT_LAYER`), — чтобы ни один дочерний процесс повышенного движка
(`reg.exe`, `auditpol`, PowerShell задач, де-повышенная задача пользователя) не
перехватили через унаследованную переменную; тот же набор чистит окно перед
запуском. Задачи стража и наблюдения идут от учётной записи администратора,
который их поставил (его `HKCU\Environment` обычному пользователю не переписать),
а не от обычного вошедшего пользователя.

**Папки пользователя (чистка, VS Code).** Удалять или писать *по пути* с
правами администратора там, куда могут писать программы пользователя, нельзя:
проверку нельзя привязать к действию, компонент пути между ними можно подменить
ссылкой. Поэтому движок так не делает.

* Папки профиля (`%TEMP%`, `%LOCALAPPDATA%\…`, `settings.json` VS Code) обрабатывает
  короткая задача **от имени самого пользователя, без повышения**
  (`Invoke-AsUser`): она может ровно то, что он и так может сам. Сценарий задачи —
  постоянный текст движка в защищённой папке; данные ей идут JSON-ом, ответ — малым
  JSON-файлом, из которого движок берёт только числа и короткие строки. Ссылка на
  пути — отказ, внутрь ссылок задача не заходит.
* Общие системные папки (`C:\Windows\Temp`, `ProgramData\…\WER`) чистит сам
  движок, но только объекты, чей **владелец** — SYSTEM, администраторы,
  TrustedInstaller или системная служба, и внутрь чужого не заходит.
  Не-администратор не может создать объект с таким владельцем (нужна привилегия
  смены владельца или восстановления), поэтому junction, подложенная в
  `C:\Windows\Temp`, пропускается, а не удаляется насквозь.
* Во `%TEMP%` файлы моложе 24 часов остаются (ими ещё пользуются запущенные
  программы); корзина очищается только после отдельного вопроса, а сам модуль
  чистки по умолчанию выключен.

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
* **Под замком.** Каждая запись *и каждое чтение* берут замок — файл
  `C:\ProgramData\Win11Privacy\journal.lock`, открытый без совместного доступа в
  защищённой папке (внутри одного процесса повторно входимый; если процесс
  завершился, Windows закрывает файл сама). Раньше это был именованный мьютекс
  `Global\Win11Privacy-Journal`, который мог создать и держать любой процесс, даже
  служба без прав, — и тогда не работали ни применение, ни откат (проверено на VM);
  у файла явные права при создании — только SYSTEM и администраторы, даже читать
  пользователям нельзя (унаследованные от папки права позволили бы любому процессу
  открыть его на чтение без совместного доступа и держать), а замок, оставшийся с
  более широкими правами, исправляется при открытии. Без прав администратора
  показ журнала читает его и без замка. У ReplaceFile есть миг, когда файла под
  этим именем нет, и чтение без замка видело «журнала нет». Файлы данных
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
| пока другой процесс держит журнал открытым без совместного доступа | журнал «не читается», в него не дописывается, история цела (T-4) | тест: второй процесс держит `changes.json`; чтение, попытка записи, история сверяется побайтно |
| во время возврата из копии | запись о ходе говорит, какой файл импортировался; следующий запуск — `RecoveryRequired`; повтор доводит и сверяет (T-3) | тест: дочерний процесс обрывается после `Prepared`, внутри первого импорта, после первого файла (настоящий reg.exe); VM: настоящий движок оборван посреди импорта |
| во время смены номера, после остановки служб | в записи о ходе — какие службы работали; «Вернуть как было» и следующая смена номера запускают их (GDID) | тест: дочерний процесс обрывается на каждой из 8 стадий; VM: настоящее стирание оборвано после остановки CDPSvc |

Проверки обрыва из таблицы, где сказано «тест», по-настоящему обрывают
дочерний процесс PowerShell (`[Environment]::Exit`) с функциями самого движка
ровно на границе, а потом восстанавливаются по тому, что на диске; реестр там
— пробные ключи `HKCU:\Software\W11P*`, `auditpol` — заглушка. Случаи с кустами
и брандмауэром проверяются ещё и на настоящей Windows 11 в VM
(`guest-hives.ps1`, `guest-fw.ps1`).

Не доказано: отключение питания во время обновления метаданных NTFS сверх того,
что гарантирует ReplaceFile; обрыв внутри самих `reg.exe load/unload`.

## Резервные копии

* Копия реестра делается прямо перед первым настоящим изменением при ручном
  применении и никогда — стражем. Хранится она только в защищённом хранилище
  программы `C:\ProgramData\Win11Privacy\backups` (W11P-005): на рабочий стол
  больше ничего не пишется. Вернуть копию — из окна («Изменения» → «Из резервной
  копии»); пункт «Открыть папку резервных копий» открывает хранилище (читать его
  могут все, менять — только администраторы). Остаются самая первая копия и 20
  последних, более старые убираются, когда кладётся новая.
* Ветка считается сохранённой, только если `reg.exe export` закончил с кодом 0
  **и** файл начинается с `Windows Registry Editor Version 5.00`. Недописанный
  файл удаляется; каждая невыгруженная ветка называется вместе с причиной.
* Точка восстановления на время ставит `SystemRestorePointCreationFrequency` в 0
  и возвращает прежнее значение.
* **Создание копии (W11P-001).** `reg.exe` выгружает ветки в новую рабочую папку
  внутри `C:\ProgramData\Win11Privacy` (писать туда могут только система и
  администраторы; папка проверяется: не ссылка, владелец доверенный), а не на
  рабочий стол, куда пишет любая программа пользователя. Каждый файл читается
  один раз в память, проверяется и подписывается ровно этими байтами; у списка
  подписей (`backup-sig.json`, версия 2) есть имя папки и своя подпись — убрать
  из него файл незаметно нельзя. В хранилище переносится только готовая
  подписанная копия — одним переименованием внутри того же защищённого корня (тот
  же том, без копирования). Движок с правами администратора не пишет файлы копии
  ни в одну папку, куда может писать пользователь: прежний перенос на рабочий
  стол и запись на другой том через `CreateNew` убраны. Рабочие папки оборванного
  запуска остаются внутри защищённого корня и убираются через час.
* **Возврат из копии.** Список подписей разбирается строгим разбором движка (без
  повторов полей, только известные поля и простые имена файлов), у версии 2
  сверяются его подпись и имя папки. В папке должны быть ровно файлы из списка:
  лишний `.reg`, недостающий, ссылка или папка с таким именем — отказ целиком.
  Каждый файл читается один раз, подпись сверяется на этих байтах, проверяется
  содержимое (целая выгрузка `reg.exe` ветки, которую программа сама сохраняет,
  без удалений разделов и без разделов вне этой ветки), и эти же байты пишутся в
  защищённую рабочую папку. Импорт начинается, только если прошли все файлы;
  перед импортом каждого файл открывается без права записи для других, подпись
  сверяется ещё раз, и `reg.exe` читает его, пока он открыт. Копия прежней версии
  со списком версии 1 (только подписи файлов) по-прежнему возвращается; копию без
  подписей можно импортировать только вручную. **Защита от понижения формата:**
  список версии 1 принимается только у папки с датой раньше появления версии 2
  (2026-11-15) и никогда — у папки из хранилища; имя папки вместе с датой входит
  в подпись каждого файла, задним числом его не переименовать. Копии прежних
  версий на рабочем столе и в `-BackupRoot` по-прежнему видны в списке и
  возвращаются.
* **Возврат по шагам (T-3).** `reg.exe import` не транзакционен — пишет значения
  по одному и, оборвавшись, оставляет записанное, — и программа не делает вид,
  что это не так. Вместо этого восстановление держит свой замок (`restore.lock`,
  как замок журнала: второе восстановление в это время — отказ) и ведёт
  подписанную запись о ходе `op-restore.json` в папке данных (пишется как
  журнал: подмена одним действием, под замком журнала, HMAC со своей
  приставкой). До первого импорта нынешнее состояние тех же веток сохраняется
  обычной подписанной копией в хранилище («снимок до восстановления»); не
  сохранилось — не импортируется ничего. Стадия каждого файла ложится на диск
  *до* запуска reg.exe (`importing`); после импорта ветка выгружается заново, и в
  ней должен быть каждый раздел и каждое значение копии с теми же данными и того
  же вида — «reg.exe закончил с кодом 0» само по себе больше не «вернулось».
  Состояния: `Prepared`, `InProgress`, `Restored` (запись убирается),
  `PartiallyRestored` (запись остаётся), `Failed` (не импортировано ничего,
  записи нет); следующий запуск называет `RecoveryRequired` запись, оставшуюся в
  `InProgress` при свободном замке (процесс умер), или в `PartiallyRestored`.
  Коды выхода: 0 — вернулось и сверено, 2 — вернулось частично, 1 — не
  импортировано ничего. Сам по себе незаконченный импорт не повторяется: окно
  говорит о нём человеку, а он выбирает ту же копию ещё раз (снимок, сделанный
  первым, остаётся) или снимок «до». `reg.exe import` ничего не удаляет, поэтому
  «вернулось» значит «каждое сохранённое значение на месте», а не «ветка равна
  копии», и возврат к снимку оставляет значения, которые добавил импорт. В
  журнал отката возврат из копии не пишется.

## Настройки других программ (VS Code, Firefox)

* В журнале — **один ключ** на запись (`appcfg`: программа, ключ, значение так, как
  оно написано в файле, был ли файл), и пишется она раньше изменения, как все
  остальные. Откат возвращает ровно этот ключ — тем же текстом, а если его не было,
  убирает — и не трогает всё остальное в файле, в том числе то, что человек
  поменял после программы. Файл, который завела программа и который после отката
  опустел, удаляется.
* Раньше при первом применении весь `settings.json` копировался в
  `*.win11privacy.bak`, а откат копировал его обратно поверх файла: всё, что человек
  успел поменять, пропадало (проверено на VM). Копии прежних версий не применяются
  никогда, о них только говорится.
* `settings.json` VS Code лежит в профиле пользователя, поэтому его пишет задача без
  повышения (см. *Папки пользователя*); ссылка на пути — отказ. `policies.json`
  Firefox лежит в Program Files (писать могут только администраторы) и пишется
  напрямую, с глубиной JSON 20, чтобы глубокие корпоративные политики не
  обрезались. Папка Firefox и весь путь до неё должны быть закрыты от всех, кроме
  администраторов (`Test-PathTrusted`: с унаследованными правами, ни одну папку
  выше чужой не может переименовать), а уже лежащие `distribution` и
  `policies.json` — принадлежать системе или администраторам и не быть открыты на
  запись другим. Файл заменяется одним действием под замком
  `Global\Win11Privacy-FirefoxPolicies`, общим для движка окна и задач SYSTEM: он
  заводится с владельцем «Администраторы» и правами только для системы и
  администраторов, замок, заранее заведённый кем-то другим (владелец или права —
  см. *Замки по имени*), не используется, а перехода на замок `Local\` (у каждого
  сеанса свой) больше нет (W11P-006, T-1). Уже лежащий `policies.json`, который не разбирается (комментарий,
  иная кодировка), не перезаписывается, а оставляется как есть — чтобы не стереть
  уже стоящие там политики, в том числе корпоративные.
* Записи проверяются по форме при откате: программа из известных, допустимое имя
  ключа, прежнее значение — одно значение JSON.

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
* `auditpol /backup` пишет копию политики аудита только в личную рабочую папку
  (T-2): новую папку со случайным именем и с правами с самого создания только для
  системы и администраторов (владелец «Администраторы», без наследования) — в
  защищённом корне, если он уже есть и прошёл проверку пути целиком, иначе в
  `Windows\Temp`, если ни одну папку на пути к ней чужой не может переименовать
  или перенастроить. Временную папку пользователя повышенный движок не берёт
  (раньше брал, пока корня ещё не было). Копия читается один раз, открытой без
  права записи для других, и только если она в папке одна, это обычный свежий
  файл и его владелец — администраторы; иначе политика «не прочиталась». Движок
  без повышения (защищать нечего) берёт свою временную папку.
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
* Резервные копии реестра лежат только в `C:\ProgramData\Win11Privacy\backups`.
  Нужна копия в другом месте — её копируют вручную; копия, перенесённая обратно
  или лежащая в другом месте, перед импортом всё равно проверяется целиком.
* Программа пользователя может заранее занять имя замка
  `Global\Win11Privacy-FirefoxPolicies` (или `Global\Win11Privacy-App`). Тогда
  движок откажется писать политики Firefox — это отказ в работе, а не способ
  изменить данные (T-1). Окно открывается всё равно, но, пока имя держит чужой,
  второе окно не распознаётся (два окна для данных безопасны, см. *Замки по
  имени*). Проверка установщика «программа запущена» (`AppMutex` Inno Setup)
  смотрит только на имя, и её можно занять так же.
* Программа пользователя может держать открытым без совместного доступа
  `changes.json` или запись о ходе (`op-*.json`): у папки данных «Пользователи:
  чтение». Тогда движок отказывается писать журнал или начинать шаг, которому
  нужна запись, — отказ в работе, пока файл занят; история не теряется (T-4).
* **Повышение под другой учётной записью.** Обычный пользователь может ввести
  пароль администратора. Тогда движок работает от имени этого администратора, а за
  компьютером сидит другой человек. «Кто за компьютером» — владелец `explorer.exe`
  в том же сеансе Windows, где работает движок (сеанс другого вошедшего
  пользователя не учитывается; если Windows не ответила, номер устройства не
  стирается). Настройки `HKCU` всё равно доходят до вошедшего
  (его куст пишется так же, как у других профилей), но страж и слежение работают с
  наивысшим уровнем, который есть только у администратора: они ставятся на учётную
  запись администратора и работают, пока он в Windows. Движок говорит об этом при
  включении.
* Правило брандмауэра по адресам: имена, живущие на общих узлах (общее хранилище
  Azure, `e-msedge`, общий вход Office), в правило не попадают — закрыв их адреса,
  программа отрезала бы чужие службы. Они остаются закрытыми по имени в `hosts`.
  Выключение облачной защиты Защитника (MAPS) — реальное снижение защиты от новых
  угроз, а не «небольшое».
* Удалённое в журнал не пишется и не возвращается: модуль чистки, стирание буфера
  телеметрии, удаление приложений и стирание цифрового следа.
* Релиз собирает CI с аттестацией происхождения, но exe не подписан Authenticode, а
  компилятор (`csc`) не даёт воспроизводимой сборки: две сборки одних исходников
  дают разные хеши exe. Движок воспроизводим, и CI сверяет его со сборкой из
  `engine/`. Portable-пакету winget
  выбрать область не даёт: поставленный без `--scope machine` самоповышающийся exe
  лежит в профиле пользователя, где его может подменить любая программа этого
  пользователя до следующего запуска с повышением. Описание пакета и README велят
  ставить с `--scope machine` — тогда exe ложится в общесистемную папку winget, куда
  пишут только администраторы.
* Часть значений пишется в хранилище, которое Windows не описывает как интерфейс
  политик (`PolicyManager\default`, `MaxTelemetryAllowed` в `Policies`): Windows
  может их переписать, и страж возвращает их. Программа не утверждает, что каждое
  значение из списка меняет поведение на каждой сборке: проверка показывает то, что
  реально стоит. Влияет ли отключение «Оптимизации доставки» (`DoSvc`) на Windows
  Update во всех редакциях, не проверено.
* CI гоняет применение и откат на `windows-latest` (это Windows Server, а не
  Windows 11) и только по части модулей; Pro и Enterprise не проверяет ни один
  тест, как и PowerShell 7 (движок его не использует).

## Как проверяется

* `tests/engine-tests.ps1` — проверки поведения только на чтение, с заглушками
  на каждое опасное действие (брандмауэр, auditpol, планировщик, reg load); в
  реестр пишут только пробные ключи `HKCU:\Software\W11P*`, которые потом
  убираются. Идут в CI. В них входит `tests/engine-remediation.ps1` (T-1…T-4,
  контекст пользователя и оборванное стирание номера: настоящие замки и
  дочерние процессы, настоящий `reg.exe` на пробных ключах, обрыв процесса на
  каждой стадии).
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
