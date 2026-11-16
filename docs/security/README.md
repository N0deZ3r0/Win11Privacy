# Security reviews

Reports of the security reviews done before release 2.1.0, newest first. They were
written against the working tree before the release commit, so "nothing was
committed or pushed" in them describes that moment.

| Report | What it covers |
|---|---|
| [SECURITY_REMEDIATION_REPORT.md](SECURITY_REMEDIATION_REPORT.md), pass of 2026-11-16 | After 2.1.0: named-lock squatting (T-1), audit-policy temp file (T-2), crash-safe restore from a backup (T-3), "file busy" read as "missing" on PowerShell 5.1 (T-4), GDID user context and interrupted wipe; `FINAL_SECURITY_AUDIT.md` and `GDID_AUDIT_3.md` (section 8) updated with it |
| [GDID_AUDIT_3.md](GDID_AUDIT_3.md) | After 2.1.0: GDID third pass — preflight before any change, exact deletion, service snapshot and rollback, one result shape; section 8 — follow-up of 2026-11-16 |
| [GDID_AUDIT.md](GDID_AUDIT.md) | After 2.1.0: the device ID (GDID) subsystem — honest "sending off" over all three services, scan without false "clean", wipe in stages with wlidsvc in the journal, journal-based restore, hosts block pairing, account checks for the person at the computer |
| [FINAL_SECURITY_AUDIT.md](FINAL_SECURITY_AUDIT.md) | Final pass: backups only in the protected store (W11P-005), full ACL and path checks (W11P-006), the shared Firefox lock, manifest downgrade; test evidence and the release decision |
| [SECURITY_REMEDIATION_REPORT.md](SECURITY_REMEDIATION_REPORT.md) | Backup signing race (W11P-001), atomic Firefox `policies.json` (W11P-002), honest exit codes (W11P-003) |
| [F08_FIX_REPORT.md](F08_FIX_REPORT.md) | The engine request on standard input instead of a command line built from data (F-08) |
| [AUDIT_REPORT.md](AUDIT_REPORT.md) | Third audit of 2.0.0 (F-01 … F-08) |

How the program protects its data, journal and rollback is described in
[../security-model.md](../security-model.md); how to report a vulnerability — in
[SECURITY.md](../../SECURITY.md).
