using System;
using System.Globalization;
using System.IO;
using System.Net;
using System.Text;

namespace Win11Privacy
{
    // ====================================================================== //
    //  Версия программы. Держится в одном месте: движок объявляет такую же
    //  строкой $script:EngineVersion, а сборка сверяет их и не выпускает
    //  релиз, если они разъехались или не совпали с тегом.
    //
    //  Версия видна на «О программе» не из любви к номерам: в 1.1–1.5 была
    //  ошибка с именами параметров реестра, и человеку нужно понимать,
    //  относится ли к нему совет «нажмите „Убрать мусор“».
    // ====================================================================== //
    internal static class AppInfo
    {
        internal const string Version = "1.9.0";
        internal const string Repo = "N0deZ3r0/Win11Privacy";
        internal const string ReleasesUrl = "https://github.com/N0deZ3r0/Win11Privacy/releases/latest";

        // Сравнение вида 1.9.0 против 1.10.2 — по числам, а не по строкам:
        // иначе «1.9» окажется новее «1.10».
        internal static int Compare(string a, string b)
        {
            int[] x = Parts(a), y = Parts(b);
            for (int i = 0; i < 4; i++)
            {
                if (x[i] != y[i]) return x[i] < y[i] ? -1 : 1;
            }
            return 0;
        }

        private static int[] Parts(string v)
        {
            int[] r = new int[4];
            if (v == null) return r;
            v = v.Trim();
            if (v.StartsWith("v", StringComparison.OrdinalIgnoreCase)) v = v.Substring(1);
            string[] p = v.Split('.', '-', '+');
            for (int i = 0; i < p.Length && i < 4; i++)
            {
                int n;
                if (int.TryParse(p[i], NumberStyles.Integer, CultureInfo.InvariantCulture, out n)) r[i] = n;
                else break;
            }
            return r;
        }

        // ------------------------------------------------------------------ //
        //  Проверка обновления. Только по нажатию кнопки и никогда сама:
        //  программа о приватности не должна тайком ходить в сеть.
        //  Возвращает версию последнего релиза или пустую строку.
        // ------------------------------------------------------------------ //
        internal static string LatestRelease(out string error)
        {
            error = "";
            try
            {
                try { ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; } catch { }   // TLS 1.2
                HttpWebRequest req = (HttpWebRequest)WebRequest.Create(
                    "https://api.github.com/repos/" + Repo + "/releases/latest");
                req.UserAgent = "Win11Privacy/" + Version;      // GitHub отказывает запросам без подписи
                req.Accept = "application/vnd.github+json";
                req.Timeout = 10000;
                req.ReadWriteTimeout = 10000;
                using (WebResponse resp = req.GetResponse())
                using (Stream s = resp.GetResponseStream())
                using (StreamReader r = new StreamReader(s, Encoding.UTF8))
                {
                    System.Collections.Generic.Dictionary<string, object> d = Json.ParseObject(r.ReadToEnd());
                    string tag = Json.GetStr(d, "tag_name");
                    if (string.IsNullOrEmpty(tag)) { error = L.T("GitHub не ответил номером версии."); return ""; }
                    return tag.Trim();
                }
            }
            catch (WebException wex)
            {
                error = L.T("Не удалось связаться с GitHub: ") + wex.Message;
                return "";
            }
            catch (Exception ex)
            {
                error = ex.Message;
                return "";
            }
        }
    }
}
