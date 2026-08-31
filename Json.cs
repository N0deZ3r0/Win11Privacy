using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Win11Privacy
{
    // Компактный разборщик JSON без внешних зависимостей.
    // Возвращает: Dictionary<string,object>, List<object>, string, double, bool, null.
    internal static class Json
    {
        public static object Parse(string s)
        {
            int i = 0;
            object v = ParseValue(s, ref i);
            return v;
        }

        public static Dictionary<string, object> ParseObject(string s)
        {
            return Parse(s) as Dictionary<string, object>;
        }

        private static void SkipWs(string s, ref int i)
        {
            while (i < s.Length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')) i++;
        }

        private static object ParseValue(string s, ref int i)
        {
            SkipWs(s, ref i);
            if (i >= s.Length) return null;
            char c = s[i];
            if (c == '{') return ParseObj(s, ref i);
            if (c == '[') return ParseArr(s, ref i);
            if (c == '"') return ParseStr(s, ref i);
            if (c == 't' || c == 'f') return ParseBool(s, ref i);
            if (c == 'n') { i += 4; return null; }
            return ParseNum(s, ref i);
        }

        private static Dictionary<string, object> ParseObj(string s, ref int i)
        {
            Dictionary<string, object> d = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
            i++; // {
            SkipWs(s, ref i);
            if (i < s.Length && s[i] == '}') { i++; return d; }
            while (i < s.Length)
            {
                SkipWs(s, ref i);
                string key = ParseStr(s, ref i);
                SkipWs(s, ref i);
                if (i < s.Length && s[i] == ':') i++;
                object val = ParseValue(s, ref i);
                d[key] = val;
                SkipWs(s, ref i);
                if (i < s.Length && s[i] == ',') { i++; continue; }
                if (i < s.Length && s[i] == '}') { i++; break; }
                break;
            }
            return d;
        }

        private static List<object> ParseArr(string s, ref int i)
        {
            List<object> list = new List<object>();
            i++; // [
            SkipWs(s, ref i);
            if (i < s.Length && s[i] == ']') { i++; return list; }
            while (i < s.Length)
            {
                object val = ParseValue(s, ref i);
                list.Add(val);
                SkipWs(s, ref i);
                if (i < s.Length && s[i] == ',') { i++; continue; }
                if (i < s.Length && s[i] == ']') { i++; break; }
                break;
            }
            return list;
        }

        private static string ParseStr(string s, ref int i)
        {
            StringBuilder sb = new StringBuilder();
            if (i >= s.Length || s[i] != '"') return "";
            i++; // "
            while (i < s.Length)
            {
                char c = s[i++];
                if (c == '"') break;
                if (c == '\\' && i < s.Length)
                {
                    char e = s[i++];
                    switch (e)
                    {
                        case '"': sb.Append('"'); break;
                        case '\\': sb.Append('\\'); break;
                        case '/': sb.Append('/'); break;
                        case 'b': sb.Append('\b'); break;
                        case 'f': sb.Append('\f'); break;
                        case 'n': sb.Append('\n'); break;
                        case 'r': sb.Append('\r'); break;
                        case 't': sb.Append('\t'); break;
                        case 'u':
                            if (i + 4 <= s.Length)
                            {
                                int code = int.Parse(s.Substring(i, 4), NumberStyles.HexNumber);
                                sb.Append((char)code);
                                i += 4;
                            }
                            break;
                        default: sb.Append(e); break;
                    }
                }
                else sb.Append(c);
            }
            return sb.ToString();
        }

        private static object ParseBool(string s, ref int i)
        {
            if (s[i] == 't') { i += 4; return true; }
            i += 5; return false;
        }

        private static object ParseNum(string s, ref int i)
        {
            int start = i;
            while (i < s.Length && "+-0123456789.eE".IndexOf(s[i]) >= 0) i++;
            string num = s.Substring(start, i - start);
            double d;
            if (double.TryParse(num, NumberStyles.Any, CultureInfo.InvariantCulture, out d)) return d;
            return 0.0;
        }

        // --- удобные извлекатели ---
        public static string Str(object o)
        {
            if (o == null) return "";
            return o.ToString();
        }

        public static int Int(object o)
        {
            if (o == null) return 0;
            if (o is double) return (int)Math.Round((double)o);
            int n;
            if (int.TryParse(o.ToString(), out n)) return n;
            double d;
            if (double.TryParse(o.ToString(), NumberStyles.Any, CultureInfo.InvariantCulture, out d)) return (int)Math.Round(d);
            return 0;
        }

        public static bool Bool(object o)
        {
            if (o == null) return false;
            if (o is bool) return (bool)o;
            string s = o.ToString().ToLowerInvariant();
            return s == "true" || s == "1";
        }

        public static Dictionary<string, object> Obj(object o)
        {
            return o as Dictionary<string, object>;
        }

        public static List<object> Arr(object o)
        {
            List<object> l = o as List<object>;
            if (l != null) return l;
            return new List<object>();
        }

        public static object Get(Dictionary<string, object> d, string key)
        {
            if (d == null) return null;
            object v;
            if (d.TryGetValue(key, out v)) return v;
            return null;
        }

        public static string GetStr(Dictionary<string, object> d, string key) { return Str(Get(d, key)); }
        public static int GetInt(Dictionary<string, object> d, string key) { return Int(Get(d, key)); }
        public static bool GetBool(Dictionary<string, object> d, string key) { return Bool(Get(d, key)); }
        public static Dictionary<string, object> GetObj(Dictionary<string, object> d, string key) { return Obj(Get(d, key)); }
        public static List<object> GetArr(Dictionary<string, object> d, string key) { return Arr(Get(d, key)); }
    }
}
