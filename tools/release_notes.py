# -*- coding: utf-8 -*-
"""Собирает описание релиза: раздел версии из CHANGELOG.md + как запустить
и какие файлы приложены.

Раньше описание релиза было одинаковым у всех версий — только «как
запустить», а что изменилось, не говорилось вовсе. Теперь сборка по тегу без
раздела этой версии в CHANGELOG.md падает: релиз без описания не выйдет.

    python tools/release_notes.py --version 1.11.0 [--out release-notes.md]
        раздел «## 1.11.0» (или «## v1.11.0», «## [1.11.0] — дата»)
    python tools/release_notes.py --version unreleased
        раздел «## Не выпущено» — посмотреть, как будет выглядеть
"""

import argparse
import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHANGELOG = os.path.join(ROOT, 'CHANGELOG.md')
UNRELEASED = ('не выпущено', 'unreleased')

FOOTER = u"""
---

**Как запустить:** скачайте `Win11Privacy.exe`, правый клик → Свойства → галочка
«Разблокировать» → ОК, затем запустите. Программа запросит права администратора —
они нужны, потому что она меняет системные настройки. Ничего устанавливать не
требуется: приложение работает на встроенном в Windows .NET Framework 4.8, движок
вшит внутрь exe.

**How to run:** download `Win11Privacy.exe`, right-click → Properties → tick
"Unblock" → OK, then run it. It asks for administrator rights because it changes
system settings. Nothing to install: it runs on the .NET Framework 4.8 built into
Windows, and the engine is embedded in the exe.

| Файл / File | Зачем / What for |
|---|---|
| `Win11Privacy.exe` | Само приложение / The application |
| `Win11-Privacy-Engine.ps1` | Движок отдельно — можно изучить и запустить без интерфейса / The engine on its own, to read or run without the window |
| `SHA256SUMS.txt` | Контрольные суммы / Checksums |
| `winget-manifest.zip` | Манифест winget этой версии / The winget manifest for this version |

Проверить скачанный файл / Verify the download:
```
Get-FileHash Win11Privacy.exe -Algorithm SHA256
```

Все изменения по версиям / All changes by version: [CHANGELOG.md]({repo}/blob/main/CHANGELOG.md)
"""


def heading_version(line):
    """«## [1.11.0] — 2026-11-12» -> «1.11.0»; «## Не выпущено» -> «не выпущено»."""
    t = line[3:].strip()
    t = re.split(r'\s+[—–-]\s+', t, 1)[0].strip()
    t = t.strip('[]').strip()
    if t.lower().startswith('v') and re.match(r'v\d', t, re.I):
        t = t[1:]
    return t.lower()


def section(text, version):
    want = version.lower().lstrip('v')
    if want in UNRELEASED:
        targets = UNRELEASED
    else:
        targets = (want,)
    lines = text.splitlines()
    out, inside = [], False
    for line in lines:
        if line.startswith('## '):
            if inside:
                break
            inside = heading_version(line) in targets
            continue
        if inside:
            out.append(line)
    body = '\n'.join(out).strip()
    return body


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--version', required=True)
    ap.add_argument('--out')
    ap.add_argument('--repo', default=os.environ.get('GITHUB_SERVER_URL', 'https://github.com') + '/' +
                    os.environ.get('GITHUB_REPOSITORY', 'N0deZ3r0/Win11Privacy'))
    a = ap.parse_args()
    if not os.path.exists(CHANGELOG):
        sys.exit('нет CHANGELOG.md')
    text = io.open(CHANGELOG, encoding='utf-8-sig').read()
    body = section(text, a.version)
    if not body:
        sys.exit(u'в CHANGELOG.md нет раздела «## %s» — опишите, что нового в этой версии' % a.version)
    title = u'не выпущено' if a.version.lower() in UNRELEASED else u'v' + a.version.lstrip('v')
    notes = u'## Приватность Windows 11 — %s\n\n%s\n%s' % (title, body, FOOTER.replace('{repo}', a.repo))
    if a.out:
        io.open(a.out, 'w', encoding='utf-8', newline='\n').write(notes)
        print(u'описание релиза: %s (%d строк)' % (a.out, notes.count('\n') + 1))
    else:
        sys.stdout.write(notes)
    return 0


if __name__ == '__main__':
    sys.exit(main())
