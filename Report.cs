using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Text;
using System.Windows.Forms;

namespace Win11Privacy
{
    // Отчёт-доказательство: собирает HTML со всем, что программа узнала.
    public partial class MainForm : Form
    {
        // ================================================================== //
        //  Отчёт-доказательство (HTML)
        // ================================================================== //
        // Самопроверка: показывает, может ли программа реально менять настройки
        private void OnSelfTest(object sender, EventArgs e)
        {
            RunStreaming("-SelfTest", L.T("Самопроверка…"), delegate { });
        }

        private void OnSaveReport(object sender, EventArgs e)
        {
            SaveFileDialog sd = new SaveFileDialog();
            sd.Filter = L.T("HTML-отчёт (*.html)|*.html");
            sd.FileName = "otchet-privatnost-" + DateTime.Now.ToString("yyyy-MM-dd") + ".html";
            if (sd.ShowDialog(this) != DialogResult.OK) return;
            try
            {
                File.WriteAllText(sd.FileName, BuildReportHtml(), new UTF8Encoding(true));
                _status.Text = L.T("Отчёт сохранён: ") + Path.GetFileName(sd.FileName);
                try { Process.Start(sd.FileName); } catch { }
            }
            catch (Exception ex) { MessageBox.Show(this, ex.Message, L.T("Ошибка"), MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }

        private static string Esc(string s)
        {
            if (s == null) return "";
            return s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");
        }

        private string BuildReportHtml()
        {
            StringBuilder h = new StringBuilder();
            h.Append("<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\">");
            h.Append(L.T("<title>Отчёт о приватности Windows 11</title><style>"));
            h.Append("body{font-family:'Segoe UI',system-ui,sans-serif;max-width:900px;margin:40px auto;padding:0 20px;background:#fafafa;color:#1b1b1b;line-height:1.55}");
            h.Append("h1{font-size:28px;margin:0 0 4px}h2{font-size:19px;margin:32px 0 10px;border-bottom:2px solid #e3e3e3;padding-bottom:6px}");
            h.Append(".sub{color:#666;margin-bottom:28px}.grid{display:flex;flex-wrap:wrap;gap:12px;margin:16px 0}");
            h.Append(".tile{flex:1 1 180px;background:#fff;border:1px solid #e3e3e3;border-left:4px solid #0067c0;border-radius:8px;padding:14px 16px}");
            h.Append(".tile .c{font-size:11px;text-transform:uppercase;letter-spacing:.5px;color:#888}");
            h.Append(".tile .v{font-size:26px;font-weight:700;color:#0067c0;margin:4px 0}.tile .s{font-size:13px;color:#666}");
            h.Append("table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #e3e3e3;border-radius:8px;overflow:hidden}");
            h.Append("th,td{text-align:left;padding:9px 14px;border-bottom:1px solid #eee;font-size:14px}th{background:#f4f6f8;font-weight:600}");
            h.Append("tr:last-child td{border-bottom:none}.ok{color:#1e8e3e;font-weight:600}.bad{color:#c42b1c;font-weight:600}");
            h.Append("pre{background:#1f1f1f;color:#ddd;padding:14px;border-radius:8px;overflow-x:auto;font-size:12px;white-space:pre-wrap;word-break:break-all}");
            h.Append(".note{background:#fff8e6;border-left:4px solid #b45309;padding:12px 16px;border-radius:6px;margin:20px 0;font-size:14px}");
            h.Append("footer{margin-top:40px;color:#888;font-size:12px;border-top:1px solid #e3e3e3;padding-top:14px}");
            h.Append("</style></head><body>");
            h.Append(L.T("<h1>Отчёт о приватности Windows 11</h1>"));
            h.Append(L.T("<div class=\"sub\">Составлен ")).Append(DateTime.Now.ToString("dd.MM.yyyy HH:mm"));
            if (_detect != null) h.Append(" · ").Append(Esc(Json.GetStr(_detect, "os"))).Append(L.T(" · сборка ")).Append(Esc(Json.GetStr(_detect, "build")));
            h.Append("</div>");

            // Проверка
            if (_lastAudit != null)
            {
                int ok = Json.GetInt(_lastAudit, "ok"), total = Json.GetInt(_lastAudit, "total");
                h.Append(L.T("<h2>Проверка настроек</h2><div class=\"grid\">"));
                h.Append(L.T("<div class=\"tile\"><div class=\"c\">Индекс приватности</div><div class=\"v\">"))
                 .Append(total > 0 ? (int)Math.Round(100.0 * ok / total) : 0).Append("%</div><div class=\"s\">")
                 .Append(ok).Append(L.T(" из ")).Append(total).Append(L.T(" настроек подтверждено</div></div>"));
                h.Append(L.T("<div class=\"tile\"><div class=\"c\">Не применено</div><div class=\"v\">")).Append(total - ok)
                 .Append(L.T("</div><div class=\"s\">требуют внимания</div></div></div>"));
                h.Append(L.T("<table><tr><th>Раздел</th><th>Применено</th></tr>"));
                foreach (object o in Json.GetArr(_lastAudit, "groups"))
                {
                    Dictionary<string, object> g = Json.Obj(o);
                    int go = Json.GetInt(g, "ok"), gt = Json.GetInt(g, "total");
                    h.Append("<tr><td>").Append(Esc(Json.GetStr(g, "title"))).Append("</td><td class=\"")
                     .Append(go == gt ? "ok" : "bad").Append("\">").Append(go).Append(" / ").Append(gt).Append("</td></tr>");
                }
                h.Append("</table>");
                List<object> dns = Json.GetArr(_lastAudit, "dns");
                if (dns.Count > 0)
                {
                    h.Append(L.T("<h2>Обращения к доменам телеметрии (кэш DNS)</h2><table><tr><th>Домен</th><th>Состояние</th></tr>"));
                    foreach (object o in dns)
                    {
                        Dictionary<string, object> dn = Json.Obj(o);
                        bool bl = Json.GetBool(dn, "blocked");
                        h.Append("<tr><td>").Append(Esc(Json.GetStr(dn, "name"))).Append("</td><td class=\"")
                         .Append(bl ? "ok" : "bad").Append("\">").Append(bl ? L.T("заблокировано") : L.T("проходит")).Append("</td></tr>");
                    }
                    h.Append("</table>");
                }
            }

            // Рентген
            if (_lastXray != null)
            {
                h.Append(L.T("<h2>Рентген телеметрии — что было собрано</h2><div class=\"grid\">"));
                h.Append(L.T("<div class=\"tile\"><div class=\"c\">Событий в сутки</div><div class=\"v\">"))
                 .Append(Json.GetInt(_lastXray, "perDay")).Append("</div><div class=\"s\">")
                 .Append(Esc(Json.GetStr(_lastXray, "mbPerDay"))).Append(L.T(" МБ данных</div></div>"));
                h.Append(L.T("<div class=\"tile\"><div class=\"c\">Прогноз за год</div><div class=\"v\">"))
                 .Append(Esc(FormatBig(Json.GetInt(_lastXray, "perYear")))).Append("</div><div class=\"s\">")
                 .Append(Esc(Json.GetStr(_lastXray, "mbPerYear"))).Append(L.T(" МБ в год</div></div>"));
                if (_lastXray.ContainsKey("baselinePerDay"))
                    h.Append(L.T("<div class=\"tile\"><div class=\"c\">Было до настройки</div><div class=\"v\">"))
                     .Append(Json.GetInt(_lastXray, "baselinePerDay")).Append(L.T("</div><div class=\"s\">событий в сутки</div></div>"));
                h.Append("</div>");
                h.Append(L.T("<table><tr><th>Категория данных</th><th>Событий</th><th>Доля</th><th>Что это</th></tr>"));
                foreach (object o in Json.GetArr(_lastXray, "categories"))
                {
                    Dictionary<string, object> c = Json.Obj(o);
                    h.Append("<tr><td>").Append(Esc(Json.GetStr(c, "name"))).Append("</td><td>").Append(Json.GetInt(c, "count"))
                     .Append("</td><td>").Append(Esc(Json.GetStr(c, "share"))).Append("%</td><td>")
                     .Append(Esc(Json.GetStr(c, "what"))).Append("</td></tr>");
                }
                h.Append("</table>");
                foreach (object o in Json.GetArr(_lastXray, "categories"))
                {
                    Dictionary<string, object> c = Json.Obj(o);
                    Dictionary<string, object> sm = Json.GetObj(c, "sample");
                    if (sm == null) continue;
                    h.Append(L.T("<h2>Пример настоящего события: ")).Append(Esc(Json.GetStr(c, "name"))).Append("</h2>");
                    h.Append("<div class=\"sub\">").Append(Esc(Json.GetStr(sm, "name"))).Append(" · ").Append(Esc(Json.GetStr(sm, "time"))).Append("</div>");
                    h.Append("<pre>").Append(Esc(Json.GetStr(sm, "payload"))).Append("</pre>");
                    break;   // одного примера в отчёте достаточно
                }
            }

            // Что о вас узнали — из тех же событий
            if (_lastXray != null && Json.GetArr(_lastXray, "facts").Count > 0)
            {
                h.Append("<h2>").Append(Esc(L.T("Что о вас узнали — вытащено из самих событий"))).Append("</h2>");
                h.Append("<table><tr><th>").Append(Esc(L.T("Что"))).Append("</th><th>").Append(Esc(L.T("Сколько")))
                 .Append("</th><th>").Append(Esc(L.T("Примеры"))).Append("</th></tr>");
                foreach (object o in Json.GetArr(_lastXray, "facts"))
                {
                    Dictionary<string, object> f = Json.Obj(o);
                    List<object> ex = Json.GetArr(f, "examples");
                    string[] arr = new string[ex.Count];
                    for (int i = 0; i < ex.Count; i++) arr[i] = ex[i] == null ? "" : ex[i].ToString();
                    h.Append("<tr><td>").Append(Esc(L.T(Json.GetStr(f, "title")))).Append("</td><td>")
                     .Append(Json.GetInt(f, "distinct")).Append("</td><td>").Append(Esc(string.Join(", ", arr))).Append("</td></tr>");
                }
                h.Append("</table>");
            }

            // Хронология: что случилось за месяц
            if (_lastTimeline != null && Json.GetArr(_lastTimeline, "notes").Count > 0)
            {
                h.Append("<h2>").Append(Esc(L.T("Хронология приватности"))).Append("</h2>");
                h.Append("<table><tr><th>").Append(Esc(L.T("Дата"))).Append("</th><th>").Append(Esc(L.T("Событие"))).Append("</th></tr>");
                List<object> notes = Json.GetArr(_lastTimeline, "notes");
                for (int i = notes.Count - 1; i >= 0; i--)
                {
                    Dictionary<string, object> n = Json.Obj(notes[i]);
                    string kind = Json.GetStr(n, "kind");
                    string text;
                    if (kind == "update") text = L.T("Обновление Windows: ") + Json.GetStr(n, "list");
                    else if (kind == "drift") text = L.T("Страж нашёл сбитых настроек: ") + Json.GetInt(n, "a") + L.T(", вернул: ") + Json.GetInt(n, "b");
                    else text = L.T("Телеметрия выросла: было ") + Json.GetInt(n, "a") + L.T(" событий в сутки, стало ") + Json.GetInt(n, "b");
                    h.Append("<tr><td>").Append(Esc(Json.GetStr(n, "date"))).Append("</td><td class=\"")
                     .Append(kind == "update" ? "" : "bad").Append("\">").Append(Esc(text)).Append("</td></tr>");
                }
                h.Append("</table>");
            }

            // Монитор
            if (_lastMonitor != null)
            {
                h.Append(L.T("<h2>Монитор исходящих соединений</h2><div class=\"grid\">"));
                h.Append(L.T("<div class=\"tile\"><div class=\"c\">Соединений</div><div class=\"v\">"))
                 .Append(Json.GetInt(_lastMonitor, "total")).Append(L.T("</div><div class=\"s\">за 24 часа</div></div>"));
                h.Append(L.T("<div class=\"tile\"><div class=\"c\">К телеметрии</div><div class=\"v\">"))
                 .Append(Json.GetInt(_lastMonitor, "telemetryHits")).Append(L.T("</div><div class=\"s\">распознано по домену</div></div></div>"));
            }

            // Результат: до и после
            if (_lastProof != null && Json.GetObj(_lastProof, "before") != null)
            {
                Dictionary<string, object> pb = Json.GetObj(_lastProof, "before");
                Dictionary<string, object> pa = Json.GetObj(_lastProof, "after");
                h.Append("<h2>").Append(Esc(L.T("Результат: что было до программы и что стало"))).Append("</h2>");
                h.Append("<table><tr><th>").Append(Esc(L.T("Показатель"))).Append("</th><th>")
                 .Append(Esc(L.T("Было"))).Append("</th><th>").Append(Esc(L.T("Стало"))).Append("</th></tr>");
                string[,] rows = {
                    { L.T("Настроек приватности на месте"), "ok" },
                    { L.T("Сборщиков трассировки выключено"), "etwOff" },
                    { L.T("Задач телеметрии ещё работает"), "tasksLive" },
                    { L.T("Доменов телеметрии не отвечает"), "dnsBlocked" },
                    { L.T("Правил брандмауэра против телеметрии"), "fwRules" },
                    { L.T("Программ стартует вместе с Windows"), "startupOn" }
                };
                for (int i = 0; i < rows.GetLength(0); i++)
                    h.Append("<tr><td>").Append(Esc(rows[i, 0])).Append("</td><td>")
                     .Append(Json.GetInt(pb, rows[i, 1])).Append("</td><td>")
                     .Append(Json.GetInt(pa, rows[i, 1])).Append("</td></tr>");
                int xb2 = Json.GetInt(pb, "xrayPerDay"), xa2 = Json.GetInt(_lastProof, "xrayNow");
                if (xb2 > 0 && xa2 > 0)
                    h.Append("<tr><td>").Append(Esc(L.T("Событий телеметрии в сутки"))).Append("</td><td>")
                     .Append(xb2).Append("</td><td>").Append(xa2).Append("</td></tr>");
                h.Append("</table>");
                h.Append("<div class=\"sub\">").Append(Esc(L.T("Снимок «до» сделан "))).Append(Esc(Json.GetStr(pb, "time")))
                 .Append(Esc(L.T(", текущее состояние — "))).Append(Esc(Json.GetStr(pa, "time"))).Append("</div>");
            }

            // Автозапуск
            if (_lastStartup != null)
            {
                h.Append(L.T("<h2>Автозапуск: что стартует вместе с Windows</h2><div class=\"grid\">"));
                h.Append(L.T("<div class=\"tile\"><div class=\"c\">Записей всего</div><div class=\"v\">"))
                 .Append(Json.GetInt(_lastStartup, "total")).Append(L.T("</div><div class=\"s\">в реестре, папках и планировщике</div></div>"));
                h.Append(L.T("<div class=\"tile\"><div class=\"c\">Запускается</div><div class=\"v\">"))
                 .Append(Json.GetInt(_lastStartup, "on")).Append(L.T("</div><div class=\"s\">из них лишних: "))
                 .Append(Json.GetInt(_lastStartup, "advise")).Append("</div></div></div>");
                h.Append(L.T("<table><tr><th>Программа</th><th>Что это</th><th>Откуда</th><th>Состояние</th></tr>"));
                foreach (object o in Json.GetArr(_lastStartup, "items"))
                {
                    Dictionary<string, object> it = Json.Obj(o);
                    bool on = Json.GetBool(it, "enabled");
                    h.Append("<tr><td>").Append(Esc(Json.GetStr(it, "name"))).Append("</td><td>")
                     .Append(Esc(L.T(Json.GetStr(it, "note")))).Append("</td><td>")
                     .Append(Esc(L.T(Json.GetStr(it, "source")))).Append("</td><td class=\"")
                     .Append(on ? (Json.GetBool(it, "advise") ? "bad" : "") : "ok").Append("\">")
                     .Append(on ? L.T("запускается") : L.T("отключено")).Append("</td></tr>");
                }
                h.Append("</table>");
            }

            // Предустановленные приложения
            if (_lastApps != null)
            {
                List<object> appItems = Json.GetArr(_lastApps, "apps");
                int bloatCount = 0;
                foreach (object o in appItems) if (Json.GetBool(Json.Obj(o), "bloat")) bloatCount++;
                h.Append(L.T("<h2>Предустановленные приложения</h2>"));
                h.Append("<div class=\"sub\">").Append(Esc(L.T("Найдено приложений: "))).Append(appItems.Count)
                 .Append(Esc(L.T(", из них лишних: "))).Append(bloatCount).Append("</div>");
                if (bloatCount > 0)
                {
                    h.Append(L.T("<table><tr><th>Приложение</th><th>Идентификатор</th></tr>"));
                    foreach (object o in appItems)
                    {
                        Dictionary<string, object> a = Json.Obj(o);
                        if (!Json.GetBool(a, "bloat")) continue;
                        h.Append("<tr><td>").Append(Esc(L.T(Json.GetStr(a, "title")))).Append("</td><td>")
                         .Append(Esc(Json.GetStr(a, "name"))).Append("</td></tr>");
                    }
                    h.Append("</table>");
                }
            }

            // Досье
            if (_lastSpy != null)
            {
                h.Append(L.T("<h2>Досье: кто включал камеру, микрофон и геолокацию</h2>"));
                h.Append(L.T("<table><tr><th>Программа</th><th>Датчик</th><th>Когда</th><th>Длительность</th></tr>"));
                foreach (object co in Json.GetArr(_lastSpy, "caps"))
                {
                    Dictionary<string, object> c = Json.Obj(co);
                    string capTitle = Json.GetStr(c, "title");
                    int n = 0;
                    foreach (object io in Json.GetArr(c, "items"))
                    {
                        if (n++ >= 8) break;
                        Dictionary<string, object> it = Json.Obj(io);
                        double mins = 0;
                        object mv = Json.Get(it, "minutes");
                        if (mv != null) double.TryParse(mv.ToString().Replace(',', '.'), NumberStyles.Any, CultureInfo.InvariantCulture, out mins);
                        h.Append("<tr><td>").Append(Esc(Json.GetStr(it, "app"))).Append("</td><td>").Append(Esc(capTitle))
                         .Append("</td><td>").Append(Esc(Json.GetStr(it, "last"))).Append("</td><td>")
                         .Append(Json.GetBool(it, "active") ? L.T("<span class=\"bad\">прямо сейчас</span>") : Esc(Dur(mins)))
                         .Append("</td></tr>");
                    }
                }
                h.Append("</table>");
            }
            if (_lastFoot != null)
            {
                h.Append(L.T("<h2>Цифровой след на диске</h2>"));
                h.Append(L.T("<table><tr><th>Что хранится</th><th>Сколько</th></tr>"));
                foreach (object o in Json.GetArr(_lastFoot, "items"))
                {
                    Dictionary<string, object> it = Json.Obj(o);
                    h.Append("<tr><td>").Append(Esc(Json.GetStr(it, "title"))).Append("</td><td>")
                     .Append(Esc(Json.GetStr(it, "value"))).Append("</td></tr>");
                }
                h.Append("</table>");
            }

            h.Append(L.T("<div class=\"note\"><b>Честно о пределах.</b> Полностью прекратить обмен данными с Microsoft "));
            h.Append(L.T("на Windows нельзя: остаются проверка обновлений, активация лицензии и проверка сертификатов. "));
            h.Append(L.T("На редакциях Home и Pro минимальный уровень телеметрии система трактует как «Обязательные данные» — "));
            h.Append(L.T("это ограничение редакции, а не программы.</div>"));
            h.Append(L.T("<footer>Отчёт сформирован программой «Приватность Windows 11». "));
            h.Append(L.T("Данные получены из реестра, служб, планировщика, кэша DNS, журнала брандмауэра "));
            h.Append(L.T("и встроенного механизма диагностики Windows.</footer></body></html>"));
            return h.ToString();
        }

        private static string FormatBig(int n)
        {
            if (n >= 1000000) return (n / 1000000.0).ToString("0.#") + L.T(" млн");
            if (n >= 1000) return (n / 1000.0).ToString("0.#") + L.T(" тыс");
            return n.ToString();
        }
    }
}
