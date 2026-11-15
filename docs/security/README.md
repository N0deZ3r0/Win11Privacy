# Security reviews

Reports of the security reviews done before release 2.1.0, newest first. They were
written against the working tree before the release commit, so "nothing was
committed or pushed" in them describes that moment.

| Report | What it covers |
|---|---|
| [GDID_AUDIT.md](GDID_AUDIT.md) | After 2.1.0: the device ID (GDID) subsystem — honest "sending off" over all three services, scan without false "clean", wipe in stages with wlidsvc in the journal, journal-based restore, hosts block pairing, account checks for the person at the computer |
| [FINAL_SECURITY_AUDIT.md](FINAL_SECURITY_AUDIT.md) | Final pass: backups only in the protected store (W11P-005), full ACL and path checks (W11P-006), the shared Firefox lock, manifest downgrade; test evidence and the release decision |
| [SECURITY_REMEDIATION_REPORT.md](SECURITY_REMEDIATION_REPORT.md) | Backup signing race (W11P-001), atomic Firefox `policies.json` (W11P-002), honest exit codes (W11P-003) |
| [F08_FIX_REPORT.md](F08_FIX_REPORT.md) | The engine request on standard input instead of a command line built from data (F-08) |
| [AUDIT_REPORT.md](AUDIT_REPORT.md) | Third audit of 2.0.0 (F-01 … F-08) |

How the program protects its data, journal and rollback is described in
[../security-model.md](../security-model.md); how to report a vulnerability — in
[SECURITY.md](../../SECURITY.md).
