# -*- coding: utf-8 -*-
"""Прописывает версию программы в ресурс app.res.

В свойствах файла Windows показывает версию из ресурса VS_VERSION_INFO, и она
жила своей жизнью: в проводнике, в списке установленного и в отчётах
антивирусов значилось 5.0.0.0, когда программа была 1.9.0. Пересобирать
ресурс целиком нечем — rc.exe входит в Windows SDK, которого на машине может
не быть, — поэтому правим готовый ресурс: числа в VS_FIXEDFILEINFO и строки
FileVersion / ProductVersion, пересчитывая длины блоков.

Версия берётся из AppInfo.cs, если не задана явно:

    python tools/set_version.py               # версия из AppInfo.cs
    python tools/set_version.py --version 2.0 # вручную
    python tools/set_version.py --check       # только проверить, ничего не писать
"""

import argparse
import io
import os
import re
import struct
import sys

try:
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, 'app.res')
RT_VERSION = 16


def app_version():
    src = io.open(os.path.join(ROOT, 'AppInfo.cs'), encoding='utf-8-sig').read()
    m = re.search(r'Version\s*=\s*"([0-9.]+)"', src)
    if not m:
        sys.exit('в AppInfo.cs не нашлась строка версии')
    return m.group(1)


def four(v):
    """1.9.0 -> (1, 9, 0, 0)"""
    parts = [int(p) for p in v.split('.') if p.isdigit()]
    while len(parts) < 4:
        parts.append(0)
    return tuple(parts[:4])


def align4(n):
    return (n + 3) & ~3


# --------------------------------------------------------------------------- #
#  .RES — цепочка ресурсов. Нам нужен единственный с типом RT_VERSION.
# --------------------------------------------------------------------------- #
def read_name(buf, pos):
    """Тип или имя ресурса: либо 0xFFFF + число, либо строка UTF-16."""
    if buf[pos:pos + 2] == b'\xff\xff':
        return struct.unpack_from('<H', buf, pos + 2)[0], pos + 4
    end = pos
    while struct.unpack_from('<H', buf, end)[0] != 0:
        end += 2
    return buf[pos:end].decode('utf-16-le'), end + 2


def find_version(buf):
    """Возвращает (начало данных, длина данных, позиция поля длины)."""
    pos = 0
    while pos < len(buf):
        data_size, header_size = struct.unpack_from('<II', buf, pos)
        rtype, p = read_name(buf, pos + 8)
        rname, p = read_name(buf, p)
        start = pos + header_size
        if rtype == RT_VERSION:
            return start, data_size, pos
        pos = start + align4(data_size)
    return None, None, None


# --------------------------------------------------------------------------- #
#  VS_VERSIONINFO — дерево блоков: длина, длина значения, тип, ключ, значение,
#  дальше вложенные блоки. Правим значения и пересобираем длины снизу вверх.
# --------------------------------------------------------------------------- #
class Block(object):
    def __init__(self, key, value_bytes, is_text, children):
        self.key = key
        self.value = value_bytes
        self.is_text = is_text
        self.children = children


def parse_block(buf, pos, end):
    length, value_len, btype = struct.unpack_from('<HHH', buf, pos)
    if length == 0 or pos + length > end:
        raise ValueError('повреждённый блок версии')
    stop = pos + length
    p = pos + 6
    kend = p
    while struct.unpack_from('<H', buf, kend)[0] != 0:
        kend += 2
    key = buf[p:kend].decode('utf-16-le')
    p = align4(kend + 2 - pos) + pos
    vbytes = value_len * (2 if btype == 1 else 1)
    value = buf[p:p + vbytes]
    p = align4(p - pos) + pos + align4(vbytes)
    children = []
    while p < stop:
        child, p = parse_block(buf, p, stop)
        children.append(child)
    return Block(key, value, btype == 1, children), stop


def build_block(b):
    key = b.key.encode('utf-16-le') + b'\x00\x00'
    head = struct.pack('<HHH', 0, 0, 1 if b.is_text else 0) + key
    head += b'\x00' * (align4(len(head)) - len(head))
    value = b.value
    body = value + b'\x00' * (align4(len(value)) - len(value))
    kids = b''
    for c in b.children:
        kids += build_block(c)
    out = bytearray(head + body + kids)
    value_len = (len(value) // 2) if b.is_text else len(value)
    struct.pack_into('<HHH', out, 0, len(out), value_len, 1 if b.is_text else 0)
    return bytes(out)


def set_string(root, name, text):
    """Меняет значение строки в StringFileInfo/<язык>/<name>."""
    changed = []
    for sfi in root.children:
        if sfi.key != 'StringFileInfo':
            continue
        for table in sfi.children:
            for item in table.children:
                if item.key == name:
                    item.value = (text + '\x00').encode('utf-16-le')
                    changed.append(table.key)
    return changed


def get_string(root, name):
    for sfi in root.children:
        if sfi.key != 'StringFileInfo':
            continue
        for table in sfi.children:
            for item in table.children:
                if item.key == name:
                    return item.value.decode('utf-16-le').rstrip('\x00')
    return ''


def fixed_version(root):
    if len(root.value) < 16:
        return None
    ms, ls = struct.unpack_from('<II', root.value, 8)
    return (ms >> 16, ms & 0xFFFF, ls >> 16, ls & 0xFFFF)


def set_fixed(root, parts):
    v = bytearray(root.value)
    ms = (parts[0] << 16) | parts[1]
    ls = (parts[2] << 16) | parts[3]
    struct.pack_into('<II', v, 8, ms, ls)        # dwFileVersionMS/LS
    struct.pack_into('<II', v, 16, ms, ls)       # dwProductVersionMS/LS
    root.value = bytes(v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--version', help='версия вида 1.9.0 (по умолчанию — из AppInfo.cs)')
    ap.add_argument('--check', action='store_true', help='только сравнить, ничего не записывать')
    args = ap.parse_args()

    want = args.version or app_version()
    parts = four(want)
    dotted = '.'.join(str(p) for p in parts)

    buf = bytearray(io.open(RES, 'rb').read())
    start, size, _ = find_version(buf)
    if start is None:
        sys.exit('в app.res нет ресурса версии')

    root, _ = parse_block(bytes(buf), start, start + size)
    now_fixed = fixed_version(root)
    now_file = get_string(root, 'FileVersion')
    now_prod = get_string(root, 'ProductVersion')
    print('в ресурсе сейчас: %s (FileVersion %s, ProductVersion %s)'
          % ('.'.join(str(x) for x in now_fixed), now_file, now_prod))

    if args.check:
        ok = now_fixed == parts and now_file == dotted
        print('нужно: %s' % dotted)
        if ok:
            print('версия в ресурсе совпадает с программой')
            return 0
        print('::error::версия в app.res (%s) не совпадает с версией программы (%s) — '
              'запустите python tools/set_version.py' % (now_file, dotted))
        return 1

    set_fixed(root, parts)
    set_string(root, 'FileVersion', dotted)
    set_string(root, 'ProductVersion', dotted)

    data = build_block(root)
    tail_start = start + align4(size)
    head = bytes(buf[:start])
    # длина данных ресурса хранится в его заголовке — обновляем
    _, _, hdr = find_version(buf)
    head = bytearray(head)
    struct.pack_into('<I', head, hdr, len(data))
    padded = data + b'\x00' * (align4(len(data)) - len(data))
    out = bytes(head) + padded + bytes(buf[tail_start:])
    io.open(RES, 'wb').write(out)

    check = bytearray(out)
    s2, sz2, _ = find_version(check)
    root2, _ = parse_block(bytes(check), s2, s2 + sz2)
    print('записано: %s (FileVersion %s, ProductVersion %s)'
          % ('.'.join(str(x) for x in fixed_version(root2)),
             get_string(root2, 'FileVersion'), get_string(root2, 'ProductVersion')))
    return 0


if __name__ == '__main__':
    sys.exit(main())
