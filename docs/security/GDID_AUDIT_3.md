# GDID audit, third pass: preflight, data preservation, honest results

Repository: Win11Privacy. Audited revision `66c9670` (after the second GDID pass). Report date 2026-11-15.
Scope: the engine's device-ID subsystem (`engine/12-gdid.ps1`, `engine/29-gdid-commands.ps1`,
the GDID parts of `06-journal-entries.ps1`, `28-changes.ps1`, `20-dossier-footprint.ps1`,
`32-apply.ps1`), its tests and the VM guest script.
Committed and pushed to `main` (no tag, no release). The CHANGELOG entry is under «Не выпущено».

---

## 1. How the brief compared with the code

The brief was written against an older build of the engine. At `66c9670` several of its P0 items
were already fixed. I checked each one in the code and kept or extended its regression test:

| Brief item | State at `66c9670` | Evidence |
|---|---|---|
| 1A transmitOff ignores CDPUserSvc | already fixed: `Get-GdidTransmitState` checks CDPSvc, CDPUserSvc, the `CDPUserSvc_*` copies, and both the registry and the service manager. `Get-GdidStatus` and `Get-Footprint` both call it | tests "GDID 1–6", "копия CDPUserSvc…" |
| 1B `$unchecked` not in the success condition | already fixed: `Clean` requires `$unchecked -eq 0` | test "профили не в Windows — «не проверено», не успех" |
| 1C GdidReissue exits 0 on failure | already exited 2 when `$script:Failures -gt 0`. Hardened here: the code now comes from the result object itself | new tests "GDID3 15" |

All other items were still open, fully or in part. The table in section 2 lists them.

## 2. Confirmed defects (fixed)

| ID | Defect at `66c9670` | Fix | Test(s) that prove it |
|---|---|---|---|
| G3-01 | **No real preflight.** `Invoke-GdidWipe` ran the inventory, ignored `GdidUnreadable` and started disabling and stopping services, then deleting, with unreadable places present. | New `Get-GdidPreflight`, read-only: inventory without unreadable places, a readable profile list, a complete service snapshot. Any blocker means nothing changes: state `Failed`, or `Unverified` when nothing was found. | `GDID3 10` (place denied), `GDID3 4-5` (profile list), `GDID3 12` (wlidsvc start type), old block "…и не начинается: ни служб, ни удаления" |
| G3-02 | **DryRun always succeeded** (`state = 'DryRun'; return $true` before any check). | DryRun runs the same preflight. It succeeds only when the real run could reach a verified result. Unloaded profiles or other users' caches give `Unverified`, and a blocked preflight gives `Failed`. | `GDID3 11` ×2, "пробное стирание ничего не меняет" |
| G3-03 | **Running-service list collected with `-ErrorAction SilentlyContinue`.** An enumeration error gave an empty list. `Stop-ServiceWait 'wlidsvc'` then ran anyway, so wlidsvc could end up stopped and never restarted. | `Get-GdidServiceSnapshot` reads every relevant service (registry start type and SCM status) and the `CDPUserSvc_*` instances. If it is incomplete, the wipe does not start. Restore starts exactly the services that the wipe tried to stop and that were running in the snapshot. | `GDID3 3/12` (snapshot incomplete), `GDID3 14` (rollback), "служба, что стояла до стирания, не…" |
| G3-04 | **wlidsvc start-type read failure did not stop the wipe.** `Disable-GdidWlid` returned `ok` and the wipe continued with wlidsvc enabled, so it could mint a new ID mid-wipe. | `Disable-GdidWlid` returns `ok = $false`, so the wipe aborts with nothing changed. The snapshot also blocks it earlier. | `GDID3 12` ×2 |
| G3-05 | **Restore trusted `Start-Service`.** Success meant "no exception". | `Restore-GdidServices` re-reads the SCM status after the start. It then compares every snapshot service, start type and running state, with the state after. It returns `notBack` and `states` (before/after per service). | `GDID3 14`, "служба, что не вернулась после стирания, — не успех" |
| G3-06 | **`Stop-ServiceWait` treated any `Get-Service` error as "stopped".** | Only `NoServiceFoundForGivenName` counts as "nothing to stop". Any other error means the service did not stop. | covered by G3-03 tests (stop path) |
| G3-07 | **DeviceIdentities: discovery skipped `Logs`, deletion removed the whole `production` tree** (Logs, `DeviceLicenseUpdateFailureCount`, unknown keys and values). | Discovery and deletion share one inventory (`Get-GdidCopies` records with exact paths). An identity is a `production\<SID>\<name>` key that has a `DeviceId` value. The container's `ValidDeviceId` is removed only when it points to that identity. Keys without `DeviceId` are not counted and not touched (`GdidUnknown`). An identity with subkeys is kept intact (`kept`, so the result is `Partial`). Each removal is re-read. | old block: "личность устройства убрана", "указатель…убран", "Logs сохранён", "чужие значения…сохранены", "подключ без DeviceId сохранён"; `GDID3 8-9` |
| G3-08 | **NegativeCache listing via `Get-ChildItem`** opened every subkey. An unreadable cache entry with a matching name was reported as an unreadable "place", not as the copy it is. Deletion used `Remove-RegStatus` without a check afterwards. | Names are read through the registry API (`Read-GdidKey`), so a missing key and an unreadable key are told apart. Matching entries are removed with `DeleteSubKeyTree` and re-read. An unreadable cache blocks the wipe, and a direct removal reports `Partial` / `unreadable`. | `GDID3 7` ×4 |
| G3-09 | **Profile enumeration returned a bare integer**, and `0` on failure. | `Get-UncheckedProfiles` returns `loadedProfiles`, `unloadedProfiles`, `unloadedSids`, `enumerationFailed`, `unverified`, `places`, `errors` and `state` (`Complete`, `Unloaded`, `EnumerationFailed`). An enumeration failure is never zero. It makes the scan `Unverified` and blocks the wipe. Entra ID profiles (`S-1-12-1-…`) are counted too. | "GDID 8", "опись: список кустов не прочитался…", Pester "опись: …", `GDID3 4-5` |
| G3-10 | **Remove-GdidRegistryCopies** deleted by fixed paths (`Test-Path` treats access denied as "exists"). It removed whole keys and did not verify. | It deletes the inventory's records one by one, with `removed`, `absent`, `denied` or `kept`, and re-reads each removal. Its state is `Clean`, `NotFound`, `Partial`, `AccessDenied` or `Unverified`. | "GDID 13", `GDID3 7`, `GDID3 8-9` |
| G3-11 | **CDP cache verification**: `Get-ChildItem -Recurse -File` did not see links. An unreadable folder looked empty, and `Test-Path` decided "missing". | `Get-GdidDirLeft` walks the cache without following reparse points and counts a link as left over. A folder it cannot list counts as unverified, and depth is limited. The root is checked with `Get-Item`, so not-found and denied are told apart. A link in place of the root is not cleaned. | `GDID3 20` ×7 |
| G3-12 | **GdidRestore did not check the hosts block removal** (`$null = Remove-HostsBlock`). Firewall removal was not re-read, and the guard profile write was not re-read. | Each stage is verified: hosts blocks are counted before and after, the firewall rule is re-queried after removal, and `profile.json` is re-read. Each stage is `Restored`, `NotModified`, `NotFound`, `AccessDenied` or `RestoreFailed`. | `GDID3 17`, `GDID3 18` ×2, "профиль стража не сверился" |
| G3-13 | **Restore of a vanished service was reported as restored.** `Restore-JournalEntry` treated any `Get-Service` error, access denied included, as "service gone". It returned ok, and the journal entry was deleted. | `Restore-JournalEntry` decides "gone" by the service's registry key (`missing`). An unreadable key returns `denied`. `Restore-GdidServiceStarts` pre-checks the start type: `Missing` gives `notFound` and the journal entry stays, `ReadError` gives `accessDenied`. After a restore it re-reads the start type against the journal's `old`. `Restore-RegValue` and `Restore-ChangeKey` pass `denied` and `missing` through. | `GDID3 16` ×3 |
| G3-14 | **Detection gaps**: hybrid join was reported as "domain". OMA-DM accounts were not checked. A work account and device management looked the same. A local account with a Microsoft account connected only to the Store was judged by the same heuristic as a non-local account, and `S-1-12-1` (Entra) accounts were ignored. `Get-OtherMsaAccounts` hid errors. | `Get-GdidManagement` returns `kind` (`domain`, `entra`, `hybrid`, `mdm`, `workAccount`, `unknown`), `managed` and `workAccount`. Read failures give `unknown`, which means refusal. `Get-GdidAccountKind` returns `source`, `signInMsa`, `connectedMsa` and `known`. Status JSON gains `managedKind`, `workAccount` and `accounts`, and the lock apply warns when other accounts could not be listed. | `GDID3 19` ×3, `GDID3` account checks ×3, "GDID 9–11" |
| G3-15 | **Result model**: wipe and restore had different ad-hoc hashtables, and the exit code was derived only from `$script:Failures`. | `New-GdidResult` / `Set-GdidResultState` hold one shape for both: `operation`, `status`, `success`, `complete`, `checked`, `removed`, `remaining`, `failed`, `unverified`, `uncheckedProfiles`, `serviceStates`, `warnings`, `errors`, `timestamp` and `exitCode`, plus the old `state`, `before`, `after`, `stages` and `notBack`. `Get-GdidExitCode` gives 0 only when `success` is true and no failure was counted. That value goes both into the JSON and to `exit`. | `GDID3 15` ×3, `GDID3 21` ×2, `GDID3 22` |
| G3-16 | "Digital footprint" said "передаётся" (being sent) even when the transmit state was `Unknown`. | It now says "не проверено" (not verified) for `Unknown`. | (same function as the tab, covered by the `Get-GdidTransmitState` tests) |
| G3-17 | **Found on the VM (open item GDID-19 of the second pass).** After a reboot with the GDID services disabled in the registry, `GdidRestore` put `Start=2` back. `Get-GdidStatus` and `sc qc` then said "automatic", because they read the registry, but the service manager still held "disabled" in memory. `Start-Service` failed with **1058** (`ERROR_SERVICE_DISABLED`). `Sync-GdidRestoredServices` called `Set-Service` only when `Get-Service` said "Disabled", so it never told the service manager, and CDPSvc and DoSvc were reported as start failures (exit 2). | `Set-Service -StartupType` (ChangeServiceConfig, which updates the in-memory record) is now always called for each restored service and for the CDPUserSvc template. If Windows refuses it (DoSvc refuses even administrators) and the start then fails with 1058, the service is reported as *pending until reboot*, not failed. Other start errors stay failures. | "GDID3 (VM): тип запуска — диспетчеру служб всегда; ошибка 1058…", "после возврата: CDPSvc и копия CDPUserSvc запущены…", "служба не запустилась после возврата — ошибка"; VM phase C rerun (section 7) |

## 3. Potential defects / things not changed

* **Work accounts still refuse the wipe and the lock.** I kept this conservative choice, but the reason now says
  that the device is *not* managed (`managedKind = workAccount`). If evidence shows the MSA device identity is
  independent of the Entra registration, this can be relaxed.
* **Unloaded profiles are still not mounted.** Their copies are reported (`uncheckedProfiles`, warnings, and the result is
  `Unverified`), never wiped. A safe mount (hive load and unload with locking) exists elsewhere in the engine, but
  it has not been validated for IdentityCRL and was left out on purpose.
* **Other signed-in users' CDP caches** are not cleaned, as before. They count towards `uncheckedProfiles`.
* **Identity containers** (`production\<SID>`) are kept even when they are empty after the wipe. This is data-preserving and
  needs VM confirmation that Windows mints a new identity into an existing empty container (see section 7).
* `Restore-RegValue` with `existed = true` would still recreate a missing service key in a general rollback.
  GDID restore avoids that with the `Missing` pre-check. The general rollback path is out of scope.
* PSScriptAnalyzer style findings (empty `catch`, `ShouldProcess`, plural nouns) match the baseline style.
  No new rule categories appeared.

## 4. Files changed

* `engine/12-gdid.ps1` — `Get-UncheckedProfiles` (structured), `Read-GdidKey`, `Open-GdidKeyWrite`,
  `Remove-GdidRegValue`, `Remove-GdidRegKey`, `Remove-RegStatus` (verifies), `Get-GdidSvcEntry`,
  `Get-SvcScmView` (+`status`), `Get-GdidTransmitState` (uses the shared entry), `Get-GdidServiceSnapshot`,
  `Get-GdidCopies` (one inventory with paths), `Get-GdidScan` (+`profiles`, `unknown`),
  `Get-GdidAccountKind`, `Get-GdidAccounts`, `Test-MsaAccount`, `Get-OtherMsaAccounts`, `Get-GdidManagement(Now)`,
  `Get-ManagedReason(Now)`, `Disable-GdidWlid`, `Restore-GdidServices`, `Stop-ServiceWait`,
  `Remove-GdidRegistryCopies`, `Get-GdidDirLeft`, `Clear-GdidCdpCache`, `New-GdidResult`, `Set-GdidResultState`,
  `Get-GdidPreflight`, `Invoke-GdidWipe`, `Restore-GdidServiceStarts`, `Get-GdidHostsFound`, `Get-GdidStatus`.
* `engine/29-gdid-commands.ps1` — `Get-GdidExitCode`, GdidReissue and GdidRestore with staged, verified results.
* `engine/06-journal-entries.ps1` — `Restore-JournalEntry` (service gone or denied, `denied` flag), `Restore-RegValue` (`denied`).
* `engine/28-changes.ps1` — `Restore-ChangeKey` passes `denied`, `missing` and `note` through.
* `engine/20-dossier-footprint.ps1` — "не проверено" (not verified) for an unknown transmit state.
* `engine/32-apply.ps1` — warning when other Microsoft accounts could not be listed.
* `Win11-Privacy-Engine.ps1` — rebuilt with `tools/build_engine.py`.
* `tests/engine-tests.ps1`, `tests/engine.Tests.ps1` — updated and new regression tests (section 5).
* `CHANGELOG.md` — «Не выпущено».
* Outside the repository: `D:\Win11PrivacyVM\tools\guest-gdid.ps1` — the new helpers are added to the
  extraction lists, plus checks that `Logs` survives and that the exit code matches the JSON.

## 5. Regression tests

All the tests use stubs and their own keys under `HKCU:\Software\W11PGdidAudit-*` /
`HKCU:\Software\Win11PrivacyGdidTest` and temp folders. Services, credentials, the journal and the real
IdentityCRL are not touched.

| # | Brief case | Test |
|---|---|---|
| 1 | CDPUserSvc enabled | "GDID 2" |
| 2 | multiple CDPUserSvc instances | "GDID3 1-2" |
| 3 | service registry access denied | "GDID 6", "GDID3 3", "GDID3 3/12" |
| 4 | HKU enumeration failure | "опись: список кустов не прочитался…", "GDID3 4-5" |
| 5 | ProfileList enumeration failure | Pester "опись…", "GDID3 4-5" |
| 6 | unloaded profiles | "GDID 8", "профили не в Windows…", "GDID3 11" |
| 7 | NegativeCache enumeration failure | "GDID3 7" ×4 |
| 8 | DeviceIdentities Logs preserved | "DeviceIdentities\production\Logs сохранён" |
| 9 | unrelated values preserved | "чужие значения в DeviceIdentities сохранены", "подключ без DeviceId сохранён", "GDID3 8-9" |
| 10 | incomplete preflight | "GDID3 10", "…и не начинается" |
| 11 | DryRun with unreadable locations | "GDID3 11" ×2 |
| 12 | wlidsvc StartType read failure | "GDID3 12" ×2 |
| 13 | service stop failure | "служба не остановилась — …", old block "служба не остановилась — номер не стирается" |
| 14 | rollback after partial cleanup | "GDID 15", "GDID3 14" |
| 15 | GdidReissue nonzero exit on failure | "GDID3 15" ×3 (the real command block runs on stubs) |
| 16 | GdidRestore journal failure | "возврат при недоверенном журнале…", "GDID3 16" ×4 |
| 17 | HOSTS restoration failure | "GDID3 17" |
| 18 | firewall removal failure | "GDID3 18" ×2 |
| 19 | MDM detection uncertainty | "GDID3 19" ×3 |
| 20 | CDP junction handling | "GDID3 20" ×7 |
| 21 | JSON and GUI protocol compatibility | "GDID3 21" ×5 (the real engine's `-GdidStatus`, read-only) |
| 22 | repeated cleanup and restore | "повторное стирание…", "GDID 17", "GDID3 22" ×2 |

## 6. Results

Local runs (Windows 11 26300, Windows PowerShell 5.1.26100, as a non-administrator):

| Check | Result |
|---|---|
| `python tools/build_engine.py` / `--check` | built (33 parts, 10 781 lines) / matches |
| PowerShell AST parse: built engine, every part, both test files | 0 errors |
| `tests\engine-tests.ps1` | **800 passed, 0 failed**. The first run, before one old check was adjusted, had 786 / 1: the old check expected a CDP cleanup call when the cache folder did not exist, and the new code no longer cleans a folder that is not there. |
| `tests\engine.Tests.ps1` (Pester 3.4) | 44 passed, 0 failed |
| C# SelfTest against the real engine (`WIN11_TEST_ENGINE`) | 125 passed, 0 failed |
| `tools/check_lang.py` | all translated |
| PSScriptAnalyzer 1.25 (changed parts) | 0 errors. The warnings are the same style categories as the baseline (empty catch, ShouldProcess, plural nouns), with no new rule types. In `12-gdid.ps1`: 44 now, 40 at the baseline. |
| `-GdidStatus` on the developer PC (read-only) | exit 0. All old fields are present, and the new fields are filled in (`profiles.state = Complete`, `managedKind = ''`, `accounts[0].source = MicrosoftAccount`). |

The real IdentityCRL layout was read on the developer PC (key and value **names** only, no data).
That is where the identity shape `production\<SID>\<02…>` with `DeviceId` (an XML blob), `ValidDeviceId`
in the container, `Logs\<02…>` with "Provision …" timestamps, and NegativeCache entries with one
subkey each came from.

## 7. Needs Windows 11 VM verification

### Done on the VM (VMware, Windows 11 Home ru-RU 26300, local administrator, snapshot `before-deep`)

Run 1 (`clean,copy,tests,pester,A,B,reboot,C,fetch`), then run 2 after the G3-17 fix
(`copy,tests,B,reboot,C,fetch`):

| Check | Result |
|---|---|
| `tests\engine-tests.ps1` as administrator in the guest | 807 / 0 (run 1), **808 / 0** (run 2) |
| Pester in the guest | 44 / 0 |
| A: `-GdidReissue` on a real identity (25 copies) | `Clean`, exit 0, `exitCode` in the JSON equals the process exit code; preflight passed, `checked=25 removed=42 remaining=0` |
| A: `DeviceIdentities\production\Logs` | **kept** (its subkeys are still there after the wipe) |
| A: new ID with the narrower deletion (containers kept, only identities and their `ValidDeviceId` removed) | **Windows minted a new device ID within 33 s**, and the old IDs did not come back |
| B: lock (`gdid,gdidlock`) | blocked, no copies, audit 4/4 and 3/3, no ID for 8 minutes of service pokes |
| C: after the reboot | no ID for 6 minutes, transmission `Off` |
| C: `-GdidRestore`, run 1 | exit 2, `Partial`: CDPSvc and DoSvc failed with 1058. Diagnosed with `sc qc` / `sc start` in the guest. This became G3-17. |
| C: `-GdidRestore`, run 2 (after the fix) | **`Restored`, exit 0, CDPSvc and DoSvc running**. The CDPUserSvc copy is honestly `pending` until the next sign-in. The second restore gives `NotModified`, exit 0. |
| C: after the restore | blocks removed, and Windows minted a fresh ID; none of the earlier IDs came back |

### Still needs live verification

* A preflight block on a real system: an unreadable IdentityCRL subkey or a denied service query.
  This is only covered with stubs and ACL-locked test keys under HKCU.
* A machine with a second local profile that is **not** signed in: the wipe should end `Unverified`,
  with exit 2 and a warning. Covered with stubs only.
* Over-the-shoulder elevation: a standard user at the desk and an administrator's password typed in.
  The credential, CDP and account checks should all follow the person at the computer.
* Entra ID joined, hybrid joined, MDM-enrolled and Workplace-joined machines. The VM is a workgroup
  Home edition, so the refusal paths are covered with stubs only.
* A CDP cache that contains real junctions created by Windows, and a CDP folder with restricted
  ACLs on a live profile.
* An interrupted wipe (the engine killed between disabling wlidsvc and the restore), checked live:
  the journal path is covered by the second pass and its tests.
