# GDID audit — device ID (Device PUID) subsystem of the engine

Repository: Win11Privacy · audited revision `57a2a87`, changes on top of `8506b22` (both after the 2.1.0 release commit; the engine is the same) · report date 2026-11-15  
Scope: everything the engine does with the Microsoft device ID (GDID / Device PUID): the
`gdid` and `gdidlock` modules, `-GdidStatus`, `-GdidReissue`, `-GdidRestore`, the device-ID
hosts blocks, the account/organisation checks, the "Digital footprint" item, the guard and
the Device ID page of the window.  
Nothing was committed, pushed or tagged. The CHANGELOG entry is under «Не выпущено».

---

## 1. Summary

The subsystem reported success in several situations where it had not verified it:

* "Sending is off" looked at CDPSvc and DoSvc only — CDPUserSvc and its per-user copies,
  which the module also disables, were never checked, and "service missing" and "registry
  not readable" were the same answer.
* "No ID" / "wiped everywhere" was said while places were unreadable or user profiles were
  not checked at all; listing errors were swallowed and became "all checked".
* The wipe verified **after** restarting the services, so the Microsoft account service
  could mint a new ID that was then reported as "a copy Windows did not release"; an
  exception mid-wipe left the services stopped and wlidsvc disabled; wlidsvc's start type
  lived only in the engine's memory (a killed engine left Microsoft account sign-in broken
  with no rollback path).
* With over-the-shoulder elevation (a standard user types an administrator's password) the
  credential cleanup, the cache check and the Microsoft-account check all looked at the
  administrator instead of the person at the computer — the lock could be applied to a
  person who signs in with a Microsoft account.
* "Restore" reported every failure as "the program did not change it", always exited 0,
  and printed `True` into the log.
* The hosts parser paired markers wrongly: a block with a deleted end marker took the
  user's own `0.0.0.0` lines with it, an orphaned end marker opened a new block, and a
  damaged, empty or duplicated block counted as "in place" — "issuing blocked" could be
  shown and the wipe run "under the lock" while login.live.com was reachable.

All 16 confirmed bugs are fixed in the engine parts (no rewrite: the same functions, CLI
switches, JSON fields, journal and backup architecture; new fields are additive). Tests
cover the 20 scenarios of the task plus the regressions found on the way.

## 2. Findings

Classification: **CB** — confirmed bug (reproduced by a test against the old engine or by
reading the code path end to end), **PB** — potential bug, **LV** — requires live
verification.

| ID | Class | Area | Finding | Status |
|---|---|---|---|---|
| GDID-01 | CB | A | `transmitOff` (status) and the footprint warning checked CDPSvc + DoSvc only; CDPUserSvc template and `CDPUserSvc_<LUID>` copies ignored; `Get-SvcStart` returned -1 for both "missing" and "unreadable"; a service disabled in the registry but still running (or still remembered by the service manager until reboot) counted as off; two copies of the logic | fixed |
| GDID-02 | CB | B | `Check-Def gdidwipe` said "no ID" (`ok`) when the scan found nothing, even if places were unreadable or profiles unchecked | fixed |
| GDID-03 | CB | B | `Get-UncheckedProfiles` and `Get-IdCrlRoots` swallowed listing errors (HKU, ProfileList) → 0 unchecked profiles / other users silently skipped | fixed |
| GDID-04 | CB | B | identities under another user's SID in the system hive were labelled `user` (counted as the viewer's own copies) | fixed |
| GDID-05 | CB | B, D | the wipe's success ignored unchecked profiles; NegativeCache enumeration errors in the removal stage were swallowed | fixed |
| GDID-06 | CB | D | verification ran after the services were restarted → a freshly minted ID (normal for "change the ID") was reported as a leftover copy | fixed |
| GDID-07 | CB | C, D | wlidsvc was disabled for the wipe with its start type kept only in memory (and from `Get-Service`, losing DelayedAutostart): a killed engine left the Microsoft account service disabled forever, invisible to Restore and rollback | fixed |
| GDID-08 | CB | D | no `try/finally`: an exception between "stop services" and "restore services" left them stopped and wlidsvc disabled | fixed |
| GDID-09 | CB | D, multi-user | the user-context credential task ran as the engine's account (administrator) instead of the person at the computer; other signed-in users' credential stores were never cleaned; the CDP cache was cleaned in the session user's folder but verified in the administrator's | fixed |
| GDID-10 | CB | C | `-GdidRestore`: any `Restore-ChangeKey` error (journal untrusted, restore failed) logged as "the program did not change it" and not counted; exit code always 0; `Remove-HostsBlock` called bare printed `True`; any firewall error logged as "there was no rule"; guard profile updated last (guard could re-apply mid-restore); CDPSvc started even when the program had not changed it, DoSvc/CDPUserSvc copies never; start failure only `[i]`; wlidsvc not handled | fixed |
| GDID-11 | CB | D | `-GdidReissue` always exited 0, even when the wipe failed or was refused | fixed |
| GDID-12 | CB | E | hosts: any following marker ended a block and an orphaned end marker started one → removal (and the full rollback, kind `all`) deleted the user's own `0.0.0.0 …` lines | fixed |
| GDID-13 | CB | E | `Test-HostsBlockCurrent` accepted duplicated and unclosed blocks; `locked`, `ddsBlocked`, the `gdidwipe` precondition and the `-GdidReissue` message used the start marker only → an empty/damaged lock block meant "issuing blocked" | fixed |
| GDID-14 | CB | E | `Apply-Hosts` / `Remove-HostsBlock` did not re-read the result (Defender rewrites hosts blocks of Microsoft domains) | fixed |
| GDID-15 | CB | F | `Test-MsaLogon` asked about `$env:USERNAME` (the engine's account, env-derived); over-the-shoulder elevation hid the person's Microsoft account → the lock could break their sign-in; fallback read the engine's HKCU | fixed |
| GDID-16 | CB | F | `Get-ManagedReason` failed open: a WMI error meant "not in a domain"; WorkplaceJoin read only in the engine's HKCU | fixed |
| GDID-17 | PB | F | the lock is machine-wide: other local accounts that sign in with a Microsoft account lose it too | warned in the apply log (no refusal: the existing protection is about the person applying it) |
| GDID-18 | PB | D | CDPSvc / DoSvc stay auto-start while stopped for the wipe; a trigger start mid-wipe could write the ID back | not changed (DoSvc's configuration is denied to administrators); the verification step now catches it as `Partial` |
| GDID-19 | LV | A | services disabled by a registry write stay "Automatic" in the service manager's memory until reboot and can still be started | now reported as `Pending` ("after a restart"); VM check below |
| GDID-20 | PB | B | `Get-GdidCopies` keeps `RegistryKey` handles from `Get-Item` until GC | not changed (only logged-on users' hives, never unloaded by the engine) |
| GDID-21 | LV | D | whether the elevated engine sees the same credential store as the user (device credentials are cleaned by the engine's own `cmdkey` *and* by the user task; the engine's store is verified only when it is not the session user) | open |
| GDID-22 | LV | B | whether LocalService/NetworkService profiles or CDPSvc's service-profile CDP data hold the device PUID | not added to the wipe without evidence (same rule as for hosts domains) |
| GDID-23 | LV | D | an interactive one-shot task for another user who is signed in via fast user switching | logic covered by stubs; needs two interactive sessions |

## 3. Root causes

1. **No shared definition of "verified".** Every caller decided on its own what "off",
   "clean" and "locked" meant, and each took the cheapest signal (two `Start` values, a
   copy count, a start marker). Missing data defaulted to the success side.
2. **Errors folded into "nothing there".** `-ErrorAction SilentlyContinue` on listings and
   `Get-RegValue`-style reads (null on any error) turned access-denied into absent.
3. **Identity of "the user" taken from the engine process.** `$env:USERNAME`, `HKCU`,
   `$env:LOCALAPPDATA` and `$script:RunAccount` all name the elevating account, which is not
   the person at the computer when a standard user typed an administrator's password.
4. **Wipe written as a straight line.** No stage results, no `finally`, a change
   (wlidsvc) outside the journal, and verification placed after the step that can
   re-create what it verifies.
5. **Hosts markers parsed by toggling.** A marker was "start" or "end" by position, not by
   kind, so any damage to one block shifted the meaning of the rest of the file.

## 4. Changes

### Engine (`engine/`, rebuilt into `Win11-Privacy-Engine.ps1`)

| File | Change |
|---|---|
| `12-gdid.ps1` | **Services:** `Get-SvcStartInfo` (start type in words: Boot/System/Automatic/Manual/Disabled/Missing/ReadError; start -1 missing, -2 unreadable), `Get-SvcScmView` (running + start type the service manager remembers), `Get-GdidUserSvcInstances`, `Get-GdidTransmitState` — the single source of truth: `Off` only if all three services are disabled or missing, no copy of CDPUserSvc keeps an old start type, nothing runs, the service manager agrees and everything was read; `Pending`, `On`, `Unknown` otherwise. `Get-SvcStart` kept as a wrapper. **Scan:** `Get-GdidScan` (`Found` / `NotFound` / `Unverified`), listing failures recorded as unreadable (`Get-GdidHiveNames`, `Get-IdCrlRoots`, `Get-UncheckedProfiles`), identity labels by SID. **Accounts:** `Get-GdidUserHiveRoots`, `Test-GdidKeyHasChildren`, `Test-MsaAccount`, `Test-MsaLogon` by SID for the person at the computer and the engine's account, `Get-OtherMsaAccounts`, `Get-ManagedReason` (cached, fail-closed) / `Get-ManagedReasonNow` (session hive included). **Wipe:** `Disable-GdidWlid` / `Restore-GdidWlid` / `Get-GdidWlidJournalEntry` (write-ahead journal entry `svc|wlidsvc`, restore by `Restore-JournalEntry`, entry removed afterwards, resumes an interrupted wipe's entry), `Get-GdidCredUsers` + `Clear-GdidUserCreds` (session user and other signed-in users, each by SID; engine store verified when it is not the session user), `Remove-GdidRegistryCopies`, `Clear-GdidCdpCache` (session path, `others` counted as unchecked), `Invoke-GdidWipe` with stages, `try/catch/finally`, verification before restore and `$script:GdidWipeResult` (`Clean`, `NotFound`, `Partial`, `Failed`, `AccessDenied`, `Unverified`; success = first two). **Restore:** `Restore-GdidServiceStarts` (journal-based: `restored` / `notChanged` / `failed`), `Sync-GdidRestoredServices` (passes the start type to the service manager, starts automatic services and per-user copies, reports `pending` vs `failed`). **Status:** new fields `scanState`, `transmitState`, `transmitPending`, `transmitKnown`, `transmitProblems`, `ddsPresent`, `lockPresent`; `services[]` gains `state`, `error`, `scmStart`, `instances`; `ddsBlocked` / `locked` now mean "block intact and current" |
| `29-gdid-commands.ps1` | `-GdidReissue`: lock judged by the intact block, warns about a damaged one, JSON gains `wipe`, exit 2 on failures. `-GdidRestore`: guard profile first (with error check), journal-based service restore with honest per-service result, `$null =` on `Remove-HostsBlock`, firewall "absent" vs "failed", `Sync-GdidRestoredServices`, note about a wlidsvc disabled outside the program, JSON gains `restore`, exit 2 on failures |
| `10-apply-check.ps1` | Hosts: `Get-HostsMarkInfo`, `Test-HostsKindMatch`, `Get-HostsKindDomains`, `Split-HostsBlocks` (blocks closed only by an end marker of the same kind; unclosed blocks own only consecutive lines of their own domains; orphaned end markers removed); `Get-HostsLinesWithout`, `Get-HostsBlockLines`, `Test-HostsBlockCurrent` (exactly one intact block, exact set, no duplicates, no orphans) rebuilt on it; `Apply-Hosts` and `Remove-HostsBlock` re-read and verify. `Check-Def gdidwipe` uses `Get-GdidScan` and marks `unverified`; `Apply-Def gdidwipe` requires an intact lock block |
| `14-startup.ps1` | the guard skips `unverified` results (no wipe on every run when a place is unreadable) |
| `20-dossier-footprint.ps1` | the "sending" warning uses `Get-GdidTransmitState` |
| `32-apply.ps1` | warning about other Microsoft accounts before the lock |

### Window

| File | Change |
|---|---|
| `PageGdid.cs` | "Sending" tile from `transmitState` ("after a restart", "not verified"), subtitle "three services and their servers"; "New ID issuing" shows "block damaged" when the block is intended but not intact; services list shows start -2 ("could not be read") and per-user copies of CDPUserSvc |
| `Mocks.cs` | GDID mock with new fields; `WIN11_TEST_GDIDSTATE=pending` variant for the layout check |
| `lang-en8.txt`, `Lang.cs` | 10 new strings (regenerated with `tools/gen_lang.py`) |

### Tests and docs

| File | Change |
|---|---|
| `tests/engine-tests.ps1` | new section "Номер устройства: аудит GDID" (isolated `Start-Job`, stubs and own registry keys); hosts section extended (damaged/orphaned/duplicated blocks, repeated lock, IPv4/IPv6, write failures); status and footprint JSON checks; existing wipe section adapted to the new helpers (stubs saved and restored); static checks updated |
| `tests/engine.Tests.ps1` | Context 9: transmission states, scan `Unverified`, hosts parsing (Pester 3.4 and 5 compatible) |
| `CHANGELOG.md` | bilingual entry under «Не выпущено» (LF) |
| `docs/security/GDID_AUDIT.md`, `README.md` | this report and its index entry |

## 5. Tests — the 20 scenarios

All new checks run without administrator rights and change nothing on the machine: services,
the credential store, the journal and the firewall are stubs, registry work happens on
`HKCU:\Software\W11PGdidAudit-*` keys, hosts on a temporary file.

| # | Scenario | Where | Check |
|---|---|---|---|
| 1 | all three services disabled | engine-tests, Pester | `GDID 1`, Pester "передача: все три отключены" |
| 2 | CDPUserSvc enabled | engine-tests, Pester | `GDID 2` |
| 3 | DoSvc enabled | engine-tests | `GDID 3` |
| 4 | CDPSvc enabled | engine-tests | `GDID 4` |
| 5 | service missing | engine-tests (stub + real registry), Pester | `GDID 5`, "службы нет — Missing" |
| 6 | registry access denied | engine-tests (stub `Start`, locked test key) | `GDID 6`, "опись: место без доступа — «не проверено»" |
| 7 | multiple profiles | engine-tests | `GDID 7` (copies of three roots, identity labels by SID) |
| 8 | unloaded profiles | engine-tests, Pester | `GDID 8`, "профили не в Windows — «не проверено», не успех" |
| 9 | Microsoft account | engine-tests | `GDID 9` (person at the computer by SID, engine under a local admin) |
| 10 | local account | engine-tests | `GDID 10` |
| 11 | Entra ID / domain / MDM | engine-tests | `GDID 11`, fail-closed check, refusal order |
| 12 | Credential Manager cleanup failure | engine-tests | `GDID 12` (+ system store, + other signed-in user) |
| 13 | registry cleanup failure | engine-tests (Deny SetValue on the test key) | `GDID 13` → `AccessDenied` |
| 14 | CDP cleanup failure | engine-tests | `GDID 14` → `Partial` |
| 15 | failure in the middle of the wipe | engine-tests | `GDID 15` (services and wlidsvc restored in `finally`) |
| 16 | restore after partial failure | engine-tests | `GDID 16` ×2 (wlidsvc from an interrupted wipe's journal entry; `failed` ≠ `notChanged`) |
| 17 | repeated restore | engine-tests | `GDID 17` |
| 18 | corrupted hosts | engine-tests, Pester | unclosed block keeps user lines, orphaned end marker, foreign line inside a block, duplicated block, empty lock block, extra line |
| 19 | repeated GDIDLOCK apply | engine-tests | "повторный запрет выдачи не дописывает блоков", IPv4 + IPv6, gdid/lock independent |
| 20 | JSON and exit codes | engine-tests | status JSON fields (old + new), footprint agreement, exit 2 text check, live exit 1 without admin rights |

Detection check: the new tests were run against the engine of `HEAD` (`57a2a87`): 60 of
108 checks of the extracted sections fail there (missing functions, wrong answers), and all
pass against the fixed engine.

## 6. Results

All on the final working tree (engine rebuilt from the parts).

| Check | Where | Result |
|---|---|---|
| `python tools/build_engine.py --check` | host | engine matches the parts (33 parts, 10156 lines) |
| AST: engine and tests parse without errors | host, `Parser::ParseFile` | 0 errors in `Win11-Privacy-Engine.ps1`, `tests/engine-tests.ps1`, VM `guest-gdid.ps1` |
| AST: every called function is defined above the call (engine-tests check) | host, VM | passed |
| `tests/engine-tests.ps1`, standard user | host (Windows 11 26300) | **739 passed, 0 failed** |
| `tests/engine-tests.ps1`, administrator | test VM (Windows 11 Home ru-RU 26300, reverted to the clean snapshot) | **746 passed, 0 failed** |
| `tests/engine.Tests.ps1` (Pester 3.4) | host / VM | **44 / 44 passed** |
| SelfTest (`/define:SELFTEST`, without `app.res`, `WIN11_TEST_ENGINE` = repo engine) | host | **125 passed, 0 failed** |
| Release build (`csc` with `app.res`, engine embedded) | host | compiled without errors or warnings |
| UI layout of the Device ID page (`/define:UITEST`, mock incl. `WIN11_TEST_GDIDSTATE=pending`, RU/EN, default and minimum size) | host | no clipped or overflowing text |
| `tools/gen_lang.py` + `tools/check_lang.py` | host | 1558 pairs, all translated |
| PSScriptAnalyzer 1.23.0 (Microsoft-signed), Error + Warning, changed parts | host | **0 errors**. Warnings vs. `HEAD`: `10-apply-check` 22 → 24, `12-gdid` 25 → 40, `14-startup` 14 → 14, `20-dossier-footprint` 8 → 8, `29-gdid-commands` 0, `32-apply` 0. All new warnings are naming/style rules already present in these files (`PSUseSingularNouns` for names such as `Get-GdidUserSvcInstances`, `PSUseShouldProcessForStateChangingFunctions`, `PSAvoidUsingEmptyCatchBlock` for intentional fallbacks) |

Not run here: the live GDID phases in the VM (`host-run.ps1 -Steps "clean,copy,A,B,reboot,C,fetch"`,
about an hour: real wipe, lock, reboot, restore). `guest-gdid.ps1` was updated for the new
helpers and now logs the wipe stages, `transmitState` and the service manager's view before
and after the reboot, and checks that a second restore changes nothing (exit 0). That run is
what settles GDID-19 (the service manager keeping "Automatic" until reboot) on a real system.

## 7. PowerShell 5.1 assessment

* Only Windows PowerShell 5.1 language and cmdlets: no `??`, ternary, `-AsHashtable`,
  `ForEach-Object -Parallel`. `Get-Service -ErrorVariable` separates "no such service"
  (`NoServiceFoundForGivenName`) from real errors. `Get-LocalUser -SID` is in the in-box
  `Microsoft.PowerShell.LocalAccounts` (64-bit host; on failure the profile fallback
  answers on the cautious side).
* Known 5.1 pitfalls avoided: no `@()` around `List[object]` holding hashtables (the test
  hit exactly this once and was fixed), functions return `ToArray()` inside hashtables so
  empty arrays survive, bare status-returning calls assigned to `$null`, no locals
  shadowing parameters (`Split-HostsBlocks`/`Get-HostsLinesWithout` copy `$Lines` into
  `$src`).
* Registry reads go through .NET (`Open-RegKeyRead`, `GetSubKeyNames`) where the provider
  would open every subkey (the Services key contains keys a standard user cannot open).
* Every new function is defined above its first top-level call (AST check passes).
* Encoding: engine parts UTF-8 with BOM + CRLF, CHANGELOG LF without BOM, VM scripts ASCII
  in new lines.

## 8. Remaining limitations

* Profiles of users who are not signed in are not loaded and wiped; the scan and the wipe
  say "not verified" for them instead of "clean". On a computer with such profiles the
  audit item "ID wiped" of the lock module therefore stays "not verified" (not counted as
  applied); the guard does not re-wipe because of it. (Loading their hives is possible with
  `Use-ProfileHive`, but mounting another user's profile while they may sign in was left
  out of this change.)
* The CDP cache of other signed-in users is not cleaned (it lives in their profile and is
  cleaned only by a task in their name for the session user); it is counted as unchecked.
* Services disabled by the `gdid` module stay startable until a reboot (GDID-19): the
  status now says "after a restart" instead of "blocked". The apply path was not changed.
* GDID-17, GDID-18, GDID-20 – GDID-23 above.
* `C:\w11p` VM harness: `guest-gdid.ps1` (outside the repository) was updated for the new
  helpers and fields; older VM scripts that extract engine functions by name may need the
  same update when they touch GDID code.
