# -*- coding: utf-8 -*-
"""Показывает строки интерфейса, для которых нет английского перевода.

Ищет в исходниках вызовы L.T("..."), сверяет с lang-en*.txt и печатает
недостающие пары в готовом для словаря виде (русский TAB английский).
Строки с русскими буквами, которых нет в словаре, — это то, что в
английском интерфейсе останется по-русски.

Запуск (из корня проекта):
    python tools\\check_lang.py
"""

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

# Lang.cs — сам словарь, Mocks.cs — тестовые подписи для снимков.
SKIP = {'Lang.cs', 'Mocks.cs'}


def sources(root):
    return sorted(n for n in os.listdir(root)
                  if n.endswith('.cs') and n not in SKIP)


def dicts(root):
    names = [n for n in os.listdir(root)
             if n.startswith('lang-en') and n.endswith('.txt')]

    def num(n):
        m = re.search(r'lang-en(\d*)\.txt', n)
        return int(m.group(1)) if m and m.group(1) else 1

    return sorted(names, key=num)
LIT = re.compile(r'L\.T\("((?:[^"\\]|\\.)*)"\)')
# Движок отдаёт часть подписей данными, а не литералами интерфейса: названия и
# описания фактов рентгена, категории телеметрии, подписи файлов на странице
# «О программе». Интерфейс пропускает их через L.T, но найти их можно только
# в самом движке.
ENGINE = 'Win11-Privacy-Engine.ps1'
ENGINE_LIT = [
    re.compile(r"(?:title|what|was|now|where)\s*=\s*'([^']{3,})'"),   # факты, категории, состояния
    re.compile(r"^\s*'[^']+'\s*=\s*'([^']{3,})'\s*$", re.M),        # словари вида имя = «человеческое название»
]
CYR = re.compile(u'[Ѐ-ӿ]')


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    known = set()
    spaces = []
    for name in dicts(root):
        path = os.path.join(root, name)
        if not os.path.exists(path):
            continue
        for num, line in enumerate(io.open(path, encoding='utf-8-sig'), 1):
            line = line.rstrip('\r\n')
            if not line.strip() or line.lstrip().startswith('#') or '\t' not in line:
                continue
            ru, en = line.split('\t', 1)
            known.add(ru)
            # Строки склеиваются из кусков, поэтому краевой пробел значим:
            # без него получается «Unsent telemetry:4.7 MB».
            if en.strip() and (ru.endswith(' ') != en.endswith(' ') or
                               ru.startswith(' ') != en.startswith(' ')):
                spaces.append((name, num, ru, en))

    if spaces:
        sys.stdout.write('краевые пробелы не совпадают: %d\n' % len(spaces))
        for name, num, ru, en in spaces:
            sys.stdout.write('%s:%d  %r -> %r\n' % (name, num, ru, en))
        return 1

    missing = []
    seen = set()
    for name in sources(root):
        path = os.path.join(root, name)
        if not os.path.exists(path):
            continue
        text = io.open(path, encoding='utf-8-sig').read()
        # блоки #if UITEST не переводятся — там тестовые подписи
        for raw in LIT.findall(text):
            key = raw.replace('\\"', '"')
            if key in known or key in seen or not CYR.search(key):
                continue
            seen.add(key)
            missing.append((name, key))

    engine = os.path.join(root, ENGINE)
    if os.path.exists(engine):
        text = io.open(engine, encoding='utf-8-sig').read()
        for rx in ENGINE_LIT:
            for raw in rx.findall(text):
                if raw in known or raw in seen or not CYR.search(raw):
                    continue
                seen.add(raw)
                missing.append((ENGINE, raw))

    if not missing:
        sys.stdout.write('all translated\n')
        return 0
    sys.stdout.write('без перевода: %d\n' % len(missing))
    for name, key in missing:
        sys.stdout.write('%s\t\n' % key)
    return 1


if __name__ == '__main__':
    sys.exit(main())
