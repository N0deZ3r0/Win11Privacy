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
    // Страница «Рентген»: что Windows собрала об этом компьютере.
    public partial class MainForm : Form
    {
        // ================================================================== //
        //  Страница: Рентген телеметрии
        // ================================================================== //
        private Control BuildXrayPage()
        {
            int u = Font.Height;
            TableLayoutPanel page = new TableLayoutPanel();
            page.ColumnCount = 1; page.RowCount = 4;
            page.BackColor = Theme.WindowBg;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

            TableLayoutPanel head = new TableLayoutPanel();
            head.ColumnCount = 2; head.Dock = DockStyle.Fill; head.AutoSize = true;
            head.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            head.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            page.RowStyles[1] = new RowStyle(SizeType.Absolute, (int)(u * 7.6F));
            head.Controls.Add(PageTitle(L.T("Рентген телеметрии")), 0, 0);
            _btnReport = new ModernButton(L.T("Сохранить отчёт"), false);
            _btnReport.Font = Font; _btnReport.Anchor = AnchorStyles.Right | AnchorStyles.Bottom;
            _btnReport.Click += OnSaveReport;
            head.Controls.Add(_btnReport, 1, 0);
            page.Controls.Add(head, 0, 0);

            // панель управления
            Card ctl = new Card();
            ctl.Dock = DockStyle.Fill;
            ctl.Margin = new Padding(0, (int)(u * 0.5F), 0, (int)(u * 0.5F));
            ctl.Padding = new Padding((int)(u * 0.9F), (int)(u * 0.7F), (int)(u * 0.9F), (int)(u * 0.7F));
            TableLayoutPanel ci = new TableLayoutPanel();
            ci.Dock = DockStyle.Fill; ci.AutoSize = true; ci.ColumnCount = 1; ci.RowCount = 2;
            ci.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            ci.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            ci.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            _xrayState = new Label();
            _xrayState.AutoSize = false; _xrayState.Dock = DockStyle.Fill;
            _xrayState.TextAlign = ContentAlignment.MiddleLeft; _xrayState.ForeColor = Theme.TextDim;
            _xrayState.Text = L.T("Показывает НАСТОЯЩИЕ события, которые Windows собрала об этом компьютере,\n") +
                              L.T("с расшифровкой и сырым содержимым. Включите запись, дайте системе поработать\n") +
                              L.T("хотя бы час — и нажмите «Сканировать».");
            ci.Controls.Add(_xrayState, 0, 0);
            FlowLayoutPanel xb = new FlowLayoutPanel();
            AttachButtonRow(xb, ctl);
            xb.Margin = new Padding(0, (int)(u * 0.5F), 0, 0);
            _btnXrayRec  = new ModernButton(L.T("Включить запись"), true);
            _btnXrayRec.Click += OnXrayToggleRecording;
            _btnXrayScan = new ModernButton(L.T("Сканировать"), false); _btnXrayScan.Click += delegate { RunXrayScan(false); };
            _btnXrayBase = new ModernButton(L.T("Запомнить как «до»"), false); _btnXrayBase.Click += delegate { RunXrayScan(true); };
            _btnXrayWipe = new ModernButton(L.T("Стереть копию"), false); _btnXrayWipe.Click += OnXrayWipe;
            foreach (ModernButton b in new[] { _btnXrayRec, _btnXrayScan, _btnXrayBase, _btnXrayWipe })
            { b.Font = b.Primary ? new Font(Font, FontStyle.Bold) : Font; b.Margin = new Padding((int)(u * 0.4F), 0, 0, (int)(u * 0.3F)); xb.Controls.Add(b); }
            ci.Controls.Add(xb, 0, 1);
            ctl.Controls.Add(ci);
            page.Controls.Add(ctl, 0, 1);

            _xrayTiles = new TileGrid();
            _xrayTiles.Dock = DockStyle.Fill; _xrayTiles.AutoSize = true; _xrayTiles.Font = Font;
            _xrayTiles.Margin = new Padding(0, 0, 0, (int)(u * 0.4F));
            page.Controls.Add(_xrayTiles, 0, 2);

            Card list = new Card();
            list.Dock = DockStyle.Fill; list.Padding = new Padding((int)(u * 0.6F));
            list.Margin = new Padding(0, 0, 0, (int)(u * 0.3F));
            _xrayList = new StackPanel();
            _xrayList.Dock = DockStyle.Fill; _xrayList.Font = Font;
            _xrayList.Padding = new Padding((int)(u * 0.4F));
            Dwm.DarkScrollbars(_xrayList);
            list.Controls.Add(_xrayList);
            page.Controls.Add(list, 0, 3);
            return page;
        }

        private void OnXrayToggleRecording(object sender, EventArgs e)
        {
            if (_xrayRecording)
            { RunStreaming("-XrayDisable", L.T("Выключение записи…"), delegate { RunXrayStatus(); }); return; }
            if (MessageBox.Show(this,
                L.T("Windows начнёт вести ЛОКАЛЬНУЮ копию своих диагностических событий,\n") +
                L.T("чтобы их можно было прочитать и показать вам.\n\n") +
                L.T("Объём отправляемых данных при этом НЕ увеличивается — меняется только\n") +
                L.T("то, что копия сохраняется на диске. Стереть её можно кнопкой «Стереть копию».\n\n") +
                L.T("Продолжить?"), L.T("Включить запись"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            RunStreaming("-XrayEnable", L.T("Включение записи…"), delegate { RunXrayStatus(); });
        }

        private void OnXrayWipe(object sender, EventArgs e)
        {
            if (MessageBox.Show(this, L.T("Локальная копия собранных событий будет удалена.\nПродолжить?"),
                L.T("Стереть копию"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            RunStreaming("-XrayWipe", L.T("Стирание копии…"), delegate { RunXrayStatus(); });
        }

        private void RunXrayStatus()
        {
            RunJson("-XrayStatus", L.T("Проверка рентгена…"), delegate(Dictionary<string, object> d)
            {
                if (d == null) return;
                _xrayRecording = Json.GetBool(d, "recording");
                bool mod = Json.GetBool(d, "moduleAvailable");
                Dictionary<string, object> db = Json.GetObj(d, "db");
                _btnXrayRec.Text = _xrayRecording ? L.T("Выключить запись") : L.T("Включить запись");
                _btnXrayRec.Primary = !_xrayRecording; _btnXrayRec.Invalidate();
                _btnXrayScan.Enabled = _xrayRecording;
                string s = _xrayRecording
                    ? L.T("Запись включена. Windows ведёт локальную копию событий — можно сканировать.")
                    : L.T("Запись выключена. Пока она выключена, прочитать собранные данные нельзя.");
                if (!mod) s = L.T("На этой системе нет модуля Microsoft.DiagnosticDataViewer — рентген недоступен.");
                if (db != null && Json.GetStr(db, "mb") != "0") s += L.T("\nЛокальная копия на диске: ") + Json.GetStr(db, "mb") + L.T(" МБ.");
                Dictionary<string, object> b = Json.GetObj(d, "baseline");
                if (b != null) s += L.T("\nЭталон «до» сохранён: ") + Json.GetStr(b, "time") + " (" + Json.GetStr(b, "perDay") + L.T(" событий в сутки).");
                _xrayState.Text = s;
                foreach (NavItem n in _nav) if ((string)n.Tag == "xray") { n.Badge = _xrayRecording ? "rec" : ""; n.Invalidate(); }
            });
        }

        private void RunXrayScan(bool asBaseline)
        {
            string extra = "-XrayScan -XrayHours 24" + (asBaseline ? " -XrayBaseline" : "");
            RunJson(extra, asBaseline ? L.T("Замер «до»…") : L.T("Чтение собранных данных…"), delegate(Dictionary<string, object> d)
            {
                if (d == null) { _xrayState.Text = L.T("Не удалось получить данные."); return; }
                string err = Json.GetStr(d, "error");
                if (err.Length > 0)
                {
                    _xrayList.Controls.Clear();
                    SectionHeader sh = new SectionHeader(err); sh.Font = Font; _xrayList.Controls.Add(sh);
                    try { _xrayList.AutoScrollPosition = Point.Empty; } catch { }
            _xrayList.Restack(); _xrayState.Text = err; return;
                }
                _lastXray = d;
                RenderXray(d);
                RefreshHome();
                if (asBaseline) _xrayState.Text = L.T("Замер сохранён как «до». Примените настройки и просканируйте снова — покажу разницу.");
            });
        }

        private void RenderXray(Dictionary<string, object> d)
        {
            int total = Json.GetInt(d, "total");
            int perDay = Json.GetInt(d, "perDay");
            _xrayTiles.Controls.Clear();
            _xrayTiles.Controls.Add(Tile(L.T("Событий собрано"), total.ToString(), L.T("за последние ") + Json.GetInt(d, "hours") + L.T(" ч"), Theme.Accent));
            _xrayTiles.Controls.Add(Tile(L.T("В сутки"), perDay.ToString(), Json.GetStr(d, "mbPerDay") + L.T(" МБ данных о вас"), Theme.Warn));
            _xrayTiles.Controls.Add(Tile(L.T("Прогноз за год"), FormatBig(Json.GetInt(d, "perYear")), Json.GetStr(d, "mbPerYear") + L.T(" МБ в год"), Theme.Err));

            if (d.ContainsKey("baselinePerDay"))
            {
                int bp = Json.GetInt(d, "baselinePerDay");
                double delta = 0;
                object dp = Json.Get(d, "deltaPercent");
                if (dp != null) double.TryParse(dp.ToString().Replace(',', '.'), System.Globalization.NumberStyles.Any,
                    System.Globalization.CultureInfo.InvariantCulture, out delta);
                bool better = perDay < bp;
                _xrayTiles.Controls.Add(Tile(better ? L.T("Стало меньше на") : L.T("Изменение"),
                    (better ? "" : "+") + Math.Abs(delta).ToString("0.#") + "%",
                    L.T("было ") + bp + L.T(" → стало ") + perDay + L.T(" в сутки"), better ? Theme.Ok : Theme.Err));
            }
            else
            {
                _xrayTiles.Controls.Add(Tile(L.T("Уникальных событий"), Json.GetInt(d, "distinctNames").ToString(),
                    L.T("разных типов данных"), Theme.Accent));
            }

            _xrayList.Controls.Clear();

            // Самое ценное — не количество событий, а что из них следует.
            List<object> facts = Json.GetArr(d, "facts");
            if (facts.Count > 0)
            {
                SectionHeader s0 = new SectionHeader(L.T("Что о вас узнали — вытащено из самих событий"));
                s0.Font = Font; _xrayList.Controls.Add(s0);
                foreach (object o in facts)
                {
                    Dictionary<string, object> f = Json.Obj(o);
                    List<object> ex = Json.GetArr(f, "examples");
                    string[] arr = new string[ex.Count];
                    for (int i = 0; i < ex.Count; i++) arr[i] = ex[i] == null ? "" : ex[i].ToString();
                    string sample = string.Join(", ", arr);
                    if (sample.Length > 160) sample = sample.Substring(0, 157) + "…";
                    WipeRow r = new WipeRow("fact_" + Json.GetStr(f, "id"),
                        L.T(Json.GetStr(f, "title")) + "   ·   " + Json.GetInt(f, "distinct") + L.T(" шт."),
                        L.T(Json.GetStr(f, "what")) + "\n" + sample,
                        "", GEye, false);
                    r.Font = Font;
                    _xrayList.Controls.Add(r);
                }
            }

            SectionHeader s1 = new SectionHeader(L.T("Что именно собрано — нажмите, чтобы увидеть сырое событие"));
            s1.Font = Font; _xrayList.Controls.Add(s1);
            foreach (object o in Json.GetArr(d, "categories"))
            {
                Dictionary<string, object> c = Json.Obj(o);
                Dictionary<string, object> sm = Json.GetObj(c, "sample");
                double share = 0;
                object sh = Json.Get(c, "share");
                if (sh != null) double.TryParse(sh.ToString().Replace(',', '.'), System.Globalization.NumberStyles.Any,
                    System.Globalization.CultureInfo.InvariantCulture, out share);
                XrayCatRow row = new XrayCatRow(
                    L.T(Json.GetStr(c, "name")), Json.GetInt(c, "count"), share, Json.GetStr(c, "what"),
                    Json.GetArr(c, "topNames"),
                    sm != null ? Json.GetStr(sm, "name") : "",
                    sm != null ? Json.GetStr(sm, "time") : "",
                    sm != null ? Json.GetStr(sm, "payload") : "");
                row.Font = Font;
                _xrayList.Controls.Add(row);
            }

            List<object> ids = Json.GetArr(d, "identifiers");
            if (ids.Count > 0)
            {
                SectionHeader s2 = new SectionHeader(L.T("Метки, которыми помечены события (по ним вас узнают)"));
                s2.Font = Font; _xrayList.Controls.Add(s2);
                foreach (object o in ids)
                {
                    Dictionary<string, object> i = Json.Obj(o);
                    List<object> vals = Json.GetArr(i, "values");
                    string v = vals.Count > 0 ? Json.GetStr(Json.Obj(vals[0]), "value") : "";
                    _xrayList.Controls.Add(new KvRow(Json.GetStr(i, "key") + "  →  " + v,
                        Json.GetInt(i, "distinct") + L.T(" знач."), true) { Font = this.Font });
                }
            }

            List<object> apps = Json.GetArr(d, "apps");
            if (apps.Count > 0)
            {
                SectionHeader s3 = new SectionHeader(L.T("Программы, попавшие в отчёты о вас"));
                s3.Font = Font; _xrayList.Controls.Add(s3);
                foreach (object o in apps)
                {
                    Dictionary<string, object> a = Json.Obj(o);
                    _xrayList.Controls.Add(new KvRow(Json.GetStr(a, "name"), Json.GetInt(a, "count") + "×", false) { Font = this.Font });
                }
            }
            _xrayList.Restack();
            _xrayState.Text = L.T("Прочитано ") + total + L.T(" событий за ") + Json.GetInt(d, "hours") + L.T(" ч. ") +
                              L.T("Нажмите на категорию — покажу настоящий JSON, который ушёл в Microsoft.");
        }
    }
}
