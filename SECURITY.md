# Security Policy

**English** · [Русский](#политика-безопасности)

## Supported versions

Security fixes are published for the **latest release** only.

| Version | Supported |
| ------- | --------- |
| Latest release | Yes |
| Anything older | No |

## Reporting a vulnerability

**Do not open a public issue.** Use a
[private security advisory](https://github.com/N0deZ3r0/Win11Privacy/security/advisories/new) —
only the maintainer can read it.

Please include:

- The version shown on the **About** page
- Windows edition and build (`winver`)
- What an attacker could achieve, and the steps to get there
- A log excerpt or screenshot, if you have one

You can expect a first reply within **48 hours**, and a decision on whether the
report is accepted within a week. If it is accepted, you will be credited in the
release notes unless you would rather not be.

## Scope

Win11Privacy changes registry keys, scheduled tasks, services, firewall rules
and ETW trace sessions, and it runs elevated. In scope:

- A change applied outside what the user selected
- A rollback that does not restore the previous value
- Privilege-escalation paths opened by the tool's own elevated operation
- The portable-mode data directory being readable by other users
- Backups or logs leaking data the tool was meant to erase

Out of scope: telemetry that Windows collects and this tool does not claim to
disable, and vulnerabilities in Windows itself.

---

# Политика безопасности

**Русский** · [English](#security-policy)

## Поддерживаемые версии

Исправления безопасности выходят только для **последнего релиза**.

## Как сообщить об уязвимости

**Не создавайте публичную задачу.** Используйте
[приватный security advisory](https://github.com/N0deZ3r0/Win11Privacy/security/advisories/new) —
его видит только сопровождающий.

Приложите версию программы (страница «О программе»), издание и сборку Windows
(`winver`), что именно может сделать злоумышленник и шаги воспроизведения.

Первый ответ — в течение **48 часов**, решение по существу — в течение недели.
Если отчёт принят, вас упомянут в примечаниях к релизу, если вы не против.

## Что в области действия

Программа правит реестр, задачи планировщика, службы, правила брандмауэра и
сессии трассировки ETW, и работает с правами администратора. В области действия:
изменение сверх выбранного пользователем, откат, не возвращающий прежнее
значение, пути повышения привилегий через саму программу, доступность данных
переносимого режима другим пользователям, утечка через журналы и резервные копии.

Вне области: телеметрия Windows, которую программа не заявляет отключаемой, и
уязвимости самой Windows.
