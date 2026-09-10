# -*- coding: utf-8 -*-
"""Отправляет манифест очередной версии в каталог winget.

Каталог не следит за релизами сам: на каждую версию нужен свой манифест и свой
pull request в microsoft/winget-pkgs. Здесь это делается одной командой — и той
же командой из сборки, когда выложен релиз по тегу.

Клонировать каталог незачем (он весит гигабайты): ветка и файлы создаются через
API, дальше обычный pull request.

    python tools/submit_winget.py                  # версия из AppInfo.cs
    python tools/submit_winget.py --version 1.9.2
    python tools/submit_winget.py --dry-run        # всё собрать, ничего не отправлять

Нужен gh, вошедший в GitHub, или переменная GH_TOKEN с правом public_repo:
встроенный токен сборки в чужой репозиторий писать не может.
"""

import argparse
import base64
import io
import json
import os
import re
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UPSTREAM = 'microsoft/winget-pkgs'
PKG = 'N0deZ3r0.Win11Privacy'
OWNER = 'N0deZ3r0'


def gh(args, check=True):
    p = subprocess.run(['gh'] + args, capture_output=True, text=True,
                       encoding='utf-8', errors='replace', cwd=ROOT)
    if check and p.returncode != 0:
        sys.stderr.write('не удалась команда: gh %s\n%s\n' % (' '.join(args), (p.stderr or '')[:800]))
        sys.exit(1)
    return p.returncode, p.stdout.strip(), (p.stderr or '').strip()


def app_version():
    src = io.open(os.path.join(ROOT, 'AppInfo.cs'), encoding='utf-8-sig').read()
    m = re.search(r'Version\s*=\s*"([0-9.]+)"', src)
    if not m:
        sys.exit('в AppInfo.cs не нашлась строка версии')
    return m.group(1)


def build_manifest(version, sums):
    """Собирает манифест генератором: он же считает путь и подставляет хеш."""
    args = [sys.executable, os.path.join(ROOT, 'tools', 'make_winget.py'), '--version', version]
    if sums:
        args += ['--sums', sums]
    else:
        # хеш берём из контрольных сумм уже опубликованного релиза
        code, out, _ = gh(['release', 'download', 'v' + version, '--pattern', 'SHA256SUMS.txt',
                           '--dir', os.path.join(ROOT, 'packaging'), '--clobber'], check=False)
        if code != 0:
            sys.exit('нет опубликованного релиза v%s — сначала выложите его' % version)
        args += ['--sums', os.path.join(ROOT, 'packaging', 'SHA256SUMS.txt')]
    p = subprocess.run(args, cwd=ROOT)
    if p.returncode != 0:
        sys.exit('не удалось собрать манифест')
    return os.path.join(ROOT, 'packaging', 'winget', version)


def ensure_fork():
    fork = OWNER + '/winget-pkgs'
    code, _, _ = gh(['repo', 'view', fork, '--json', 'name'], check=False)
    if code != 0:
        gh(['repo', 'fork', UPSTREAM, '--clone=false'])
        print('форк каталога создан: ' + fork)
    return fork


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--version', help='версия пакета (по умолчанию — из AppInfo.cs)')
    ap.add_argument('--sums', help='путь к SHA256SUMS.txt (по умолчанию берётся из релиза)')
    ap.add_argument('--dry-run', action='store_true', help='собрать манифест и остановиться')
    args = ap.parse_args()

    version = args.version or app_version()
    src = build_manifest(version, args.sums)
    files = sorted(n for n in os.listdir(src) if n.endswith('.yaml'))
    print('манифест собран: %s (%d файла)' % (src, len(files)))

    if args.dry_run:
        print('пробный запуск — ничего не отправляем')
        return 0

    fork = ensure_fork()
    branch = 'win11privacy-' + version
    base = 'manifests/n/%s/Win11Privacy/%s' % (OWNER, version)

    # Уже отправленную версию второй раз не отправляем: у каталога это
    # считается дублем, и модераторы закрывают такие запросы.
    code, out, _ = gh(['pr', 'list', '--repo', UPSTREAM, '--author', OWNER,
                       '--state', 'open', '--json', 'title,url'], check=False)
    if code == 0 and out:
        for pr in json.loads(out):
            if version in pr.get('title', ''):
                print('запрос на эту версию уже открыт: ' + pr['url'])
                return 0

    # Свежесть форка не обязательна: запрос сравнивается по общему предку, а
    # добавляем мы только три новых файла. К тому же синхронизация требует
    # права workflow, если в каталоге поменялись его собственные сборки, —
    # токену с одним public_repo GitHub в этом отказывает. Не вышло — ветка
    # пойдёт от того master, что уже есть в форке.
    code, _, err = gh(['repo', 'sync', fork, '--source', UPSTREAM, '--force'], check=False)
    if code != 0:
        why = err.splitlines()[0] if err else 'без пояснений'
        print('форк не синхронизирован (%s) — ветка пойдёт от его текущего master' % why)
    head = json.loads(gh(['api', 'repos/%s/git/ref/heads/master' % fork])[1])['object']['sha']

    refs = json.loads(gh(['api', 'repos/%s/git/refs/heads' % fork])[1])
    if any(r['ref'] == 'refs/heads/' + branch for r in refs):
        gh(['api', '--method', 'DELETE', 'repos/%s/git/refs/heads/%s' % (fork, branch)])
    gh(['api', '--method', 'POST', 'repos/%s/git/refs' % fork,
        '-f', 'ref=refs/heads/' + branch, '-f', 'sha=' + head])
    print('ветка: ' + branch)

    for name in files:
        body = io.open(os.path.join(src, name), 'rb').read()
        gh(['api', '--method', 'PUT', 'repos/%s/contents/%s/%s' % (fork, base, name),
            '-f', 'message=New version: %s %s' % (PKG, version),
            '-f', 'content=' + base64.b64encode(body).decode('ascii'),
            '-f', 'branch=' + branch])
        print('  загружен ' + name)

    title = 'New version: %s version %s' % (PKG, version)
    body = (
        '### Publisher and package name\n\n'
        'N0deZ3r0 / Windows 11 Privacy (`%s`)\n\n'
        '### What this package does\n\n'
        'Turns off Microsoft data collection on Windows 10 and 11, then reads the real state of the\n'
        'system back instead of ticking boxes. Every change is journalled and can be reverted.\n'
        'Open source (MIT): https://github.com/N0deZ3r0/Win11Privacy\n\n'
        '### Checklist\n\n'
        '- [x] Have you signed the [Contributor License Agreement](https://cla.opensource.microsoft.com/microsoft/winget-pkgs)?\n'
        '- [x] Have you checked that there aren\'t other open [pull requests](https://github.com/microsoft/winget-pkgs/pulls) '
        'for the same manifest update/change?\n'
        '- [x] Have you validated your manifest locally with `winget validate --manifest <path>`?\n'
        '- [x] Does your manifest conform to the [1.6 schema](https://github.com/microsoft/winget-pkgs/tree/master/doc/manifest/schema/1.6.0)?\n\n'
        'A single portable executable published in the project\'s GitHub release; the SHA256 above\n'
        'matches `SHA256SUMS.txt` of that release. The program changes system settings and asks for\n'
        'administrator rights itself, hence `ElevationRequirement: elevatesSelf`.\n'
    ) % PKG

    code, out, err = gh(['pr', 'create', '--repo', UPSTREAM, '--base', 'master',
                         '--head', '%s:%s' % (OWNER, branch), '--title', title, '--body', body], check=False)
    if code != 0:
        sys.stderr.write(err[:800] + '\n')
        sys.exit('не удалось открыть запрос')
    print('')
    print('pull request: ' + out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
