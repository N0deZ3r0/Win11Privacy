# F-08 fix report — argument injection across the C# → elevated PowerShell boundary

Repository: Win11Privacy · audited revision `f7d58e6` (Release 2.0.0) · report date 2026-11-15  
Scope: F-08 (argument injection) and the directly related F-02 (per-app sensor access).  
Nothing was committed or pushed. No version numbers, tags or release metadata were changed.

---

## A. Executive summary

**Was F-08 present in the current checkout?** Yes, structurally. `HEAD` is still `f7d58e6`,
but the working tree already carried uncommitted fixes for F-01…F-07 from the same audit
session, including a *validation-only* mitigation for F-08: `PageDossier.IsSafeConsentKey`
rejected `"` in the ConsentStore key and the engine's `-SensorSet` rejected it too. The
root cause — the window building one flat `ProcessStartInfo.Arguments` string out of data —
was untouched, and the inventory (section B) showed that it was not limited to the sensor
key: the Desktop path (`-BackupRoot`) is read from `HKCU\...\User Shell Folders` and went into
the elevated engine's command line on **every** run, quoted only with `"`.

**Root cause.** `EngineRunner.EnginePsi(string extra)` concatenated
`-File "<engine>" <extra> -BackupRoot "<desktop>" [-DataRoot "<portable>"]` and the call
sites built `extra` by string concatenation (`"-SensorSet -SensorKey \"" + r.Key + "\" ..."`).
`powershell.exe -File` re-tokenises that string; a `"` inside a value closes the argument
and the rest becomes new engine switches, which run as administrator. Operation selection
and data shared one channel.

**What was changed.** The command line of the engine is now constant:
`powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<engine>" -Request`.
The operation and all its data travel as one JSON object on the engine's standard input
(`{"v":1,"op":"SensorSet","args":{"SensorKey":"…","SensorValue":"Deny"}}`). The window
builds it with `EngineRequest` (operation and argument names are code constants; values are
data; JSON is printable ASCII with `\uXXXX` for everything else). The engine reads stdin once
with a size cap, parses it with its own strict parser, takes the operation only from an
allowlist, accepts only that operation's arguments, validates each value's type and shape
itself, assigns parameters by explicit literal assignments, and refuses the whole request
(exit code 64) before doing anything on any error. `-Request` refuses any other command-line
switch next to it. All 54 GUI call sites and both silent-mode paths use this transport; no
string-built engine command line remains in the program. F-02: the engine now accepts the
real ConsentStore key shapes and builds the registry path from a fixed root plus validated
segments.

**Is the vulnerability demonstrably fixed?** Yes, by test at the actual process boundary:
the original exploit string (`webcam\NonPackaged\evil" -XrayStatus "`), sent through the
production C# code (`EngineProcess` + `SendRequest`, and `StartWithRequest` for silent mode)
to a real `powershell.exe` running the real engine, is refused before any operation is
selected; the engine's own trace shows no `XrayStatus` dispatch. In the disposable VM the
same was shown with a **real HKCU ConsentStore key whose name contains the quote**. See
section F for the exact results.

---

## B. Argument boundary inventory

Process launches in the C# program (`grep "Process.Start(\|\.Arguments"`), after the fix:

| Call site | Dynamic input | Input origin | Trust level | Validation now | Risk now |
|---|---|---|---|---|---|
| `EngineRunner.cs:164` `EngineProcess` (all GUI engine runs) | engine path only | `EngineFile.Ensure()` → `ProgramData` from HKLM + fixed `bin\engine.ps1` | admin-only (HKLM, protected folder) | path with `"` throws | **safe** — constant command line |
| `EngineRunner.cs:184` `SendRequest` (stdin) | the whole request | see rows below | — | engine-side strict parser + allowlist | **safe** — data channel only |
| `Program.cs:281` `RunCliAudit` (`--audit`) | none | — | — | `EngineRequest("Audit")` | **safe** |
| `Program.cs:297` `RunEngineConsole` (`--profile --silent`) | module/item ids, Desktop path | profile file chosen by the admin; HKCU | untrusted file | C# regex on ids + engine validation | **safe** |
| `Program.cs:180` relaunch with `runas` | the program's own argv | the same user's command line, gated by UAC | same user | `QuoteArgs` | not an engine boundary (UAC is the gate); unchanged |
| `Actions.cs:95`, `Crash.cs:105`, `PageSettings.cs:156`, `PageAbout.cs:387`, `Report.cs:42` | folder/file paths, release URL | own folders / constant | — | — | not an engine boundary (explorer/browser, no elevation change) |

Dynamic engine arguments (each is now a typed request argument, validated by the engine in
`Test-RequestArg`, `engine/00-header.ps1`):

| Call site (window) | Argument | Origin | Trust | Engine-side validation | Before | Now |
|---|---|---|---|---|---|---|
| `PageDossier.cs:315` SensorSet | `SensorKey` | HKCU ConsentStore child-key names (`-Spy` output) | **untrusted** (any user process) | request: no control chars/`"`, ≤320; then `Get-ConsentKeyPath` grammar (section E) | **unsafe** (F-08) | safe |
| `EngineRunner.cs:202` every run | `BackupRoot` | `Environment.GetFolderPath(Desktop)` ← HKCU shell folders | **untrusted** (user-writable registry) | path: drive or `\\server\share`, no `"<>|?*/` or control chars, no `..`, ≤1024 | **unsafe** (every run) | safe |
| `EngineRunner.cs:202` portable | `DataRoot` | folder next to the exe | trusted like the exe | path rule + existing `-DataRoot` checks in `03-datafolder.ps1` | quoted, no `"` possible in NTFS names | safe |
| `PageDossier.cs:347` Block/UnblockApp | `AppPath` | process paths from the network monitor | untrusted-ish (process images) | path rule | quoted only | safe |
| `PageChanges.cs:147` RestoreBackup | `BackupPath` | folder names on the Desktop (`-ListBackups`) | **untrusted** (user-writable) | path rule (+ existing signature check of the backup) | quoted only | safe |
| `Actions.cs:660` SnapshotDiff | `SnapshotDiff` | snapshot file names in ProgramData | admin-only folder | `^[A-Za-z0-9._-]{1,128}\|[A-Za-z0-9._-]{1,128}$` | quoted only | safe |
| `PageChanges.cs:109` RestoreItems | `ChangeItems` | ids from the signed journal (base64url) | engine-produced | `^[A-Za-z0-9._]{1,8192}$` each | quoted | safe |
| `PageApps.cs:199` StartupSet | `StartupItems`, `StartupValue` | base64url ids of Run entries (Run value names are user-writable, but encoded) | engine-produced | ids as above; value `On`/`Off` | quoted | safe |
| `PageApps.cs:95` RemoveApps | `AppItems` | Appx package names | system | `^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$` | unquoted, comma-joined | safe |
| `PageDossier.cs:377` FootprintWipe | `WipeItems` | fixed footprint ids | engine-produced | `^[A-Za-z0-9_-]{1,64}$` | unquoted | safe |
| `Actions.cs:43/122/255/611`, `PageGdid.cs:214`, `Program.cs:261` | `Modules`, `SkipItems` | engine definitions; profile file | engine / untrusted file | `^[A-Za-z0-9_-]{1,64}$`; `^[a-z][a-z0-9_]{0,40}#[0-9]{1,4}$` | unquoted (profile ids regex-checked in C#) | safe |
| `Actions.cs:527`, `PageTimeline.cs:94`, `PageXray.cs:139` | `MonitorHours`, `TimelineDays`, `XrayHours` | constants | code | int ranges | constants | safe |
| switches (`DryRun`, `SpyAll`, `GuardDaily`, …) | flags | UI state | code | must be JSON `true` | constants | safe |

Engine-internal command lines (not reachable from the window's data after the fix):

| Site | Dynamic part | Status |
|---|---|---|
| `engine/14-startup.ps1:373`, `18-live-notify.ps1:17`, `21-sensor-watch.ps1:27/60` scheduled-task actions | engine copy path + `$script:DataArg` (`-DataRoot "<path>"`) | `DataRoot` can only arrive validated (no `"`), and only as `…\Win11Privacy-Data` (existing rule) → safe |
| `engine/12-gdid.ps1:406` one-shot task | task path from the engine's own definitions | safe (constant data) |
| `Actions.cs` "File for other PCs" (`apply.cmd`) | module/item ids written into a batch file for another machine | not a runtime boundary of this program; ids come from the engine's definitions (selection rows), unchanged |

---

## C. Design decision

**Selected: Option A — structured request over standard input.**

- Command line: constant except the engine path, which comes from HKLM-derived ProgramData
  and a protected folder (and is rejected if it contains `"`).
- Request: one JSON object, printable ASCII only (`EngineRequest.AppendString` escapes
  `"`, `\`, control characters and every non-ASCII char as `\uXXXX`), so pipe encoding
  (OEM code page, UTF-8 console) cannot alter it. A leading UTF-8 BOM, which the pipe
  writer adds when the console code page is 65001, is stripped by the engine.
- Engine: `Read-EngineRequest` reads stdin to EOF once (cap 256 KiB, printable ASCII + TAB/CR/LF
  only); `ConvertFrom-EngineRequest` is a hand-written strict parser (objects, arrays,
  strings with standard escapes, integers, `true`/`false`; no `null`, no floats; duplicate keys
  rejected case-insensitively; depth ≤ 4; ≤ 64 fields; ≤ 4096 list items; no trailing data);
  `Use-EngineRequest` checks top-level fields (`v`, `op`, `args` only, `v` = 1), the operation
  against the allowlist `$RequestOps` (case-sensitive), each argument against the operation's
  list (+ `BackupRoot`, `DataRoot`), type/shape with `Test-RequestArg`, required arguments,
  and only then assigns `$script:<Param>` through two literal `switch -CaseSensitive`
  blocks (`Set-RequestOp`, `Set-RequestArg`) — no variable name ever comes from the JSON.
  Validation of the whole request happens before the first assignment. Any failure:
  `[!]` line, `###JSON### {"error":"request rejected"}`, exit 64, nothing else runs.
- No `ConvertFrom-Json`, no `Invoke-Expression`, no `cmd.exe`, no evaluation of request text.
- Operations that only scheduled tasks use (`Guard`, `SensorGuard`, `NetGuard`,
  `WatcherNotify`, `PurgeBuffer`, `Proof*`) are not in the allowlist: the window never asks
  for them, so a request cannot either.

**Rejected alternatives.**
- *Option B (protected request file)* — needs a new file in a trusted location with an
  explicit ACL, reparse/replace checks and cleanup on every exit path; strictly more moving
  parts than a pipe that only the parent holds, for no extra property.
- *Option C (correct per-argument quoting)* — would keep operation selection and data in the
  same channel; correctness depends on the exact `powershell.exe -File` re-tokenisation rules
  (backslash runs before quotes, values starting with `-` bound as parameter names), and any
  future call site that forgets the quoting helper re-opens the bug. Rejected.

**Security assumptions.** The window runs elevated (manifest `requireAdministrator`); the
engine file is the protected, SHA-256-checked copy; the parent writes stdin and closes it, and
no other process holds the pipe; the engine's environment is hardened by `EngineFile.Harden`
(which now also removes the test-only `WIN11_ENGINE_TRACE`).

**Compatibility.** C# 5 / .NET Framework 4.x in-box `csc` (no new API beyond
`ProcessStartInfo.RedirectStandardInput`, `ThreadPool`); PowerShell 5.1 (`[Console]::OpenStandardInput`,
`[Console]::IsInputRedirected`, regex, hashtables). No new dependencies.

**Migration impact.** Every `RunJson`/`RunStreaming` caller now passes an `EngineRequest`
(54 call sites converted by exact, individually checked replacements);
`EngineWrites(string)` became `EngineRequest.Writes`; `SilentProfileArgs` returns an
`EngineRequest`. The engine's command-line switches remain for scheduled tasks and manual use.

---

## D. Changed files (this patch)

| File | Purpose | Details |
|---|---|---|
| `EngineRequest.cs` (new) | request object | op/arg names restricted to Latin letters (code constants), duplicate args rejected, ASCII-only JSON writer, `WithCommon`, `Describe` (log only), `Writes` (replaces the old string-matching `EngineWrites`) |
| `EngineRunner.cs` | process boundary | `EngineProcess` (constant command line, stdin redirected), `SendRequest` (background write + close), `EnginePsi(EngineRequest, out json)`, `RunJson`/`RunStreaming`/`Launch` take the request |
| `Program.cs` | silent mode | `SilentProfileArgs` → `EngineRequest`; `RunCliAudit`, `RunEngineConsole` use `EngineProcess` + `StartWithRequest` |
| `Actions.cs`, `MainForm.cs`, `PageAbout.cs`, `PageApps.cs`, `PageChanges.cs`, `PageDossier.cs`, `PageGdid.cs`, `PageHome.cs`, `PageTimeline.cs`, `PageXray.cs`, `Report.cs` | call sites | every engine call built with `new EngineRequest(op)...`; no string concatenation of switches remains |
| `PageDossier.cs` | GUI pre-check | `IsSafeConsentKey` mirrors the engine grammar (defence in depth; the engine does not rely on it) |
| `Engine.cs` | environment | `Harden` removes `WIN11_ENGINE_TRACE` |
| `engine/00-header.ps1` | engine | `[switch]$Request`; allowlist, argument spec, strict reader/parser, validation, literal assignment, fail-closed exit 64; test trace `###OP###` only with `WIN11_ENGINE_TRACE` (1 = trace, 2 = accept and exit) |
| `engine/20-dossier-footprint.ps1` | F-02 | `Get-ConsentKeyPath`; `-SensorSet` builds the path from it |
| `Win11-Privacy-Engine.ps1` | generated | rebuilt with `python tools/build_engine.py` (not hand-edited) |
| `SelfTest.cs` | tests | request serialisation corpus, constant command line, real boundary runs (A, B, E, F), ConsentStore grammar cases |
| `tests/engine-tests.ps1` | tests | engine-level request tests A, B, C (grammar), D, E, malformed requests; static check updated |
| `.github/workflows/build.yml` | CI | SelfTest gets `WIN11_TEST_ENGINE` so the boundary tests run on the agent |
| `docs/security-model.md`, `CHANGELOG.md` | docs | transport described (EN/RU) |

Other uncommitted changes in the same working tree (F-01…F-07 fixes, UI work, the installer)
are **not** part of this patch and are listed in `AUDIT_REPORT.md` / `CHANGELOG.md`.

---

## E. F-02 resolution — accepted ConsentStore grammar

Source of truth: what `-Spy` emits (`engine/19-dossier-sensors.ps1`): the relative path under
`HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore`.

```
<capability>                                   e.g. location
<capability>\<PackageName>_<PublisherId>       e.g. webcam\Microsoft.WindowsCamera_8wekyb3d8bbwe
<capability>\NonPackaged\<D:#path#to#app.exe>  e.g. microphone\NonPackaged\C:#Program Files#App#app.exe
```

- capability: case-insensitive match against the engine's own list `$script:SpyCaps`
  (webcam, microphone, location and the other capabilities the dossier shows, including
  `sensors.custom`); the canonical name from the list is used in the path;
- package: `^[A-Za-z0-9][A-Za-z0-9.-]{1,99}_[A-Za-z0-9]{13}$`, not `NonPackaged`;
- NonPackaged program: `^[A-Za-z]:(#[^#<>:"|?*\\/]+)+$` (drive letter, `#`-separated
  non-empty parts; Unicode allowed, e.g. Cyrillic folders), no `.` part;
- the whole key: ≤ 320 chars, 1–3 `\`-segments, no empty segment, no `.`/`..`,
  no control chars, no `"`, no `/`.

Rejected (tested): `..`, `webcam\..\evil`, empty segments, leading/trailing separators,
`webcam\NonPackaged` alone, drive paths (`C:\Windows\…`), UNC (`\\server\share`), registry
roots (`HKLM:\…`), unknown capabilities, UNC-style NonPackaged (`##server#share#…`), bare
names without publisher id, 4 segments, over-long keys, control characters, quotes, `/`.
The registry path is `ConsentRoot + '\' + <canonical capability> [+ '\' + segment …]`, and
`Set-Reg` writes it through the .NET registry API (no wildcard expansion). Global
capability keys (`location`) keep working as before.

---

## F. Regression tests

All results below were produced by actually running the tests on 2026-11-15 and reading
their output. "Host" = the development PC, **not elevated**, read-only operations only (no
registry writes). "VM" = the disposable Windows 11 test VM (`W11P-TEST`, build 26300,
administrator, UAC off), reverted to the clean snapshot `before-deep` first.

| # | Test (where) | Attack / behaviour covered | Result |
|---|---|---|---|
| A1 | SelfTest `Boundary` — "A (как окно)" (host) | original exploit `webcam\NonPackaged\evil" -XrayStatus "` built by `EngineRequest`, started by `EngineProcess` + `SendRequest` (the window's code) against the real engine; trace shows the chosen operation | **pass**: exit 64, no `###OP###`, no `XrayStatus` |
| A2 | SelfTest — "A (тихий режим)" (host) | same, through `StartWithRequest` (silent mode) | **pass** |
| A3 | SelfTest + engine-tests — `-XrayStatus -XrayWipe` without quote in the key (host) | switch text that survives the value check stays data | **pass**: only `SensorSet` dispatched; key refused by `Get-ConsentKeyPath`, no write |
| A4 | `guest-f08.ps1` (VM, admin) | a **real HKCU ConsentStore key** named `webcam\NonPackaged\evil" -XrayStatus "` created with the .NET registry API, then the window-shaped request | **pass**: exit 64, no operation, `-XrayStatus` not run, key value unchanged |
| B1 | SelfTest + engine-tests (host) | `BackupRoot` = `C:\Temp\x -PurgeData -XrayWipe -Revert` with the read-only `DataInfo` | **pass**: only `DataInfo` dispatched, no "Удаление данных программы" section |
| B2 | SelfTest + engine-tests (host) | `BackupPath` = `C:\x" -PurgeData -RestoreAll "` | **pass**: exit 64, no operation |
| B3 | engine-tests (host) | `Modules` = `telemetry -Revert`; `SnapshotDiff` = `a.json\|b.json" -RestoreAll "` | **pass**: refused, no operation |
| — | (all) | no destructive command was executed during injection testing: positive cases use `DataInfo`/`ListDefs`, and the destructive shapes in F1 are run in accept-only mode (`WIN11_ENGINE_TRACE=2`) | — |
| C1 | `guest-f08.ps1` (VM, admin) | legitimate keys: `webcam\NonPackaged\C:#w11p-test#fake.exe`, `microphone\W11PTest.FakeApp_1a2b3c4d5e6f7`, `webcam\NonPackaged\C:#Программы#Тест камеры#cam [1].exe`, global `location` — Deny then Allow | **pass** (8/8): value written and read back each time, then restored |
| C2 | engine-tests (host) | `Get-ConsentKeyPath` maps 5 legitimate keys (incl. upper-case capability, `sensors.custom`, Cyrillic, `( )` `[ ]`) to the exact registry path | **pass** (5/5) |
| D1 | engine-tests (host) | 20 invalid keys: `..`, `webcam\..\evil`, empty segments, leading/trailing separators, `webcam\NonPackaged`, `C:\Windows\System32`, `\\server\share\x`, `HKLM:\SOFTWARE\x`, unknown capability, `##server#share#x.exe`, `.` part, bare NonPackaged name, `/`, 4 segments, bare name, 330+ chars, newline, quote, `webcam\.` | **pass** (20/20 refused without write) |
| D2 | `guest-f08.ps1` (VM, admin) | 17 invalid keys against the real HKCU; full ConsentStore key list compared before/after | **pass** (17/17; no key created or removed) |
| E1 | SelfTest `Requests` (host) | 20 adversarial strings (quotes, `\`, trailing/double backslashes, empty, whitespace, `\n\r\t`, `-PurgeData`, `$(...)`, shell metacharacters, Cyrillic, NUL/control chars, emoji surrogates, U+2028) → JSON is printable ASCII and reads back unchanged; op unchanged | **pass** |
| E2 | SelfTest `Boundary` + engine-tests (host) | 23 adversarial `BackupRoot` values through the real engine | **pass**: every case either refused (64, no op) or exactly `DataInfo` |
| E3 | engine-tests (host) | 28 malformed/foreign requests: empty, not JSON, duplicate `op`, case-duplicate keys, task-only ops (`Guard`), unknown op, `Request` as op, wrong op case, wrong version, extra field, non-object args, foreign argument, string-for-int, out-of-range, float, `false` switch, non-string list item, missing/empty required, `null`, trailing second request, duplicate `args`, depth, array root, truncated, non-ASCII bytes, 300 KB, `-Request` plus `-XrayStatus` on the command line | **pass**: all refused before operation selection |
| E4 | engine-tests (host) | BOM-prefixed, whitespace/CRLF, `\u` path, `ListDefs` | **pass** |
| F1 | SelfTest `Boundary` — "F" (host) | every request shape the window builds (55: Apply, Audit, InstallGuard, RemoveApps, StartupSet, RestoreItems, RestoreBackup, SensorSet, Block/UnblockApp, FootprintWipe, SnapshotDiff, Monitor, Timeline, XrayScan ±Baseline, Spy+SpyAll and 34 argument-less ops) is accepted by the engine schema in accept-only mode, plus `DataRoot` | **pass** (55/55 + 1) |
| F2 | SelfTest `Commands`/`Requests` (host) | constant command line (`EngineProcess`), quote in engine path refused, op/arg names restricted, duplicate args refused, `EngineRequest.Writes` for all ops | **pass** |
| F3 | section B of this report | security argument for every other launch site | documented |

Full suites:

| Suite | Where | Result |
|---|---|---|
| SelfTest (`/define:SELFTEST`, with `WIN11_TEST_ENGINE`) | host | **114 passed, 0 failed** |
| `tests/engine-tests.ps1` | host (not admin) | **569 passed, 0 failed** (first run: 564/3 — two test bugs and one stale static check, fixed in the tests; see below) |
| `tests/engine-tests.ps1` | VM (admin) | first run 570 passed / 1 failed (the same test bug, the VM had the unfixed test file); re-run with the fixed test file: **573 passed, 0 failed** (includes all F-08 checks A–E, run as administrator) |
| Pester `tests/engine.Tests.ps1` | host (3.4) / VM | **35 / 0** and **35 / 0** |
| F-08 live checks `guest-f08.ps1` | VM (admin) | **14 passed, 0 failed** |
| Installer checks `tests/installer-tests.ps1` (with the F-08 exe) | VM (admin) | **40 passed, 0 failed** |
| UI page scan (UITEST, 6 pages × 2 sizes) | host | 0 clipped, all pages opened |

Defects found by these tests during the work and fixed:
- the strict parser's depth limit counted list elements too deep, so every request with a
  list (Apply, Audit, InstallGuard, RemoveApps, …) was refused — caught by F1, fixed
  (`$Depth -gt 4`);
- on this PC the console input code page is UTF-8, and .NET writes a UTF-8 BOM into the
  child's stdin pipe already at `Process.Start` — the engine strips one leading BOM; the
  first version of the BOM test added a second one itself (test bug, fixed);
- two test-only issues in `engine-tests.ps1` (`$engineText` used before it is defined; the
  recycle-bin static check still looked for the old `-EmptyRecycleBin` string).

---

## G. Build and compatibility

Compiler: in-box `%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe` (C# 5, .NET
Framework 4.x); PowerShell 5.1 (Windows PowerShell, host and VM).

| Command | Result |
|---|---|
| `python tools/build_engine.py` | `собран Win11-Privacy-Engine.ps1 (частей: 33, строк: 9028)` |
| `python tools/build_engine.py --check` | matches the parts |
| PowerShell parser on `Win11-Privacy-Engine.ps1`, `engine/00-header.ps1`, `engine/20-dossier-footprint.ps1`, `tests/engine-tests.ps1` | 0 errors each |
| `csc /target:winexe /optimize+ /win32res:app.res … *.cs` (release exe) | exit 0 (pre-existing warning CS0649 `TileGrid.SingleRow` only) |
| `csc /define:SELFTEST /main:Win11Privacy.SelfTest … *.cs` | exit 0 |
| `csc /define:UITEST … *.cs` | exit 0 (pre-existing CS0162 in UITEST-only code) |
| `python tools/gen_lang.py` + `git diff --exit-code Lang.cs` + `python tools/check_lang.py` | unchanged, "all translated" (no new UI strings) |
| PSScriptAnalyzer (Microsoft-signed copy) on `engine/00-header.ps1`, `engine/20-dossier-footprint.ps1` | new code: only `PSUseShouldProcessForStateChangingFunctions` for the internal `Set-RequestOp`/`Set-RequestArg` and `PSAvoidUsingWriteHost` (the engine's output channel); the empty-catch findings are pre-existing |
| `.github/workflows/build.yml` | PowerShell 5.1 `run:` blocks checked ASCII-only (5 blocks, 0 non-ASCII lines); SelfTest step now sets `WIN11_TEST_ENGINE` |

Not run: the GitHub Actions workflow itself (nothing was pushed), and the live
`tests/roundtrip.ps1` (it applies and reverts settings; unchanged by this patch, CI-only).

---

## H. Residual risks

- **Manual / scheduled-task command lines remain.** The engine still accepts its switches
  on the command line for scheduled tasks and manual runs. Their arguments are constants
  plus the validated `DataRoot`; an administrator typing switches by hand is outside the
  threat model. `-Request` cannot be combined with them.
- **Validation granularity.** Each argument's shape is checked at the request layer and
  again where it is used, but the shape rules for ids (`AppItems`, `StartupItems`, …) are
  intentionally permissive enough for real data; they no longer matter for operation
  selection, only for what each operation accepts.
- **UNC Desktop.** `BackupRoot` accepts `\\server\share\…` (redirected Desktop). Device paths
  (`\\?\`, `\\.\`) are rejected.
- **ConsentStore keys outside the grammar** (programs started from network shares, i.e.
  `##server#share#…`) cannot be toggled from the dossier; the engine refuses them rather
  than guess.
- **Test-only trace.** `WIN11_ENGINE_TRACE` changes engine output (and with `2` makes it exit
  after validation). The window removes it from the engine's environment; a process that
  could set the elevated window's own environment is already beyond this boundary.
- **Other audit findings** (F-01, F-03…F-07) are fixed in the same working tree but are not
  part of this patch and were not re-verified here beyond the full test suites.

---

## I. Release recommendation

**READY FOR REVIEW.**

The injection is removed structurally at the process boundary (no data on the engine's
command line), the engine validates every request independently of the window and fails
closed, F-02 works with real ConsentStore keys and refuses malformed ones, and the
original exploit was shown refused both through the production C# code and with a real
HKCU key in a disposable VM. It is *not* called production-ready here: the change touches
every engine call of the program, and it has not yet gone through the GitHub Actions run
(SelfTest boundary tests, UI pages as administrator, the live roundtrip) or a human review
of the diff. The other audit fixes in the same working tree should be reviewed separately.

### Acceptance criteria

- [x] F-08 is eliminated at the actual process boundary.
- [x] Registry-derived values cannot create additional engine switches.
- [x] Other dynamic engine arguments have been audited (section B).
- [x] Engine-side request validation is independent of GUI validation.
- [x] F-02 works with legitimate ConsentStore paths (VM, C1).
- [x] Invalid ConsentStore paths fail closed (D1, D2).
- [x] No destructive command was executed during injection testing.
- [x] PowerShell 5.1 compatibility is preserved.
- [x] Existing functionality and process lifecycle remain intact (all suites green; cancellation path unchanged — `StopEngine` still kills the tracked process).
- [x] Regression tests cover the original exploit and related input classes.
- [x] Full available tests and build checks have been run (CI not run — nothing pushed).
- [x] `F08_FIX_REPORT.md` records the evidence.
