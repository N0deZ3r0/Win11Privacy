# -*- coding: utf-8 -*-
"""Собирает Lang.cs из словарей lang-en*.txt.

Формат словаря: одна пара на строку, русский и английский разделены
табуляцией. Строки, начинающиеся с #, и пустые пропускаются. Escape-
последовательности (\\n, \\t) пишутся так же, как в C#, — они уходят
в литерал как есть; кавычки экранируются автоматически.

Если один и тот же русский текст встретился дважды, побеждает первый:
файлы просматриваются по порядку номеров.

Запуск (из корня проекта):
    python tools\\gen_lang.py
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

HEADER = u"""using System;
using System.Collections.Generic;
using System.Globalization;
using System.Threading;

namespace Win11Privacy
{
    // ================================================================== //
    //  Язык интерфейса. По умолчанию берётся язык Windows: русский —
    //  как есть, всё остальное — английский. Переключается на странице
    //  «О программе» и запоминается вместе с размером окна.
    // ================================================================== //
    internal static class L
    {
        private static bool _en;
        private static bool _explicit;
        private static Dictionary<string, string> _map;

        public static bool English
        {
            get { return _en; }
            set { _en = value; _explicit = true; }
        }

        public static void DetectFromSystem()
        {
            if (_explicit) return;
            try { _en = !Thread.CurrentThread.CurrentUICulture.TwoLetterISOLanguageName.Equals("ru", StringComparison.OrdinalIgnoreCase); }
            catch { _en = false; }
        }

        public static string T(string ru)
        {
            if (!_en || ru == null) return ru;
            if (_map == null) Build();
            string v;
            if (_map.TryGetValue(ru, out v)) return v;
            return ru;
        }

        private static void Build()
        {
            _map = new Dictionary<string, string>(%d, StringComparer.Ordinal);
"""

FOOTER = u"""        }
    }
}
"""

def dicts(root):
    """Все словари lang-en*.txt по порядку номеров: список файлов не надо
    править руками при добавлении нового."""
    names = [n for n in os.listdir(root)
             if n.startswith('lang-en') and n.endswith('.txt')]

    def num(n):
        m = re.search(r'lang-en(\d*)\.txt', n)
        return int(m.group(1)) if m and m.group(1) else 1

    return sorted(names, key=num)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    pairs = []
    seen = set()
    for name in dicts(root):
        path = os.path.join(root, name)
        if not os.path.exists(path):
            continue
        for num, line in enumerate(io.open(path, encoding='utf-8-sig'), 1):
            line = line.rstrip('\r\n')
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            if '\t' not in line:
                sys.stderr.write(u'%s:%d нет табуляции: %s\n' % (name, num, line))
                return 1
            ru, en = line.split('\t', 1)
            if ru in seen:
                continue
            seen.add(ru)
            pairs.append((ru, en))

    body = []
    for ru, en in pairs:
        body.append(u'            _map["%s"] = "%s";'
                    % (ru.replace('"', '\\"'), en.replace('"', '\\"')))

    text = (HEADER % len(pairs)) + u'\n'.join(body) + u'\n' + FOOTER
    out = os.path.join(root, 'Lang.cs')
    with io.open(out, 'w', encoding='utf-8-sig', newline='\r\n') as f:
        f.write(text)
    sys.stdout.write('Lang.cs: %d pairs\n' % len(pairs))
    return 0


if __name__ == '__main__':
    sys.exit(main())
