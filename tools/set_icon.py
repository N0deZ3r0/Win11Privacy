# -*- coding: utf-8 -*-
"""Кладёт значок программы в app.ico и в ресурс app.res.

Значок живёт в двух местах: app.ico вшивается в exe как ресурс (из него окно
берёт значок для заголовка и панели задач), а app.res — это ресурс Win32,
по которому значок exe видит Проводник. Пересобрать app.res целиком нечем —
rc.exe входит в Windows SDK, — поэтому меняем в готовом ресурсе только
картинки значка (RT_ICON) и их оглавление (RT_GROUP_ICON). Манифест и версия
(её прописывает tools/set_version.py) остаются как были.

    python tools/set_icon.py logo-16.png logo-24.png ... logo-256.png
        собрать app.ico из PNG (размер берётся из самих файлов)
        и переложить его в app.res
    python tools/set_icon.py
        только переложить текущий app.ico в app.res
"""

import os
import struct
import sys

try:
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICO = os.path.join(ROOT, 'app.ico')
RES = os.path.join(ROOT, 'app.res')
RT_ICON, RT_GROUP_ICON = 3, 14


def png_size(data):
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        sys.exit('не PNG')
    return struct.unpack('>II', data[16:24])


def build_ico(pngs):
    """PNG внутри ICO Windows понимает начиная с Vista — на 10 и 11 это норма."""
    images = []
    for path in pngs:
        data = open(path, 'rb').read()
        w, h = png_size(data)
        if w != h or w > 256:
            sys.exit('%s: значок должен быть квадратным и не больше 256: %dx%d' % (path, w, h))
        images.append((w, data))
    images.sort(key=lambda x: x[0])
    out = struct.pack('<HHH', 0, 1, len(images))
    offset = 6 + 16 * len(images)
    for w, data in images:
        b = 0 if w == 256 else w
        out += struct.pack('<BBBBHHII', b, b, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
    for _, data in images:
        out += data
    return out


def read_ico(buf):
    _, kind, n = struct.unpack_from('<HHH', buf, 0)
    if kind != 1:
        sys.exit('app.ico — не значок')
    entries = []
    for i in range(n):
        w, h, colors, _, planes, bits, size, off = struct.unpack_from('<BBBBHHII', buf, 6 + 16 * i)
        entries.append((w, h, colors, planes, bits, buf[off:off + size]))
    return entries


def read_name(buf, pos):
    if buf[pos:pos + 2] == b'\xff\xff':
        return struct.unpack_from('<H', buf, pos + 2)[0], pos + 4
    end = pos
    while struct.unpack_from('<H', buf, end)[0] != 0:
        end += 2
    return buf[pos:end].decode('utf-16-le'), end + 2


def align4(n):
    return (n + 3) & ~3


def resources(buf):
    """(тип, заголовок, данные) по порядку."""
    out, pos = [], 0
    while pos < len(buf):
        data_size, header_size = struct.unpack_from('<II', buf, pos)
        rtype, _ = read_name(buf, pos + 8)
        out.append((rtype, buf[pos:pos + header_size], buf[pos + header_size:pos + header_size + data_size]))
        pos += header_size + align4(data_size)
    return out


def ordinal_header(template, rtype, rid, size):
    """Заголовок с числовыми типом и именем; хвост (язык, флаги) — как у прежнего значка."""
    tail = template[-16:]
    return struct.pack('<II', size, 32) + struct.pack('<HHHH', 0xFFFF, rtype, 0xFFFF, rid) + tail


def main():
    if len(sys.argv) > 1:
        open(ICO, 'wb').write(build_ico(sys.argv[1:]))
        print('app.ico: собран из %d картинок' % (len(sys.argv) - 1))
    entries = read_ico(open(ICO, 'rb').read())

    res = resources(open(RES, 'rb').read())
    template = next((h for t, h, _ in res if t == RT_ICON), None) or next(h for t, h, _ in res if t == RT_GROUP_ICON)

    icons = []
    group = struct.pack('<HHH', 0, 1, len(entries))
    for i, (w, h, colors, planes, bits, data) in enumerate(entries, 1):
        icons.append((RT_ICON, ordinal_header(template, RT_ICON, i, len(data)), data))
        group += struct.pack('<BBBBHHIH', w, h, colors, 0, planes, bits, len(data), i)
    icons.append((RT_GROUP_ICON, ordinal_header(template, RT_GROUP_ICON, 1, len(group)), group))

    out, placed = b'', False
    for rtype, header, data in res:
        if rtype in (RT_ICON, RT_GROUP_ICON):
            if not placed:          # новые картинки встают туда, где были старые
                for _, h2, d2 in icons:
                    out += h2 + d2 + b'\0' * (align4(len(d2)) - len(d2))
                placed = True
            continue
        out += header + data + b'\0' * (align4(len(data)) - len(data))
    if not placed:
        for _, h2, d2 in icons:
            out += h2 + d2 + b'\0' * (align4(len(d2)) - len(d2))
    open(RES, 'wb').write(out)
    print('app.res: значок обновлён, размеров: %d' % len(entries))
    return 0


if __name__ == '__main__':
    sys.exit(main())
