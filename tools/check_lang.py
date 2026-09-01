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

SOURCES = ['MainForm.cs', 'Ui.cs', 'Ui2.cs', 'Ui3.cs', 'Ui4.cs']
DICTS = ['lang-en.txt', 'lang-en2.txt', 'lang-en3.txt', 'lang-en4.txt']
LIT = re.compile(r'L\.T\("((?:[^"\\]|\\.)*)"\)')
CYR = re.compile(u'[Ѐ-ӿ]')


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    known = set()
    spaces = []
    for name in DICTS:
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
    for name in SOURCES:
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

    if not missing:
        sys.stdout.write('all translated\n')
        return 0
    sys.stdout.write('без перевода: %d\n' % len(missing))
    for name, key in missing:
        sys.stdout.write('%s\t\n' % key)
    return 1


if __name__ == '__main__':
    sys.exit(main())
