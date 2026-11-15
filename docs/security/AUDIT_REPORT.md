# Win11Privacy — Deep Code Audit

**Date:** 2026-11-14
**Scope:** entire local repository at `main` @ `f7d58e6` (Release 2.0.0)
**Method:** full source read (engine 33 parts, C# WinForms, Python tooling, CI,
tests, docs), static analysis (PowerShell AST, PSScriptAnalyzer 1.23.0 signed,
csc warn:4, Python AST), live reproduction on a disposable Windows 11 Home VM.
**Rule followed:** read-only on the repository; no source changed, no settings
applied on the host. All live checks ran in the throwaway VM or the scratchpad.

---

## 1. Executive summary

This is a mature, unusually careful codebase. The hard parts — the signed
write-ahead undo journal, the re-entrant file lock, atomic `hosts`/journal
replacement, the `PSModulePath`/profiler-env hardening, the de-elevated user
tasks, the SHA-256-checked embedded engine — are implemented correctly and are
backed by real tests (local read-only suite, Pester, a live apply/revert round
trip in CI, and an extensive VM harness). Two prior audits have already been
remediated (commits `e0e8172`, `f771762`).

I found **one HIGH-severity argument-injection** defect (a crafted registry key
name is concatenated unescaped into the elevated engine's command line and
executes as additional engine switches — confirmed on the VM), plus three
mid-severity correctness/honesty defects, two of which make a user-facing
feature silently not work, and one TOCTOU that contradicts a guarantee written
in `docs/security-model.md`. I did **not** find an arbitrary-privileged-code
execution path (the injection is limited to the engine's own verbs) or a
silent catastrophic data-loss defect.

| ID | Sev | Confidence | One line |
|----|-----|-----------|----------|
| F-08 | HIGH | CONFIRMED (VM) | A `"` in a ConsentStore key name (writable by a non-admin in their own HKCU) breaks out of the `-SensorKey` argument; the elevated engine then parses and runs attacker-chosen engine switches. Injected `-XrayStatus` executed on the VM. |
| F-01 | MEDIUM | CONFIRMED (VM) | A `.reg` file dropped into the backup folder *before signing* gets signed and is imported as admin on restore — contradicts the "added file is not imported" guarantee. |
| F-02 | MEDIUM | CONFIRMED (VM) | The dossier "deny this app the camera/mic/location" button never works: the engine rejects every real ConsentStore key. |
| F-03 | MEDIUM | CONFIRMED (VM) | Per-app network block is keyed by file *name* only; two programs with the same exe name collide — the second reports "blocked" with no rule, and unblocking removes the first one's rule. |
| F-04 | LOW | CONFIRMED (VM) | `-RestoreAll` always exits 0 even when the journal is untrusted and nothing was restored; the window shows "Готово." (success). |
| F-05 | LOW | CONFIRMED (static) | Guard/watch install commands exit 0 even when `Register-ScheduledTask` throws; the status line shows success (the error is only in the log text). |
| F-06 | INFO | CONFIRMED (VM) | A freshly created quarantine folder inherits the ProgramData ACL (Users may create sub-items in it). Defense-in-depth only. |
| F-07 | INFO | CONFIRMED | 75 empty `catch {}` blocks; several legitimately swallow unexpected errors on read paths. |

**F-08 should be fixed before the next release** (and it is cheap to fix);
F-01/F-02/F-03 next.

### Scores (0–10)

| Area | Score | Why |
|---|---|---|
| Security | 6 | Threat model is explicit and mostly upheld, but F-08 is a real, confirmed elevation-relevant argument injection into the admin engine; F-01 is a constrained TOCTOU. No arbitrary-code path found. |
| Reliability | 7 | Write-ahead + verify-after-write everywhere; F-02/F-03 are genuine feature breakages; several commands under-report failure (F-04/F-05). |
| PowerShell quality | 8 | Idiomatic, PS 5.1-aware, defensively written; empty-catch density is the main smell. |
| C# architecture | 8 | Clean partial-class split, correct UI threading, resource disposal, SHA-verified engine extraction. |
| Windows integration | 9 | Deep, correct, edition-aware; service-SID firewall rules, task settings vs. state, hive mounts all handled properly. |
| Privacy effectiveness | 7 | Honest about Home/Pro telemetry floor and Tamper Protection; large, well-researched definition set; some values go to undocumented stores (acknowledged). |
| Build system | 8 | Deterministic engine build, `--check` in CI, actions pinned by SHA; exe not reproducible/signed (acknowledged). |
| Testing | 8 | Real round trip + crash tests + VM harness; gaps: F-02/F-03/F-04 paths not covered. |
| Documentation | 9 | `security-model.md` is exceptional and mostly kept in step with code (F-01 is the one place it over-claims). |
| Overall maturity | 7 | Production-quality foundations; one confirmed elevation-relevant injection (F-08) and two broken features keep it from an 8 until fixed. |

---

## 2. Repository architecture

* **Engine** — one PowerShell 5.1 file `Win11-Privacy-Engine.ps1` (8 497 lines),
  built by `tools/build_engine.py` from 33 ordered parts in `engine/`. The built
  file is committed, embedded in the exe as the `engine.ps1` resource, released,
  and SHA-256-checked at runtime. CI runs `build_engine.py --check`.
* **GUI** — C# 5 / WinForms built with the in-box `csc` (no external deps).
  `MainForm` is a partial class across `MainForm.cs`, `Navigation.cs`, `Page*.cs`,
  `EngineRunner.cs`, `Program.cs`, `Actions.cs`, etc. The engine is extracted to
  `%ProgramData%\Win11Privacy\bin\engine-<pid>.ps1` with an admin-only ACL and run
  by full-path `powershell.exe`.
* **Tooling** — Python: `build_engine.py`, `gen_lang.py`/`check_lang.py` (generate
  `Lang.cs`), `set_version.py`, `make_winget.py`, `submit_winget.py`,
  `release_notes.py`.
* **CI** — `.github/workflows/build.yml`: a read-only `build` job (checks, tests,
  live round trip, exe build) and a tag-only `release` job (write + attestation +
  winget) with actions pinned by commit SHA.

### Trust model (as implemented)
The window and the engine run as administrator (manifest `requireAdministrator`).
Everything the elevated engine consumes from a user-writable location
(`PSModulePath`, `HKCU\Environment`, the data folder in portable mode, the
journal, user-profile files) is either rebuilt from the system, locked down by
ACL, HMAC-signed, or handled by a de-elevated per-user task. This is correct and
well tested.

---

## 3. Repository coverage

| Component | Files | Inspected |
|---|---|---|
| Engine parts | `engine/00`–`engine/32` (33) | ✅ all read |
| Built engine | `Win11-Privacy-Engine.ps1` | ✅ verified = build of parts |
| C# GUI | all `*.cs` (37) | ✅ key paths read in full: Program, EngineRunner, Engine(File), Actions, PageChanges, PageDossier, PageAbout, SingleInstance, Crash, AppInfo, SelfTest, Rows; others skimmed |
| Python | all 7 `tools/*.py` | ✅ build_engine, submit_winget read in full; others read |
| CI | `.github/workflows/build.yml` | ✅ full |
| Tests | `engine-tests.ps1`, `engine.Tests.ps1`, `roundtrip.ps1` | ✅ structure + relevant sections |
| Docs | `docs/security-model.md`, READMEs, CHANGELOG | ✅ security-model full |
| Build/packaging | `build.cmd`, `check-engine.cmd`, manifest, winget tooling | ✅ |

Not line-by-line: the larger UI-only files (`Charts.cs`, `Controls.cs`,
`Rows.cs`, `Lang.cs`, several `Page*.cs`) were read for the audited behaviour
(argument building, result handling) but not every pixel of layout code.

### Checks actually run

| Check | Command | Result |
|---|---|---|
| Engine = build of parts | `python tools/build_engine.py --check` | ✅ 33 parts, 8497 lines, match |
| PowerShell parser | `Parser::ParseFile` over all `.ps1` | ✅ 0 errors |
| PSScriptAnalyzer 1.23.0 | per engine part, Error+Warning | 237 warnings, **0 errors** (78 unused-param false positives from split header, 75 empty-catch, rest style) |
| C# release build | `csc /warn:4 /optimize+` | ✅ exit 0, 1 benign CS0649 |
| SelfTest | `csc /define:SELFTEST` → run | ✅ **64 passed / 0 failed** |
| Translations | `gen_lang.py` + `check_lang.py` | ✅ 1547 pairs, Lang.cs in sync, all translated |
| Version sync | `set_version.py --check` + AppInfo/engine | ✅ 2.0.0 everywhere |
| Python AST | `ast.parse` all `tools/*.py` | ✅ |
| Secret scan | `git log -p --all` regex sweep | ✅ none |
| Determinism | build exe twice, compare SHA | ❌ differ (csc, documented) |
| VM: engine behaviour suite | `engine-tests.ps1` (as admin) | ✅ **551 passed / 0 failed** |
| VM: Pester suite | `engine.Tests.ps1` | ✅ **35 passed / 0 failed** |
| VM: audit probes P1–P3 | guest-audit3.ps1 | F-01/F-04/F-06 confirmed |
| VM: audit probes P4,P6 | guest-audit4.ps1 | F-02/F-03 confirmed |

---

## 4. Findings

### F-08 — Argument injection into the elevated engine via a ConsentStore key name

* **Severity:** HIGH **Confidence:** CONFIRMED (VM)
* **Files:** `PageDossier.cs:268` (`OnSensorToggleAccess`), `EngineRunner.cs:181-198`
  (`EnginePsi` builds a single `psi.Arguments` string),
  `engine/19-dossier-sensors.ps1:93` (`key = $rel`, derived from the HKCU
  ConsentStore child-key name)
* **Description.** The dossier builds the engine command line by raw string
  concatenation, inserting the per-app key between literal quotes with **no
  escaping**:
  ```csharp
  RunJson("-SensorSet -SensorKey \"" + r.Key + "\" -SensorValue " + want, ...);
  ```
  `r.Key` is the ConsentStore relative path `<cap>\<app>` taken from the child-key
  **name** under `HKCU:\…\CapabilityAccessManager\ConsentStore\<cap>`. `EnginePsi`
  then passes this as one flat `psi.Arguments` string to `powershell.exe -File …`
  (the .NET Framework `ProcessStartInfo` has no argv array). A Windows registry
  key name may contain a double-quote. Any program of the user can create, in its
  **own HKCU** (medium integrity, no elevation), a subkey such as:
  ```
  HKCU\…\ConsentStore\webcam\NonPackaged\evil" -XrayWipe "
  ```
  When the user later runs the app elevated (UAC) and clicks the "deny" button on
  that dossier row, the `"` closes the `-SensorKey` value and the remaining tokens
  (`-XrayWipe`, or any other engine switch) are parsed by the engine's `param()`
  block and executed **with administrator rights**. The engine-side `SensorKey`
  validation never gets the chance to reject it, because the injected switch is a
  *separate* parsed argument, not part of the `SensorKey` value.
* **Reproduction (VM, confirmed).** `guest-audit4.ps1` launched the engine exactly
  as the window does (one `ProcessStartInfo.Arguments` string) with
  `-SensorKey "webcam\NonPackaged\x" -XrayStatus "`. The engine returned the
  **`-XrayStatus`** JSON (`{"db":…,"recording":false,…}`) and exit 0 — i.e. the
  injected switch executed instead of `SensorSet`
  (`P5 injected -XrayStatus ran instead of SensorSet: True`). `-XrayStatus` is
  read-only and was chosen deliberately; the identical mechanism reaches
  **destructive** verbs the engine exposes — `-XrayWipe`, `-FootprintWipe
  -WipeItems …`, `-PurgeData`, `-Revert`, `-RemoveGuard`, `-GdidReissue` — all of
  which would then run elevated.
* **Expected vs actual.** Expected: a key value is passed as data and either
  written or rejected by the engine's validation. Actual: a key value containing
  `"` is re-tokenized into additional engine switches that run with admin rights.
* **Impact.** A non-elevated process of the same user can pre-stage a registry key
  so that the next elevated use of the dossier runs an attacker-chosen engine
  action at high integrity — a UAC/elevation boundary bypass limited to the
  engine's own (including destructive) verbs. Not arbitrary code execution (no
  engine switch runs an attacker-named binary), hence HIGH, not CRITICAL. F-02
  (the button always errors) actually makes the bait *more* plausible: the user
  clicks "deny", sees it "fail", and the injected action has already run.
* **Conditions.** User can write their own HKCU (always); dossier is opened and
  the planted row's deny button is clicked while elevated.
* **Fix.** Two independent layers:
  1. **GUI:** reject or percent/caret-escape any `r.Key` that is not a strict
     ConsentStore path (`^[A-Za-z0-9._-]+(\\(NonPackaged\\)?[A-Za-z0-9._#-]+)?$`,
     no `"`), *before* building the command line. Do the same audit for every
     other place the GUI concatenates registry/file-derived data into
     `psi.Arguments` (`-ChangeItems`, `-WipeItems`, `-BackupPath`, `-AppPath`,
     `-SnapshotDiff`).
  2. **Engine:** have `-SensorSet` accept the full ConsentStore path shape (fixing
     F-02 at the same time) and reject control/quote characters — so even a
     mis-passed value cannot select an unintended target.
* **Regression test.** A SpyRow key of `x" -XrayStatus "` must make the engine
  run `SensorSet` (and fail validation), **never** `-XrayStatus`; assert the
  returned JSON has the `key`/`error` shape, not the XrayStatus shape.
* **Related:** F-02 (same `r.Key` field; the engine-side fix overlaps).

### F-01 — Backup signing TOCTOU: a file added before signing is signed and imported

* **Severity:** MEDIUM **Confidence:** CONFIRMED (VM)
* **Files:** `engine/04-backup.ps1:117-131` (`Ensure-Backup`), `engine/23-backups.ps1:39-75` (`Restore-BackupFolder`)
* **Description.** `Ensure-Backup` exports each registry branch to the backup
  folder, then signs **whatever `*.reg` files are in the folder at that moment**:
  ```
  foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Filter '*.reg')) {
      $sigs[$f.Name] = Get-BackupFileSig $f.FullName (Split-Path $dir -Leaf) $f.Name -Create
  }
  ```
  The export loop runs branch by branch (each `reg.exe export` is a separate
  process; on the VM the whole loop took ~tens of seconds). Any process that can
  write into the backup folder during that window can drop an extra `.reg`
  file; it then lands in `backup-sig.json` with a valid signature. On
  `-RestoreBackup`, `Restore-BackupFolder` copies it into the protected folder,
  the signature **matches** (it was signed with the real journal key), and
  `reg.exe import` runs it **as administrator**.
* **Reproduction (VM, confirmed).** `guest-audit3.ps1` started an apply with a
  backup, a second process waited for the `Win11Privacy-Backup-*` folder and
  dropped `zz-probe.reg` (a marker key) into it. Result:
  `P1a planted file signed: True`, `restore ... restored 15, refused 0`,
  `P1b marker key imported into HKLM: True`.
* **Expected vs actual.** `docs/security-model.md` (English "Backups",
  lines 209-216) states: *"A changed, added or unsigned file is not imported."*
  An **added** file *is* imported if it was added before signing. The guarantee
  holds only for files added after the backup is complete.
* **Impact.** A local process able to write the backup folder (the elevated
  Desktop, or the portable folder in `-DataRoot` mode) and to win the export
  race can get an arbitrary registry key written with admin rights — but only if
  the user later clicks "restore from backup" on that specific backup. Constrained
  (no persistence, no silent trigger), hence MEDIUM, not HIGH. The project's own
  threat model already treats "a program able to write that folder during the
  window" as in scope for the folder-rename case (known-limitations list).
* **Fix.** Sign only the files the engine itself exported in this run (track the
  names it wrote), not the result of a fresh `Get-ChildItem`; or build the
  signed set from the exact export list and refuse any extra `.reg` present.
* **Regression test.** Extend `guest-backup.ps1`: during apply, drop a `.reg`
  into the folder; assert it is **not** in `backup-sig.json` and is refused on
  restore.
* **Related:** the documented folder-rename race (known-limitations §).

### F-02 — Per-app sensor deny never works (input rejected by the engine)

* **Severity:** MEDIUM **Confidence:** CONFIRMED (VM pending; static certain)
* **Files:** `PageDossier.cs:262-288` (`OnSensorToggleAccess`),
  `engine/19-dossier-sensors.ps1:93-96` (`Get-SpyReport` produces `key`),
  `engine/20-dossier-footprint.ps1:213-231` (`SensorSet`)
* **Description.** The dossier shows a per-program "deny / allow" button for
  camera, microphone and location. The key it sends is the ConsentStore relative
  path produced by `Get-SpyReport`:
  `$rel = ($k.PSPath -replace '^.*\\ConsentStore\\', '')` — e.g.
  `webcam\Microsoft.WindowsCamera_8wekyb3d8bbwe` or
  `webcam\NonPackaged\C:#Windows#...`. The GUI passes it verbatim:
  `"-SensorSet -SensorKey \"" + r.Key + "\" -SensorValue " + want`. The engine
  validates:
  ```
  if ($SensorKey -notmatch '^[A-Za-z0-9_]{1,64}$' ...) { $r.error = 'недопустимое имя датчика'; exit 1 }
  ```
  Every real per-app key contains a backslash (and often `:`/`#`/length > 64),
  so the regex **always rejects it**. The feature returns an error dialog
  ("Не удалось изменить доступ") in 100% of cases.
* **Expected vs actual.** Expected: clicking "deny" writes
  `ConsentStore\<cap>\<app>\Value = Deny`. Actual: validation fails; nothing is
  written; the user sees a warning dialog. The global/per-capability path the
  regex was written for (bare `webcam`) is never sent by the UI.
* **Impact.** A visible, documented privacy control silently does not function.
  No security impact (it fails closed), but it misleads the user into thinking
  per-app denial is available.
* **Fix.** Validate the full ConsentStore relative path instead: allow one or two
  path segments of `[A-Za-z0-9._\-]` plus optional `NonPackaged\<encoded exe>`,
  reject `..`, control chars and absolute roots, and build `$root` from the
  validated segments. Or have the GUI send capability + app separately.
* **Regression test.** `-SensorSet -SensorKey "webcam\Microsoft.WindowsCamera_8wekyb3d8bbwe" -SensorValue Deny`
  must succeed and set the value; a key with `..` or control chars must be
  refused.

### F-03 — Per-app network block keyed by file name only (collisions)

* **Severity:** MEDIUM **Confidence:** CONFIRMED (VM pending; static certain)
* **Files:** `engine/10-apply-check.ps1:606` (`Get-FwRuleName`), `:608-626`
  (`Test-FwRule`/`Apply-FwRule`), `engine/13-detect-monitor-guard.ps1:48-66`
  (`BlockApp`/`UnblockApp`)
* **Description.** The firewall rule name for an app block is the **leaf file
  name only**:
  ```
  function Get-FwRuleName { ... return ("Win11Privacy: " + (Split-Path $Target -Leaf)) }
  ```
  `Apply-FwRule` short-circuits on an existing display name
  (`if (Get-NetFirewallRule -DisplayName $name) { "уже есть"; return }`), and
  `Test-FwRule` checks existence by display name. So for two different programs
  with the same exe name (`C:\a\tool.exe` and `C:\b\tool.exe`):
  - blocking the first creates a rule targeting `C:\a\tool.exe`;
  - blocking the second finds the name already present → creates **no** rule, yet
    `Emit-Json @{ blocked = (Test-FwRule 'app' $AppPath) }` returns `blocked=true`
    (the name exists), so the UI reports success;
  - `C:\b\tool.exe` is **not actually blocked**;
  - `-UnblockApp` on either removes the single shared rule (the first program's).
* **Impact.** Silent failure of a security control and a confusing unblock. The
  user believes program B is blocked when only A is, or unblocks A while meaning B.
* **Fix.** Include a hash of the full program path in the rule name (and store the
  path), or set the rule's `-Program` as the identity and check by program path,
  not display name.
* **Regression test.** Block two same-named exes in different folders; assert two
  distinct rules each with the right `-Program`, and that unblocking one leaves
  the other.

### F-04 — `-RestoreAll` reports success on an untrusted/empty journal

* **Severity:** LOW **Confidence:** CONFIRMED (VM)
* **Files:** `engine/30-data.ps1:99-106` (`RestoreAll`), `PageChanges.cs:153-158`
  (`OnRestoreAll` → `RunStreaming`), `EngineRunner.cs:238-249` (exit→status map)
* **Description.** `-RestoreAll` calls `Restore-Journal` (which increments
  `$script:Failures` and returns `state='untrusted'` when the journal can't be
  trusted) but then unconditionally `exit 0`. `RunStreaming` maps exit 0 to
  "Готово." The main `-Revert` path does this correctly (`exit 2` on failures);
  `-RestoreAll` does not.
* **Reproduction (VM, confirmed).** Planted an invalid `changes.json`;
  `P2 RestoreAll exit 0, state untrusted, restored 0`. The engine prints the
  "журналу нельзя верить" line to the log, but the final status and exit code say
  success.
* **Impact.** Honesty regression only: the log shows the red line, but the status
  bar/green "Готово." contradicts it. Inconsistent with the project's own
  honest-exit-code principle.
* **Fix.** `exit $(if ($r.state -eq 'untrusted' -or $script:Failures -gt 0) { 2 } else { 0 })`.
* **Regression test.** `-RestoreAll` over an untrusted journal must exit non-zero.

### F-05 — Guard/watch install commands report success on failure

* **Severity:** LOW **Confidence:** CONFIRMED (static)
* **Files:** `engine/14-startup.ps1:362-399` (`InstallGuard`),
  `engine/21-sensor-watch.ps1` (`InstallSensorGuard`/`InstallNetGuard`),
  `engine/18-live-notify.ps1:7-30` (`InstallWatcher`)
* **Description.** Each wraps `Register-ScheduledTask` in `try { … } catch {
  Write-Log "[!] не удалось…" }` and then `exit 0` unconditionally. On a real
  failure (e.g. a non-admin elevation account that cannot register an S4U/Highest
  task — a case the memory notes actually occurs) the window still shows
  "Готово." The error is visible in the log text, but the status line and exit
  code claim success.
* **Impact.** The user may believe the guard is protecting them when registration
  failed. Low, because the log line is visible on the same screen.
* **Fix.** Set a failure flag in the catch and `exit 1`/`2`; let the GUI show
  "Завершено с ошибкой."
* **Regression test.** Stub `Register-ScheduledTask` to throw; assert the command
  exits non-zero.

### F-06 — Fresh quarantine folder inherits the ProgramData ACL

* **Severity:** INFO **Confidence:** CONFIRMED (VM)
* **Files:** `engine/03-datafolder.ps1:72-85` (`New-QuarantineDir`),
  `Engine.cs:157-172` (`FreshQuarantine`)
* **Description.** `New-QuarantineDir` creates `<root>.untrusted-<time>-<rnd>`
  with `[IO.Directory]::CreateDirectory($cand)` — i.e. inheriting ProgramData's
  ACL, where **Users may create files and folders**. VM output:
  `protected: False`, `BUILTIN\Users … Write (CI)`,
  `P3 Users may create subfolders in the quarantine folder: True`.
* **Why it is only INFO.** The folder name carries an 8-hex random suffix (not
  predictable), it is checked not to be a reparse point right after creation, the
  moved-in items keep their own (untrusted) ACLs, and nothing reads the quarantine
  back as trusted. So a non-admin writing into it gains nothing. It is a
  defense-in-depth gap, not a vulnerability.
* **Fix (optional).** Create the quarantine folder with an explicit admins-only,
  protected ACL (as `Protect-DataRoot` does for the data root).

### F-07 — Empty catch blocks swallow unexpected errors

* **Severity:** INFO **Confidence:** CONFIRMED
* **Detail.** PSScriptAnalyzer flags 75 `catch {}` in the engine. Most are
  deliberate (best-effort reads, "determine if we can, else null"). A few on read
  paths (`Get-SpyReport`, footprint, timeline) turn an unexpected error into
  "nothing found", which `docs/security-model.md` acknowledges for read-only
  pages. No change-making path does this (those are all verify-after-write).
  Recommend narrowing the broad ones to the expected exception types over time.

---

## 5. Component reviews

### PowerShell engine
Idiomatic and PS 5.1-aware (the code and the memory both document the real
5.1 traps: `@($list)` over `List[object]`, `ConvertFrom-Json` single-object
arrays, case-insensitive variable names clobbering parameters, empty-array →
`$null` return, `Remove-Item -Recurse` following junctions). Registry existence
is decided via the raw API (`Get-RegRaw`/`Open-RegKeyRead`), correctly
distinguishing "no key" from "access denied". No `Invoke-Expression` on
untrusted input, no string-built reg paths from journal data without
shape-checks. Native commands run by full path without `cmd.exe`; `cmd` lines
forbid `%` and newlines. Injection surface is well contained **inside** the engine (no `Invoke-Expression`
on untrusted input, native commands by full path, `cmd` lines forbid `%`/newlines).
The one real injection is at the **GUI→engine boundary** (F-08): the command line
is a single concatenated `psi.Arguments` string, and a registry-derived value with
a `"` re-tokenizes into engine switches. The engine's own `SensorSet` validation is
sound but runs too late to stop it.

### C# GUI
Correct UI threading (`BeginInvoke` from engine-output threads), per-run tracking
so "Stop"/close kill the right process and settle busy state correctly, resource
disposal on process exit, SHA-256 verification of the extracted engine before
and after write, admin-only ACL on the engine folder with a fresh-quarantine
path for a pre-planted root, full-path `powershell.exe`, and env hardening
mirroring the engine. `EngineWrites()` correctly classifies read vs write
commands. The one honesty gap is that exit-code→status mapping trusts the
engine's code, which F-04/F-05 under-report.

### Windows integration
Edition-aware (`Get-Edition`, `OsBuild` gating via `Min`), task "disabled" read
from `Settings.Enabled` not `State`, service firewall rules valid (the targeted
services have a service SID — verified `sc qsidtype`: UNRESTRICTED, so
`-Service` WFP rules bind), hive mount/unmount with stale-mount cleanup keyed by
PID, SYSTEM one-shot tasks checked by SID before start and removed after. The
GDID wipe verifies emptiness after each step and restores services. Strong.

### Privacy effectiveness
Honest where it matters: Home/Pro telemetry floor stated, Tamper Protection
warned (`Test-TamperProtection` → MAPS may be ignored), `hosts` vs DoH vs
firewall-by-IP separated, shared-endpoint names kept out of IP rules, the leak
test labelled "endpoint reachability, not traffic observed". The definition set
is large and researched (24H2/25H2 tasks, ECS, Click-to-Do model caching). It
correctly does **not** claim total telemetry elimination. Some values target
undocumented stores (`PolicyManager\default`, `MaxTelemetryAllowed` under
`Policies`) — acknowledged in the limitations.

### Build & supply chain
Engine build is deterministic and `--check`-gated in CI; `build_engine.py`'s
comparison is BOM/line-ending-insensitive, but CI *also* compares the exe's
embedded resource SHA to the committed CRLF+BOM file, closing the loop. Actions
pinned by commit SHA (verified by the team against the GitHub API per the memory).
`release` job is tag-only with least privilege on `build`. winget submit ticks
the "validated" box only if `winget validate` actually ran. exe is not
reproducible (csc) and not Authenticode-signed — both documented; provenance
attestation is present.

### Test coverage
Real strengths: live apply→verify→revert round trip in CI, crash-consistency
tests that kill a real child PowerShell at each boundary, a second-writer journal
stress test, and a broad VM harness (data-folder trust, hives, firewall, backups,
one-shot SYSTEM tasks, GDID). **Gaps that would have caught this audit's
findings:** no test passes a quote-bearing key through the GUI→engine boundary
(F-08); no test asserts a file added to the backup folder is refused (F-01); no
test exercises `SensorSet` with a real ConsentStore key (F-02); no test blocks
two same-named exes (F-03); no test asserts `-RestoreAll` exit code on an
untrusted journal (F-04). The engine's own argument surface is tested, but no
test models the *GUI* command-string construction, which is where F-08 lives.

### Compatibility
Windows 11 Home/Pro/Enterprise/Education, PS 5.1 FullLanguage, 64-bit;
ConstrainedLanguage exits cleanly. CI round trip runs on `windows-latest`
(Server, not 11) and only part of the modules; Pro/Enterprise and PS 7 are
untested (PS 7 is not used). Localized Windows handled (audit CSV by column
position, SIDs not names).

---

## 6. False positives considered and dismissed

* **Service firewall rules ineffective** — dismissed: `DiagTrack`,
  `dmwappushservice`, `WerSvc`, `wlidsvc` all report `SERVICE_SID_TYPE:
  UNRESTRICTED`, so they have a service SID and `New-NetFirewallRule -Service`
  binds correctly.
* **Engine `--check` ignores BOM/CRLF, so a tampered committed engine passes** —
  dismissed: CI separately verifies the exe's embedded resource SHA equals the
  committed file bytes, and the version-sync step compares strings.
* **PSModulePath / profiler-env hijack** — dismissed: thoroughly handled in the
  header and `EngineFile.Harden`, with a dedicated test.
* **Journal forgery / replay** — HMAC + shape-check + known-entry filter in
  portable mode; replay in portable mode is acknowledged and limited to genuine
  records.

---

## 7. Remediation priority

**P0 (fix immediately):**
* F-08 — stop the argument injection: validate/escape `r.Key` (and every other
  registry/file-derived value concatenated into `psi.Arguments`) in the GUI, and
  tighten `-SensorSet` key validation in the engine. Cheap, high value.

**P1 (before next release):**
* F-01 — sign only the engine's own exported files.
* F-02 — accept the real ConsentStore key format in `SensorSet` (shares the
  engine-side fix with F-08).
* F-03 — make app firewall rules identify the full program path.

**P2 (important):**
* F-04, F-05 — return honest non-zero exit codes; let the window show failure.
* Add the four missing regression tests listed above.

**P3 (long term):**
* F-06 — explicit admins-only ACL on the quarantine folder.
* F-07 — narrow broad `catch {}` to expected exception types on read paths.
* Consider an Authenticode certificate; expand the CI round trip to more modules.

---

## 8. Unresolved / not executed

* F-02, F-03 and F-08 were confirmed on the VM (`guest-audit4.ps1`): per-app
  sensor deny returned "недопустимое имя датчика" (F-02); two same-named exes
  produced one rule pointing at the first program, with the second reporting
  `blocked:true` and unblocking the second removing the first's rule (F-03);
  and `-SensorKey "…x" -XrayStatus "` executed `-XrayStatus` (F-08).
* Destructive engine verbs were **not** fired through F-08 (only read-only
  `-XrayStatus`); their reachability is inferred from the identical parsing
  mechanism, not separately executed, to avoid destructive actions.
* Pro/Enterprise behaviour and PS 7 remain untested by design.
* Power loss during NTFS metadata updates beyond ReplaceFile, and a kill during
  `reg.exe load/unload`, remain unproven (acknowledged by the project).

---

*Audit performed read-only against the local repository; no source was modified
and no privacy settings were applied to the host. Live checks ran in a disposable
Windows 11 VM.*
