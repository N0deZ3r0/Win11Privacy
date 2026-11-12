# -*- coding: utf-8 -*-
"""Собирает Win11-Privacy-Engine.ps1 из частей в папке engine/.

Исходники движка разложены по разделам (engine/NN-раздел.ps1), а программа,
задачи стража, проверка по SHA-256 и релиз по-прежнему работают с одним
файлом: так модель безопасности не меняется — один файл, одна сверка.
Части склеиваются по порядку номеров в именах, как есть.

    python tools/build_engine.py            собрать Win11-Privacy-Engine.ps1
    python tools/build_engine.py --check    только сверить: собранное = лежащее
                                            в репозитории (так проверяет CI)
    python tools/build_engine.py --where N  в какой части строка N собранного
                                            файла (PowerShell сообщает об
                                            ошибках по собранному файлу)

Править нужно части в engine/, а не собранный файл: CI не пропустит
расхождение. Если собранный файл всё же правили напрямую (он новее всех
частей), сборка остановится, а не сотрёт правки; затереть их: --force.
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
PARTS = os.path.join(ROOT, 'engine')
TARGET = os.path.join(ROOT, 'Win11-Privacy-Engine.ps1')
PART_RX = re.compile(r'^(\d{2})-[a-z0-9-]+\.ps1$')


def part_names():
    names = sorted(n for n in os.listdir(PARTS) if PART_RX.match(n))
    if not names:
        sys.exit(u'в engine/ нет частей движка (NN-имя.ps1)')
    nums = [PART_RX.match(n).group(1) for n in names]
    if len(set(nums)) != len(nums):
        sys.exit(u'в engine/ два файла с одним номером: ' + ', '.join(names))
    stray = sorted(n for n in os.listdir(PARTS) if n.lower().endswith('.ps1') and not PART_RX.match(n))
    if stray:
        sys.exit(u'в engine/ файлы не по образцу NN-имя.ps1 (сборка их пропустила бы): ' + ', '.join(stray))
    return names


def read_text(path):
    # BOM отбрасывается; переводы строк — к одному виду
    with io.open(path, encoding='utf-8-sig', newline='') as f:
        return f.read().replace('\r\n', '\n')


def load_parts():
    out = []
    for n in part_names():
        t = read_text(os.path.join(PARTS, n))
        if t and not t.endswith('\n'):
            t += '\n'          # часть без перевода строки в конце склеилась бы со следующей
        out.append((n, t))
    return out


def first_diff(a, b):
    al, bl = a.split('\n'), b.split('\n')
    n = min(len(al), len(bl))
    return next((i for i in range(n) if al[i] != bl[i]), n) + 1


def where(pieces, line):
    start = 1
    for n, t in pieces:
        count = t.count('\n')
        if line < start + count:
            return u'строка %d собранного файла — engine/%s, строка %d' % (line, n, line - start + 1)
        start += count
    return u'строки %d в собранном файле нет: в нём %d строк' % (line, start - 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true',
                    help=u'только сверить собранный файл с частями')
    ap.add_argument('--force', action='store_true',
                    help=u'собрать, даже если собранный файл правили напрямую')
    ap.add_argument('--where', type=int, metavar='N',
                    help=u'в какой части строка N собранного файла')
    a = ap.parse_args()
    pieces = load_parts()
    text = ''.join(t for _, t in pieces)
    summary = u'частей: %d, строк: %d' % (len(pieces), text.count('\n'))

    if a.where is not None:
        print(where(pieces, a.where))
        return 0

    have = read_text(TARGET) if os.path.exists(TARGET) else None
    if a.check:
        if have != text:
            sys.exit(u'Win11-Privacy-Engine.ps1 не совпадает со сборкой из engine/ (первое расхождение — строка %d). '
                     u'Правьте части в engine/ и запустите: python tools/build_engine.py'
                     % first_diff(have or '', text))
        print(u'движок совпадает со сборкой из engine/ (%s)' % summary)
        return 0

    if have is not None and have != text and not a.force:
        # Собранный файл новее всех частей — его правили руками, и сборка
        # молча стёрла бы эти правки. Пусть человек решит сам.
        newest = max(os.path.getmtime(os.path.join(PARTS, n)) for n, _ in pieces)
        if os.path.getmtime(TARGET) > newest:
            sys.exit(u'Win11-Privacy-Engine.ps1 правили напрямую: он новее всех частей в engine/ и расходится '
                     u'со сборкой (строка %d). Перенесите правки в части и соберите снова; '
                     u'затереть их: python tools/build_engine.py --force' % first_diff(have, text))

    # как и прежде: UTF-8 с BOM (без него PowerShell 5.1 читает файл как ANSI) и CRLF
    data = (u'﻿' + text.replace('\n', '\r\n')).encode('utf-8')
    if have is not None:
        with io.open(TARGET, 'rb') as f:
            if f.read() == data:
                print(u'Win11-Privacy-Engine.ps1 уже собран (%s)' % summary)
                return 0
    tmp = TARGET + '.tmp'
    with io.open(tmp, 'wb') as f:
        f.write(data)
    os.replace(tmp, TARGET)    # целиком или никак: оборванной записи не будет
    print(u'собран Win11-Privacy-Engine.ps1 (%s)' % summary)
    return 0


if __name__ == '__main__':
    sys.exit(main())
