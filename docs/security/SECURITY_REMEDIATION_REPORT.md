# Win11Privacy — security remediation report (W11P-001 … W11P-003)

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
