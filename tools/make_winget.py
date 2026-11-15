# -*- coding: utf-8 -*-
"""Собирает манифест winget для очередного релиза.

Через winget установка выглядит так:

    winget install N0deZ3r0.Win11Privacy

и снимает сразу два вопроса: где взять файл и почему SmartScreen ругается на
скачанный exe — каталог winget проверяет хеш сам.

С версии 2.1 в каталог идёт установщик Win11Privacy-Setup.exe (Inno Setup):
winget ставит программу в Program Files с удалением через «Приложения». Выбор
«обычная установка или переносимая версия» — в самом мастере установки, а
winget всегда делает обычную установку.

Запуск (из корня проекта), хеш берётся из SHA256SUMS.txt релиза или задаётся
вручную:

    python tools/make_winget.py --sha 6f1c...  [--version 2.1.0]

Готовые файлы кладутся в packaging/winget/<версия>/ — их и отправляют
отдельным pull request в microsoft/winget-pkgs.
"""

import argparse
import io
import os
import re
import sys

# На сборке стандартный вывод Windows — cp1252, и русский текст роняет скрипт
# ошибкой кодировки. Просим UTF-8; на старых версиях python молча пропускаем.
try:
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKG_ID = 'N0deZ3r0.Win11Privacy'
REPO = 'N0deZ3r0/Win11Privacy'
SCHEMA = '1.28.0'
SCHEMA_URL = 'https://aka.ms/winget-manifest.%s.1.28.0.schema.json'


def read_version():
    src = io.open(os.path.join(ROOT, 'AppInfo.cs'), encoding='utf-8-sig').read()
    m = re.search(r'Version\s*=\s*"([0-9.]+)"', src)
    if not m:
        sys.exit('в AppInfo.cs не нашлась строка версии')
    return m.group(1)


# Файл, который ставит winget, и ключ удаления, по которому winget узнаёт
# установленную программу: AppId из installer/Win11Privacy.iss + «_is1».
SETUP = 'Win11Privacy-Setup.exe'
PRODUCT_CODE = '{D3C03EE2-3FF3-4F72-9976-D10B9424046B}_is1'


def read_sha(path, name=SETUP):
    """SHA256SUMS.txt из релиза: строки вида «<хеш>  Win11Privacy-Setup.exe»."""
    for line in io.open(path, encoding='utf-8-sig').read().splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[-1].lstrip('*').lower() == name.lower():
            return parts[0].lower()
    sys.exit('в %s нет строки про %s' % (path, name))


VERSION_YAML = u"""# yaml-language-server: $schema={schema_url_version}
# Создано tools/make_winget.py — правьте генератор, а не этот файл
PackageIdentifier: {pkg}
PackageVersion: {ver}
DefaultLocale: en-US
ManifestType: version
ManifestVersion: {schema}
"""

INSTALLER_YAML = u"""# yaml-language-server: $schema={schema_url_installer}
# Создано tools/make_winget.py — правьте генератор, а не этот файл
PackageIdentifier: {pkg}
PackageVersion: {ver}
# Установщик Inno Setup: winget знает его ключи тихой установки
# (/VERYSILENT /SUPPRESSMSGBOXES /NORESTART) и папки (/DIR=).
InstallerType: inno
Scope: machine
# Установщик сам запрашивает права администратора: программа меняет
# системные настройки, и её папка должна быть закрыта для записи
ElevationRequirement: elevatesSelf
UpgradeBehavior: install
ProductCode: '{product_code}'
AppsAndFeaturesEntries:
  - Publisher: {publisher}
    ProductCode: '{product_code}'
ReleaseDate: {date}
Installers:
  - Architecture: x64
    InstallerUrl: https://github.com/{repo}/releases/download/v{ver}/{setup}
    InstallerSha256: {sha}
ManifestType: installer
ManifestVersion: {schema}
"""

LOCALE_YAML = u"""# yaml-language-server: $schema={schema_url_locale}
# Создано tools/make_winget.py — правьте генератор, а не этот файл
PackageIdentifier: {pkg}
PackageVersion: {ver}
PackageLocale: en-US
Publisher: {publisher}
PublisherUrl: https://github.com/{owner}
PublisherSupportUrl: https://github.com/{repo}/issues
PackageName: Windows 11 Privacy
PackageUrl: https://github.com/{repo}
License: MIT
LicenseUrl: https://github.com/{repo}/blob/main/LICENSE
ShortDescription: Turns off Microsoft data collection, shows what has already been collected and keeps updates from switching it back on.
Description: |-
  Applies privacy settings to Windows 10 and 11, then reads the real state of
  the system back instead of ticking boxes. Shows the telemetry events Windows
  has actually collected about this computer, which apps used the camera,
  microphone and location, and what leaves the machine over the network.
  Settings changes are journalled and can be reverted one item at a time.
  What the optional cleanup deletes (temporary files, the telemetry buffer,
  removed apps) cannot be brought back.
  winget runs the regular installer: the program goes to Program Files (a
  folder only administrators can write to, which auto-protection relies on)
  and can be removed in Settings > Apps. A portable version is offered by the
  same installer when it is run by hand.
Tags:
  - privacy
  - telemetry
  - windows
  - debloat
ReleaseNotesUrl: https://github.com/{repo}/releases/tag/v{ver}
ManifestType: defaultLocale
ManifestVersion: {schema}
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--sha', help='SHA-256 файла ' + SETUP)
    ap.add_argument('--sums', help='путь к SHA256SUMS.txt из релиза')
    ap.add_argument('--version', help='версия (по умолчанию — из AppInfo.cs)')
    ap.add_argument('--date', help='дата релиза в виде ГГГГ-ММ-ДД')
    args = ap.parse_args()

    version = args.version or read_version()
    sha = args.sha
    if not sha and args.sums:
        sha = read_sha(args.sums)
    if not sha:
        sys.exit('нужен --sha или --sums: каталог winget без хеша пакет не примет')
    sha = sha.strip().lower()
    if not re.match(r'^[0-9a-f]{64}$', sha):
        sys.exit('это не похоже на SHA-256: ' + sha)

    date = args.date
    if not date:
        import datetime
        date = datetime.date.today().isoformat()

    owner = REPO.split('/')[0]
    out = os.path.join(ROOT, 'packaging', 'winget', version)
    if not os.path.isdir(out):
        os.makedirs(out)

    fields = dict(pkg=PKG_ID, ver=version, schema=SCHEMA, repo=REPO, owner=owner,
                  sha=sha, date=date, publisher=owner, setup=SETUP, product_code=PRODUCT_CODE,
                  schema_url_version=SCHEMA_URL % 'version',
                  schema_url_installer=SCHEMA_URL % 'installer',
                  schema_url_locale=SCHEMA_URL % 'defaultLocale')
    files = {
        PKG_ID + '.yaml': VERSION_YAML,
        PKG_ID + '.installer.yaml': INSTALLER_YAML,
        PKG_ID + '.locale.en-US.yaml': LOCALE_YAML,
    }
    for name, tpl in files.items():
        path = os.path.join(out, name)
        with io.open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(tpl.format(**fields))
        print('записан ' + os.path.relpath(path, ROOT))

    print('')
    print('Проверить и отправить в каталог:')
    print('    winget validate --manifest packaging/winget/%s' % version)
    print('    wingetcreate submit packaging/winget/%s' % version)


if __name__ == '__main__':
    main()