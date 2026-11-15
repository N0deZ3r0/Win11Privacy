using System;
using System.Collections.Generic;
using System.Text;

namespace Win11Privacy
{
    // ====================================================================== //
    //  Запрос к движку (F-08). Раньше окно склеивало командную строку:
    //  «-SensorSet -SensorKey "<имя раздела реестра>"», и кавычка в имени
    //  раздела, который в своём HKCU может завести любая программа
    //  пользователя, закрывала значение — остаток строки PowerShell разбирал
    //  как новые ключи движка, и они выполнялись с правами администратора.
    //
    //  Теперь командная строка движка постоянная («-File <движок> -Request»),
    //  а операция и её данные уходят на стандартный ввод одним JSON:
    //      {"v":1,"op":"SensorSet","args":{"SensorKey":"...","SensorValue":"Deny"}}
    //  Операция — имя из кода, данные — только значения: ни кавычки, ни
    //  «-Ключ» внутри значения операцию уже не меняют. Движок разбирает запрос
    //  строго и сам проверяет и операцию, и форму каждого значения
    //  (engine/00-header.ps1), не полагаясь на проверки окна.
    //
    //  JSON — только печатный ASCII: всё остальное (кириллица в путях,
    //  управляющие символы) пишется как \uXXXX. Так кодировка канала между
    //  процессами ничего не может исказить.
    // ====================================================================== //
    internal sealed class EngineRequest
    {
        public readonly string Op;
        private readonly List<KeyValuePair<string, object>> _args = new List<KeyValuePair<string, object>>();

        public EngineRequest(string op)
        {
            if (!IsName(op)) throw new ArgumentException("engine operation name: " + op);
            Op = op;
        }

        // Имена операций и аргументов — только из кода программы: буквы латиницы
        private static bool IsName(string s)
        {
            if (string.IsNullOrEmpty(s) || s.Length > 40) return false;
            foreach (char c in s) if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'))) return false;
            return true;
        }

        private EngineRequest Add(string name, object value)
        {
            if (!IsName(name)) throw new ArgumentException("engine argument name: " + name);
            if (Has(name)) throw new ArgumentException("engine argument repeated: " + name);
            _args.Add(new KeyValuePair<string, object>(name, value));
            return this;
        }

        public EngineRequest Switch(string name) { return Add(name, true); }
        public EngineRequest Switch(string name, bool on) { return on ? Add(name, true) : this; }
        public EngineRequest Str(string name, string value) { return Add(name, value ?? ""); }
        public EngineRequest Int(string name, int value) { return Add(name, value); }
        public EngineRequest List(string name, IEnumerable<string> values)
        {
            List<string> l = new List<string>();
            if (values != null) foreach (string v in values) l.Add(v ?? "");
            return Add(name, l);
        }

        public bool Has(string name)
        {
            foreach (KeyValuePair<string, object> a in _args) if (a.Key == name) return true;
            return false;
        }

        // Копия запроса с общими для всех операций аргументами: где лежат
        // резервные копии и (в переносимом режиме) данные. Сам запрос вызывающего
        // не меняется.
        public EngineRequest WithCommon(string backupRoot, string dataRoot)
        {
            EngineRequest r = new EngineRequest(Op);
            r._args.AddRange(_args);
            if (!string.IsNullOrEmpty(backupRoot) && !r.Has("BackupRoot")) r.Str("BackupRoot", backupRoot);
            if (!string.IsNullOrEmpty(dataRoot) && !r.Has("DataRoot")) r.Str("DataRoot", dataRoot);
            return r;
        }

        public string ToJson()
        {
            StringBuilder sb = new StringBuilder();
            sb.Append("{\"v\":1,\"op\":");
            AppendString(sb, Op);
            sb.Append(",\"args\":{");
            for (int i = 0; i < _args.Count; i++)
            {
                if (i > 0) sb.Append(',');
                AppendString(sb, _args[i].Key);
                sb.Append(':');
                object v = _args[i].Value;
                if (v is bool) sb.Append((bool)v ? "true" : "false");
                else if (v is int) sb.Append(((int)v).ToString(System.Globalization.CultureInfo.InvariantCulture));
                else if (v is List<string>)
                {
                    sb.Append('[');
                    List<string> l = (List<string>)v;
                    for (int j = 0; j < l.Count; j++) { if (j > 0) sb.Append(','); AppendString(sb, l[j]); }
                    sb.Append(']');
                }
                else AppendString(sb, (string)v);
            }
            sb.Append("}}");
            return sb.ToString();
        }

        // Строка JSON только из печатного ASCII
        internal static void AppendString(StringBuilder sb, string s)
        {
            sb.Append('"');
            foreach (char c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < 0x20 || c > 0x7E) sb.Append("\\u").Append(((int)c).ToString("x4"));
                        else sb.Append(c);
                        break;
                }
            }
            sb.Append('"');
        }

        // Для журнала в окне: что запущено. Только показ — движку уходит ToJson().
        public string Describe()
        {
            StringBuilder sb = new StringBuilder("-" + Op);
            foreach (KeyValuePair<string, object> a in _args)
            {
                if (a.Key == "BackupRoot" || a.Key == "DataRoot") continue;
                sb.Append(" -").Append(a.Key);
                if (a.Value is bool) continue;
                if (a.Value is List<string>) sb.Append(' ').Append(string.Join(", ", ((List<string>)a.Value).ToArray()));
                else sb.Append(' ').Append(Convert.ToString(a.Value, System.Globalization.CultureInfo.InvariantCulture));
            }
            return sb.ToString();
        }

        // Операции, которые меняют систему. Остальные движок только читает, и
        // обрывать их можно без последствий.
        private static readonly string[] WriteOps = {
            "Revert", "RestoreAll", "RestoreItems", "RestoreBackup", "RemoveApps",
            "StartupSet", "SensorSet", "FootprintWipe", "XrayWipe",
            "PurgeData", "CleanJunk", "BlockApp", "UnblockApp", "InstallGuard", "GdidReissue", "GdidRestore",
            "InstallNetGuard", "RemoveNetGuard",
            "RemoveGuard", "GuardNow", "InstallWatcher", "RemoveWatcher",
            "InstallSensorGuard", "RemoveSensorGuard", "EnableMonitor",
            "DisableMonitor", "XrayEnable", "XrayDisable"
        };

        public bool Writes
        {
            get
            {
                // применение меняет систему, тестовый прогон — нет
                if (Op == "Apply") return !Has("DryRun");
                // замер «до» сохраняет эталон, обычный замер только читает
                if (Op == "XrayScan") return Has("XrayBaseline");
                return Array.IndexOf(WriteOps, Op) >= 0;
            }
        }
    }
}
