# Win11Privacy — security remediation report

This file holds two passes. The newest comes first:

* **Pass of 2026-11-16 — T-1 … T-4 and GDID hardening** (this section).
* Pass of 2026-11-15 — W11P-001 … W11P-003, R-1 … R-4 (further below, unchanged).

---

# Pass of 2026-11-16: T-1 … T-4 and GDID hardening

Repository: Win11Privacy, branch `main`, base `HEAD` = `700d84e`, plus the
uncommitted working tree of this pass. Date: 2026-11-16. Nothing was committed,
pushed, tagged or released.

The brief listed three open items of `FINAL_SECURITY_AUDIT.md` (T-1, T-2, T-3) and
asked for a GDID re-check and a targeted review. Every item was checked against
the code first, not against the earlier reports. One new defect was found while
verifying (T-4) and is fixed here as well.

Statuses: **FIXED** — code changed and the regression tests were run and passed;
**FIXED, residual** — the defect is fixed and a documented, lower risk remains;
**NOT VERIFIED** — changed but the required test could not be run.

## Summary

| ID | Severity | Root cause | Fix | Verification |
|---|---|---|---|---|
| T-1 | LOW (DoS); the owner check was bypassable | An elevated engine trusted a lock whose owner was its own user SID — the same SID every non-elevated program of that user has — and created new locks granting that SID full control. Existing locks' DACLs were not checked. The window treated any object on its name as "already running". | Trusted owners: SYSTEM, Administrators (own SID only without elevation). New locks: owner Administrators, DACL SYSTEM + Administrators only. Existing locks: owner **and** every Allow ACE checked; NULL DACL, other object type, no READ_CONTROL → refused. Check runs on the handle that is waited on. The window starts when its name is squatted. | FIXED, residual (squatting DoS) — host tests, SelfTest, VM (LOCAL SERVICE squatter, SYSTEM ↔ admin) |
| T-2 | LOW | `Get-AuditSetting` wrote the `auditpol /backup` CSV into the user's `%TEMP%` while the protected root did not exist, and used an existing root without checking it. A user process could swap the CSV (monitor status, journal "before" value) or replace `%TEMP%` with a junction. | `New-PrivateWorkDir`: fresh random folder with an explicit SYSTEM + Administrators DACL (owner Administrators) in the protected root (only if `Test-PathTrusted`) or `Windows\Temp` (only if `Test-DirChainSecure`); verified after creation. `Read-PrivateWorkFile`: exactly one regular, recent, admin-owned file, read once without write sharing. No place → `-1`, auditpol not called. | FIXED — host tests (9 tamper cases), VM (real auditpol, LOCAL SERVICE probe) |
| T-3 | LOW → crash-safe recovery | `reg.exe import` is not transactional; a killed restore left an unknown partial state, nothing recorded it, success was "reg.exe exit 0" without verification, two restores could run at once. | Restore lock; signed progress record `op-restore.json` (Prepared / InProgress / Restored / PartiallyRestored / Failed, `RecoveryRequired` for the next run); snapshot of the same branches before the first import (mandatory); per-file stage written before reg.exe; verification by re-export after each file; exit 0 / 2 / 1; window notice; no automatic repeat. | FIXED, residual (merge semantics of reg import) — host tests with real reg.exe and real process kills at 3 stages, VM (real engine killed mid-import) |
| T-4 | MEDIUM | On Windows PowerShell 5.1 a `catch [DirectoryNotFoundException]` clause starts receiving "file in use by another process" (an `IOException` wrapped in `MethodInvocationException`) once the code has run a few dozen times (reproduced: the 18th retry; a function called 60 times misrouted 7 times). `Read-TextShared` then returned "no such file". Users can open `changes.json` for reading without sharing → the elevated engine saw "no journal": rollback said "nothing to restore", and the next journal write replaced the history with only the new entries. | Error kinds decided from the .NET exception (`GetBaseException()`, `Test-IoBusy`, `Test-IoMissing`) in `Read-TextShared`, `Replace-FileAtomic`, `Use-JournalLock`, `Enter-OpLock`, `Read-OpRecord`, `Open-ProgramMutex`, the Firefox lock wait. No typed catch of `FileNotFound`/`DirectoryNotFound` remains in the engine. | FIXED, residual (holding the file blocks writes = DoS) — host test reproduces the old behaviour on this PowerShell build and proves the fix end to end |
| GDID-A | MEDIUM | `Get-SessionUser` took the owner of *any* `explorer.exe` on the machine. With two signed-in users the user tasks (`Invoke-AsUser`), the CDP cache cleanup and HKCU settings could go to the other user; a WMI failure was silently "the engine itself is at the computer". Entra ID owners (`S-1-12-1-…`) were ignored. | `explorer.exe` of the engine's own session only; Entra ID accepted; a WMI failure is recorded (`$script:SessionUserError`) and blocks the wipe in `Get-GdidPreflight`. | FIXED — host tests (stubs). Live two-user test: NOT VERIFIED |
| GDID-B | LOW | Credential checks read a failed `cmdkey /list` as "nothing left" (task check command and the engine's own store). `Get-GdidCredUsers` skipped Entra ID hives. | Check command exits 2 when the listing fails; the own-store check needs exit code 0; Entra ID hives included. | FIXED — host tests (real cmd.exe with a fake cmdkey) |
| GDID-C | MEDIUM (availability) | The wipe stopped services and kept the "running before" list only in memory: a killed wipe left CDPSvc etc. stopped until a reboot, and a new wipe saw them stopped and did not start them. | Wipe lock + signed record `op-gdid-wipe.json` written before the first change; removed when the services are back; `GdidRestore` starts the recorded services (stage `interruptedWipe`), the next wipe carries them; status shows `interruptedWipe` (window row "Wipe interrupted"). | FIXED — host tests (process killed at 8 stages), VM (real wipe killed after CDPSvc stopped) |

## T-1 — Global mutex squatting

**What was vulnerable.** `Global\Win11Privacy-FirefoxPolicies` (engine,
`Open-FirefoxMutex`) and `Global\Win11Privacy-App` (window, `SingleInstance.Take`).

* Owner check bypass: `Test-MutexOwnerTrusted` accepted the current user's SID.
  For an elevated engine that SID is shared by every medium-integrity program of
  the same user, which can create the mutex first (owner = user SID) — it passed.
* Weak DACL on the program's own lock: the new lock granted `FullControl` to the
  current user's SID, so a non-elevated program of the same user could open the
  real lock, take and hold it, or rewrite its DACL (`WRITE_DAC`) to lock SYSTEM out.
* No DACL check of an existing lock with a trusted owner.
* The window: any object under its name (another user's mutex, an event, an
  inaccessible mutex) made it quit silently as "already running".

**Impact classification.** Denial of service and loss of the Firefox lock's
integrity guarantee (a held lock blocks writers; no lost-update was possible
because all writers still used the same object). No privilege escalation was
found or claimed: the lock only orders read-modify-write of `policies.json`, and
the data written never comes from the lock holder.

**Fix** (`engine/09-thirdparty.ps1`: `Get-MutexTrustedSids`,
`Test-MutexOwnerTrusted`, `Get-MutexSecurityProblem`, `New-ProgramMutexSecurity`,
`Open-ProgramMutex`, `Open-FirefoxMutex`, wait in `Update-FirefoxPoliciesFile`;
`SingleInstance.cs`: `Take(name)`, `TrustedSids`, `NewSecurity`, `Problem`):
trusted = SYSTEM, Administrators (+ own SID only without elevation); new lock
owner Administrators (fallback to the default owner if Windows refuses), DACL
SYSTEM + Administrators; an existing lock must have a trusted owner and no Allow
ACE for anyone else beyond `READ_CONTROL | MUTANT_QUERY_STATE`; no READ_CONTROL on
the handle, NULL DACL, other object type, access denied → refused. The handle
checked is the handle waited on (no reopen by name). The window opens when its
name is squatted (`SingleInstance.Squatted`); the engine's locks keep the data safe.

**Not fixed (residual, LOW):** anyone can still pre-create the names: Firefox
policy writes are refused while the squatter lives; the window cannot detect a
second window meanwhile; Inno Setup's `AppMutex` check can be blocked the same way.
A lock in the protected data folder would avoid the squatting but would split the
domain between installations with different data roots (the W11P-007 problem).

## T-2 — audit policy temp file

**What was vulnerable.** `Get-AuditSetting` (`engine/12-gdid.ps1`): CSV in
`[IO.Path]::GetTempPath()` when `$script:SafeRoot` did not exist, and in the root
when it merely existed (no trust check). A user program could replace the CSV
between write and read (monitor state; the journal's "before" value for the audit
policy), plant a junction for `%TEMP%` (auditpol as administrator creates a file in
the target), or read the policy.

**Fix** (`engine/03-datafolder.ps1`: `New-PrivateWorkDir`, `Remove-StalePrivateDirs`,
`Read-PrivateWorkFile`, `Remove-PrivateWorkDir`; `engine/12-gdid.ps1`:
`Get-AuditSetting`): see the summary table. Only SYSTEM and Administrators can
list, create, link or rename inside the private folder, so the CSV cannot be
swapped, linked (junction, symbolic or hard link) or partially overwritten; the
file must be the only entry, a regular file, created after the call started,
owned by Administrators, ≤ 4 MB; it is read once from a handle without write
sharing. `finally` removes the folder without following links; folders left by a
killed run (protected) are removed after an hour, only with a trusted owner and
never through a link. Value must be 0…3 (empty → 0 as before), otherwise `-1`.

**Residual:** the file's hard-link count is not read (.NET Framework has no API
without P/Invoke); a hard link would need write access to the private folder,
which the LOCAL SERVICE probe in the VM confirmed is denied.

## T-3 — non-transactional registry import

**What could leave a partial restore.** `reg.exe import` per file (stops or is
killed mid-file), the engine killed between files, power loss, a concurrent second
restore, and "exit 0 but the value is not what the backup says".

**Fix** (`engine/23-backups.ps1`: `ConvertFrom-RegExportText`, `Get-RegFileBranch`,
`ConvertTo-PsRegPath`, `Test-RegImported`, `Get-RestoreRecovery`,
`Restore-BackupFolder`, `-RestoreBackup`, `-ListBackups`; `engine/05-journal.ps1`:
`Write-OpRecord`, `Read-OpRecord`, `Remove-OpRecord`, `Set-OpRecordAside`,
`Enter-OpLock`, `Test-OpRunning`, `Open-JournalLockFile -Path`; window
`PageChanges.cs`): no imitation of a transaction — a crash-safe record of where
the restore is, built on the journal's primitives (signed with the journal key and
its own prefix, written by `Save-Json` under the journal lock, separate file so
that a full rollback never "executes" it and older versions do not set the journal
aside). States as in the summary; the record is written before every import, and
the next run turns a dead `InProgress` (lock free) into `RecoveryRequired`. The
backup manifest format is unchanged (v1 legacy and v2 backups restore as before;
the snapshot is an ordinary v2 backup).

**Residual:** `reg.exe import` merges — values absent from the backup stay, and
the snapshot cannot express "this value did not exist", so returning to the
snapshot leaves values the import added (documented). A killed restore leaves its
protected `restore-*` work folder for an hour. Power loss beyond what
`ReplaceFile` guarantees is not proven.

## T-4 — busy file read as missing (new)

**Found** while testing T-3: a held `op-restore.json` was read as "no record".
Reproduced in isolation on this host (Windows PowerShell 5.1.26100): a loop with
`catch [FileNotFoundException] … catch [DirectoryNotFoundException] … catch
[IOException] { sleep }` sends the sharing violation to the
`DirectoryNotFoundException` clause on the 18th pass, and a function with such
clauses called 60 times misroutes 7 of them. `catch [UnauthorizedAccessException]`
and cmdlet errors (`ItemNotFoundException`) did not misroute in the same probe.

**Impact.** Users have read access to the data folder, so any process of the user
could hold `changes.json` open without sharing: `Read-JournalFile` then answered
`none` (trusted, empty) instead of `unreadable`, `-RestoreAll` reported nothing to
restore, and the next `Save-JournalEntries` (once the file was released for the
replace) wrote a journal with only the new entries — the undo history was lost.
The same function reads `profile.json` and the other data files.

**Fix:** see the summary table (`engine/03-datafolder.ps1`, `05-journal.ps1`,
`09-thirdparty.ps1`).

**Residual (LOW, DoS):** while a user process holds the file, the engine refuses to
write the journal (or the progress records) — it no longer loses anything. Removing
"Users: read" from the data files would close this too but needs a review of every
non-elevated reader; left as a documented limitation.

## GDID hardening

Checked against the brief (A–E). Files: `engine/07-system.ps1` (`Get-SessionUser`),
`engine/12-gdid.ps1` (`Get-CredCheckCmd`, `Get-GdidCredUsers`,
`Clear-GdidUserCreds`, `Get-GdidPreflight`, `Get-GdidWipeRecovery`,
`Test-GdidWipeSvcName`, `Restore-GdidInterruptedWipe`, `Invoke-GdidWipe`,
`Get-GdidStatus`), `engine/29-gdid-commands.ps1` (`-GdidRestore` stage
`interruptedWipe`), `PageGdid.cs`.

* **A. Credential store and UAC** (user A at the desk, administrator B's password):
  the engine runs as B; B's own store is cleaned by B's own `cmdkey` (now verified
  with the exit code), A's store by a one-shot task registered for A's SID and
  verified by SID before it starts (`Test-OneShotTaskMine`); other signed-in users
  get their own task. Targets are the two constants in `$script:GdidCredUser`
  (one in `$script:GdidCredSystem` for SYSTEM) — no other credential is touched.
  The session-filter bug (GDID-A) was the way A's and another user C's contexts
  could mix. An access error is never "no credentials" (GDID-B).
* **B. IdentityCRL**: re-checked; the inventory/deletion of the third pass is
  unchanged (exact records, `Logs` and unknown keys kept, each deletion re-read).
  Repeated runs are idempotent (`absent`), an incomplete deletion is `Partial`.
* **C. Services**: registry start type, SCM start type, runtime state and the
  per-user `CDPUserSvc_*` instances are distinct in `Get-GdidSvcEntry`; restore
  after a reboot (G3-17) unchanged. New: recovery of the running state after a
  killed wipe (GDID-C).
* **D. Unloaded profiles**: still never mounted; any unloaded profile or an
  unreadable profile list keeps the result `Unverified`, never `Clean` (re-run:
  existing tests "профили не в Windows…", "GDID3 11").
* **E. Crash at every stage** (host test, a child process killed with
  `[Environment]::Exit` inside each stage): preflight → no record, nothing changed;
  wlidsvc / stop / credentials / IdentityCRL / verify / service restore / final
  cleanup → record present with the services that were running, lock free, status
  `RecoveryRequired`; `GdidRestore` starts them, the next wipe carries them. wlidsvc's
  start type comes back through the journal (unchanged design). A one-shot task
  being run at the moment of the kill stays registered (random name, no trigger) —
  residual, see `FINAL_SECURITY_AUDIT.md`.

## Tests added

All new checks are in `tests/engine-remediation.ps1`, run by `tests/engine-tests.ps1`
(and therefore by CI): T-1 (13 SDDL owner/DACL cases, free name, second process
waits, 5 processes racing, squatters: Everyone DACL, user-owned under elevation,
Firefox name, event object, empty DACL; admin-only: Administrators-owned with a
Users ACE), T-2 (9 tamper cases incl. junction, extra file, old file, 5 MB file,
bad values; no protected place → no auditpol call; admin-only: ACL of the private
folder, Windows\Temp fallback, stale cleanup with a junction), T-3 (real reg.exe:
restore + snapshot, ineffective import, resume, unverifiable, snapshot failure,
record failure at start and after the first file, busy lock, tampered record,
unreadable record, process killed after Prepared / inside the first import / after
the first file), T-4 (old pattern reproduced, new function on a held file 5×,
missing file/folder, end-to-end held `changes.json`), GDID (session filter, Entra
ID, WMI failure blocks the wipe, credential users, check command with a fake
cmdkey, own-store listing failure, interrupted-wipe record, restart, failure,
"Settled", carry-over into the next wipe, record before first change, record
failure, busy wipe lock, process killed at 8 stages). `SelfTest.cs`: 15 window-lock
checks. Old harnesses in `tests/engine-tests.ps1` got the new helper functions and
stubs; three checks that pinned the old behaviour were changed to the new rule
(own SID trusted only without elevation; restore exit code by state; credential
check command).

## Test results

All numbers come from runs made on 2026-11-16 with the final tree (engine rebuilt from
`engine/`, `build_engine.py --check` passes). Nothing was estimated; failed runs are
listed as such.

| Suite | Where / identity | Result |
|---|---|---|
| `tests/engine-tests.ps1` incl. `engine-remediation.ps1`, final run | host, standard user, Windows PowerShell 5.1.26100 | **879 passed, 0 failed**; 5 blocks skipped with a note (data-folder protection, ACL on disk as administrator, file symbolic link, and the admin-only parts of the T-1 and T-2 checks) — they run in the VM |
| same, earlier runs | host | run 1 (new engine, old harnesses): 682 passed, 69 failed — the old harnesses extract engine functions by name and did not know the new helpers, three checks pinned the old behaviour; the script stopped in the Firefox section. Harnesses fixed (no check removed). Run 2: 879/0 before the last two edits (`Open-ProgramMutex`, `Read-OpRecord` catch handling); run 3 above. `engine-remediation.ps1` alone: first 64/2 (one was T-4 itself, found here; one wrong expectation of 2 left work folders instead of 3), then 74/0 |
| `tests/engine-tests.ps1` (full) | VM, administrator, after revert to the clean snapshot | **890 passed, 0 failed, nothing skipped** (admin branches of T-1, T-2 included; T-4's old pattern reproduces on the guest's PowerShell too) |
| `tests/engine.Tests.ps1` (Pester 3.4.0) | host / VM | **44 / 0** and **44 / 0** |
| SelfTest (`/define:SELFTEST`, real engine via `WIN11_TEST_ENGINE`) | host (standard user) / VM (administrator) | **140 / 0** and **140 / 0** (15 new window-lock checks) |
| Live checks `guest-remed4.ps1` (real engine requests, auditpol, reg.exe, services, SYSTEM and LOCAL SERVICE tasks) | VM, administrator | **28 passed, 1 failed**. The failure was the harness: the admin held the Firefox lock for a fixed 8 s, and the SYSTEM task started after that, so it got the lock at once. Re-checked with a start handshake (`guest-remed4b.ps1`): **3 / 3** — the SYSTEM writer opens the admin's lock as the program's own and waits 6 s each time. The harness is fixed for future runs. |
| Static / build | host | `build_engine.py --check` OK; PowerShell parser: engine and both test files 0 errors; `gen_lang.py` + `check_lang.py` all translated; `set_version.py --check` OK; `release_notes.py --version 2.1.0` OK; `py_compile tools/*.py` OK; `csc` release, `SELFTEST`, `UITEST` with `/warn:4` OK |

Live checks in the VM covered: SYSTEM-created lock opened and waited on by the admin
engine (owner Administrators); LOCAL SERVICE pre-creating both lock names with an
open DACL → Firefox write refused within seconds, file untouched; the window's real
code (`SingleInstance` from the built exe) starts with the squatted name and reports it,
and detects a real second instance; the lock works again after the squatter exits;
real `auditpol` read through the private folder (with and without the protected root,
nothing left in `Windows\Temp`); LOCAL SERVICE denied list, read, overwrite, create,
mkdir, junction, hard link, rename and delete in the private folder; real restore
(17 files) exit 0 and verified, snapshot in the store, no record left; engine killed
mid-import → ListBackups `RecoveryRequired` → repeat exit 0, `resumed`, snapshot of the
interrupted attempt kept, record removed; restore lock held → exit 1, nothing imported;
real `GdidReissue` killed after CDPSvc stopped → status `RecoveryRequired` with CDPSvc →
`GdidRestore` starts CDPSvc, clears the record, wlidsvc's start type back from the
journal; killed again → the next complete wipe restarts CDPSvc. No one-shot task was
left behind by the kills in this run.

## Not run / needs manual testing

* **PSScriptAnalyzer** — not run: loading the saved Microsoft-signed copy from another
  session's folder was refused by this session's permission rules.
* **UI text-fit scan** (`UITEST` pages) — not run; the build compiles. The new UI (the
  restore notice, the "Wipe interrupted" row) appears only with data the mocks do not
  produce.
* **`tests/installer-tests.ps1`** — not run (changes the system; VM/CI only). The
  installer script is unchanged; only the exe changed.
* **`tests/roundtrip.ps1`** and the **GitHub Actions workflow** — not run (CI only;
  nothing was pushed).
* **Needs manual / special-environment testing:**
  two users signed in at once (fast user switching) and real over-the-shoulder
  elevation (the session filter is proven with stubs only; the VM has one account
  and UAC off); a non-elevated process of the *same* user squatting the lock (the VM
  cannot produce a medium-integrity process of the administrator; covered by the
  SDDL decision tests, by stubbing elevation on the host, and by LOCAL SERVICE as the
  foreign identity in the VM); Entra ID / hybrid / MDM machines; power loss during
  a restore (only process kills were tested); a CDP cache with real Windows junctions.

---

# Pass of 2026-11-15: W11P-001 … W11P-003

> **Superseded in part by the pass of 2026-11-16** (above): of the "Remaining risks"
> at the end of this pass, *concurrent restore of the same backup folder* and
> *registry import is not transactional* are addressed by T-3 (restore lock, progress
> record, verification), and *named mutex squatting* by T-1 (owner and DACL checks;
> the squatting DoS itself remains). The rest of this pass is unchanged.

Repository: Win11Privacy, branch `main`, `HEAD` = `f7d58e6` (Release 2.0.0) plus the
uncommitted working tree of this session (earlier audit fixes F-01…F-08, the F-08
request transport, UI work and the installer; see `AUDIT_REPORT.md`,
`F08_FIX_REPORT.md`). Date: 2026-11-15. Nothing was committed or pushed.

---

## Executive summary

| Finding | Severity | Status | Evidence |
|---|---|---|---|
| W11P-001 Backup TOCTOU / signing race | HIGH | **Fixed** | unit tests (host) + live tests with real `reg.exe` and a non-admin identity (VM) |
| W11P-002 Firefox `policies.json` non-atomic write | MEDIUM | **Fixed** | unit tests incl. disk-write failure, stale temp, 6 concurrent writers (host) |
| W11P-003 `SensorSet` false success (exit 0 with `ok:false`) | MEDIUM | **Fixed** (engine + GUI) | unit tests, process-level test (host), live registry-write failure (VM) |
| R-1 Same false-success pattern in `XrayWipe`, `RemoveApps`, `StartupSet`, `RestoreItems`, `PurgeData` | LOW (confirmed) | **Fixed** | static regression check |
| R-2 `policies.json` read as ANSI → non-ASCII text in other policies corrupted on write | LOW (confirmed) | **Fixed** (part of W11P-002) | unit test with Cyrillic policy values |
| R-3 Restore imported "everything except the suspicious part" (partial import of a tampered backup) | LOW | **Fixed** (fail closed, part of W11P-001) | unit + live tests |
| R-4 Partial `RestoreBackup` (reg.exe refused some files) exited 0 | LOW | **Fixed** (exit 2) | static check |

Open: see "Remaining risks". Overall: all three findings and R-1…R-4 are fixed and
covered by regression tests that pass on the host (standard user) and in the VM
(administrator, real `reg.exe`, a non-admin identity for the tamper probes).

> **Superseded in part by the final hardening pass** (`FINAL_SECURITY_AUDIT.md`):
> W11P-005 removed the publication of backups onto the desktop described in step 4
> below — backups now stay in `C:\ProgramData\Win11Privacy\backups` only — and
> W11P-006 replaced the explicit-only ACL check used by `Test-ItemTrusted`. The rest
> of this report is unchanged and still describes the current code.

---

## Phase 1–2: inspection and threat model

**Trust boundaries.** The window (`Win11Privacy.exe`) and the engine it starts run as
administrator; the guard tasks run as administrator/SYSTEM. Every other process of the
same user runs at medium integrity and must not be able to influence what the elevated
code writes to the registry or the file system. `C:\ProgramData\Win11Privacy` is the
protected root (explicit ACL, SYSTEM/Administrators write, owner checked,
`Assert-SafeRoot`); the user's Desktop, `%TEMP%` and HKCU are attacker-writable.

**Attacker-controlled inputs relevant here.** Files and folders on the Desktop
(backup folders, `backup-sig.json`, `.reg` files), names of HKCU ConsentStore keys,
the content of `policies.json` (only administrators can write under Program Files by
default, but the file may contain anything an administrator or a GPO put there).

**Privileged operations.** `reg.exe export` and `reg.exe import` (writes HKLM/HKCU as
administrator), writing `policies.json` in Program Files, writing ConsentStore values.

**Invariants after the fix.**
1. The elevated engine never writes a backup file into a user-writable directory with
   `reg.exe`, and never signs bytes it did not just read from a protected location.
2. Bytes that are verified are exactly the bytes that are imported; nothing can change
   them between the check and the import.
3. A backup whose folder content does not match its signed manifest imports nothing.
4. `policies.json` is replaced in one step or not at all; unrelated policies survive.
5. An engine operation that failed never exits with 0, and the window does not show
   success unless both the JSON `ok` and the exit code say so.

Baseline before the changes (same session, same tree minus these fixes): engine-tests
569/0 (host) and 573/0 (VM, admin), Pester 35/0, SelfTest 114/0.

---

## Detailed remediation

### W11P-001 — Backup TOCTOU / HMAC signing race (HIGH)

**Original problem.** `Ensure-Backup` created `Desktop\Win11Privacy-Backup-…`,
ran `reg.exe export "<key>" "<desktop file>" /y` as administrator, then read the file
back from the Desktop to compute its HMAC. Any medium-integrity process could replace
the file between export and signing (the replacement then carried a valid signature),
and could also plant a link inside the freshly created folder so that `reg.exe /y`
overwrote a file elsewhere with administrator rights. On restore, files were already
copied to a protected folder before verification, but the manifest could be shortened
(entries were not signed as a set), an extra or tampered file only skipped that file
while the rest was imported, and `ConvertFrom-Json` silently keeps the last of two
duplicate keys.

**Root cause.** Export and signing happened in an attacker-writable directory; the
signed object was a path, not the bytes; the manifest had no integrity of its own;
restore was best-effort instead of fail-closed.

**Files / functions.**
- `engine/04-backup.ps1`: new `Get-BackupBytesSig` (HMAC of bytes; `Get-BackupFileSig`
  kept as a wrapper), `Get-BackupManifestSig`, `ConvertTo-BackupManifestText`,
  `Remove-StaleWorkDirs`, `New-SafeWorkDir`, `New-RegBackup`; `Ensure-Backup` now calls
  `New-RegBackup`.
- `engine/23-backups.ps1`: new `Read-BackupManifest`, `Get-BackupAllowedBranches`,
  `Test-RegImportContent`; `Restore-BackupFolder` rewritten; `-RestoreBackup` exit codes.

**Technical solution.**
1. *Staging.* `New-SafeWorkDir` creates `ProgramData\Win11Privacy\backup-<random>` only
   after `Assert-SafeRoot` (owner, protected ACL, no reparse point on the root) and checks
   the new folder with `Test-ItemTrusted` (not a reparse point, trusted owner, no explicit
   write ACE for others).
2. *Export and sign from memory.* `reg.exe` exports into the staging folder only. Each
   file is read once into memory, validated (`Test-RegExportFile` rules) and signed from
   those bytes (`w11p-backup|<folder>|<file>|` prefix, HMAC-SHA256 with the existing
   journal key from `Get-SignKey` — 32 random bytes in the protected root, owner/ACL
   checked; suitable and unchanged).
3. *Signed manifest, version 2.* `backup-sig.json` = `{"version":2,"folder":…,"files":{name:sig},"sig":…}`,
   ASCII only, keys sorted; `sig` = HMAC over the folder name and all `name:sig` pairs.
   The `files` map keeps the version 1 shape, so older program versions can still read it.
4. *Publish only when complete.* At the time of this report: same volume — the whole
   staging folder was renamed onto the Desktop in one `Directory.Move` (keeping its
   protected ACL); different volume — files were written from memory with
   `FileMode.CreateNew`, the manifest last. **Changed by W11P-005:** the finished folder
   is now renamed into `ProgramData\Win11Privacy\backups` (same protected root, same
   volume) and nothing is written to the Desktop or `-BackupRoot` any more.
5. *Restore.* `Read-BackupManifest` parses with the engine's strict parser (no
   duplicate keys, case-insensitive; only `version/files/folder/sig`; file names must
   match `^[A-Za-z0-9_.(){}+-]{1,200}\.reg$`; signatures 64 hex chars; version 2:
   folder name and manifest signature must match; version 1: accepted as legacy).
   The folder must contain exactly the listed `.reg` files (extra, missing, link or
   directory → refused). Every file is read once, its HMAC is checked on those bytes,
   its content is checked by `Test-RegImportContent` (UTF-16 `reg.exe` export, complete,
   first key = a branch the program itself backs up (`Get-BackupAllowedBranches` from
   the definitions), every other key inside that branch, no `[-…]` deletions), and the
   same bytes are written with `CreateNew` into `ProgramData\Win11Privacy\restore-<random>`.
   Nothing is imported unless all files passed. Immediately before each import the
   staged file is opened with `FileShare.Read` (no writers), its HMAC is recomputed
   from the bytes read through that handle, and `reg.exe import` runs while the handle
   is held — the verified bytes are the imported bytes.
6. *Cleanup.* Staging/restore folders are removed with `Remove-TreeNoFollow` (deletes
   links as entries, never follows them); folders left by an interrupted run are removed
   after one hour by `Remove-StaleWorkDirs`.
7. *Exit codes.* `-RestoreBackup`: 1 = nothing restored (refused/error), 2 = some files
   rejected by `reg.exe`, 0 = all restored.

**Backward compatibility.** Backup folder layout and file names are unchanged; version 1
manifests (per-file signatures, written with a UTF-8 BOM by older versions) still
restore; unsigned backups are still refused (as before). Backups whose branches are no
longer part of the program's definitions are refused (fail closed) and can still be
imported manually.

**Security impact.** Removes the export/sign TOCTOU and the privileged write into a
user-writable directory, prevents partial or shortened restores, and binds the imported
bytes to the verified bytes.

### W11P-002 — Firefox `policies.json` non-atomic write (MEDIUM)

**Original problem.** `Write-FirefoxKey` rewrote `policies.json` in place with
`Set-Content`; an interrupted or failed write left an empty/partial file and lost every
policy, corporate ones included. In addition `Get-Content` without `-Encoding` reads a
BOM-less UTF-8 file as ANSI, so non-ASCII text in other policies was corrupted when the
file was written back (confirmed by test).

**Files / functions.** `engine/09-thirdparty.ps1`: new `Read-Utf8Strict`,
`Write-JsonFileAtomic`, `Update-FirefoxPoliciesFile`; `Write-FirefoxKey` now validates
the Firefox folder and delegates; `Get-FirefoxPolicy` reads strictly as UTF-8.

**Technical solution.** JSON is serialised in memory and parsed back before writing; a
uniquely named temporary file is created in the same directory with `CreateNew`, written
as UTF-8 without BOM, flushed to disk (`Flush(true)`), read back strictly and parsed
again, then put in place by the existing `Replace-FileAtomic` (`File.Replace` when the
destination exists — keeps its ACL/attributes; `File.Move` when it does not; retried on
sharing violations, re-evaluated each attempt, so a destination created or removed
concurrently is handled). On any error the original file is untouched and the temporary
file is deleted; stale own temporary files older than one hour are removed. Existing
files are read with strict UTF-8 decoding (with or without BOM) — a file in another
encoding or one that does not parse is not touched. Read-modify-write runs under the
named mutex `Global\Win11Privacy-FirefoxPolicies` (all engine instances: window, guard,
revert). The Firefox installation folder must not be writable by non-administrators
(`Test-ItemTrusted`), and the `distribution` folder and the file must not be reparse
points (checked before and after creating the folder).

**Security impact.** No data loss on interrupted writes, no lost updates between
concurrent writers, no mojibake of unrelated policies, no privileged write through a
planted link.

### W11P-003 — `SensorSet` false-success exit code (MEDIUM)

**Original problem.** `-SensorSet` emitted `{"ok":false,…}` but always ended with
`exit 0`. The window used only `ok`, so it was consistent by accident; scripted callers
and any code path that looks at the exit code saw success.

**Files / functions.** `engine/20-dossier-footprint.ps1`: new `Invoke-SensorSet`; the
`-SensorSet` dispatcher. `EngineRunner.cs`: `RunJson` adds `_exitCode` to the parsed
answer; new `EngineSucceeded`. `PageDossier.cs`: the sensor toggle uses `EngineSucceeded`.

**Technical solution.** Success requires: the registry write and the undo-journal save
did not add a failure (`$script:Failures` unchanged — `Set-Reg` writes the journal
entry ahead, `Save-JournalEntries` counts its own failure), **and** the value read back
equals the requested one. The JSON contract (`key`, `value`, `ok`, `error`) is
unchanged; the error text now distinguishes write/journal failure from read-back
mismatch. Exit code: 0 only when `ok`; 1 for an invalid key or value (nothing done);
2 when the write, the journal or the verification failed. The window treats an answer
as success only when `ok` is true **and** the exit code is 0.

### Additional confirmed defects fixed (R-1 … R-4)

- **R-1** `XrayWipe`, `RemoveApps`, `StartupSet`, `RestoreItems`, `PurgeData` counted
  failures but always exited 0, so the window showed "Готово" (Done). They now exit 2
  when a failure was counted (the window shows "Готово, с ошибками"), like `Revert`.
- **R-2, R-3, R-4** — see W11P-002 and W11P-001 above.

### Review of recent changes (no new defect found)

- **F-08 request transport** (`engine/00-header.ps1`, `EngineRequest.cs`,
  `EngineRunner.cs`): parser strictness (duplicates, unknown fields, types, depth, size,
  ASCII-only, single read of stdin, BOM), operation allowlist, `-Request` exclusivity
  and fail-closed exit 64 were re-tested (engine-tests and SelfTest boundary tests below).
  The only process launches that carry dynamic data are the engine (constant command
  line + stdin) and the self-relaunch with `runas` (the user's own arguments, gated by UAC).
- **Scheduled tasks** pass only constants and the validated `DataRoot` (no quotes possible).
- **Temporary files** in this patch are created with `CreateNew` in protected or
  same-directory locations and removed without following links.
- **ErrorActionPreference = Continue** in the engine: the new code uses .NET calls
  (terminating exceptions) inside `try/catch` and returns explicit results; no new
  silent `-ErrorAction SilentlyContinue` on security-relevant steps.

---

## Test results

All numbers below were produced in this session; nothing was estimated.

| Suite | Where | Result |
|---|---|---|
| `tests/engine-tests.ps1` (full) | host, standard user, Windows PowerShell 5.1 | **624 passed, 0 failed** (admin-only cases skipped with a note) |
| `tests/engine-tests.ps1` (full) | VM, administrator, clean snapshot | **627 passed, 0 failed** (second pass; the first pass had 1 failure caused by the test itself — it assumed a writable `D:`, which is a CD drive in the VM; the test was made to skip without a second writable volume, and was removed with W11P-005, which dropped cross-volume publication) |
| `tests/engine.Tests.ps1` (Pester 3.4) | host and VM | **35 passed, 0 failed** |
| SelfTest (`/define:SELFTEST`, real engine via `WIN11_TEST_ENGINE`) | host | **121 passed, 0 failed** |
| Live remediation checks (`guest-remed.ps1`, real `reg.exe`, registry, LOCAL SERVICE probe) | VM | **19 passed, 0 failed** (first pass 18/1: the test denied the registry write through the PowerShell provider, which cannot handle `C:` inside a key name; rewritten with the .NET registry API) |
| `python tools/build_engine.py --check`, `gen_lang.py`, `check_lang.py`, `set_version.py --check`, `release_notes.py`, `make_winget.py`, `py_compile` | host | all OK |
| `csc` release, `UITEST`, `SELFTEST` builds, `/warn:4` | host | OK, only the pre-existing CS0649 |
| PSScriptAnalyzer (Microsoft-signed copy) on the changed engine parts | host | style findings only (verbs, plural nouns, empty `catch`), no errors |

Key regression tests (all in `tests/engine-tests.ps1`, section W11P-001/002/003):
export only into the protected staging folder; manifest v2 shape and signature;
nine tamper variants (extra file, missing file, manifest deleted / not JSON / entry
removed / duplicate key / `..` path / unknown version / other folder) each import
nothing; swap of the source file and of the staged copy *during* the import does not
reach `reg.exe`; junction instead of the backup folder; foreign branch, key outside
the branch, look-alike prefix, key deletion, non-UTF-16 and truncated content refused;
interrupted export and interrupted import; stale work folders; `policies.json`: other
policies and Cyrillic preserved, BOM/no BOM, file or folder missing, unparsable JSON
and non-UTF-8 left untouched, disk write failure (ACL deny) leaves the original intact,
stale temp files, junction as `distribution`, 6 concurrent writer processes; SensorSet
success / write failure / invalid key with exit codes 0 / 2 / 1; static checks that the
five other operations exit 2 after a counted failure.

---

## Remaining risks

- **Concurrent restore of the same backup folder** by two engine instances imports twice
  (each instance stages its own verified copy; the result is the same registry state).
- **Registry import is not transactional.** If `reg.exe` or the engine is killed in the
  middle of a restore, the files imported so far stay imported (reported as partial,
  exit 2, when the engine survives). The work folder is cleaned on the next restore.
- ~~Cross-volume publication~~ — **resolved by W11P-005**: backups are no longer
  written to the Desktop or any other user-writable folder.
- **Named mutex squatting.** A process of the user could pre-create
  `Global\Win11Privacy-FirefoxPolicies`; Firefox policy writes are then refused
  (denial of service, no corruption). Since W11P-006 such a lock is refused at once
  instead of being used, and there is no silent fallback to a per-session lock.
- **Legacy (version 1) backups** cannot detect a manifest entry removed together with
  its file; version 2 can.
- **Firefox per-user installs** (outside Program Files) are not supported by the engine
  (unchanged); a Firefox folder writable by non-administrators is refused.
- **`QuoteArgs`** (self-relaunch with `runas`) does not escape backslashes before quotes;
  arguments come from the same user and cross the UAC prompt — not an engine boundary.
- Not run here: the GitHub Actions workflow (nothing pushed) and `tests/roundtrip.ps1`
  (CI-only by design).

---

## Compatibility

- **Windows PowerShell 5.1**: all engine code uses PS 5.1 syntax and .NET Framework APIs
  (`[IO.File]::Open` with `FileMode/FileShare`, `FileStream.Flush(bool)`,
  `[IO.File]::Replace`, `System.Threading.Mutex`, `HMACSHA256`); verified by running the
  engine and the test suites under Windows PowerShell 5.1 on the host and in the VM.
- **Windows 11**: verified live in the test VM (Windows 11 Home Single Language,
  build 26300, ru-RU); the host is Windows 11 build 26300. Nothing in the patch is
  Windows-11-specific; Windows 10 support is unchanged (same APIs).
- **C# / .NET Framework 4.x**: built with the in-box `csc` (C# 5), `/warn:4`, only the
  pre-existing warning CS0649.

---

## Release recommendation

For the scope of this report (W11P-001…003, R-1…R-4): **ready**, subject to the CI
workflow passing on GitHub (not run here — nothing was pushed). The release decision
for the whole tree is made in `FINAL_SECURITY_AUDIT.md`, which also covers W11P-005
and W11P-006.
