# Win11Privacy — final security audit and remediation

Repository: Win11Privacy, branch `main`, `HEAD` = `f7d58e6` (Release 2.0.0) plus the
uncommitted working tree of this session. Date: 2026-11-15. Nothing was committed,
pushed, tagged or released.

Earlier reports in the same tree: `AUDIT_REPORT.md` (F-01…F-08), `F08_FIX_REPORT.md`
(structured request transport), `SECURITY_REMEDIATION_REPORT.md` (W11P-001…003,
R-1…R-4). This report covers the final pass: W11P-005, W11P-006, the Firefox lock, the
review of backup/restore, IPC and the engine, and gives the release decision for the
whole tree.

Statuses: **FIXED** — code changed and the regression test was run and passed;
**PARTIALLY FIXED** — mitigation exists, residual risk remains; **OPEN** — unresolved
(accepted or out of scope, with reason); **NOT VERIFIED** — code changed but the
required test could not be run.

---

## Update of 2026-11-16 (after 2.1.0, base `700d84e`)

The three open items of this report (T-1, T-2, T-3) were re-checked against the code
and fixed; GDID was re-checked (user context, credentials, services, unloaded profiles,
crash at every stage); a targeted review of the privilege boundary found one new
defect (T-4). Full details, files and tests: `SECURITY_REMEDIATION_REPORT.md`, pass of
2026-11-16; GDID: `GDID_AUDIT_3.md`, section 8. Nothing was committed, pushed, tagged or
released.

| ID | Severity | Status |
|---|---|---|
| T-1 Global mutex squatting | LOW (DoS); owner check was bypassable by any program of the same user | FIXED, residual DoS (names can still be pre-created; no privilege escalation path) |
| T-2 audit policy temp file | LOW | FIXED |
| T-3 non-transactional registry import | LOW | FIXED — crash-safe recovery with explicit states; residual: reg import merges |
| T-4 busy file read as missing (new) | MEDIUM | FIXED, residual DoS (holding a data file blocks writes, nothing is lost) |
| GDID-A session user from any session | MEDIUM | FIXED (live two-user test NOT VERIFIED) |
| GDID-B `cmdkey` failure read as "no credentials" | LOW | FIXED |
| GDID-C killed wipe leaves services stopped | MEDIUM (availability) | FIXED |

**Targeted review, no new defect found:** window → engine requests (no new operation
or argument; SelfTest boundary tests 140/0), backup HMAC and manifest (format
unchanged, v1 legacy and v2 restore; the snapshot is a v2 backup; the progress records
use their own HMAC prefix), ACL and trusted-path checks (unchanged; the private work
folder and the lock files use them), reparse points and junctions (new code never
follows links; a junction in place of the audit copy is refused and its target left
intact), hard links (a standard user cannot create a hard link to a file without
write access on this Windows build — checked on the host for `hosts` and
`changes.json`; the private folder denies link creation, checked with LOCAL SERVICE),
exit codes (restore 0 / 2 / 1 by state, GDID restore 2 when the interrupted-wipe stage
fails), typed `catch` clauses (none of `FileNotFound`/`DirectoryNotFound` left;
`UnauthorizedAccess` and cmdlet `ItemNotFound` clauses kept — they did not misroute in
the probe).

**Test evidence of the update** (all run on 2026-11-16 on the final tree):

| Suite | Result |
|---|---|
| `tests/engine-tests.ps1` incl. `engine-remediation.ps1` — host, standard user | 879 passed, 0 failed, 5 admin-only blocks skipped with a note |
| same — VM, administrator, clean snapshot | 890 passed, 0 failed, nothing skipped |
| Pester 3.4 — host / VM | 44 / 0, 44 / 0 |
| SelfTest — host / VM (administrator) | 140 / 0, 140 / 0 |
| Live VM checks `guest-remed4.ps1` | 28 / 1 — the failure was harness timing (lock released before the SYSTEM task started); re-check with a start handshake 3 / 3 |
| GitHub Actions on `395af49` | failed: 16 audit-policy checks in administrator mode — the runner's `Windows\Temp` does not pass the path check, so the engine correctly had no private place; the tests now use a protected test root in `ProgramData` and check the `Windows\Temp` branch by the machine's ACL (VM, both ACL variants: 79 / 0) — see `SECURITY_REMEDIATION_REPORT.md` |
| GitHub Actions on `480305a` | **passed** (whole build job incl. live rollback and installer tests); notice: the runner's `C:\Windows\Temp` grants Users full control, refused as designed |
| Not run | PSScriptAnalyzer (permission), UI text-fit scan, installer tests, roundtrip locally; live two-user / over-the-shoulder, Entra/hybrid/MDM, power loss |

**Release recommendation for the update: CONDITIONAL RELEASE** — no critical or high
finding is open; the remaining items are documented denials of service (lock names,
a held data file), the merge semantics of `reg.exe import`, and the scenarios listed
as not run. Conditions: commit, let the GitHub Actions workflow pass (it runs the
engine tests as administrator), and accept the behaviour changes — a restore now
refuses to start when the "before" snapshot cannot be saved, and the window opens
even when another program holds its lock name.

---

## Summary

| Category | Result |
|---|---|
| Critical vulnerabilities | 0 found |
| High vulnerabilities | 3 (W11P-001, W11P-005, W11P-006) — all FIXED |
| Medium vulnerabilities | 4 (W11P-002, W11P-003, W11P-007, W11P-008) — all FIXED |
| Low vulnerabilities | 2 fixed (W11P-009, W11P-010); 3 open, accepted (T-1 lock-name squatting, T-2 audit-policy temp file, T-3 non-transactional registry import) — **all three fixed in the update of 2026-11-16 (residual DoS / merge semantics documented), see above** |
| Fixed findings | 9 security findings + R-1…R-4 reliability defects |
| Open findings | 3 low / theoretical, documented below (none allows a privileged write or a change of data) — as of 2026-11-16 none open; one new MEDIUM (T-4) found and fixed |
| Tests passed | 1598 test cases in 7 suites (details in *Test evidence*) |
| Tests failed | 0 in the final runs (two earlier runs of the live checks failed one check each because of the test harness, see *Test evidence*) |
| Tests not run | GitHub Actions workflow (nothing pushed); `tests/roundtrip.ps1` (CI-only by design); `make_winget.py` / `submit_winget.py` (unchanged in this pass, last run earlier in the session) |

**Release recommendation: CONDITIONAL RELEASE** — see the last section.

---

## Threat model (short)

The window and the engine it starts run as administrator; the guard and watch tasks
run as administrator or SYSTEM. Every other process of the signed-in user runs at
medium integrity and must not be able to influence what the elevated code writes or
imports. Attacker-writable: the user's profile (Desktop, `%TEMP%`, AppData), HKCU,
`C:\ProgramData` itself (users may create files there), named kernel objects in the
`Global\` namespace (any process may create them). Protected: `C:\ProgramData\Win11Privacy`
(explicit ACL, owner and path checked), Program Files.

---

## Findings

### W11P-005 — privileged backup publication into a user-writable folder (HIGH) — FIXED

- **Affected:** `engine/04-backup.ps1` — `New-RegBackup`, `Ensure-Backup`;
  `engine/23-backups.ps1` — `Get-BackupList`, `Read-BackupManifest`;
  `engine/25-selftest.ps1`; GUI `PageSettings.cs`, `Actions.cs`, `PageChanges.cs`.
- **Original vulnerability.** After W11P-001 the signed backup was built in protected
  staging, but it was still *published* by the elevated engine into the Desktop (or
  `-BackupRoot`): same volume by `Directory.Move`, another volume by writing every file
  with `CreateNew`. The destination is controlled by the user. Path checks for reparse
  points before the writes cannot exclude a race.
- **Root cause.** A privileged component wrote into an attacker-controlled directory.
- **Exploitation prerequisites.** Code running as the signed-in user (no admin), an
  apply with backup enabled; for the cross-volume branch a Desktop on another volume.
- **Attack scenario.** Between the reparse check and the `CreateNew` writes, the user's
  process replaces the destination folder with a junction to a protected folder; the
  elevated engine then *creates* `HKLM__*.reg` and `backup-sig.json` there (no
  overwrite thanks to `CreateNew`, but a privileged file creation in a folder the user
  chose). On the same volume no write happened, but the published copy carried a
  protected ACL in the user's Desktop (could not be deleted without elevation).
- **Code modification.** Publication to the Desktop is removed entirely, as the user
  asked ("убрать папку с рабочего стола, оставить только в программе возврат"):
  1. the finished, signed staging folder is moved with one `Directory.Move` into
     `ProgramData\Win11Privacy\backups\<leaf>` — same protected root, same volume;
     the store is created inside the verified root and checked with `Test-ItemTrusted`
     (no link, trusted owner, no untrusted write — inherited included, W11P-006);
  2. the elevated engine writes **no** backup file into any user-writable folder;
     `-BackupRoot` is still accepted (interface unchanged) and only used to *list*
     backups of older versions;
  3. retention: the very first backup and the 20 newest stay (`Limit-BackupStore`);
  4. `Get-BackupList` lists the store first and marks those items `protected`; a copy
     with the same folder name elsewhere is shown once, from the store;
  5. `-SelfTest` checks the store instead of probing a write to the Desktop;
  6. the window: "Open backup folder" opens the store; texts no longer say "desktop"
     (RU/EN dictionaries updated).
  A user-level copy through a de-elevated task (the two-stage design suggested in the
  task) was implemented first and then dropped at the user's request — it would have
  kept a second, user-writable copy that brings nothing for restore, which always
  verifies the signatures anyway.
- **Backup format:** unchanged (folder name, `.reg` files, `backup-sig.json` v2). Only
  the location changed — documented in README, CHANGELOG, `docs/security-model.md`.
- **Regression tests** (`tests/engine-tests.ps1`, section W11P-001):
  backup lands in the store and nothing is written to the Desktop/`-BackupRoot`, no
  de-elevated task is used; work folder removed; store is a junction → refused, nothing
  written to the junction target; move into the store denied (ACL) → error, store empty,
  work folder removed; "disk full" during export → nothing counted, no backup;
  interrupted export → nothing new in the store; 4 processes × 3 backups at once →
  12 distinct complete backups, no work folder left; retention keeps first + N newest;
  list shows the stored copy once, `protected`; static check that neither
  `New-RegBackup` nor `Ensure-Backup` references the Desktop, `Invoke-AsUser` or
  `BackupRoot`. Live (VM, `guest-remed.ps1`): apply creates the backup in the store,
  nothing on the Desktop or in `-BackupRoot`; store, backup folder and file have a
  trusted owner and no untrusted write ACE (explicit or inherited); a LOCAL SERVICE
  process cannot modify a stored file, add a file, add a folder to the store, rename
  a stored backup, or write into staging; `ListBackups` marks it protected; restore
  exit 0; `SelfTest` reports the store usable.
- **Test evidence:** host engine-tests 660/0 (standard user); VM engine-tests 669/0 (administrator, clean snapshot) (admin-only cases: symbolic link in a backup, concurrency, ACL); VM live checks `guest-remed.ps1` 34/0 (backup section 24/24).
- **Residual risk.** None known for publication. Behaviour change: backups are no
  longer visible on the Desktop; deleting them needs administrator rights (or the
  uninstaller's "remove program data").

### W11P-006 — incomplete ACL validation in `Test-ItemTrusted` (HIGH) — FIXED

- **Affected:** `engine/03-datafolder.ps1` — `Test-ItemTrusted` (new
  `Get-UntrustedRights`, `Test-PathTrusted`, `Test-SafeRootChain`, `Move-UntrustedAside`),
  `Assert-SafeRoot`, `Protect-DataRoot`, `Get-UntrustedItems`; `engine/09-thirdparty.ps1`
  — `Write-FirefoxKey`; `Engine.cs` — `OpenToOthers`, `TrustedDeep`, `HasUntrusted`,
  `ChainSecure`, `SecureRoot`.
- **Original vulnerability.** `GetAccessRules($true, $false, …)` returned explicit ACEs
  only. A folder or file writable by Users/Authenticated Users/Everyone through an
  *inherited* ACE was trusted. Only the object itself was checked, not the path above
  it.
- **Root cause.** Explicit-only enumeration (correct only in the legacy-root migration,
  where inherited rights are about to be replaced) was reused for every trust decision.
- **Exploitation prerequisites.** A location checked with `Test-ItemTrusted` whose
  write permission comes from a parent — e.g. a Firefox installed into a folder that
  inherits user-write rights, or a misconfigured `ProgramData`.
- **Attack scenario.** Firefox installed under `C:\Tools\Firefox` (inherits
  "Authenticated Users: Modify" from `C:\`). The old check trusted the folder; the user
  creates `distribution\` with a junction or swaps `policies.json` between the read and
  the administrator's replace → privileged write through a user-controlled path. Same
  for any parent that a user may rename: the checked folder can be replaced as a whole.
- **Code modification.** `Get-UntrustedRights` evaluates explicit **and inherited**
  ACEs: everything that applies to the object (not inherit-only), plus — for a folder —
  what it passes to children (except CREATOR OWNER/CREATOR GROUP, which become the
  creator); OWNER RIGHTS is skipped (the owner is checked separately); Deny is
  subtracted only when it is explicit, the ACL is canonical, the trustee is Everyone
  and it applies to the object — a Deny for one group does not cover a principal that
  gets the right through another group, and an inherited Deny is evaluated after
  explicit Allows. Dangerous rights: write/append data, write EA/attributes, delete,
  delete child, WRITE_DAC, WRITE_OWNER, GENERIC_WRITE, GENERIC_ALL. Unreadable
  security descriptor, missing object or reparse point → not trusted.
  `Test-PathTrusted` = object trusted **and** `Test-DirChainSecure` for every parent
  (nobody else may delete/rename it, change its ACL/owner, or delete children of the
  parent). `Assert-SafeRoot` now also requires the chain to `C:\ProgramData` to be
  secure. `Write-FirefoxKey` uses `Test-PathTrusted` for the Firefox folder and
  `Test-ItemTrusted` for an existing `distribution` folder and `policies.json`.
  The legacy-root migration keeps an explicit-only pass (`-ExplicitOnly`) — inherited
  rights from `ProgramData` are replaced by the new root ACL in the next step — and
  then re-checks everything fully after the new ACL has propagated, quarantining
  anything still untrusted. The window (`Engine.cs`) mirrors all of this.
- **Not weakened:** every previous rejection still rejects; the only relaxations are
  CREATOR OWNER for children (cannot be exploited by someone else) and an explicit
  Everyone Deny (which provably applies to everybody first).
- **Regression tests:** 23 in-memory security-descriptor cases (SDDL): closed folder,
  TrustedInstaller owner, user owner, explicit write, inherited write on folder and
  file, delete only, delete child, WRITE_DAC, WRITE_OWNER, GENERIC_WRITE,
  GENERIC_ALL, write attributes, inherit-only write for children (folder) and on a
  file, CREATOR OWNER, OWNER RIGHTS, explicit Everyone Deny, Deny for Users with
  Allow for Authenticated Users, inherited Deny after explicit Allow, non-canonical
  order, inherit-only Deny, empty DACL; reparse point; unreadable descriptor; null
  object; `-ExplicitOnly` semantics; real folders: Program Files trusted with its path,
  System32 path trusted, ProgramData not trusted itself but not renamable, user TEMP not
  trusted, inherited write on a real file seen; `Assert-SafeRoot` false when the chain
  is open even if the root is closed. As administrator (VM/CI): closed folder/file
  trusted; file and folder opened to Users by inheritance not trusted (trusted with
  `-ExplicitOnly` — the old blind spot); folder passing write to children not trusted;
  closed file under the user's TEMP → path not trusted; Delete for Authenticated Users
  → not trusted; legacy-root migration keeps the admin's own files (propagation check).
  SelfTest: `ChainSecure` for System32 and ProgramData true, TEMP and a missing folder
  false; static checks for the window's second full pass and chain check.
- **Test evidence:** host engine-tests 660/0 (standard user) (W11P-006 section 13/13; the admin-only part is skipped on the host); VM engine-tests 669/0 (administrator, clean snapshot) (admin part 6/6, legacy-root migration keeps the admin's own files); SelfTest 125/0.
- **Residual risk.** A `ProgramData` whose ACL was opened by third-party software
  (rename/delete for users) now makes the program refuse its data folder — fail closed,
  with a message in the log. This is deliberate.

### W11P-007 — Firefox lock fell back to `Local\` (MEDIUM) — FIXED

- **Affected:** `engine/09-thirdparty.ps1` — `Update-FirefoxPoliciesFile`, new
  `Open-FirefoxMutex`, `Test-MutexOwnerTrusted`.
- **Original vulnerability.** `New-Object Mutex($false,'Global\…')` and on any error
  `Local\…`. A mutex created by a SYSTEM task gets SYSTEM's default DACL, which does not
  give an elevated administrator full access; .NET Framework's `Mutex(bool,string)`
  opens an existing mutex with full access, so the window's engine got
  `UnauthorizedAccessException` and silently took a per-session `Local\` lock.
- **Root cause.** Fail-open fallback; default object DACL.
- **Exploitation prerequisites.** The guard (SYSTEM) and an apply/revert from the
  window writing `policies.json` at the same time; or a user process that creates the
  name with a DACL denying administrators.
- **Attack scenario.** The user pre-creates `Global\Win11Privacy-FirefoxPolicies` with an
  empty DACL; every elevated writer falls back to its own `Local\` lock, and the SYSTEM
  guard and the window's engine read-modify-write `policies.json` concurrently → lost
  policy keys (integrity of a security configuration), no privileged write elsewhere.
- **Code modification.** Only `Global\`. A new lock is created with a protected
  `MutexSecurity` (SYSTEM, Administrators, creator: full control), so SYSTEM and the
  window open each other's lock. An existing lock is used only if its owner is SYSTEM,
  Administrators or the current account; otherwise, or if it cannot be opened, the
  write is refused at once with a clear reason (no 30 s wait, no deadlock, no fallback).
- **Regression tests:** owner rule; DACL of a new lock; lock squatted with an
  inaccessible DACL → refused, file untouched, no `Local\`; writes work again after the
  squatter is gone; 6 concurrent writer processes keep all keys; static check that
  `Local\Win11Privacy-FirefoxPolicies` no longer exists. Live (VM): SYSTEM holds the
  lock → the administrator engine opens it and **waits** (shared domain), the file
  keeps both writers' keys; the administrator holds it → a SYSTEM writer waits and
  writes; LOCAL SERVICE pre-creates the name with an open DACL (untrusted owner) or an
  empty DACL → the administrator's write is refused within seconds, file untouched.
- **Test evidence:** host engine-tests 660/0 (standard user) (lock tests 4/4, 6 concurrent writers); VM live checks `guest-remed.ps1` 34/0 (Firefox lock section 7/7: SYSTEM held the lock 12 s and the administrator engine waited 11.9 s and then wrote; a SYSTEM writer waited 6.3 s behind the administrator's lock and wrote; both squatters refused at once).
- **Residual risk.** T-1 (squatting = denial of service).

### W11P-008 — backup manifest downgrade v2 → v1 (MEDIUM) — FIXED

- **Affected:** `engine/23-backups.ps1` — `Read-BackupManifest`, new `Test-BackupV1Allowed`.
- **Original vulnerability.** Version 1 manifests (per-file signatures, no signature
  of the list) were accepted for every backup, so the v2 protection against a shortened
  list could be bypassed by rewriting a v2 manifest as v1.
- **Attack scenario.** On a copy the user can write (a backup kept outside the store),
  remove one file and rewrite the manifest as v1 without that entry → restore imports
  only part of the saved state, silently.
- **Code modification.** v1 is accepted only for a folder dated before v2 existed
  (`$script:BackupV2Since = '20261115'`) and never for a folder in the store. The folder
  name (with its date) is part of every file signature, so the date cannot be moved
  back without breaking all signatures. Legacy 2.0.0 backups keep working.
- **Regression tests:** legacy v1 (older date) restores; v1 on a folder dated today →
  refused; v1 in the store → refused; legacy folder renamed → refused. Live (VM, real
  key): legacy 2.0.0-style backup restores; downgraded stored backup and downgraded
  copy outside the store refused; renamed legacy refused.
- **Test evidence:** host engine-tests 660/0 (standard user); VM live checks `guest-remed.ps1` 34/0 (downgrade and legacy cases 4/4, real signing key).
- **Residual risk.** A system clock set before 2026-11-15 would give new backups an
  older date; they are still in the store, where v1 is never accepted.

### W11P-009 — window's data-root checks were explicit-only and ignored the path (LOW) — FIXED

- **Affected:** `Engine.cs` — `SecureRoot`, `OpenToOthers`, `TrustedDeep`, `Quarantine`.
- **Problem / fix.** Same blind spot as W11P-006 on the window side (it prepares
  `ProgramData\Win11Privacy\bin` before every engine start). Now: chain check before
  touching the root (`ChainSecure`, else the engine is not started), explicit-only pass
  only during migration, then a full pass after the new root ACL.
- **Tests / evidence:** SelfTest `ChainSecure` cases and static checks — SelfTest 125/0 (4 new `ChainSecure` cases); static checks in host engine-tests 660/0 (standard user).
- **Residual risk:** none known.

### W11P-010 — existing `distribution` / `policies.json` not trust-checked (LOW) — FIXED

- **Affected:** `engine/09-thirdparty.ps1` — `Write-FirefoxKey`.
- **Problem.** Only the Firefox folder was checked. An existing `distribution` folder
  created by some tool with user-write rights let a user swap `policies.json` between
  the read and the administrator's replace.
- **Fix.** Existing `distribution` and `policies.json` must pass `Test-ItemTrusted`.
- **Tests:** foreign `distribution` → refused, no file created; foreign
  `policies.json` → refused, unchanged; all trusted → written; the whole path is checked.
  Evidence: host engine-tests 660/0 (standard user) (Firefox section).

### W11P-001 / W11P-002 / W11P-003 and R-1…R-4 — FIXED (earlier pass, re-verified)

Details in `SECURITY_REMEDIATION_REPORT.md`. Re-run in this pass with the current tree
(the W11P-001 tests were adapted to the store; none was removed or weakened — the
cross-volume publication test was replaced because that code path no longer exists).

---

## Open and theoretical items

| ID | Severity | Status | Why it stays |
|---|---|---|---|
| T-1 | LOW | **FIXED, residual DoS** (2026-11-16) | Re-checked: the owner check trusted the engine's own user SID, which every non-elevated program of that user shares, and new locks granted that SID full control; DACLs of existing locks were not checked; the window quit on any object under its name. Fixed (owner + full DACL check, Administrators-owned locks, window starts when squatted). Residual: pre-creating a name is still possible — Firefox policy writes are refused (DoS), the window cannot detect a second window meanwhile, the installer's `AppMutex` check can be blocked. No privilege escalation path was found. Details: `SECURITY_REMEDIATION_REPORT.md`, pass of 2026-11-16. |
| T-2 | LOW | **FIXED** (2026-11-16) | The CSV now goes only into a fresh private folder (SYSTEM + Administrators, owner Administrators) in the verified protected root or `Windows\Temp`; read once, only if it is the one regular, recent, admin-owned file. No protected place → "could not be read", auditpol is not called. Verified live in the VM with a LOCAL SERVICE probe. |
| T-3 | LOW | **FIXED (crash-safe recovery), residual** (2026-11-16) | Restore lock, signed progress record with states Prepared / InProgress / Restored / PartiallyRestored / Failed and `RecoveryRequired` for the next run, mandatory snapshot before the first import, verification by re-export after each file, exit 0 / 2 / 1, window notice, no automatic repeat. Residual: reg import merges (values the backup lacks stay; the snapshot cannot express "did not exist"). |
| T-4 | MEDIUM | **FIXED, residual DoS** (new, 2026-11-16) | Windows PowerShell 5.1 misrouted "file in use" to a `catch [DirectoryNotFoundException]` clause after repeated execution, so `Read-TextShared` answered "no such file": a user process holding `changes.json` open made the elevated engine see no journal and the next write replace the history. Error kinds now come from the exception itself. Residual: holding the file blocks journal writes (DoS, nothing lost). |
| GDID-A…C | MEDIUM / LOW | **FIXED** (2026-11-16) | Session user only from the engine's own session (two signed-in users could get each other's tasks/cache cleanup); `cmdkey` listing failure is not "no credentials"; a killed wipe no longer leaves services stopped (signed record, restart by "Restore" and by the next wipe). See `GDID_AUDIT_3.md` section 8. |
| — | INFO | by design | HMAC key (`journal.key`, 32 random bytes, SYSTEM/Administrators only, created with its ACL atomically, replaced only if found readable by others or corrupt). No rotation: rotating would invalidate every backup and the journal; an attacker who can read the key is already administrator. HMAC-SHA256 over the exact bytes, with domain-separated prefixes for files and the manifest — no change needed. |
| — | INFO | by design | Portable-mode replay of an older journal (pre-existing, documented in `docs/security-model.md`). |
| — | INFO | not a boundary | `QuoteArgs` for the self-relaunch with `runas` — the user's own arguments, behind the UAC prompt. |

---

## Review notes (no new defect found)

- **IPC (window ↔ engine).** Constant command line `-File <engine in ProgramData\bin>
  -Request`; one JSON request on stdin (strict parser: duplicates case-insensitive,
  unknown fields, types, depth ≤ 4, size limit, ASCII, BOM) against an operation
  allowlist; any error → exit 64, nothing done. The engine file is compared by SHA-256
  with the embedded copy before every start; `Harden` strips injected environment
  (`PSModulePath`, `WIN11_ENGINE_TRACE`, …). Exit codes: 0 ok, 1 refused/nothing done,
  2 partial, 64 bad request; the window shows "Done, with errors" for 2 and uses
  `ok` **and** exit 0 for the sensor toggle. stdout is read to the end, stderr
  asynchronously (no pipe deadlock).
- **Scheduled tasks / SYSTEM / impersonation.** One-shot tasks: random name, registered
  without `-Force`, verified (command, SID) before start, run `schtasks`/PowerShell
  directly; task names given to `schtasks /change` are rejected if they contain `"`,
  CR or LF and must exist. `Invoke-AsUser` (de-elevated work in the user's profile):
  input in the protected root, result owner checked before it is read.
- **Engine search** for `Invoke-Expression`, dynamic script blocks, `Start-Process`,
  `cmd.exe`, `reg.exe`, `schtasks`, `netsh`: no dynamic code from data; `cmd.exe`
  only for constant lines without `%`/line breaks; `reg.exe` by full path with fixed
  argument shapes; user-profile deletions run as the user.
- **Backup/restore**: file identity is the folder name + file name inside the HMAC;
  names restricted to `^[A-Za-z0-9_.(){}+-]{1,200}\.reg$` (no traversal, case-insensitive
  duplicates rejected by the parser); exactly the listed files must be present; links
  refused; content limited to the program's own branches; verified bytes = imported
  bytes (staged copy held open without write sharing during `reg.exe import`).

---

## Source quality

- The modular engine (`engine/NN-*.ps1`) is the source; `Win11-Privacy-Engine.ps1` was
  rebuilt with `tools/build_engine.py` and `--check` passes. `Win11Privacy.exe` was
  rebuilt from the current sources.
- Line endings: working tree CRLF / index LF through `core.autocrlf=true`, as before;
  three engine parts edited by script were normalised back to CRLF; `CHANGELOG.md`
  stays LF-only; BOMs unchanged. **No `.gitattributes` added:** introducing `eol`
  attributes would renormalise many files in the next commit and needs a separate
  rule for the LF-only CHANGELOG — a maintenance change better done on its own.
- PSScriptAnalyzer (Microsoft-signed copy) on the changed engine parts: style findings
  only (unapproved verbs, plural nouns, empty `catch`, one pre-existing unused
  variable in the VS Code part); no errors.
- The UITEST build shows CS0162 (unreachable code after the `#if UITEST … return`
  blocks in `MainForm.cs`) — test build only, not part of this pass.

---

## Test evidence

All numbers come from runs made in this session on 2026-11-15 with the final tree
(engine `Win11-Privacy-Engine.ps1` rebuilt from `engine/`, MD5 `8104262e…`).
Nothing was estimated; a run that failed is listed as such.

| Suite | Where / identity | Result |
|---|---|---|
| `tests/engine-tests.ps1` (full, Windows PowerShell 5.1) | host, standard user | **660 passed, 0 failed**; 4 blocks need administrator rights and are skipped there with a note (dry-run apply, data-folder protection, symbolic link to a file, ACL on disk as administrator) — they run in the VM |
| `tests/engine-tests.ps1` (full) | VM, administrator, after revert to the clean snapshot | **669 passed, 0 failed** |
| `tests/engine.Tests.ps1` (Pester 3.4.0) | host / VM | **35 / 0** and **35 / 0** |
| SelfTest (`/define:SELFTEST`, real engine through `WIN11_TEST_ENGINE`) | host | **125 passed, 0 failed** |
| Live checks `guest-remed.ps1` (real engine, `reg.exe`, registry, Task Scheduler, SYSTEM and LOCAL SERVICE tasks) | VM, administrator | final run **34 passed, 0 failed**. Run 1: 33/1 — the check compared the account *name* with "SYSTEM", the Russian guest shows "СИСТЕМА" (now compared by SID). Run 2: 33/1 — the LOCAL SERVICE squatter task started only after the 30 s wait, so no squatter existed and the write correctly succeeded (wait raised to 120 s). The product behaved the same in all three runs. |
| Installer (`installer/build.ps1` with pinned Inno Setup 6.7.4, `tests/installer-tests.ps1`) | VM, administrator, with the rebuilt `Win11Privacy.exe` | ISCC build exit 0; **40 passed, 0 failed** (install, reinstall, uninstall with and without data, portable) |
| Static / build | host | `build_engine.py --check` OK; PowerShell parser: engine and tests 0 errors; `gen_lang.py` + `check_lang.py` all translated; `set_version.py --check` OK; `release_notes.py --version 2.0.0` OK; `py_compile tools/*.py` OK; `csc` release, `UITEST`, `SELFTEST` with `/warn:4` OK (CS0649 pre-existing; CS0162 in the UITEST build only); PSScriptAnalyzer: style findings only |

Not run: the GitHub Actions workflow (nothing was pushed), `tests/roundtrip.ps1`
(CI-only by design), `make_winget.py` / `submit_winget.py` (unchanged in this pass).

Reproduce (from the repository root, Windows PowerShell 5.1):

```
python tools/build_engine.py --check
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/engine-tests.ps1
powershell.exe -NoProfile -Command "Invoke-Pester -Script tests/engine.Tests.ps1"
```

Run `tests/engine-tests.ps1` once more from an elevated prompt to include the
administrator-only cases. The VM checks are driven by
`D:\Win11PrivacyVM\installer\host-remed3.ps1` (clean snapshot, engine tests, Pester,
live checks) and `host-installer.ps1` — outside the repository, they need the test VM.

---

## Release recommendation

**CONDITIONAL RELEASE.**

Every finding of the audit that allowed an ordinary program of the user to influence
what the elevated engine writes or imports is fixed and covered by regression tests
that were run on the host and, as administrator with real system components, in the
VM: W11P-005 (no privileged write into user folders — backups stay in the protected
store), W11P-006 (full ACL and path validation, engine and window), W11P-007 (one
shared Firefox lock, squatting refused), W11P-008 (no manifest downgrade), W11P-009,
W11P-010, and W11P-001…003 / R-1…R-4 from the previous pass. No critical, high or
medium finding is open; the three open items are low and cannot change data.

Conditions before tagging a release:
1. Commit the working tree and let the GitHub Actions workflow pass (it builds the
   exe and the installer and runs the tests as administrator) — not run here.
2. Accept the documented behaviour changes: registry backups are no longer put on the
   desktop (they are in `C:\ProgramData\Win11Privacy\backups`, restored from the
   window, first + 20 newest kept); the program refuses its data folder if
   `C:\ProgramData` was opened by other software so that non-administrators can rename
   or delete folders in it; a pre-created Firefox lock makes Firefox policy writes fail
   instead of running without a lock.
